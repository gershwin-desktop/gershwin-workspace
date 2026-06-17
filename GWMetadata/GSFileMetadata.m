/* GSFileMetadata.m
 *
 * Metadata model for Mac OS / macOS Finder metadata on GNUstep.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GSFileMetadata.h"
#import "GSAppleDouble.h"
#import "GWMetaXattr.h"
#import <GNUstepBase/GNUstep.h>
#import <string.h>

/*
 * Marker used for "no position" in FinderInfo fdLocation.
 * When both v and h are -1 (0xFFFF) it means "not positioned".
 */
#define GS_NO_ICON_POSITION  ((int16_t)(-1))

/*
 * Convert a big-endian uint32 (FourCharCode) to host byte order.
 */
static inline uint32_t
be32_to_host(const uint8_t *bytes)
{
  return ((uint32_t)bytes[0] << 24)
       | ((uint32_t)bytes[1] << 16)
       | ((uint32_t)bytes[2] << 8)
       |  (uint32_t)bytes[3];
}

/*
 * Convert a big-endian uint16 to host byte order.
 */
static inline uint16_t
be16_to_host(const uint8_t *bytes)
{
  return ((uint16_t)bytes[0] << 8)
       |  (uint16_t)bytes[1];
}

/*
 * Convert a host uint32 to big-endian bytes
 */
static inline void
host_to_be32(uint8_t *bytes, uint32_t value)
{
  bytes[0] = (value >> 24) & 0xFF;
  bytes[1] = (value >> 16) & 0xFF;
  bytes[2] = (value >> 8)  & 0xFF;
  bytes[3] =  value        & 0xFF;
}

/*
 * Convert a host uint16 to big-endian bytes
 */
static inline void
host_to_be16(uint8_t *bytes, uint16_t value)
{
  bytes[0] = (value >> 8) & 0xFF;
  bytes[1] =  value       & 0xFF;
}

@implementation GSFileMetadata

@synthesize finderInfo = _finderInfo;
@synthesize resourceFork = _resourceFork;
@synthesize finderComment = _finderComment;
@synthesize forceSidecar = _forceSidecar;

/* =================================================================
 * Init / Dealloc
 * ================================================================= */

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _parsed.valid = NO;
      _forceSidecar = NO;
    }
  return self;
}

- (void)dealloc
{
  DESTROY(_finderInfo);
  DESTROY(_resourceFork);
  DESTROY(_finderComment);
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  GSFileMetadata *copy = [[GSFileMetadata allocWithZone: zone] init];
  [copy setFinderInfo: _finderInfo];
  [copy setResourceFork: _resourceFork];
  [copy setFinderComment: _finderComment];
  copy.forceSidecar = _forceSidecar;
  return copy;
}

/* =================================================================
 * Parsing
 * ================================================================= */

- (void)invalidateParsed
{
  _parsed.valid = NO;
}

- (void)parseIfNeeded
{
  if (_parsed.valid)
    return;

  /* Defaults */
  _parsed.typeCode = 0;
  _parsed.creatorCode = 0;
  _parsed.flags = 0;
  _parsed.iconPosition = NSMakePoint(-1, -1);
  _parsed.labelNumber = 0;

  if ([_finderInfo length] >= 16)
    {
      const uint8_t *bytes = [_finderInfo bytes];

      _parsed.typeCode = be32_to_host(bytes);
      _parsed.creatorCode = be32_to_host(bytes + 4);
      _parsed.flags = be16_to_host(bytes + 8);

      /* fdLocation: int16 v (vertical) at bytes 10-11,
       *            int16 h (horizontal) at bytes 12-13.
       * Top-left origin, icon-center coordinates.
       * https://developer.apple.com/library/archive/technotes/tb/tb_42.html */
      int16_t v = (int16_t)be16_to_host(bytes + 10);
      int16_t h = (int16_t)be16_to_host(bytes + 12);
      _parsed.iconPosition = NSMakePoint(h, v);

      /* Label is encoded in fdFlags bits 1-3 */
      _parsed.labelNumber = (_parsed.flags >> 1) & 0x7;
    }

  _parsed.valid = YES;
}

/* =================================================================
 * Properties - Setting invalidates cache
 * ================================================================= */

- (void)setFinderInfo:(NSData *)data
{
  ASSIGN(_finderInfo, data);
  [self invalidateParsed];
}

/* =================================================================
 * Convenient property accessors (read)
 * ================================================================= */

- (GSOType)typeCode
{
  [self parseIfNeeded];
  return _parsed.typeCode;
}

- (GSOType)creatorCode
{
  [self parseIfNeeded];
  return _parsed.creatorCode;
}

- (uint16_t)finderFlags
{
  [self parseIfNeeded];
  return _parsed.flags;
}

- (BOOL)isLocked
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderIsNameLocked) != 0;
}

- (BOOL)hasCustomIcon
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderHasCustomIcon) != 0;
}

- (BOOL)isInvisible
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderIsInvisible) != 0;
}

- (BOOL)isAlias
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderIsAlias) != 0;
}

- (BOOL)isStationery
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderIsStationery) != 0;
}

- (BOOL)hasBundle
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderHasBundle) != 0;
}

- (NSPoint)iconPosition
{
  [self parseIfNeeded];
  return _parsed.iconPosition;
}

- (NSInteger)labelNumber
{
  [self parseIfNeeded];
  return _parsed.labelNumber;
}

/* =================================================================
 * Convenient property accessors (write)
 * ================================================================= */

- (void)setTypeCode:(GSOType)code
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 4)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be32(bytes, code);
      _parsed.typeCode = code;
    }
}

- (void)setCreatorCode:(GSOType)code
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 8)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be32(bytes + 4, code);
      _parsed.creatorCode = code;
    }
}

- (void)setFinderFlags:(uint16_t)flags
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 10)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be16(bytes + 8, flags);
      _parsed.flags = flags;
      /* Recompute label from flags */
      _parsed.labelNumber = (flags >> 1) & 0x7;
    }
}

- (void)setLocked:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsNameLocked;
  else
    flags &= ~GSFileFinderIsNameLocked;
  [self setFinderFlags: flags];
}

- (void)setCustomIcon:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderHasCustomIcon;
  else
    flags &= ~GSFileFinderHasCustomIcon;
  [self setFinderFlags: flags];
}

- (void)setInvisible:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsInvisible;
  else
    flags &= ~GSFileFinderIsInvisible;
  [self setFinderFlags: flags];
}

- (void)setAlias:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsAlias;
  else
    flags &= ~GSFileFinderIsAlias;
  [self setFinderFlags: flags];
}

- (void)setStationery:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsStationery;
  else
    flags &= ~GSFileFinderIsStationery;
  [self setFinderFlags: flags];
}

- (void)setHasBundle:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderHasBundle;
  else
    flags &= ~GSFileFinderHasBundle;
  [self setFinderFlags: flags];
}

- (void)setIconPosition:(NSPoint)position
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 14)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be16(bytes + 10, (uint16_t)(int16_t)position.y);
      host_to_be16(bytes + 12, (uint16_t)(int16_t)position.x);
      _parsed.iconPosition = position;
    }
}

- (void)setLabelNumber:(NSInteger)label
{
  if (label < 0 || label > 7)
    label = 0;

  uint16_t flags = [self finderFlags];
  /* Clear the label bits (1-3), then set new value */
  flags &= ~GSFileFinderColorBits;
  flags |= (label << 1);
  [self setFinderFlags: flags];
  _parsed.labelNumber = label;
}

/* =================================================================
 * Internal: ensure we have a mutable 32-byte FinderInfo buffer
 * ================================================================= */

- (void)createFinderInfoIfNeeded
{
  if (_finderInfo == nil)
    {
      /* Create a zero-filled 32-byte FinderInfo */
      uint8_t zeros[32] = { 0 };
      _finderInfo = [[NSMutableData alloc] initWithBytes: zeros length: 32];
    }
  else if (![_finderInfo isKindOfClass: [NSMutableData class]]
           || [_finderInfo length] < 32)
    {
      /* Make it mutable and pad to 32 bytes */
      NSMutableData *md = nil;
      if ([_finderInfo isKindOfClass: [NSMutableData class]])
        md = (NSMutableData *)_finderInfo;
      else
        md = [[_finderInfo mutableCopy] autorelease];

      if ([md length] < 32)
        {
          [md setLength: 32];
          /* Zero out the new bytes */
          memset((uint8_t *)[md mutableBytes] + [_finderInfo length], 0,
                 32 - [_finderInfo length]);
        }

      ASSIGN(_finderInfo, md);
    }
}

/* =================================================================
 * Read from file
 * ================================================================= */

+ (GSFileMetadata *)metadataForFileAtPath:(NSString *)path
{
  return [self metadataForFileAtPath: path forceSidecar: NO];
}

+ (GSFileMetadata *)metadataForFileAtPath:(NSString *)path
                             forceSidecar:(BOOL)forceSidecar
{
  if (!path || [path length] == 0)
    return nil;

  GSFileMetadata *md = [[[self alloc] init] autorelease];

  if (forceSidecar)
    {
      /* Read only from sidecar file */
      return [md readSidecarForPath: path] ? md : nil;
    }

  /* Try xattrs first */
  BOOL found = NO;

  /* Read FinderInfo via xattr */
  {
    const char *cpath = [path fileSystemRepresentation];
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_FINDERINFO UTF8String],
                                NULL, 0);
    if (size >= 32)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_FINDERINFO UTF8String],
                    [data mutableBytes], size);
        md.finderInfo = data;
        found = YES;
      }
  }

  /* Read ResourceFork via xattr */
  {
    const char *cpath = [path fileSystemRepresentation];
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_RESOURCEFORK UTF8String],
                                NULL, 0);
    if (size > 0)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_RESOURCEFORK UTF8String],
                    [data mutableBytes], size);
        md.resourceFork = data;
        found = YES;
      }
  }

  /* Read Finder comment via xattr */
  {
    const char *cpath = [path fileSystemRepresentation];
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_FINDERCOMMENT UTF8String],
                                NULL, 0);
    if (size > 0)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String],
                    [data mutableBytes], size);
        NSString *comment = [[NSString alloc] initWithData: data
                                                  encoding: NSUTF8StringEncoding];
        if (comment)
          {
            md.finderComment = comment;
            RELEASE(comment);
          }
        found = YES;
      }
  }

  /* If nothing found via xattrs, try sidecar */
  if (!found)
    {
      if ([md readSidecarForPath: path])
        found = YES;
    }

  return found ? md : nil;
}

/* =================================================================
 * Write to file
 * ================================================================= */

- (BOOL)writeToFileAtPath:(NSString *)path error:(NSError **)error
{
  if (!path || [path length] == 0)
    {
      if (error)
        *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                     code: NSFileNoSuchFileError
                                 userInfo: nil];
      return NO;
    }

  if (_forceSidecar)
    return [self writeSidecarToFileAtPath: path error: error];

  const char *cpath = [path fileSystemRepresentation];
  BOOL success = YES;

  /* Write FinderInfo */
  if (_finderInfo && [_finderInfo length] >= 32)
    {
      if (gs_setxattr(cpath, [GSXATTR_FINDERINFO UTF8String],
                       [_finderInfo bytes], [_finderInfo length],
                       0) != 0)
        {
          /* Xattr failed, fall back to sidecar */
          return [self writeSidecarToFileAtPath: path error: error];
        }
    }

  /* Write ResourceFork */
  if (_resourceFork && [_resourceFork length] > 0)
    {
      if (gs_setxattr(cpath, [GSXATTR_RESOURCEFORK UTF8String],
                       [_resourceFork bytes], [_resourceFork length],
                       0) != 0)
        {
          /* Clean up the FinderInfo we just wrote */
          gs_removexattr(cpath, [GSXATTR_FINDERINFO UTF8String]);
          return [self writeSidecarToFileAtPath: path error: error];
        }
    }

  /* Write Finder comment */
  if (_finderComment && [_finderComment length] > 0)
    {
      NSData *commentData = [_finderComment dataUsingEncoding: NSUTF8StringEncoding];
      if (gs_setxattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String],
                       [commentData bytes], [commentData length],
                       0) != 0)
        {
          /* Non-fatal: comment couldn't be written, but main metadata is OK */
          NSDebugLLog(@"gwspace", @"GSFileMetadata: Could not write comment xattr for %@", path);
        }
    }

  /* Remove sidecar file if it exists (we're using xattrs now) */
  NSString *sidecarPath = [[self class] sidecarPathForFilePath: path];
  if ([[NSFileManager defaultManager] fileExistsAtPath: sidecarPath])
    {
      [[NSFileManager defaultManager] removeFileAtPath: sidecarPath
                                               handler: nil];
    }

  return success;
}

- (BOOL)writeSidecarToFileAtPath:(NSString *)path error:(NSError **)error
{
  NSString *sidecarPath = [[self class] sidecarPathForFilePath: path];

  /* Create AppleDouble blob */
  NSData *appleDoubleData = [self appleDoubleData];
  if (!appleDoubleData)
    {
      /* No metadata to write: remove sidecar if it exists */
      if ([[NSFileManager defaultManager] fileExistsAtPath: sidecarPath])
        {
          [[NSFileManager defaultManager] removeFileAtPath: sidecarPath
                                                   handler: nil];
        }
      return YES;
    }

  /* Write the sidecar file */
  BOOL written = [[NSFileManager defaultManager] createFileAtPath: sidecarPath
                                                         contents: appleDoubleData
                                                       attributes: nil];
  if (!written && error)
    {
      *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                   code: NSFileWriteUnknownError
                               userInfo: @{
        NSFilePathErrorKey: sidecarPath,
        NSLocalizedDescriptionKey: @"Could not write AppleDouble sidecar file"
      }];
    }

  return written;
}

- (BOOL)readSidecarForPath:(NSString *)path
{
  NSString *sidecarPath = [[self class] sidecarPathForFilePath: path];
  NSData *sidecarData = [NSData dataWithContentsOfFile: sidecarPath];
  if (!sidecarData)
    return NO;

  GSAppleDouble *ad = [[GSAppleDouble alloc] initWithData: sidecarData];
  if (!ad)
    return NO;

  if ([ad hasFinderInfo])
    self.finderInfo = [ad finderInfo];

  if ([ad hasResourceFork])
    self.resourceFork = [ad resourceFork];

  DESTROY(ad);
  return YES;
}

/* =================================================================
 * AppleDouble conversion
 * ================================================================= */

- (NSData *)appleDoubleData
{
  GSAppleDouble *ad = [[GSAppleDouble alloc] init];

  if (_finderInfo && [_finderInfo length] > 0)
    [ad setFinderInfo: _finderInfo];

  if (_resourceFork && [_resourceFork length] > 0)
    [ad setResourceFork: _resourceFork];

  NSData *result = [ad appleDoubleData];
  DESTROY(ad);
  return result;
}

+ (GSFileMetadata *)metadataFromAppleDoubleData:(NSData *)data
{
  if (!data || [data length] < APPLEDOUBLE_HEADER_SIZE)
    return nil;

  GSAppleDouble *ad = [[GSAppleDouble alloc] initWithData: data];
  if (!ad)
    return nil;

  GSFileMetadata *md = [[[self alloc] init] autorelease];

  if ([ad hasFinderInfo])
    md.finderInfo = [ad finderInfo];
  if ([ad hasResourceFork])
    md.resourceFork = [ad resourceFork];

  DESTROY(ad);
  return md;
}

/* =================================================================
 * Custom icon support
 * ================================================================= */

- (NSData *)customIconData
{
  if (![self hasCustomIcon])
    return nil;

  if (!_resourceFork || [_resourceFork length] < 256)
    return nil;

  /*
   * The resource fork contains a classic Mac OS Resource Manager format.
   * We look for an 'icns' resource (type 'icns') at resource ID -16455
   * (kCustomIconResource).
   *
   * Resource fork format:
   *   Header (16 bytes, big-endian):
   *     4 bytes: data offset (to resource data area)
   *     4 bytes: map offset (to resource map)
   *     4 bytes: data length
   *     4 bytes: map length
   *   Resource map contains type list and reference lists.
   *
   * For simplicity, we scan for the 'icns' magic bytes directly,
   * which is a robust approach since icns files start with 'icns'.
   */

  const uint8_t *bytes = [_resourceFork bytes];
  NSUInteger length = [_resourceFork length];

  /* Look for 'icns' magic */
  for (NSUInteger i = 0; i < length - 8; i++)
    {
      if (bytes[i] == 'i' && bytes[i+1] == 'c' && bytes[i+2] == 'n' && bytes[i+3] == 's')
        {
          /* Found icns container. Read the length from the icns header
           * (bytes i+4 to i+7, big-endian). The total icns file size is
           * stored in the icns header.
           */
          uint32_t icnsLen = ((uint32_t)bytes[i+4] << 24)
                           | ((uint32_t)bytes[i+5] << 16)
                           | ((uint32_t)bytes[i+6] << 8)
                           |  (uint32_t)bytes[i+7];

          if (icnsLen >= 8 && i + icnsLen <= length)
            {
              return [NSData dataWithBytes: bytes + i length: icnsLen];
            }
        }
    }

  return nil;
}

- (NSImage *)customIconAsImage
{
  NSData *icnsData = [self customIconData];
  if (!icnsData)
    return nil;

  /*
   * On macOS we would use NSImage initWithData: which natively
   * handles icns. On GNUstep with the icns library, we may need
   * to convert via libicns. For now we try NSImage directly.
   */
  NSImage *image = [[NSImage alloc] initWithData: icnsData];
  if (image)
    return [image autorelease];

  /*
   * If NSImage can't handle icns, we could use the icns library
   * or a simple PNG decoder for the embedded icon representations.
   * For initial implementation, fall back gracefully.
   */
  NSDebugLLog(@"gwspace", @"GSFileMetadata: NSImage could not decode icns data (%lu bytes)",
        (unsigned long)[icnsData length]);
  return nil;
}

/* =================================================================
 * Utilities
 * ================================================================= */

+ (NSString *)sidecarPathForFilePath:(NSString *)filePath
{
  NSString *dir = [filePath stringByDeletingLastPathComponent];
  NSString *file = [filePath lastPathComponent];
  return [dir stringByAppendingPathComponent:
           [NSString stringWithFormat: @"._%@", file]];
}

+ (BOOL)isSidecarPath:(NSString *)path
{
  if (!path) return NO;
  NSString *name = [path lastPathComponent];
  return [name hasPrefix: @"._"];
}

+ (NSColor *)colorForLabel:(GSFileLabel)label
{
  /*
   * Finder label colours from fdFlags encoding:
   *   0 = none, 1 = grey, 2 = green, 3 = purple,
   *   4 = blue,  5 = yellow, 6 = red, 7 = orange
   */
  switch (label)
    {
      case GSFileLabelGrey:
        return [NSColor colorWithCalibratedRed: 0.6 green: 0.6 blue: 0.6 alpha: 1.0];
      case GSFileLabelGreen:
        return [NSColor colorWithCalibratedRed: 0.3 green: 0.85 blue: 0.39 alpha: 1.0];
      case GSFileLabelPurple:
        return [NSColor colorWithCalibratedRed: 0.69 green: 0.32 blue: 0.87 alpha: 1.0];
      case GSFileLabelBlue:
        return [NSColor colorWithCalibratedRed: 0.25 green: 0.61 blue: 0.98 alpha: 1.0];
      case GSFileLabelYellow:
        return [NSColor colorWithCalibratedRed: 1.0 green: 0.87 blue: 0.0 alpha: 1.0];
      case GSFileLabelRed:
        return [NSColor colorWithCalibratedRed: 1.0 green: 0.23 blue: 0.19 alpha: 1.0];
      case GSFileLabelOrange:
        return [NSColor colorWithCalibratedRed: 1.0 green: 0.58 blue: 0.0 alpha: 1.0];
      case GSFileLabelNone:
      default:
        return nil;
    }
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"<GSFileMetadata: type='%c%c%c%c' creator='%c%c%c%c' flags=0x%04x label=%ld>",
    (char)(_parsed.typeCode >> 24) & 0xFF,
    (char)(_parsed.typeCode >> 16) & 0xFF,
    (char)(_parsed.typeCode >> 8) & 0xFF,
    (char)(_parsed.typeCode) & 0xFF,
    (char)(_parsed.creatorCode >> 24) & 0xFF,
    (char)(_parsed.creatorCode >> 16) & 0xFF,
    (char)(_parsed.creatorCode >> 8) & 0xFF,
    (char)(_parsed.creatorCode) & 0xFF,
    _parsed.flags,
    (long)_parsed.labelNumber];
}

@end
