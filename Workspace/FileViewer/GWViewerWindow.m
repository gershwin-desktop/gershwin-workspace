/* GWViewerWindow.m
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: July 2004
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

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "GWViewerWindow.h"
#import "FSNode.h"
#import "GWViewersManager.h"

// Forward declare methods to avoid warnings
@interface NSObject (ViewerDelegateMethods)
- (NSArray *)lastSelection;
@end


@implementation GWViewerWindow

- (void)dealloc
{  
  [super dealloc];
}

- (id)init
{
  unsigned int style = NSTitledWindowMask | NSClosableWindowMask 
    | NSMiniaturizableWindowMask | NSResizableWindowMask;

  self = [super initWithContentRect: NSZeroRect
                          styleMask: style
                            backing: NSBackingStoreBuffered 
                              defer: NO];
  return self; 
}


- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{	
  return [[self delegate] validateItem: menuItem];
}

- (void)openSelection:(id)sender
{
  [[self delegate] openSelectionInNewViewer: NO];
}

- (void)openSelectionAsFolder:(id)sender
{
  [[self delegate] openSelectionAsFolder];
}

- (void)openWith:(id)sender
{
  [[self delegate] openSelectionWith];
}

- (void)newFolder:(id)sender
{
  [[self delegate] newFolder];
}

- (void)newFile:(id)sender
{
  [[self delegate] newFile];
}

- (void)duplicateFiles:(id)sender
{
  [[self delegate] duplicateFiles];
}

- (void)recycleFiles:(id)sender
{
  [[self delegate] recycleFiles];
}

- (void)deleteFiles:(id)sender
{
  [[self delegate] deleteFiles];
}

- (void)goBackwardInHistory:(id)sender
{
  [[self delegate] goBackwardInHistory];
}

- (void)goForwardInHistory:(id)sender
{
  [[self delegate] goForwardInHistory];
}

- (void)setViewerType:(id)sender
{
  [[self delegate] setViewerType: sender];
}

- (void)setShownType:(id)sender
{
  [[self delegate] setShownType: sender];
}

- (void)setExtendedShownType:(id)sender
{
  [[self delegate] setExtendedShownType: sender];
}

- (void)setIconsSize:(id)sender
{
  [[self delegate] setIconsSize: sender];
}

- (void)setIconsPosition:(id)sender
{
  [[self delegate] setIconsPosition: sender];
}

- (void)setLabelSize:(id)sender
{
  [[self delegate] setLabelSize: sender];
}

- (void)chooseLabelColor:(id)sender
{
  [[self delegate] chooseLabelColor: sender];
}

- (void)chooseBackColor:(id)sender
{
  [[self delegate] chooseBackColor: sender];
}

- (void)selectAllInViewer:(id)sender
{
  [[self delegate] selectAllInViewer];
}

- (void)showTerminal:(id)sender
{
  [[self delegate] showTerminal];
}

- (void)keyDown:(NSEvent *)theEvent 
{
  unsigned flags = [theEvent modifierFlags];
  NSString *characters = [theEvent characters];
  unichar character = 0;
		
  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
    }
		
  switch (character)
    {
    case NSLeftArrowFunctionKey:
      if ((flags & NSCommandKeyMask) || (flags & NSControlKeyMask))
	{
	  [[self delegate] goBackwardInHistory];
	}
      return;

    case NSRightArrowFunctionKey:			
      if ((flags & NSCommandKeyMask) || (flags & NSControlKeyMask))
	{
	  [[self delegate] goForwardInHistory];
	} 
      return;

    case NSUpArrowFunctionKey:
      NSLog(@"GWViewerWindow: NSUpArrowFunctionKey pressed, flags=0x%x", flags);
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
	{
	  NSLog(@"GWViewerWindow: Shift-Up detected");
	  // Shift-Up = Open parent folder in new viewer
	  id delegate = [self delegate];
	  if ([delegate respondsToSelector: @selector(baseNode)])
	    {
	      FSNode *baseNode = [delegate baseNode];
	      if (baseNode)
		{
		  NSString *parentPath = [[baseNode path] stringByDeletingLastPathComponent];
		  if (parentPath && ![parentPath isEqual: [baseNode path]])
		    {
		      FSNode *parentNode = [FSNode nodeWithPath: parentPath];
		      if (parentNode)
			{
			  GWViewersManager *manager = [GWViewersManager viewersManager];
			  if (manager)
			    {
			      [manager viewerForNode: parentNode
					   showType: 0
				      showSelection: NO
					   forceNew: NO
					   withKey: nil];
			    }
			}
		    }
		}
	    }
	  return;
	}
      if (flags & NSCommandKeyMask)
	{
	  [[self delegate] openParentFolder];
	}
      return;

    case NSDownArrowFunctionKey:
      NSLog(@"GWViewerWindow: NSDownArrowFunctionKey pressed, flags=0x%x", flags);
      if ((flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
	{
	  NSLog(@"GWViewerWindow: Command-Shift-Down detected");
	  // Command-Shift-Down = Open as Folder (alternative shortcut)
	  [[self delegate] openSelectionAsFolder];
	  return;
	}
      if (flags & NSShiftKeyMask)
	{
	  // Shift-Down = Open Selection
	  [[self delegate] openSelectionInNewViewer: NO];
	  return;
	}
      if (flags & NSCommandKeyMask)
	{
    // Command-Down = Open Selection
	  [[self delegate] openSelection: nil];
	}
      return;

    case NSDeleteCharacter:
    case NSBackspaceCharacter:
    case NSDeleteFunctionKey:
      if (flags & (NSShiftKeyMask | NSCommandKeyMask))
	{
	  // Command + Delete or Shift + Delete = Empty Trash
	  [[self delegate] emptyTrash];
	}
      else if (flags & NSCommandKeyMask)
	{
	  // Command + Delete = Move to Trash
	  [[self delegate] recycleFiles];
	}
      else if (flags & NSAlternateKeyMask)
	{
	  // Option + Delete = Delete immediately
	  [[self delegate] deleteFiles];
	}
      return;
      
    case '.':
      if (flags & (NSShiftKeyMask | NSCommandKeyMask))
	{
	  // Command + Shift + . = Show hidden files
	  [[self delegate] toggleHiddenFiles];
	}
      return;
    /*
    case ' ':
      // Space = Quick Look
      if (!(flags & (NSCommandKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSControlKeyMask)))
        {
          id del = [self delegate];
          BOOL allowQuickLook = YES;

          // If the delegate can report a last selection, require a non-empty selection
          if ([del respondsToSelector: @selector(lastSelection)])
            {
              NSArray *sel = [del lastSelection];
              if (!sel || ([sel count] == 0))
                allowQuickLook = NO;
            }

          if (allowQuickLook && [del respondsToSelector: @selector(quickLook:)])
            {
              [del quickLook: nil];
            }
        }
      return;
    */
    }
	
  [super keyDown: theEvent];
}

- (void)print:(id)sender
{
	[super print: sender];
}

@end
