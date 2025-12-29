/* Workspace.m
 *  
 * Copyright (C) 2003-2016 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola
 * Date: August 2001
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

#include "config.h"

/* the following for getrlimit */
#include <sys/types.h>
#include <sys/time.h>
#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
/* getrlimit */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWFunctions.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "Workspace.h"
#import "Dialogs.h"
#import "OpenWithController.h"
#import "RunExternalController.h"
#import "StartAppWin.h"
#import "Preferences/PrefController.h"
#import "Fiend/Fiend.h"
#import "GWDesktopManager.h"
#import "Dock.h"
#import "GWViewersManager.h"
#import "GWViewer.h"
#import "Finder.h"
#import "Inspector.h"
#import "Operation.h"
#import "TShelf/TShelfWin.h"
#import "TShelf/TShelfView.h"
#import "TShelf/TShelfViewItem.h"
#import "TShelf/TShelfIconsView.h"
#import "History/History.h"


static NSString *defaulteditor = @"nedit.app";
static NSString *defaultxterm = @"xterm";

static Workspace *gworkspace = nil;

NSString *_pendingSystemActionCommand = nil;
NSString *_pendingSystemActionTitle = nil;

@interface Workspace (PrivateMethods)
- (void)_updateTrashContents;
// Async service connection probes
- (void)_probeFSWatcherTimer:(NSTimer *)timer;
- (void)_probeRecyclerTimer:(NSTimer *)timer;
- (void)_probeDDBdTimer:(NSTimer *)timer;
- (void)_probeMDExtractorTimer:(NSTimer *)timer;
@end

@implementation Workspace

#ifndef byname
  #define byname 0
  #define bykind 1
  #define bydate 2
  #define bysize 3
  #define byowner 4
#endif

#define HISTORT_CACHE_MAX 20

#ifndef TSHF_MAXF
  #define TSHF_MAXF 999
#endif


+ (void)initialize
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject: @"Workspace" 
               forKey: @"DesktopApplicationName"];
  [defaults setObject: @"gworkspace" 
               forKey: @"DesktopApplicationSelName"];
  [defaults synchronize];
}

+ (Workspace *)gworkspace
{
  if (gworkspace == nil) {
    gworkspace = [[Workspace alloc] init];
  }	
  return gworkspace;
}

+ (void)registerForServices
{
  NSArray *sendTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, nil];	
  NSArray *returnTypes = [NSArray arrayWithObjects: NSFilenamesPboardType, nil];	
  [NSApp registerServicesMenuSendTypes: sendTypes returnTypes: returnTypes];
}

- (void)dealloc
{
  if (fswatcher && [[(NSDistantObject *)fswatcher connectionForProxy] isValid]) {
    [fswatcher unregisterClient: (id <FSWClientProtocol>)self];
    DESTROY (fswatcher);
  }
  [[NSDistributedNotificationCenter defaultCenter] removeObserver: self];
  [wsnc removeObserver: self];
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  if (logoutTimer && [logoutTimer isValid]) {
    [logoutTimer invalidate];
    DESTROY (logoutTimer);
  }
  DESTROY (recyclerApp);
  DESTROY (ddbd);
  DESTROY (mdextractor);
  RELEASE (gwProcessName);
  RELEASE (gwBundlePath);
  RELEASE (defEditor);
  RELEASE (defXterm);
  RELEASE (defXtermArgs);
  RELEASE (selectedPaths);
  RELEASE (trashContents);
  RELEASE (trashPath);
  RELEASE (watchedPaths);
  RELEASE (fiend);
  RELEASE (history);
  RELEASE (openWithController);
  RELEASE (runExtController);
  RELEASE (startAppWin);
  RELEASE (tshelfWin);
  RELEASE (tshelfPBDir);
  RELEASE (vwrsManager);
  RELEASE (dtopManager);
  DESTROY (inspector);
  DESTROY (fileOpsManager);
  RELEASE (finder);
  RELEASE (launchedApps);
  if (launchDotFallbacks) {
    // Invalidate any pending timers and release the dictionary
    NSEnumerator *enm = [[launchDotFallbacks allValues] objectEnumerator];
    id t = nil;
    while ((t = [enm nextObject])) {
      if ([t isKindOfClass:[NSTimer class]] && [t isValid]) {
        [(NSTimer *)t invalidate];
      }
    }
    RELEASE(launchDotFallbacks);
  }
  RELEASE (storedAppinfoPath);
  RELEASE (storedAppinfoLock);
    
  [super dealloc];
}

- (void)createMenu
{
  NSMenu *mainMenu = [NSMenu new];
  NSMenu *menu;
  NSMenu *subMenu;
  NSMenu *windows, *services;  
  id<NSMenuItem> menuItem;
  
  // File
  menuItem = [mainMenu addItemWithTitle:_(@"File") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  [menu addItemWithTitle:_(@"New Folder") action:@selector(newFolder:) keyEquivalent:@"N"];
  [menu addItemWithTitle:_(@"New File")  action:@selector(newFile:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Open") action:@selector(openSelection:) keyEquivalent:@"o"];
  [menu addItemWithTitle:_(@"Open With...")  action:@selector(openWith:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Open as Folder") action:@selector(openSelectionAsFolder:) keyEquivalent:@"O"];
  [menu addItemWithTitle:_(@"Close Window") action:@selector(performClose:) keyEquivalent:@"w"];
  [menu addItemWithTitle:_(@"Print...") action:@selector(print:) keyEquivalent:@"p"];
  [menu addItemWithTitle:_(@"Get Info") action:@selector(showAttributesInspector:) keyEquivalent:@"i"];
  [menu addItemWithTitle:_(@"Duplicate")  action:@selector(duplicateFiles:) keyEquivalent:@"d"];
  [menu addItemWithTitle:_(@"Destroy")  action:@selector(deleteFiles:) keyEquivalent:@""];
  [menu addItemWithTitle:_(@"Move to Recycler")  action:@selector(recycleFiles:) keyEquivalent:@"r"];

  // Edit
  menuItem = [mainMenu addItemWithTitle:_(@"Edit") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  [menu addItemWithTitle:_(@"Cut") action:@selector(cut:) keyEquivalent:@"x"];
  [menu addItemWithTitle:_(@"Copy") action:@selector(copy:) keyEquivalent:@"c"];
  [menu addItemWithTitle:_(@"Paste") action:@selector(paste:) keyEquivalent:@"v"];
  [menu addItemWithTitle:_(@"Select All") action:@selector(selectAllInViewer:) keyEquivalent:@"a"];

  // View
  menuItem = [mainMenu addItemWithTitle:_(@"View") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Icon") action:@selector(setViewerType:) keyEquivalent:@"1"];
  [menuItem setTag:GWViewTypeIcon];
  [menuItem autorelease];
  [menu addItem:menuItem];
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"List") action:@selector(setViewerType:) keyEquivalent:@"2"];
  [menuItem setTag:GWViewTypeList];
  [menuItem autorelease];
  [menu addItem:menuItem];

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Browser") action:@selector(setViewerType:) keyEquivalent:@"3"];
  [menuItem setTag:GWViewTypeBrowser];
  [menuItem autorelease];
  [menu addItem:menuItem];

  menuItem = [menu addItemWithTitle:_(@"View Behaviour") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  NSLog(@"Created View Behaviour submenu");

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Browsing") action:@selector(setViewerBehaviour:) keyEquivalent:@"B"];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];
  NSLog(@"Added Browsing menu item with target: %@", self);

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Spatial") action:@selector(setViewerBehaviour:) keyEquivalent:@"S"];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];
  NSLog(@"Added Spatial menu item with target: %@", self);

  [subMenu addItem:[NSMenuItem separatorItem]];

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Set Browsing as Default") action:@selector(setDefaultBrowsingBehaviour:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Set Spatial as Default") action:@selector(setDefaultSpatialBehaviour:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];

  menuItem = [menu addItemWithTitle:_(@"Show") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"Name only") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Type") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Size") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Modification date") action:@selector(setShownType:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Owner") action:@selector(setShownType:) keyEquivalent:@""];
      
  menuItem = [menu addItemWithTitle:_(@"Icon Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"24") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"28") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"32") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"36") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"40") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"48") action:@selector(setIconsSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"64") action:@selector(setIconsSize:) keyEquivalent:@""];
      
  menuItem = [menu  addItemWithTitle:_(@"Icon Position") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Up") action:@selector(setIconsPosition:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Left") action:@selector(setIconsPosition:) keyEquivalent:@""];

  menuItem = [menu addItemWithTitle:_(@"Thumbnails") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Make thumbnail(s)") action:@selector(makeThumbnails:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Remove thumbnail(s)") action:@selector(removeThumbnails:) keyEquivalent:@""];

  menuItem = [menu addItemWithTitle:_(@"Label Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"10") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"11") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"12") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"13") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"14") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"15") action:@selector(setLabelSize:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"16") action:@selector(setLabelSize:) keyEquivalent:@""];

  [menu addItemWithTitle:_(@"Viewer") action:@selector(showViewer:) keyEquivalent:@"n"];	
            
  // Tools
  menuItem = [mainMenu addItemWithTitle:_(@"Tools") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];	
		
  menuItem = [menu addItemWithTitle:_(@"Inspectors") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];	
  [subMenu addItemWithTitle:_(@"Show Inspectors") action:NULL keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Contents") action:@selector(showContentsInspector:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Tools") action:@selector(showToolsInspector:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Annotations") action:@selector(showAnnotationsInspector:) keyEquivalent:@""];

  [menu addItemWithTitle:_(@"Finder") action:@selector(showFinder:) keyEquivalent:@"f"];

  [menu addItemWithTitle:_(@"Run...") action:@selector(runCommand:) keyEquivalent:@"0"];  

  menuItem = [menu addItemWithTitle:_(@"History") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  [subMenu addItemWithTitle:_(@"Show History") action:@selector(showHistory:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Go backward") action:@selector(goBackwardInHistory:) keyEquivalent:@""];
  [subMenu addItemWithTitle:_(@"Go forward") action:@selector(goForwardInHistory:) keyEquivalent:@""];
  
  [menu addItemWithTitle:_(@"Check for disks") action:@selector(checkRemovableMedia:) keyEquivalent:@"E"];
	
  // Windows
  menuItem = [mainMenu addItemWithTitle:_(@"Windows") action:NULL keyEquivalent:@""];
  windows = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: windows forItem: menuItem];		
  [windows addItemWithTitle:_(@"Arrange in Front") action:@selector(arrangeInFront:) keyEquivalent:@""];
  [windows addItemWithTitle:_(@"Miniaturize Window") action:@selector(performMiniaturize:) keyEquivalent:@"m"];

  // About, Preferences
  [mainMenu addItemWithTitle:_(@"About Workspace") action:@selector(showInfo:) keyEquivalent:@""];
  [mainMenu addItemWithTitle:_(@"Preferences...") action:@selector(showPreferences:) keyEquivalent:@","];

  // Services
  menuItem = [mainMenu addItemWithTitle:_(@"Services") action:NULL keyEquivalent:@""];
  services = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: services forItem: menuItem];		

  // Trash
  [mainMenu addItemWithTitle:_(@"Empty Recycler") action:@selector(emptyRecycler:) keyEquivalent:@""];
  
  // Hide
  [mainMenu addItemWithTitle:_(@"Hide") action:@selector(hide:) keyEquivalent:@"h"];
  [mainMenu addItemWithTitle:_(@"Hide Others") action:@selector(hideOtherApplications:)  keyEquivalent:@"H"];
  [mainMenu addItemWithTitle:_(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];

  // Restart, Shut Down, Log Out
  [mainMenu addItemWithTitle:_(@"Restart...") action:@selector(restart:) keyEquivalent:@""];
  [mainMenu addItemWithTitle:_(@"Shut Down...") action:@selector(shutdown:) keyEquivalent:@""];
  [mainMenu addItemWithTitle:_(@"Logout") action:@selector(logout:) keyEquivalent:@""];

  [mainMenu update];

  [NSApp setServicesMenu: services];
  [NSApp setWindowsMenu: windows];
  [NSApp setMainMenu: mainMenu];    
  
  RELEASE (mainMenu);
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
  NSUserDefaults *defaults;
  id entry;
  BOOL boolentry;
  NSArray *extendedInfo;
  NSMenu *menu;
  NSString *lockpath;
  NSUInteger i;
  
  [self createMenu];
    
  [[self class] registerForServices];
  
  ASSIGN (gwProcessName, [[NSProcessInfo processInfo] processName]);
  ASSIGN (gwBundlePath, [[NSBundle mainBundle] bundlePath]);
  
  fm = [NSFileManager defaultManager];
  ws = [NSWorkspace sharedWorkspace];
  fsnodeRep = [FSNodeRep sharedInstance];  
    
  extendedInfo = [fsnodeRep availableExtendedInfoNames];
  menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"View", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Show", @"")] submenu];

  for (i = 0; i < [extendedInfo count]; i++)
    {
      [menu addItemWithTitle: [extendedInfo objectAtIndex: i] 
                      action: @selector(setExtendedShownType:) 
               keyEquivalent: @""];
    }
	    
  defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject: gwProcessName forKey: @"GSWorkspaceApplication"];
        
  entry = [defaults objectForKey: @"reserved_names"];
  if (entry) 
    {
      [fsnodeRep setReservedNames: entry];
    } 
  else 
    {
      [fsnodeRep setReservedNames: [NSArray arrayWithObjects: @".gwdir", @".gwsort", nil]];
    }
        
  entry = [defaults stringForKey: @"defaulteditor"];
  if (entry == nil)
    {
      defEditor = [[NSString alloc] initWithString: defaulteditor];
    } 
  else 
    {
      ASSIGN (defEditor, entry);
    }

	entry = [defaults stringForKey: @"defxterm"];
	if (entry == nil) {
		defXterm = [[NSString alloc] initWithString: defaultxterm];
	} else {
		ASSIGN (defXterm, entry);
  }

	entry = [defaults stringForKey: @"defaultxtermargs"];
	if (entry == nil) {
		defXtermArgs = nil;
	} else {
		ASSIGN (defXtermArgs, entry);
  }
  
  teminalService = [defaults boolForKey: @"terminal_services"];
  [self setUseTerminalService: teminalService];
  		
	entry = [defaults objectForKey: @"default_sortorder"];	
	if (entry == nil) { 
		[defaults setObject: @"0" forKey: @"default_sortorder"];
    [fsnodeRep setDefaultSortOrder: byname];
	} else {
    [fsnodeRep setDefaultSortOrder: [entry intValue]];
	}

  boolentry = [defaults boolForKey: @"GSFileBrowserHideDotFiles"];
  [fsnodeRep setHideSysFiles: boolentry];

	entry = [defaults objectForKey: @"hiddendirs"];
	if (entry) {
    [fsnodeRep setHiddenPaths: entry];
	} 

	entry = [defaults objectForKey: @"history_cache"];
	if (entry) {
    maxHistoryCache = [entry intValue];
	} else {
    maxHistoryCache = HISTORT_CACHE_MAX;
  }
  
  dontWarnOnQuit = [defaults boolForKey: @"NoWarnOnQuit"];

  boolentry = [defaults boolForKey: @"use_thumbnails"];
  [fsnodeRep setUseThumbnails: boolentry];
  
  selectedPaths = [[NSArray alloc] initWithObjects: NSHomeDirectory(), nil];
  trashContents = [NSMutableArray new];
  ASSIGN (trashPath, [self trashPath]);
  [self _updateTrashContents];
  
  startAppWin = [[StartAppWin alloc] init];
  
  // Create standard user directories in $HOME if they don't exist
  [self createStandardUserDirectories];
  
  watchedPaths = [[NSCountedSet alloc] initWithCapacity: 1];
  fswatcher = nil;
  fswnotifications = YES;
  [self connectFSWatcher];
    
  recyclerApp = nil;

  dtopManager = [GWDesktopManager desktopManager];
    
  NSLog(@"DEBUG: Workspace init - no_desktop setting: %d", [defaults boolForKey: @"no_desktop"]);
  if ([defaults boolForKey: @"no_desktop"] == NO)
  { 
    id item;
   
    NSLog(@"DEBUG: Workspace calling activateDesktop");
    [dtopManager activateDesktop];
    NSLog(@"DEBUG: Workspace activateDesktop returned");
    menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
    item = [menu itemWithTitle: NSLocalizedString(@"Show Desktop", @"")];
    [item setTitle: NSLocalizedString(@"Hide Desktop", @"")];

  } else if ([defaults boolForKey: @"uses_recycler"])
  { 
    [self connectRecycler];
  }  

  tshelfPBFileNum = 0;
  [self createTabbedShelf];
  if ([defaults boolForKey: @"tshelf"])
    [self showTShelf: nil];
  else
    [self hideTShelf: nil];

  prefController = [PrefController new];  
  
  history = [[History alloc] init];
  
  openWithController = [[OpenWithController alloc] init];
  runExtController = [[RunExternalController alloc] init];
  	    
  finder = [Finder finder];
  
  fiend = [[Fiend alloc] init];
  
  if ([defaults boolForKey: @"usefiend"])
    [self showFiend: nil];
  else
    [self hideFiend: nil];
    
  vwrsManager = [GWViewersManager viewersManager];
  [vwrsManager showViewers];
  
  inspector = [Inspector new];
  if ([defaults boolForKey: @"uses_inspector"]) {  
    [self showInspector: nil]; 
  }
  
  fileOpsManager = [Operation new];
  
  ddbd = nil;
  [self connectDDBd];
  
  mdextractor = nil;
  if ([defaults boolForKey: @"GSMetadataIndexingEnabled"]) {
    [self connectMDExtractor];
  }
    
  [defaults synchronize];
  terminating = NO;
  
  [self setContextHelp];
  
  storedAppinfoPath = [NSTemporaryDirectory() stringByAppendingPathComponent: @"GSLaunchedApplications"];
  RETAIN (storedAppinfoPath); 
  lockpath = [storedAppinfoPath stringByAppendingPathExtension: @"lock"];   
  storedAppinfoLock = [[NSDistributedLock alloc] initWithPath: lockpath];

  launchedApps = [NSMutableArray new];   
  activeApplication = nil;   
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
  
  NS_DURING
    {
      [NSApp setServicesProvider:self];
    }
  NS_HANDLER
    {
      NSLog(@"setServicesProvider: %@", localException);
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

  [dnc addObserver: self 
          selector: @selector(changeDefaultEditor:) 
              name: @"GWDefaultEditorChangedNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(thumbnailsDidChange:) 
              name: @"GWThumbnailsDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(removableMediaPathsDidChange:) 
              name: @"GSRemovableMediaPathsDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(reservedMountNamesDidChange:) 
              name: @"GSReservedMountNamesDidChangeNotification"
            object: nil];
 
  [dnc addObserver: self 
          selector: @selector(hideDotsFileDidChange:) 
              name: @"GSHideDotFilesDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(customDirectoryIconDidChange:) 
              name: @"GWCustomDirectoryIconDidChangeNotification"
            object: nil];

  [dnc addObserver: self 
          selector: @selector(applicationForExtensionsDidChange:) 
              name: @"GWAppForExtensionDidChangeNotification"
            object: nil];
  
  [self initializeWorkspace]; 
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  [self resetSelectedPaths];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
  // Only allow termination for logout actions
  if (!loggingout) {
    // Not a logout action, do not quit
    return NSTerminateCancel;
  }

  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  
#define TEST_CLOSE(o, w) if ((o) && ([w isVisible])) [w close]
  
  if ([fileOpsManager operationsPending]) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Wait the operations to terminate!", @""),
					        NSLocalizedString(@"Ok", @""), 
                  nil, 
                  nil);  
    return NSTerminateCancel;  
  }

  if (logoutTimer && [logoutTimer isValid]) {
    [logoutTimer invalidate];
    DESTROY (logoutTimer);
  }
  
  [wsnc removeObserver: self];
  
  fswnotifications = NO;
  terminating = YES;

  [self updateDefaults];
  
  TEST_CLOSE (prefController, [prefController myWin]);
  TEST_CLOSE (fiend, [fiend myWin]);
  TEST_CLOSE (history, [history myWin]); 
  TEST_CLOSE (tshelfWin, tshelfWin);
  TEST_CLOSE (startAppWin, [startAppWin win]);

  if (fswatcher)
    {
      NSConnection *conn = [(NSDistantObject *)fswatcher connectionForProxy];
  
      if ([conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          NS_DURING
            [fswatcher unregisterClient: (id <FSWClientProtocol>)self];  
          NS_HANDLER
            NSLog(@"[Workspace shouldTerminateApplication] unregister fswatcher: %@", [localException description]);
          NS_ENDHANDLER
          DESTROY (fswatcher);
        }
    }

  [inspector updateDefaults];

  [finder stopAllSearchs];
  
  if (recyclerApp)
    {
      NSConnection *conn;

      conn = [(NSDistantObject *)recyclerApp connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          [recyclerApp terminateApplication];
          DESTROY (recyclerApp);
        }
    }
  
  if (ddbd)
    {
      NSConnection *conn = [(NSDistantObject *)ddbd connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          DESTROY (ddbd);
        }
    }

  if (mdextractor)
    {
      NSConnection *conn = [(NSDistantObject *)mdextractor connectionForProxy];
  
      if (conn && [conn isValid])
        {
          [nc removeObserver: self
                        name: NSConnectionDidDieNotification
                      object: conn];
          DESTROY (mdextractor);
        }
  }
  		
  // This is a logout - allow termination
  return NSTerminateNow; 
}

- (NSString *)defEditor
{
  return defEditor;
}

- (NSString *)defXterm
{
  return defXterm;
}

- (NSString *)defXtermArgs
{
  return defXtermArgs;
}

- (GWViewersManager *)viewersManager
{
  return vwrsManager;
}

- (GWDesktopManager *)desktopManager
{
  return dtopManager;
}

- (History *)historyWindow
{
  return history;
}

- (id)rootViewer
{
  return nil;
}

- (void)showRootViewer
{
  id viewer = [vwrsManager rootViewer];
  
  if (viewer == nil) {
    [vwrsManager showRootViewer];
  } else {
    [viewer activate];
  }
}

- (void)rootViewerSelectFiles:(NSArray *)paths
{
  NSString *path = [[paths objectAtIndex: 0] stringByDeletingLastPathComponent];
  FSNode *parentnode = [FSNode nodeWithPath: path];
  NSArray *selection = [NSArray arrayWithArray: paths];
  id viewer = [vwrsManager rootViewer];
  id nodeView = nil;

  if ([paths count] == 1)
    {
      FSNode *node = [FSNode nodeWithPath: [paths objectAtIndex: 0]];
      
      if ([node isDirectory] && ([node isPackage] == NO))
        {
          parentnode = [FSNode nodeWithPath: [node path]];
          selection = [NSArray arrayWithObject: [node path]];
        }
    }
  
  if (viewer == nil)
    viewer = [vwrsManager showRootViewer];
  
  nodeView = [viewer nodeView];
  [nodeView showContentsOfNode: parentnode];
  [nodeView selectRepsOfPaths: selection];
  
  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)])
    [nodeView scrollSelectionToVisible];
}

- (void)newViewerAtPath:(NSString *)path
{
  FSNode *node = [FSNode nodeWithPath: path];
  int defaultType = [self defaultViewerType];

  NSLog(@"newViewerAtPath: %@ using default viewer type: %d", path, defaultType);

  if (defaultType == SPATIAL) {
    // Create spatial viewer
    [vwrsManager viewerOfType: SPATIAL
                     showType: nil
                      forNode: node
                showSelection: NO
               closeOldViewer: nil
                     forceNew: NO];
  } else {
    // Create browsing viewer (original behavior)
    [vwrsManager viewerForNode: node
                      showType: 0
                 showSelection: NO
                      forceNew: NO
                       withKey: nil];
  }
}

- (NSImage *)tshelfBackground
{
  if ([dtopManager isActive]) {
    return [dtopManager tabbedShelfBackground];
  }
  return nil;
}

- (void)tshelfBackgroundDidChange
{
  if ([tshelfWin isVisible]) {
    [[tshelfWin shelfView] setNeedsDisplay: YES];
  }  
}

- (NSString *)tshelfPBDir
{
  return tshelfPBDir;
}

- (NSString *)tshelfPBFilePath
{
  NSString *tshelfPBFileNName;

  tshelfPBFileNum++;
  if (tshelfPBFileNum >= TSHF_MAXF)
    {
      tshelfPBFileNum = 0;
    }
  
  tshelfPBFileNName = [NSString stringWithFormat: @"%i", tshelfPBFileNum];
  
  return [tshelfPBDir stringByAppendingPathComponent: tshelfPBFileNName];
}

- (void)changeDefaultEditor:(NSNotification *)notif
{
  NSString *editor = [notif object];

  if (editor) {
    ASSIGN (defEditor, editor);
  }
}

- (void)changeDefaultXTerm:(NSString *)xterm 
                 arguments:(NSString *)args
{
  ASSIGN (defXterm, xterm);
  
  if ([args length]) {
    ASSIGN (defXtermArgs, args);
  } else {
    DESTROY (defXtermArgs);
  }
}

- (void)setUseTerminalService:(BOOL)value
{
  teminalService = value;
}

- (NSString *)gworkspaceProcessName
{
  return gwProcessName;
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id entry;

  [tshelfWin saveDefaults];  
   
  if ([tshelfWin isVisible])
    {
    [defaults setBool: YES forKey: @"tshelf"];
    }
  else
    {
      [defaults setBool: NO forKey: @"tshelf"];
    }
  [defaults setObject: [NSString stringWithFormat: @"%i", tshelfPBFileNum]
               forKey: @"tshelfpbfnum"];

  if ([[prefController myWin] isVisible])
    {
      [prefController updateDefaults]; 
    }
	
  if ((fiend != nil) && ([[fiend myWin] isVisible]))
    {
      [fiend updateDefaults]; 
      [defaults setBool: YES forKey: @"usefiend"];
    }
  else
    {
      [defaults setBool: NO forKey: @"usefiend"];
    }

  [history updateDefaults];

  [defaults setObject: [fsnodeRep hiddenPaths] 
               forKey: @"hiddendirs"];

  entry = [NSNumber numberWithInt: [fsnodeRep defaultSortOrder]];
  [defaults setObject: entry forKey: @"default_sortorder"];

  [vwrsManager updateDefaults];

  [dtopManager updateDefaults];

  [finder updateDefaults];

  [defaults setObject: defEditor forKey: @"defaulteditor"];
  [defaults setObject: defXterm forKey: @"defxterm"];
  if (defXtermArgs != nil)
    {
      [defaults setObject: defXtermArgs forKey: @"defaultxtermargs"];
    }

  [defaults setBool: teminalService forKey: @"terminal_services"];
	
  [defaults setBool: [fsnodeRep usesThumbnails]  
             forKey: @"use_thumbnails"];

  entry = [NSNumber numberWithInt: maxHistoryCache];
  [defaults setObject: entry forKey: @"history_cache"];

  [defaults setBool: [[inspector win] isVisible] forKey: @"uses_inspector"];

  [defaults setBool: (recyclerApp != nil) forKey: @"uses_recycler"];

	[defaults synchronize];
}

- (void)setContextHelp
{
  NSHelpManager *manager = [NSHelpManager sharedHelpManager];
  NSString *help;

  help = @"TabbedShelf.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [tshelfWin shelfView]];

  help = @"History.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[history myWin] contentView]];

  help = @"Fiend.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[fiend myWin] contentView]];

  help = @"RunExternal.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[runExtController win] contentView]];

  help = @"Preferences.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[prefController myWin] contentView]];

  help = @"Inspector.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[inspector win] contentView]];
}

- (NSAttributedString *)contextHelpFromName:(NSString *)fileName
{
  NSString *bpath = [[NSBundle mainBundle] bundlePath];
  NSString *resPath = [bpath stringByAppendingPathComponent: @"Resources"];
  NSArray *languages = [NSUserDefaults userLanguages];
  NSUInteger i;
     
  for (i = 0; i < [languages count]; i++)
    {
      NSString *language = [languages objectAtIndex: i];
      NSString *langDir = [NSString stringWithFormat: @"%@.lproj", language];  
      NSString *helpPath = [langDir stringByAppendingPathComponent: @"Help"];
      
      helpPath = [resPath stringByAppendingPathComponent: helpPath];
      helpPath = [helpPath stringByAppendingPathComponent: fileName];
      
      if ([fm fileExistsAtPath: helpPath])
	{
	  NS_DURING
	    {
	      NSAttributedString *help = [[NSAttributedString alloc] initWithPath: helpPath
							       documentAttributes: NULL];
	      return AUTORELEASE (help);
	    }
	  NS_HANDLER
	    {
	      return nil;
	    }
	  NS_ENDHANDLER;
	}
    }
  
  return nil;
}

- (void)startXTermOnDirectory:(NSString *)dirPath
{
  if (teminalService) {
    NSPasteboard *pboard = [NSPasteboard pasteboardWithUniqueName];
    NSArray *types = [NSArray arrayWithObject: NSFilenamesPboardType];

    [pboard declareTypes: types owner: self];
    [pboard setPropertyList: [NSArray arrayWithObject: dirPath]
									  forType: NSFilenamesPboardType];
                    
    NSPerformService(@"Terminal/Open shell here", pboard);  
                      
  } else {  
	  NSTask *task = [NSTask new];

	  AUTORELEASE (task);
	  [task setCurrentDirectoryPath: dirPath];			
	  [task setLaunchPath: defXterm];

    if (defXtermArgs) {
	    NSArray *args = [defXtermArgs componentsSeparatedByString: @" "];
	    [task setArguments: args];
    }

	  [task launch];
  }
}

- (int)defaultSortType
{
  return [fsnodeRep defaultSortOrder];
}

- (void)setDefaultSortType:(int)type
{
  [fsnodeRep setDefaultSortOrder: type];
}

- (int)defaultViewerType
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id entry = [defaults objectForKey: @"defaultViewerType"];

  if (entry) {
    return [entry intValue];
  }

  // Default to browsing mode for backward compatibility
  return BROWSING;
}

- (void)setDefaultViewerType:(int)type
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject: [NSNumber numberWithInt: type] forKey: @"defaultViewerType"];
  [defaults synchronize];

  NSLog(@"Default viewer type set to: %d (%@)", type,
        (type == SPATIAL) ? @"Spatial" : @"Browsing");
}

- (void)createTabbedShelf
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id entry;
  NSString *basePath;
  BOOL isdir;

  entry = [defaults objectForKey: @"tshelfpbfnum"];
  if (entry) {
    tshelfPBFileNum = [entry intValue];
  } else {
    tshelfPBFileNum = 0;
  }      
       
  basePath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
  basePath = [basePath stringByAppendingPathComponent: @"Workspace"];

  if (([fm fileExistsAtPath: basePath isDirectory: &isdir] && isdir) == NO) {
    if ([fm createDirectoryAtPath: basePath attributes: nil] == NO) {
      NSLog(@"Can't create the Workspace directory! Quitting now.");
      [NSApp terminate: self];
    }
  }

	tshelfPBDir = [basePath stringByAppendingPathComponent: @"PBData"];

	if ([fm fileExistsAtPath: tshelfPBDir isDirectory: &isdir] == NO) {
    if ([fm createDirectoryAtPath: tshelfPBDir attributes: nil] == NO) {
      NSLog(@"Can't create the TShelf directory! Quitting now.");
      [NSApp terminate: self];
    }
	} else {
		if (isdir == NO) {
			NSLog (@"Warning - %@ is not a directory - quitting now!", tshelfPBDir);			
			[NSApp terminate: self];
		}
  }
  
  RETAIN (tshelfPBDir);

  tshelfWin = [[TShelfWin alloc] init];
}

- (TShelfWin *)tabbedShelf
{
  return tshelfWin;
}

- (StartAppWin *)startAppWin
{
  return startAppWin;
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)anItem
{	
  SEL action = [anItem action];

  if (sel_isEqual(action, @selector(showRecycler:))) {
    return (([dtopManager isActive] == NO) || ([dtopManager dockActive] == NO));
  
  } else if (sel_isEqual(action, @selector(emptyRecycler:))) {
    return ([trashContents count] != 0);
  } else if (sel_isEqual(action, @selector(removeTShelfTab:))
              || sel_isEqual(action, @selector(renameTShelfTab:))
                      || sel_isEqual(action, @selector(addTShelfTab:))) {
    return [tshelfWin isVisible];

  } else if (sel_isEqual(action, @selector(activateContextHelp:))) {
    return ([NSHelpManager isContextHelpModeActive] == NO);

  } else if (sel_isEqual(action, @selector(logout:))) {
    return !loggingout;
    
  } else if (sel_isEqual(action, @selector(cut:))
                || sel_isEqual(action, @selector(copy:))
                  || sel_isEqual(action, @selector(paste:))) {
    NSWindow *kwin = [NSApp keyWindow];

    if (kwin && [kwin isKindOfClass: [TShelfWin class]]) {
      TShelfViewItem *item = [[tshelfWin shelfView] selectedTabItem];

      if (item) {
        TShelfIconsView *iview = (TShelfIconsView *)[item view];

        if ([iview iconsType] == DATA_TAB) {
          if (sel_isEqual(action, @selector(paste:))) {
            return YES;
          } else {
            return [iview hasSelectedIcon];
          }
        } else {
          return NO;
        }
      } else {
        return NO;
      }               
    }
  }
  
  return YES;
}
           
- (void)fileSystemWillChange:(NSNotification *)notif
{
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  
  if (info) { 
    CREATE_AUTORELEASE_POOL(arp);   
    NSString *source = [info objectForKey: @"source"];
    NSString *destination = [info objectForKey: @"destination"];
  
    if ([source isEqual: trashPath] || [destination isEqual: trashPath]) {    
      [self _updateTrashContents];
    }
    
    if (ddbd != nil) {
      [ddbd fileSystemDidChange: [NSArchiver archivedDataWithRootObject: info]];
    }
    
    RELEASE (arp);
  } 
}

- (void)setSelectedPaths:(NSArray *)paths
{
 
  if (paths && ([selectedPaths isEqualToArray: paths] == NO))
    {
      NSUInteger i;
      NSMutableArray *onlyDirPaths;
      NSFileManager *fileMgr;

      ASSIGN (selectedPaths, paths);
    
      if ([[inspector win] isVisible])
        {
          [inspector setCurrentSelection: paths];
        }
      
      /* we extract from the selection only valid directories */
      onlyDirPaths = [[NSMutableArray arrayWithCapacity:1] retain];
      fileMgr = [NSFileManager defaultManager];
      for (i = 0; i < [paths count]; i++)
        {
          NSString *p;
          BOOL isDir;
          p = [paths objectAtIndex:i];
          if([fileMgr fileExistsAtPath:p isDirectory:&isDir])
            if (isDir)
              [onlyDirPaths addObject:p];
        }
      if ([onlyDirPaths count] > 0)
        [finder setCurrentSelection: onlyDirPaths];
      [onlyDirPaths release];
    
      [[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWCurrentSelectionChangedNotification"
                                               object: nil];      
    }
}

- (void)resetSelectedPaths
{
  if (selectedPaths == nil) {
    return;
  }
  
  if ([[inspector win] isVisible]) {
    [inspector setCurrentSelection: selectedPaths];
  }
				
  [[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWCurrentSelectionChangedNotification"
	 								        object: nil];    
}

- (NSArray *)selectedPaths
{
  return selectedPaths;
}

- (void)openSelectedPaths:(NSArray *)paths newViewer:(BOOL)newv
{
  NSUInteger count = [paths count];
  NSUInteger i;
  
  [self setSelectedPaths: paths];      

  if (count > MAX_FILES_TO_OPEN_DIALOG) {
    NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
    NSString *msg2 = NSLocalizedString(@"items?", @"");
  
    if (NSRunAlertPanel(nil,
                        [NSString stringWithFormat: @"%@ %lu %@", msg1, (unsigned long)count, msg2],
                NSLocalizedString(@"Cancel", @""),
                NSLocalizedString(@"Yes", @""),
                nil)) {
      return;
    }
  }
  
  for (i = 0; i < count; i++) {
    NSString *apath = [paths objectAtIndex: i];
    
    if ([fm fileExistsAtPath: apath]) {
      NSString *defApp = nil, *type = nil;

      NS_DURING
        {
	  [ws getInfoForFile: apath application: &defApp type: &type];     

	  if (type != nil)
	    {
	      if ((type == NSDirectoryFileType) || (type == NSFilesystemFileType))
		{
		  if (newv)
		    [self newViewerAtPath: apath];    
		}
	      else if ((type == NSPlainFileType) || ([type isEqual: NSShellCommandFileType]))
		{
		  [self openFile: apath];
		}
	      else if (type == NSApplicationFileType)
		{
		  [ws launchApplication: apath];
		}
	    }
        }
      NS_HANDLER
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""), 
              [NSString stringWithFormat: @"%@ %@!", 
               NSLocalizedString(@"Can't open ", @""), [apath lastPathComponent]],
                                            NSLocalizedString(@"OK", @""), 
                                            nil, 
                                            nil);                                     
        }
      NS_ENDHANDLER
    }
  }
}

- (void)openSelectedPathsWith
{
  BOOL canopen = YES;
  NSUInteger i;

  for (i = 0; i < [selectedPaths count]; i++) {
    FSNode *node = [FSNode nodeWithPath: [selectedPaths objectAtIndex: i]];

    if (([node isPlain] == NO) 
          && (([node isPackage] == NO) || [node isApplication])) {
      canopen = NO;
      break;
    }
  }
  
  if (canopen) {
    [openWithController activate];
  }
}

- (BOOL)openFile:(NSString *)fullPath
{
  NSString *appName = nil;
  NSString *type = nil;
  BOOL success;
  NSURL *aURL;

  aURL = nil;
  [ws getInfoForFile: fullPath application: &appName type: &type];

  if (type == NSDirectoryFileType)
    {
      [self newViewerAtPath: fullPath];
      return YES;
    }
  else if (type == NSPlainFileType)
    {
      if ([[fullPath pathExtension] isEqualToString: @"webloc"])
	{
	  NSDictionary *weblocDict;
	  NSString *urlString;

	  weblocDict = [NSDictionary dictionaryWithContentsOfFile: fullPath];
	  urlString = [weblocDict objectForKey:@"URL"];
	  aURL = [NSURL URLWithString: urlString];
        }
    }
  
  NS_DURING
    {
      if (aURL == nil)
	success = [ws openFile: fullPath withApplication: appName];
      else
	success = [ws openURL: aURL];
    }
  NS_HANDLER
    {
      NSRunAlertPanel(NSLocalizedString(@"error", @""), 
		      [NSString stringWithFormat: @"%@ %@!", 
				NSLocalizedString(@"Can't open ", @""), [fullPath lastPathComponent]],
		      NSLocalizedString(@"OK", @""), 
		      nil, 
		      nil);                                     
      success = NO;
    }
  NS_ENDHANDLER  
  
    return success;  
}

- (BOOL)application:(NSApplication *)theApplication 
           openFile:(NSString *)filename
{
  BOOL isDir;

  if ([filename isAbsolutePath] 
                    && [fm fileExistsAtPath: filename isDirectory: &isDir]) {
    NSString *type = nil;
    NSString *appName;

    [ws getInfoForFile: filename application: &appName type: &type];
    if (isDir) {
      if ([[filename pathExtension] isEqual: @"lsf"]) {
        return [finder openLiveSearchFolderAtPath: filename];
      } else if (type == NSDirectoryFileType) {
        [self newViewerAtPath: filename];
        return YES;
      }
    }

    // it is a direcotry or a bundle, which is a NSFilePlainType
    [self openFile: filename];
    return YES;
  } 

  return NO;
}

- (NSArray *)getSelectedPaths
{
  return selectedPaths;
}

- (void)showPasteboardData:(NSData *)data 
                    ofType:(NSString *)type
                  typeIcon:(NSImage *)icon
{
  if ([[inspector win] isVisible]) {
    if ([inspector canDisplayDataOfType: type]) {
      [inspector showData: data ofType: type];
    }
  }
}

- (void)newObjectAtPath:(NSString *)basePath 
            isDirectory:(BOOL)directory
{
  NSString *fullPath;
  NSString *fileName;
  NSString *operation;
  NSMutableDictionary *notifObj;  
  unsigned suff;
    
	if ([self verifyFileAtPath: basePath] == NO) {
		return;
	}
	
	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  if (directory) {
    fileName = @"NewFolder";
    operation = @"WorkspaceCreateDirOperation";
  } else {
    fileName = @"NewFile";
    operation = @"WorkspaceCreateFileOperation";
  }

  fullPath = [basePath stringByAppendingPathComponent: fileName];
  	
  if ([fm fileExistsAtPath: fullPath]) {    
    suff = 1;
    while (1) {    
      NSString *s = [fileName stringByAppendingFormat: @"%i", suff];
      fullPath = [basePath stringByAppendingPathComponent: s];
      if ([fm fileExistsAtPath: fullPath] == NO) {
        fileName = [NSString stringWithString: s];
        break;      
      }      
      suff++;
    }     
  }

  notifObj = [NSMutableDictionary dictionaryWithCapacity: 1];		
  [notifObj setObject: operation forKey: @"operation"];	
  [notifObj setObject: basePath forKey: @"source"];	
  [notifObj setObject: basePath forKey: @"destination"];	
  [notifObj setObject: [NSArray arrayWithObject: fileName] forKey: @"files"];	

  [self performFileOperation: notifObj];
}

- (void)duplicateFiles
{
  NSString *basePath;
  NSMutableArray *files;
  NSInteger tag;
  NSUInteger i;

  basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];
  basePath = [basePath stringByDeletingLastPathComponent];

	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  files = [NSMutableArray array];
  for (i = 0; i < [selectedPaths count]; i++) {
    [files addObject: [[selectedPaths objectAtIndex: i] lastPathComponent]];
  }

  [self performFileOperation: NSWorkspaceDuplicateOperation 
              source: basePath destination: basePath files: files tag: &tag];
}

- (void)deleteFiles
{
  NSString *basePath;
  NSMutableArray *files;
  NSInteger tag;
  NSUInteger i;

  basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];
  basePath = [basePath stringByDeletingLastPathComponent];

	if ([fm isWritableFileAtPath: basePath] == NO) {
		NSString *err = NSLocalizedString(@"Error", @"");
		NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
		NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
		return;
	}

  files = [NSMutableArray array];
  for (i = 0; i < [selectedPaths count]; i++) {
    [files addObject: [[selectedPaths objectAtIndex: i] lastPathComponent]];
  }

  [self performFileOperation: NSWorkspaceDestroyOperation 
              source: basePath destination: basePath files: files tag: &tag];
}

- (void)moveToTrash
{
  NSArray *vpaths = [ws mountedLocalVolumePaths];
  NSMutableArray *umountPaths = [NSMutableArray array];
  NSMutableArray *files = [NSMutableArray array];
  NSUInteger i;
  NSInteger tag;

  for (i = 0; i < [selectedPaths count]; i++) {
    NSString *path = [selectedPaths objectAtIndex: i];

    if ([vpaths containsObject: path]) {
      [umountPaths addObject: path];
    } else {
      [files addObject: [path lastPathComponent]];
    }
  }

  for (i = 0; i < [umountPaths count]; i++) {
    [ws unmountAndEjectDeviceAtPath: [umountPaths objectAtIndex: i]];
  }

  if ([files count])
    {
      NSString *basePath = [NSString stringWithString: [selectedPaths objectAtIndex: 0]];

      basePath = [basePath stringByDeletingLastPathComponent];

      if ([fm isWritableFileAtPath: basePath] == NO)
        {
          NSString *err = NSLocalizedString(@"Error", @"");
          NSString *msg = NSLocalizedString(@"You do not have write permission\nfor", @"");
          NSString *buttstr = NSLocalizedString(@"Continue", @"");
          NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, basePath], buttstr, nil, nil);   
          return;
        }

      [self performFileOperation: NSWorkspaceRecycleOperation
                          source: basePath destination: trashPath 
                           files: files tag: &tag];
    }
}

- (BOOL)verifyFileAtPath:(NSString *)path
{
  if ([fm fileExistsAtPath: path] == NO)
    {
      NSString *err = NSLocalizedString(@"Error", @"");
      NSString *msg = NSLocalizedString(@": no such file or directory!", @"");
      NSString *buttstr = NSLocalizedString(@"Continue", @"");
      NSMutableDictionary *notifObj = [NSMutableDictionary dictionaryWithCapacity: 1];		
      NSString *basePath = [path stringByDeletingLastPathComponent];
		
      NSRunAlertPanel(err, [NSString stringWithFormat: @"%@%@", path, msg], buttstr, nil, nil);   

      [notifObj setObject: NSWorkspaceDestroyOperation forKey: @"operation"];	
      [notifObj setObject: basePath forKey: @"source"];	
      [notifObj setObject: basePath forKey: @"destination"];	
      [notifObj setObject: [NSArray arrayWithObjects: path, nil] forKey: @"files"];	

      [[NSNotificationCenter defaultCenter]
 					 postNotificationName: @"GWFileSystemWillChangeNotification"
						       object: notifObj];
      [[NSNotificationCenter defaultCenter]
 				  postNotificationName: @"GWFileSystemDidChangeNotification"
						object: notifObj];
      return NO;
    }
	
  return YES;
}

- (void)setUsesThumbnails:(BOOL)value
{  
  if ([fsnodeRep usesThumbnails] == value) {
    return;
  }
  
  [fsnodeRep setUseThumbnails: value];
  
  [vwrsManager thumbnailsDidChangeInPaths: nil];
  [dtopManager thumbnailsDidChangeInPaths: nil];
  
  if ([tshelfWin isVisible]) {
    [tshelfWin updateIcons]; 
	}
}

- (void)thumbnailsDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSArray *deleted = [info objectForKey: @"deleted"];	
  NSArray *created = [info objectForKey: @"created"];	
  NSMutableArray *tmbdirs = [NSMutableArray array];
  NSUInteger i;

  [fsnodeRep thumbnailsDidChange: info];

  if ([fsnodeRep usesThumbnails] == NO)
    return;

  NSString *thumbnailDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];

  thumbnailDir = [thumbnailDir stringByAppendingPathComponent: @"Thumbnails"];
  
  if (deleted && [deleted count])
    {
      for (i = 0; i < [deleted count]; i++) {
        NSString *path = [deleted objectAtIndex: i];
        NSString *dir = [path stringByDeletingLastPathComponent];

        if ([tmbdirs containsObject: dir] == NO) {
          [tmbdirs addObject: dir];
        }
      }

      [vwrsManager thumbnailsDidChangeInPaths: tmbdirs];
      [dtopManager thumbnailsDidChangeInPaths: tmbdirs];

      if ([tshelfWin isVisible])
        [tshelfWin updateIcons]; 

      [tmbdirs removeAllObjects];
    }

    if (created && [created count]) {
      NSString *dictName = @"thumbnails.plist";
      NSString *dictPath = [thumbnailDir stringByAppendingPathComponent: dictName];
      
      if ([fm fileExistsAtPath: dictPath]) {
        NSDictionary *tdict = [NSDictionary dictionaryWithContentsOfFile: dictPath];

        for (i = 0; i < [created count]; i++) {
          NSString *key = [created objectAtIndex: i];
          NSString *dir = [key stringByDeletingLastPathComponent];
          NSString *tumbname = [tdict objectForKey: key];
          NSString *tumbpath = [thumbnailDir stringByAppendingPathComponent: tumbname]; 

          if ([fm fileExistsAtPath: tumbpath]) {        
            if ([tmbdirs containsObject: dir] == NO) {
              [tmbdirs addObject: dir];
            }
          }
        }
      }
      
      [vwrsManager thumbnailsDidChangeInPaths: tmbdirs];
      [dtopManager thumbnailsDidChangeInPaths: tmbdirs];
      
      if ([tshelfWin isVisible]) {
        [tshelfWin updateIcons]; 
		  }
    }
}

- (void)removableMediaPathsDidChange:(NSNotification *)notif
{
  NSArray *removables;

  removables = [[[NSUserDefaults standardUserDefaults] persistentDomainForName: NSGlobalDomain] objectForKey: @"GSRemovableMediaPaths"];

  [fsnodeRep setVolumes: removables];
  [dtopManager removableMediaPathsDidChange];
}

- (void)reservedMountNamesDidChange:(NSNotification *)notif
{

}

- (void)hideDotsFileDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  BOOL hide = [[info objectForKey: @"hide"] boolValue];
  
  [fsnodeRep setHideSysFiles: hide];
  [vwrsManager hideDotsFileDidChange: hide];
  [dtopManager hideDotsFileDidChange: hide];

  [tshelfWin checkIconsAfterDotsFilesChange];
  
  if (fiend != nil) {
    [fiend checkIconsAfterDotsFilesChange];
  }
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  [vwrsManager hiddenFilesDidChange: paths];
  [dtopManager hiddenFilesDidChange: paths];
  [tshelfWin checkIconsAfterHidingOfPaths: paths]; 

  if (fiend != nil) {
    [fiend checkIconsAfterHidingOfPaths: paths];
  }
}

- (void)customDirectoryIconDidChange:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *dirpath = [info objectForKey: @"path"];
  NSString *imgpath = [info objectForKey: @"icon_path"];  
  NSArray *paths;	

  [fsnodeRep removeCachedIconsForKey: imgpath];
  
  if ([dirpath isEqual: path_separator()] == NO) {
    dirpath = [dirpath stringByDeletingLastPathComponent];
  }
  
  paths = [NSArray arrayWithObject: dirpath];
  
  [vwrsManager thumbnailsDidChangeInPaths: paths];
  [dtopManager thumbnailsDidChangeInPaths: paths];

  if ([tshelfWin isVisible]) {
    [tshelfWin updateIcons]; 
	}
}

- (void)applicationForExtensionsDidChange:(NSNotification *)notif
{
  NSDictionary *changedInfo = [notif userInfo];
  NSString *app = [changedInfo objectForKey: @"app"];
  NSArray *extensions = [changedInfo objectForKey: @"exts"];
  NSUInteger i;

  for (i = 0; i < [extensions count]; i++) {
    [[NSWorkspace sharedWorkspace] setBestApp: app
                                       inRole: nil 
                                 forExtension: [extensions objectAtIndex: i]];  
  }
}

- (int)maxHistoryCache
{
  return maxHistoryCache;
}

- (void)setMaxHistoryCache:(int)value
{
  maxHistoryCache = value;
}

- (void)connectFSWatcher
{
  if (fswatcher == nil)
  {
    fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher" 
                                                                  host: @""];

    if (fswatcher == nil)
    {
      NSString *cmd;
      NSMutableArray *arguments;
      cmd = [NSTask launchPathForTool: @"fswatcher"];    
      arguments = [NSMutableArray arrayWithCapacity:2];
      [arguments addObject:@"--daemon"];
      [arguments addObject:@"--auto"];  
      [NSTask launchedTaskWithLaunchPath: cmd arguments: arguments];

      NSDictionary *info = [NSDictionary dictionaryWithObject:[NSDate dateWithTimeIntervalSinceNow: 6.0]
                                                       forKey:@"deadline"];
      [NSTimer scheduledTimerWithTimeInterval:0.2
                                       target:self
                                     selector:@selector(_probeFSWatcherTimer:)
                                     userInfo:info
                                      repeats:YES];
    }
    
    if (fswatcher)
    {
      RETAIN (fswatcher);
      [fswatcher setProtocolForProxy: @protocol(FSWatcherProtocol)];
    
	    [[NSNotificationCenter defaultCenter] addObserver: self
	                   selector: @selector(fswatcherConnectionDidDie:)
		                     name: NSConnectionDidDieNotification
		                   object: [fswatcher connectionForProxy]];
                       
	    [fswatcher registerClient: (id <FSWClientProtocol>)self 
                isGlobalWatcher: NO];
    } else {
      fswnotifications = NO;
      NSLog(@"Workspace: unable to contact fswatcher; notifications disabled");
    }
  }
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  NSAssert(connection == [fswatcher connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (fswatcher);
  fswatcher = nil;

  if (NSRunAlertPanel(nil,
                    NSLocalizedString(@"The fswatcher connection died.\nDo you want to restart it?", @""),
                    NSLocalizedString(@"Yes", @""),
                    NSLocalizedString(@"No", @""),
                    nil)) {
    [self connectFSWatcher]; 
    
    if (fswatcher != nil) {
      NSEnumerator *enumerator = [watchedPaths objectEnumerator];
      NSString *path;
      
      while ((path = [enumerator nextObject])) {
        unsigned count = [watchedPaths countForObject: path];
        unsigned i;
      
        for (i = 0; i < count; i++) {
          [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
        }
      }
    }
                   
  } else {
    fswnotifications = NO;
    NSRunAlertPanel(nil,
                    NSLocalizedString(@"fswatcher notifications disabled!", @""),
                    NSLocalizedString(@"Ok", @""),
                    nil, 
                    nil);  
  }
}

- (oneway void)watchedPathDidChange:(NSData *)dirinfo
{
  CREATE_AUTORELEASE_POOL(arp);
  NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
  NSString *event = [info objectForKey: @"event"];

  if ([event isEqual: @"GWFileDeletedInWatchedDirectory"]
            || [event isEqual: @"GWFileCreatedInWatchedDirectory"]) {
    NSString *path = [info objectForKey: @"path"];

    if ([path isEqual: trashPath]) {
      [self _updateTrashContents];
    }
  }
  
	[[NSNotificationCenter defaultCenter]
 				 postNotificationName: @"GWFileWatcherFileDidChangeNotification"
	 								     object: info];  
  RELEASE (arp);                       
}

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo
{
}

- (void)connectRecycler
{
  if (recyclerApp == nil)
    {
      recyclerApp = [NSConnection rootProxyForConnectionWithRegisteredName: @"Recycler" 
                                                                      host: @""];
      
      if (recyclerApp == nil)
        {
          [ws launchApplication: @"Recycler"];

          NSDictionary *info = [NSDictionary dictionaryWithObject:[NSDate dateWithTimeIntervalSinceNow: 8.0]
                                                           forKey:@"deadline"];
          [NSTimer scheduledTimerWithTimeInterval:0.2
                                           target:self
                                         selector:@selector(_probeRecyclerTimer:)
                                         userInfo:info
                                          repeats:YES];
        }
    
      if (recyclerApp)
        {
          NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
          id item = [menu itemWithTitle: NSLocalizedString(@"Show Recycler", @"")];

          if (item != nil) {
            [item setTitle: NSLocalizedString(@"Hide Recycler", @"")];
          }
    
          RETAIN (recyclerApp);
          [recyclerApp setProtocolForProxy: @protocol(RecyclerAppProtocol)];
    
          [[NSNotificationCenter defaultCenter] addObserver: self
                                                   selector: @selector(recyclerConnectionDidDie:)
                                                       name: NSConnectionDidDieNotification
                                                     object: [recyclerApp connectionForProxy]];
        } 
      else
        {
          NSLog(@"Workspace: unable to contact Recycler");
        }
    }
}

- (void)recyclerConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  id item = [menu itemWithTitle: NSLocalizedString(@"Hide Recycler", @"")];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  NSAssert(connection == [recyclerApp connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (recyclerApp);
  recyclerApp = nil;

  if (item != nil) {
    [item setTitle: NSLocalizedString(@"Show Recycler", @"")];
  }
    
  if (recyclerCanQuit == NO) {  
    if (NSRunAlertPanel(nil,
                      NSLocalizedString(@"The Recycler connection died.\nDo you want to restart it?", @""),
                      NSLocalizedString(@"Yes", @""),
                      NSLocalizedString(@"No", @""),
                      nil)) {
      [self connectRecycler]; 
    }    
  }
}

- (void)connectDDBd
{
  if (ddbd == nil)
    {
      ddbd = [NSConnection rootProxyForConnectionWithRegisteredName: @"ddbd" 
							       host: @""];

      if (ddbd == nil)
	{
    NSString *cmd;
    NSMutableArray *arguments;
    cmd = [NSTask launchPathForTool: @"ddbd"];    

    arguments = [NSMutableArray arrayWithCapacity:2];
    [arguments addObject:@"--daemon"];
    [arguments addObject:@"--auto"];  
    [NSTask launchedTaskWithLaunchPath: cmd arguments: arguments];

    NSDictionary *info = [NSDictionary dictionaryWithObject:[NSDate dateWithTimeIntervalSinceNow: 6.0]
                                                     forKey:@"deadline"];
    [NSTimer scheduledTimerWithTimeInterval:0.2
                                     target:self
                                   selector:@selector(_probeDDBdTimer:)
                                   userInfo:info
                                    repeats:YES];
	}
    
      if (ddbd)
	{
	  RETAIN (ddbd);
	  [ddbd setProtocolForProxy: @protocol(DDBdProtocol)];
    
	  [[NSNotificationCenter defaultCenter] addObserver: self
						   selector: @selector(ddbdConnectionDidDie:)
						       name: NSConnectionDidDieNotification
						     object: [ddbd connectionForProxy]];
	}
      else
	{
    NSLog(@"Workspace: unable to contact ddbd");
	}
    }
}  
  
- (void)ddbdConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
						  name: NSConnectionDidDieNotification
						object: connection];

  NSAssert(connection == [ddbd connectionForProxy],
		                                  NSInternalInconsistencyException);
  RELEASE (ddbd);
  ddbd = nil;
  
  NSRunAlertPanel(nil,
                  NSLocalizedString(@"ddbd connection died.", @""),
                  NSLocalizedString(@"Ok", @""),
                  nil,
                  nil);                
}

- (BOOL)ddbdactive
{
  return ((terminating == NO) && (ddbd != nil));
}

- (void)ddbdInsertPath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd insertPath: path];
  }
}

- (void)ddbdRemovePath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd removePath: path];
  }
}

- (NSString *)ddbdGetAnnotationsForPath:(NSString *)path
{
  if (ddbd != nil) {
    return [ddbd annotationsForPath: path];
  }
  
  return nil;
}

- (void)ddbdSetAnnotations:(NSString *)annotations
                   forPath:(NSString *)path
{
  if (ddbd != nil) {
    [ddbd setAnnotations: annotations forPath: path];
  }
}

- (void)connectMDExtractor
{
  if (mdextractor == nil) {
    mdextractor = [NSConnection rootProxyForConnectionWithRegisteredName: @"mdextractor" 
                                                                    host: @""];

    if (mdextractor == nil) {
	    NSString *cmd;
      cmd = [NSTask launchPathForTool: @"mdextractor"];    
      [NSTask launchedTaskWithLaunchPath: cmd arguments: nil];

      NSDictionary *info = [NSDictionary dictionaryWithObject:[NSDate dateWithTimeIntervalSinceNow: 8.0]
                                                       forKey:@"deadline"];
      [NSTimer scheduledTimerWithTimeInterval:0.2
                                       target:self
                                     selector:@selector(_probeMDExtractorTimer:)
                                     userInfo:info
                                      repeats:YES];
    }
    
    if (mdextractor) {
      [mdextractor setProtocolForProxy: @protocol(MDExtractorProtocol)];
      RETAIN (mdextractor);
    
	    [[NSNotificationCenter defaultCenter] addObserver: self
	                   selector: @selector(mdextractorConnectionDidDie:)
		                     name: NSConnectionDidDieNotification
		                   object: [mdextractor connectionForProxy]];
    } else {
      NSLog(@"Workspace: unable to contact mdextractor");
    }
  }
}

// MARK: - Async probe timers

- (void)_probeFSWatcherTimer:(NSTimer *)timer
{
  if (fswatcher) {
    [timer invalidate];
    return;
  }
  NSDate *deadline = [[timer userInfo] objectForKey:@"deadline"];
  fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName:@"fswatcher" host:@""];
  if (fswatcher) {
    [timer invalidate];
    RETAIN(fswatcher);
    [fswatcher setProtocolForProxy:@protocol(FSWatcherProtocol)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fswatcherConnectionDidDie:)
                                                 name:NSConnectionDidDieNotification
                                               object:[fswatcher connectionForProxy]];
    [fswatcher registerClient:(id <FSWClientProtocol>)self isGlobalWatcher:NO];
    return;
  }
  if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
    [timer invalidate];
    fswnotifications = NO;
    NSLog(@"Workspace: fswatcher did not respond; notifications disabled");
  }
}

- (void)_probeRecyclerTimer:(NSTimer *)timer
{
  if (recyclerApp) {
    [timer invalidate];
    return;
  }
  NSDate *deadline = [[timer userInfo] objectForKey:@"deadline"];
  recyclerApp = [NSConnection rootProxyForConnectionWithRegisteredName:@"Recycler" host:@""];
  if (recyclerApp) {
    [timer invalidate];
    NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
    id item = [menu itemWithTitle: NSLocalizedString(@"Show Recycler", @"")];
    if (item != nil) {
      [item setTitle: NSLocalizedString(@"Hide Recycler", @"")];
    }
    RETAIN(recyclerApp);
    [recyclerApp setProtocolForProxy:@protocol(RecyclerAppProtocol)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recyclerConnectionDidDie:)
                                                 name:NSConnectionDidDieNotification
                                               object:[recyclerApp connectionForProxy]];
    return;
  }
  if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
    [timer invalidate];
    NSLog(@"Workspace: Recycler did not respond");
  }
}

- (void)_probeDDBdTimer:(NSTimer *)timer
{
  if (ddbd) {
    [timer invalidate];
    return;
  }
  NSDate *deadline = [[timer userInfo] objectForKey:@"deadline"];
  ddbd = [NSConnection rootProxyForConnectionWithRegisteredName:@"ddbd" host:@""];
  if (ddbd) {
    [timer invalidate];
    RETAIN(ddbd);
    [ddbd setProtocolForProxy:@protocol(DDBdProtocol)];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ddbdConnectionDidDie:)
                                                 name:NSConnectionDidDieNotification
                                               object:[ddbd connectionForProxy]];
    return;
  }
  if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
    [timer invalidate];
    NSLog(@"Workspace: ddbd did not respond");
  }
}

- (void)_probeMDExtractorTimer:(NSTimer *)timer
{
  if (mdextractor) {
    [timer invalidate];
    return;
  }
  NSDate *deadline = [[timer userInfo] objectForKey:@"deadline"];
  mdextractor = [NSConnection rootProxyForConnectionWithRegisteredName:@"mdextractor" host:@""];
  if (mdextractor) {
    [timer invalidate];
    [mdextractor setProtocolForProxy:@protocol(MDExtractorProtocol)];
    RETAIN(mdextractor);
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(mdextractorConnectionDidDie:)
                                                 name:NSConnectionDidDieNotification
                                               object:[mdextractor connectionForProxy]];
    return;
  }
  if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
    [timer invalidate];
    NSLog(@"Workspace: mdextractor did not respond");
  }
}

- (void)mdextractorConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
						  name: NSConnectionDidDieNotification
						object: connection];

  NSAssert(connection == [mdextractor connectionForProxy],
	   NSInternalInconsistencyException);
  RELEASE (mdextractor);
  mdextractor = nil;

  if (NSRunAlertPanel(nil,
		      NSLocalizedString(@"The mdextractor connection died.\nDo you want to restart it?", @""),
		      NSLocalizedString(@"Yes", @""),
		      NSLocalizedString(@"No", @""),
		      nil))
       {
      [self connectMDExtractor];
    }
}

- (void)slideImage:(NSImage *)image 
	      from:(NSPoint)fromPoint
		to:(NSPoint)toPoint
{
         [[NSWorkspace sharedWorkspace] slideImage: image from: fromPoint to: toPoint];
}


//
// NSServicesRequests protocol
//
- (id)validRequestorForSendType:(NSString *)sendType
                     returnType:(NSString *)returnType
{	
  BOOL sendOK = ((sendType == nil) || ([sendType isEqual: NSFilenamesPboardType]));
  BOOL returnOK = ((returnType == nil)
		   || ([returnType isEqual: NSFilenamesPboardType]
		       && (selectedPaths != nil)));

  if (sendOK && returnOK)
    {
      return self;
    }
  return nil;
}
	
- (BOOL)readSelectionFromPasteboard:(NSPasteboard *)pboard
{
  return ([[pboard types] indexOfObject: NSFilenamesPboardType] != NSNotFound);
}

- (BOOL)writeSelectionToPasteboard:(NSPasteboard *)pboard
                             types:(NSArray *)types
{
	if ([types containsObject: NSFilenamesPboardType]) {
		NSArray *typesDeclared = [NSArray arrayWithObject: NSFilenamesPboardType];

		[pboard declareTypes: typesDeclared owner: self];
		
		return [pboard setPropertyList: selectedPaths 
									  		   forType: NSFilenamesPboardType];
	}
	
	return NO;
}

//
// Workspace service
//

- (void)openInWorkspace:(NSPasteboard *)pboard
	       userData:(NSString *)userData
		  error:(NSString **)error
{
  NSArray *types = [pboard types];
  if ([types containsObject: NSStringPboardType])
    {
      NSString *path = [pboard stringForType: NSStringPboardType];
      path = [path stringByTrimmingCharactersInSet:
		     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      [self openSelectedPaths: [NSArray arrayWithObject: path] newViewer: YES];
    }
}

//
// Menu Operations
//
- (void)logout:(id)sender
{
  [self startLogout];
}

- (void)showInfo:(id)sender
{
  
  [NSApp orderFrontStandardInfoPanel: self];
}

- (void)showPreferences:(id)sender
{
  [prefController activate]; 
}

- (void)activateContextHelp:(id)sender
{
  if ([NSHelpManager isContextHelpModeActive] == NO) {
    [NSHelpManager setContextHelpModeActive: YES];
  }
}

- (void)showViewer:(id)sender
{
  [vwrsManager showRootViewer];
}

- (void)showHistory:(id)sender
{
  [history activate];
}

- (void)showInspector:(id)sender
{
  [inspector activate];
  [inspector setCurrentSelection: selectedPaths];
}

- (void)showAttributesInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showAttributes];
}

- (void)showContentsInspector:(id)sender
{
  [self showInspector: nil];  
  [inspector showContents];
}

- (void)showToolsInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showTools];
}

- (void)showAnnotationsInspector:(id)sender
{
  [self showInspector: nil]; 
  [inspector showAnnotations];
}

- (void)showRecycler:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  id item;

  if (recyclerApp == nil)
    {
      recyclerCanQuit = NO; 
      [self connectRecycler];
      item = [menu itemWithTitle: NSLocalizedString(@"Show Recycler", @"")];
      [item setTitle: NSLocalizedString(@"Hide Recycler", @"")];
    }
  else
    {
      recyclerCanQuit = YES;
      [recyclerApp terminateApplication];
      item = [menu itemWithTitle: NSLocalizedString(@"Hide Recycler", @"")];
      [item setTitle: NSLocalizedString(@"Show Recycler", @"")];
    }
}

- (void)showFinder:(id)sender
{
  [finder activate];   
}

- (void)showFiend:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Fiend", @"")] submenu];

  while (1)
    {
      if ([menu numberOfItems] == 0)
        break;

      [menu removeItemAtIndex: 0];
    }

  [menu addItemWithTitle: NSLocalizedString(@"Hide Fiend", @"")
                  action: @selector(hideFiend:) keyEquivalent: @""];
  [menu addItemWithTitle: NSLocalizedString(@"Remove Current Layer", @"")
                  action: @selector(removeFiendLayer:) keyEquivalent: @""];
  [menu addItemWithTitle: NSLocalizedString(@"Rename Current Layer", @"")
                  action: @selector(renameFiendLayer:) keyEquivalent: @""];	
  [menu addItemWithTitle: NSLocalizedString(@"Add Layer...", @"")
                  action: @selector(addFiendLayer:) keyEquivalent: @""];

  [fiend activate];
}

- (void)hideFiend:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Fiend", @"")] submenu];

  while (1)
    {
      if ([menu numberOfItems] == 0)
	{
	  break;
	}
      [menu removeItemAtIndex: 0];
    }

  [menu addItemWithTitle: NSLocalizedString(@"Show Fiend", @"")
		  action: @selector(showFiend:) keyEquivalent: @""];

  if (fiend != nil)
    {
      [fiend hide];
    }
}

- (void)addFiendLayer:(id)sender
{
  [fiend addLayer];
}

- (void)removeFiendLayer:(id)sender
{
  [fiend removeCurrentLayer];
}

- (void)renameFiendLayer:(id)sender
{
  [fiend renameCurrentLayer];
}

- (void)showTShelf:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Tabbed Shelf", @"")] submenu];

  [[menu itemAtIndex: 0] setTitle: NSLocalizedString(@"Hide Tabbed Shelf", @"")];
  [[menu itemAtIndex: 0] setAction: @selector(hideTShelf:)];

  [tshelfWin activate];
}

- (void)hideTShelf:(id)sender
{
  NSMenu *menu = [[[NSApp mainMenu] itemWithTitle: NSLocalizedString(@"Tools", @"")] submenu];
  menu = [[menu itemWithTitle: NSLocalizedString(@"Tabbed Shelf", @"")] submenu];

  [[menu itemAtIndex: 0] setTitle: NSLocalizedString(@"Show Tabbed Shelf", @"")];
  [[menu itemAtIndex: 0] setAction: @selector(showTShelf:)];

  if ([tshelfWin isVisible])
    {
      [tshelfWin deactivate];
    }
}

- (void)selectSpecialTShelfTab:(id)sender
{
  if ([tshelfWin isVisible] == NO)
    {
      [tshelfWin activate];
    }
  [[tshelfWin shelfView] selectLastItem];
}

- (void)addTShelfTab:(id)sender
{
  [tshelfWin addTab]; 
}

- (void)removeTShelfTab:(id)sender
{
  [tshelfWin removeTab]; 
}

- (void)renameTShelfTab:(id)sender
{
  [tshelfWin renameTab]; 
}

- (void)cut:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin)
    {
      if ([kwin isKindOfClass: [TShelfWin class]])
	{
	  TShelfViewItem *item = [[tshelfWin shelfView] selectedTabItem];

	  if (item)
	    {
	      TShelfIconsView *iview = (TShelfIconsView *)[item view];
	      [iview doCut];
	    }
	}
      else if ([vwrsManager hasViewerWithWindow: kwin]
                                  || [dtopManager hasWindow: kwin])
	{
	  id nodeView;
	  NSArray *selection;
	  NSArray *basesel;

	  if ([vwrsManager hasViewerWithWindow: kwin])
	    {
	      nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
	    }
	  else
	    {
	      nodeView = [dtopManager desktopView];
	    }

	  selection = [nodeView selectedPaths];
	  basesel = [NSArray arrayWithObject: [[nodeView baseNode] path]];

	  if ([selection count] && ([selection isEqual: basesel] == NO))
	    {
	      NSPasteboard *pb = [NSPasteboard generalPasteboard];

	      [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
			 owner: nil];

	      if ([pb setPropertyList: selection forType: NSFilenamesPboardType])
		{
		  [fileOpsManager setFilenamesCut: YES];
		}
	    }
	}
    }
}

- (void)copy:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin) {
    if ([kwin isKindOfClass: [TShelfWin class]]) {
      TShelfViewItem *item = [[tshelfWin shelfView] selectedTabItem];

      if (item) {
        TShelfIconsView *iview = (TShelfIconsView *)[item view];
        [iview doCopy];    
      }
      
    } else if ([vwrsManager hasViewerWithWindow: kwin]
                                  || [dtopManager hasWindow: kwin]) {
      id nodeView;
      NSArray *selection;
      NSArray *basesel;
      
      if ([vwrsManager hasViewerWithWindow: kwin]) {
        nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
      } else {
        nodeView = [dtopManager desktopView];
      }
    
      selection = [nodeView selectedPaths];  
      basesel = [NSArray arrayWithObject: [[nodeView baseNode] path]];
      
      if ([selection count] && ([selection isEqual: basesel] == NO)) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];

        [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
                   owner: nil];

        if ([pb setPropertyList: selection forType: NSFilenamesPboardType]) {
          [fileOpsManager setFilenamesCut: NO];
        }
      }
    }
  }
}

- (void)paste:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin) {
    if ([kwin isKindOfClass: [TShelfWin class]]) {
      TShelfViewItem *item = [[tshelfWin shelfView] selectedTabItem];

      if (item) {
        TShelfIconsView *iview = (TShelfIconsView *)[item view];
        [iview doPaste];    
      }
      
    } else if ([vwrsManager hasViewerWithWindow: kwin]
                                  || [dtopManager hasWindow: kwin]) {
      NSPasteboard *pb = [NSPasteboard generalPasteboard];

      if ([[pb types] containsObject: NSFilenamesPboardType]) {
        NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];   

        if (sourcePaths) {
          BOOL cut = [fileOpsManager filenamesWasCut];
          id nodeView;

          if ([vwrsManager hasViewerWithWindow: kwin]) {
            nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
          } else {
            nodeView = [dtopManager desktopView];
          }

          if ([nodeView validatePasteOfFilenames: sourcePaths
                                       wasCut: cut]) {
            NSMutableDictionary *opDict = [NSMutableDictionary dictionary];
            NSString *source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
            NSString *destination = [[nodeView shownNode] path];
            NSMutableArray *files = [NSMutableArray array];
            NSString *operation;
            int i;

            for (i = 0; i < [sourcePaths count]; i++) {  
              NSString *spath = [sourcePaths objectAtIndex: i];
              [files addObject: [spath lastPathComponent]];
            }  

            if (cut) {
              if ([source isEqual: trashPath]) {
                operation = @"WorkspaceRecycleOutOperation";
              } else {
		            operation = NSWorkspaceMoveOperation;
              }
            } else {
		          operation = NSWorkspaceCopyOperation;
            }

	          [opDict setObject: operation forKey: @"operation"];
	          [opDict setObject: source forKey: @"source"];
	          [opDict setObject: destination forKey: @"destination"];
	          [opDict setObject: files forKey: @"files"];

	          [self performFileOperation: opDict];	
          }
        }
      }
    }    
  }
}

- (void)runCommand:(id)sender
{
  [runExtController activate];
}

- (void)checkRemovableMedia:(id)sender
{
  [dtopManager checkNewRemovableMedia];	
}

- (void)emptyRecycler:(id)sender
{
  CREATE_AUTORELEASE_POOL(arp);
  FSNode *node = [FSNode nodeWithPath: trashPath];
  NSMutableArray *subNodes = [[node subNodes] mutableCopy];
  int count = [subNodes count];
  NSUInteger i;  
  
  for (i = 0; i < count; i++)
    {
      FSNode *nd = [subNodes objectAtIndex: i];

      if ([nd isReserved])
	{
	  [subNodes removeObjectAtIndex: i];
	  i--;
	  count --;
	}
    }
  
  if ([subNodes count])
    {
      NSMutableArray *files = [NSMutableArray array];
      NSMutableDictionary *opinfo = [NSMutableDictionary dictionary];

      for (i = 0; i < [subNodes count]; i++)
	{
	  [files addObject: [[(FSNode *)[subNodes objectAtIndex: i] path] lastPathComponent]];
	}

      [opinfo setObject: @"WorkspaceEmptyRecyclerOperation" forKey: @"operation"];
      [opinfo setObject: trashPath forKey: @"source"];
      [opinfo setObject: trashPath forKey: @"destination"];
      [opinfo setObject: files forKey: @"files"];

      [self performFileOperation: opinfo];
    }

  RELEASE (subNodes);
  RELEASE (arp);
}


//
// DesktopApplication protocol
//
- (void)selectionChanged:(NSArray *)newsel
{
  if (newsel && [newsel count] && ([vwrsManager orderingViewers] == NO)) {
    [self setSelectedPaths: [FSNode pathsOfNodes: newsel]];
  }
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  if (selectedPaths && [selectedPaths count]) {
    [self openSelectedPaths: selectedPaths newViewer: newv];
  }  
}

- (void)openSelectionWithApp:(id)sender
{
  NSString *appName = (NSString *)[(NSMenuItem *)sender representedObject];
  NSUInteger count = (selectedPaths ? [selectedPaths count] : 0);
  
  if (count) {
    NSUInteger i;

    if (count > MAX_FILES_TO_OPEN_DIALOG) {
      NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
      NSString *msg2 = NSLocalizedString(@"items?", @"");

      if (NSRunAlertPanel(nil,
                          [NSString stringWithFormat: @"%@ %lu %@", msg1, (unsigned long)count, msg2],
                  NSLocalizedString(@"Cancel", @""),
                  NSLocalizedString(@"Yes", @""),
                  nil)) {
        return;
      }
    }

    for (i = 0; i < count; i++) {
      NSString *path = [selectedPaths objectAtIndex: i];
    
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

- (void)performFileOperation:(NSDictionary *)opinfo
{
  NSString *operation = [opinfo objectForKey: @"operation"];
  NSString *source = [opinfo objectForKey: @"source"];
  NSString *destination = [opinfo objectForKey: @"destination"];
  NSArray *files = [opinfo objectForKey: @"files"];
  NSInteger tag;

  if (destination == nil && [operation isEqualToString:NSWorkspaceRecycleOperation])
    destination = [self trashPath];

  [self performFileOperation: operation source: source 
		 destination: destination files: files tag: &tag];
}

- (BOOL)filenamesWasCut
{
  return [fileOpsManager filenamesWasCut];
}

- (void)setFilenamesCut:(BOOL)value
{
  [fileOpsManager setFilenamesCut: value];
}

- (void)lsfolderDragOperation:(NSData *)opinfo
              concludedAtPath:(NSString *)path
{
  [finder lsfolderDragOperation: opinfo concludedAtPath: path];
}     
                          
- (void)concludeRemoteFilesDragOperation:(NSData *)opinfo
                             atLocalPath:(NSString *)localPath
{
  NSDictionary *infoDict = [NSUnarchiver unarchiveObjectWithData: opinfo];
  NSArray *srcPaths = [infoDict objectForKey: @"paths"];
  BOOL bookmark = [[infoDict objectForKey: @"bookmark"] boolValue];
  NSString *connName = [infoDict objectForKey: @"dndconn"];
  NSArray *locContents = [fm directoryContentsAtPath: localPath];
  BOOL samename = NO;
  int i;

  if (locContents) {
    NSConnection *conn;
    id remote;
  
    for (i = 0; i < [srcPaths count]; i++) {
      NSString *name = [[srcPaths objectAtIndex: i] lastPathComponent];

      if ([locContents containsObject: name]) {
        samename = YES;
        break;
      }
    }
    
    conn = [NSConnection connectionWithRegisteredName: connName host: @""];
  
    if (conn) {
      remote = [conn rootProxy];
      
      if (remote) {
        NSMutableDictionary *reply = [NSMutableDictionary dictionary];
        NSData *rpdata;
      
        [reply setObject: localPath forKey: @"destination"];
        [reply setObject: srcPaths forKey: @"paths"];
        [reply setObject: [NSNumber numberWithBool: bookmark] forKey: @"bookmark"];  
        [reply setObject: [NSNumber numberWithBool: !samename] forKey: @"dndok"];
        rpdata = [NSArchiver archivedDataWithRootObject: reply];
      
        [remote setProtocolForProxy: @protocol(GWRemoteFilesDraggingInfo)];
        remote = (id <GWRemoteFilesDraggingInfo>)remote;
      
        [remote remoteDraggingDestinationReply: rpdata];
      }
    }
  }
}

- (void)addWatcherForPath:(NSString *)path
{
  [watchedPaths addObject: path];

  if (fswnotifications) {
    [self connectFSWatcher];
    [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
  }
}

- (void)removeWatcherForPath:(NSString *)path
{
  [watchedPaths removeObject: path];

  if (fswnotifications) {
    [self connectFSWatcher];
    [fswatcher client: (id <FSWClientProtocol>)self removeWatcherForPath: path];
  }
}

- (NSString *)trashPath
{
  static NSString *tpath = nil;
  
  if (tpath == nil) {
    tpath = [NSHomeDirectory() stringByAppendingPathComponent: @".Trash"]; 
    RETAIN (tpath);
  }
  
  return tpath;
}

- (id)workspaceApplication
{
  return [Workspace gworkspace];
}

- (oneway void)terminateApplication
{
  [NSApp terminate: self];
}

- (BOOL)terminating
{
  return terminating;
}

static BOOL GWWaitForTaskExit(NSTask *task, NSTimeInterval timeout)
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: timeout];

  while ([task isRunning] && ([deadline timeIntervalSinceNow] > 0))
    {
      GWProcessStartupRunLoop(0.1);
    }

  return ![task isRunning];
}

- (BOOL)trySystemAction:(NSString *)actionType 
{
  // These arrays can be expanded with more commands if needed for other systems
  // or if the current commands fail. The order is important - we try the most
  // common commands first, and if they fail, we try alternatives.
  NSArray *commands;
  if ([actionType isEqualToString:@"restart"]) {
    commands = [NSArray arrayWithObjects:
      // systemd-based Linux (Debian with systemd)
      [NSArray arrayWithObjects:@"/bin/systemctl", @"reboot", nil],
      [NSArray arrayWithObjects:@"/usr/bin/systemctl", @"reboot", nil],
      // Traditional Unix commands (BSD and Linux)
      [NSArray arrayWithObjects:@"/sbin/reboot", nil],
      [NSArray arrayWithObjects:@"/usr/sbin/reboot", nil],
      [NSArray arrayWithObjects:@"/sbin/shutdown", @"-r", @"now", nil],
      [NSArray arrayWithObjects:@"/usr/sbin/shutdown", @"-r", @"now", nil],
      // With sudo as fallback (if LoginWindow isn't running as root)
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/bin/systemctl", @"reboot", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/usr/bin/systemctl", @"reboot", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/sbin/reboot", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/usr/sbin/reboot", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/sbin/shutdown", @"-r", @"now", nil], nil
    ];
  } else if ([actionType isEqualToString:@"shutdown"]) {
    commands = [NSArray arrayWithObjects:
      // systemd-based Linux (Debian with systemd)
      [NSArray arrayWithObjects:@"/bin/systemctl", @"poweroff", nil],
      [NSArray arrayWithObjects:@"/usr/bin/systemctl", @"poweroff", nil],
      // Traditional Unix commands (BSD and Linux)
      [NSArray arrayWithObjects:@"/sbin/poweroff", nil],
      [NSArray arrayWithObjects:@"/usr/sbin/poweroff", nil],
      [NSArray arrayWithObjects:@"/sbin/shutdown", @"-h", @"now", nil],
      [NSArray arrayWithObjects:@"/usr/sbin/shutdown", @"-h", @"now", nil],
      [NSArray arrayWithObjects:@"/sbin/shutdown", @"-p", @"now", nil],  // BSD-style with poweroff
      [NSArray arrayWithObjects:@"/sbin/halt", @"-p", nil],  // Another BSD option
      // With sudo as fallback (if LoginWindow isn't running as root)
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/bin/systemctl", @"poweroff", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/usr/bin/systemctl", @"poweroff", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/sbin/poweroff", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/usr/sbin/poweroff", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/sbin/shutdown", @"-h", @"now", nil],
      [NSArray arrayWithObjects:@"sudo", @"-A", @"-E", @"/sbin/shutdown", @"-p", @"now", nil], nil
    ];
  } else {
    return NO;
  }
    
  for (NSArray *cmd in commands) {
    NSLog(@"Attempting system action with command: %@", [cmd componentsJoinedByString:@" "]);
    NSTask *task = [NSTask new];
    AUTORELEASE(task);
    [task setLaunchPath:[cmd objectAtIndex:0]];
    if ([cmd count] > 1) {
      [task setArguments:[cmd subarrayWithRange:NSMakeRange(1, [cmd count]-1)]];
    }
    
    @try {
      [task launch];
      BOOL finished = GWWaitForTaskExit(task, 3.0);

      if (!finished) {
        NSLog(@"System action command still running after timeout: %@. Assuming system will %@.", [cmd componentsJoinedByString:@" "], actionType);
        return YES; // Don't block the UI waiting forever
      }

      if ([task terminationStatus] == 0) {
        NSLog(@"System action command launched successfully: %@", [cmd componentsJoinedByString:@" "]);        
        return YES; // Command exited cleanly; system should now proceed
      }

      NSLog(@"System action failed with command: %@, exit status: %d", [cmd componentsJoinedByString:@" "], [task terminationStatus]);
      // Try next command
    } @catch (NSException *e) {
      NSLog(@"System action failed with command: %@, error: %@", [cmd componentsJoinedByString:@" "], e);
      // Try next command
    }
  }
  
  NSLog(@"All system action commands failed for action type: %@", actionType);
  return NO; // All failed
}

- (void)executeSystemCommandAndReset
{
  if (_pendingSystemActionCommand) {
    NSString *actionType = [_pendingSystemActionCommand copy];
    NSString *actionTitle = [_pendingSystemActionTitle copy];
    NSLog(@"Executing system command for action: %@", actionType);

    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
      actionType, @"action",
      actionTitle ? actionTitle : (id)[NSNull null], @"title",
      nil];

    [NSThread detachNewThreadSelector:@selector(_performSystemActionAsync:)
                             toTarget:self
                           withObject: payload];

    RELEASE(actionType);
    RELEASE(actionTitle);
  }
}

- (void)_performSystemActionAsync:(NSDictionary *)info
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *actionType = [info objectForKey:@"action"];

  BOOL success = [self trySystemAction: actionType];

  NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithBool: success], @"success",
    actionType, @"action",
    [info objectForKey:@"title"], @"title",
    nil];

  [self performSelectorOnMainThread:@selector(_finalizeSystemAction:)
                         withObject: result
                      waitUntilDone: NO];

  RELEASE(pool);
}

- (void)_finalizeSystemAction:(NSDictionary *)result
{
  BOOL success = [[result objectForKey:@"success"] boolValue];
  NSString *actionType = [result objectForKey:@"action"];
  id titleObj = [result objectForKey:@"title"];
  NSString *title = ([titleObj isKindOfClass:[NSNull class]]) ? nil : titleObj;

  (void)title; // title currently unused but kept for potential UI messaging

  if (!success) {
    NSRunAlertPanel(NSLocalizedString(@"error", @""),
                    [NSString stringWithFormat:@"Failed to execute %@ command. No suitable command found.", actionType],
                    NSLocalizedString(@"OK", @""),
                    nil,
                    nil);
  }

  DESTROY(_pendingSystemActionCommand);
  DESTROY(_pendingSystemActionTitle);
  loggingout = NO;

  NSLog(@"System action attempt completed (success=%d). Application state reset. App will NOT quit.", success);
}

- (void)restart:(id)sender
{
    [[Workspace gworkspace] startLogoutRestartShutdownWithType:@"restart"
        message:NSLocalizedString(@"Are you sure you want to quit\nall applications and restart now?", @"")
        systemAction:NSLocalizedString(@"Restart", @"")
        pendingCommand:@"restart"];
}

- (void)shutdown:(id)sender
{
    [[Workspace gworkspace] startLogoutRestartShutdownWithType:@"shutdown"
        message:NSLocalizedString(@"Are you sure you want to quit\nall applications and shut down now?", @"")
        systemAction:NSLocalizedString(@"Shut Down", @"")
        pendingCommand:@"shutdown"];
}

- (void)createStandardUserDirectories
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *homeDirectory = NSHomeDirectory();
  NSArray *standardDirectories = @[
    @"Desktop",
    @"Documents", 
    @"Downloads",
    @"Music",
    @"Pictures",
    @"Public",
    @"Templates",
    @"Videos"
  ];
  
  for (NSString *dirName in standardDirectories) {
    NSString *dirPath = [homeDirectory stringByAppendingPathComponent:dirName];
    BOOL isDirectory = NO;
    
    if (![fileManager fileExistsAtPath:dirPath isDirectory:&isDirectory]) {
      NS_DURING
        {
          if ([fileManager createDirectoryAtPath:dirPath 
                                       attributes:nil]) {
            NSLog(@"Created standard directory: %@", dirPath);
          } else {
            NSLog(@"Failed to create directory: %@", dirPath);
          }
        }
      NS_HANDLER
        {
          NSLog(@"Error creating directory %@: %@", dirPath, [localException reason]);
        }
      NS_ENDHANDLER
    } else if (!isDirectory) {
      NSLog(@"Warning: %@ exists but is not a directory", dirPath);
    }
  }
}

- (void)setViewerBehaviour:(id)sender
{
  NSLog(@"*** setViewerBehaviour method called! ***");
  NSString *title = [sender title];
  NSLog(@"setViewerBehaviour called with title: %@", title);

  // Get current key window to determine what path we're working with
  NSWindow *keyWindow = [NSApp keyWindow];
  if (!keyWindow) {
    NSLog(@"No key window found");
    return;
  }

  // Try to get viewer from the key window
  id viewer = [vwrsManager viewerWithWindow: keyWindow];
  if (!viewer) {
    NSLog(@"No viewer found for key window");
    return;
  }

  // Get the base node (current path) from the viewer
  FSNode *currentNode = [viewer baseNode];
  if (!currentNode) {
    NSLog(@"No base node found in viewer");
    return;
  }

  NSLog(@"Current path: %@", [currentNode path]);

  // Determine viewer type based on menu item title
  unsigned int viewerType;
  if ([title isEqualToString: @"Browsing"]) {
    viewerType = BROWSING;
    NSLog(@"Setting viewer to BROWSING mode");
  } else if ([title isEqualToString: @"Spatial"]) {
    viewerType = SPATIAL;
    NSLog(@"Setting viewer to SPATIAL mode");
  } else {
    NSLog(@"Unknown viewer behaviour: %@", title);
    return;
  }

  // Create new viewer with the selected behavior
  NSLog(@"Attempting to create new viewer with type %u", viewerType);

  id newViewer = [vwrsManager viewerOfType: viewerType
                                  showType: nil
                                   forNode: currentNode
                             showSelection: YES
                            closeOldViewer: viewer
                                  forceNew: YES];

  if (newViewer) {
    NSLog(@"Successfully created new viewer for path %@", [currentNode path]);
    [newViewer activate];
  } else {
    NSLog(@"Failed to create new viewer");
  }

  NSLog(@"Finished processing viewer behavior change");
}

- (void)setDefaultBrowsingBehaviour:(id)sender
{
  NSLog(@"Setting default viewer behavior to Browsing");
  [self setDefaultViewerType: BROWSING];

  NSRunAlertPanel(@"Default Viewer Set",
                  @"Browsing mode is now the default for new viewer windows.",
                  @"OK", nil, nil);
}

- (void)setDefaultSpatialBehaviour:(id)sender
{
  NSLog(@"Setting default viewer behavior to Spatial");
  [self setDefaultViewerType: SPATIAL];

  NSRunAlertPanel(@"Default Viewer Set",
                  @"Spatial mode is now the default for new viewer windows.",
                  @"OK", nil, nil);
}

@end


@implementation Workspace (SharedInspector)

- (oneway void)showExternalSelection:(NSArray *)selection
{
  if ([[inspector win] isVisible] == NO) {
    [self showContentsInspector: nil];    
  }  
  
  if (selection) {
    [inspector setCurrentSelection: selection];
  } else {
    [self resetSelectedPaths];
  }
}

@end


@implementation	Workspace (PrivateMethods)

- (void)_updateTrashContents
{
  FSNode *node = [FSNode nodeWithPath: trashPath];

  [trashContents removeAllObjects];

  if (node && [node isValid]) {
    NSArray *subNodes = [node subNodes];
    NSUInteger i;

    for (i = 0; i < [subNodes count]; i++) {
      FSNode *subnode = [subNodes objectAtIndex: i];

      if ([subnode isReserved] == NO) {
	[trashContents addObject: subnode];
      }
    }
  }
}

@end

