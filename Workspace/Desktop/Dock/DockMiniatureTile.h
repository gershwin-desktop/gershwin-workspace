/* DockMiniatureTile.h
 *
 * The Dock tile of a minimized window.  The tile only draws a frame; the
 * window manager's compositor paints the window's live content into it.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@interface DockMiniatureTile : NSView
{
  unsigned long clientWindow;
}

- (id)initWithWindow:(unsigned long)aWindow title:(NSString *)title;
- (unsigned long)clientWindow;

/* Where the content goes, in the tile's own coordinates: a square as large
 * as an icon in a tile that size, inside the frame. */
- (NSRect)contentRect;

- (void)restore:(id)sender;
- (void)closeWindow:(id)sender;

@end
