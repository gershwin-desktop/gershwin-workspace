/* GWMetadataCopier.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWMetadataCopier.h"
#import "GSAppleDouble.h"
#import "GWMetaXattr.h"
#import "GSFileMetadata.h"
#import "DSStore.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <string.h>
#include <sys/stat.h>

/* The wrapper in GWMetaXattr takes Linux-style names, so every attribute we
 * handle lives in the "user" namespace.  Other namespaces (security.*,
 * system.*) belong to the kernel and are not ours to copy. */
static NSString * const GWUserNamespace = @"user.";

/* AppleDouble keeps these two outside the ATTR blob, in entries 9 and 2. */
static NSString * const GWFinderInfoName = @"com.apple.FinderInfo";
static NSString * const GWResourceForkName = @"com.apple.ResourceFork";
#define GW_FINDERINFO_SIZE 32

static NSError *
copyError(NSString *path, NSString *what, int code)
{
  NSString *reason = [NSString stringWithFormat: @"%@: %s", what,
                       code ? strerror(code) : "unreadable"];
  return [NSError errorWithDomain: NSPOSIXErrorDomain
                             code: code
                         userInfo: @{ NSFilePathErrorKey: path,
                                      NSLocalizedDescriptionKey: reason }];
}

/* Windows has no lstat() and no symbolic links worth skipping here, so a
 * plain stat() answers the same question there. */
#if defined(_WIN32)
#define gw_lstat(p, st) stat((p), (st))
#else
#define gw_lstat(p, st) lstat((p), (st))
#endif

@implementation GWMetadataCopier

@synthesize xattrSupportProbe = _xattrSupportProbe;
@synthesize xattrSetter = _xattrSetter;

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _xattrSupportProbe = [^int(NSString *path) {
        return gs_xattr_supported(GW_FSREP(path));
      } copy];
      _xattrSetter = [^int(NSString *path, NSString *name, NSData *value) {
        /* gs_setxattr refuses a NULL value, an empty one needs a pointer. */
        const void *bytes = [value length] ? [value bytes] : "";
        return gs_setxattr(GW_FSREP(path), [name UTF8String],
                           bytes, [value length], 0) == 0 ? 0 : errno;
      } copy];
    }
  return self;
}

- (void)dealloc
{
  DESTROY(_xattrSupportProbe);
  DESTROY(_xattrSetter);
  [super dealloc];
}

+ (NSString *)sidecarPathForPath:(NSString *)path
{
  return [[path stringByDeletingLastPathComponent]
    stringByAppendingPathComponent:
      [@"._" stringByAppendingString: [path lastPathComponent]]];
}

/* All attributes of an item as name (without "user.") -> value; nil with
 * *error set when one cannot be read. */
- (NSDictionary *)_attributesAtPath:(NSString *)path error:(NSError **)error
{
  const char *cpath = GW_FSREP(path);
  gs_xattr_list_t *list = gs_xattr_list_for_path(cpath,
                                                 [GWUserNamespace UTF8String]);
  NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
  int i;

  if (list == NULL)
    {
      if (error)
        *error = copyError(path, @"cannot list extended attributes", errno);
      return nil;
    }
  for (i = 0; i < list->count; i++)
    {
      NSString *name = [NSString stringWithUTF8String: list->entries[i].name];
      NSData *value = [NSData dataWithBytes: list->entries[i].value
                                     length: list->entries[i].size];

      if (name == nil)
        {
          /* A name that is not UTF-8 cannot travel in a sidecar and must
           * not be silently skipped. */
          gs_xattr_list_free(list);
          if (error)
            *error = copyError(path, @"extended attribute name is not UTF-8",
                               EILSEQ);
          return nil;
        }
      [attrs setObject: value
                forKey: [name substringFromIndex: [GWUserNamespace length]]];
    }
  gs_xattr_list_free(list);
  return attrs;
}

/* Result of storing the attributes on the destination. */
typedef NS_ENUM(NSInteger, GWAttrStore) {
  GWAttrStoreDone,
  GWAttrStoreTooBig,   /* nothing was left on the item; use the sidecar */
  GWAttrStoreFailed
};

- (GWAttrStore)_setAttributes:(NSDictionary *)attrs
                       atPath:(NSString *)path
                        error:(NSError **)error
{
  const char *cpath = GW_FSREP(path);
  NSMutableArray *written = [NSMutableArray array];

  for (NSString *name in attrs)
    {
      NSData *value = [attrs objectForKey: name];
      NSString *full = [GWUserNamespace stringByAppendingString: name];
      int err = _xattrSetter(path, full, value);

      if (err == 0)
        {
          [written addObject: full];
          continue;
        }
      /* ext4 caps one attribute at about a block, other filesystems have
       * similar limits; GSFileMetadata already moves such metadata into the
       * sidecar.  E2BIG (Linux) and ENOSPC (Linux, FreeBSD, OpenBSD) mean
       * "does not fit here"; every other error is a real failure.  The
       * attributes already stored are removed so that the item never has a
       * partial set that disagrees with its sidecar. */
      if (err == E2BIG || err == ENOSPC)
        {
          for (NSString *done in written)
            gs_removexattr(cpath, [done UTF8String]);
          return GWAttrStoreTooBig;
        }
      if (error)
        *error = copyError(path,
          [NSString stringWithFormat: @"cannot set %@", name], err);
      return GWAttrStoreFailed;
    }
  return GWAttrStoreDone;
}

/* Everything goes into the sidecar, the way Mac OS X would have written it:
 * FinderInfo and resource fork in their own entries, the rest as ATTR
 * records.  The source's own sidecar, if any, is the base so that what
 * only it knows stays. */
- (BOOL)_writeSidecarAtPath:(NSString *)sidecar
                 attributes:(NSDictionary *)attrs
                   baseData:(NSData *)base
                      error:(NSError **)error
{
  GSAppleDouble *ad = nil;
  NSData *out;

  if (base != nil)
    {
      ad = [[GSAppleDouble alloc] initWithData: base];
      if (ad == nil)
        {
          if (error)
            *error = copyError(sidecar, @"source sidecar is not AppleDouble",
                               EINVAL);
          return NO;
        }
    }
  else
    ad = [[GSAppleDouble alloc] init];

  for (NSString *name in attrs)
    {
      NSData *value = [attrs objectForKey: name];

      if ([name isEqual: GWFinderInfoName]
          && [value length] == GW_FINDERINFO_SIZE)
        [ad setFinderInfo: value];
      else if ([name isEqual: GWResourceForkName])
        [ad setResourceFork: value];
      else
        [ad setXattr: value forKey: name];
    }
  out = [ad appleDoubleData];
  DESTROY(ad);

  if (out == nil)
    return YES;
  if (![out writeToFile: sidecar atomically: YES])
    {
      if (error)
        *error = copyError(sidecar, @"cannot write sidecar", errno);
      return NO;
    }
  return YES;
}

- (BOOL)copyMetadataFromPath:(NSString *)srcPath
                      toPath:(NSString *)dstPath
                       error:(NSError **)error
{
  struct stat st;
  NSString *srcSidecar = [[self class] sidecarPathForPath: srcPath];
  NSString *dstSidecar = [[self class] sidecarPathForPath: dstPath];
  NSData *sidecarData;
  NSDictionary *attrs;
  const char *cdst = GW_FSREP(dstPath);
  struct stat dst;
  BOOL widened = NO;
  BOOL ok;

  if (gw_lstat(GW_FSREP(srcPath), &st) != 0)
    {
      if (error)
        *error = copyError(srcPath, @"cannot stat", errno);
      return NO;
    }
  /* user.* attributes cannot live on links or device nodes. */
  if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))
    return YES;

  sidecarData = [NSData dataWithContentsOfFile: srcSidecar];
  attrs = [self _attributesAtPath: srcPath error: error];
  if (attrs == nil)
    return NO;
  if ([attrs count] == 0 && sidecarData == nil)
    return YES;

  if (stat(cdst, &dst) != 0)
    {
      if (error)
        *error = copyError(dstPath, @"cannot stat", errno);
      return NO;
    }
  /* Writing a user attribute, and probing for support, needs write
   * permission on the item; a copy of a read-only file is read-only. */
  if ((dst.st_mode & S_IWUSR) == 0)
    {
      if (chmod(cdst, dst.st_mode | S_IWUSR) != 0)
        {
          if (error)
            *error = copyError(dstPath, @"cannot make writable", errno);
          return NO;
        }
      widened = YES;
    }

  int support = _xattrSupportProbe(dstPath);

  if (support < 0)
    {
      /* Neither "supported" nor "not supported": do not guess. */
      if (error)
        *error = copyError(dstPath, @"cannot tell whether extended attributes are supported",
                           errno);
      ok = NO;
    }
  else
    {
      GWAttrStore stored = GWAttrStoreTooBig;

      if (support == 1)
        stored = [self _setAttributes: attrs atPath: dstPath error: error];
      if (stored == GWAttrStoreFailed)
        ok = NO;
      else if (stored == GWAttrStoreDone)
        {
          ok = YES;
          if (sidecarData != nil
              && ![sidecarData writeToFile: dstSidecar atomically: YES])
            {
              if (error)
                *error = copyError(dstSidecar, @"cannot write sidecar", errno);
              ok = NO;
            }
        }
      else
        ok = [self _writeSidecarAtPath: dstSidecar
                            attributes: attrs
                              baseData: sidecarData
                                 error: error];
    }

  if (widened)
    chmod(cdst, dst.st_mode & 07777);
  return ok;
}

- (BOOL)copyMetadataOfTreeAtPath:(NSString *)srcPath
                          toPath:(NSString *)dstPath
                           error:(NSError **)error
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *en;
  NSString *rel;

  if (![self copyMetadataFromPath: srcPath toPath: dstPath error: error])
    return NO;

  en = [fm enumeratorAtPath: srcPath];
  while ((rel = [en nextObject]) != nil)
    {
      if (![self copyMetadataFromPath: [srcPath stringByAppendingPathComponent: rel]
                               toPath: [dstPath stringByAppendingPathComponent: rel]
                                error: error])
        return NO;
    }
  return YES;
}

- (BOOL)isRenameFromPath:(NSString *)srcPath toPath:(NSString *)dstPath
{
  struct stat src, dstDir;

  if (gw_lstat(GW_FSREP(srcPath), &src) != 0
      || stat(GW_FSREP([dstPath stringByDeletingLastPathComponent]), &dstDir) != 0)
    return NO;
  return src.st_dev == dstDir.st_dev;
}

/* Finder 10.6 shows a comment only when the folder's own .DS_Store has the
 * item's cmmt record; the attribute alone is not enough.  The record is
 * keyed by name, so every copy, duplicate or move to a new name or folder
 * needs its own. */
- (void)_storeCommentRecordForItemAtPath:(NSString *)path
                                   error:(NSError **)error
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];

  if ([md.finderComment length] == 0)
    return;
  [DSStore setComment: md.finderComment forItemAtPath: path error: error];
}

/* A copied folder holds more items than the one dropped: each needs its
 * record in the .DS_Store of the folder it now sits in (the copied store, if
 * any, only has the records its source folder had). */
- (void)_storeCommentRecordsOfTreeAtPath:(NSString *)path
                                   error:(NSError **)error
{
  NSDirectoryEnumerator *en;
  NSString *rel;
  NSError *failure = nil;

  [self _storeCommentRecordForItemAtPath: path error: &failure];
  en = [[NSFileManager defaultManager] enumeratorAtPath: path];
  while (failure == nil && (rel = [en nextObject]) != nil)
    {
      if ([[rel lastPathComponent] isEqual: @".DS_Store"])
        continue;
      [self _storeCommentRecordForItemAtPath:
              [path stringByAppendingPathComponent: rel]
                                       error: &failure];
    }
  if (failure != nil && error)
    *error = failure;
}

/* The record is keyed by the old name in the old folder; left behind it
 * would show the comment again on any new item of that name. */
- (void)_dropCommentRecordOfMovedItemAtPath:(NSString *)oldPath
                                    toPath:(NSString *)newPath
                                      error:(NSError **)error
{
  if ([oldPath isEqual: newPath])
    return;
  [DSStore setComment: @"" forItemAtPath: oldPath error: error];
}

- (BOOL)copyItemAtPath:(NSString *)srcPath
                toPath:(NSString *)dstPath
               handler:(id)handler
         metadataError:(NSError **)metadataError
{
  if (![[NSFileManager defaultManager] copyPath: srcPath
                                         toPath: dstPath
                                        handler: handler])
    return NO;
  if ([self copyMetadataOfTreeAtPath: srcPath
                              toPath: dstPath
                               error: metadataError])
    [self _storeCommentRecordsOfTreeAtPath: dstPath error: metadataError];
  return YES;
}

- (BOOL)moveItemAtPath:(NSString *)srcPath
                toPath:(NSString *)dstPath
               handler:(id)handler
         metadataError:(NSError **)metadataError
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *srcSidecar = [[self class] sidecarPathForPath: srcPath];
  NSString *dstSidecar = [[self class] sidecarPathForPath: dstPath];

  if ([self isRenameFromPath: srcPath toPath: dstPath])
    {
      if (![fm movePath: srcPath toPath: dstPath handler: handler])
        return NO;
      if ([fm fileExistsAtPath: srcSidecar])
        [fm movePath: srcSidecar toPath: dstSidecar handler: handler];
      [self _storeCommentRecordForItemAtPath: dstPath error: metadataError];
      [self _dropCommentRecordOfMovedItemAtPath: srcPath
                                         toPath: dstPath
                                          error: metadataError];
      return YES;
    }

  /* Across filesystems nothing travels by itself.  The source is the only
   * complete copy until the destination has everything. */
  NSError *error = nil;

  if (![self copyItemAtPath: srcPath
                     toPath: dstPath
                    handler: handler
              metadataError: &error])
    return NO;
  if (error != nil)
    {
      if (metadataError)
        *metadataError = error;
      return NO;
    }
  if (![fm removeFileAtPath: srcPath handler: handler])
    return NO;
  if ([fm fileExistsAtPath: srcSidecar])
    [fm removeFileAtPath: srcSidecar handler: handler];
  [self _dropCommentRecordOfMovedItemAtPath: srcPath
                                     toPath: dstPath
                                      error: metadataError];
  return YES;
}

@end
