/* DockMiniatureTile.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "DockMiniatureTile.h"
#import "X11AppSupport.h"

@implementation DockMiniatureTile

- (id)initWithWindow:(unsigned long)aWindow title:(NSString *)title
{
  self = [super initWithFrame: NSZeroRect];
  if (self != nil)
    {
      clientWindow = aWindow;
      if ([title length] > 0)
        [self setToolTip: title];
    }
  return self;
}

- (unsigned long)clientWindow
{
  return clientWindow;
}

- (NSRect)contentRect
{
  NSRect b = [self bounds];
  /* An icon fills three quarters of its tile; a miniature the same. */
  CGFloat side = floor(MIN(NSWidth(b), NSHeight(b)) * 0.75);

  return NSMakeRect(floor(NSMidX(b) - side / 2), floor(NSMidY(b) - side / 2),
                    side, side);
}

- (void)drawRect:(NSRect)rect
{
  NSRect frame = NSInsetRect([self contentRect], -2, -2);
  NSBezierPath *path = [NSBezierPath bezierPath];

  [path appendBezierPathWithRoundedRect: NSInsetRect(frame, 0.5, 0.5)
                                xRadius: 3
                                yRadius: 3];
  [[NSColor colorWithCalibratedWhite: 1.0 alpha: 0.35] set];
  [path fill];
  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.35] set];
  [path stroke];
}

/* The Dock is never the key window, so the first click has to count. */
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

/* Taken here, or the press goes on to the Dock, which tracks it as a drag
 * and keeps the release. */
- (void)mouseDown:(NSEvent *)event
{
}

- (void)mouseUp:(NSEvent *)event
{
  if (NSPointInRect([self convertPoint: [event locationInWindow] fromView: nil],
                    [self bounds]))
    [self restore: self];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
  NSMenu *menu = AUTORELEASE ([[NSMenu alloc] initWithTitle: @""]);

  [[menu addItemWithTitle: NSLocalizedString(@"Restore", @"")
                   action: @selector(restore:)
            keyEquivalent: @""] setTarget: self];
  [[menu addItemWithTitle: NSLocalizedString(@"Close", @"")
                   action: @selector(closeWindow:)
            keyEquivalent: @""] setTarget: self];
  return menu;
}

/* The window manager restores a minimized window that is made active, and
 * the restore grows out of this tile. */
- (void)restore:(id)sender
{
  [[GWX11WindowManager sharedManager] activateWindow: clientWindow];
}

- (void)closeWindow:(id)sender
{
  [[GWX11WindowManager sharedManager] closeWindow: clientWindow];
}

@end
