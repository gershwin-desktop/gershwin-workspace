/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The column view options.  A 10.6 Finder keeps them once for all folders
 * (com.apple.finder StandardViewOptions/ColumnViewOptions, E30), not per
 * folder, so they live here once, in the application's defaults, and every
 * FSNBrowser follows them at once. */

#ifndef FSN_COLUMN_VIEW_OPTIONS_H
#define FSN_COLUMN_VIEW_OPTIONS_H

#import <Foundation/Foundation.h>
#import "FSNArrangement.h"

/* Posted (object: the shared options) when an option changed, by a setter
 * or by the defaults changing underneath. */
extern NSString * const FSNColumnViewOptionsDidChangeNotification;

/* The defaults keys, in the application's domain.  Named for what they
 * mean, unlike two of Finder's (E30: Finder's ShowPreview means "show
 * icons", its ColumnShowIcons "show preview column"). */
extern NSString * const FSNColumnViewTextSizeKey;            /* integer 10..16 */
extern NSString * const FSNColumnViewShowsIconsKey;          /* bool */
extern NSString * const FSNColumnViewShowsIconPreviewKey;    /* bool */
extern NSString * const FSNColumnViewShowsPreviewColumnKey;  /* bool */
extern NSString * const FSNColumnViewArrangeByKey;           /* Finder code, or "none" */
extern NSString * const FSNColumnViewColumnWidthKey;         /* integer, points */

/* The width of every column until the user sets another one (E30). */
extern const CGFloat FSNColumnViewDefaultColumnWidth;

@interface FSNColumnViewOptions : NSObject
{
  int textSize;
  BOOL showsIcons;
  BOOL showsIconPreview;
  BOOL showsPreviewColumn;
  FSNIconsArrangement arrangement;
  CGFloat columnWidth;
}

+ (FSNColumnViewOptions *)sharedOptions;

/* Finder's ArrangeBy codes (E30): dnam, kipl, modd, ascd, phys, labl.
 * Unknown codes give FSNIconsArrangeNone, None gives nil. */
+ (FSNIconsArrangement)arrangementForFinderCode:(NSString *)code;
+ (NSString *)finderCodeForArrangement:(FSNIconsArrangement)value;

/* Reads the options from the defaults again; YES when one changed (the
 * change is then posted).  Done by itself when the defaults change. */
- (BOOL)reload;

/* Text size of the names, held to 10..16; 12 when never set, or the
 * NSFontSize default the browser used to follow. */
- (int)textSize;
- (void)setTextSize:(int)size;

/* On by default (E30). */
- (BOOL)showsIcons;
- (void)setShowsIcons:(BOOL)flag;

/* On by default (E30); has no effect while icons are off, where Finder
 * greys the checkbox out. */
- (BOOL)showsIconPreview;
- (void)setShowsIconPreview:(BOOL)flag;

/* On by default (E30). */
- (BOOL)showsPreviewColumn;
- (void)setShowsPreviewColumn:(BOOL)flag;

/* By name by default (E30); None is Workspace's own: the folder's sort
 * order. */
- (FSNIconsArrangement)arrangement;
- (void)setArrangement:(FSNIconsArrangement)value;

/* The width of every column: set by an Option-drag of a column's resize
 * handle (E32); whole points, at least FSNBrowserMinimumColumnWidth. */
- (CGFloat)columnWidth;
- (void)setColumnWidth:(CGFloat)width;

@end

#endif /* FSN_COLUMN_VIEW_OPTIONS_H */
