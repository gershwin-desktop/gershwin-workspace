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

- (void)invalidateCaches
{
  [GSFileMetadata invalidateAllCachedMetadata];
}

@end
