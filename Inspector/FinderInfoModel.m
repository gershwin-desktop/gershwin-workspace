/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "FinderInfoModel.h"
#import "GSFileMetadata.h"
#import "GWMetaXattr.h"
#import "FinderInfoLocker.h"
#import "DSStore.h"

#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

NSString * const GWFinderInfoErrorDomain = @"GWFinderInfoErrorDomain";

#pragma mark - Big-endian output

static void appendBE32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v };
  [d appendBytes: b length: 4];
}

#pragma mark - Icon builder

@implementation FinderInfoIconBuilder

/* Resample a plain 8-bit RGB(A) bitmap by hand: going through a graphics
 * context needs a window server, which a command line tool (and the unit
 * test) does not have.  Alpha-weighted bilinear keeps transparent pixels from
 * bleeding their colour into the edges. */
+ (NSBitmapImageRep *)scaledCopyOfBitmap:(NSBitmapImageRep *)src side:(NSInteger)side
{
  NSInteger sw = [src pixelsWide], sh = [src pixelsHigh];
  NSInteger spp = [src samplesPerPixel];
  BOOL srcAlpha = [src hasAlpha];
  const uint8_t *sp = [src bitmapData];
  NSBitmapImageRep *dst;
  uint8_t *dp;
  CGFloat scale = MIN((CGFloat)side / sw, (CGFloat)side / sh);
  NSInteger dw = MAX(1, (NSInteger)(sw * scale + 0.5)), dh = MAX(1, (NSInteger)(sh * scale + 0.5));
  NSInteger ox = (side - dw) / 2, oy = (side - dh) / 2, x, y;

  dst = [[[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL
                  pixelsWide: side
                  pixelsHigh: side
               bitsPerSample: 8
             samplesPerPixel: 4
                    hasAlpha: YES
                    isPlanar: NO
              colorSpaceName: NSCalibratedRGBColorSpace
                 bytesPerRow: 0
                bitsPerPixel: 32] autorelease];
  dp = [dst bitmapData];
  memset(dp, 0, [dst bytesPerRow] * side);

  for (y = 0; y < dh; y++) {
    for (x = 0; x < dw; x++) {
      CGFloat fx = (x + 0.5) * sw / dw - 0.5, fy = (y + 0.5) * sh / dh - 0.5;
      NSInteger x0 = (NSInteger)floor(fx), y0 = (NSInteger)floor(fy);
      CGFloat tx = fx - x0, ty = fy - y0, acc[4] = { 0, 0, 0, 0 };
      uint8_t *out;
      int k, j;

      for (j = 0; j < 4; j++) {
        NSInteger sx = MIN(MAX(x0 + (j & 1), 0), sw - 1);
        NSInteger sy = MIN(MAX(y0 + (j >> 1), 0), sh - 1);
        CGFloat w = ((j & 1) ? tx : 1 - tx) * ((j >> 1) ? ty : 1 - ty);
        const uint8_t *px = sp + sy * [src bytesPerRow] + sx * spp;
        CGFloat a = srcAlpha ? px[spp - 1] / 255.0 : 1.0;

        for (k = 0; k < 3; k++)
          acc[k] += w * a * px[k];
        acc[3] += w * a;
      }
      out = dp + (oy + y) * [dst bytesPerRow] + (ox + x) * 4;
      for (k = 0; k < 3; k++)
        out[k] = acc[3] > 0 ? (uint8_t)MIN(255.0, acc[k] / acc[3] + 0.5) : 0;
      out[3] = (uint8_t)MIN(255.0, acc[3] * 255.0 + 0.5);
    }
  }
  return dst;
}

/* The largest bitmap behind the image that is plain 8-bit chunky RGB(A). */
+ (NSBitmapImageRep *)plainBitmapOfImage:(NSImage *)image
{
  NSEnumerator *e = [[image representations] objectEnumerator];
  NSImageRep *rep;
  NSBitmapImageRep *best = nil;

  while ((rep = [e nextObject]) != nil) {
    NSBitmapImageRep *b = [rep isKindOfClass: [NSBitmapImageRep class]] ? (id)rep : nil;

    if (b == nil || [b isPlanar] || [b bitsPerSample] != 8 || [b samplesPerPixel] < 3
        || [b bitsPerPixel] != [b samplesPerPixel] * 8)
      continue;
    if (best == nil || [b pixelsWide] > [best pixelsWide])
      best = b;
  }
  return best;
}

/* PNG-in-icns element types: ic07 128px, ic08 256px, ic09 512px. */
+ (NSData *)pngOfImage:(NSImage *)image side:(NSInteger)side
{
  NSBitmapImageRep *plain = [self plainBitmapOfImage: image];
  NSBitmapImageRep *rep;
  NSSize size = [image size];

  if (plain != nil && [plain pixelsWide] > 0 && [plain pixelsHigh] > 0) {
    rep = [self scaledCopyOfBitmap: plain side: side];
  } else {
    CGFloat scale;
    NSRect dst;

    if (size.width <= 0 || size.height <= 0)
      return nil;
    rep = [[[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes: NULL
                    pixelsWide: side
                    pixelsHigh: side
                 bitsPerSample: 8
               samplesPerPixel: 4
                      hasAlpha: YES
                      isPlanar: NO
                colorSpaceName: NSCalibratedRGBColorSpace
                   bytesPerRow: 0
                  bitsPerPixel: 32] autorelease];
    memset([rep bitmapData], 0, [rep bytesPerRow] * side);
    scale = MIN(side / size.width, side / size.height);
    dst = NSMakeRect((side - size.width * scale) / 2, (side - size.height * scale) / 2,
                     size.width * scale, size.height * scale);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: rep]];
    [image drawInRect: dst fromRect: NSZeroRect operation: NSCompositeSourceOver fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
  }
  return [rep representationUsingType: NSPNGFileType properties: [NSDictionary dictionary]];
}

+ (NSData *)icnsDataFromImage:(NSImage *)image
{
  static const struct { const char *type; NSInteger side; } kinds[] = {
    { "ic07", 128 }, { "ic08", 256 }, { "ic09", 512 }
  };
  NSMutableData *body = [NSMutableData data];
  NSMutableData *icns = [NSMutableData data];
  NSUInteger i;

  if (image == nil)
    return nil;
  for (i = 0; i < sizeof(kinds) / sizeof(kinds[0]); i++) {
    NSData *png = [self pngOfImage: image side: kinds[i].side];

    if (png == nil)
      return nil;
    [body appendBytes: kinds[i].type length: 4];
    appendBE32(body, (uint32_t)([png length] + 8));
    [body appendData: png];
  }
  [icns appendBytes: "icns" length: 4];
  appendBE32(icns, (uint32_t)([body length] + 8));
  [icns appendData: body];
  return icns;
}

@end

#pragma mark - Model

/* Finder keeps a folder's icon in a file of this name inside it ("Icon" and
 * a carriage return). */
static NSString *iconFilePath(NSString *folder)
{
  return [folder stringByAppendingPathComponent: @"Icon\r"];
}

@implementation FinderInfoModel

@synthesize path = _path;
@synthesize isDirectory = _isDirectory;
@synthesize hideExtension = _hideExtension;
@synthesize locked = _locked;
@synthesize nameLocked = _nameLocked;
@synthesize stationery = _stationery;
@synthesize invisible = _invisible;
@synthesize labelNumber = _labelNumber;
@synthesize hasCustomIcon = _hasCustomIcon;
@synthesize customIconICNS = _customIconICNS;

static id<FinderInfoLocking> defaultLocker;

+ (void)setDefaultLocker:(id<FinderInfoLocking>)locker
{
  [defaultLocker autorelease];
  defaultLocker = [locker retain];
}

+ (id<FinderInfoLocking>)defaultLocker
{
  if (defaultLocker == nil)
    defaultLocker = [FinderInfoSystemLocker new];
  return defaultLocker;
}

+ (BOOL)supportsLocking
{
  return [FinderInfoSystemLocker isSupported];
}

+ (BOOL)isValidCodeString:(NSString *)string
{
  NSUInteger i;

  if ([string length] == 0)
    return YES;
  if ([string length] != 4)
    return NO;
  for (i = 0; i < 4; i++) {
    unichar c = [string characterAtIndex: i];

    if (c < 0x20 || c > 0x7E)
      return NO;
  }
  return YES;
}

+ (uint32_t)codeFromString:(NSString *)string
{
  uint32_t code = 0;
  NSUInteger i;

  if ([self isValidCodeString: string] == NO)
    return 0;
  for (i = 0; i < [string length]; i++)
    code = (code << 8) | (uint32_t)[string characterAtIndex: i];
  return code;
}

+ (NSString *)stringFromCode:(uint32_t)code
{
  char c[4] = { code >> 24, code >> 16, code >> 8, code };
  NSUInteger i;

  if (code == 0)
    return @"";
  for (i = 0; i < 4; i++) {
    /* Codes with control or high bytes are shown as nothing rather than
     * mangled: the field only edits printable codes. */
    if ((uint8_t)c[i] < 0x20 || (uint8_t)c[i] > 0x7E)
      return @"";
  }
  return [[[NSString alloc] initWithBytes: c length: 4 encoding: NSASCIIStringEncoding]
    autorelease];
}

+ (instancetype)modelForPath:(NSString *)path
{
  return [[[self alloc] initWithPath: path] autorelease];
}

- (instancetype)initWithPath:(NSString *)path
{
  self = [super init];
  if (self) {
    BOOL isDir = NO;
    GSFileMetadata *md;

    _path = [path copy];
    [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir];
    _isDirectory = isDir;

    /* Uncached read: the shared cache may hold stale data after an edit made
     * by another tool. */
    md = [GSFileMetadata metadataForFileAtPath: path forceSidecar: NO];
    if (md != nil) {
      uint16_t flags = [md finderFlags];

      _hideExtension = (flags & GSFileFinderIsExtensionHidden) != 0;
      _nameLocked = [md isLocked];
      _invisible = [md isInvisible];
      _labelNumber = [md labelNumber];
      _comment = [[md finderComment] copy];
      if (isDir == NO) {
        _stationery = [md isStationery];
        _typeCode = [[FinderInfoModel stringFromCode: [md typeCode]] copy];
        _creatorCode = [[FinderInfoModel stringFromCode: [md creatorCode]] copy];
      }
      _hasCustomIcon = [md hasCustomIcon];
      if (_hasCustomIcon) {
        /* The shared reader goes through the cache, which may be stale. */
        [GSFileMetadata invalidateCachedMetadataForPath: path];
        [GSFileMetadata invalidateCachedMetadataForPath: iconFilePath(path)];
        _customIconICNS = [[GSFileMetadata customIconDataForPath: path] copy];
      }
    }
    if (_typeCode == nil)
      _typeCode = @"";
    if (_creatorCode == nil)
      _creatorCode = @"";
    _locker = [[FinderInfoModel defaultLocker] retain];
    _locked = [_locker isImmutableAtPath: path];
  }
  return self;
}

- (void)dealloc
{
  [_path release];
  [_locker release];
  [_typeCode release];
  [_creatorCode release];
  [_comment release];
  [_customIconICNS release];
  [super dealloc];
}

- (NSString *)typeCode { return _typeCode; }
- (NSString *)creatorCode { return _creatorCode; }
- (NSString *)comment { return _comment; }
- (void)setTypeCode:(NSString *)code { [_typeCode autorelease]; _typeCode = [code copy]; }
- (void)setCreatorCode:(NSString *)code { [_creatorCode autorelease]; _creatorCode = [code copy]; }
- (void)setComment:(NSString *)text
{
  [_comment autorelease];
  _comment = [text copy];
  _commentChanged = YES;
}

- (BOOL)setCustomIconFromImage:(NSImage *)image
{
  NSData *icns = [FinderInfoIconBuilder icnsDataFromImage: image];

  if (icns == nil)
    return NO;
  [_customIconICNS release];
  _customIconICNS = [icns retain];
  _hasCustomIcon = YES;
  _iconChanged = YES;
  return YES;
}

- (void)clearCustomIcon
{
  DESTROY(_customIconICNS);
  _hasCustomIcon = NO;
  _iconChanged = YES;
}

static NSError *errorWithText(NSString *key)
{
  NSString *text = NSLocalizedStringFromTableInBundle(key, @"FinderInfo",
    [NSBundle bundleForClass: [FinderInfoModel class]], @"");

  return [NSError errorWithDomain: GWFinderInfoErrorDomain
                             code: 1
                         userInfo: [NSDictionary dictionaryWithObject: text
                                                               forKey: NSLocalizedDescriptionKey]];
}

/* Finder writes the comment twice, as the xattr and as the item's cmmt record
 * in the parent's .DS_Store (E8).  Only that one record is touched, so
 * positions and view settings other tools keep there survive. */
static BOOL writeStoreComment(NSString *path, NSString *comment, NSError **error)
{
  NSString *item = [path lastPathComponent];
  NSString *storePath = [[path stringByDeletingLastPathComponent]
                          stringByAppendingPathComponent: @".DS_Store"];
  BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath: storePath];
  BOOL clear = [comment length] == 0;
  DSStore *store;

  /* The root has no parent folder to hold a record. */
  if ([path isEqualToString: @"/"])
    return YES;
  if (!exists && clear)
    return YES;
  if (exists) {
    store = [DSStore storeWithPath: storePath];
    if ([store load] == NO) {
      if (error)
        *error = errorWithText(@"The .DS_Store of the folder could not be read; the comment was not stored there.");
      return NO;
    }
  } else {
    store = [DSStore createStoreAtPath: storePath withEntries: nil];
  }
  if (clear)
    [store removeEntriesForFilename: item codes: [NSSet setWithObject: @"cmmt"]];
  else
    [store setCommentsForFilename: item comments: comment];
  if ([store save] == NO) {
    if (error)
      *error = errorWithText(@"The .DS_Store of the folder could not be written.");
    return NO;
  }
  return YES;
}

/* The Icon file of a folder: empty data fork, invisible, the icon in the
 * resource fork.  Finder does not set kHasCustomIcon on this file (E18). */
static BOOL writeFolderIconFile(NSString *folder, NSData *icns, NSError **error)
{
  NSString *file = iconFilePath(folder);
  NSFileManager *fm = [NSFileManager defaultManager];
  GSFileMetadata *imd;

  if ([fm fileExistsAtPath: file] == NO
      && [fm createFileAtPath: file contents: [NSData data] attributes: nil] == NO) {
    if (error)
      *error = errorWithText(@"The icon file could not be created in the folder.");
    return NO;
  }
  imd = [GSFileMetadata metadataForFileAtPath: file forceSidecar: NO];
  imd = imd ? [[imd copy] autorelease] : [[[GSFileMetadata alloc] init] autorelease];
  [imd setCustomIconData: icns];
  [imd setCustomIcon: NO];
  [imd setInvisible: YES];
  return [imd writeToFileAtPath: file error: error];
}

static BOOL removeFolderIconFile(NSString *folder, NSError **error)
{
  NSString *file = iconFilePath(folder);
  NSFileManager *fm = [NSFileManager defaultManager];

  if ([fm fileExistsAtPath: file] == NO)
    return YES;
  if ([fm removeFileAtPath: file handler: nil] == NO) {
    if (error)
      *error = errorWithText(@"The icon file could not be removed from the folder.");
    return NO;
  }
  [fm removeFileAtPath: [GSFileMetadata sidecarPathForFilePath: file] handler: nil];
  [GSFileMetadata invalidateCachedMetadataForPath: file];
  return YES;
}


- (BOOL)write:(NSError **)error
{
  GSFileMetadata *md;
  const char *cpath = [_path fileSystemRepresentation];
  uint16_t flags;
  BOOL wasLocked = [_locker isImmutableAtPath: _path];

  if ([FinderInfoModel isValidCodeString: _typeCode] == NO
      || [FinderInfoModel isValidCodeString: _creatorCode] == NO) {
    if (error)
      *error = errorWithText(@"Type and creator codes must be empty or exactly four "
                             @"printable ASCII characters.");
    return NO;
  }

  /* A locked file refuses xattr changes, so lift the lock for the write. */
  if (wasLocked && [_locker setImmutable: NO atPath: _path error: error] == NO)
    return NO;

  md = [GSFileMetadata metadataForFileAtPath: _path forceSidecar: NO];
  if (md == nil)
    md = [[[GSFileMetadata alloc] init] autorelease];
  else
    md = [[md copy] autorelease];

  flags = [md finderFlags];
  flags = _hideExtension ? (flags | GSFileFinderIsExtensionHidden)
                         : (flags & ~GSFileFinderIsExtensionHidden);
  [md setFinderFlags: flags];
  [md setLocked: _nameLocked];
  [md setInvisible: _invisible];
  [md setLabelNumber: _labelNumber];
  if (_isDirectory && _iconChanged) {
    /* The folder only says that it has an icon; the icon is in its Icon file. */
    [md setCustomIcon: _customIconICNS != nil];
  }
  if (_isDirectory == NO) {
    [md setStationery: _stationery];
    [md setTypeCode: [FinderInfoModel codeFromString: _typeCode]];
    [md setCreatorCode: [FinderInfoModel codeFromString: _creatorCode]];
    if (_iconChanged) {
      if (_customIconICNS != nil) {
        [md setCustomIconData: _customIconICNS];
      } else {
        [md clearCustomIcon];
      }
    }
  }
  [md setFinderComment: ([_comment length] > 0 ? _comment : nil)];

  if ([md writeToFileAtPath: _path error: error] == NO) {
    if (wasLocked)
      [_locker setImmutable: YES atPath: _path error: NULL];
    return NO;
  }

  /* GSFileMetadata only writes attributes that are set, so removals are ours. */
  if ([_comment length] == 0)
    gs_removexattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String]);
  if (_isDirectory == NO && _iconChanged && _customIconICNS == nil)
    gs_removexattr(cpath, [GSXATTR_RESOURCEFORK UTF8String]);
  if (_isDirectory && _iconChanged) {
    BOOL ok = _customIconICNS != nil ? writeFolderIconFile(_path, _customIconICNS, error)
                                     : removeFolderIconFile(_path, error);

    if (ok == NO) {
      if (wasLocked)
        [_locker setImmutable: YES atPath: _path error: NULL];
      return NO;
    }
  }
  if (_commentChanged && writeStoreComment(_path, _comment, error) == NO) {
    if (wasLocked)
      [_locker setImmutable: YES atPath: _path error: NULL];
    return NO;
  }
  _commentChanged = NO;
  _iconChanged = NO;
  [GSFileMetadata invalidateCachedMetadataForPath: _path];

  if (_locked) {
    if ([_locker setImmutable: YES atPath: _path error: error] == NO)
      return NO;
  }
  return YES;
}

@end
