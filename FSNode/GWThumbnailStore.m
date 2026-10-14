/*
 * GWThumbnailStore.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GWThumbnailStore.h"
#import "GWThumbnailImage.h"
#import "GWThumbnailPNG.h"
#import "GWWorkerPool.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#else
#include <sys/file.h>
#endif
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

NSString * const GWThumbnailsDidChangeNotification = @"GWThumbnailsDidChangeNotification";

/* The Software text chunk of every stored PNG. */
static NSString * const GWThumbnailSoftware = @"Gershwin Workspace";

static NSString * const GWThumbnailIndexName = @"thumbnails.plist";
static NSString * const GWThumbnailLockName = @".thumbnails.lock";
static const char GWThumbnailTempPrefix[] = "tmp-";

/* Text chunks are written ahead of IDAT, well inside this, so scans read
 * only the head of each file. */
#define GW_THUMBNAIL_HEAD 4096

/* A file this young may belong to a store whose index update is still on
 * its way; cleanups leave it alone. */
#define GW_THUMBNAIL_IN_FLIGHT 60

/* Index changes wait this long for each other before they are written. */
#define GW_THUMBNAIL_FLUSH_DELAY 1.0

BOOL
GWThumbnailStampForPath(NSString *path, GWThumbnailFileStamp *stamp)
{
  const char *p = [path fileSystemRepresentation];
  struct stat st;

  if (p == NULL || stat(p, &st) != 0 || S_ISREG(st.st_mode) == 0
      || access(p, R_OK) != 0)
    {
      return NO;
    }
  stamp->mtime = (long long)st.st_mtime;
  stamp->size = (long long)st.st_size;
  stamp->ctime = (long long)st.st_ctime;
  return YES;
}

static GWThumbnailSourceState
SourceState(NSString *source)
{
  GWThumbnailSourceState state;
  struct stat st;

  memset(&state, 0, sizeof(state));
  if (stat([source fileSystemRepresentation], &st) == 0)
    {
      state.exists = YES;
      state.stamp.mtime = (long long)st.st_mtime;
      state.stamp.size = (long long)st.st_size;
      state.stamp.ctime = (long long)st.st_ctime;
    }
  state.parentExists =
    (stat([[source stringByDeletingLastPathComponent] fileSystemRepresentation],
          &st) == 0 && S_ISDIR(st.st_mode));
  return state;
}

static NSData *
ReadHead(NSString *path)
{
  int fd = open([path fileSystemRepresentation], O_RDONLY);
  NSMutableData *data;
  ssize_t n;

  if (fd < 0)
    {
      return nil;
    }
  data = [NSMutableData dataWithLength: GW_THUMBNAIL_HEAD];
  n = read(fd, [data mutableBytes], GW_THUMBNAIL_HEAD);
  close(fd);
  if (n < 0)
    {
      return nil;
    }
  [data setLength: (NSUInteger)n];
  return data;
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
  if (errno != ENOENT
      || EnsureDirectory([path stringByDeletingLastPathComponent]) == NO)
    {
      return NO;
    }
  /* Thumbnails show what the user's files contain. */
  return (mkdir(p, 0700) == 0 || errno == EEXIST) ? YES : NO;
}

/* An exclusive lock on the whole index while it is merged and written;
 * Windows has no flock(). */
static BOOL
IndexLock(int fd)
{
#ifdef _WIN32
  OVERLAPPED whole;

  memset(&whole, 0, sizeof(whole));
  return LockFileEx((HANDLE)_get_osfhandle(fd), LOCKFILE_EXCLUSIVE_LOCK, 0,
                    MAXDWORD, MAXDWORD, &whole) ? YES : NO;
#else
  return flock(fd, LOCK_EX) == 0;
#endif
}

static void
IndexUnlock(int fd)
{
#ifdef _WIN32
  OVERLAPPED whole;

  memset(&whole, 0, sizeof(whole));
  UnlockFileEx((HANDLE)_get_osfhandle(fd), 0, MAXDWORD, MAXDWORD, &whole);
#else
  flock(fd, LOCK_UN);
#endif
}

/* rename() over an existing file; Windows' own rename() refuses that. */
static BOOL
ReplaceExisting(const char *from, const char *to)
{
#ifdef _WIN32
  return MoveFileExA(from, to, MOVEFILE_REPLACE_EXISTING) ? YES : NO;
#else
  return rename(from, to) == 0;
#endif
}

static time_t
FileAge(NSString *path, time_t now)
{
  struct stat st;

  if (lstat([path fileSystemRepresentation], &st) != 0)
    {
      return -1;
    }
  return now - st.st_mtime;
}

@implementation GWThumbnailStore

static GWThumbnailStore *shared = nil;
static BOOL sharedWritable = NO;

+ (void)setSharedStoreWritable:(BOOL)flag
{
  @synchronized ([GWThumbnailStore class])
    {
      sharedWritable = flag;
    }
}

+ (void)setSharedStore:(GWThumbnailStore *)store
{
  @synchronized ([GWThumbnailStore class])
    {
      ASSIGN (shared, store);
    }
}

+ (GWThumbnailStore *)sharedStore
{
  @synchronized ([GWThumbnailStore class])
    {
      if (shared == nil)
        {
          NSString *dir = [NSSearchPathForDirectoriesInDomains
            (NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
          /* The same reading as Workspace's GWScaleFactor(), which this
           * framework cannot link: the desktop's GSScaleFactor, 1 when it
           * is unset or not positive. */
          id value = [[NSUserDefaults standardUserDefaults]
                       objectForKey: @"GSScaleFactor"];
          float scale = value ? [value floatValue] : 0.0F;

          if (scale <= 0.0F)
            {
              scale = 1.0F;
            }
          shared = [[GWThumbnailStore alloc]
            initWithDirectory: [dir stringByAppendingPathComponent: @"Thumbnails"]
                    pixelSize: (NSUInteger)ceil(GWThumbnailMaximumPoints * scale)
                     writable: sharedWritable];
          /* Index changes still waiting for their flush must not be lost
           * when Workspace quits within that second. */
          [[NSNotificationCenter defaultCenter]
            addObserver: shared
               selector: @selector(applicationWillTerminate:)
                   name: NSApplicationWillTerminateNotification
                 object: nil];
        }
    }
  return shared;
}

- (void)applicationWillTerminate:(NSNotification *)notif
{
  [self flush];
}

- (void)loadIndex
{
  NSDictionary *disk = [NSDictionary dictionaryWithContentsOfFile: indexPath];
  NSEnumerator *e;
  NSString *path;

  if (disk == nil)
    {
      [self rebuildIndex];
      return;
    }

  [index setDictionary: disk];
  if (writable == NO)
    {
      return;
    }
  e = [disk keyEnumerator];
  while ((path = [e nextObject]) != nil)
    {
      id value = [disk objectForKey: path];
      NSDictionary *entry = GWThumbnailEntryFromIndexValue(value);

      if (entry == nil)
        {
          [index removeObjectForKey: path];
          [pending setObject: [NSNull null] forKey: path];
        }
      else if ([entry objectForKey: GWThumbnailEntryMTime] == nil)
        {
          [self migrateOldEntry: entry forPath: path];
        }
    }
}

/* Older Workspace versions listed a bare file name per source, with no
 * stamp. Such a thumbnail is kept, with its source's present stamp, when
 * it was made after the source last changed, and dropped otherwise. */
- (void)migrateOldEntry:(NSDictionary *)entry forPath:(NSString *)path
{
  NSString *name = [entry objectForKey: GWThumbnailEntryName];
  NSString *file = [directory stringByAppendingPathComponent: name];
  GWThumbnailFileStamp stamp;
  struct stat st;

  if (GWThumbnailStampForPath(path, &stamp)
      && stat([file fileSystemRepresentation], &st) == 0
      && (long long)st.st_mtime >= stamp.mtime)
    {
      NSDictionary *migrated = GWThumbnailMakeEntry(name, GWThumbnailKindThumbnail,
                                                    nil, stamp, NO);

      [index setObject: migrated forKey: path];
      [pending setObject: migrated forKey: path];
      return;
    }
  unlink([file fileSystemRepresentation]);
  [index removeObjectForKey: path];
  [pending setObject: name forKey: path];
}

/* A lost or damaged index is rebuilt from the text chunks of the PNGs;
 * when two files claim the same source, the newer one wins and the
 * cleanup removes the other. */
- (void)rebuildIndex
{
  NSMutableDictionary *newest = [NSMutableDictionary dictionary];
  DIR *d = opendir([directory fileSystemRepresentation]);
  struct dirent *de;

  [index removeAllObjects];
  if (d == NULL)
    {
      return;
    }
  while ((de = readdir(d)) != NULL)
    {
      CREATE_AUTORELEASE_POOL(pool);
      NSString *name = [NSString stringWithUTF8String: de->d_name];

      if (GWThumbnailNameCounter(name) >= 0 && [[name pathExtension] isEqualToString: @"png"])
        {
          NSString *file = [directory stringByAppendingPathComponent: name];
          NSString *path = nil;
          NSDictionary *entry = GWThumbnailEntryFromText(
            GWThumbnailTextChunksInPNG(ReadHead(file)), name, &path);
          struct stat st;

          if (entry != nil && stat([file fileSystemRepresentation], &st) == 0)
            {
              NSNumber *age = [newest objectForKey: path];

              if (age == nil || [age longLongValue] < (long long)st.st_mtime)
                {
                  [newest setObject: [NSNumber numberWithLongLong: st.st_mtime]
                             forKey: path];
                  [index setObject: entry forKey: path];
                  [pending setObject: entry forKey: path];
                }
            }
        }
      RELEASE(pool);
    }
  closedir(d);
}

- (void)initCounter
{
  NSEnumerator *e = [index objectEnumerator];
  DIR *d = opendir([directory fileSystemRepresentation]);
  struct dirent *de;
  id value;

  counter = 0;
  while ((value = [e nextObject]) != nil)
    {
      long c = GWThumbnailNameCounter([GWThumbnailEntryFromIndexValue(value)
                                        objectForKey: GWThumbnailEntryName]);
      counter = MAX(counter, c);
    }
  if (d != NULL)
    {
      while ((de = readdir(d)) != NULL)
        {
          counter = MAX(counter, GWThumbnailNameCounter(
            [NSString stringWithUTF8String: de->d_name]));
        }
      closedir(d);
    }
}

- (id)initWithDirectory:(NSString *)aDirectory pixelSize:(NSUInteger)pixels
{
  return [self initWithDirectory: aDirectory pixelSize: pixels writable: YES];
}

- (BOOL)isWritable
{
  return writable;
}

- (id)initWithDirectory:(NSString *)aDirectory
              pixelSize:(NSUInteger)pixels
               writable:(BOOL)flag
{
  self = [super init];
  if (self != nil)
    {
      directory = [[aDirectory stringByStandardizingPath] copy];
      indexPath = [[directory stringByAppendingPathComponent: GWThumbnailIndexName] copy];
      lockPath = [[directory stringByAppendingPathComponent: GWThumbnailLockName] copy];
      pixelSize = pixels;
      lock = [NSRecursiveLock new];
      index = [NSMutableDictionary new];
      pending = [NSMutableDictionary new];
      writable = flag;

      if (writable && EnsureDirectory(directory) == NO)
        {
          NSLog(@"GWThumbnailStore: cannot create %@: %s", directory, strerror(errno));
          [self release];
          return nil;
        }
      [self loadIndex];
      if (writable)
        {
          [self initCounter];
          [self flush];
        }
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [directory release];
  [indexPath release];
  [lockPath release];
  [writer release];
  [lock release];
  [index release];
  [pending release];
  [super dealloc];
}

- (NSString *)directory
{
  return directory;
}

- (NSUInteger)pixelSize
{
  return pixelSize;
}

- (CGFloat)scaleFactor
{
  return (CGFloat)pixelSize / GWThumbnailMaximumPoints;
}

- (BOOL)containsPath:(NSString *)path
{
  return [path isEqualToString: directory]
    || [path hasPrefix: [directory stringByAppendingString: @"/"]];
}

- (NSDictionary *)entryForPath:(NSString *)path
{
  NSDictionary *entry;

  [lock lock];
  entry = [GWThumbnailEntryFromIndexValue([index objectForKey: path]) retain];
  [lock unlock];
  return [entry autorelease];
}

- (NSString *)fileForPath:(NSString *)path
                     kind:(NSString *)kind
                   source:(NSString *)source
{
  NSDictionary *entry = [self entryForPath: path];
  NSString *recorded;
  GWThumbnailFileStamp stamp;

  if (entry == nil
      || [[entry objectForKey: GWThumbnailEntryKind] isEqualToString: kind] == NO)
    {
      return nil;
    }
  recorded = GWThumbnailEntrySourcePath(entry, path);
  if ([recorded isEqualToString: (source ? source : path)] == NO
      || GWThumbnailStampForPath(recorded, &stamp) == NO
      || GWThumbnailEntryMatches(entry, stamp) == NO)
    {
      return nil;
    }
  return [directory stringByAppendingPathComponent:
    [entry objectForKey: GWThumbnailEntryName]];
}

- (NSData *)dataForPath:(NSString *)path
                   kind:(NSString *)kind
                 source:(NSString *)source
{
  NSString *file = [self fileForPath: path kind: kind source: source];

  return file ? [NSData dataWithContentsOfFile: file] : nil;
}

- (BOOL)hasFailureForPath:(NSString *)path source:(NSString *)source
{
  return [self fileForPath: path kind: GWThumbnailKindFailure source: source] != nil;
}

- (void)setNeedsFlush
{
  BOOL start = NO;

  [lock lock];
  if (flushScheduled == NO)
    {
      flushScheduled = YES;
      start = YES;
    }
  [lock unlock];
  if (start)
    {
      /* A GNUstep thread, not libdispatch, whose workers running ObjC
       * race the main thread's +load dispatch; callers come from any
       * thread, most without a run loop. */
      [NSThread detachNewThreadSelector: @selector(flushLater:)
                               toTarget: self
                             withObject: nil];
    }
}

- (void)flushLater:(id)unused
{
  @autoreleasepool
    {
      [NSThread sleepForTimeInterval: GW_THUMBNAIL_FLUSH_DELAY];
      [self flush];
    }
}

/* Applies one pending change to an index: an entry is set, a name
 * removes the entry only while it still names that file (another
 * process may have replaced it meanwhile), NSNull removes whatever is
 * there. */
static void
ApplyChange(NSMutableDictionary *target, NSString *path, id change)
{
  if ([change isKindOfClass: [NSDictionary class]])
    {
      [target setObject: change forKey: path];
    }
  else if ([change isKindOfClass: [NSNull class]])
    {
      [target removeObjectForKey: path];
    }
  else if ([[GWThumbnailEntryFromIndexValue([target objectForKey: path])
             objectForKey: GWThumbnailEntryName] isEqual: change])
    {
      [target removeObjectForKey: path];
    }
}

- (void)flush
{
  NSDictionary *changes;

  if (writable == NO)
    {
      return;
    }
  NSMutableDictionary *disk;
  NSEnumerator *e;
  NSString *path;
  int fd;

  [lock lock];
  flushScheduled = NO;
  changes = [pending copy];
  [pending removeAllObjects];
  [lock unlock];
  if ([changes count] == 0)
    {
      [changes release];
      return;
    }

  /* Merge with what is on disk under an exclusive lock, so a second
   * process writing the index at the same time loses nothing. */
  fd = open([lockPath fileSystemRepresentation], O_RDWR | O_CREAT, 0600);
  if (fd < 0 || IndexLock(fd) == NO)
    {
      NSLog(@"GWThumbnailStore: cannot lock %@: %s", lockPath, strerror(errno));
      if (fd >= 0)
        {
          close(fd);
        }
      [lock lock];
      [pending addEntriesFromDictionary: changes];
      [lock unlock];
      [changes release];
      return;
    }
  disk = [NSMutableDictionary dictionaryWithContentsOfFile: indexPath];
  if (disk == nil)
    {
      disk = [NSMutableDictionary dictionary];
    }
  e = [changes keyEnumerator];
  while ((path = [e nextObject]) != nil)
    {
      ApplyChange(disk, path, [changes objectForKey: path]);
    }
  if ([disk writeToFile: indexPath atomically: YES] == NO)
    {
      NSLog(@"GWThumbnailStore: cannot write %@", indexPath);
    }
  IndexUnlock(fd);
  close(fd);

  /* Take over what other processes added, without undoing changes this
   * process made while the file was being written. */
  [lock lock];
  [index setDictionary: disk];
  e = [pending keyEnumerator];
  while ((path = [e nextObject]) != nil)
    {
      ApplyChange(index, path, [pending objectForKey: path]);
    }
  [lock unlock];
  [changes release];
}

/* Writes png under the next free counter name. The name is claimed with
 * O_EXCL, which fails when it exists and so keeps threads and processes
 * from taking the same one, and the complete file then replaces the empty
 * claim in one rename; mkstemp makes it 0600. */
- (NSString *)writeFile:(NSData *)png
{
  NSString *template = [directory stringByAppendingPathComponent:
    [NSString stringWithFormat: @"%sXXXXXX", GWThumbnailTempPrefix]];
  const char *bytes = [png bytes];
  NSUInteger left = [png length];
  NSString *name = nil;
  BOOL ok = YES;
  char *tmp = strdup([template fileSystemRepresentation]);
  int fd;

  if (tmp == NULL || (fd = mkstemp(tmp)) < 0)
    {
      NSLog(@"GWThumbnailStore: cannot write in %@: %s", directory, strerror(errno));
      free(tmp);
      return nil;
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
  while (ok)
    {
      long c;

      [lock lock];
      counter = (counter >= LONG_MAX - 1) ? 1 : counter + 1;
      c = counter;
      [lock unlock];
      name = [NSString stringWithFormat: @"%lx.png", c];
      fd = open([[directory stringByAppendingPathComponent: name]
                  fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
      if (fd >= 0)
        {
          close(fd);
          ok = ReplaceExisting(tmp, [[directory stringByAppendingPathComponent: name]
                                  fileSystemRepresentation]);
          break;
        }
      if (errno != EEXIST)
        {
          ok = NO;
        }
    }
  if (ok == NO)
    {
      NSLog(@"GWThumbnailStore: cannot write in %@: %s", directory, strerror(errno));
      name = nil;
    }
  unlink(tmp);
  free(tmp);
  return name;
}

- (void)setEntry:(NSDictionary *)entry forPath:(NSString *)path
{
  NSString *old;

  [lock lock];
  old = [[GWThumbnailEntryFromIndexValue([index objectForKey: path])
           objectForKey: GWThumbnailEntryName] retain];
  [index setObject: entry forKey: path];
  [pending setObject: entry forKey: path];
  [lock unlock];
  if (old != nil && [old isEqual: [entry objectForKey: GWThumbnailEntryName]] == NO)
    {
      unlink([[directory stringByAppendingPathComponent: old] fileSystemRepresentation]);
    }
  [old release];
  [self setNeedsFlush];
}

- (NSData *)storeRGBA:(NSData *)rgba
                width:(NSUInteger)width
               height:(NSUInteger)height
              forPath:(NSString *)path
                 kind:(NSString *)kind
               source:(NSString *)source
           watchCTime:(BOOL)watchCTime
{
  GWThumbnailFileStamp stamp;
  NSUInteger tw = 0, th = 0;
  NSDictionary *entry;
  NSString *name;
  NSData *png;

  if (writable == NO || rgba == nil || [self containsPath: path]
      || GWThumbnailStampForPath(source ? source : path, &stamp) == NO)
    {
      return nil;
    }
  GWThumbnailFitSize(width, height, pixelSize, &tw, &th);
  if (tw != width || th != height)
    {
      rgba = GWThumbnailDownscaleRGBA(rgba, width, height, tw, th);
    }
  entry = GWThumbnailMakeEntry(@"", kind, source, stamp, watchCTime);
  png = GWThumbnailPNGEncodeRGBA(rgba, tw, th,
    GWThumbnailTextForEntry(path, entry, GWThumbnailSoftware));
  name = png ? [self writeFile: png] : nil;
  if (name == nil)
    {
      return png;
    }
  [self setEntry: GWThumbnailMakeEntry(name, kind, source, stamp, watchCTime)
         forPath: path];
  return png;
}

- (NSData *)storeImageData:(NSData *)data
                   forPath:(NSString *)path
                      kind:(NSString *)kind
                    source:(NSString *)source
{
  NSUInteger w = 0, h = 0;
  NSData *rgba = GWThumbnailRGBAFromData(data, GW_THUMBNAIL_MAX_DECODE_SIDE, &w, &h);

  return [self storeRGBA: rgba width: w height: h forPath: path
                    kind: kind source: source watchCTime: NO];
}

- (void)storeRGBAInBackground:(NSData *)rgba
                        width:(NSUInteger)width
                       height:(NSUInteger)height
                      forPath:(NSString *)path
                         kind:(NSString *)kind
                       source:(NSString *)source
                   watchCTime:(BOOL)watchCTime
{
  NSMutableDictionary *job = [NSMutableDictionary dictionaryWithCapacity: 7];

  [job setObject: rgba forKey: @"rgba"];
  [job setObject: [NSNumber numberWithUnsignedInteger: width] forKey: @"width"];
  [job setObject: [NSNumber numberWithUnsignedInteger: height] forKey: @"height"];
  [job setObject: path forKey: @"path"];
  [job setObject: kind forKey: @"kind"];
  if (source != nil)
    {
      [job setObject: source forKey: @"source"];
    }
  [job setObject: [NSNumber numberWithBool: watchCTime] forKey: @"watchCTime"];
  [lock lock];
  if (writer == nil)
    {
      /* Two are plenty for encoding a few hundred kilobytes each. */
      writer = [[GWWorkerPool alloc] initWithMaximumWorkers: 2
                                                     target: self
                                                   selector: @selector(storeJob:)];
    }
  [lock unlock];
  [writer addJob: job];
}

- (void)storeJob:(NSDictionary *)job
{
  [self storeRGBA: [job objectForKey: @"rgba"]
            width: [[job objectForKey: @"width"] unsignedIntegerValue]
           height: [[job objectForKey: @"height"] unsignedIntegerValue]
          forPath: [job objectForKey: @"path"]
             kind: [job objectForKey: @"kind"]
           source: [job objectForKey: @"source"]
       watchCTime: [[job objectForKey: @"watchCTime"] boolValue]];
}

- (BOOL)storeFailureForPath:(NSString *)path source:(NSString *)source
{
  /* One transparent pixel: the smallest image every reader accepts, so a
   * failure record is rebuilt from its text chunks like any entry. */
  return [self storeRGBA: [NSMutableData dataWithLength: 4] width: 1 height: 1
                 forPath: path kind: GWThumbnailKindFailure source: source
              watchCTime: NO] != nil;
}

- (BOOL)removeEntryForPath:(NSString *)path
{
  NSString *name;

  if (writable == NO)
    {
      return NO;
    }
  [lock lock];
  name = [[GWThumbnailEntryFromIndexValue([index objectForKey: path])
            objectForKey: GWThumbnailEntryName] retain];
  if (name != nil)
    {
      [index removeObjectForKey: path];
      [pending setObject: name forKey: path];
    }
  [lock unlock];
  if (name == nil)
    {
      return NO;
    }
  unlink([[directory stringByAppendingPathComponent: name] fileSystemRepresentation]);
  [name release];
  [self setNeedsFlush];
  return YES;
}

/* Drops the entry of path when its file is gone or its source is gone or
 * changed. known says the caller knows the source was moved or deleted,
 * so a missing directory is no sign of unmounted media. */
- (BOOL)removeEntryIfStale:(NSString *)path now:(time_t)now known:(BOOL)known
{
  GWThumbnailSourceState state;
  NSDictionary *entry = [self entryForPath: path];
  NSString *file;
  time_t age;

  if (entry == nil)
    {
      return NO;
    }
  file = [directory stringByAppendingPathComponent:
    [entry objectForKey: GWThumbnailEntryName]];
  age = FileAge(file, now);
  state = SourceState(GWThumbnailEntrySourcePath(entry, path));
  if (known)
    {
      state.parentExists = YES;
    }
  if (age >= 0 && GWThumbnailEntryIsStale(entry, state, (NSTimeInterval)age) == NO)
    {
      return NO;
    }
  return [self removeEntryForPath: path];
}

- (NSArray *)removeStaleEntriesForPaths:(NSArray *)paths
{
  if (writable == NO)
    {
      return [NSArray array];
    }
  return [self staleEntriesRemovedForPaths: paths];
}

- (NSArray *)staleEntriesRemovedForPaths:(NSArray *)paths
{
  NSMutableArray *dropped = [NSMutableArray array];
  NSMutableArray *candidates = [NSMutableArray array];
  time_t now = time(NULL);
  NSEnumerator *e;
  NSString *key;
  NSUInteger i;

  /* A moved or deleted folder takes everything inside it along. */
  [lock lock];
  e = [index keyEnumerator];
  while ((key = [e nextObject]) != nil)
    {
      for (i = 0; i < [paths count]; i++)
        {
          NSString *path = [paths objectAtIndex: i];

          if ([key isEqualToString: path]
              || [key hasPrefix: [path stringByAppendingString: @"/"]])
            {
              [candidates addObject: key];
              break;
            }
        }
    }
  [lock unlock];

  for (i = 0; i < [candidates count]; i++)
    {
      NSString *path = [candidates objectAtIndex: i];

      if ([self removeEntryIfStale: path now: now known: YES])
        {
          [dropped addObject: path];
        }
    }
  return dropped;
}

/* A file no entry names: adopted when its text chunks still describe a
 * source without an entry of its own, deleted otherwise. */
- (void)reviewUnreferencedFile:(NSString *)name now:(time_t)now
{
  NSString *file = [directory stringByAppendingPathComponent: name];
  NSString *path = nil;
  NSDictionary *entry = nil;
  time_t age = FileAge(file, now);

  if (age < 0 || age < GW_THUMBNAIL_IN_FLIGHT)
    {
      return;
    }
  if ([[name pathExtension] isEqualToString: @"png"])
    {
      entry = GWThumbnailEntryFromText(GWThumbnailTextChunksInPNG(ReadHead(file)),
                                       name, &path);
    }
  if (entry != nil && [self entryForPath: path] == nil
      && GWThumbnailEntryIsStale(entry,
           SourceState(GWThumbnailEntrySourcePath(entry, path)),
           (NSTimeInterval)age) == NO)
    {
      [self setEntry: entry forPath: path];
      return;
    }
  unlink([file fileSystemRepresentation]);
}

- (NSArray *)removeStaleEntries
{
  NSArray *paths;
  NSMutableArray *dropped;
  NSUInteger i;

  if (writable == NO)
    {
      return [NSArray array];
    }
  NSMutableSet *referenced = [NSMutableSet set];
  NSEnumerator *e;
  id value;
  time_t now = time(NULL);
  DIR *d;
  struct dirent *de;

  [lock lock];
  paths = [[index allKeys] retain];
  [lock unlock];
  dropped = [NSMutableArray array];
  for (i = 0; i < [paths count]; i++)
    {
      if ([self removeEntryIfStale: [paths objectAtIndex: i] now: now known: NO])
        {
          [dropped addObject: [paths objectAtIndex: i]];
        }
    }
  [paths release];

  [lock lock];
  e = [index objectEnumerator];
  while ((value = [e nextObject]) != nil)
    {
      NSString *name = [GWThumbnailEntryFromIndexValue(value)
                         objectForKey: GWThumbnailEntryName];

      if (name != nil)
        {
          [referenced addObject: name];
        }
    }
  [lock unlock];

  d = opendir([directory fileSystemRepresentation]);
  if (d != NULL)
    {
      while ((de = readdir(d)) != NULL)
        {
          CREATE_AUTORELEASE_POOL(pool);
          NSString *name = [NSString stringWithUTF8String: de->d_name];

          if (strncmp(de->d_name, GWThumbnailTempPrefix,
                      strlen(GWThumbnailTempPrefix)) == 0)
            {
              /* Left behind by a writer that died before linking it. */
              NSString *file = [directory stringByAppendingPathComponent: name];

              if (FileAge(file, now) >= GW_THUMBNAIL_IN_FLIGHT)
                {
                  unlink([file fileSystemRepresentation]);
                }
            }
          else if (GWThumbnailNameCounter(name) >= 0
                   && [referenced containsObject: name] == NO)
            {
              [self reviewUnreferencedFile: name now: now];
            }
          RELEASE(pool);
        }
      closedir(d);
    }
  return dropped;
}

- (NSUInteger)importEntriesFromCacheDirectory:(NSString *)cacheDirectory
                                     software:(NSString *)software
{
  if (writable == NO)
    {
      return 0;
    }
  return [self importFromCacheDirectory: cacheDirectory software: software];
}

- (NSUInteger)importFromCacheDirectory:(NSString *)cacheDirectory
                              software:(NSString *)software
{
  /* The keys that earlier build wrote. */
  NSString *uriKey = @"Thumb::URI";
  NSString *mtimeKey = @"Thumb::MTime";
  NSString *sizeKey = @"Thumb::Size";
  NSString *failRoot = [cacheDirectory stringByAppendingPathComponent: @"fail"];
  NSMutableArray *dirs = [NSMutableArray array];
  NSMutableSet *failDirs = [NSMutableSet set];
  NSArray *sizes = [NSArray arrayWithObjects: @"normal", @"large", @"x-large",
                            @"xx-large", nil];
  NSUInteger moved = 0;
  NSUInteger i;
  DIR *d;
  struct dirent *de;

  for (i = 0; i < [sizes count]; i++)
    {
      [dirs addObject: [cacheDirectory stringByAppendingPathComponent:
        [sizes objectAtIndex: i]]];
    }
  d = opendir([failRoot fileSystemRepresentation]);
  if (d != NULL)
    {
      while ((de = readdir(d)) != NULL)
        {
          if (de->d_name[0] != '.')
            {
              NSString *dir = [failRoot stringByAppendingPathComponent:
                [NSString stringWithUTF8String: de->d_name]];

              [dirs addObject: dir];
              [failDirs addObject: dir];
            }
        }
      closedir(d);
    }

  for (i = 0; i < [dirs count]; i++)
    {
      NSString *dir = [dirs objectAtIndex: i];
      BOOL failures = [failDirs containsObject: dir];

      d = opendir([dir fileSystemRepresentation]);
      if (d == NULL)
        {
          continue;
        }
      while ((de = readdir(d)) != NULL)
        {
          CREATE_AUTORELEASE_POOL(pool);
          NSString *file = [dir stringByAppendingPathComponent:
            [NSString stringWithUTF8String: de->d_name]];
          NSData *png = [[file pathExtension] isEqualToString: @"png"]
            ? [NSData dataWithContentsOfFile: file] : nil;
          NSDictionary *text = GWThumbnailTextChunksInPNG(png);

          if ([[text objectForKey: GWThumbnailTextSoftware] isEqual: software])
            {
              NSString *path = GWThumbnailPathForFileURI([text objectForKey: uriKey]);
              NSDictionary *old = [NSDictionary dictionaryWithObjectsAndKeys:
                [text objectForKey: mtimeKey], GWThumbnailEntryMTime,
                [text objectForKey: sizeKey], GWThumbnailEntrySize, nil];
              GWThumbnailFileStamp stamp;

              if (path != nil && GWThumbnailStampForPath(path, &stamp)
                  && GWThumbnailEntryMatches(old, stamp)
                  && [self fileForPath: path kind: (failures ? GWThumbnailKindFailure
                                                             : GWThumbnailKindIcon)
                                source: nil] == nil)
                {
                  NSUInteger w = 0, h = 0;
                  NSData *rgba = failures ? nil
                    : GWThumbnailPNGDecodeRGBA(png, GW_THUMBNAIL_MAX_DECODE_SIDE, &w, &h);
                  BOOL stored = failures
                    ? [self storeFailureForPath: path source: nil]
                    : ([self storeRGBA: rgba width: w height: h forPath: path
                                  kind: GWThumbnailKindIcon source: nil
                            watchCTime: NO] != nil);

                  if (stored)
                    {
                      moved++;
                    }
                }
              unlink([file fileSystemRepresentation]);
            }
          RELEASE(pool);
        }
      closedir(d);
      if (failures)
        {
          /* Fails, as it should, while other entries are still in it. */
          rmdir([dir fileSystemRepresentation]);
        }
    }
  return moved;
}

@end
