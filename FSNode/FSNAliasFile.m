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
  /* NSFileManager instead of stat(): Windows file system paths are wide
   * characters, which stat() does not take. */
  NSDictionary *attrs = [[NSFileManager defaultManager]
                          fileAttributesAtPath: path traverseLink: NO];

  if (![[attrs fileType] isEqualToString: NSFileTypeRegular])
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
  unsigned long long size;

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
  size = [[[NSFileManager defaultManager] fileAttributesAtPath: path
                                                  traverseLink: NO] fileSize];
  if (size == 0 || size > ALIAS_DATA_MAX)
    {
      return nil;
    }
  record = [NSData dataWithContentsOfFile: path];
  return [[[FSNAlias alloc] initWithData: record] autorelease];
}

/* lstat, not stat: a symlink must be seen as the link, and a dangling one
 * has nothing to stat at all. */
static BOOL
isSymlink(NSString *path)
{
  struct stat st;

  return lstat([path fileSystemRepresentation], &st) == 0 && S_ISLNK(st.st_mode);
}

+ (NSString *)originalOfItemAtPath:(NSString *)path
{
  NSString *target;

  if (isSymlink(path))
    {
      target = [[NSFileManager defaultManager]
		 pathContentOfSymbolicLinkAtPath: path];
      if (target == nil)
	{
	  return nil;
	}
      if ([target isAbsolutePath] == NO)
	{
	  target = [[path stringByDeletingLastPathComponent]
		     stringByAppendingPathComponent: target];
	}
    }
  else
    {
      target = [[self aliasWithContentsOfFile: path] resolvePath];
    }
  if (target == nil
      || [[NSFileManager defaultManager] fileExistsAtPath: target] == NO)
    {
      return nil;
    }
  return [target stringByResolvingSymlinksInPath];
}

+ (BOOL)canShowOriginalForPaths:(NSArray *)paths
{
  NSString *path;

  if ([paths count] != 1)
    {
      return NO;
    }
  path = [paths objectAtIndex: 0];
  return isSymlink(path) || [self isAliasFileAtPath: path];
}

@end
