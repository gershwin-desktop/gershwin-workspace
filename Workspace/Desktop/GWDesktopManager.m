/* GWDesktopManager.m
 *  
 * Copyright (C) 2005-2021 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale <enrico@imago.ro>
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

#import <AppKit/AppKit.h>
#include <GNUstepGUI/GSDisplayServer.h>
#import "GWDesktopManager.h"
#import "GWDesktopWindow.h"
#import "GWDesktopView.h"
#import "Dock.h"
#import "FSNFunctions.h"
#import "Workspace.h"
#import "GWViewersManager.h"
#import "Thumbnailer/GWThumbnailer.h"
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <math.h>
#include <unistd.h>

#define RESV_MARGIN 10

static GWDesktopManager *desktopManager = nil;

@implementation GWDesktopManager

+ (GWDesktopManager *)desktopManager
{
  if (desktopManager == nil)
    {
      desktopManager = [[GWDesktopManager alloc] init];
    }
  return desktopManager;
}

- (void)dealloc
{
  [[ws notificationCenter] removeObserver: self];
  [nc removeObserver: self];
  RELEASE (dskNode);
  RELEASE (win);
  RELEASE (dock);
  RELEASE (mpointWatcher);

  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self) {
    NSUserDefaults *defaults;
    id defentry;
    NSString *path;
    id window = nil;

    fm = [NSFileManager defaultManager];
    nc = [NSNotificationCenter defaultCenter];
    ws = [NSWorkspace sharedWorkspace];
    gworkspace = [Workspace gworkspace];
    fsnodeRep = [FSNodeRep sharedInstance];
    mpointWatcher = [[MPointWatcher alloc] initForManager: self];
    
    [self checkDesktopDirs];

    path = [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop"];  
    ASSIGN (dskNode, [FSNode nodeWithPath: path]);

    defaults = [NSUserDefaults standardUserDefaults];	

    singleClickLaunch = [defaults boolForKey: @"singleclicklaunch"];
    defentry = [defaults objectForKey: @"dockposition"];
    dockPosition = defentry ? [defentry intValue] : DockPositionRight;

    [self setReservedFrames];
    
    usexbundle = [defaults boolForKey: @"xbundle"];

    if (usexbundle) {
      window = [self loadXWinBundle];
      [window retain];
    }

    if (window == nil) {
      usexbundle = NO;
      window = [GWDesktopWindow new];
    }

    [window setDelegate: self];

    desktopView = [[GWDesktopView alloc] initForManager: self];
    [(NSWindow *)window setContentView: desktopView];
    RELEASE (desktopView);

    win = RETAIN (window);
    RELEASE (window);

    hidedock = [defaults boolForKey: @"hidedock"];
    
    NS_DURING
      {
        dock = [[Dock alloc] initForManager: self];
      }
    NS_HANDLER
      {
        NSLog(@"GWDesktopManager: exception initializing Dock: %@", [localException reason]);
        dock = [[Dock alloc] initForManager: self];
      }
    NS_ENDHANDLER
        
    [nc addObserver: self 
           selector: @selector(fileSystemWillChange:) 
               name: @"GWFileSystemWillChangeNotification"
             object: nil];

    [nc addObserver: self 
           selector: @selector(fileSystemDidChange:) 
               name: @"GWFileSystemDidChangeNotification"
             object: nil];

    [nc addObserver: self 
           selector: @selector(watcherNotification:) 
               name: @"GWFileWatcherFileDidChangeNotification"
             object: nil];    
    
    [[ws notificationCenter] addObserver: self 
				selector: @selector(newVolumeMounted:)
				    name: NSWorkspaceDidMountNotification
				  object: nil];

    [[ws notificationCenter] addObserver: self 
				selector: @selector(mountedVolumeWillUnmount:)
				    name: NSWorkspaceWillUnmountNotification
				  object: nil];

    [[ws notificationCenter] addObserver: self 
				selector: @selector(mountedVolumeDidUnmount:)
				    name: NSWorkspaceDidUnmountNotification
				  object: nil];

    [self setContextHelp];
  }
  
  return self;
}

- (void)activateDesktop
{
  NSLog(@"DEBUG: GWDesktopManager activateDesktop called");
  [win activate];
  NSLog(@"DEBUG: Desktop window activated");
  
  // Set the menu for the desktop window so it gets exported via DBus/AppMenu
  // This ensures Menu.app can find the menus when the desktop is active
  // We do this after activation to avoid triggering the Menu.app scan loop
  [win setMenu: [NSApp mainMenu]];
  
  // Set the desktop window as the X11 active window so Menu.app shows its menus
  // This is needed because the desktop is the first window and should show menus on startup
  Display *display = XOpenDisplay(NULL);
  if (display)
    {
      Window root = DefaultRootWindow(display);
      Atom netActiveWindow = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
      
      // Get the X11 window ID for the desktop window
      GSDisplayServer *srv = GSServerForWindow(win);
      if (srv)
        {
          Window desktopXWindow = (Window)(uintptr_t)[srv windowDevice: [win windowNumber]];
          
          if (desktopXWindow)
            {
              XChangeProperty(display, root, netActiveWindow, XA_WINDOW, 32,
                             PropModeReplace, (unsigned char*)&desktopXWindow, 1);
              XFlush(display);
              NSLog(@"DEBUG: Set _NET_ACTIVE_WINDOW to desktop window 0x%lx", desktopXWindow);
            }
        }
      XCloseDisplay(display);
    }
  
  [desktopView showMountedVolumes];
  [desktopView showContentsOfNode: dskNode];
  [self addWatcherForPath: [dskNode path]];
    
  if ((hidedock == NO) && ([dock superview] == nil)) {
    NSLog(@"DEBUG: Adding dock as subview (hidedock=%d)", hidedock);
    [desktopView addSubview: dock];
    [dock tile];
    NSLog(@"DEBUG: Dock added to desktop view, frame: %@", NSStringFromRect([dock frame]));
  } else {
    NSLog(@"DEBUG: Dock NOT added (hidedock=%d, superview=%@)", hidedock, [dock superview]);
  }
  
  [mpointWatcher startWatching];  
  NSLog(@"DEBUG: activateDesktop completed");
}

- (void)deactivateDesktop
{
  [win deactivate];
  [self removeWatcherForPath: [dskNode path]];  
  [mpointWatcher stopWatching];
}

- (BOOL)isActive
{
  return [win isVisible];
}

- (void)checkDesktopDirs
{
  NSString *path;
  BOOL isdir;

  path = [NSHomeDirectory() stringByAppendingPathComponent: @"Desktop"]; 

  if (([fm fileExistsAtPath: path isDirectory: &isdir] && isdir) == NO) {
    NSString *hiddenNames = @".gwsort\n.gwdir\n.hidden\n";

    if ([fm createDirectoryAtPath: path attributes: nil] == NO) {
      NSRunAlertPanel(NSLocalizedString(@"error", @""), 
             NSLocalizedString(@"Can't create the Desktop directory!", @""), 
                                        NSLocalizedString(@"OK", @""), nil, nil);                                     
      [NSApp terminate: self];
    }

    [hiddenNames writeToFile: [path stringByAppendingPathComponent: @".hidden"]
                  atomically: YES];
  }

  path = [NSHomeDirectory() stringByAppendingPathComponent: @".Trash"]; 

  if ([fm fileExistsAtPath: path isDirectory: &isdir] == NO) {
    if ([fm createDirectoryAtPath: path attributes: nil] == NO) {
      NSLog(@"Can't create the Recycler directory! Quitting now.");
      [NSApp terminate: self];
    }
  }
}

- (void)setUsesXBundle:(BOOL)value
{
  usexbundle = value;
  
  if ([self isActive]) { 
    id window = nil;  
    BOOL changed = NO;
    
    if (usexbundle) {
      if ([win isKindOfClass: [GWDesktopWindow class]]) {
        window = [self loadXWinBundle];
        changed = (window != nil);
      }
    } else {
      if ([win isKindOfClass: [GWDesktopWindow class]] == NO) {
        window = [GWDesktopWindow new];
        changed = YES;
      }
    }
    
    if (changed) {
      RETAIN (desktopView);
      [desktopView removeFromSuperview];

      [win close];
      DESTROY (win);
      
      [window setDelegate: self];
      [(NSWindow *)window setContentView: desktopView];
      RELEASE (desktopView);

      win = RETAIN (window);
      RELEASE (window);
      
      [win activate];
    }
  }
}

- (BOOL)usesXBundle
{
  return usexbundle;
}

- (id)loadXWinBundle
{
  NSEnumerator	*enumerator;
  NSString *bpath;
  NSBundle *bundle;
  
  enumerator = [NSSearchPathForDirectoriesInDomains
    (NSLibraryDirectory, NSAllDomainsMask, YES) objectEnumerator];
  while ((bpath = [enumerator nextObject]) != nil)
    {
      bpath = [bpath stringByAppendingPathComponent: @"Bundles"];
      bpath = [bpath stringByAppendingPathComponent: @"XDesktopWindow.bundle"];

      bundle = [NSBundle bundleWithPath: bpath];
  
      if (bundle) {
        id pC;

        pC = [[[bundle principalClass] alloc] init];
        [pC autorelease];
	return pC;
      }
    }

  return nil;
}

- (BOOL)hasWindow:(id)awindow
{
  return (win && (win == awindow));
}

- (id)desktopView
{
  return desktopView;
}


- (BOOL)singleClickLaunch
{
  return singleClickLaunch;
}

- (void)setSingleClickLaunch:(BOOL)value
{
  singleClickLaunch = value;
  [dock setSingleClickLaunch:singleClickLaunch];
}

- (Dock *)dock
{
  return dock;
}

- (DockPosition)dockPosition
{
  return dockPosition;
}

- (void)setDockPosition:(DockPosition)pos
{
  dockPosition = pos;
  [dock setPosition: pos];
  [self setReservedFrames];
  [desktopView dockPositionDidChange];
}

- (void)setDockActive:(BOOL)value
{
  hidedock = !value;
  
  if (hidedock && [dock superview]) {
    [dock removeFromSuperview];
    [desktopView setNeedsDisplayInRect: dockReservedFrame];
    
  } else if ([dock superview] == nil) {
    [desktopView addSubview: dock];
    [dock tile];
    [desktopView setNeedsDisplayInRect: dockReservedFrame];
  }
}

- (BOOL)dockActive
{
  return !hidedock;
}

- (void)setReservedFrames
{
  NSRect screenFrame = [[NSScreen mainScreen] frame];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
  NSString *menuStyle = [defaults objectForKey: @"NSMenuInterfaceStyle"];
  
  macmenuReservedFrame = NSZeroRect;

  if (menuStyle && [menuStyle isEqual: @"NSMacintoshInterfaceStyle"]) {
    macmenuReservedFrame.size.width = screenFrame.size.width;
    macmenuReservedFrame.size.height = 25;
    macmenuReservedFrame.origin.x = 0;
    macmenuReservedFrame.origin.y = screenFrame.size.height - 25;    
  }

  dockReservedFrame.size.height = screenFrame.size.height;
  dockReservedFrame.size.width = 64 + RESV_MARGIN;
  dockReservedFrame.origin.x = 0;
  dockReservedFrame.origin.y = 0;
  
  if (dockPosition == DockPositionRight) {
    dockReservedFrame.origin.x = screenFrame.size.width - 64 - RESV_MARGIN;
  }
}

- (NSRect)macmenuReservedFrame
{
  return macmenuReservedFrame;
}

- (NSRect)dockReservedFrame
{
  return dockReservedFrame;
}

- (void)deselectAllIcons
{
  [desktopView unselectOtherReps: nil];
  [desktopView selectionDidChange];
  [desktopView stopRepNameEditing];
}

- (void)deselectInSpatialViewers
{
  [[gworkspace viewersManager] selectedSpatialViewerChanged: nil];
}

- (void)addWatcherForPath:(NSString *)path
{
  [gworkspace addWatcherForPath: path];
}

- (void)removeWatcherForPath:(NSString *)path
{
  [gworkspace removeWatcherForPath: path];
}

- (void)showRootViewer
{
  [gworkspace newViewerAtPath: path_separator()];
}

- (BOOL)selectFile:(NSString *)fullPath
inFileViewerRootedAtPath:(NSString *)rootFullpath
{
  return [gworkspace selectFile: fullPath inFileViewerRootedAtPath: rootFullpath];
}

- (void)performFileOperation:(NSDictionary *)opinfo
{
  [gworkspace performFileOperation: opinfo];
}
                      
- (NSString *)trashPath
{
  return [gworkspace trashPath];
}

- (void)moveToTrash
{
  [gworkspace moveToTrash];
}

- (void)checkNewRemovableMedia
{
  NS_DURING
  {
    [NSThread detachNewThreadSelector: @selector(mountRemovableMedia)
                             toTarget: [GWMounter class]
                           withObject: nil];
  }
  NS_HANDLER
  {
    NSLog(@"Error! A fatal error occurred while detaching the thread.");
  }
  NS_ENDHANDLER
}

- (void)makeThumbnails:(id)sender
{
  NSString *path;

  path = [dskNode path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t makeThumbnails:path];
      [t release];
    }
}

- (void)removeThumbnails:(id)sender
{
  NSString *path;

  path = [dskNode path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t removeThumbnails:path];
      [t release];
    }
}

- (void)fileSystemWillChange:(NSNotification *)notif
{
  NSDictionary *opinfo = (NSDictionary *)[notif object];  

  if ([dskNode involvedByFileOperation: opinfo]) {
    [[self desktopView] nodeContentsWillChange: opinfo];
  }
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  NSDictionary *opinfo = (NSDictionary *)[notif object];  

  if ([dskNode isValid] == NO) {
    NSRunAlertPanel(nil, 
                    NSLocalizedString(@"The Desktop directory has been deleted! Quitting now!", @""),
                    NSLocalizedString(@"OK", @""), 
                    nil, 
                    nil);                                     
    [NSApp terminate: self];
  }

  /* update the desktop view, but only if it is visible */
  if ([self isActive] && [dskNode involvedByFileOperation: opinfo])
    {
      [[self desktopView] nodeContentsDidChange: opinfo];  
    }
  
  if ([self dockActive])
    {
      [dock nodeContentsDidChange: opinfo];
    }
}

- (void)watcherNotification:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  NSString *path = [info objectForKey: @"path"];
  NSString *event = [info objectForKey: @"event"];
  
  NSLog(@"DEBUG: GWDesktopManager watcherNotification called");
  NSLog(@"DEBUG: path = %@, event = %@", path, event);
  NSLog(@"DEBUG: dskNode path = %@", [dskNode path]);
  
  /* Check if this is a change in one of our watched mount root directories */
  if ([mpointWatcher isWatchingPath: path]) {
    NSLog(@"DEBUG: Change detected in mount root directory: %@", path);
    /* Verify the mount is ready before showing it on desktop */
    [self verifyAndShowVolumeAtPath: path];
    return;
  }
  
  if ([path isEqual: [dskNode path]])
    {
      NSLog(@"DEBUG: Path matches desktop node path");
      if ([event isEqual: @"GWWatchedPathDeleted"])
        {
          NSRunAlertPanel(nil, 
                          NSLocalizedString(@"The Desktop directory has been deleted! Quitting now!", @""),
                          NSLocalizedString(@"OK", @""), 
                          nil, 
                          nil);                                     
          [NSApp terminate: self];
        }
      /* update the desktop view, but only if active */
      else if ([self isActive]) 
        {
          NSLog(@"DEBUG: Desktop is active, calling watchedPathChanged on desktop view");
          [[self desktopView] watchedPathChanged: info];
        }
      else
        {
          NSLog(@"DEBUG: Desktop is NOT active, skipping update");
        }
    }
  else
    {
      NSLog(@"DEBUG: Path does NOT match desktop node path");
    }
  /* update the dock, if active */
  if ([self dockActive])
    {
      NSLog(@"DEBUG: Dock is active, calling watchedPathChanged on dock");
      [dock watchedPathChanged: info];
    }
}

- (void)thumbnailsDidChangeInPaths:(NSArray *)paths
{
  [[self desktopView] updateIcons];
}

- (void)removableMediaPathsDidChange
{
  [[self desktopView] showMountedVolumes];
  [mpointWatcher startWatching];
}

- (void)verifyAndShowVolumeAtPath:(NSString *)mountRootPath
{
  /* Spawn a background worker thread to perform verification so we don't block the main thread */
  [NSThread detachNewThreadSelector:@selector(verifyAndShowVolumeWorker:) toTarget:self withObject:mountRootPath];
}

- (void)verifyAndShowVolumeWorker:(NSString *)mountRootPath
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSFileManager *localFM = [NSFileManager defaultManager];
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  int maxAttempts = 5;
  int attempt = 0;
  BOOL verified = NO;

  /* Try to verify the mount with exponential backoff */
  while (attempt < maxAttempts && !verified) {
    attempt++;

    /* Wait with exponential backoff: 0.1s, 0.2s, 0.4s, 0.8s, 1.6s */
    if (attempt > 1) {
      usleep((useconds_t)(100000 * pow(2, attempt - 2)));
    }

    NSLog(@"MountVerification: Attempt %d/%d to verify mount root: %@", attempt, maxAttempts, mountRootPath);

    @autoreleasepool {
      NSError *contentsError = nil;
      NSArray *contents = [localFM contentsOfDirectoryAtPath:mountRootPath error:&contentsError];

      if (contents && [contents count] > 0) {
        for (NSString *item in contents) {
          NSString *itemPath = [mountRootPath stringByAppendingPathComponent:item];
          BOOL isDir = NO;

          if ([localFM fileExistsAtPath:itemPath isDirectory:&isDir] && isDir) {
            NSArray *mountedPaths = [workspace mountedLocalVolumePaths];
            if ([mountedPaths containsObject:itemPath]) {
              NSLog(@"MountVerification: Verified mounted volume at: %@", itemPath);
              verified = YES;
              break;
            }

            NSError *readError = nil;
            NSArray *subContents = [localFM contentsOfDirectoryAtPath:itemPath error:&readError];
            if (subContents) {
              NSLog(@"MountVerification: Directory is accessible: %@", itemPath);
              verified = YES;
              break;
            }
          }
        }
      }
    }
  }

  if (verified) {
    NSLog(@"MountVerification: Mount verified after %d attempt(s), updating desktop", attempt);
    [self performSelectorOnMainThread:@selector(removableMediaPathsDidChange) withObject:nil waitUntilDone:NO];
  } else {
    NSLog(@"MountVerification: Could not verify mount at %@ after %d attempts, skipping desktop update", mountRootPath, maxAttempts);
  }

  [pool release];
}

- (void)hideDotsFileDidChange:(BOOL)hide
{
  [[self desktopView] reloadFromNode: dskNode];
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  [[self desktopView] reloadFromNode: dskNode];
}

- (void)newVolumeMounted:(NSNotification *)notif
{
  NSLog(@"GWDesktopManager: newVolumeMounted notification received: %@", [notif userInfo]);
  if (win && [win isVisible]) {
    NSDictionary *dict = [notif userInfo];  
    NSString *volpath = [dict objectForKey: @"NSDevicePath"];

    NSLog(@"GWDesktopManager: Calling newVolumeMountedAtPath for %@", volpath);
    [[self desktopView] newVolumeMountedAtPath: volpath];
  } else {
    NSLog(@"GWDesktopManager: Desktop window not visible, skipping mount display");
  }
}

- (void)mountedVolumeWillUnmount:(NSNotification *)notif
{
  NSLog(@"GWDesktopManager: mountedVolumeWillUnmount notification received: %@", [notif userInfo]);
  if (win && [win isVisible]) {
    NSDictionary *dict = [notif userInfo];  
    NSString *volpath = [dict objectForKey: @"NSDevicePath"];

    NSLog(@"GWDesktopManager: Processing will unmount for %@", volpath);
    [fsnodeRep lockPaths: [NSArray arrayWithObject: volpath]];
    [[self desktopView] workspaceWillUnmountVolumeAtPath: volpath];
  } else {
    NSLog(@"GWDesktopManager: Desktop window not visible, skipping will unmount processing");
  }
}

- (void)mountedVolumeDidUnmount:(NSNotification *)notif
{
  NSLog(@"GWDesktopManager: mountedVolumeDidUnmount notification received: %@", [notif userInfo]);
  if (win && [win isVisible]) {
    NSDictionary *dict = [notif userInfo];  
    NSString *volpath = [dict objectForKey: @"NSDevicePath"];

    NSLog(@"GWDesktopManager: Processing did unmount for %@", volpath);
    [fsnodeRep unlockPaths: [NSArray arrayWithObject: volpath]];
    [[self desktopView] workspaceDidUnmountVolumeAtPath: volpath];
    
    /* Also send unmount notification to viewers so they can close windows */
    if (volpath) {
      NSString *parent = [volpath stringByDeletingLastPathComponent];
      NSString *name = [volpath lastPathComponent];
      NSDictionary *opinfo = @{ @"operation": @"UnmountOperation",
                                @"source": parent,
                                @"destination": parent,
                                @"files": @[name],
                                @"unmounted": volpath };
      
      NSLog(@"GWDesktopManager: Posting GWFileSystemDidChangeNotification for unmount of %@", volpath);
      [[NSNotificationCenter defaultCenter] postNotificationName:@"GWFileSystemDidChangeNotification" object:opinfo];
    }
  } else {
    NSLog(@"GWDesktopManager: Desktop window not visible, skipping did unmount processing");
  }
}

- (void)unlockVolumeAtPath:(NSString *)volpath
{
  [fsnodeRep unlockPaths: [NSArray arrayWithObject: volpath]];
  [[self desktopView] unlockVolumeAtPath: volpath];
}

- (void)mountedVolumesDidChange
{
  [[self desktopView] showMountedVolumes];
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  [defaults setObject: [NSNumber numberWithInt: dockPosition]
               forKey: @"dockposition"];

  [defaults setBool: singleClickLaunch forKey: @"singleclicklaunch"];

  [defaults setBool: usexbundle forKey: @"xbundle"];
  [defaults setBool: hidedock forKey: @"hidedock"];
  
  [dock updateDefaults];
  [desktopView updateDefaults];
}

- (void)setContextHelp
{
  NSHelpManager *manager = [NSHelpManager sharedHelpManager];
  NSString *help;

  help = @"Desktop.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
               withObject: [self desktopView]];

  help = @"Dock.rtfd";
  [manager setContextHelp: (NSAttributedString *)help withObject: dock];
  
  help = @"Recycler.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
               withObject: [dock trashIcon]];
}

@end


//
// GWDesktopWindow Delegate Methods
//
@implementation GWDesktopManager (GWDesktopWindowDelegateMethods)

- (BOOL)validateItem:(id)menuItem
{
  if ([self isActive]) {
    SEL action = [menuItem action];

    if (sel_isEqual(action, @selector(duplicateFiles:))
                || sel_isEqual(action, @selector(recycleFiles:))
                      || sel_isEqual(action, @selector(deleteFiles:))) {
      return ([[desktopView selectedNodes] count] > 0);

    } else if (sel_isEqual(action, @selector(openSelection:))) {
      NSArray *selection = [desktopView selectedNodes];
     
      return (selection && [selection count] 
            && ([selection isEqual: [NSArray arrayWithObject: dskNode]] == NO));
    
    } else if (sel_isEqual(action, @selector(openWith:))) {
      NSArray *selection = [desktopView selectedNodes];
      BOOL canopen = YES;
      int i;

      if (selection && [selection count]
            && ([selection isEqual: [NSArray arrayWithObject: dskNode]] == NO)) {
        for (i = 0; i < [selection count]; i++) {
          FSNode *node = [selection objectAtIndex: i];

          if (([node isPlain] == NO) 
                && (([node isPackage] == NO) || [node isApplication])) {
            canopen = NO;
            break;
          }
        }
      } else {
        canopen = NO;
      }

      return canopen;
      
    } else if (sel_isEqual(action, @selector(openSelectionAsFolder:))) {
      NSArray *selection = [desktopView selectedNodes];
    
      if (selection && ([selection count] == 1)) {  
        return [[selection objectAtIndex: 0] isDirectory];
      }
    
      return NO;
    }
         
    return YES;
  }
  
  return NO;
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  NSArray *selreps = [desktopView selectedReps];
  NSUInteger i;
    
  for (i = 0; i < [selreps count]; i++) {
    FSNode *node = [[selreps objectAtIndex: i] node];
        
    if ([node hasValidPath]) {           
      NS_DURING
        {
      if ([node isDirectory]) {
        if ([node isPackage]) {    
          if ([node isApplication] == NO) {
            [gworkspace openFile: [node path]];
          } else {
            [ws launchApplication: [node path]];
          }
        } else {
          // Set animation rect from the desktop icon
          id icon = [desktopView repOfSubnodePath: [node path]];
          if (icon && [icon respondsToSelector: @selector(window)])
            {
              NSRect iconBounds = [icon bounds];
              NSRect rectInWindow = [icon convertRect: iconBounds toView: nil];
              NSRect rectOnScreen = [[icon window] convertRectToScreen: rectInWindow];
              [[gworkspace viewersManager] setPendingOpenAnimationRect: rectOnScreen];
            }
          [gworkspace newViewerAtPath: [node path]];
        } 
      } else if ([node isPlain]) {        
        [gworkspace openFile: [node path]];
      }
        }
      NS_HANDLER
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""), 
              [NSString stringWithFormat: @"%@ %@!", 
                        NSLocalizedString(@"Can't open ", @""), [node name]],
                                            NSLocalizedString(@"OK", @""), 
                                            nil, 
                                            nil);                                     
        }
      NS_ENDHANDLER
      
    } else {
      NSRunAlertPanel(NSLocalizedString(@"error", @""), 
          [NSString stringWithFormat: @"%@ %@!", 
                    NSLocalizedString(@"Can't open ", @""), [node name]],
                                        NSLocalizedString(@"OK", @""), 
                                        nil, 
                                        nil);                                     
    }
  }
}

- (void)openSelectionAsFolder
{
  NSArray *selnodes = [desktopView selectedNodes];
  unsigned i;
    
  for (i = 0; i < [selnodes count]; i++) {
    FSNode *node = [selnodes objectAtIndex: i];
        
    if ([node isDirectory]) {
      // Set animation rect from the desktop icon
      id icon = [desktopView repOfSubnodePath: [node path]];
      if (icon && [icon respondsToSelector: @selector(window)])
        {
          NSRect iconBounds = [icon bounds];
          NSRect rectInWindow = [icon convertRect: iconBounds toView: nil];
          NSRect rectOnScreen = [[icon window] convertRectToScreen: rectInWindow];
          [[gworkspace viewersManager] setPendingOpenAnimationRect: rectOnScreen];
        }
      [gworkspace newViewerAtPath: [node path]];
    } else if ([node isPlain]) {        
      [gworkspace openFile: [node path]];
    }
  }
}

- (void)openSelectionWith
{
  [gworkspace openSelectedPathsWith];
}

- (void)newFolder
{
  [gworkspace newObjectAtPath: [dskNode path] isDirectory: YES];
}

- (void)newFile
{
  [gworkspace newObjectAtPath: [dskNode path] isDirectory: NO];
}

- (void)duplicateFiles
{
  if ([[desktopView selectedNodes] count]) {
    [gworkspace duplicateFiles];
  }
}

- (void)recycleFiles
{
  if ([[desktopView selectedNodes] count]) {
    [gworkspace moveToTrash];
  }
}

- (void)emptyTrash
{
  [gworkspace emptyTrash: nil];
}

- (void)deleteFiles
{
  if ([[desktopView selectedNodes] count]) {
    [gworkspace deleteFiles];
  }
}

- (void)setShownType:(id)sender
{
  NSString *title = [sender title];
  FSNInfoType type = FSNInfoNameType;

  if ([title isEqual: NSLocalizedString(@"Name", @"")]) {
    type = FSNInfoNameType;
  } else if ([title isEqual: NSLocalizedString(@"Type", @"")]) {
    type = FSNInfoKindType;
  } else if ([title isEqual: NSLocalizedString(@"Size", @"")]) {
    type = FSNInfoSizeType;
  } else if ([title isEqual: NSLocalizedString(@"Modification date", @"")]) {
    type = FSNInfoDateType;
  } else if ([title isEqual: NSLocalizedString(@"Owner", @"")]) {
    type = FSNInfoOwnerType;
  } else {
    type = FSNInfoNameType;
  } 

  [desktopView setShowType: type];  
}

- (void)setExtendedShownType:(id)sender
{
  [desktopView setExtendedShowType: [sender title]]; 
}

- (void)setIconsSize:(id)sender
{
  [desktopView setIconSize: [[sender title] intValue]];
}

- (void)setIconsPosition:(id)sender
{
  NSString *title = [sender title];

  if ([title isEqual: NSLocalizedString(@"Left", @"")]) {
    [desktopView setIconPosition: NSImageLeft];
  } else {
    [desktopView setIconPosition: NSImageAbove];
  }
}

- (void)setLabelSize:(id)sender
{
  [desktopView setLabelTextSize: [[sender title] intValue]];
}

- (void)selectAllInViewer
{
  [desktopView selectAll];
}

- (void)showTerminal
{
  [gworkspace startXTermOnDirectory: [dskNode path]];
}

@end


@implementation MPointWatcher

- (void)dealloc
{
  if (timer && [timer isValid])
    {
      [timer invalidate];
    }

  RELEASE (mountedRemovableVolumes);
  RELEASE (watchedMountRoots);
  [super dealloc];
}

- (id)initForManager:(GWDesktopManager *)mngr
{
  self = [super init];
  
  if (self)
    {
      manager = mngr;
      active = NO;
      fm = [NSFileManager defaultManager];
      watchedMountRoots = [[NSMutableSet alloc] init];

      timer = [NSTimer scheduledTimerWithTimeInterval: 1.5
					       target: self
					     selector: @selector(watchMountPoints:)
					     userInfo: nil
					      repeats: YES];
    }
  
  return self;
}

- (void)startWatching
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray *configuredPaths = [[defaults persistentDomainForName: NSGlobalDomain] objectForKey: @"GSRemovableMediaPaths"];
  NSMutableSet *pathsToWatch = [NSMutableSet set];
  
  /* Add configured removable media paths from preferences */
  if (configuredPaths && [configuredPaths count] > 0) {
    for (NSString *path in configuredPaths) {
      [pathsToWatch addObject: path];
      /* Also watch the parent directory to catch siblings */
      NSString *parent = [path stringByDeletingLastPathComponent];
      if (parent && [parent length] > 1) {
        [pathsToWatch addObject: parent];
      }
    }
  }
  
  /* Add common mount root directories as fallbacks */
  [pathsToWatch addObject: @"/media"];
  [pathsToWatch addObject: @"/Volumes"];
  
  /* Add per-user media directory */
  NSString *userName = NSUserName();
  NSString *userMediaDir = [@"/media" stringByAppendingPathComponent: userName];
  [pathsToWatch addObject: userMediaDir];
  
  NSString *runMediaUser = [[@"/run/media" stringByAppendingPathComponent: userName] stringByStandardizingPath];
  if ([fm fileExistsAtPath: runMediaUser]) {
    [pathsToWatch addObject: runMediaUser];
  }
  
  /* Register watchers for paths that aren't already watched */
  for (NSString *path in pathsToWatch) {
    BOOL isDir = NO;
    if ([fm fileExistsAtPath: path isDirectory: &isDir] && isDir) {
      if (![watchedMountRoots containsObject: path]) {
        [manager addWatcherForPath: path];
        [watchedMountRoots addObject: path];
        NSLog(@"MPointWatcher: Started watching mount root: %@", path);
      }
    }
  }
  
  [mountedRemovableVolumes release];
  mountedRemovableVolumes = [[NSWorkspace sharedWorkspace] mountedRemovableMedia];
  [mountedRemovableVolumes retain];
  active = YES;
}

- (void)stopWatching
{
  /* Remove all watchers we registered */
  for (NSString *path in watchedMountRoots) {
    [manager removeWatcherForPath: path];
    NSLog(@"MPointWatcher: Stopped watching mount root: %@", path);
  }
  [watchedMountRoots removeAllObjects];
  
  active = NO;
  [mountedRemovableVolumes release];
  mountedRemovableVolumes = nil;
}

- (void)watchMountPoints:(id)sender
{
  if (active)
    {
      BOOL removed = NO;
      BOOL added = NO;
      NSUInteger i;
      NSArray *newVolumes = [[NSWorkspace sharedWorkspace] mountedRemovableMedia];

      for (i = 0; i < [mountedRemovableVolumes count]; i++)
	{
	  NSString *vol;

	  vol = [mountedRemovableVolumes objectAtIndex:i];
	  if (![newVolumes containsObject:vol])
	    removed |= YES;
	}

      for (i = 0; i < [newVolumes count]; i++)
	{
	  NSString *vol;

	  vol = [newVolumes objectAtIndex:i];
	  if (![mountedRemovableVolumes containsObject:vol])
	    added |= YES;
	}

      if (added || removed)
	[manager mountedVolumesDidChange];

      [mountedRemovableVolumes release];
      mountedRemovableVolumes = newVolumes;
      [mountedRemovableVolumes retain];
    }
}

- (BOOL)isWatchingPath:(NSString *)path
{
  return [watchedMountRoots containsObject: path];
}

@end


@implementation GWMounter

+ (void)mountRemovableMedia
{
  CREATE_AUTORELEASE_POOL(pool);
  [[NSWorkspace sharedWorkspace] mountNewRemovableMedia];
  RELEASE (pool);  
}

@end
