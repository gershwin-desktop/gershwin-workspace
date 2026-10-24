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
#import "Workspace.h"
#import "GWDesktopManager.h"
#import "FSNSpringLoader.h"
#import "../LookInside/GWLookInsideController.h"

// Forward declare methods to avoid warnings
@interface NSObject (ViewerDelegateMethods)
- (NSArray *)lastSelection;
- (void)openSelection;
- (void)openSelectionAsFolder;
@end


@implementation GWViewerWindow

/* Spring-loaded folders follow a drag across windows, and a window's drag
 * events only pass through here.  The loader hears of an event before it is
 * handled: handling a drop can run a confirmation panel, and the loader must
 * know where the drop landed before that. */
- (void)sendEvent:(NSEvent *)theEvent
{
  [[FSNSpringLoader sharedLoader] noteEvent: theEvent inWindow: self];
  [super sendEvent: theEvent];
}

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

- (void)ejectVolumes:(id)sender
{
  [[self delegate] ejectSelectedVolumes];
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

- (void)makeAliasFiles:(id)sender
{
  [[self delegate] makeAliasFiles];
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

- (void)openParentFolder:(id)sender
{
  [[self delegate] openParentFolder];
}

- (void)openParentFolder
{
  [self openParentFolder: nil];
}

- (void)showAttributesInspector:(id)sender
{
  [[self delegate] showAttributesInspector: sender];
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
  if ([super performKeyEquivalent: theEvent])
    {
      return YES;
    }

  unsigned flags = [theEvent modifierFlags];
  NSString *characters = [theEvent characters];

  if ([characters length] > 0 && [characters characterAtIndex: 0] == ' ')
    {
      /* Same handler as the Desktop's Space bar; Option opens straight
       * into full screen.  Get Info's Attributes/Contents inspector -
       * what Space used to open here - stays reachable only from its own
       * menu item. */
      id del = [self delegate];
      NSArray *selection = nil;
      id baseNode = nil;

      if ([del respondsToSelector: @selector(lastSelection)])
        {
          selection = [del lastSelection];
        }
      /* lastSelection holds the base folder itself when nothing inside it
       * is selected. */
      if ([del respondsToSelector: @selector(baseNode)])
        {
          baseNode = [del baseNode];
        }

      return [[GWLookInsideController sharedController]
                 handleSpaceKeyWithCommand: (flags & NSCommandKeyMask) != 0
                                     shift: (flags & NSShiftKeyMask) != 0
                                   control: (flags & NSControlKeyMask) != 0
                                    option: (flags & NSAlternateKeyMask) != 0
                                 selection: selection
                                  baseNode: baseNode
                              sourceWindow: self];
    }

  return NO;
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
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
	{
	  // Shift-Up = Open parent folder in new viewer
	  [[self delegate] openEnclosingFolderClosingViewer: NO];
	  return;
	}
      if (flags & NSCommandKeyMask)
	{
	  // Cmd+Shift+Up also closes this viewer where Up opens a window
	  [[self delegate] openEnclosingFolderClosingViewer: (flags & NSShiftKeyMask) != 0];
	}
      return;

    case NSDownArrowFunctionKey:
      if ((flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
	{
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
      if ((flags & NSShiftKeyMask) && (flags & NSCommandKeyMask))
	{
	  // Command + Shift + Delete = Empty Trash
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
      if ((flags & NSShiftKeyMask) && (flags & NSCommandKeyMask))
	{
	  // Command + Shift + . = Show hidden files; the setting belongs to
	  // the application, the viewer only follows it
	  [[Workspace gworkspace] toggleHiddenFiles];
	}
      return;

    case 0x01B: // Escape
      {
        id delegate = [self delegate];
        if ([delegate respondsToSelector: @selector(nodeView)])
          {
            id nodeView = [delegate nodeView];
            if ([nodeView respondsToSelector: @selector(cancelOperation:)])
              {
                [nodeView cancelOperation: nil];
              }
          }
      }
      return;
    case 'o':
    case 'O':
      if (flags & NSCommandKeyMask)
        {
          if (flags & NSShiftKeyMask)
            {
              [[self delegate] openSelectionAsFolder];
            }
          else
            {
              [[self delegate] openSelection];
            }
          return;
        }
      break;
    }
	
  [super keyDown: theEvent];
}

- (void)print:(id)sender
{
	[super print: sender];
}

- (void)performClose:(id)sender
{
  // Close the window
  [super performClose: sender];
}

@end
