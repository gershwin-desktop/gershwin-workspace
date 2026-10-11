/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import "GMDSFinderAttributes.h"
#import "GSFileMetadata.h"

NSString * const GMDSFSLabelKey = @"GSMDItemFSLabel";
NSString * const GMDSUserTagsKey = @"GSMDItemUserTags";

static NSDictionary *
row(NSString *key, NSString *attribute)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
          key, @"key", attribute, @"attribute", nil];
}

@implementation GMDSFinderAttributes

+ (NSArray *)attributesForMetadata:(GSFileMetadata *)metadata
{
  NSMutableArray *rows = [NSMutableArray array];
  NSMutableArray *seen = [NSMutableArray array];
  NSUInteger color = 0;
  NSString *tag;

  if (metadata) {
    color = [GSFileMetadata finderColorForLabel:
             (GSFileLabel)[metadata labelNumber]];
  }
  [rows addObject: row(GMDSFSLabelKey,
                       [NSString stringWithFormat: @"%lu",
                        (unsigned long)color])];

  for (tag in [metadata userTags]) {
    NSRange nl;

    if ([tag isKindOfClass: [NSString class]] == NO) {
      continue;
    }
    /* Later Finders append the colour number after a newline. */
    nl = [tag rangeOfString: @"\n"];
    if (nl.location != NSNotFound) {
      tag = [tag substringToIndex: nl.location];
    }
    if ([tag length] == 0 || [seen containsObject: tag]) {
      continue;
    }
    [seen addObject: tag];
    [rows addObject: row(GMDSUserTagsKey, tag)];
  }
  return rows;
}

+ (NSArray *)attributesForPath:(NSString *)path
{
  return [self attributesForMetadata:
          [GSFileMetadata metadataForFileAtPath: path forceSidecar: NO]];
}

@end
