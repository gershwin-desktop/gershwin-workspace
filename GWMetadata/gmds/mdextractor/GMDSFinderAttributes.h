/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>

@class GSFileMetadata;

/* Index keys; they must match MDKit's attributes.plist. */
extern NSString * const GMDSFSLabelKey;
extern NSString * const GMDSUserTagsKey;

/*
 * The Finder label and tags of a file as rows for the "attributes" table
 * (dictionaries with "key" and "attribute"), so that smart folders and Find
 * can search them like Spotlight's kMDItemFSLabel and kMDItemUserTags.
 */
@interface GMDSFinderAttributes : NSObject

/* One GMDSFSLabelKey row with Finder's colour number as text ("0" for no
 * label, because Spotlight reports 0 and "label is not red" must match
 * unlabelled files) and one GMDSUserTagsKey row per distinct tag name. */
+ (NSArray *)attributesForMetadata:(GSFileMetadata *)metadata;

/* Reads the metadata from disk each time: the daemon outlives label changes,
 * so the shared per-path cache of GSFileMetadata must not be used. */
+ (NSArray *)attributesForPath:(NSString *)path;

@end
