/* GWMetadataProvider.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GWMetadataProvider.h"
#import "GSFileMetadata.h"

@implementation GWMetadataProvider

+ (instancetype)sharedProvider
{
  static GWMetadataProvider *shared = nil;
  if (shared == nil)
    shared = [[self alloc] init];
  return shared;
}

- (NSColor *)labelColorForPath:(NSString *)path
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  if (md == nil)
    return nil;
  NSInteger label = [md labelNumber];
  if (label <= 0)
    return nil;
  return [GSFileMetadata colorForLabel: (GSFileLabel)label];
}

- (BOOL)isInvisibleAtPath:(NSString *)path
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  return md ? [md isInvisible] : NO;
}

- (NSImage *)customIconForPath:(NSString *)path
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  if (md && [md hasCustomIcon])
    return [md customIconAsImage];
  return nil;
}

- (NSPoint)iconPositionForPath:(NSString *)path
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  return md ? [md iconPosition] : NSMakePoint(-1, -1);
}

/* All of these read through +metadataForFileAtPath:, which already keeps a
 * path-keyed cache that -invalidateCaches clears, so a list view asking for
 * every row costs no extra syscalls. */

- (NSInteger)labelIndexForPath:(NSString *)path
{
  return [[GSFileMetadata metadataForFileAtPath: path] labelNumber];
}

- (NSString *)labelNameForPath:(NSString *)path
{
  NSInteger label = [self labelIndexForPath: path];
  return label > 0 ? [GSFileMetadata tagNameForLabel: (GSFileLabel)label]
                   : nil;
}

- (NSString *)commentForPath:(NSString *)path
{
  NSString *comment = [[GSFileMetadata metadataForFileAtPath: path]
                        finderComment];
  return [comment length] > 0 ? comment : nil;
}

- (BOOL)isExtensionHiddenForPath:(NSString *)path
{
  return [[GSFileMetadata metadataForFileAtPath: path] isExtensionHidden];
}

- (BOOL)isNameLockedForPath:(NSString *)path
{
  return [[GSFileMetadata metadataForFileAtPath: path] isNameLocked];
}

- (void)invalidateCaches
{
  [GSFileMetadata invalidateAllCachedMetadata];
}

@end
