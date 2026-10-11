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
#import "GWMetaXattr.h"

#include <archive.h>
#include <archive_entry.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>

#ifdef _WIN32
/* MinGW has no lstat(); there are no POSIX symlinks to preserve anyway. */
# define lstat stat
# ifndef ACCESSPERMS
#  define ACCESSPERMS 0777
# endif
#endif

/* GNUstep's -fileSystemRepresentation returns UTF-16 on Windows, but the C
   library calls here take narrow strings, so use the UTF-8 form there. On
   the other platforms this is the plain -fileSystemRepresentation call. */
#ifdef _WIN32
#define GW_FSREP(path) [(path) UTF8String]
#else
#define GW_FSREP(path) [(path) fileSystemRepresentation]
#endif

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

/* An all-zero FinderInfo alone is what a Mac writes for an item it has
 * nothing to say about (Finder's Compress does it for .DS_Store); it
 * carries no information and must not be applied or written. */
static BOOL
appledouble_is_empty(GSAppleDouble *ad)
{
  if ([[ad extendedAttributes] count] > 0 || [[ad resourceFork] length] > 0)
    return NO;
  if (![ad hasFinderInfo])
    return YES;
  const uint8_t *b = [[ad finderInfo] bytes];
  NSUInteger n = [[ad finderInfo] length];
  while (n > 0 && b[n - 1] == 0)
    n--;
  return n == 0;
}

/*
 * The AppleDouble a Mac's ditto/Finder would write for the item, built from
 * everything the item carries: FinderInfo, resource fork and every user.*
 * attribute (not just the ones GSFileMetadata models), with the item's own
 * "._" sidecar as base for volumes without attributes.  Returns nil when the
 * item has nothing a Mac would keep, so no empty "._" entry is written.
 */
static NSData *
appledouble_for_path(NSString *path)
{
  const char *cpath = GW_FSREP(path);
  NSString *sidecar = [[path stringByDeletingLastPathComponent]
    stringByAppendingPathComponent:
      [@"._" stringByAppendingString: [path lastPathComponent]]];
  NSData *base = [NSData dataWithContentsOfFile: sidecar];
  GSAppleDouble *ad = base ? [[GSAppleDouble alloc] initWithData: base] : nil;

  if (ad == nil)
    ad = [[GSAppleDouble alloc] init];

  gs_xattr_list_t *list = gs_xattr_list_for_path(cpath, "user.");
  int i;
  for (i = 0; list != NULL && i < list->count; i++)
    {
      NSString *name = [NSString stringWithUTF8String: list->entries[i].name];
      NSData *value = [NSData dataWithBytes: list->entries[i].value
                                     length: list->entries[i].size];
      if (name == nil)
        continue;
      name = [name substringFromIndex: 5];  /* "user." */
      if ([name isEqualToString: @"com.apple.FinderInfo"])
        {
          /* Only 32 bytes are FinderInfo; 10.6 ignores any other length. */
          if ([value length] == 32)
            [ad setFinderInfo: value];
        }
      else if ([name isEqualToString: @"com.apple.ResourceFork"])
        [ad setResourceFork: value];
      else if ([name isEqualToString: @"com.apple.quarantine"])
        [ad setXattr: [GSFileMetadata sidecarQuarantine: value] forKey: name];
      else
        [ad setXattr: value forKey: name];
    }
  if (list != NULL)
    gs_xattr_list_free(list);

  BOOL nothing = appledouble_is_empty(ad);

  NSData *out = nothing ? nil : [ad appleDoubleData];
  [ad release];
  return out;
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
  archive_entry_set_pathname(e, GW_FSREP(macosxPath));
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
  const char *cpath = GW_FSREP(path);

  if (lstat(cpath, &st) != 0)
    return ARCHIVE_WARN;

  /* Write the real file entry */
  struct archive_entry *entry = archive_entry_new();
  archive_entry_set_pathname(entry, GW_FSREP(arcname));
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
  NSData *ad = appledouble_for_path(path);
  if (ad && [ad length] > 0)
    r = write_macosx_entry(a, arcname, ad);

  return r;
}

static int
add_dir_to_archive(struct archive *a, NSString *path, NSString *arcname)
{
  struct stat st;
  const char *cpath = GW_FSREP(path);

  if (lstat(cpath, &st) != 0)
    return ARCHIVE_WARN;

  struct archive_entry *entry = archive_entry_new();
  archive_entry_set_pathname(entry, GW_FSREP(arcname));
  archive_entry_copy_stat(entry, &st);

  int r = archive_write_header(a, entry);
  archive_entry_free(entry);

  /* __MACOSX companion for directories too (custom icons, labels) */
  if (r >= ARCHIVE_OK)
    {
      NSData *ad = appledouble_for_path(path);
      if (ad && [ad length] > 0)
        r = write_macosx_entry(a, arcname, ad);
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

/* AppleDouble header magic, to tell a real "._" companion from a user's
 * file that merely has such a name. */
static BOOL
is_appledouble(NSData *d)
{
  const uint8_t *b = [d bytes];
  return [d length] >= 26 && b[0] == 0x00 && b[1] == 0x05
         && b[2] == 0x16 && b[3] == 0x07;
}

/* The path of the item an AppleDouble companion describes, from the entry
 * path of the companion itself: dir/._name -> dir/name. */
static NSString *
real_path_from_companion(NSString *epath)
{
  NSString *name = [epath lastPathComponent];
  return [[epath stringByDeletingLastPathComponent]
    stringByAppendingPathComponent: [name substringFromIndex: 2]];
}

/*
 * Give the extracted item the metadata of its AppleDouble: FinderInfo
 * (label, flags, type), resource fork (custom icon) and every attribute
 * (comment, tags, quarantine, other programs').  They become user.*
 * attributes; where the volume has none, or one value does not fit (E2BIG,
 * ENOSPC), everything stays in the item's "._" sidecar, which is how a Mac
 * keeps it on such a volume.  Any other failure is reported.
 */
static BOOL
apply_appledouble(NSData *ad, NSString *destPath, NSString **why)
{
  GSAppleDouble *parsed = [[[GSAppleDouble alloc] initWithData: ad] autorelease];
  if (parsed == nil)
    {
      *why = @"not a valid AppleDouble";
      return NO;
    }

  if (appledouble_is_empty(parsed))
    return YES;

  NSMutableDictionary *items = [NSMutableDictionary dictionary];
  if ([parsed hasFinderInfo])
    [items setObject: [parsed finderInfo] forKey: @"user.com.apple.FinderInfo"];
  if ([parsed hasResourceFork] && [[parsed resourceFork] length] > 0)
    [items setObject: [parsed resourceFork]
              forKey: @"user.com.apple.ResourceFork"];
  NSDictionary *attrs = [parsed extendedAttributes];
  for (NSString *name in attrs)
    {
      NSData *value = [attrs objectForKey: name];
      /* The Mac's own attribute holds the plain value; "q/" is only the
       * sidecar's spelling. */
      if ([name isEqualToString: @"com.apple.quarantine"])
        value = [GSFileMetadata plainQuarantine: value];
      [items setObject: value
                forKey: [@"user." stringByAppendingString: name]];
    }

  NSString *sidecar = [GSFileMetadata sidecarPathForFilePath: destPath];
  const char *cdst = GW_FSREP(destPath);
  struct stat st;
  BOOL widened = NO;
  BOOL inSidecar = NO;
  NSMutableArray *written = [NSMutableArray array];

  /* Where a Mac reads the volume it sees only "._" files, so the companion
   * stays exactly that. */
  NSInteger appleDouble = [GSFileMetadata storesMetadataInAppleDoubleAtPath: destPath];
  if (appleDouble < 0)
    {
      *why = [NSString stringWithFormat: @"cannot examine the filesystem: %s",
                strerror(errno)];
      return NO;
    }

  /* Setting a user attribute needs write permission, an archive may well
   * hold a read-only file. */
  if (stat(cdst, &st) == 0 && (st.st_mode & S_IWUSR) == 0
      && chmod(cdst, st.st_mode | S_IWUSR) == 0)
    widened = YES;

  int support = appleDouble == 1 ? 0 : gs_xattr_supported(cdst);
  if (support < 0)
    {
      *why = [NSString stringWithFormat: @"cannot tell whether attributes are supported: %s",
                strerror(errno)];
      if (widened)
        chmod(cdst, st.st_mode & 07777);
      return NO;
    }
  inSidecar = (support == 0);
  for (NSString *name in items)
    {
      if (inSidecar)
        break;
      NSData *value = [items objectForKey: name];
      /* gs_setxattr refuses a NULL value pointer; an empty value needs one. */
      const void *bytes = [value length] ? [value bytes] : "";
      if (gs_setxattr(cdst, [name UTF8String], bytes, [value length], 0) == 0)
        {
          [written addObject: name];
          continue;
        }
      if (errno == E2BIG || errno == ENOSPC)
        {
          for (NSString *done in written)
            gs_removexattr(cdst, [done UTF8String]);
          inSidecar = YES;
          break;
        }
      *why = [NSString stringWithFormat: @"cannot set %@: %s", name, strerror(errno)];
      if (widened)
        chmod(cdst, st.st_mode & 07777);
      return NO;
    }
  if (widened)
    chmod(cdst, st.st_mode & 07777);

  if (inSidecar && ![ad writeToFile: sidecar atomically: YES])
    {
      *why = [[GSFileMetadata sidecarWriteErrorAtPath: sidecar code: errno]
               localizedDescription];
      return NO;
    }
  [GSFileMetadata invalidateCachedMetadataForPath: destPath];
  return YES;
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

  const char *outpath = GW_FSREP(outputPath);
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

  /* Only a folder this call creates may take the metadata of the archive's
   * stripped top folder; a folder that was there is the user's. */
  BOOL createdDest = ![fm fileExistsAtPath: destDir];
  if (createdDest)
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

  archive_read_support_format_all(a);
  archive_read_support_filter_all(a);

  const char *cpath = GW_FSREP(archivePath);
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
   * First pass:
   *   - Read __MACOSX entries, collecting AppleDouble metadata.
   *   - Collect all regular entry paths to detect a common top-level
   *     directory that can be stripped (avoids double-nesting archives
   *     like "archive/archive/file.txt").
   */
  NSMutableDictionary *metadataDict = [NSMutableDictionary dictionary];
  NSMutableArray *entryPaths = [NSMutableArray array];
  NSMutableSet *companions = [NSMutableSet set];
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

      NSString *lastName = [epath lastPathComponent];
      int64_t esize = archive_entry_size(entry);

      if ([epath hasPrefix: @"__MACOSX/"])
        {
          /* Finder's "Compress": metadata in a tree of its own. */
          NSString *real = real_path_from_macosx(epath);
          if (real && esize > 0 && esize <= MAX_METADATA_ENTRY_SIZE)
            {
              NSMutableData *ad = [NSMutableData dataWithLength: (NSUInteger)esize];
              ssize_t nread = archive_read_data(a, [ad mutableBytes], [ad length]);
              if (nread == esize && is_appledouble(ad))
                [metadataDict setObject: ad forKey: real];
            }
          archive_read_data_skip(a);
        }
      else if ([lastName hasPrefix: @"._"] && [lastName length] > 2
               && esize > 0 && esize <= MAX_METADATA_ENTRY_SIZE)
        {
          /* tar, ditto -c and cpio: the companion sits beside its item. */
          NSMutableData *ad = [NSMutableData dataWithLength: (NSUInteger)esize];
          ssize_t nread = archive_read_data(a, [ad mutableBytes], [ad length]);
          if (nread == esize && is_appledouble(ad))
            {
              [metadataDict setObject: ad forKey: real_path_from_companion(epath)];
              [companions addObject: epath];
            }
          else
            [entryPaths addObject: epath];
          archive_read_data_skip(a);
        }
      else
        {
          [entryPaths addObject: epath];
          archive_read_data_skip(a);
        }
    }

  if (!ok)
    {
      archive_read_close(a);
      archive_read_free(a);
      return NO;
    }

  /* Determine common top-level prefix to strip.
   * If all entries share the same first path component (e.g. "archive/"),
   * that component is stripped so the user gets files directly in destDir
   * rather than destDir/archive/ …. */
  NSString *stripPrefix = nil;
  if ([entryPaths count] > 1)
    {
      NSString *common = nil;
      for (NSString *p in entryPaths)
        {
          NSString *top = [[p pathComponents] objectAtIndex: 0];
          if (top == nil) { common = nil; break; }
          if (common == nil)
            common = top;
          else if (![common isEqualToString: top])
            { common = nil; break; }
        }
      if (common)
        stripPrefix = [common stringByAppendingString: @"/"];
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
  archive_read_support_format_all(a);
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
      if (epath == nil) { archive_read_data_skip(a); continue; }

      /* Skip metadata entries on second pass */
      if ([epath hasPrefix: @"__MACOSX/"] || [companions containsObject: epath])
        {
          archive_read_data_skip(a);
          continue;
        }

      /* Strip common top-level prefix if detected */
      NSString *relpath = epath;
      if (stripPrefix && [relpath hasPrefix: stripPrefix])
        relpath = [relpath substringFromIndex: [stripPrefix length]];

      NSString *destPath = [destDir stringByAppendingPathComponent: relpath];

      /* Zip-Slip defense */
      if (!path_is_within(canonicalDest, destPath))
        {
          archive_read_data_skip(a);
          continue;
        }

      /* A .DS_Store is the view settings of the folder it sits in. Where
       * the folder already has one, those are the user's, not the archive's. */
      if ([[destPath lastPathComponent] isEqualToString: @".DS_Store"]
          && [fm fileExistsAtPath: destPath])
        {
          archive_read_data_skip(a);
          continue;
        }

      mode_t mode = archive_entry_mode(entry);
      mode_t filetype = mode & S_IFMT;

      if (filetype == S_IFDIR)
        {
          if (![fm fileExistsAtPath: destPath])
            {
              NSDictionary *attrs = nil;
              if (mode & ACCESSPERMS)
                attrs = @{NSFilePosixPermissions: @(mode & ACCESSPERMS)};
              [fm createDirectoryAtPath: destPath attributes: attrs];
            }
          archive_read_data_skip(a);
        }
      else if (filetype == S_IFREG)
        {
          NSString *parent = [destPath stringByDeletingLastPathComponent];
          if (![fm fileExistsAtPath: parent])
            [fm createDirectoryAtPath: parent attributes: nil];

          mode_t openmode = (mode & ACCESSPERMS) ? (mode & ACCESSPERMS) : 0644;
          int fd = open(GW_FSREP(destPath),
                        O_WRONLY | O_CREAT | O_TRUNC, openmode);
          if (fd >= 0)
            {
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

      /* Apply metadata from pass 1.  A directory entry may end in "/",
       * its companion's key does not.  With a stripped top folder the
       * destination stands for it and gets its label (relpath is empty),
       * but only when we created it. */
      NSString *key = epath;
      while ([key length] > 1 && [key hasSuffix: @"/"])
        key = [key substringToIndex: [key length] - 1];
      NSData *ad = ([relpath length] > 0 || createdDest)
        ? [metadataDict objectForKey: key] : nil;
      if (ad)
        {
          NSString *why = nil;
          if (!apply_appledouble(ad, destPath, &why))
            {
              if (error)
                *error = [NSError errorWithDomain: @"GWMetaArchive" code: 17
                  userInfo: @{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat: @"Cannot apply metadata to %@: %@",
                      destPath, why]}];
              ok = NO;
              break;
            }
        }
    }

  archive_read_close(a);
  archive_read_free(a);
  return ok;
}

+ (BOOL)isArchiveExtension:(NSString *)ext
{
  if ([ext length] == 0)
    return NO;

  static NSSet *archiveExts = nil;
  if (!archiveExts)
    {
      archiveExts = [[NSSet alloc] initWithObjects:
        @"zip", @"cbz",
        @"tar", @"tgz", @"tar.gz", @"gz", @"gzip",
        @"bz2", @"bzip2", @"tbz2", @"tar.bz2",
        @"xz", @"txz", @"tar.xz",
        @"lzma", @"tlz", @"tar.lzma",
        @"7z", @"rar", @"cab", @"iso",
        @"lzh", @"lha", @"ar", @"cpio", @"zst",
        nil];
    }
  return [archiveExts containsObject: [ext lowercaseString]];
}

@end
