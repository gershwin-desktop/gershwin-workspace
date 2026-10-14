/*
 * GWThumbnailStore.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWThumbnailStore.h"
#import "GWThumbnailPNG.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

/* Our own entries carry their tEXt chunks ahead of IDAT, well inside this,
 * so the sweep reads only the head of each file. */
#define GW_THUMBNAIL_SWEEP_HEAD 4096

BOOL
GWThumbnailStampForPath(NSString *path, GWThumbnailFileStamp *stamp)
{
  const char *p = [path fileSystemRepresentation];
  struct stat st;

  if (stat(p, &st) != 0 || S_ISREG(st.st_mode) == 0 || access(p, R_OK) != 0)
    {
      return NO;
    }
  stamp->mtime = (long long)st.st_mtime;
  stamp->size = (long long)st.st_size;
  return YES;
}

static BOOL
EnsureDirectory(NSString *path)
{
  const char *p = [path fileSystemRepresentation];
  struct stat st;

  if (stat(p, &st) == 0)
    {
      return S_ISDIR(st.st_mode) ? YES : NO;
    }
  if (errno != ENOENT)
    {
      return NO;
    }
  if (EnsureDirectory([path stringByDeletingLastPathComponent]) == NO)
    {
      return NO;
    }
  /* The standard wants every cache directory private to the user: the
   * thumbnails show what the user's files contain. */
  return (mkdir(p, 0700) == 0 || errno == EEXIST) ? YES : NO;
}

static NSData *
ReadHead(NSString *path, NSUInteger limit)
{
  int fd = open([path fileSystemRepresentation], O_RDONLY);
  NSMutableData *data;
  ssize_t n;

  if (fd < 0)
    {
      return nil;
    }
  data = [NSMutableData dataWithLength: limit];
  n = read(fd, [data mutableBytes], limit);
  close(fd);
  if (n < 0)
    {
      return nil;
    }
  [data setLength: (NSUInteger)n];
  return data;
}

@implementation GWThumbnailStore

+ (NSString *)defaultDirectory
{
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *home = [env objectForKey: @"HOME"];

  /* $HOME first, as the base directory spec says; the password database
   * only for a process started without one. */
  if ([home isAbsolutePath] == NO)
    {
      home = NSHomeDirectory();
    }
  return GWThumbnailCacheDirectory([env objectForKey: @"XDG_CACHE_HOME"], home);
}

- (id)initWithDirectory:(NSString *)aDirectory
               software:(NSString *)aSoftware
               mimeType:(NSString *)aMimeType
                program:(NSString *)aProgram
                version:(NSString *)aVersion
{
  self = [super init];
  if (self != nil)
    {
      directory = [[aDirectory stringByStandardizingPath] copy];
      software = [aSoftware copy];
      mimeType = [aMimeType copy];
      program = [aProgram copy];
      failureDirectory = [[[directory stringByAppendingPathComponent: @"fail"]
        stringByAppendingPathComponent:
          GWThumbnailFailureDirectoryName(aProgram, aVersion)] copy];
    }
  return self;
}

- (void)dealloc
{
  [directory release];
  [software release];
  [mimeType release];
  [program release];
  [failureDirectory release];
  [super dealloc];
}

- (NSString *)directory
{
  return directory;
}

- (BOOL)containsPath:(NSString *)path
{
  NSString *prefix = [directory stringByAppendingString: @"/"];

  return [path isEqualToString: directory] || [path hasPrefix: prefix];
}

- (NSString *)entryForPath:(NSString *)path inDirectory:(NSString *)dir
{
  return [dir stringByAppendingPathComponent:
    GWThumbnailFileNameForURI(GWThumbnailURIForPath(path))];
}

- (NSString *)sizeDirectoryForPixels:(NSUInteger)pixels
{
  return [directory stringByAppendingPathComponent:
    GWThumbnailSizeDirectoryForPixels(pixels)];
}

- (NSDictionary *)textForPath:(NSString *)path stamp:(GWThumbnailFileStamp)stamp
{
  NSMutableDictionary *text = [NSMutableDictionary dictionary];

  [text setObject: GWThumbnailURIForPath(path) forKey: GWThumbnailKeyURI];
  [text setObject: [NSString stringWithFormat: @"%lld", stamp.mtime]
           forKey: GWThumbnailKeyMTime];
  [text setObject: [NSString stringWithFormat: @"%lld", stamp.size]
           forKey: GWThumbnailKeySize];
  [text setObject: mimeType forKey: GWThumbnailKeyMimetype];
  [text setObject: software forKey: GWThumbnailKeySoftware];
  return text;
}

- (NSData *)validEntry:(NSString *)entry
               forPath:(NSString *)path
                 stamp:(GWThumbnailFileStamp)stamp
{
  NSData *png = [NSData dataWithContentsOfFile: entry];

  if (png == nil
      || GWThumbnailMatchesFile(GWThumbnailTextChunksInPNG(png),
                                GWThumbnailURIForPath(path), stamp) == NO)
    {
      return nil;
    }
  return png;
}

- (NSData *)thumbnailForPath:(NSString *)path
                       stamp:(GWThumbnailFileStamp)stamp
                      pixels:(NSUInteger)pixels
{
  return [self validEntry: [self entryForPath: path
                                  inDirectory: [self sizeDirectoryForPixels: pixels]]
                  forPath: path
                    stamp: stamp];
}

- (BOOL)hasFailureForPath:(NSString *)path
                    stamp:(GWThumbnailFileStamp)stamp
{
  return [self validEntry: [self entryForPath: path inDirectory: failureDirectory]
                  forPath: path
                    stamp: stamp] != nil;
}

/* The standard's concurrent-writer procedure: write a temporary file in
 * the target directory, then rename it over the entry, so a reader sees
 * either the old entry or the complete new one. mkstemp makes the file
 * 0600 and keeps two threads of this process apart. */
- (BOOL)writePNG:(NSData *)png toEntry:(NSString *)entry
{
  NSString *dir = [entry stringByDeletingLastPathComponent];
  NSString *template = [entry stringByAppendingFormat: @".%@-XXXXXX", program];
  const char *bytes = [png bytes];
  NSUInteger left = [png length];
  BOOL ok = YES;
  char *tmp;
  int fd;

  if (EnsureDirectory(dir) == NO)
    {
      NSLog(@"GWThumbnailStore: cannot create %@: %s", dir, strerror(errno));
      return NO;
    }

  tmp = strdup([template fileSystemRepresentation]);
  if (tmp == NULL)
    {
      return NO;
    }
  fd = mkstemp(tmp);
  if (fd < 0)
    {
      NSLog(@"GWThumbnailStore: cannot write in %@: %s", dir, strerror(errno));
      free(tmp);
      return NO;
    }
  while (ok && left > 0)
    {
      ssize_t n = write(fd, bytes, left);

      if (n < 0 && errno == EINTR)
        {
          continue;
        }
      ok = (n > 0);
      if (ok)
        {
          bytes += n;
          left -= (NSUInteger)n;
        }
    }
  if (close(fd) != 0)
    {
      ok = NO;
    }
  if (ok && rename(tmp, [entry fileSystemRepresentation]) != 0)
    {
      ok = NO;
    }
  if (ok == NO)
    {
      NSLog(@"GWThumbnailStore: cannot write %@: %s", entry, strerror(errno));
      unlink(tmp);
    }
  free(tmp);
  return ok;
}

- (NSData *)storeIconData:(NSData *)icon
                  forPath:(NSString *)path
                    stamp:(GWThumbnailFileStamp)stamp
                   pixels:(NSUInteger)pixels
{
  NSString *sizeDir = [self sizeDirectoryForPixels: pixels];
  NSUInteger box = GWThumbnailPixelsForSizeDirectory([sizeDir lastPathComponent]);
  NSUInteger w = 0, h = 0, tw = 0, th = 0;
  NSData *rgba = GWThumbnailPNGDecodeRGBA(icon, GW_THUMBNAIL_MAX_DECODE_SIDE, &w, &h);
  NSData *png;

  if (rgba == nil)
    {
      return nil;
    }
  GWThumbnailFitSize(w, h, box, &tw, &th);
  if (tw != w || th != h)
    {
      rgba = GWThumbnailDownscaleRGBA(rgba, w, h, tw, th);
    }
  png = GWThumbnailPNGEncodeRGBA(rgba, tw, th, [self textForPath: path stamp: stamp]);
  if (png != nil)
    {
      [self writePNG: png toEntry: [self entryForPath: path inDirectory: sizeDir]];
    }
  return png;
}

- (BOOL)storeFailureForPath:(NSString *)path
                      stamp:(GWThumbnailFileStamp)stamp
{
  /* The standard asks for an "empty" PNG; one transparent pixel is the
   * smallest image every reader accepts. */
  NSData *pixel = [NSMutableData dataWithLength: 4];
  NSData *png = GWThumbnailPNGEncodeRGBA(pixel, 1, 1,
                                         [self textForPath: path stamp: stamp]);

  return png != nil
    && [self writePNG: png toEntry: [self entryForPath: path
                                           inDirectory: failureDirectory]];
}

- (BOOL)removeEntryIfStale:(NSString *)entry now:(time_t)now
{
  const char *e = [entry fileSystemRepresentation];
  NSDictionary *text;
  NSString *original;
  GWThumbnailOriginalState state;
  struct stat est, ost, pst;

  if (lstat(e, &est) != 0 || S_ISREG(est.st_mode) == 0)
    {
      return NO;
    }
  text = GWThumbnailTextChunksInPNG(ReadHead(entry, GW_THUMBNAIL_SWEEP_HEAD));
  original = GWThumbnailPathForURI([text objectForKey: GWThumbnailKeyURI]);
  if (original == nil)
    {
      return NO;
    }

  memset(&state, 0, sizeof(state));
  state.exists = (stat([original fileSystemRepresentation], &ost) == 0);
  if (state.exists)
    {
      state.stamp.mtime = (long long)ost.st_mtime;
      state.stamp.size = (long long)ost.st_size;
    }
  state.parentExists =
    (stat([[original stringByDeletingLastPathComponent] fileSystemRepresentation],
          &pst) == 0 && S_ISDIR(pst.st_mode));

  if (GWThumbnailIsStale(text, software, state,
                         (NSTimeInterval)(now - est.st_mtime)) == NO)
    {
      return NO;
    }
  return unlink(e) == 0;
}

/* Every directory that can hold entries of ours: the size directories and
 * our fail/ directories, those of earlier versions included, since nobody
 * else would ever clean those up. */
- (NSArray *)ownDirectories
{
  NSMutableArray *dirs = [NSMutableArray array];
  NSString *failRoot = [directory stringByAppendingPathComponent: @"fail"];
  NSString *prefix = [program stringByAppendingString: @"-"];
  NSEnumerator *e = [GWThumbnailSizeDirectories() objectEnumerator];
  NSString *name;
  DIR *d;
  struct dirent *de;

  while ((name = [e nextObject]) != nil)
    {
      [dirs addObject: [directory stringByAppendingPathComponent: name]];
    }
  d = opendir([failRoot fileSystemRepresentation]);
  if (d != NULL)
    {
      while ((de = readdir(d)) != NULL)
        {
          name = [NSString stringWithUTF8String: de->d_name];
          if ([name hasPrefix: prefix])
            {
              [dirs addObject: [failRoot stringByAppendingPathComponent: name]];
            }
        }
      closedir(d);
    }
  return dirs;
}

- (NSUInteger)removeStaleEntries
{
  NSEnumerator *e = [[self ownDirectories] objectEnumerator];
  time_t now = time(NULL);
  NSUInteger removed = 0;
  NSString *dir;

  while ((dir = [e nextObject]) != nil)
    {
      DIR *d = opendir([dir fileSystemRepresentation]);
      struct dirent *de;

      if (d == NULL)
        {
          continue;
        }
      while ((de = readdir(d)) != NULL)
        {
          CREATE_AUTORELEASE_POOL(pool);

          /* Entries are always 32 hex digits plus .png; anything else
           * (a writer's temporary file, foreign junk) is not ours to judge. */
          if (strlen(de->d_name) == 36 && strcmp(de->d_name + 32, ".png") == 0)
            {
              NSString *entry = [dir stringByAppendingPathComponent:
                [NSString stringWithUTF8String: de->d_name]];

              if ([self removeEntryIfStale: entry now: now])
                {
                  removed++;
                }
            }
          RELEASE(pool);
        }
      closedir(d);
    }
  return removed;
}

- (NSUInteger)removeStaleEntriesForPath:(NSString *)path
{
  NSEnumerator *e = [[self ownDirectories] objectEnumerator];
  time_t now = time(NULL);
  NSUInteger removed = 0;
  NSString *dir;

  if (GWThumbnailURIForPath(path) == nil)
    {
      return 0;
    }
  while ((dir = [e nextObject]) != nil)
    {
      if ([self removeEntryIfStale: [self entryForPath: path inDirectory: dir]
                               now: now])
        {
          removed++;
        }
    }
  return removed;
}

@end
