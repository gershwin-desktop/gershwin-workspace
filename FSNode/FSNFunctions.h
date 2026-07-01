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
@class NSView;

/* Reference height used for iloc<->GNUstep conversion: the enclosing window's
 * content-view height (like macOS Finder), so positions are relative to the
 * visible content area and survive window resize.  Falls back to the view's
 * own bounds height, then 600.0 if nothing is available yet. */
CGFloat FSNReferenceHeightForView(NSView *view);

/* Flip a center point between iloc (top-left) and GNUstep (bottom-left).
 * The transform is its own inverse, so one implementation serves both. */
NSPoint FSNFlipCenterForReferenceHeight(NSPoint center, CGFloat refH);

@class NSColor;

/* Draw a Finder label-colour dot (drop shadow + filled oval + hairline
 * border) into the current graphics context at dotRect.  Single source for
 * the badge drawing that was duplicated across icon/list/browser/path/dock
 * cells; each caller still computes its own dotRect so placement/size are
 * unchanged.  No-op when color is nil. */
void FSNDrawLabelDot(NSRect dotRect, NSColor *color);

#endif // FSN_FUNCTIONS_H
