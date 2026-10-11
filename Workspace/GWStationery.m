/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWStationery.h"
#import "GWMetadataCopier.h"
#import "GSFileMetadata.h"

static NSError *
stationeryError(NSString *text)
{
  return [NSError errorWithDomain: @"GWStationeryErrorDomain"
                             code: 1
                         userInfo: [NSDictionary dictionaryWithObject: text
                                                               forKey: NSLocalizedDescriptionKey]];
}

@implementation GWStationery

+ (NSString *)copyPathForStationeryAtPath:(NSString *)path
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [path stringByDeletingLastPathComponent];
  NSString *name = [path lastPathComponent];
  NSString *ext = [name pathExtension];
  NSString *base = ([ext length] > 0) ? [name stringByDeletingPathExtension] : name;
  NSUInteger n;

  for (n = 1; ; n++)
    {
      NSString *stem = (n == 1)
        ? [base stringByAppendingString: @" copy"]
        : [NSString stringWithFormat: @"%@ copy %lu", base, (unsigned long)n];
      NSString *candidate = [dir stringByAppendingPathComponent:
        ([ext length] > 0) ? [stem stringByAppendingPathExtension: ext] : stem];

      if ([fm fileExistsAtPath: candidate] == NO)
        return candidate;
    }
}

+ (NSString *)makeCopyOfStationeryAtPath:(NSString *)path error:(NSError **)error
{
  NSString *copyPath = [self copyPathForStationeryAtPath: path];
  GWMetadataCopier *copier = [[GWMetadataCopier new] autorelease];
  NSError *metadataError = nil;
  GSFileMetadata *md;

  if ([copier copyItemAtPath: path toPath: copyPath handler: nil
               metadataError: &metadataError] == NO)
    {
      if (error) *error = stationeryError(@"The stationery pad could not be copied.");
      return nil;
    }
  if (metadataError != nil)
    {
      if (error) *error = metadataError;
      return nil;
    }
  /* The cache still holds the copy path's state from before it existed. */
  [GSFileMetadata invalidateCachedMetadataForPath: copyPath];
  md = [GSFileMetadata metadataForFileAtPath: copyPath];
  if (md == nil)
    {
      if (error) *error = stationeryError(@"The copy has no Finder information.");
      return nil;
    }
  [md setStationery: NO];
  if ([md writeToFileAtPath: copyPath error: error] == NO)
    return nil;
  return copyPath;
}

@end
