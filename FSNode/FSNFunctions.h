/* FSNFunctions.h
 *  
 * Copyright (C) 2004-2016 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola <rm@gnu.org>
 * Date: March 2004
 *
 * This file is part of the GNUstep FSNode framework
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#ifndef FSN_FUNCTIONS_H
#define FSN_FUNCTIONS_H

enum GSFilenameExtensionDisplayMode {
    GSFilenameExtensionDisplayAll = 0,
    GSFilenameExtensionHidePackageExtensions = 1,
    GSFilenameExtensionHideAll = 2
};
typedef enum GSFilenameExtensionDisplayMode GSFilenameExtensionDisplayMode;

GSFilenameExtensionDisplayMode GSCurrentExtensionDisplayMode(void);

BOOL GSExtensionIsPackageExtension(NSString *extension);

BOOL GSFilenameExtensionIsNumeric(NSString *ext);

NSString *GSDisplayNameForFilename(NSString *filename, GSFilenameExtensionDisplayMode mode);

NSString *GSFilenameHiddenExtension(NSString *filename, GSFilenameExtensionDisplayMode mode);

NSString *path_separator(void);

BOOL isSubpathOfPath(NSString *p1, NSString *p2);

BOOL pathsAreOnSameVolume(NSString *path1, NSString *path2);

NSDragOperation dragOperationForCurrentModifierFlags(void);

NSString *subtractFirstPartFromPath(NSString *path, NSString *firstpart);

NSComparisonResult compareWithExtType(id r1, id r2, void *context);

NSString *sizeDescription(unsigned long long size);

NSArray *makePathsSelection(NSArray *selnodes);

double myrintf(double a);

void showAlertNoPermission(Class c, NSString *name);
void showAlertInRecycler(Class c);
void showAlertInvalidName(Class c);
NSInteger showAlertExtensionChange(Class c, NSString *extension);
void showAlertNameInUse(Class c, NSString *newname);

/* Icon-position coordinate conversion (single source of truth).
 *
 * DS_Store Iloc / FinderInfo fdLocation use top-left origin (y grows down);
 * GNUstep views use bottom-left origin (y grows up).  Both stored as icon
 * CENTER coordinates.  Conversion is symmetric about a reference height. */
/* The canonical iloc <-> view-center transform lives in FSNIconPlacement.h
 * (Foundation-only, co-located with the other placement geometry). */

@class NSColor;

/* Draw a Finder label-colour dot (drop shadow + filled oval + hairline
 * border) into the current graphics context at dotRect.  Single source for
 * the badge drawing that was duplicated across icon/list/browser/path/dock
 * cells; each caller still computes its own dotRect so placement/size are
 * unchanged.  No-op when color is nil. */
void FSNDrawLabelDot(NSRect dotRect, NSColor *color);

#endif // FSN_FUNCTIONS_H
