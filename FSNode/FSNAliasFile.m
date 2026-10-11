/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "FSNAliasFile.h"
#import "GSFileMetadata.h"

#include <string.h>
#include <sys/stat.h>

/* A record is a few hundred bytes; this only stops a mislabelled huge file
 * from being read whole. */
#define ALIAS_DATA_MAX (1024 * 1024)

static uint32_t
be32(const uint8_t *b)
{
  return ((uint32_t)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

/* The first alias writer laid its fork out with a type count of 1 and a
 * reference list offset of 18, which points past its 46 byte map, so an
 * honest Resource Manager reader finds nothing.  Aliases written that way
 * are still on users' disks; this accepts exactly that layout (map 46 bytes
 * long, one 'alis' type entry, record at the start of the data area) and
 * nothing else. */
static NSData *
recordFromFirstWriterFork(NSData *fork)
{
  const uint8_t *f = [fork bytes];
  NSUInteger len = [fork length];
  uint32_t dataOff, mapOff, dataLen, mapLen, recLen;

  if (len < 256 + 4 + 46)
    {
      return nil;
    }
  dataOff = be32(f);
  mapOff = be32(f + 4);
  dataLen = be32(f + 8);
  mapLen = be32(f + 12);
  if (dataOff != 256 || mapLen != 46 || dataLen < 4
      || mapOff != 256 + (uint64_t)dataLen || len != (uint64_t)mapOff + 46)
    {
      return nil;
    }
  recLen = be32(f + dataOff);
  if (recLen != dataLen - 4
      || memcmp(f + mapOff + 28, "\x00\x01" "alis" "\x00\x00\x00\x12", 10) != 0)
    {
      return nil;
    }
  return [fork subdataWithRange: NSMakeRange(dataOff + 4, recLen)];
}

@implementation FSNAlias (FSNAliasFile)

+ (BOOL)isAliasFileAtPath:(NSString *)path
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) != 0 || !S_ISREG(st.st_mode))
    {
      return NO;
    }
  return [[GSFileMetadata metadataForFileAtPath: path] isAlias];
}

+ (FSNAlias *)aliasWithContentsOfFile:(NSString *)path
{
  GSFileMetadata *md;
  NSData *fork;
  NSData *record;
  FSNAlias *alias;
  struct stat st;

  if ([self isAliasFileAtPath: path] == NO)
    {
      return nil;
    }
  md = [GSFileMetadata metadataForFileAtPath: path];
  fork = [md resourceFork];
  record = fork ? [GSFileMetadata firstDataForResourceType:
		     [GSFileMetadata osTypeFromString: @"alis"] inFork: fork] : nil;
  if (record == nil && fork != nil)
    {
      record = recordFromFirstWriterFork(fork);
    }
  alias = record ? [[[FSNAlias alloc] initWithData: record] autorelease] : nil;
  if (alias != nil)
    {
      return alias;
    }
  if (stat([path fileSystemRepresentation], &st) != 0
      || st.st_size <= 0 || st.st_size > ALIAS_DATA_MAX)
    {
      return nil;
    }
  record = [NSData dataWithContentsOfFile: path];
  return [[[FSNAlias alloc] initWithData: record] autorelease];
}

@end
