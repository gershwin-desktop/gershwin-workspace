/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Finder's "Show icon preview": an image file is shown with its own picture
 * instead of the icon of its type.  Shared by the views that offer the
 * option so that they show the same picture for the same file. */

#ifndef FSN_ICON_PREVIEW_H
#define FSN_ICON_PREVIEW_H

#import <Foundation/Foundation.h>

@class FSNode;
@class NSImage;

@interface FSNIconPreview : NSObject

/* A file whose picture the preview shows: an image file of a type AppKit
 * reads, not a folder or a link. */
+ (BOOL)isPlainImageNode:(FSNode *)node;

/* The picture of an image file at size points at most (smaller pictures stay
 * as small as they are), or nil when it cannot be read.  Pictures are kept
 * for as long as memory allows, keyed so a file changed on disk or shown at
 * another size is decoded again. */
+ (NSImage *)previewImageForNode:(FSNode *)node size:(int)size;

/* The icon of the file's type, never a thumbnail of the file itself. */
+ (NSImage *)genericTypeIconForNode:(FSNode *)node size:(int)size;

/* What a view shows for node at size: for an image file without a custom
 * icon its picture (showsPreview) or its type icon, for anything else the
 * icon FSNodeRep has for it. */
+ (NSImage *)iconForNode:(FSNode *)node size:(int)size showsPreview:(BOOL)showsPreview;

@end

#endif /* FSN_ICON_PREVIEW_H */
