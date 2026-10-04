/* t_DockDragRemoval.m - headless coverage of the drag-out removal rule.
 *
 * Removing a docked icon by drag and drop is only meant when the drag is
 * carried further out beyond the Dock's face (outward, away from the
 * screen edge) than twice the Dock's height; a drop let go nearer than
 * that comes back instead of taking the icon out, and so does a drag that
 * merely moved the icon along the Dock.  The rule
 * itself lives in Dock.h as DockDropRemovesIcon(), a Foundation-only static
 * inline, precisely so it can be proven without building a Dock (which
 * needs NSWorkspace, X11 and a running desktop) - the same pattern as
 * t_DockPoll.m for DockMagnifyPollInterval().  Dock.h drags in
 * GWDesktopManager.h and FSNodeRep.h for their declarations only; nothing
 * here links FSNode or messages an AppKit class.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "Dock.h"
#import <Foundation/Foundation.h>

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  CGFloat h = 64.0;

  /* --- nearer than twice the Dock's height: a slip, never a removal --- */
  {
    PASS(DockDropRemovesIcon(0.0, h) == NO, "a drop still on the bar does not remove");

    PASS(DockDropRemovesIcon(h, h) == NO,
         "dragged exactly one Dock height out does not remove yet");

    PASS(DockDropRemovesIcon(2.0 * h - 0.5, h) == NO,
         "half a point short of the span does not remove: the accidental "
         "twitch near the edge stays on the safe side");
  }

  /* --- past the span: deliberate, removes --- */
  {
    PASS(DockDropRemovesIcon(2.0 * h, h) == YES,
         "at exactly twice the Dock's height the removal counts (>=)");

    PASS(DockDropRemovesIcon(2.0 * h + 0.5, h) == YES, "half a point past the span removes");

    PASS(DockDropRemovesIcon(20.0 * h, h) == YES, "a drag flung far across the desktop removes");
  }

  /* --- the threshold moves with the Dock's thickness --- */
  {
    PASS(DockDropRemovesIcon(128.0, h) == YES && DockDropRemovesIcon(127.0, h) == NO,
         "a 64 point bar takes removals from 128 points out, and only "
         "those");
  }

  /* --- degenerate geometry keeps the icon (fails closed) --- */
  {
    PASS(DockDropRemovesIcon(10000.0, 0.0) == NO,
         "no bar to measure against means keep, not remove");

    PASS(DockDropRemovesIcon(0.99, 0.5) == NO && DockDropRemovesIcon(1.5, 0.5) == YES,
         "a hair-thin bar still splits at twice its own height");
  }

  [arp release];
  exit(0);
}
