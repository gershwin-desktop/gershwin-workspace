/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWLookInsideKeys.m - the Look Inside panel's key map and how stepping
 * through several items wraps.  Headless. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/LookInside/GWLookInsideKeys.m"

static NSString * const kSetName = @"Look Inside keys";

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET([kSetName UTF8String])

  /* MI-LI-1, MI-LI-2: Space and Escape close. */
  PASS(GWLookInsideActionForKey(' ', NO, NO, 1, NO) == GWLookInsideKeyActionClose,
       "MI-LI-1 Space closes the panel");
  PASS(GWLookInsideActionForKey(0x1B, NO, NO, 3, NO) == GWLookInsideKeyActionClose,
       "MI-LI-2 Escape closes the panel");
  PASS(GWLookInsideActionForKey(0x1B, NO, NO, 3, YES) == GWLookInsideKeyActionClose,
       "MI-LI-2 Escape closes the panel from the overview too");

  /* MI-LI-3: one item - the arrows move the folder window's selection. */
  PASS(GWLookInsideActionForKey(GWLookInsideDownArrowKey, NO, NO, 1, NO)
       == GWLookInsideKeyActionForwardToViewer,
       "MI-LI-3 Down arrow with one item goes to the folder window");
  PASS(GWLookInsideActionForKey(GWLookInsideLeftArrowKey, NO, NO, 1, NO)
       == GWLookInsideKeyActionForwardToViewer,
       "MI-LI-3 Left arrow with one item goes to the folder window");

  /* MI-LI-4: several items - the arrows step through them. */
  PASS(GWLookInsideActionForKey(GWLookInsideRightArrowKey, NO, NO, 3, NO)
       == GWLookInsideKeyActionNext,
       "MI-LI-4 Right arrow with several items shows the next one");
  PASS(GWLookInsideActionForKey(GWLookInsideDownArrowKey, NO, NO, 3, NO)
       == GWLookInsideKeyActionNext,
       "MI-LI-4 Down arrow with several items shows the next one");
  PASS(GWLookInsideActionForKey(GWLookInsideLeftArrowKey, NO, NO, 3, NO)
       == GWLookInsideKeyActionPrevious,
       "MI-LI-4 Left arrow with several items shows the previous one");
  PASS(GWLookInsideActionForKey(GWLookInsideUpArrowKey, NO, NO, 3, NO)
       == GWLookInsideKeyActionPrevious,
       "MI-LI-4 Up arrow with several items shows the previous one");

  /* MI-LI-5: the overview of several items. */
  PASS(GWLookInsideActionForKey('\r', YES, NO, 3, NO) == GWLookInsideKeyActionToggleOverview,
       "MI-LI-5 Command-Return shows the overview of several items");
  PASS(GWLookInsideActionForKey('\r', YES, NO, 1, NO) == GWLookInsideKeyActionNone,
       "MI-LI-5 there is no overview of a single item");
  PASS(GWLookInsideActionForKey('\r', NO, NO, 3, YES) == GWLookInsideKeyActionToggleOverview,
       "MI-LI-5 Return in the overview shows the highlighted item");
  PASS(GWLookInsideActionForKey('\r', NO, NO, 3, NO) == GWLookInsideKeyActionNone,
       "MI-LI-5 Return outside the overview does nothing");

  /* MI-LI-6: full screen. */
  PASS(GWLookInsideActionForKey(' ', NO, YES, 1, NO) == GWLookInsideKeyActionToggleFullScreen,
       "MI-LI-6 Option-Space switches full screen");

  /* MI-LI-7: open with the default application. */
  PASS(GWLookInsideActionForKey('o', YES, NO, 1, NO) == GWLookInsideKeyActionOpen,
       "MI-LI-7 Command-O opens the item");
  PASS(GWLookInsideActionForKey(GWLookInsideDownArrowKey, YES, NO, 1, NO)
       == GWLookInsideKeyActionOpen,
       "MI-LI-7 Command-Down opens the item");
  PASS(GWLookInsideActionForKey('o', NO, NO, 1, NO) == GWLookInsideKeyActionNone,
       "MI-LI-7 a plain o does nothing");

  /* MI-LI-8: stepping wraps at both ends. */
  PASS(GWLookInsideStepIndex(0, 3, 1) == 1, "MI-LI-8 next of the first is the second");
  PASS(GWLookInsideStepIndex(2, 3, 1) == 0, "MI-LI-8 next of the last is the first");
  PASS(GWLookInsideStepIndex(0, 3, -1) == 2, "MI-LI-8 previous of the first is the last");
  PASS(GWLookInsideStepIndex(0, 0, 1) == 0, "MI-LI-8 stepping in nothing stays at 0");

  END_SET([kSetName UTF8String])

  [arp release];
  return 0;
}
