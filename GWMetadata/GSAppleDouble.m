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
    }
  return self;
}

- (instancetype)initWithData:(NSData *)data
{
  self = [super init];
  if (!self)
    return nil;

  _entries = [[NSMutableDictionary alloc] initWithCapacity: 4];

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
  return copy;
}

- (void)dealloc
{
  DESTROY(_entries);
  [super dealloc];
}

- (NSMutableDictionary *)mutableEntries
{
  return _entries;
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

- (NSData *)appleDoubleData
{
  NSArray *sortedIDs = [[_entries allKeys] sortedArrayUsingSelector:
    @selector(compare:)];
  NSUInteger entryCount = [sortedIDs count];

  if (entryCount == 0)
    return nil;

  /* Calculate total size */
  NSUInteger totalSize = APPLEDOUBLE_HEADER_SIZE
                       + entryCount * APPLEDOUBLE_ENTRY_SIZE;

  /* Collect entry data and compute offsets */
  NSMutableArray *dataBlocks = [NSMutableArray arrayWithCapacity: entryCount];
  for (NSNumber *key in sortedIDs)
    {
      NSData *entryData = [_entries objectForKey: key];
      [dataBlocks addObject: entryData];
      totalSize += [entryData length];
    }

  NSMutableData *result = [NSMutableData dataWithLength: totalSize];
  uint8_t *bytes = [result mutableBytes];

  /* Write header */
  writeBE32(bytes, APPLEDOUBLE_MAGIC);
  writeBE32(bytes + 4, APPLEDOUBLE_VERSION);
  /* Filler: bytes 8-23 are already zero from dataWithLength: */
  writeBE16(bytes + 24, entryCount);

  /* Write entry descriptors and data blocks */
  NSUInteger dataOffset = APPLEDOUBLE_HEADER_SIZE
                        + entryCount * APPLEDOUBLE_ENTRY_SIZE;

  {
    NSUInteger i;
    for (i = 0; i < entryCount; i++)
    {
      NSNumber *key = [sortedIDs objectAtIndex: i];
      NSData *entryData = [dataBlocks objectAtIndex: i];
      uint32_t entryID = [key unsignedIntValue];
      uint32_t dataLen = (uint32_t)[entryData length];

      NSUInteger descOffset = APPLEDOUBLE_HEADER_SIZE
                            + i * APPLEDOUBLE_ENTRY_SIZE;
      uint8_t *desc = bytes + descOffset;

      writeBE32(desc, entryID);
      writeBE32(desc + 4, dataOffset);
      writeBE32(desc + 8, dataLen);

      /* Copy data block */
      memcpy(bytes + dataOffset, [entryData bytes], dataLen);
      dataOffset += dataLen;
    }
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
