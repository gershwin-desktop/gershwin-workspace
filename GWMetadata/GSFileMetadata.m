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

/*
 * Map the numeric `frView` code stored in a directory's FinderInfo DInfo to
 * the 4-character `vstl` view code used by `.DS_Store`, and back.  The numeric
 * codes match the classic Mac OS Finder view enum (icon=0, list=1, column=2,
 * cover-flow=4); gallery (glyv) is a newer addition.
 */
static uint16_t
GSFinderInfoViewForStyleCode(NSString *code)
{
  if ([code isEqualToString: @"Nlsv"]) return 1;
  if ([code isEqualToString: @"clmv"]) return 2;
  if ([code isEqualToString: @"Flwv"]) return 4;
  if ([code isEqualToString: @"glyv"]) return 5;
  return 0; /* icnv / default = icon */
}

static NSString *
GSStyleCodeForFinderInfoView(uint16_t frView)
{
  switch (frView)
    {
    case 1: return @"Nlsv";
    case 2: return @"clmv";
    case 4: return @"Flwv";
    case 5: return @"glyv";
    default: return @"icnv";
    }
}

@implementation GSFileMetadata

@synthesize finderInfo = _finderInfo;
@synthesize resourceFork = _resourceFork;
@synthesize finderComment = _finderComment;
@synthesize userTagsData = _userTagsData;
@synthesize quarantine = _quarantine;

enum {
  GSFieldResourceFork = 1 << 0,
  GSFieldComment      = 1 << 1,
  GSFieldUserTags     = 1 << 2,
  GSFieldQuarantine   = 1 << 3,
  /* Tags were built from a label alone, not read from disk: a write must
   * merge them into the tags on disk instead of replacing those. */
  GSTagsFromLabelOnly = 1 << 4,
  GSFieldAll          = 0xF   /* the four fields above, not the flag */
};

/* Written by hand instead of synthesized so every change is recorded. */
- (void)setResourceFork:(NSData *)value
{
  ASSIGNCOPY(_resourceFork, value);
  _modified |= GSFieldResourceFork;
}

- (void)setFinderComment:(NSString *)value
{
  ASSIGNCOPY(_finderComment, value);
  _modified |= GSFieldComment;
}

- (void)setUserTagsData:(NSData *)value
{
  ASSIGNCOPY(_userTagsData, value);
  _modified |= GSFieldUserTags;
  _modified &= ~GSTagsFromLabelOnly;
}

- (void)setQuarantine:(NSString *)value
{
  ASSIGNCOPY(_quarantine, value);
  _modified |= GSFieldQuarantine;
}

/* The object now mirrors what is on disk; later setters mark what differs. */
- (void)_markLoaded
{
  _loaded = GSFieldAll;
  _modified = 0;
  memset(_fiTouched, 0, sizeof(_fiTouched));
}

/* The FinderInfo bytes to store: `disk` (what is stored now, may be nil)
 * with exactly the bits a setter on this object set.  Returns `disk` itself
 * when nothing was touched, so nothing is rewritten. */
- (NSData *)_finderInfoPatchedOver:(NSData *)disk
{
  if (_finderInfo == nil)
    return disk;

  const uint8_t *cur = [_finderInfo bytes];
  NSUInteger n = MIN((NSUInteger)32, [_finderInfo length]);
  NSMutableData *out = nil;

  for (NSUInteger i = 0; i < n; i++)
    {
      uint8_t t = _fiTouched[i];

      if (t == 0)
        continue;
      if (out == nil)
        {
          out = [NSMutableData dataWithData: disk];
          if ([out length] < 32)
            [out setLength: 32];
        }
      uint8_t *o = (uint8_t *)[out mutableBytes];
      o[i] = (o[i] & ~t) | (cur[i] & t);
    }
  return out ? out : disk;
}

- (void)_touchFinderInfoBytes:(NSRange)range
{
  memset(_fiTouched + range.location, 0xFF, range.length);
}

- (void)_touchFinderFlags:(uint16_t)mask
{
  _fiTouched[8] |= (uint8_t)(mask >> 8);
  _fiTouched[9] |= (uint8_t)mask;
}
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
  DESTROY(_userTagsData);
  DESTROY(_quarantine);
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  GSFileMetadata *copy = [[GSFileMetadata allocWithZone: zone] init];
  [copy setFinderInfo: _finderInfo];
  [copy setResourceFork: _resourceFork];
  [copy setFinderComment: _finderComment];
  [copy setUserTagsData: _userTagsData];
  [copy setQuarantine: _quarantine];
  copy.forceSidecar = _forceSidecar;
  memcpy(copy->_fiTouched, _fiTouched, sizeof(_fiTouched));
  copy->_modified = _modified;
  copy->_loaded = _loaded;
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

      _parsed.labelNumber = [GSFileMetadata labelForFinderColor:
                              (_parsed.flags >> 1) & 0x7];
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
  [self _touchFinderInfoBytes: NSMakeRange(0, 32)];
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

- (BOOL)isNameLocked
{
  return [self isLocked];
}

- (BOOL)isExtensionHidden
{
  [self parseIfNeeded];
  return (_parsed.flags & GSFileFinderIsExtensionHidden) != 0;
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
  if (_parsed.labelNumber != GSFileLabelNone)
    return _parsed.labelNumber;

  /* Modern systems store tags only in _kMDItemUserTags and may not set the
   * legacy fdFlags label bits.  Fall back to the first standard colour tag. */
  for (NSString *tag in [self userTags])
    {
      GSFileLabel label = [GSFileMetadata labelForTagName: tag];
      if (label != GSFileLabelNone)
        return label;
    }
  return GSFileLabelNone;
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
      [self _touchFinderInfoBytes: NSMakeRange(0, 4)];
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
      [self _touchFinderInfoBytes: NSMakeRange(4, 4)];
      _parsed.creatorCode = code;
    }
}

- (void)setFinderFlags:(uint16_t)flags
{
  [self _setFinderFlags: flags touching: 0xFFFF];
}

/* `touched` names the bits the caller means to set; the others are only
 * carried along and must not overwrite what is on disk. */
- (void)_setFinderFlags:(uint16_t)flags touching:(uint16_t)touched
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 10)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be16(bytes + 8, flags);
      _parsed.flags = flags;
      _parsed.labelNumber = [GSFileMetadata labelForFinderColor:
                              (flags >> 1) & 0x7];
      [self _touchFinderFlags: touched];
    }
}

- (void)setLocked:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsNameLocked;
  else
    flags &= ~GSFileFinderIsNameLocked;
  [self _setFinderFlags: flags touching: GSFileFinderIsNameLocked];
}

- (void)setNameLocked:(BOOL)value
{
  [self setLocked: value];
}

- (void)setExtensionHidden:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsExtensionHidden;
  else
    flags &= ~GSFileFinderIsExtensionHidden;
  [self _setFinderFlags: flags touching: GSFileFinderIsExtensionHidden];
}

- (void)setCustomIcon:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderHasCustomIcon;
  else
    flags &= ~GSFileFinderHasCustomIcon;
  [self _setFinderFlags: flags touching: GSFileFinderHasCustomIcon];
}

- (void)setInvisible:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsInvisible;
  else
    flags &= ~GSFileFinderIsInvisible;
  [self _setFinderFlags: flags touching: GSFileFinderIsInvisible];
}

- (void)setAlias:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsAlias;
  else
    flags &= ~GSFileFinderIsAlias;
  [self _setFinderFlags: flags touching: GSFileFinderIsAlias];
}

- (void)setStationery:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderIsStationery;
  else
    flags &= ~GSFileFinderIsStationery;
  [self _setFinderFlags: flags touching: GSFileFinderIsStationery];
}

- (void)setHasBundle:(BOOL)value
{
  uint16_t flags = [self finderFlags];
  if (value)
    flags |= GSFileFinderHasBundle;
  else
    flags &= ~GSFileFinderHasBundle;
  [self _setFinderFlags: flags touching: GSFileFinderHasBundle];
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
      [self _touchFinderInfoBytes: NSMakeRange(10, 4)];
      _parsed.iconPosition = position;
    }
}

/* =================================================================
 * Directory spatial view / window (FinderInfo DInfo)
 * ================================================================= */

- (NSString *)viewStyleCodeForDirectory
{
  [self parseIfNeeded];
  if ([_finderInfo length] < 16)
    return nil;
  const uint8_t *bytes = [_finderInfo bytes];
  uint16_t frView = be16_to_host(bytes + 14);
  return GSStyleCodeForFinderInfoView(frView);
}

- (void)setViewStyleCodeForDirectory:(NSString *)code
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 16)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be16(bytes + 14, GSFinderInfoViewForStyleCode(code));
      [self _touchFinderInfoBytes: NSMakeRange(14, 2)];
    }
}

- (NSRect)windowBoundsForDirectory
{
  [self parseIfNeeded];
  if ([_finderInfo length] < 8)
    return NSZeroRect;
  const uint8_t *bytes = [_finderInfo bytes];
  int16_t top    = (int16_t)be16_to_host(bytes + 0);
  int16_t left   = (int16_t)be16_to_host(bytes + 2);
  int16_t bottom = (int16_t)be16_to_host(bytes + 4);
  int16_t right  = (int16_t)be16_to_host(bytes + 6);
  /* A zero rect means "unset" - the classic default window. */
  if (top == 0 && left == 0 && bottom == 0 && right == 0)
    return NSZeroRect;
  return NSMakeRect(left, top, right - left, bottom - top);
}

- (void)setWindowBoundsForDirectory:(NSRect)bounds
{
  [self parseIfNeeded];
  [self createFinderInfoIfNeeded];
  if ([_finderInfo length] >= 8)
    {
      uint8_t *bytes = (uint8_t *)[(NSMutableData *)_finderInfo mutableBytes];
      host_to_be16(bytes + 0, (uint16_t)(int16_t)bounds.origin.y);
      host_to_be16(bytes + 2, (uint16_t)(int16_t)bounds.origin.x);
      host_to_be16(bytes + 4, (uint16_t)(int16_t)(bounds.origin.y + bounds.size.height));
      host_to_be16(bytes + 6, (uint16_t)(int16_t)(bounds.origin.x + bounds.size.width));
      [self _touchFinderInfoBytes: NSMakeRange(0, 8)];
    }
}

- (void)setLabelNumber:(NSInteger)label
{
  if (label < 0 || label > 7)
    label = 0;

  /* Capture the old label BEFORE setFinderFlags: recomputes it from the
   * new flags (it derives labelNumber from the flag bits). */
  NSString *old = [GSFileMetadata tagNameForLabel: (GSFileLabel)_parsed.labelNumber];
  NSString *tag = [GSFileMetadata tagNameForLabel: (GSFileLabel)label];

  uint16_t flags = [self finderFlags];
  /* Clear the label bits (1-3), then set new value */
  flags &= ~GSFileFinderColorBits;
  flags |= (uint16_t)([GSFileMetadata finderColorForLabel:
                         (GSFileLabel)label] << 1);
  [self _setFinderFlags: flags touching: GSFileFinderColorBits];
  _parsed.labelNumber = label;

  /* Keep the _kMDItemUserTags xattr in sync with the label: colour tags are
   * shown via that attribute, not via .DS_Store.  See Apple File System
   * Programming Guide:
   * https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html
   * Replace the standard tag that matches our label, and remove it when the
   * label is cleared. */
  BOOL tagsUnread = (_userTagsData == nil && !(_loaded & GSFieldUserTags));

  NSMutableArray *tags = [[[self userTags] mutableCopy] autorelease];
  if (tags == nil)
    tags = [NSMutableArray array];
  if (old && [tags containsObject: old])
    [tags removeObject: old];
  if (tag && ![tags containsObject: tag])
    [tags addObject: tag];

  [self setUserTags: ([tags count] ? tags : nil)];
  if (tagsUnread)
    _modified |= GSTagsFromLabelOnly;
}

/* The tags to put on disk.  Normally this object's; when they came from a
 * label alone, the tags already on disk (diskData) with the colour tags
 * replaced by this label's, so other tags survive a label change. */
- (NSData *)_userTagsDataToWriteOver:(NSData *)diskData
{
  if (!(_modified & GSTagsFromLabelOnly))
    return _userTagsData;

  id disk = diskData ? [NSPropertyListSerialization
    propertyListWithData: diskData options: NSPropertyListImmutable
                  format: NULL error: NULL] : nil;
  NSMutableArray *tags = [disk isKindOfClass: [NSArray class]]
    ? [[disk mutableCopy] autorelease] : [NSMutableArray array];
  for (NSUInteger i = [tags count]; i > 0; i--)
    {
      id t = [tags objectAtIndex: i - 1];
      if ([t isKindOfClass: [NSString class]]
          && [GSFileMetadata labelForTagName: t] != GSFileLabelNone)
        [tags removeObjectAtIndex: i - 1];
    }
  NSString *tag = [GSFileMetadata tagNameForLabel:
                    (GSFileLabel)[self labelNumber]];
  if (tag)
    [tags addObject: tag];
  if ([tags count] == 0)
    return nil;
  return [NSPropertyListSerialization
    dataWithPropertyList: tags format: NSPropertyListBinaryFormat_v1_0
                 options: 0 error: NULL];
}

/* =================================================================
 * User tags (_kMDItemUserTags)
 * ================================================================= */

+ (NSString *)tagNameForLabel:(GSFileLabel)label
{
  switch (label)
    {
      case GSFileLabelGrey:    return @"Gray";
      case GSFileLabelGreen:   return @"Green";
      case GSFileLabelPurple:  return @"Purple";
      case GSFileLabelBlue:    return @"Blue";
      case GSFileLabelYellow:  return @"Yellow";
      case GSFileLabelRed:     return @"Red";
      case GSFileLabelOrange:  return @"Orange";
      case GSFileLabelNone:
      default:                 return nil;
    }
}

/* Finder colour number (index) -> GSFileLabel, from evidence E24. */
static const GSFileLabel kLabelForFinderColor[8] = {
  GSFileLabelNone, GSFileLabelGrey, GSFileLabelGreen, GSFileLabelPurple,
  GSFileLabelBlue, GSFileLabelYellow, GSFileLabelRed, GSFileLabelOrange
};

+ (GSFileLabel)labelForFinderColor:(NSUInteger)color
{
  return color < 8 ? kLabelForFinderColor[color] : GSFileLabelNone;
}

+ (NSUInteger)finderColorForLabel:(GSFileLabel)label
{
  for (NSUInteger i = 1; i < 8; i++)
    if (kLabelForFinderColor[i] == label)
      return i;
  return 0;
}

+ (GSFileLabel)labelForTagName:(NSString *)tagName
{
  /* Later Finders store colour tags as "Name\nN" with the name localized,
   * so only the number identifies the colour. */
  NSRange nl = [tagName rangeOfString: @"\n"];
  if (nl.location != NSNotFound)
    {
      NSString *num = [tagName substringFromIndex: NSMaxRange(nl)];
      NSInteger color = [num integerValue];
      if ([num length] == 1 && color >= 0 && color < 8)
        return [self labelForFinderColor: (NSUInteger)color];
      return GSFileLabelNone;
    }
  if ([tagName isEqualToString: @"Gray"])   return GSFileLabelGrey;
  if ([tagName isEqualToString: @"Grey"])   return GSFileLabelGrey;
  if ([tagName isEqualToString: @"Green"])  return GSFileLabelGreen;
  if ([tagName isEqualToString: @"Purple"]) return GSFileLabelPurple;
  if ([tagName isEqualToString: @"Blue"])   return GSFileLabelBlue;
  if ([tagName isEqualToString: @"Yellow"]) return GSFileLabelYellow;
  if ([tagName isEqualToString: @"Red"])    return GSFileLabelRed;
  if ([tagName isEqualToString: @"Orange"]) return GSFileLabelOrange;
  return GSFileLabelNone;
}

- (NSArray *)userTags
{
  NSData *raw = [self userTagsData];
  if (raw == nil)
    return nil;

  id value = [NSPropertyListSerialization propertyListWithData: raw
                                                       options: NSPropertyListImmutable
                                                        format: NULL
                                                         error: NULL];
  if ([value isKindOfClass: [NSArray class]])
    return (NSArray *)value;
  return nil;
}

- (void)setUserTags:(NSArray *)tags
{
  if (tags == nil || [tags count] == 0)
    {
      [self setUserTagsData: nil];
      return;
    }
  NSError *error = nil;
  NSData *data = [NSPropertyListSerialization
                   dataWithPropertyList: tags
                                 format: NSPropertyListBinaryFormat_v1_0
                                options: 0
                                  error: &error];
  if (error == nil)
    [self setUserTagsData: data];
}

/* Finder comment: macOS/Finder stores com.apple.metadata:kMDItemFinderComment
 * as a binary plist (bplist00) wrapping an NSString - never raw UTF-8.  Older
 * Gershwin revisions wrote raw UTF-8, which 10.6+ Finder cannot parse or
 * display, so comments written by Gershwin were invisible on the Mac. */
- (NSData *)_finderCommentToPlistData
{
  if (_finderComment == nil || [_finderComment length] == 0)
    return nil;
  NSData *data = [NSPropertyListSerialization
                   dataWithPropertyList: _finderComment
                                 format: NSPropertyListBinaryFormat_v1_0
                                options: 0
                                  error: NULL];
  if (data == nil)
    data = [_finderComment dataUsingEncoding: NSUTF8StringEncoding];
  return data;
}

+ (NSString *)_commentFromXattrData:(NSData *)fc
{
  if (fc == nil || [fc length] == 0)
    return nil;
  const unsigned char *b = [fc bytes];
  BOOL isPlist = ([fc length] >= 8 && b[0] == 'b' && b[1] == 'p' && b[2] == 'l'
                  && b[3] == 'i' && b[4] == 's' && b[5] == 't'
                  && b[6] == '0' && b[7] == '0');
  if (isPlist)
    {
      id plist = [NSPropertyListSerialization
                   propertyListWithData: fc
                                options: NSPropertyListImmutable
                                 format: NULL
                                  error: NULL];
      if ([plist isKindOfClass: [NSString class]])
        return (NSString *)plist;   /* autoreleased */
    }
  return [[[NSString alloc] initWithData: fc encoding: NSUTF8StringEncoding]
           autorelease];
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

/*
 * Path-keyed cache for the common (xattr-first) read path.  Reading
 * metadata costs up to three getxattr syscalls plus a possible sidecar
 * open, and callers hit this per-file during directory listing, icon
 * drawing, and cell display — so an unbounded amount of syscalls without
 * a cache.  A negative result is cached as NSNull so unlabeled files (the
 * majority) stop re-probing on every redraw.  Cleared by
 * +invalidateAllCachedMetadata (wired to the same refresh events that
 * clear FSNodeRep's icon cache) and per-path on write.  Main-thread only.
 */
static NSMutableDictionary *_metadataCache = nil;

+ (NSMutableDictionary *)_metadataCache
{
  if (_metadataCache == nil)
    _metadataCache = [[NSMutableDictionary alloc] init];
  return _metadataCache;
}

+ (void)invalidateAllCachedMetadata
{
  [_metadataCache removeAllObjects];
}

+ (void)invalidateCachedMetadataForPath:(NSString *)path
{
  if (path)
    [_metadataCache removeObjectForKey: path];
}

+ (GSFileMetadata *)metadataForFileAtPath:(NSString *)path
{
  if (!path || [path length] == 0)
    return nil;

  NSMutableDictionary *cache = [self _metadataCache];
  id cached = [cache objectForKey: path];
  if (cached != nil)
    return (cached == [NSNull null]) ? nil : cached;

  GSFileMetadata *md = [self metadataForFileAtPath: path forceSidecar: NO];
  [cache setObject: (md ? (id)md : (id)[NSNull null]) forKey: path];
  return md;
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
      if (![md readSidecarForPath: path])
        return nil;
      [md _markLoaded];
      return md;
    }

  /* Try xattrs first */
  BOOL found = NO;

  /* Read FinderInfo via xattr */
  {
    const char *cpath = GW_FSREP(path);
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
    const char *cpath = GW_FSREP(path);
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

  /* Read Finder comment via xattr (binary plist, like macOS/Finder) */
  {
    const char *cpath = GW_FSREP(path);
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_FINDERCOMMENT UTF8String],
                                NULL, 0);
    if (size > 0)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String],
                    [data mutableBytes], size);
        NSString *comment = [GSFileMetadata _commentFromXattrData: data];
        if (comment)
          {
            md.finderComment = comment;
          }
        found = YES;
      }
  }

  /* Read user tags (_kMDItemUserTags) via xattr */
  {
    const char *cpath = GW_FSREP(path);
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_USERTAGS UTF8String],
                                NULL, 0);
    if (size > 0)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_USERTAGS UTF8String],
                    [data mutableBytes], size);
        md.userTagsData = data;
        found = YES;
      }
  }

  /* Read quarantine record via xattr (plain UTF-8 string) */
  {
    const char *cpath = GW_FSREP(path);
    ssize_t size = gs_getxattr(cpath,
                                [GSXATTR_QUARANTINE UTF8String],
                                NULL, 0);
    if (size > 0)
      {
        NSMutableData *data = [NSMutableData dataWithLength: size];
        gs_getxattr(cpath, [GSXATTR_QUARANTINE UTF8String],
                    [data mutableBytes], size);
        NSString *q = [[NSString alloc] initWithData: data
                                            encoding: NSUTF8StringEncoding];
        if (q)
          {
            md.quarantine = q;
            RELEASE(q);
            found = YES;
          }
      }
  }

  /* If nothing found via xattrs, try sidecar */
  if (!found)
    {
      if ([md readSidecarForPath: path])
        found = YES;
    }

  if (!found)
    return nil;
  [md _markLoaded];
  return md;
}

/* =================================================================
 * Write to file
 * ================================================================= */

- (NSData *)_xattrData:(NSString *)name atPath:(NSString *)path
{
  const char *cpath = GW_FSREP(path);
  ssize_t size = gs_getxattr(cpath, [name UTF8String], NULL, 0);
  if (size <= 0)
    return nil;
  NSMutableData *data = [NSMutableData dataWithLength: size];
  gs_getxattr(cpath, [name UTF8String], [data mutableBytes], size);
  return data;
}

/* YES when every entry and attribute of the sidecar is now an xattr of the
 * file.  What the file already has wins, and a field this object cleared
 * stays cleared.  NO keeps the sidecar: entries xattrs cannot hold, bytes
 * behind FinderInfo, or a failure such as E2BIG/ENOSPC. */
- (BOOL)_migrateSidecar:(NSString *)sidecarPath toFileAtPath:(NSString *)path
{
  NSData *raw = [NSData dataWithContentsOfFile: sidecarPath];
  GSAppleDouble *ad = raw ? [[[GSAppleDouble alloc] initWithData: raw]
                              autorelease] : nil;
  if (ad == nil)
    return NO;

  const uint8_t *b = [raw bytes];
  NSUInteger len = [raw length];
  uint16_t count = (uint16_t)((b[24] << 8) | b[25]);
  if (len < APPLEDOUBLE_HEADER_SIZE
      || (NSUInteger)count * APPLEDOUBLE_ENTRY_SIZE > len - APPLEDOUBLE_HEADER_SIZE)
    return NO;
  NSDictionary *attrs = [ad extendedAttributes];
  for (uint16_t i = 0; i < count; i++)
    {
      const uint8_t *d = b + APPLEDOUBLE_HEADER_SIZE + i * APPLEDOUBLE_ENTRY_SIZE;
      uint32_t eid = ((uint32_t)d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
      uint32_t elen = ((uint32_t)d[8] << 24) | (d[9] << 16) | (d[10] << 8) | d[11];

      if (eid != GSAppleDoubleFinderInfo && eid != GSAppleDoubleResourceFork)
        return NO;
      if (eid == GSAppleDoubleFinderInfo && elen > 32 && [attrs count] == 0)
        return NO;
    }

  const char *cpath = GW_FSREP(path);
  NSMutableDictionary *items = [NSMutableDictionary dictionary];
  if ([ad hasFinderInfo])
    [items setObject: [ad finderInfo] forKey: GSXATTR_FINDERINFO];
  if ([ad hasResourceFork] && [[ad resourceFork] length] > 0)
    [items setObject: [ad resourceFork] forKey: GSXATTR_RESOURCEFORK];
  for (NSString *name in attrs)
    {
      NSData *value = [attrs objectForKey: name];

      if ([name isEqualToString: @"com.apple.quarantine"])
        value = [[self class] plainQuarantine: value];
      [items setObject: value forKey: [@"user." stringByAppendingString: name]];
    }

  NSDictionary *cleared = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithUnsignedInteger: GSFieldResourceFork], GSXATTR_RESOURCEFORK,
    [NSNumber numberWithUnsignedInteger: GSFieldComment], GSXATTR_FINDERCOMMENT,
    [NSNumber numberWithUnsignedInteger: GSFieldUserTags], GSXATTR_USERTAGS,
    [NSNumber numberWithUnsignedInteger: GSFieldQuarantine], GSXATTR_QUARANTINE,
    nil];
  for (NSString *name in items)
    {
      NSData *value = [items objectForKey: name];

      if (gs_getxattr(cpath, [name UTF8String], NULL, 0) >= 0)
        continue;
      if (_modified & [[cleared objectForKey: name] unsignedIntegerValue])
        continue;
      /* An empty value has no bytes pointer; hand over a real one so the
       * attribute is created empty instead of the whole migration failing. */
      if (gs_setxattr(cpath, [name UTF8String],
                      [value length] > 0 ? [value bytes] : "",
                      [value length], 0) != 0)
        return NO;
    }
  return YES;
}

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

  if (![self _divertFolderIconAtPath: path error: error])
    return NO;
  if (_forceSidecar)
    return [self writeSidecarToFileAtPath: path error: error];

  const char *cpath = GW_FSREP(path);
  BOOL success = YES;

  /* Write FinderInfo: only the bytes this object changed, over what is
   * stored now (a Mac or another tool may have set the rest). */
  {
    NSData *stored = [self _xattrData: GSXATTR_FINDERINFO atPath: path];
    NSData *base = stored;
    if (base == nil)
      {
        NSData *sc = [NSData dataWithContentsOfFile:
          [[self class] sidecarPathForFilePath: path]];
        GSAppleDouble *old = sc ? [[[GSAppleDouble alloc]
          initWithData: sc] autorelease] : nil;
        base = [old hasFinderInfo] ? [old finderInfo] : nil;
      }
    NSData *patched = [self _finderInfoPatchedOver: base];
    if (patched && [patched length] >= 32 && ![patched isEqual: stored])
      {
        if (gs_setxattr(cpath, [GSXATTR_FINDERINFO UTF8String],
                         [patched bytes], [patched length], 0) != 0)
          {
            /* Xattr failed, fall back to sidecar */
            return [self writeSidecarToFileAtPath: path error: error];
          }
      }
  }

  /* Write ResourceFork.  An emptied fork (after -clearCustomIcon) must go
   * away on disk too, or Finder keeps showing the old icon data. */
  if (!(_modified & GSFieldResourceFork))
    {
    }
  else if (_resourceFork && [_resourceFork length] > 0)
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
  else
    {
      gs_removexattr(cpath, [GSXATTR_RESOURCEFORK UTF8String]);
    }

  /* Write Finder comment as a binary plist, matching macOS/Finder's storage
   * of com.apple.metadata:kMDItemFinderComment so 10.6+ Finder displays it. */
  if (!(_modified & GSFieldComment))
    {
    }
  else if (_finderComment && [_finderComment length] > 0)
    {
      NSData *commentData = [self _finderCommentToPlistData];
      if (commentData
          && gs_setxattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String],
                         [commentData bytes], [commentData length],
                         0) != 0)
        {
          /* Non-fatal: comment couldn't be written, but main metadata is OK */
        }
    }
  else
    {
      /* A cleared comment must not linger as the old text on disk. */
      gs_removexattr(cpath, [GSXATTR_FINDERCOMMENT UTF8String]);
    }

  /* Write user tags (_kMDItemUserTags).  Setting tags to nil removes the
   * attribute entirely so a cleared label does not linger. */
  if (!(_modified & GSFieldUserTags))
    {
    }
  else
    {
      NSData *tagsOut = [self _userTagsDataToWriteOver:
        [self _xattrData: GSXATTR_USERTAGS atPath: path]];
      if (tagsOut && [tagsOut length] > 0)
        {
          gs_setxattr(cpath, [GSXATTR_USERTAGS UTF8String],
                      [tagsOut bytes], [tagsOut length], 0);
        }
      else
        {
          gs_removexattr(cpath, [GSXATTR_USERTAGS UTF8String]);
        }
    }

  if (!(_modified & GSFieldQuarantine))
    {
    }
  else if (_quarantine && [_quarantine length] > 0)
    {
      NSData *qData = [_quarantine dataUsingEncoding: NSUTF8StringEncoding];
      gs_setxattr(cpath, [GSXATTR_QUARANTINE UTF8String],
                   [qData bytes], [qData length], 0);
    }
  else
    {
      gs_removexattr(cpath, [GSXATTR_QUARANTINE UTF8String]);
    }

  /* A sidecar may hold what the xattrs lack (written before xattrs worked,
   * or by a Mac).  Move it over; it goes only when nothing is left in it. */
  NSString *sidecarPath = [[self class] sidecarPathForFilePath: path];
  if ([[NSFileManager defaultManager] fileExistsAtPath: sidecarPath]
      && [self _migrateSidecar: sidecarPath toFileAtPath: path])
    {
      [[NSFileManager defaultManager] removeFileAtPath: sidecarPath
                                               handler: nil];
    }

  return success;
}

- (BOOL)writeSidecarToFileAtPath:(NSString *)path error:(NSError **)error
{
  if (![self _divertFolderIconAtPath: path error: error])
    return NO;
  NSString *sidecarPath = [[self class] sidecarPathForFilePath: path];

  /* Merge over what is already there: entries and attributes written by
   * other software (a Mac, a copy tool) are not ours to delete.  Of the
   * attributes we manage only those this object changed, or that the file
   * lacks, are replaced; the rest are carried over byte for byte. */
  NSData *existing = [NSData dataWithContentsOfFile: sidecarPath];
  GSAppleDouble *old = existing ? [[[GSAppleDouble alloc]
    initWithData: existing] autorelease] : nil;
  NSDictionary *oldAttrs = [old extendedAttributes];
  NSMutableSet *managed = [NSMutableSet set];
  static const struct { NSUInteger bit; NSString *name; } fields[] = {
    { GSFieldUserTags,   @"com.apple.metadata:_kMDItemUserTags" },
    { GSFieldComment,    @"com.apple.metadata:kMDItemFinderComment" },
    { GSFieldQuarantine, @"com.apple.quarantine" },
  };
  for (NSUInteger i = 0; i < sizeof(fields) / sizeof(fields[0]); i++)
    {
      if ((_modified & fields[i].bit)
          || [oldAttrs objectForKey: fields[i].name] == nil)
        [managed addObject: fields[i].name];
    }

  /* Entry 2 is always replaced by the fresh content, so hand it the fork
   * already in the file unless this object changed it. */
  NSData *fork = _resourceFork;
  if (!(_modified & GSFieldResourceFork) && [old hasResourceFork])
    fork = [old resourceFork];
  NSData *tagsOut = [self _userTagsDataToWriteOver:
    [oldAttrs objectForKey: @"com.apple.metadata:_kMDItemUserTags"]];
  /* With no sidecar yet the FinderInfo lives in the xattr; an export that
   * left it out would lose type, creator and flags on the other side. */
  NSData *fiBase = [old hasFinderInfo] ? [old finderInfo]
    : [self _xattrData: GSXATTR_FINDERINFO atPath: path];
  NSData *fi = [self _finderInfoPatchedOver: fiBase];
  NSData *fresh = [self _appleDoubleDataWithFinderInfo: fi
                                          resourceFork: fork
                                                  tags: tagsOut];
  NSData *appleDoubleData = [GSAppleDouble
    appleDoubleDataByUpdatingSidecar: existing
                         withContent: fresh
                   managedXattrNames: managed];
  if (!appleDoubleData)
    {
      /* Nothing left to keep: remove sidecar if it exists */
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

  NSData *tags = [ad dataForEntry: GSAppleDoubleUserTags];
  if (tags && [tags length] > 0)
    self.userTagsData = tags;

  /* macOS AppleDouble stores xattrs (FinderInfo, ResourceFork, tags,
   * Finder comment) inside an "ATTR" blob within entry 9.  Fall back to
   * those when the classic entries above are absent.  Note the names here
   * are the raw macOS xattr names (no "user." prefix), unlike the
   * Gershwin xattr layer's GSXATTR_* constants. */
  NSDictionary *xattrs = [ad extendedAttributes];
  if (xattrs)
    {
      if (self.finderInfo == nil)
        {
          NSData *fi = [xattrs objectForKey: @"com.apple.FinderInfo"];
          if (fi && [fi length] >= 32)
            self.finderInfo = fi;
        }
      if (self.resourceFork == nil)
        {
          NSData *rf = [xattrs objectForKey: @"com.apple.ResourceFork"];
          if (rf && [rf length] > 0)
            self.resourceFork = rf;
        }
      if (self.userTagsData == nil)
        {
          NSData *ut = [xattrs objectForKey:
            @"com.apple.metadata:_kMDItemUserTags"];
          if (ut && [ut length] > 0)
            self.userTagsData = ut;
        }
      if (self.finderComment == nil)
        {
          NSData *fc = [xattrs objectForKey:
            @"com.apple.metadata:kMDItemFinderComment"];
          if (fc && [fc length] > 0)
            {
              NSString *comment = [GSFileMetadata _commentFromXattrData: fc];
              if (comment)
                self.finderComment = comment;
            }
        }
      if (self.quarantine == nil)
        {
          NSData *qd = [xattrs objectForKey: @"com.apple.quarantine"];
          if (qd && [qd length] > 0)
            {
              /* copyfile pads the record with NULs in some variants;
               * they are not part of the value. */
              NSUInteger len = [qd length];
              const char *bytes = [qd bytes];
              while (len > 0 && bytes[len - 1] == 0)
                len--;
              NSData *trimmed = [[self class] plainQuarantine:
                [qd subdataWithRange: NSMakeRange(0, len)]];
              NSString *q = [[NSString alloc]
                initWithData: trimmed encoding: NSUTF8StringEncoding];
              if (q)
                {
                  self.quarantine = q;
                  RELEASE(q);
                }
            }
        }
    }

  DESTROY(ad);
  return YES;
}

/* =================================================================
 * AppleDouble conversion
 * ================================================================= */

- (NSData *)appleDoubleData
{
  return [self _appleDoubleDataWithFinderInfo: _finderInfo
                                 resourceFork: _resourceFork
                                         tags: _userTagsData];
}

- (NSData *)_appleDoubleDataWithFinderInfo:(NSData *)finderInfo
                              resourceFork:(NSData *)fork
                                      tags:(NSData *)tags
{
  GSAppleDouble *ad = [[GSAppleDouble alloc] init];

  if (finderInfo && [finderInfo length] > 0)
    [ad setFinderInfo: finderInfo];

  if (fork && [fork length] > 0)
    [ad setResourceFork: fork];

  /* Tags and the Finder comment are xattrs to macOS; staging them as
   * such makes -appleDoubleData emit the ATTR-blob layout a real Mac
   * writes, so dot_clean/ditto on macOS ingest them natively. */
  if (tags && [tags length] > 0)
    [ad setXattr: tags
          forKey: @"com.apple.metadata:_kMDItemUserTags"];

  if (_finderComment && [_finderComment length] > 0)
    {
      NSData *commentData = [self _finderCommentToPlistData];
      if (commentData)
        [ad setXattr: commentData
              forKey: @"com.apple.metadata:kMDItemFinderComment"];
    }

  if (_quarantine && [_quarantine length] > 0)
    {
      NSData *qData = [_quarantine dataUsingEncoding: NSUTF8StringEncoding];
      if (qData)
        [ad setXattr: [[self class] sidecarQuarantine: qData]
              forKey: @"com.apple.quarantine"];
    }

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
  NSData *tags = [ad dataForEntry: GSAppleDoubleUserTags];
  if (tags == nil || [tags length] == 0)
    tags = [[ad extendedAttributes]
              objectForKey: @"com.apple.metadata:_kMDItemUserTags"];
  if (tags && [tags length] > 0)
    md.userTagsData = tags;
  NSData *commentData = [[ad extendedAttributes]
    objectForKey: @"com.apple.metadata:kMDItemFinderComment"];
  if (commentData && [commentData length] > 0)
    {
      NSString *comment = [self _commentFromXattrData: commentData];
      if (comment)
        md.finderComment = comment;
    }
  NSData *qData = [[ad extendedAttributes]
    objectForKey: @"com.apple.quarantine"];
  if (qData && [qData length] > 0)
    {
      NSUInteger len = [qData length];
      const char *bytes = [qData bytes];
      while (len > 0 && bytes[len - 1] == 0)
        len--;
      NSString *q = [[NSString alloc]
        initWithData: [self plainQuarantine:
                        [qData subdataWithRange: NSMakeRange(0, len)]]
            encoding: NSUTF8StringEncoding];
      if (q)
        {
          md.quarantine = q;
          RELEASE(q);
        }
    }

  DESTROY(ad);
  [md _markLoaded];
  return md;
}

/* =================================================================
 * Custom icon support
 * ================================================================= */

/* Resource File Format: Inside Macintosh "More Macintosh Toolbox", Resource
 * Manager chapter (public documentation of the classic format).  All fields
 * are big-endian. */
enum { GSCustomIconResourceID = -16455 };

static uint32_t gsBE32(const uint8_t *p)
{
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
       | ((uint32_t)p[2] << 8) | p[3];
}

static uint16_t gsBE16(const uint8_t *p)
{
  return (uint16_t)((p[0] << 8) | p[1]);
}

static void gsAppend16(NSMutableData *d, uint16_t v)
{
  uint8_t b[2] = { (uint8_t)(v >> 8), (uint8_t)v };
  [d appendBytes: b length: 2];
}

static void gsAppend32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { (uint8_t)(v >> 24), (uint8_t)(v >> 16),
                   (uint8_t)(v >> 8), (uint8_t)v };
  [d appendBytes: b length: 4];
}

+ (GSOType)osTypeFromString:(NSString *)string
{
  char c[5] = { 0 };

  if ([string length] != 4
      || ![string getCString: c maxLength: 5
                    encoding: NSMacOSRomanStringEncoding])
    return 0;
  return gsBE32((const uint8_t *)c);
}

+ (NSDictionary *)resourceEntryWithType:(GSOType)type
                             resourceID:(NSInteger)rid
                                   data:(NSData *)data
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithUnsignedInt: type], @"type",
    [NSNumber numberWithInteger: rid], @"id",
    data ? data : [NSData data], @"data", nil];
}

+ (NSData *)resourceForkWithResources:(NSArray *)entries
{
  /* Types in order of first appearance; each keeps its entries in order. */
  NSMutableArray *types = [NSMutableArray array];
  NSMutableDictionary *byType = [NSMutableDictionary dictionary];
  NSMutableData *dataArea = [NSMutableData data];
  NSMutableDictionary *offsets = [NSMutableDictionary dictionary];
  const uint32_t dataOffset = 256;

  for (NSDictionary *e in entries)
    {
      NSNumber *type = [e objectForKey: @"type"];
      NSInteger rid = [[e objectForKey: @"id"] integerValue];
      NSData *data = [e objectForKey: @"data"];

      if (type == nil || data == nil || rid < INT16_MIN || rid > INT16_MAX)
        return nil;
      NSMutableArray *list = [byType objectForKey: type];
      if (list == nil)
        {
          list = [NSMutableArray array];
          [byType setObject: list forKey: type];
          [types addObject: type];
        }
      [list addObject: e];
      /* Reference offsets are 24 bit and count from the start of the data. */
      if ([dataArea length] > 0x00FFFFFF)
        return nil;
      [offsets setObject: [NSNumber numberWithUnsignedInteger: [dataArea length]]
                  forKey: [NSValue valueWithNonretainedObject: e]];
      gsAppend32(dataArea, (uint32_t)[data length]);
      [dataArea appendData: data];
    }
  if ([types count] == 0 || [types count] > 0x8000
      || [dataArea length] > 0x00FFFFFF)
    return nil;

  uint32_t dataLen = (uint32_t)[dataArea length];
  uint32_t mapOffset = dataOffset + dataLen;
  NSUInteger typeCount = [types count];
  NSUInteger refTotal = [entries count];
  /* 16 header copy, 4 handle, 2 file ref, 2 attributes, 2 + 2 offsets, then
   * the type list (count + 8 per type) and 12 bytes per reference. */
  uint32_t typeListOff = 28;
  uint32_t mapLen = typeListOff + 2 + 8 * (uint32_t)typeCount
                  + 12 * (uint32_t)refTotal;
  NSMutableData *map = [NSMutableData dataWithCapacity: mapLen];
  NSMutableData *refs = [NSMutableData data];

  gsAppend32(map, dataOffset);
  gsAppend32(map, mapOffset);
  gsAppend32(map, dataLen);
  gsAppend32(map, mapLen);
  gsAppend32(map, 0);
  gsAppend16(map, 0);
  gsAppend16(map, 0);
  gsAppend16(map, typeListOff);
  gsAppend16(map, (uint16_t)mapLen);   /* no names: the name list is empty */
  gsAppend16(map, (uint16_t)(typeCount - 1));
  for (NSNumber *type in types)
    {
      NSArray *list = [byType objectForKey: type];
      /* Reference list offsets count from the start of the type list. */
      uint16_t refOff = (uint16_t)(2 + 8 * typeCount + [refs length]);

      gsAppend32(map, [type unsignedIntValue]);
      gsAppend16(map, (uint16_t)([list count] - 1));
      gsAppend16(map, refOff);
      for (NSDictionary *e in list)
        {
          uint32_t off = (uint32_t)[[offsets objectForKey:
            [NSValue valueWithNonretainedObject: e]] unsignedIntegerValue];

          gsAppend16(refs, (uint16_t)(int16_t)[[e objectForKey: @"id"]
                                                 integerValue]);
          gsAppend16(refs, 0xFFFF);          /* no name */
          gsAppend32(refs, off & 0x00FFFFFF); /* attributes 0 + offset */
          gsAppend32(refs, 0);               /* handle, filled by the system */
        }
    }
  [map appendData: refs];

  NSMutableData *fork = [NSMutableData dataWithCapacity:
    dataOffset + dataLen + mapLen];
  gsAppend32(fork, dataOffset);
  gsAppend32(fork, mapOffset);
  gsAppend32(fork, dataLen);
  gsAppend32(fork, mapLen);
  [fork setLength: dataOffset];
  [fork appendData: dataArea];
  [fork appendData: map];
  return fork;
}

+ (NSData *)resourceForkWithICNS:(NSData *)icns
{
  if ([icns length] == 0)
    return nil;
  return [self resourceForkWithResources: [NSArray arrayWithObject:
    [self resourceEntryWithType: [self osTypeFromString: @"icns"]
                     resourceID: GSCustomIconResourceID
                           data: icns]]];
}

/* Walks the type and reference lists once.  useID selects an exact ID;
 * otherwise the lowest ID of the type wins. */
static NSData *gsLookupResource(NSData *fork, GSOType type, BOOL useID,
                                int16_t wantID)
{
  const uint8_t *b = [fork bytes];
  NSUInteger len = [fork length];
  NSData *best = nil;
  int bestID = 0;

  if (len < 16 || type == 0)
    return nil;

  uint64_t dataOff = gsBE32(b), mapOff = gsBE32(b + 4);
  uint64_t dataLen = gsBE32(b + 8), mapLen = gsBE32(b + 12);
  /* Every offset and size comes from the file and is checked before use. */
  if (mapOff > len || mapLen > len - mapOff || mapLen < 30
      || dataOff > len || dataLen > len - dataOff)
    return nil;

  const uint8_t *map = b + mapOff;
  uint64_t tlOff = gsBE16(map + 24);
  if (tlOff + 2 > mapLen)
    return nil;
  const uint8_t *tl = map + tlOff;
  uint64_t tlAvail = mapLen - tlOff;
  /* The stored count is one less than the number of types. */
  if (gsBE16(tl) == 0xFFFF || 2 + ((uint64_t)gsBE16(tl) + 1) * 8 > tlAvail)
    return nil;
  uint32_t typeCount = (uint32_t)gsBE16(tl) + 1;

  for (uint32_t t = 0; t < typeCount; t++)
    {
      const uint8_t *te = tl + 2 + 8 * (uint64_t)t;

      if (gsBE32(te) != type)
        continue;
      uint32_t refCount = (uint32_t)gsBE16(te + 4) + 1;
      uint64_t refOff = gsBE16(te + 6);
      if (refOff > tlAvail || 12 * (uint64_t)refCount > tlAvail - refOff)
        return nil;
      for (uint32_t r = 0; r < refCount; r++)
        {
          const uint8_t *re = tl + refOff + 12 * (uint64_t)r;
          int rid = (int16_t)gsBE16(re);
          uint64_t off = ((uint32_t)re[5] << 16) | ((uint32_t)re[6] << 8) | re[7];

          if (useID && rid != wantID)
            continue;
          if (off + 4 > dataLen)
            return nil;
          uint64_t size = gsBE32(b + dataOff + off);
          if (size > dataLen - off - 4)
            return nil;
          if (best == nil || rid < bestID)
            {
              best = [NSData dataWithBytes: b + dataOff + off + 4
                                    length: (NSUInteger)size];
              bestID = rid;
            }
        }
      return best;
    }
  return nil;
}

+ (NSData *)dataForResourceType:(GSOType)type
                     resourceID:(NSInteger)rid
                         inFork:(NSData *)fork
{
  if (rid < INT16_MIN || rid > INT16_MAX)
    return nil;
  return gsLookupResource(fork, type, YES, (int16_t)rid);
}

+ (NSData *)firstDataForResourceType:(GSOType)type inFork:(NSData *)fork
{
  return gsLookupResource(fork, type, NO, 0);
}

+ (NSData *)icnsDataFromResourceFork:(NSData *)fork
{
  const uint8_t *b = [fork bytes];
  NSUInteger len = [fork length];

  /* Older versions stored the bare icns container as the fork.  A classic
   * fork cannot start with 'icns' (its first word is the data offset). */
  if (len >= 8 && memcmp(b, "icns", 4) == 0)
    {
      uint32_t n = gsBE32(b + 4);
      return (n >= 8 && n <= len) ? [fork subdataWithRange: NSMakeRange(0, n)]
                                  : nil;
    }
  NSData *icns = [self dataForResourceType: [self osTypeFromString: @"icns"]
                                resourceID: GSCustomIconResourceID
                                    inFork: fork];
  return [icns length] > 0 ? icns : nil;
}

- (NSData *)customIconData
{
  if (![self hasCustomIcon])
    return nil;
  return [[self class] icnsDataFromResourceFork: _resourceFork];
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
  return nil;
}

+ (NSData *)customIconDataForPath:(NSString *)path
{
  GSFileMetadata *md = [self metadataForFileAtPath: path];
  BOOL isDir = NO;

  if (md == nil || ![md hasCustomIcon])
    return nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir] && isDir)
    {
      GSFileMetadata *imd = [self metadataForFileAtPath:
        [path stringByAppendingPathComponent: @"Icon\r"]];

      return imd ? [self icnsDataFromResourceFork: [imd resourceFork]] : nil;
    }
  return [md customIconData];
}

/* 10.6 tar prefixes a quarantine value with "q/"; the Mac's own xattr holds
 * the plain "0000;..." value. */
+ (NSData *)plainQuarantine:(NSData *)value
{
  if ([value length] > 2 && memcmp([value bytes], "q/", 2) == 0)
    return [value subdataWithRange: NSMakeRange(2, [value length] - 2)];
  return value;
}

/* tar -x and dot_clean on 10.6 drop a sidecar quarantine value that lacks
 * the "q/" prefix; the prefix is not doubled. */
+ (NSData *)sidecarQuarantine:(NSData *)value
{
  NSMutableData *out;

  if ([value length] >= 2 && memcmp([value bytes], "q/", 2) == 0)
    return value;
  out = [NSMutableData dataWithBytes: "q/" length: 2];
  [out appendData: value];
  return out;
}

+ (BOOL)writeFolderIconICNS:(NSData *)icns atPath:(NSString *)folder error:(NSError **)error
{
  NSString *file = [folder stringByAppendingPathComponent: @"Icon\r"];
  NSFileManager *fm = [NSFileManager defaultManager];
  GSFileMetadata *imd;

  if ([fm fileExistsAtPath: file] == NO
      && [fm createFileAtPath: file contents: [NSData data] attributes: nil] == NO)
    {
      if (error)
        *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                     code: NSFileWriteUnknownError
                                 userInfo: nil];
      return NO;
    }
  imd = [self metadataForFileAtPath: file forceSidecar: NO];
  imd = imd ? [[imd copy] autorelease] : [[[GSFileMetadata alloc] init] autorelease];
  /* Finder leaves kHasCustomIcon off the Icon file itself (E18). */
  [imd setCustomIconData: icns];
  [imd setCustomIcon: NO];
  [imd setInvisible: YES];
  if ([imd writeToFileAtPath: file error: error] == NO)
    return NO;
  [self invalidateCachedMetadataForPath: file];
  return YES;
}

+ (BOOL)removeFolderIconAtPath:(NSString *)folder error:(NSError **)error
{
  NSString *file = [folder stringByAppendingPathComponent: @"Icon\r"];
  NSFileManager *fm = [NSFileManager defaultManager];

  if ([fm fileExistsAtPath: file] == NO)
    return YES;
  if ([fm removeFileAtPath: file handler: nil] == NO)
    {
      if (error)
        *error = [NSError errorWithDomain: NSCocoaErrorDomain
                                     code: NSFileWriteUnknownError
                                 userInfo: nil];
      return NO;
    }
  [fm removeFileAtPath: [self sidecarPathForFilePath: file] handler: nil];
  [self invalidateCachedMetadataForPath: file];
  return YES;
}

/* A folder cannot take a resource fork on a Mac, so a fork set on one goes
 * to its Icon file (or that file goes, for an emptied fork) and the write
 * proceeds as if the fork were unchanged. */
- (BOOL)_divertFolderIconAtPath:(NSString *)path error:(NSError **)error
{
  BOOL isDir = NO;
  NSData *icns;

  if (!(_modified & GSFieldResourceFork)
      || ![[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir]
      || !isDir)
    return YES;
  icns = [[self class] icnsDataFromResourceFork: _resourceFork];
  if (icns != nil
      ? ![[self class] writeFolderIconICNS: icns atPath: path error: error]
      : ![[self class] removeFolderIconAtPath: path error: error])
    return NO;
  /* The fork now lives in the Icon file, not in this folder's metadata. */
  _modified &= ~GSFieldResourceFork;
  DESTROY(_resourceFork);
  return YES;
}

+ (NSImage *)customIconImageForPath:(NSString *)path
{
  NSData *icns = [self customIconDataForPath: path];

  return icns ? [[[NSImage alloc] initWithData: icns] autorelease] : nil;
}

- (void)setCustomIconData:(NSData *)icnsData
{
  if (icnsData == nil || [icnsData length] == 0)
    {
      [self clearCustomIcon];
      return;
    }

  /* Finder reads the icon from the resource fork's 'icns' -16455 resource,
   * so the raw icns bytes alone would show nothing there. */
  [self setResourceFork: [[self class] resourceForkWithICNS: icnsData]];

  [self setCustomIcon: YES];
}

- (void)clearCustomIcon
{
  [self setCustomIcon: NO];
  [self setResourceFork: nil];
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
   * Finder label colours from fdFlags / lclr encoding:
   *   0 = none, 1 = red, 2 = orange, 3 = yellow,
   *   4 = green, 5 = blue, 6 = purple, 7 = grey
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
