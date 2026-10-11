/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class GWSavedSearch;

/*
 * Turns what the Find window searched for into a Spotlight smart folder.
 * Only criteria with the same meaning in both are converted; for the rest
 * (contents, annotations, owner, kinds other than folder and application,
 * searching one folder level only) the conversion fails with a message
 * naming them, instead of saving a search that finds other files.
 */
@interface GWFindCriteria : NSObject

/* criteria is the Find window's dictionary: one entry per module, keyed by
 * the module's class name. */
+ (GWSavedSearch *)savedSearchForCriteria:(NSDictionary *)criteria
                              searchPaths:(NSArray *)paths
                                recursive:(BOOL)recursive
                                    error:(NSString **)error;

@end
