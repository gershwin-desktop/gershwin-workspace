/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsidePreviewView.h - the preview of one file or folder, as a
 * plain view with no knowledge of the window it sits in.  The Look Inside
 * panel shows it at full size; the browser view's preview column shows the
 * compact style next to the selected file.
 *
 * Full style: images at their own size (scaled down to fit), plain and
 * rich text in a read-only scrolling text view, the pages of a PDF, and a
 * large icon with the item's facts for folders, audio (with a Play button
 * when this system can play the format), video and everything else.
 *
 * Compact style, for a small picture area whose host lists the item's
 * facts itself (the column view's preview column): the same content
 * previews, and the bare icon where there is no picture of the content.
 */

#import <AppKit/AppKit.h>
#import "GWLookInsidePreviewKind.h"

typedef enum
{
  GWLookInsidePreviewStyleFull = 0,
  GWLookInsidePreviewStyleCompact
} GWLookInsidePreviewStyle;

/* Keys of +infoForPath:. */
extern NSString * const GWLookInsideInfoName;
extern NSString * const GWLookInsideInfoKind;
extern NSString * const GWLookInsideInfoSize;      /* absent for a folder: computed later */
extern NSString * const GWLookInsideInfoItems;     /* folders only, "3 items" */
extern NSString * const GWLookInsideInfoModified;

@class GWLookInsideFolderSizer;
@class GWLookInsidePDFRenderer;

@interface GWLookInsidePreviewView : NSView
{
  GWLookInsidePreviewStyle _style;
  NSString *_path;
  GWLookInsidePreviewKind _kind;
  NSView *_content;                  /* the one subview showing the preview */
  NSImageView *_picture;             /* info layout: icon or image */
  NSTextField *_nameField;           /* info layout: the item's name */
  NSMutableArray *_labelFields;      /* info layout: "Kind", "Size", ... */
  NSMutableArray *_valueFields;      /* info layout: their values */
  NSTextField *_sizeValueField;      /* filled in when a folder's size arrives */
  NSButton *_playButton;             /* audio this system can play */
  NSSound *_sound;
  GWLookInsideFolderSizer *_sizer;
  GWLookInsidePDFRenderer *_pdfRenderer;
}

- (id)initWithFrame:(NSRect)frame style:(GWLookInsidePreviewStyle)style;

/* Shows `path`, replacing whatever was shown; nil shows nothing.  Work
 * that takes long (a folder's size, the pages of a PDF) is done in the
 * background and lands later; showing another path or -stopTasks drops
 * it. */
- (void)showPath:(NSString *)path;

- (NSString *)path;
- (GWLookInsidePreviewKind)kind;
- (GWLookInsidePreviewStyle)style;

/* Stops background work and playing sound; call before throwing the view
 * away while it may still be busy. */
- (void)stopTasks;

/* The facts the info layout lists for `path` (keys above), localized and
 * formatted; a folder's size is not in it, it is computed in the
 * background. */
+ (NSDictionary *)infoForPath:(NSString *)path;

/* The extensions NSImage can decode, lower-case, for
 * GWLookInsidePreviewKindForPath(). */
+ (NSArray *)imageExtensions;

@end
