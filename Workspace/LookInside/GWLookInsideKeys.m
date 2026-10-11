/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWLookInsideKeys.h"

GWLookInsideKeyAction
GWLookInsideActionForKey(unichar character, BOOL command, BOOL option,
                         NSUInteger itemCount, BOOL overviewShown)
{
  BOOL several = (itemCount > 1);

  switch (character)
    {
    case ' ':
      if (command)
        {
          return GWLookInsideKeyActionNone;
        }
      return option ? GWLookInsideKeyActionToggleFullScreen : GWLookInsideKeyActionClose;

    case 0x1B:
      return GWLookInsideKeyActionClose;

    case '\r':
    case 0x03:
      /* Return alone means "show this one" only where something is
       * highlighted to be shown, which is the overview. */
      if (several && (command || overviewShown))
        {
          return GWLookInsideKeyActionToggleOverview;
        }
      return GWLookInsideKeyActionNone;

    case 'o':
      return command ? GWLookInsideKeyActionOpen : GWLookInsideKeyActionNone;

    case GWLookInsideUpArrowKey:
    case GWLookInsideDownArrowKey:
    case GWLookInsideLeftArrowKey:
    case GWLookInsideRightArrowKey:
      if (command)
        {
          /* Command-Down opens an item in a folder window; keeping the
           * same chord here means the panel never swallows it. */
          return (character == GWLookInsideDownArrowKey)
            ? GWLookInsideKeyActionOpen : GWLookInsideKeyActionNone;
        }
      if (several || overviewShown)
        {
          return (character == GWLookInsideUpArrowKey || character == GWLookInsideLeftArrowKey)
            ? GWLookInsideKeyActionPrevious : GWLookInsideKeyActionNext;
        }
      return GWLookInsideKeyActionForwardToViewer;

    default:
      return GWLookInsideKeyActionNone;
    }
}

NSUInteger
GWLookInsideStepIndex(NSUInteger index, NSUInteger count, NSInteger delta)
{
  NSInteger stepped;

  if (count == 0)
    {
      return 0;
    }

  stepped = ((NSInteger)(index % count) + delta) % (NSInteger)count;
  if (stepped < 0)
    {
      stepped += (NSInteger)count;
    }
  return (NSUInteger)stepped;
}
