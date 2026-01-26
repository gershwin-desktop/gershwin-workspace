/* DockIcon.m
 *  
 * Copyright (C) 2005-2021 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale <enrico@imago.ro>
 *          Riccardo Mottola <rm@gnu.org>
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

#include <math.h>
#include <unistd.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "DockIcon.h"
#import "Dock.h"
#import "GWDesktopManager.h"
#import "Workspace.h"

@implementation DockIcon

- (void)dealloc
{
  /* Stop bouncing and clean up timer */
  isBouncing = NO;
  if (bounceTimer) {
    [bounceTimer invalidate];
    bounceTimer = nil;
  }
  RELEASE (appName);
  RELEASE (highlightColor);
  RELEASE (darkerColor);
  RELEASE (highlightImage);
  RELEASE (trashFullIcon);
  RELEASE (ejectIcon);
  RELEASE (dragIcon);
  
  [super dealloc];
}

- (id)initForNode:(FSNode *)anode
          appName:(NSString *)aname
         iconSize:(int)isize
{
  /* Validate inputs to prevent crashes */
  if (anode == nil) {
    [self release];
    return nil;
  }
  
  self = [super initForNode: anode
               nodeInfoType: FSNInfoNameType
               extendedType: nil
                   iconSize: isize
               iconPosition: NSImageOnly
                  labelFont: [NSFont systemFontOfSize: 12]
                  textColor: [NSColor controlTextColor]
                  gridIndex: 0
                  dndSource: NO
                  acceptDnd: NO
                  slideBack: NO];

  if (self) {
    if (aname != nil && [aname length] > 0) {
      ASSIGN (appName, aname);
    } else if (node != nil) {
      ASSIGN (appName, [[node name] stringByDeletingPathExtension]);
    } else {
      ASSIGN (appName, @"Unknown");
    }
        
    if (icon) {
      dragIcon = [icon copy];
    }
    
    docked = NO;
    launched = NO;
    apphidden = NO;
    appPID = 0;
    isDragMountpointOnly = NO;
    ejectIcon = nil;

    /* Initialize bounce animation variables */
    isBouncing = NO;
    bounceTimer = nil;
    bounceVelocity = 0.0;
    bounceOffset = 0.0;
    bounceGravity = 1.0;  /* Doubled gravity for twice as fast animation */
    pauseCounter = 0;  /* No pause initially */

    minimumLaunchClicks = 2;
    
    nc = [NSNotificationCenter defaultCenter];
    fm = [NSFileManager defaultManager];
    ws = [NSWorkspace sharedWorkspace];

    if (appName) {
      [self setToolTip: appName];
    }
  }

  return self;
}

- (NSString *)appName
{
  return appName;
}

- (void)setWsIcon:(BOOL)value
{
  isWsIcon = value;
  if (isWsIcon) {
    [self removeAllToolTips];
  }
}

- (BOOL)isWsIcon
{
  return isWsIcon;
}

- (void)setTrashIcon:(BOOL)value
{
  if (value != isTrashIcon) {
    isTrashIcon = value;

    if (isTrashIcon) {
      NSArray *subNodes;
      NSUInteger i, count;

      ASSIGN (icon, [fsnodeRep trashIconOfSize: ceil(icnBounds.size.width)]);
      ASSIGN (trashFullIcon, [fsnodeRep trashFullIconOfSize: ceil(icnBounds.size.width)]);
      
      /* Load the Eject icon for use during mountpoint drags */
      NSString *ejectPath = [[NSBundle mainBundle] pathForResource: @"Eject" ofType: @"icns"];
      if (ejectPath) {
        ASSIGN (ejectIcon, [[NSImage alloc] initWithContentsOfFile: ejectPath]);
      }
      
      subNodes = [node subNodes];
      count = [subNodes count];
      
      for (i = 0; i < [subNodes count]; i++) {
        if ([[subNodes objectAtIndex: i] isReserved]) {
          count --;
        }
      }
      
      [self setTrashFull: !(count == 0)];
    
    } else {
      ASSIGN (icon, [fsnodeRep iconOfSize: ceil(icnBounds.size.width) 
                                  forNode: node]);
    }
  }
  
  if (isTrashIcon) {
    [self removeAllToolTips];
  }  
}

- (void)setTrashFull:(BOOL)value
{
  trashFull = value;
  [self setNeedsDisplay: YES];
}

- (BOOL)isTrashIcon
{
  return isTrashIcon;
}

- (BOOL)isSpecialIcon
{
  return (isWsIcon || isTrashIcon);
}

- (void)setDocked:(BOOL)value
{
  docked = value;
}

- (BOOL)isDocked
{
  return docked;
}

- (void)setSingleClickLaunch:(BOOL)value
{
  minimumLaunchClicks = (value == YES) ? 1 : 2;
}

- (void)setLaunched:(BOOL)value
{
  launched = value;
  if (value) {
    [self stopBouncing];
  }
  [self setNeedsDisplay: YES];
}

- (BOOL)isLaunched
{
  return launched;
}

- (void)setAppPID:(pid_t)pid
{
  appPID = pid;
}

- (pid_t)appPID
{
  return appPID;
}

- (void)setAppHidden:(BOOL)value
{
  apphidden = value;
  [self setNeedsDisplay: YES];
  [container setNeedsDisplayInRect: [self frame]];
}

- (BOOL)isAppHidden
{
  return apphidden;
}

- (void)animateLaunch
{
  /* Start the bouncing animation */
  isBouncing = YES;
  bounceVelocity = 6.32;  /* Initial upward velocity for 20px bounce height */
  bounceOffset = 0.0;
  
  /* Create a timer to update the animation 30 times per second (half as fast) */
  if (!bounceTimer) {
    bounceTimer = [NSTimer scheduledTimerWithTimeInterval: 0.033333
                                                   target: self
                                                 selector: @selector(_bounceTimerFired:)
                                                 userInfo: nil
                                                  repeats: YES];
  }
}

- (void)stopBouncing
{
  /* Just set the flag; let the timer callback check it */
  isBouncing = NO;
  bounceOffset = 0.0;
  bounceVelocity = 0.0;
  pauseCounter = 0;
  [self setNeedsDisplay: YES];
}

- (void)_bounceTimerFired:(NSTimer *)timer
{
  /* Check if we should still be bouncing */
  if (!isBouncing) {
    return;
  }
  
  /* Handle pause between bounces (500ms pause between iterations) */
  /* At 30fps (0.033s per frame), 500ms = ~15 frames */
  if (pauseCounter > 0) {
    pauseCounter--;
    [self setNeedsDisplay: YES];
    if (container) {
      [container setNeedsDisplayInRect: [self frame]];
    }
    return;
  }
  
  /* Apply gravity to velocity */
  bounceVelocity -= bounceGravity;
  
  /* Update position */
  bounceOffset += bounceVelocity;
  
  /* Bounce off the ground (y = 0) - repeat bouncing with pause */
  if (bounceOffset <= 0.0) {
    bounceOffset = 0.0;
    /* Bounce completed - set pause counter for 500ms pause */
    /* 500ms / 33.333ms per frame ≈ 15 frames */
    pauseCounter = 15;
    /* Reset velocity for next bounce cycle */
    bounceVelocity = 6.32;  /* Initial upward velocity for 20px bounce height */
  }
  
  /* Request redraw */
  [self setNeedsDisplay: YES];
  if (container) {
    NSRect f = [self frame];
    DockPosition pos = DockPositionBottom;
    
    if ([container respondsToSelector: @selector(position)]) {
      pos = [(Dock *)container position];
    }
    
    if (pos == DockPositionLeft) {
      f.size.width += 25;
    } else if (pos == DockPositionRight) {
      f.origin.x -= 25;
      f.size.width += 25;
    } else {
      f.size.height += 25;
    }
    
    [container setNeedsDisplayInRect: f];
  }
}

- (void)setHighlightColor:(NSColor *)color
{
  ASSIGN (highlightColor, [color highlightWithLevel: 0.2]);
  ASSIGN (darkerColor, [color shadowWithLevel: 0.4]);
}

- (void)setHighlightImage:(NSImage *)image
{
  DESTROY (highlightImage);
  
  if (image) {
    NSSize size = [self frame].size;
    
    highlightImage = [[NSImage alloc] initWithSize: size];
    [highlightImage lockFocus]; 
    [image compositeToPoint: NSZeroPoint 
                   fromRect: [self frame]
                  operation: NSCompositeCopy];
    [highlightImage unlockFocus];
  }
}

- (void)setUseHlightImage:(BOOL)value
{
  useHligtImage = value;
}

- (void)setIsDndSourceIcon:(BOOL)value
{
  if (isDndSourceIcon != value) {
    isDndSourceIcon = value;
    [self setNeedsDisplay: YES];
  }
}

- (void)setIconSize:(int)isize
{
  icnBounds = NSMakeRect(0, 0, isize, isize);
  if (isTrashIcon) {
    ASSIGN (icon, [fsnodeRep trashIconOfSize: ceil(icnBounds.size.width)]);
    ASSIGN (trashFullIcon, [fsnodeRep trashFullIconOfSize: ceil(icnBounds.size.width)]);
  } else {
    ASSIGN (icon, [fsnodeRep iconOfSize: ceil(icnBounds.size.width) 
                                forNode: node]);
  }
  hlightRect.size.width = ceil(isize / 3 * 4);
  hlightRect.size.height = ceil(hlightRect.size.width * [fsnodeRep highlightHeightFactor]);
  if ((hlightRect.size.height - isize) < 4) {
    hlightRect.size.height = isize + 4;
  }
  hlightRect.origin.x = 0;
  hlightRect.origin.y = 0;
  ASSIGN (highlightPath, [fsnodeRep highlightPathOfSize: hlightRect.size]); 
  [self tile];
}

- (void)mouseUp:(NSEvent *)theEvent
{
  if (theEvent == nil) return;
  
  if ([theEvent clickCount] >= minimumLaunchClicks) {
    if ([self isSpecialIcon] == NO) {
      NSString *nodePath = [node path];
      
      /* Safety check: ensure we have a valid path and name */
      if (nodePath == nil || appName == nil) {
        NSLog(@"DockIcon mouseUp: missing path or appName");
        return;
      }
      
      if ([node isApplication]) {
        if (launched == NO) {
          /* Launch the app if not already launched. Use the full path for proper resolution. */
          [ws launchApplication: nodePath];
        } else if (apphidden) {
          /* App is running but hidden; unhide and activate it */
          [[Workspace gworkspace] unhideAppWithPath: nodePath andName: appName];
        } else {
          /* App is already running and visible; just activate/raise it.
           * Use PID if available for more robust window matching. */
          [[Workspace gworkspace] activateAppWithPath: nodePath andName: appName pid: appPID];
        }
      } else if ([node isDirectory]) {
        /* This is a folder icon in the Dock. Open it explicitly in a new viewer. */
        [[Workspace gworkspace] newViewerAtPath: nodePath];
      }
    } else if (isWsIcon) {
      [[GWDesktopManager desktopManager] showRootViewer];
    
    } else if (isTrashIcon) {
      NSString *path = [node path];
      if (path) {
        [[GWDesktopManager desktopManager] selectFile: path inFileViewerRootedAtPath: path];
      }
    }
  }
}

- (void)mouseDown:(NSEvent *)theEvent
{
  NSEvent *nextEvent = nil;
  BOOL startdnd = NO;
    
  if ([theEvent clickCount] == 1)
    {
      [self select];

      dragdelay = 0;
      [(Dock *)container setDndSourceIcon: nil];

    while (1)
      {
	nextEvent = [[self window] nextEventMatchingMask:
				     NSLeftMouseUpMask | NSLeftMouseDraggedMask];

	if ([nextEvent type] == NSLeftMouseUp) {
	  [[self window] postEvent: nextEvent atStart: YES];
	  [self unselect];
	  break;

	} else if (([nextEvent type] == NSLeftMouseDragged)
		   && ([self isSpecialIcon] == NO)) {
	  if (dragdelay < 5) {
	    dragdelay++;
	  } else {
	    startdnd = YES;
	    break;
	  }
	}
      }

    if (startdnd == YES)
      {
	[self startExternalDragOnEvent: theEvent withMouseOffset: NSZeroSize];
      }
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if (isTrashIcon) {
    // Context menu for trash icon
    CREATE_AUTORELEASE_POOL(arp);
    NSMenu *menu = [[NSMenu alloc] initWithTitle: @""];
    NSMenuItem *item;
    
    item = [NSMenuItem new];
    [item setTitle: NSLocalizedString(@"Empty Trash", @"")];
    [item setTarget: [Workspace gworkspace]];
    [item setAction: @selector(emptyTrash:)];
    [menu addItem: item];
    RELEASE (item);
    
    RELEASE (arp);
    return AUTORELEASE (menu);
  } else if (isWsIcon) {
    /* Workspace icon: use default menu behavior from superclass. */
    return [super menuForEvent: theEvent];
  } else if ([self isSpecialIcon] == NO) {
    NSString *appPath = [ws fullPathForApplication: appName];
    
    if (appPath) {
      CREATE_AUTORELEASE_POOL(arp);
      NSMenu *menu = [[NSMenu alloc] initWithTitle: appName];
      NSMenuItem *item;
      GWLaunchedApp *app;
      
      item = [NSMenuItem new];  
      [item setTitle: NSLocalizedString(@"Show In File Viewer", @"")];
      [item setTarget: (Dock *)container];  
      [item setAction: @selector(iconMenuAction:)]; 
      [item setRepresentedObject: appPath];            
      [menu addItem: item];
      RELEASE (item);

      app = [[Workspace gworkspace] launchedAppWithPath: appPath
                                                 andName: appName];      
      if (app && [app isRunning]) {
        item = [NSMenuItem new];  
        [item setTarget: (Dock *)container];  
        [item setAction: @selector(iconMenuAction:)]; 
        [item setRepresentedObject: app];            
      
        if ([app isHidden]) {
          [item setTitle: NSLocalizedString(@"Unhide", @"")];
        } else {
          [item setTitle: NSLocalizedString(@"Hide", @"")];
        }
        
        [menu addItem: item];
        RELEASE (item);      

        item = [NSMenuItem new];  
        [item setTitle: NSLocalizedString(@"Quit", @"")];
        [item setTarget: (Dock *)container];  
        [item setAction: @selector(iconMenuAction:)]; 
        [item setRepresentedObject: app];            
        [menu addItem: item];
        RELEASE (item);
      }
      
      /* Add dock management options */
      if (docked || (app && [app isRunning])) {
        [menu addItem: [NSMenuItem separatorItem]];
        
        /* Show "Keep in Dock" only for running apps that are not docked */
        if (app && [app isRunning] && !docked) {
          item = [NSMenuItem new];
          [item setTarget: (Dock *)container];
          [item setAction: @selector(iconMenuAction:)];
          [item setTitle: NSLocalizedString(@"Keep in Dock", @"")];
          [item setRepresentedObject: self];
          [menu addItem: item];
          RELEASE (item);
        }
        
        /* Show "Remove from Dock" for all docked apps (regardless of running status) */
        if (docked) {
          item = [NSMenuItem new];
          [item setTarget: (Dock *)container];
          [item setAction: @selector(iconMenuAction:)];
          [item setTitle: NSLocalizedString(@"Remove from Dock", @"")];
          [item setRepresentedObject: self];
          [menu addItem: item];
          RELEASE (item);
        }
      } 
      
      RELEASE (arp);
      return AUTORELEASE (menu);
    } else if ([node isDirectory]) {
      /* Folder context menu */
      CREATE_AUTORELEASE_POOL(arp);
      NSMenu *menu = [[NSMenu alloc] initWithTitle: [node name]];
      NSMenuItem *item;
      NSString *path = [node path];

      item = [NSMenuItem new];
      [item setTitle: NSLocalizedString(@"Open", @"")];
      [item setTarget: [Workspace gworkspace]];
      [item setAction: @selector(newViewerAtPath:)];
      [item setRepresentedObject: path];
      [menu addItem: item];
      RELEASE (item);

      item = [NSMenuItem new];
      [item setTitle: NSLocalizedString(@"New Viewer", @"")];
      [item setTarget: [Workspace gworkspace]];
      [item setAction: @selector(newViewerAtPath:)];
      [item setRepresentedObject: path];
      [menu addItem: item];
      RELEASE (item);

      item = [NSMenuItem new];
      [item setTitle: NSLocalizedString(@"Open in Terminal", @"")];
      [item setTarget: [Workspace gworkspace]];
      [item setAction: @selector(openTerminal:)];
      [item setRepresentedObject: path];
      [menu addItem: item];
      RELEASE (item);

      [menu addItem: [NSMenuItem separatorItem]];

      if (docked) {
        item = [NSMenuItem new];
        [item setTarget: (Dock *)container];
        [item setAction: @selector(iconMenuAction:)];
        [item setTitle: NSLocalizedString(@"Remove from Dock", @"")];
        [item setRepresentedObject: self];
        [menu addItem: item];
        RELEASE (item);
      }

      RELEASE (arp);
      return AUTORELEASE (menu);
    }
  }
  
  return [super menuForEvent: theEvent];
}

- (void)startExternalDragOnEvent:(NSEvent *)event
                 withMouseOffset:(NSSize)offset
{
  NSPasteboard *pb = [NSPasteboard pasteboardWithName: NSDragPboard];	
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  [dict setObject: appName forKey: @"name"];
  [dict setObject: [node path] forKey: @"path"];
  [dict setObject: [NSNumber numberWithBool: docked] 
           forKey: @"docked"];
  [dict setObject: [NSNumber numberWithBool: launched] 
           forKey: @"launched"];
  [dict setObject: [NSNumber numberWithBool: apphidden] 
           forKey: @"hidden"];
  
  [pb declareTypes: [NSArray arrayWithObject: @"DockIconPboardType"] 
             owner: nil];
    
  if ([pb setData: [NSArchiver archivedDataWithRootObject: dict] 
          forType: @"DockIconPboardType"]) {
    NSPoint dragPoint = [event locationInWindow]; 
    NSSize fs = [self frame].size; 
 
    dragPoint.x -= ((fs.width - icnPoint.x) / 2);
    dragPoint.y -= ((fs.height - icnPoint.y) / 2);
      
    [self unselect];  
    [self setIsDndSourceIcon: YES];
    [(Dock *)container setDndSourceIcon: self];
    [(Dock *)container tile];
    
    [[self window] dragImage: dragIcon
                          at: dragPoint 
                      offset: NSZeroSize
                       event: event
                  pasteboard: pb
                      source: self
                   slideBack: NO];
  }
}

- (void)draggedImage:(NSImage *)anImage
	     endedAt:(NSPoint)aPoint
	   deposited:(BOOL)flag
{
	dragdelay = 0;
  [self setIsDndSourceIcon: NO];
  [(Dock *)container setDndSourceIcon: nil];
}

- (void)drawRect:(NSRect)rect
{   
#define DRAWDOT(c1, c2, p) \
{ \
[c1 set]; \
NSRectFill(NSMakeRect(p.x, p.y, 3, 2)); \
[c2 set]; \
NSRectFill(NSMakeRect(p.x + 1, p.y, 2, 1)); \
NSRectFill(NSMakeRect(p.x + 2, p.y + 1, 1, 1)); \
}

#define DRAWDOTS(c1, c2, p) \
{ \
int i, x = p.x, y = p.y; \
for (i = 0; i < 3; i++) { \
[c1 set]; \
NSRectFill(NSMakeRect(x, y, 3, 2)); \
[c2 set]; \
NSRectFill(NSMakeRect(x + 1, y, 2, 1)); \
NSRectFill(NSMakeRect(x + 2, y + 1, 1, 1)); \
x += 6; \
} \
}
 	
  if (isSelected || launching) {
    [highlightColor set];
    NSRectFill(rect);

    if (highlightImage && useHligtImage) {
      [highlightImage dissolveToPoint: NSZeroPoint fraction: 0.2];
    }
  }
  
  if (launching) {		
	  [icon dissolveToPoint: icnPoint fraction: dissFract];
	  return;
  }
  
  if (isDndSourceIcon == NO) {
    /* Adjust icon position when bouncing */
    NSPoint drawPoint = icnPoint;
    if (isBouncing && bounceOffset != 0.0) {
      DockPosition pos = DockPositionBottom;
      
      if ([container respondsToSelector: @selector(position)]) {
        pos = [(Dock *)container position];
      }
      
      if (pos == DockPositionLeft) {
        drawPoint.x += bounceOffset;
      } else if (pos == DockPositionRight) {
        drawPoint.x -= bounceOffset;
      } else {
        drawPoint.y += bounceOffset;  /* Add to Y to move upward in Cocoa coords */
      }
    }
    
    if (isTrashIcon == NO) {
      [icon compositeToPoint: drawPoint operation: NSCompositeSourceOver];
    } else {
      /* When dragging mountpoints only, show Eject icon; otherwise show Trash icon */
      if (isDragMountpointOnly && ejectIcon) {
        [ejectIcon compositeToPoint: drawPoint operation: NSCompositeSourceOver];
      } else if (trashFull) {
        [trashFullIcon compositeToPoint: drawPoint operation: NSCompositeSourceOver];
      } else {
        [icon compositeToPoint: drawPoint operation: NSCompositeSourceOver];
      }
    }

  if (isWsIcon == YES) 
  {
      NSPoint p;
      p.x = (rect.size.width / 2) - 1;
      p.y = 2;
      DRAWDOT([NSColor blackColor], [NSColor whiteColor], p);
  }

    if (launched)
    {
      NSPoint p;
      p.x = (rect.size.width / 2) - 1;
      p.y = 2;
      DRAWDOT([NSColor blackColor], [NSColor whiteColor], p);
    }
    
  }
}

- (BOOL)acceptsDraggedPaths:(NSArray *)paths
{
  unsigned i;

  if ([self isSpecialIcon] == NO) {
    for (i = 0; i < [paths count]; i++) {
      NSString *path = [paths objectAtIndex: i];
      FSNode *nod = [FSNode nodeWithPath: path];

      if (([nod isPlain] || [nod isDirectory] || ([nod isPackage] && ([nod isApplication] == NO))) == NO) {
        return NO;
      }
    }

    [self select]; 
    return YES;
    
  } else if (isTrashIcon) {
    NSString *fromPath = [[paths objectAtIndex: 0] stringByDeletingLastPathComponent];
    BOOL accept = YES;
    
    if ([fromPath isEqual: [[GWDesktopManager desktopManager] trashPath]] == NO) {
      NSArray *vpaths = [ws mountedLocalVolumePaths];
    
      for (i = 0; i < [paths count]; i++) {
        NSString *path = [paths objectAtIndex: i];

        if (([vpaths containsObject: path] == NO)
                          && ([fm isWritableFileAtPath: path] == NO)) {
          accept = NO;
          break;
        }
      }
    } else {
      accept = NO;
    }
      
    if (accept) {
      [self select];
    }
  
    return accept;
  }

  return NO;
}

- (void)setDraggedPaths:(NSArray *)paths
{
  NSUInteger i;
  
  [self unselect];
        
  if ([self isSpecialIcon] == NO)
    {
      for (i = 0; i < [paths count]; i++)
        {
          NSString *path = [paths objectAtIndex: i];
          FSNode *nod = [FSNode nodeWithPath: path];
          
          if ([nod isPlain] || ([nod isPackage] && ([nod isApplication] == NO)))
            {
              NS_DURING
                {
                  [ws openFile: path withApplication: appName];
                }
              NS_HANDLER
                {
                  NSRunAlertPanel(NSLocalizedString(@"error", @""), 
                                  [NSString stringWithFormat: @"%@ %@!", 
                                            NSLocalizedString(@"Can't open ", @""), [path lastPathComponent]],
                                  NSLocalizedString(@"OK", @""), 
                                  nil, 
                                  nil);                                     
                }
              NS_ENDHANDLER  
             }
        } 
    }
  else if (isTrashIcon) // FIXME this is largely similar to RecyclerIcon ####
    {
      NSArray *vpaths = [ws mountedLocalVolumePaths];
      NSMutableArray *files = [NSMutableArray array];
      NSMutableArray *umountPaths = [NSMutableArray array];
      NSMutableDictionary *opinfo = [NSMutableDictionary dictionary];
      
      for (i = 0; i < [paths count]; i++)
        {
          NSString *srcpath = [paths objectAtIndex: i];
          
          if ([vpaths containsObject: srcpath])
            {
              [umountPaths addObject: srcpath];
            }
          else
            {
              [files addObject: [srcpath lastPathComponent]];
            }
        }
      
    for (i = 0; i < [umountPaths count]; i++)
      {
        NSString *umpath = [umountPaths objectAtIndex: i];
        
        // Don't allow ejecting root filesystem
        if ([[Workspace gworkspace] isRootFilesystem: umpath]) {
          NSString *err = NSLocalizedString(@"Error", @"");
          NSString *msg = NSLocalizedString(@"You cannot eject the root filesystem", @"");
          NSString *buttstr = NSLocalizedString(@"OK", @"");
          NSRunAlertPanel(err, msg, buttstr, nil, nil);
          continue;
        }
        
        // Use unified unmount method
        [[Workspace gworkspace] unmountVolumeAtPath: umpath];
      }
    
    if ([files count])
      {
        NSString *fromPath = [[paths objectAtIndex: 0] stringByDeletingLastPathComponent];
        
        if ([fm isWritableFileAtPath: fromPath] == NO) {
          NSString *err = NSLocalizedString(@"Error", @"");
          NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
          NSString *buttstr = NSLocalizedString(@"Continue", @"");
          NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, fromPath], buttstr, nil, nil);   
          return;
        }
        
        [opinfo setObject: NSWorkspaceRecycleOperation forKey: @"operation"];
        [opinfo setObject: fromPath forKey: @"source"];
        [opinfo setObject: [node path] forKey: @"destination"];
        [opinfo setObject: files forKey: @"files"];
        
        [[GWDesktopManager desktopManager] performFileOperation: opinfo];
      }
    }
}

- (void)setIsDragMountpointOnly:(BOOL)value
{
  if (isDragMountpointOnly != value) {
    isDragMountpointOnly = value;
    if (isTrashIcon) {
      [self setNeedsDisplay: YES];
    }
  }
}

- (BOOL)isDragMountpointOnly
{
  return isDragMountpointOnly;
}

@end
