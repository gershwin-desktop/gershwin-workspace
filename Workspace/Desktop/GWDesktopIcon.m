/* GWDesktopIcon.m
 *  
 * Copyright (C) 2005-2021 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola <rm@gnu.org>
 *
 * Date: January 2005
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */
 
#include <Foundation/Foundation.h>
#include <AppKit/AppKit.h>
#include "GWDesktopIcon.h"

@implementation GWDesktopIcon

- (id)initForNode:(FSNode *)anode
     nodeInfoType:(FSNInfoType)type
     extendedType:(NSString *)exttype
         iconSize:(int)isize
     iconPosition:(NSUInteger)ipos
        labelFont:(NSFont *)lfont
        textColor:(NSColor *)tcolor
        gridIndex:(NSUInteger)gindex
        dndSource:(BOOL)dndsrc
        acceptDnd:(BOOL)dndaccept
        slideBack:(BOOL)slback
{
  self = [super initForNode: anode
	       nodeInfoType: type
	       extendedType: exttype
		   iconSize: isize
	       iconPosition: ipos
		  labelFont: lfont
		  textColor: tcolor
		  gridIndex: gindex
		  dndSource: dndsrc
		  acceptDnd: dndaccept
		  slideBack: slback];

  if (self)
    {
      drawLabelBackground = YES;
    }

  return self;
}

- (void)mouseUp:(NSEvent *)theEvent
{
  NSPoint location = [theEvent locationInWindow];
  location = [self convertPoint: location fromView: nil];
  BOOL onself = NO;

  if (icnPosition == NSImageOnly)
    {
      onself = [self mouse: location inRect: icnBounds];
    }
  else
    {
      onself = ([self mouse: location inRect: icnBounds]
                || [self mouse: location inRect: labelRect]);
    }

  if (onself && ([node isLocked] == NO) && ([theEvent clickCount] > 1))
    {
      // Route through the window's delegate (GWDesktopManager for desktop),
      // which properly handles folders, packages, applications, and files.
      id windowDelegate = [[self window] delegate];
      if (windowDelegate && [windowDelegate respondsToSelector: @selector(openSelectionInNewViewer:)])
        {
          BOOL newv = (([theEvent modifierFlags] & NSControlKeyMask)
                       || ([theEvent modifierFlags] & NSAlternateKeyMask));
          [windowDelegate openSelectionInNewViewer: newv];
        }
      return;
    }

  [super mouseUp: theEvent];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  /* Clicking an icon activates the Desktop window, as it always did here.
   * Everything else is FSNIcon's handling, so Desktop icons are dragged,
   * dropped and renamed exactly like icons in an icon view instead of
   * following a copy of that code that fell behind it. */
  [[self window] makeMainWindow];
  [[self window] makeKeyWindow];

  [super mouseDown: theEvent];
}

@end
