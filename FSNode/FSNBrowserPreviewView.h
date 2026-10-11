/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The preview column of the column view (Finder's "Show preview column"):
 * the column after a selected file shows a large picture of the file and
 * what it is.  The picture comes from the application's FSNPreviewProvider
 * when it has one for the file, otherwise it is the file's large icon. */

#ifndef FSN_BROWSER_PREVIEW_VIEW_H
#define FSN_BROWSER_PREVIEW_VIEW_H

#import <AppKit/NSView.h>

@class FSNode;
@class NSImage;
@class NSImageView;
@class NSColor;

@interface FSNBrowserPreviewView : NSView
{
  FSNode *node;
  NSView *providedView;
  NSImageView *iconView;
  NSMutableArray *infoFields;
  NSColor *backColor;
  NSSize pictureSize;
}

/* The rows of information under the picture: pairs of a label ("Name:")
 * and its value, in the order shown. */
+ (NSArray *)infoRowsForNode:(FSNode *)anode;

/* Shows anode; nil empties the view. */
- (void)showNode:(FSNode *)anode;
- (FSNode *)node;

/* The provider's view of the file, or nil when the icon is shown instead. */
- (NSView *)providedView;

/* The large icon shown when the provider has no view, else nil. */
- (NSImage *)iconImage;

- (void)setBackgroundColor:(NSColor *)color;

@end

#endif /* FSN_BROWSER_PREVIEW_VIEW_H */
