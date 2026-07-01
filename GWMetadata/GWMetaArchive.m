/* GWMetaArchive.m
 *
 * libarchive wrapper for zip read/write with Mac metadata.
 *
 * Uses explicit __MACOSX/._ companion entries (the standard macOS format)
 * rather than relying on libarchive's mac_metadata API, which may not
 * be supported in all builds.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWMetaArchive.h"
#import "GSFileMetadata.h"
#import "GSAppleDouble.h"

#include <archive.h>
#include <archive_entry.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

#define READ_BLOCK_SIZE  10240
#define WRITE_BLOCK_SIZE  16384

/* Upper bound for a single __MACOSX/._ metadata entry buffered in pass 1.
 * AppleDouble headers are a few KB; anything larger is almost certainly a
 * malicious archive trying to exhaust memory (every such entry is buffered
 * at full size in metadataDict).  1 MB is a generous ceiling. */
#define MAX_METADATA_ENTRY_SIZE  (1024 * 1024)

/* ------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------ */

static void
collect_tree(NSString *root, NSMutableArray *entries, NSFileManager *fm)
{
  NSArray *contents = [fm directoryContentsAtPath: root];
  if (!contents) return;

  NSUInteger i;
  for (i = 0; i < [contents count]; i++)
    {
      NSString *name = [contents objectAtIndex: i];
      NSString *full  = [root stringByAppendingPathComponent: name];
      if ([name hasPrefix: @"._"]) continue;

      [entries addObject: full];

      BOOL isDir;
      if ([fm fileExistsAtPath: full isDirectory: &isDir] && isDir)
        collect_tree(full, entries, fm);
    }
}

static int
copy_fd_to_archive(struct archive *a, int fd)
{
  char buf[WRITE_BLOCK_SIZE];
  ssize_t n;
  while ((n = read(fd, buf, sizeof(buf))) > 0)
    {
      if (archive_write_data(a, buf, (size_t)n) < 0)
        return ARCHIVE_FATAL;
    }
  return (n == 0) ? ARCHIVE_OK : ARCHIVE_FATAL;
}

/*
 * Write a __MACOSX/._ companion entry containing the AppleDouble blob.
 * This is the standard macOS zip format for file metadata.
 */
static int
write_macosx_entry(struct archive *a, NSString *arcname, NSData *appleDouble)
{
  NSString *dir  = [arcname stringByDeletingLastPathComponent];
  NSString *file = [arcname lastPathComponent];
  NSString *macosxPath;

  if ([dir length] == 0 || [dir isEqualToString: @"."])
    macosxPath = [NSString stringWithFormat: @"__MACOSX/._%@", file];
  else
    macosxPath = [NSString stringWithFormat: @"__MACOSX/%@/._%@", dir, file];

  struct archive_entry *e = archive_entry_new();
  archive_entry_set_pathname(e, [macosxPath fileSystemRepresentation]);
  archive_entry_set_filetype(e, AE_IFREG);
  archive_entry_set_size(e, [appleDouble length]);
  archive_entry_set_perm(e, 0644);

  int r = archive_write_header(a, e);
  if (r >= ARCHIVE_OK)
    r = (int)archive_write_data(a, [appleDouble bytes], [appleDouble length]);

  archive_entry_free(e);
  return (r >= 0) ? ARCHIVE_OK : ARCHIVE_FATAL;
}

/*
 * Add a single file + optional __MACOSX companion to the archive.
 */
static int
add_file_to_archive(struct archive *a, NSString *path, NSString *arcname)
{
  struct stat st;
  const char *cpath = [path fileSystemRepresentation];

  if (lstat(cpath, &st) != 0)
    return ARCHIVE_WARN;

  /* Write the real file entry */
  struct archive_entry *entry = archive_entry_new();
  archive_entry_set_pathname(entry, [arcname fileSystemRepresentation]);
  archive_entry_copy_stat(entry, &st);

  int r = archive_write_header(a, entry);
  if (r < ARCHIVE_WARN)
    {
      archive_entry_free(entry);
      return r;
    }

  if (S_ISREG(st.st_mode) && st.st_size > 0)
    {
      int fd = open(cpath, O_RDONLY);
      if (fd >= 0)
        {
          r = copy_fd_to_archive(a, fd);
          close(fd);
        }
    }
  archive_entry_free(entry);

  if (r < ARCHIVE_WARN) return r;

  /* Write __MACOSX companion if metadata exists */
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  if (md)
    {
      NSData *ad = [md appleDoubleData];
      if (ad && [ad length] > 0)
        r = write_macosx_entry(a, arcname, ad);
    }
  /* md is autoreleased */

  return r;
}

static int
add_dir_to_archive(struct archive *a, NSString *path, NSString *arcname)
{
  struct stat st;
  const char *cpath = [path fileSystemRepresentation];

  if (lstat(cpath, &st) != 0)
    return ARCHIVE_WARN;

  struct archive_entry *entry = archive_entry_new();
  archive_entry_set_pathname(entry, [arcname fileSystemRepresentation]);
  archive_entry_copy_stat(entry, &st);

  int r = archive_write_header(a, entry);
  archive_entry_free(entry);

  /* __MACOSX companion for directories too (custom icons, labels) */
  if (r >= ARCHIVE_OK)
    {
      GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
      if (md)
        {
          NSData *ad = [md appleDoubleData];
          if (ad && [ad length] > 0)
            r = write_macosx_entry(a, arcname, ad);
        }
    }
  return r;
}

/* ------------------------------------------------------------------
 * Extraction helpers
 * ------------------------------------------------------------------ */

static int
copy_archive_data_to_fd(struct archive *a, int fd)
{
  const void *buf;
  size_t size;
  int64_t offset;
  int r;
  for (;;)
    {
      r = archive_read_data_block(a, &buf, &size, &offset);
      if (r == ARCHIVE_EOF) return ARCHIVE_OK;
      if (r != ARCHIVE_OK)  return r;

      ssize_t written = write(fd, buf, size);
      if (written < 0 || (size_t)written != size)
        return ARCHIVE_FATAL;
    }
}

/*
 * Parse a `__MACOSX/._path` entry path into the corresponding
 * real file path.  Returns nil if the string doesn't match.
 *
 *   __MACOSX/._foo        → foo
 *   __MACOSX/dir/._bar    → dir/bar
 */
static NSString *
real_path_from_macosx(NSString *mpx)
{
  if (![mpx hasPrefix: @"__MACOSX/"]) return nil;

  NSString *rest = [mpx substringFromIndex: 9];  /* skip "__MACOSX/" */
  NSArray  *comps = [rest pathComponents];

  /* Walk components: replace any "._X" with "X", everything else is a dir */
  NSMutableArray *out = [NSMutableArray arrayWithCapacity: [comps count]];
  for (NSString *c in comps)
    {
      if ([c hasPrefix: @"._"])
        [out addObject: [c substringFromIndex: 2]];
      else
        [out addObject: c];
    }
  if ([out count] == 0) return nil;
  return [NSString pathWithComponents: out];
}

/*
 * Zip-Slip guard: return YES only when `candidate` resolves to `canonicalDir`
 * itself or a path strictly inside it.  `canonicalDir` must already be
 * standardized (see extractArchive:).  `candidate` is standardized here so
 * that any embedded ".." components (or an absolute entry name) are collapsed
 * before the prefix check, preventing extraction outside the destination.
 */
static BOOL
path_is_within(NSString *canonicalDir, NSString *candidate)
{
  NSString *std = [candidate stringByStandardizingPath];
  if ([std isEqualToString: canonicalDir])
    return YES;

  NSString *prefix = [canonicalDir hasSuffix: @"/"]
                       ? canonicalDir
                       : [canonicalDir stringByAppendingString: @"/"];
  return [std hasPrefix: prefix];
}

@implementation GWMetaArchive

/* =================================================================
 * Compression
 * ================================================================= */

+ (BOOL)compressPaths:(NSArray *)filePaths
          toArchiveAt:(NSString *)outputPath
                error:(NSError **)error
{
  if (!filePaths || [filePaths count] == 0)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 1
          userInfo: @{NSLocalizedDescriptionKey: @"No files to compress"}];
      return NO;
    }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableArray *allFiles = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [filePaths count]; i++)
    {
      NSString *fp = [filePaths objectAtIndex: i];
      BOOL isDir;
      if ([fm fileExistsAtPath: fp isDirectory: &isDir])
        {
          [allFiles addObject: fp];
          if (isDir) collect_tree(fp, allFiles, fm);
        }
    }

  if ([allFiles count] == 0)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 2
          userInfo: @{NSLocalizedDescriptionKey: @"No valid files found"}];
      return NO;
    }

  /* Common prefix for relative archive paths */
  NSString *commonParent = [[allFiles objectAtIndex: 0] stringByDeletingLastPathComponent];
  for (i = 1; i < [allFiles count]; i++)
    {
      NSString *p = [[allFiles objectAtIndex: i] stringByDeletingLastPathComponent];
      while (![commonParent isEqualToString: p])
        {
          if ([commonParent length] < [p length])
            p = [p stringByDeletingLastPathComponent];
          else if ([commonParent length] > [p length])
            commonParent = [commonParent stringByDeletingLastPathComponent];
          else {
            commonParent = [commonParent stringByDeletingLastPathComponent];
            p = [p stringByDeletingLastPathComponent];
          }
        }
    }

  struct archive *a = archive_write_new();
  if (!a)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 3
          userInfo: @{NSLocalizedDescriptionKey: @"archive_write_new failed"}];
      return NO;
    }

  archive_write_set_format_zip(a);
  archive_write_add_filter_none(a);

  const char *outpath = [outputPath fileSystemRepresentation];
  if (archive_write_open_filename(a, outpath) != ARCHIVE_OK)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 4
          userInfo: @{NSLocalizedDescriptionKey:
            [NSString stringWithFormat: @"Cannot open %@: %s",
              outputPath, archive_error_string(a)]}];
      archive_write_free(a);
      return NO;
    }

  BOOL ok = YES;
  NSUInteger prefixLen = [commonParent length];
  if (![commonParent hasSuffix: @"/"]) prefixLen++;

  for (i = 0; i < [allFiles count]; i++)
    {
      NSString *fp = [allFiles objectAtIndex: i];
      NSString *arcname = [fp substringFromIndex: prefixLen];
      BOOL isDir;
      [fm fileExistsAtPath: fp isDirectory: &isDir];

      int r = isDir ? add_dir_to_archive(a, fp, arcname)
                     : add_file_to_archive(a, fp, arcname);
      if (r < ARCHIVE_WARN)
        {
          if (error)
            *error = [NSError errorWithDomain: @"GWMetaArchive" code: 5
              userInfo: @{NSLocalizedDescriptionKey:
                [NSString stringWithFormat: @"Error adding %@: %s",
                  fp, archive_error_string(a)]}];
          ok = NO;
          break;
        }
    }

  archive_write_close(a);
  archive_write_free(a);
  return ok;
}

+ (BOOL)compressDirectory:(NSString *)dirPath
              toArchiveAt:(NSString *)outputPath
                    error:(NSError **)error
{
  return [self compressPaths: @[dirPath] toArchiveAt: outputPath error: error];
}

/* =================================================================
 * Extraction
 * ================================================================= */

+ (BOOL)extractArchive:(NSString *)archivePath
                  toDir:(NSString *)destDir
                 error:(NSError **)error
{
  NSFileManager *fm = [NSFileManager defaultManager];

  if (![fm fileExistsAtPath: destDir])
    {
      if (![fm createDirectoryAtPath: destDir attributes: nil])
        {
          if (error)
            *error = [NSError errorWithDomain: @"GWMetaArchive" code: 10
              userInfo: @{NSLocalizedDescriptionKey:
                [NSString stringWithFormat: @"Cannot create %@", destDir]}];
          return NO;
        }
    }

  struct archive *a = archive_read_new();
  if (!a)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 11
          userInfo: @{NSLocalizedDescriptionKey: @"archive_read_new failed"}];
      return NO;
    }

  archive_read_support_format_zip(a);
  archive_read_support_filter_all(a);

  const char *cpath = [archivePath fileSystemRepresentation];
  if (archive_read_open_filename(a, cpath, READ_BLOCK_SIZE) != ARCHIVE_OK)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 12
          userInfo: @{NSLocalizedDescriptionKey:
            [NSString stringWithFormat: @"Cannot open %@: %s",
              archivePath, archive_error_string(a)]}];
      archive_read_free(a);
      return NO;
    }

  /*
   * First pass: read all __MACOSX entries, collecting AppleDouble data
   * keyed by the real file path (relative to destDir).
   */
  NSMutableDictionary *metadataDict = [NSMutableDictionary dictionary];
  BOOL ok = YES;
  struct archive_entry *entry;

  for (;;)
    {
      int r = archive_read_next_header(a, &entry);
      if (r == ARCHIVE_EOF) break;
      if (r != ARCHIVE_OK)
        {
          if (error)
            *error = [NSError errorWithDomain: @"GWMetaArchive" code: 13
              userInfo: @{NSLocalizedDescriptionKey:
                [NSString stringWithFormat: @"Error reading archive: %s",
                  archive_error_string(a)]}];
          ok = NO;
          break;
        }

      const char *ename = archive_entry_pathname(entry);
      if (!ename) { archive_read_data_skip(a); continue; }

      NSString *epath = [NSString stringWithUTF8String: ename];

      if ([epath hasPrefix: @"__MACOSX/"])
        {
          NSString *real = real_path_from_macosx(epath);
          int64_t esize = archive_entry_size(entry);
          if (real && esize > 0 && esize <= MAX_METADATA_ENTRY_SIZE)
            {
              NSMutableData *ad = [NSMutableData dataWithLength: (NSUInteger)esize];
              ssize_t nread = archive_read_data(a, [ad mutableBytes], [ad length]);
              if (nread > 0)
                [metadataDict setObject: ad forKey: real];
            }
          archive_read_data_skip(a);
        }
      else if ([[epath lastPathComponent] hasPrefix: @"._"])
        {
          /* Loose ._ sidecar — parse it, find corresponding file */
          archive_read_data_skip(a);
        }
      else
        {
          archive_read_data_skip(a);
        }
    }

  if (!ok)
    {
      archive_read_close(a);
      archive_read_free(a);
      return NO;
    }

  /* Close and re-open for second pass (extract real files) */
  archive_read_close(a);
  archive_read_free(a);

  a = archive_read_new();
  if (!a)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 15
          userInfo: @{NSLocalizedDescriptionKey: @"archive_read_new failed"}];
      return NO;
    }
  archive_read_support_format_zip(a);
  archive_read_support_filter_all(a);
  if (archive_read_open_filename(a, cpath, READ_BLOCK_SIZE) != ARCHIVE_OK)
    {
      if (error)
        *error = [NSError errorWithDomain: @"GWMetaArchive" code: 14
          userInfo: @{NSLocalizedDescriptionKey: @"Cannot re-open archive"}];
      return NO;
    }

  /* Canonical destination used for the per-entry Zip-Slip check below. */
  NSString *canonicalDest = [destDir stringByStandardizingPath];

  for (;;)
    {
      int r = archive_read_next_header(a, &entry);
      if (r == ARCHIVE_EOF) break;
      if (r != ARCHIVE_OK) { ok = NO; break; }

      const char *ename = archive_entry_pathname(entry);
      if (!ename) { archive_read_data_skip(a); continue; }

      NSString *epath = [NSString stringWithUTF8String: ename];
      /* A non-UTF-8 entry name yields nil; skip rather than risk a
       * nil argument to stringByAppendingPathComponent: below. */
      if (epath == nil) { archive_read_data_skip(a); continue; }

      /* Skip metadata entries on second pass */
      if ([epath hasPrefix: @"__MACOSX/"] ||
          [[epath lastPathComponent] hasPrefix: @"._"])
        {
          archive_read_data_skip(a);
          continue;
        }

      NSString *destPath = [destDir stringByAppendingPathComponent: epath];

      /* Zip-Slip defense: reject entries that resolve outside destDir
       * (embedded ".." or absolute names) before any create/open. */
      if (!path_is_within(canonicalDest, destPath))
        {
          NSDebugLLog(@"gwspace",
            @"GWMetaArchive: rejecting unsafe archive entry '%@'", epath);
          archive_read_data_skip(a);
          continue;
        }

      mode_t filetype = archive_entry_filetype(entry);

      if (filetype == AE_IFDIR)
        {
          if (![fm fileExistsAtPath: destPath])
            [fm createDirectoryAtPath: destPath attributes: nil];
          archive_read_data_skip(a);
        }
      else if (filetype == AE_IFREG)
        {
          NSString *parent = [destPath stringByDeletingLastPathComponent];
          if (![fm fileExistsAtPath: parent])
            [fm createDirectoryAtPath: parent attributes: nil];

          int fd = open([destPath fileSystemRepresentation],
                        O_WRONLY | O_CREAT | O_TRUNC, 0644);
          if (fd >= 0)
            {
              /* Propagate a write failure instead of silently leaving a
               * truncated file and still reporting success. */
              if (copy_archive_data_to_fd(a, fd) != ARCHIVE_OK)
                {
                  close(fd);
                  if (error)
                    *error = [NSError errorWithDomain: @"GWMetaArchive" code: 16
                      userInfo: @{NSLocalizedDescriptionKey:
                        [NSString stringWithFormat: @"Error extracting %@", epath]}];
                  ok = NO;
                  break;
                }
              close(fd);
            }
          else
            {
              archive_read_data_skip(a);
            }
        }
      else
        {
          archive_read_data_skip(a);
          continue;
        }

      /* Apply metadata from pass 1 */
      NSData *ad = [metadataDict objectForKey: epath];
      if (ad)
        {
          GSFileMetadata *md = [GSFileMetadata metadataFromAppleDoubleData: ad];
          if (md)
            {
              NSError *we = nil;
              if (![md writeToFileAtPath: destPath error: &we])
                NSDebugLLog(@"gwspace", @"GWMetaArchive: failed to write xattr for %@: %@",
                      destPath, we);
            }
        }
    }

  archive_read_close(a);
  archive_read_free(a);
  return ok;
}

@end
