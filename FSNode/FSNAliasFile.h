/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef _FSNALIASFILE_H_
#define _FSNALIASFILE_H_

#import "FSNAlias.h"

/* Alias FILES as a Finder stores them, as opposed to the bare records in
 * FSNAlias.h.  Reading them goes through GSFileMetadata (extended attributes
 * or a "._" sidecar). */
@interface FSNAlias (FSNAliasFile)

/* YES if the file at path is marked as an alias (kIsAlias in its Finder
 * Info, from an extended attribute or a "._" sidecar).  A data fork that
 * merely looks like a record is not enough: a text file starting with
 * "book" must not be mistaken for an alias. */
+ (BOOL)isAliasFileAtPath:(NSString *)path;

/* The alias record of an alias file, or nil if the file is not marked as an
 * alias or holds no record that parses.  The record is searched in the 'alis'
 * resource of the resource fork (classic and 10.6 Finder aliases, the 10.6
 * bookmark form included) and then in the data fork (bookmark files written
 * by NSURL). */
+ (FSNAlias *)aliasWithContentsOfFile:(NSString *)path;

@end

#endif
