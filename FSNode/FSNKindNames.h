/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* The one table that turns a file extension into the human readable kind
 * the list view's Kind column, the Summary Info window and the Inspector
 * show. */
@interface FSNKindNames : NSObject

/* Localized kind for a well-known extension, nil for any other. */
+ (NSString *)kindForExtension:(NSString *)extension;

/* YES for a name that is an identifier rather than words for a person, such
 * as a pasteboard type (NSPDFPboardType) or a UTI (public.plain-text).
 * Applications declare such names as the "type name" of a document type. */
+ (BOOL)isIdentifierName:(NSString *)name;

@end
