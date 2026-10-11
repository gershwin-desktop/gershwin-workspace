/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsideKeys.h - what a key pressed in the Look Inside panel does.
 * Plain Foundation so the whole key map is covered by a headless test;
 * the panel only performs the action it is handed.
 */

#import <Foundation/Foundation.h>

/* AppKit's NSUpArrowFunctionKey .. NSRightArrowFunctionKey, repeated here
 * so this file does not need AppKit. */
enum
{
  GWLookInsideUpArrowKey = 0xF700,
  GWLookInsideDownArrowKey = 0xF701,
  GWLookInsideLeftArrowKey = 0xF702,
  GWLookInsideRightArrowKey = 0xF703
};

typedef enum
{
  GWLookInsideKeyActionNone = 0,
  GWLookInsideKeyActionClose,
  GWLookInsideKeyActionNext,
  GWLookInsideKeyActionPrevious,
  /* The folder window moves its own selection; the panel follows it. */
  GWLookInsideKeyActionForwardToViewer,
  GWLookInsideKeyActionToggleOverview,
  GWLookInsideKeyActionToggleFullScreen,
  GWLookInsideKeyActionOpen
} GWLookInsideKeyAction;

/* `character` is the first character of the event (AppKit's function key
 * values for the arrows), `command`/`option` the modifier state,
 * `itemCount` how many items the panel was opened for and
 * `overviewShown` whether the overview of all of them is up. */
GWLookInsideKeyAction GWLookInsideActionForKey(unichar character,
                                               BOOL command,
                                               BOOL option,
                                               NSUInteger itemCount,
                                               BOOL overviewShown);

/* The index `delta` steps away from `index` among `count` items; stepping
 * past either end wraps around, so the arrow keys can cycle through a
 * selection without a dead end. */
NSUInteger GWLookInsideStepIndex(NSUInteger index, NSUInteger count, NSInteger delta);
