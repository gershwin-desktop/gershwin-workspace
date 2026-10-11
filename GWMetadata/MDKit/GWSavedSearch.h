/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

/*
 * A Spotlight smart folder (".savedSearch" property list), read into the
 * query language of MDKit and written back from it.
 *
 * Only terms whose meaning is the same in both query languages are
 * translated. Everything else is collected in -unsupportedTerms; a saved
 * search with any unsupported term has no MDKit query at all, because
 * dropping a term would silently return different files than the original.
 * Approximations that still return the right kind of files (for example
 * matching a content type by file name extension) are listed in -notes.
 */
@interface GWSavedSearch : NSObject
{
  NSString *rawQuery;
  NSArray *scopes;
  BOOL finderFilesOnly;
  BOOL userFilesOnly;
  NSMutableArray *unsupported;
  NSMutableArray *notes;
  NSArray *paths;
  BOOL parsed;
  id tree;
}

/* Reads the file; nil with a message in *error when it is no saved search
 * or from a newer format. */
+ (GWSavedSearch *)savedSearchWithContentsOfFile:(NSString *)path
                                           error:(NSString **)error;

+ (GWSavedSearch *)savedSearchWithRawQuery:(NSString *)raw
                                    scopes:(NSArray *)scopes;

/* Builds the Spotlight form of an MDKit query description. Nil with a
 * message in *error when a term has no Spotlight equivalent. */
+ (GWSavedSearch *)savedSearchWithMDKitQuery:(NSString *)mdkQuery
                                 searchPaths:(NSArray *)searchPaths
                                       error:(NSString **)error;

- (NSString *)rawQuery;

/* Scope strings as stored: kMDQueryScope* names or absolute paths. */
- (NSArray *)scopes;

- (BOOL)finderFilesOnly;
- (BOOL)userFilesOnly;

/* Directories to search; nil means everywhere that is indexed. */
- (NSArray *)searchPaths;

/* MDKit query text, or nil when anything is unsupported. Relative dates
 * ($time.today(-7)) are resolved against date. */
- (NSString *)mdkQueryStringAtDate:(NSDate *)date;

- (NSArray *)unsupportedTerms;
- (NSArray *)notes;

/* Text for the viewer window: why there is no result, or what was
 * approximated. Nil when the search runs exactly as written. */
- (NSString *)statusText;

- (NSDictionary *)propertyList;
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)flag;

@end
