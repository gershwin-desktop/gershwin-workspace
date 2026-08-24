/* GSAppleDouble.m
 *
 * AppleSingle/AppleDouble V2 format handler implementation.
 * Format spec: https://kaiser-edv.de/documents/AppleSingle_AppleDouble.pdf
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GSAppleDouble.h"
#import <GNUstepBase/GNUstep.h>

/* Private interface for internal access to the entries dictionary */
@interface GSAppleDouble (Private)
- (NSMutableDictionary *)mutableEntries;
- (NSMutableDictionary *)mutableXattrs;
@end



/*
 * AppleDouble magic, big-endian: 0x00 0x05 0x16 0x07
 */
#define APPLEDOUBLE_MAGIC    0x00051607

/*
 * AppleDouble version, big-endian: 0x00 0x02 0x00 0x00
 */
#define APPLEDOUBLE_VERSION  0x00020000

/*
 * Header size: magic(4) + version(4) + filler(16) + entryCount(2) = 26 bytes.
 */
#define APPLEDOUBLE_HEADER_SIZE  26

/*
 * Entry descriptor size: entryID(4) + offset(4) + length(4) = 12 bytes.
 */
#define APPLEDOUBLE_ENTRY_SIZE   12

/*
 * Apple "ATTR" extended-attributes blob magic, big-endian: 0x41 0x54 0x54 0x52
 * ("ATTR").  macOS embeds this after the 32-byte FinderInfo + 2-byte padding
 * inside entry ID 9 whenever a file carries xattrs (com.apple.FinderInfo is
 * only 32 bytes; longer entry-9 data means an ATTR blob follows).
 */
#define APPLEDOUBLE_ATTR_MAGIC   0x41545452

/* ATTR header size: magic(4)+debug(4)+total(4)+dataStart(4)+dataLen(4)
 * +reserved(12)+flags(2)+numAttrs(2) = 36 bytes. */
#define APPLEDOUBLE_ATTR_HDR_SIZE 36

/* FinderInfo is 32 bytes; the ATTR blob is preceded by 2 padding bytes. */
#define APPLEDOUBLE_FINFO_SIZE    32
#define APPLEDOUBLE_ATTR_PAD      2

static uint32_t
readBE32(const uint8_t *bytes)
{
  return ((uint32_t)bytes[0] << 24)
       | ((uint32_t)bytes[1] << 16)
       | ((uint32_t)bytes[2] << 8)
       |  (uint32_t)bytes[3];
}

static void
writeBE32(uint8_t *bytes, uint32_t value)
{
  bytes[0] = (value >> 24) & 0xFF;
  bytes[1] = (value >> 16) & 0xFF;
  bytes[2] = (value >> 8)  & 0xFF;
  bytes[3] =  value        & 0xFF;
}

static void
writeBE16(uint8_t *bytes, uint16_t value)
{
  bytes[0] = (value >> 8) & 0xFF;
  bytes[1] =  value       & 0xFF;
}

@implementation GSAppleDouble

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _entries = [[NSMutableDictionary alloc] initWithCapacity: 4];
      _xattrs = [[NSMutableDictionary alloc] initWithCapacity: 4];
    }
  return self;
}

/* Parse the Apple "ATTR" extended-attributes blob found at absolute file
 * offset `base` (the "ATTR" magic) inside the full AppleDouble buffer
 * `bytes`/`length`.  xattr value offsets stored in the blob are absolute
 * from the start of the AppleDouble file, so we resolve them against
 * `bytes` directly.  Malformed pieces are skipped rather than crashing. */
- (void)_parseAttrBlobFromBytes:(const uint8_t *)bytes
                         length:(NSUInteger)length
               atAbsoluteOffset:(uint32_t)base
{
  if ((uint64_t)base + APPLEDOUBLE_ATTR_HDR_SIZE > length)
    return;

  uint32_t magic = readBE32(bytes + base);
  if (magic != APPLEDOUBLE_ATTR_MAGIC)
    return;

  uint32_t total = readBE32(bytes + base + 8);
  uint16_t numAttrs = (bytes[base + 34] << 8) | bytes[base + 35];

  /* The ATTR header references absolute offsets; bound them. */
  if ((uint64_t)base + APPLEDOUBLE_ATTR_HDR_SIZE + (uint64_t)numAttrs * 12 > length)
    return;

  uint32_t entryOff = base + APPLEDOUBLE_ATTR_HDR_SIZE;
  for (uint16_t i = 0; i < numAttrs; i++)
    {
      if ((uint64_t)entryOff + 11 > length)
        break;

      uint32_t valueOff = readBE32(bytes + entryOff);
      uint32_t valueLen = readBE32(bytes + entryOff + 4);
      uint8_t nameLen = bytes[entryOff + 10];

      if (nameLen == 0 || (uint64_t)entryOff + 11 + nameLen > length)
        break;

      /* Value offset/length are absolute within the AppleDouble buffer. */
      if ((uint64_t)valueOff + (uint64_t)valueLen > length)
        {
          entryOff += 12;
          continue;
        }

      NSData *nameData = [NSData dataWithBytes: bytes + entryOff + 11
                                        length: nameLen];
      /* Owned; released at the end of this iteration. */
      NSString *full = [[NSString alloc] initWithData: nameData
                                             encoding: NSUTF8StringEncoding];
      /* xattr names from macOS include a trailing NUL; drop it.  The
       * trimmed variant is autoreleased - only `full` is owned here. */
      NSString *name = full;
      if (name != nil && [name length] > 0
          && [name characterAtIndex: [name length] - 1] == 0)
        name = [name substringToIndex: [name length] - 1];

      if (name != nil && valueLen > 0)
        {
          NSData *value = [NSData dataWithBytes: bytes + valueOff
                                         length: valueLen];
          [_xattrs setObject: value forKey: name];
        }
      DESTROY(full);

      /* Entries are 4-byte aligned (11 fixed + nameLen, then pad). */
      uint32_t row = 11 + nameLen;
      row = (row + 3) & ~((uint32_t)3);
      entryOff += row;
    }
  (void)total;
}

- (instancetype)initWithData:(NSData *)data
{
  self = [super init];
  if (!self)
    return nil;

  _entries = [[NSMutableDictionary alloc] initWithCapacity: 4];
  _xattrs = [[NSMutableDictionary alloc] initWithCapacity: 4];

  const uint8_t *bytes = [data bytes];
  NSUInteger length = [data length];

  /* Must be at least large enough for header + one entry descriptor */
  if (length < APPLEDOUBLE_HEADER_SIZE + APPLEDOUBLE_ENTRY_SIZE)
    {
      DESTROY(self);
      return nil;
    }

  /* Validate magic */
  uint32_t magic = readBE32(bytes);
  if (magic != APPLEDOUBLE_MAGIC)
    {
      DESTROY(self);
      return nil;
    }

  /* Validate version */
  uint32_t version = readBE32(bytes + 4);
  if (version != APPLEDOUBLE_VERSION)
    {
      DESTROY(self);
      return nil;
    }

  /* Read entry count */
  uint16_t entryCount = (bytes[24] << 8) | bytes[25];

  /* Check total size: header + entryCount descriptors + data */
  NSUInteger descriptorsEnd = APPLEDOUBLE_HEADER_SIZE
                            + entryCount * APPLEDOUBLE_ENTRY_SIZE;
  if (descriptorsEnd > length)
    {
      DESTROY(self);
      return nil;
    }

  /* Parse each entry descriptor */
  {
    uint16_t i;
    for (i = 0; i < entryCount; i++)
    {
      NSUInteger descOffset = APPLEDOUBLE_HEADER_SIZE
                            + i * APPLEDOUBLE_ENTRY_SIZE;
      const uint8_t *desc = bytes + descOffset;

      uint32_t entryID  = readBE32(desc);
      uint32_t dataOff  = readBE32(desc + 4);
      uint32_t dataLen  = readBE32(desc + 8);

      /* Validate offset and length.  Compute the sum in 64-bit so a
       * crafted (dataOff, dataLen) cannot wrap the 32-bit addition and
       * slip past this bound check into an out-of-bounds read below. */
      if ((uint64_t)dataOff + (uint64_t)dataLen > length
          || dataOff < descriptorsEnd)
        {
          /* Malformed entry; skip it rather than failing entirely */
          continue;
        }

      NSData *entryData = [NSData dataWithBytes: bytes + dataOff
                                         length: dataLen];
      [_entries setObject: entryData
                   forKey: [NSNumber numberWithUnsignedInt: entryID]];

      /* macOS stores xattrs (com.apple.FinderInfo, _kMDItemUserTags, ...)
       * in an "ATTR" blob after the 32-byte FinderInfo inside entry 9. */
      if (entryID == GSAppleDoubleFinderInfo && dataLen > APPLEDOUBLE_FINFO_SIZE)
        {
          [self _parseAttrBlobFromBytes: bytes
                                 length: length
                       atAbsoluteOffset: dataOff
                                      + APPLEDOUBLE_FINFO_SIZE
                                      + APPLEDOUBLE_ATTR_PAD];
          /* Expose only the 32-byte FinderInfo, not the ATTR blob. */
          [_entries setObject:
              [entryData subdataWithRange:
                NSMakeRange(0, APPLEDOUBLE_FINFO_SIZE)]
                         forKey: [NSNumber numberWithUnsignedInt: entryID]];
        }
    }
  }

  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  GSAppleDouble *copy = [[GSAppleDouble allocWithZone: zone] init];
  for (NSNumber *key in _entries)
    {
      id value = [_entries objectForKey: key];
      [[copy mutableEntries] setObject: value forKey: key];
    }
  for (NSString *key in _xattrs)
    {
      [[copy mutableXattrs] setObject: [_xattrs objectForKey: key]
                               forKey: key];
    }
  return copy;
}

- (void)dealloc
{
  DESTROY(_entries);
  DESTROY(_xattrs);
  [super dealloc];
}

- (NSMutableDictionary *)mutableEntries
{
  return _entries;
}

- (NSMutableDictionary *)mutableXattrs
{
  return _xattrs;
}

- (void)setEntry:(GSAppleDoubleEntryID)entryID data:(NSData *)data
{
  if (data)
    [_entries setObject: data
                 forKey: [NSNumber numberWithUnsignedInt: entryID]];
  else
    [_entries removeObjectForKey: [NSNumber numberWithUnsignedInt: entryID]];
}

- (NSData *)dataForEntry:(GSAppleDoubleEntryID)entryID
{
  return [_entries objectForKey: [NSNumber numberWithUnsignedInt: entryID]];
}

- (NSData *)finderInfo
{
  return [self dataForEntry: GSAppleDoubleFinderInfo];
}

- (void)setFinderInfo:(NSData *)data
{
  [self setEntry: GSAppleDoubleFinderInfo data: data];
}

- (NSData *)resourceFork
{
  return [self dataForEntry: GSAppleDoubleResourceFork];
}

- (void)setResourceFork:(NSData *)data
{
  [self setEntry: GSAppleDoubleResourceFork data: data];
}

- (BOOL)hasFinderInfo
{
  return [self finderInfo] != nil;
}

- (BOOL)hasResourceFork
{
  return [self resourceFork] != nil;
}

- (void)setXattr:(NSData *)value forKey:(NSString *)name
{
  if (value && [value length] > 0 && name && [name length] > 0)
    [_xattrs setObject: value forKey: name];
  else
    [_xattrs removeObjectForKey: name];
}

- (NSDictionary<NSString *, NSData *> *)extendedAttributes
{
  return [NSDictionary dictionaryWithDictionary: _xattrs];
}

/* Serialize.  Two shapes, mirroring what macOS itself writes:
 *
 * Classic (no staged xattrs): entry 9 = FinderInfo[32], entry 2 = fork.
 * ATTR (>=1 staged xattr):    entry 9 = FinderInfo[32] + pad[2]
 *                             + ATTR header[36] + 4-byte-aligned records
 *                             + packed values; entry 2 keeps the fork.
 * Entry order is FinderInfo first, ResourceFork last (samba's adouble.c
 * notes both positions are load-bearing for Mac readers). */
- (NSData *)appleDoubleData
{
  NSData *finderInfo = [_entries objectForKey:
    [NSNumber numberWithUnsignedInt: GSAppleDoubleFinderInfo]];
  NSData *resourceFork = [_entries objectForKey:
    [NSNumber numberWithUnsignedInt: GSAppleDoubleResourceFork]];

  /* Drop a stale over-long entry 9 (only possible via setEntry: misuse;
   * parsing already truncates). */
  if (finderInfo && [finderInfo length] > APPLEDOUBLE_FINFO_SIZE)
    finderInfo = [finderInfo subdataWithRange:
      NSMakeRange(0, APPLEDOUBLE_FINFO_SIZE)];

  NSArray *xattrNames = [[_xattrs allKeys]
    sortedArrayUsingSelector: @selector(compare:)];
  BOOL attrMode = [xattrNames count] > 0;
  NSUInteger valuesLength = 0;
  NSUInteger recordsSize = 0;

  /* Nothing at all -> nothing to write (callers treat nil as "remove
   * any sidecar"). */
  if (!attrMode
      && (!finderInfo || [finderInfo length] == 0)
      && (!resourceFork || [resourceFork length] == 0)
      && [_entries count] <= 2)
    return nil;

  uint8_t fi[APPLEDOUBLE_FINFO_SIZE] = {0};
  if (finderInfo && [finderInfo length] >= APPLEDOUBLE_FINFO_SIZE)
    memcpy(fi, [finderInfo bytes], APPLEDOUBLE_FINFO_SIZE);

  /* --- size pass ------------------------------------------------------ */
  NSUInteger entryCount;
  NSUInteger fiLen, rfLen, extLen = 0;

  if (attrMode)
    {
      recordsSize = 0;
      valuesLength = 0;
      for (NSString *name in xattrNames)
        {
          NSUInteger nameLen = [name lengthOfBytesUsingEncoding:
                                  NSUTF8StringEncoding] + 1 /* NUL */;
          recordsSize += (11 + nameLen + 3) & ~(NSUInteger)3;
          valuesLength += [[_xattrs objectForKey: name] length];
        }
      extLen = APPLEDOUBLE_FINFO_SIZE + APPLEDOUBLE_ATTR_PAD
             + APPLEDOUBLE_ATTR_HDR_SIZE + recordsSize
             + valuesLength;
      fiLen = extLen;
      entryCount = 2;                 /* 9 + 2, exactly like macOS */
    }
  else
    {
      fiLen = (finderInfo && [finderInfo length] > 0)
            ? APPLEDOUBLE_FINFO_SIZE : 0;
      entryCount = (fiLen ? 1 : 0) + 1;   /* 9? + always-2 */
    }
  rfLen = resourceFork ? [resourceFork length] : 0;

  /* Remaining custom entries (anything other than 9/2) trail behind. */
  NSMutableArray *extraIDs = [NSMutableArray array];
  for (NSNumber *key in _entries)
    {
      uint32_t idv = [key unsignedIntValue];
      if (idv != GSAppleDoubleFinderInfo
          && idv != GSAppleDoubleResourceFork)
        [extraIDs addObject: key];
    }
  [extraIDs sortUsingSelector: @selector(compare:)];
  entryCount += [extraIDs count];

  NSUInteger totalSize = APPLEDOUBLE_HEADER_SIZE
                       + entryCount * APPLEDOUBLE_ENTRY_SIZE
                       + fiLen + rfLen;
  for (NSNumber *key in extraIDs)
    totalSize += [[_entries objectForKey: key] length];

  /* --- emit pass ------------------------------------------------------ */
  NSMutableData *result = [NSMutableData dataWithLength: totalSize];
  uint8_t *bytes = [result mutableBytes];

  writeBE32(bytes, APPLEDOUBLE_MAGIC);
  writeBE32(bytes + 4, APPLEDOUBLE_VERSION);
  /* Filler: real Macs write the filesystem name here; parsers ignore it,
   * but byte-faithful output costs nothing. */
  memcpy(bytes + 8, "Mac OS X", 8);
  memset(bytes + 16, ' ', 8);
  writeBE16(bytes + 24, (uint16_t)entryCount);

  NSUInteger descCursor = APPLEDOUBLE_HEADER_SIZE;
  NSUInteger dataCursor = APPLEDOUBLE_HEADER_SIZE
                        + entryCount * APPLEDOUBLE_ENTRY_SIZE;

  /* Entry 9 first. */
  if (attrMode)
    {
      writeBE32(bytes + descCursor, GSAppleDoubleFinderInfo);
      writeBE32(bytes + descCursor + 4, (uint32_t)dataCursor);
      writeBE32(bytes + descCursor + 8, (uint32_t)fiLen);
      descCursor += APPLEDOUBLE_ENTRY_SIZE;

      uint8_t *e = bytes + dataCursor;         /* entry 9 data */
      NSUInteger recordsStart = APPLEDOUBLE_FINFO_SIZE
                              + APPLEDOUBLE_ATTR_PAD
                              + APPLEDOUBLE_ATTR_HDR_SIZE;
      memcpy(e, fi, APPLEDOUBLE_FINFO_SIZE);

      uint8_t *h = e + APPLEDOUBLE_FINFO_SIZE + APPLEDOUBLE_ATTR_PAD;
      writeBE32(h, APPLEDOUBLE_ATTR_MAGIC);
      /* debug_tag stays 0 - unchecked by every known reader */
      /* total_size is the END of the ATTR region relative to nothing:
       * absolute file offset of entry 9's last byte (= dstart + dlen). */
      writeBE32(h + 8,  (uint32_t)(dataCursor + fiLen));
      writeBE32(h + 12, (uint32_t)(dataCursor + recordsStart
                                   + recordsSize));
      writeBE32(h + 16, (uint32_t)valuesLength);
      writeBE16(h + 32, 0);                            /* flags         */
      writeBE16(h + 34, (uint16_t)[xattrNames count]);

      NSUInteger rec = recordsStart;
      NSUInteger valAbs = dataCursor + recordsStart + recordsSize;
      for (NSString *name in xattrNames)
        {
          NSData *value = [_xattrs objectForKey: name];
          NSUInteger nameLen = [name lengthOfBytesUsingEncoding:
                                  NSUTF8StringEncoding] + 1;
          writeBE32(e + rec,      (uint32_t)valAbs);
          writeBE32(e + rec + 4,  (uint32_t)[value length]);
          writeBE16(e + rec + 8,  0);
          e[rec + 10] = (uint8_t)nameLen;
          memcpy(e + rec + 11, [name UTF8String], nameLen - 1);
          e[rec + 11 + nameLen - 1] = 0;

          memcpy(bytes + valAbs, [value bytes], [value length]);
          valAbs += [value length];
          rec += (11 + nameLen + 3) & ~(NSUInteger)3;
        }
      dataCursor += fiLen;
    }
  else if (fiLen)
    {
      writeBE32(bytes + descCursor, GSAppleDoubleFinderInfo);
      writeBE32(bytes + descCursor + 4, (uint32_t)dataCursor);
      writeBE32(bytes + descCursor + 8, (uint32_t)fiLen);
      descCursor += APPLEDOUBLE_ENTRY_SIZE;
      memcpy(bytes + dataCursor, fi, APPLEDOUBLE_FINFO_SIZE);
      dataCursor += fiLen;
    }

  /* Entry 2 last among the well-known ones - present even when empty,
   * matching Mac-produced files. */
  writeBE32(bytes + descCursor, GSAppleDoubleResourceFork);
  writeBE32(bytes + descCursor + 4, (uint32_t)dataCursor);
  writeBE32(bytes + descCursor + 8, (uint32_t)rfLen);
  descCursor += APPLEDOUBLE_ENTRY_SIZE;
  if (rfLen)
    {
      memcpy(bytes + dataCursor, [resourceFork bytes], rfLen);
      dataCursor += rfLen;
    }

  for (NSNumber *key in extraIDs)
    {
      NSData *data = [_entries objectForKey: key];
      writeBE32(bytes + descCursor, [key unsignedIntValue]);
      writeBE32(bytes + descCursor + 4, (uint32_t)dataCursor);
      writeBE32(bytes + descCursor + 8, (uint32_t)[data length]);
      descCursor += APPLEDOUBLE_ENTRY_SIZE;
      memcpy(bytes + dataCursor, [data bytes], [data length]);
      dataCursor += [data length];
    }

  return result;
}

#pragma mark - Convenience class methods

+ (NSData *)finderInfoFromAppleDoubleData:(NSData *)data
{
  GSAppleDouble *ad = [[self alloc] initWithData: data];
  NSData *fi = nil;
  if (ad)
    {
      fi = [[ad finderInfo] retain];
      DESTROY(ad);
    }
  return [fi autorelease];
}

+ (NSData *)resourceForkFromAppleDoubleData:(NSData *)data
{
  GSAppleDouble *ad = [[self alloc] initWithData: data];
  NSData *rf = nil;
  if (ad)
    {
      rf = [[ad resourceFork] retain];
      DESTROY(ad);
    }
  return [rf autorelease];
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"<GSAppleDouble: entries=%@ finderInfo=%@ resourceFork=%lu bytes>",
    [_entries allKeys],
    ([self hasFinderInfo] ? @"YES" : @"NO"),
    (unsigned long)[[self resourceFork] length]];
}

@end
