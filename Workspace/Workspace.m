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

#import <objc/runtime.h>

/* the following for getrlimit */
#include <sys/types.h>
#include <sys/time.h>
#include <unistd.h>
#include <sys/stat.h>
#ifdef HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif
/* getrlimit */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSInfoPanel.h>
#import <GNUstepBase/GNUstep.h>
#import <dispatch/dispatch.h>

#import "GWFunctions.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "Workspace.h"

/* Set of paths the user has recently unmounted via the GUI.
 * Used by showMountedVolumes to suppress the "Unexpectedly" dialog.
 * Paths are removed after a short timeout. */
static NSMutableSet *recentUserUnmounts = nil;
static NSTimeInterval recentUserUnmountTimeout = 2.0;
#import "Dialogs.h"
#import "AppDataTrash.h"
#import "AboutController.h"
#import "OpenWithController.h"
#import "RunExternalController.h"
#import "StartAppWin.h"
#import "Preferences/PrefController.h"
#import "GWApplicationLauncher.h"
#import "GWUnmountHelper.h"
#import "GWDesktopManager.h"
#import "VolumeManager.h"
#import "ISOWrite/DiskFormatOperation.h"
#import "ISOWrite/BlockDeviceInfo.h"
#import "ISOWrite/DeviceEraseConfirmation.h"
#import "GWDesktopWindow.h"
#import "GWDockWindow.h"
#import "Dock.h"
#import "GWViewersManager.h"
#import "GWViewer.h"
#import "Finder.h"
#import "Inspector.h"
#import "Operation.h"
#import "History/History.h"
#import "X11AppSupport.h"
#import "Thumbnailer/GWThumbnailer.h"
#import "GSGlobalShortcutsManager.h"
#import "GSFileMetadata.h"
#import "DSStore.h"
#import "DSStoreInfo.h"
#import "GWViewSettingsManager.h"
#import "GWMetaArchive.h"
#import "FSNIconsView.h"
#import "GWMetadataProvider.h"
#import "GWIconPositionStore.h"
#import "GWArchiveOperation.h"
#import "Network/NetworkFSNode.h"
#import "Network/NetworkServiceManager.h"
#import "Network/NetworkServiceItem.h"
#import "Network/NetworkVolumeManager.h"
#import "AVFSMount.h"
#import "LowDiskWarn.h"
#if HAVE_DBUS
#import "DBusConnection.h"
#import "FileManagerDBusInterface.h"
#endif


static NSString *defaulteditor = @"nedit.app";
static NSString *defaultxterm = @"xterm";

static Workspace *gworkspace = nil;

/* Forward declarations for methods resolved at runtime on container/view objects.
 * Avoids method-not-found warnings when calling on `id` typed objects. */
@interface NSObject (WorkspaceForwardDecls)
- (void)workspaceWillUnmountVolumeAtPath:(NSString *)vpath;
- (void)workspaceDidUnmountVolumeAtPath:(NSString *)vpath;
- (void)setCustomIconPositions:(NSDictionary *)positions;
- (NSArray *)icons;
- (void)cleanupIconPositions;
- (void)batchRepositionIcons:(NSArray *)icons toCenterPoints:(NSArray *)points;
@end

@interface Workspace (PrivateMethods)
- (void)_updateTrashContents;
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
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *userPrefs = [@"~/Library/Preferences/org.gnustep.Workspace.plist" stringByExpandingTildeInPath];

  if (![fm fileExistsAtPath: userPrefs])
    {
      NSString *localPrefs = @"/Local/Library/Preferences/GlobalDefaults/org.gnustep.Workspace.plist";
      NSString *systemPrefs = @"/System/Library/Preferences/GlobalDefaults/org.gnustep.Workspace.plist";
      NSDictionary *d = nil;

      if ([fm fileExistsAtPath: localPrefs])
        {
          d = [NSDictionary dictionaryWithContentsOfFile: localPrefs];
        }
      else if ([fm fileExistsAtPath: systemPrefs])
        {
          d = [NSDictionary dictionaryWithContentsOfFile: systemPrefs];
        }

      if (d != nil)
        {
          [defaults registerDefaults: d];
        }
    }

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
  RELEASE (history);
  RELEASE (openWithController);
  RELEASE (openWithMenu);
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
  DESTROY (lowDiskWarn);

#if HAVE_DBUS
  DESTROY (fileManagerDBusInterface);
  DESTROY (dbusFileHandle);
#endif
    
  [super dealloc];
}

- (void)createMenu
{
  NSMenu *mainMenu = [NSMenu new];
  NSMenu *menu;
  NSMenu *subMenu;
  NSMenu *windows, *services;  
  id<NSMenuItem> menuItem;
  
  // Workspace menu (main application menu)
  menuItem = [mainMenu addItemWithTitle:_(@"About This Computer") action:@selector(showAboutThisComputer:) keyEquivalent:@""];
  [menuItem setTarget:self];

  menuItem = [mainMenu addItemWithTitle:_(@"About Workspace") action:@selector(showInfo:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [mainMenu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [mainMenu addItemWithTitle:_(@"Preferences...") action:@selector(showPreferences:) keyEquivalent:@","];
  [menuItem setTarget:self];
  
  [mainMenu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [mainMenu addItemWithTitle:_(@"Empty Trash") action:@selector(emptyTrash:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [mainMenu addItem:[NSMenuItem separatorItem]];
  
  // Services submenu
  menuItem = [mainMenu addItemWithTitle:_(@"Services") action:NULL keyEquivalent:@""];
  services = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: services forItem: menuItem];
  
  [mainMenu addItem:[NSMenuItem separatorItem]];
  
  [mainMenu addItemWithTitle:_(@"Hide Workspace") action:@selector(hide:) keyEquivalent:@"h"];
  [mainMenu addItemWithTitle:_(@"Hide Others") action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
  [[mainMenu itemWithTitle:_(@"Hide Others")] setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
  [mainMenu addItemWithTitle:_(@"Show All") action:@selector(unhideAllApplications:) keyEquivalent:@""];
  
  [mainMenu addItem:[NSMenuItem separatorItem]];
  
  // File menu
  menuItem = [mainMenu addItemWithTitle:_(@"File") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  
  menuItem = [menu addItemWithTitle:_(@"New Workspace Window") action:@selector(showViewer:) keyEquivalent:@"n"];
  [menuItem setTarget:self];
  
  [menu addItemWithTitle:_(@"New Folder") action:@selector(newFolder:) keyEquivalent:@"N"];
  [[menu itemWithTitle:_(@"New Folder")] setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [[menu itemWithTitle:_(@"New Folder")] setTarget:self];
  
  // menuItem = [menu addItemWithTitle:_(@"New File") action:@selector(newFile:) keyEquivalent:@""];
  // [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Open") action:@selector(openSelection:) keyEquivalent:@"o"];
  [menuItem setTarget:self];
  
  // Open With submenu
  menuItem = [menu addItemWithTitle:_(@"Open With") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  ASSIGN (openWithMenu, subMenu);
  menuItem = [menu addItemWithTitle:_(@"Open as Folder") action:@selector(openSelectionAsFolder:) keyEquivalent:@"O"];
  [[menu itemWithTitle:_(@"Open as Folder")] setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];


  menuItem = [menu addItemWithTitle:_(@"Print") action:@selector(print:) keyEquivalent:@"p"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Close Window") action:@selector(performClose:) keyEquivalent:@"w"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Get Info") action:@selector(showAttributesInspector:) keyEquivalent:@"i"];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Compress") action:@selector(compressFiles:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Duplicate") action:@selector(duplicateFiles:) keyEquivalent:@"d"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Make Alias") action:@selector(notImplemented:) keyEquivalent:@"l"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Quick Look \"item\"") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  // Share submenu
  menuItem = [menu addItemWithTitle:_(@"Share") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Move to Trash") action:@selector(recycleFiles:) keyEquivalent:@""];
  [menuItem setKeyEquivalent:@"\x7f"]; // Backspace
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Destroy") action:@selector(deleteFiles:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Find") action:@selector(showFinder:) keyEquivalent:@"f"];
  [menuItem setTarget:self];
  // Label submenu
  menuItem = [menu addItemWithTitle:_(@"Label") action:NULL keyEquivalent:@""];
  subMenu = [self labelColorSubmenu];
  [menu setSubmenu: subMenu forItem: menuItem];

  // Edit menu
  menuItem = [mainMenu addItemWithTitle:_(@"Edit") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  
  [menu addItemWithTitle:_(@"Undo") action:@selector(undo:) keyEquivalent:@"z"];
  [[menu itemWithTitle:_(@"Undo")] setTarget:self];
  [menu addItemWithTitle:_(@"Redo") action:@selector(redo:) keyEquivalent:@"Z"];
  [[menu itemWithTitle:_(@"Redo")] setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [[menu itemWithTitle:_(@"Redo")] setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Cut") action:@selector(cut:) keyEquivalent:@"x"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Copy") action:@selector(copy:) keyEquivalent:@"c"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Paste") action:@selector(paste:) keyEquivalent:@"v"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Select All") action:@selector(selectAllInViewer:) keyEquivalent:@"a"];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  //menuItem = [menu addItemWithTitle:_(@"Show Clipboard") action:@selector(notImplemented:) keyEquivalent:@""];
  //[menuItem setTarget:self];

  [menu addItem:[NSMenuItem separatorItem]];

  // menuItem = [menu addItemWithTitle:_(@"Start Dictation") action:@selector(notImplemented:) keyEquivalent:@""];
  // [menuItem setTarget:self];
  //menuItem = [menu addItemWithTitle:_(@"Symbols") action:@selector(notImplemented:) keyEquivalent:@""];
  //[menuItem setTarget:self];

  // View menu
  menuItem = [mainMenu addItemWithTitle:_(@"View") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"as Icons") action:@selector(setViewerType:) keyEquivalent:@"1"];
  [menuItem setTarget:self];
  [menuItem setTag:GWViewTypeIcon];
  [menuItem autorelease];
  [menu addItem:menuItem];
  
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"as List") action:@selector(setViewerType:) keyEquivalent:@"2"];
  [menuItem setTarget:self];
  [menuItem setTag:GWViewTypeList];
  [menuItem autorelease];
  [menu addItem:menuItem];

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"as Columns") action:@selector(setViewerType:) keyEquivalent:@"3"];
  [menuItem setTarget:self];
  [menuItem setTag:GWViewTypeBrowser];
  [menuItem autorelease];
  [menu addItem:menuItem];
  
  //menuItem = [menu addItemWithTitle:_(@"as Gallery") action:@selector(notImplemented:) keyEquivalent:@"4"];
  //[menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];

  /* Toggle the rightmost "Contents" inspector pane in every view type. */
  menuItem = [menu addItemWithTitle:_(@"Show Inspector") action:@selector(toggleInspector:) keyEquivalent:@"i"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSControlKeyMask];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Use Stacks") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  menuItem = [menu addItemWithTitle:_(@"View Behavior") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Browsing") action:@selector(setViewerBehaviour:) keyEquivalent:@"b"];
  [menuItem setTarget:self];
  [menuItem setTag:BROWSING];   /* read by -setViewerBehaviour: (locale-safe) */
  [subMenu addItem:menuItem];
  [menuItem release];

  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Spatial") action:@selector(setViewerBehaviour:) keyEquivalent:@"s"];
  [menuItem setTarget:self];
  [menuItem setTag:SPATIAL];
  [subMenu addItem:menuItem];
  [menuItem release];
  
  [subMenu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Set Browsing as Default") action:@selector(setDefaultBrowsingBehaviour:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];
  
  menuItem = [[NSMenuItem alloc] initWithTitle:_(@"Set Spatial as Default") action:@selector(setDefaultSpatialBehaviour:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [subMenu addItem:menuItem];
  [menuItem release];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Show") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Name only") action:@selector(setShownType:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Type") action:@selector(setShownType:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Size") action:@selector(setShownType:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Modification date") action:@selector(setShownType:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Owner") action:@selector(setShownType:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  menuItem = [menu addItemWithTitle:_(@"Icon Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"24") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"28") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"32") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"36") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"40") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"48") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"64") action:@selector(setIconsSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  menuItem = [menu addItemWithTitle:_(@"Icon Position") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Up") action:@selector(setIconsPosition:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Left") action:@selector(setIconsPosition:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  menuItem = [menu addItemWithTitle:_(@"Thumbnails") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Make thumbnail(s)") action:@selector(makeThumbnails:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Remove thumbnail(s)") action:@selector(removeThumbnails:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  menuItem = [menu addItemWithTitle:_(@"Label Size") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"10") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"11") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"12") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"13") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"14") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"15") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"16") action:@selector(setLabelSize:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  // Sort By submenu
  menuItem = [menu addItemWithTitle:_(@"Sort By") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Name") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Kind") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Date Modified") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Date Created") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Size") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Tags") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Clean Up") action:@selector(cleanUp:) keyEquivalent:@""];
  [menuItem setTarget:self];

  // Clean Up By submenu
  menuItem = [menu addItemWithTitle:_(@"Clean Up By") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Name") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 0];
  menuItem = [subMenu addItemWithTitle:_(@"Kind") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 1];
  menuItem = [subMenu addItemWithTitle:_(@"Date Modified") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 2];
  menuItem = [subMenu addItemWithTitle:_(@"Date Created") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 5];
  menuItem = [subMenu addItemWithTitle:_(@"Size") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 3];
  menuItem = [subMenu addItemWithTitle:_(@"Tags") action:@selector(cleanUpBy:) keyEquivalent:@""];
  [menuItem setTarget:self]; [menuItem setTag: 0];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Show Sidebar") action:@selector(toggleSidebar:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [menuItem setState: NSOnState];
  menuItem = [menu addItemWithTitle:_(@"Show Preview") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Hide Toolbar") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Customize Toolbar...") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Show View Options") action:@selector(notImplemented:) keyEquivalent:@"j"];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Show Preview Options") action:@selector(notImplemented:) keyEquivalent:@"J"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Enter Full Screen") action:@selector(toggleFullScreen:) keyEquivalent:@"f"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSControlKeyMask];
  [menuItem setTarget:self];

  // Go menu
  menuItem = [mainMenu addItemWithTitle:_(@"Go") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  
  menuItem = [menu addItemWithTitle:_(@"Back") action:@selector(goBackwardInHistory:) keyEquivalent:@"["];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Forward") action:@selector(goForwardInHistory:) keyEquivalent:@"]"];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Enclosing Folder") action:@selector(openParentFolder:) keyEquivalent:@""];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalent:@""];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Recents") action:@selector(showHistory:) keyEquivalent:@"F"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Documents") action:@selector(goToDocuments:) keyEquivalent:@"O"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Desktop") action:@selector(goToDesktop:) keyEquivalent:@"D"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Downloads") action:@selector(goToDownloads:) keyEquivalent:@"L"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Music") action:@selector(goToMusic:) keyEquivalent:@"M"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Pictures") action:@selector(goToPictures:) keyEquivalent:@"P"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Videos") action:@selector(goToVideos:) keyEquivalent:@"V"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Home") action:@selector(goToHome:) keyEquivalent:@"H"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  menuItem = [menu addItemWithTitle:_(@"Computer") action:@selector(goToComputer:) keyEquivalent:@"C"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  menuItem = [menu addItemWithTitle:_(@"Transfer") action:NULL keyEquivalent:@""];
  [menuItem setEnabled:NO];
  menuItem = [menu addItemWithTitle:_(@"Network") action:@selector(goToNetwork:) keyEquivalent:@"K"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  // menuItem = [menu addItemWithTitle:_(@"Cloud Drive") action:NULL keyEquivalent:@""];
  // [menuItem setEnabled:NO];
  menuItem = [menu addItemWithTitle:_(@"Applications") action:@selector(goToApplications:) keyEquivalent:@"A"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  menuItem = [menu addItemWithTitle:_(@"Utilities") action:@selector(goToUtilities:) keyEquivalent:@"U"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Go to Folder...") action:@selector(goToFolder:) keyEquivalent:@"G"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  menuItem = [menu addItemWithTitle:_(@"Connect to Server...") action:@selector(connectToServer:) keyEquivalent:@"K"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask];

  // Tools menu
  menuItem = [mainMenu addItemWithTitle:_(@"Tools") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];

  menuItem = [menu addItemWithTitle:_(@"Run...") action:@selector(runCommand:) keyEquivalent:@"R"];
  [menuItem setTarget:self];
  [menuItem setKeyEquivalentModifierMask: NSCommandKeyMask | NSShiftKeyMask];
  
  [menu addItem:[NSMenuItem separatorItem]];

  /*
  menuItem = [menu addItemWithTitle:_(@"History") action:NULL keyEquivalent:@""];
  subMenu = AUTORELEASE ([NSMenu new]);
  [menu setSubmenu: subMenu forItem: menuItem];
  menuItem = [subMenu addItemWithTitle:_(@"Show History") action:@selector(showHistory:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Go backward") action:@selector(goBackwardInHistory:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [subMenu addItemWithTitle:_(@"Go forward") action:@selector(goForwardInHistory:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];

  menuItem = [menu addItemWithTitle:_(@"Check for disks") action:@selector(checkRemovableMedia:) keyEquivalent:@"E"];
  [menuItem setTarget:self];
  */

  // Window menu
  menuItem = [mainMenu addItemWithTitle:_(@"Window") action:NULL keyEquivalent:@""];
  windows = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: windows forItem: menuItem];
  
  [windows addItemWithTitle:_(@"Minimize") action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [windows addItemWithTitle:_(@"Zoom") action:@selector(performZoom:) keyEquivalent:@""];
  
  [windows addItem:[NSMenuItem separatorItem]];
  
  menuItem = [windows addItemWithTitle:_(@"Cycle Through Windows") action:@selector(notImplemented:) keyEquivalent:@"`"];
  [menuItem setTarget:self];
  
  [windows addItem:[NSMenuItem separatorItem]];
  
  [windows addItemWithTitle:_(@"Bring All to Front") action:@selector(arrangeInFront:) keyEquivalent:@""];
  
  [windows addItem:[NSMenuItem separatorItem]];
  // Window list will be added here dynamically
  
  // Help menu
  menuItem = [mainMenu addItemWithTitle:_(@"Help") action:NULL keyEquivalent:@""];
  menu = AUTORELEASE ([NSMenu new]);
  [mainMenu setSubmenu: menu forItem: menuItem];
  
  menuItem = [menu addItemWithTitle:_(@"Workspace Help") action:@selector(workspaceHelp:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Gershwin Help") action:@selector(openGershwinHelp:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  // NOTE: Instead of implementing this in Workspace, we should implement this in Menu.app
  // so that it works system-wide. Menu.app can inspect the frontmost application and show
  // its keyboard shortcuts, and insert them into the Help menu dynamically or create one if needed.
  menuItem = [menu addItemWithTitle:_(@"Keyboard Shortcuts") action:@selector(notImplemented:) keyEquivalent:@"/"];
  [menuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"New to Gershwin? Get Started") action:@selector(notImplemented:) keyEquivalent:@""];
  [menuItem setTarget:self];
  
  [menu addItem:[NSMenuItem separatorItem]];
  
  menuItem = [menu addItemWithTitle:_(@"Feedback") action:@selector(openFeedback:) keyEquivalent:@""];
  [menuItem setTarget:self];
  menuItem = [menu addItemWithTitle:_(@"Legal & Regulatory") action:@selector(openLegal:) keyEquivalent:@""];
  [menuItem setTarget:self];
  

  [mainMenu update];
  [mainMenu setDelegate: self];

  [self fixSubmenuContainerItems: mainMenu];

  [NSApp setServicesMenu: services];
  [NSApp setWindowsMenu: windows];
  [NSApp setMainMenu: mainMenu];    
  
  RELEASE (mainMenu);
}

/* GNUstep's menu auto-enabling disables items whose action resolves to no
 * target.  Submenu container items ("Tools", "View", ...) have no action, so
 * the whole menu title gets greyed out.  Give every container a real no-op
 * action handled by Workspace so the title itself is never disabled; the
 * individual items inside are still validated as usual. */
- (void)fixSubmenuContainerItems:(NSMenu *)menu
{
  NSArray *items = [menu itemArray];
  NSUInteger i;

  for (i = 0; i < [items count]; i++) {
    NSMenuItem *item = [items objectAtIndex: i];
    NSMenu *submenu = [item submenu];

    if (submenu) {
      [item setAction: @selector(submenuAction:)];
      [item setTarget: self];
      [item setEnabled: YES];
      [self fixSubmenuContainerItems: submenu];
    }
  }
}

/* No-op action for submenu container items (see fixSubmenuContainerItems:). */
- (void)submenuAction:(id)sender
{
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
  /* Supply FSNode with the Finder-metadata provider so cells/views can read
   * label colours, invisibility, custom icons and icon positions without
   * depending on the metadata implementation directly. */
  [fsnodeRep setMetadataProvider: [GWMetadataProvider sharedProvider]];
  [fsnodeRep setIconPositionStore: [GWIconPositionStore sharedStore]];


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
      [fsnodeRep setReservedNames: [NSArray arrayWithObjects: @".gwsort", nil]];
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

  if ([defaults objectForKey: @"use_thumbnails"] == nil)
    boolentry = YES;
  else
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
    
  dtopManager = [GWDesktopManager desktopManager];
    
  if ([defaults boolForKey: @"no_desktop"] == NO)
  { 
    [dtopManager activateDesktop];

  }

  prefController = [PrefController new];  
  
  history = [[History alloc] init];
  
  openWithController = [[OpenWithController alloc] init];
  runExtController = [[RunExternalController alloc] init];
  	    
  finder = [Finder finder];
  
  vwrsManager = [GWViewersManager viewersManager];
  // Don't open viewer windows on startup - just show desktop
  // [vwrsManager showViewers];
  
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

static BOOL (*orig_getInfoForFile)(id, SEL, NSString*, NSString**, NSString**);

static BOOL swizzled_getInfoForFile(id self, SEL _cmd, NSString *fullPath, NSString **appName, NSString **type)
{
  BOOL result = orig_getInfoForFile(self, _cmd, fullPath, appName, type);
  if (result == YES && *appName != nil) {
    return YES;
  }
  NSString *ext = [fullPath pathExtension];
  if ([ext length] == 0) {
    NSString *filename = [[fullPath lastPathComponent] lowercaseString];
    *appName = [self getBestAppInRole: nil forExtension: filename];
    if (*appName != nil) {
      *type = NSPlainFileType;
      return YES;
    }
  }
  return result;
}

- (void)_swizzleGetInfoForFileForNoExtensionFiles
{
  Class cls = [NSWorkspace class];
  SEL sel = @selector(getInfoForFile:application:type:);
  Method m = class_getInstanceMethod(cls, sel);
  if (m) {
    orig_getInfoForFile = (BOOL (*)(id, SEL, NSString*, NSString**, NSString**))method_getImplementation(m);
    method_setImplementation(m, (IMP)swizzled_getInfoForFile);
  }
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
  [self _swizzleGetInfoForFileForNoExtensionFiles];

  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
  
  NS_DURING
    {
      [NSApp setServicesProvider:self];
    }
  NS_HANDLER
    {
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

  /* Listen for user-initiated unmount notifications from the eject(1)
   * and umount(1) CLI tools, so the "Volume Removed Unexpectedly"
   * dialog is suppressed when those tools are used. */
  [dnc addObserver: self
          selector: @selector(workspaceWillUnmountFromCLI:)
              name: @"GWWorkspaceWillUnmountNotification"
            object: nil];

  /* Listen for successful unmount notifications from the eject(1) and
   * umount(1) CLI tools, so the desktop icon is removed and the volume
   * list is updated. */
  [dnc addObserver: self
          selector: @selector(workspaceDidUnmountFromCLI:)
              name: @"GWWorkspaceDidUnmountNotification"
            object: nil];

  [self initializeWorkspace];

  lowDiskWarn = [[LowDiskWarn alloc] init];
  [lowDiskWarn startMonitoring];

  // Initialize global shortcuts manager only if this instance is rendering the desktop
  if ([dtopManager isActive]) {
    globalShortcutsManager = [[GSGlobalShortcutsManager sharedManager] retain];
    if (![globalShortcutsManager startWithVerbose:YES]) {  // Enable verbose for debugging
      DESTROY(globalShortcutsManager);
    } else {
    }
  } else {
  }
  
#if HAVE_DBUS
  // Initialize and register the FileManager DBus interface
  fileManagerDBusInterface = [[FileManagerDBusInterface alloc] initWithWorkspace:self];
  if (![fileManagerDBusInterface registerOnDBus]) {
    DESTROY(fileManagerDBusInterface);
  } else {
    
    // Set up D-Bus file descriptor monitoring for asynchronous message handling
    // This ensures FileManager1 receives messages immediately without blocking
    int dbusFd = [[fileManagerDBusInterface dbusConnection] getFileDescriptor];
    if (dbusFd >= 0) {
      dbusFileHandle = [[NSFileHandle alloc] initWithFileDescriptor:dbusFd closeOnDealloc:NO];
      if (dbusFileHandle) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(processDBusMessages:)
                                                   name:NSFileHandleDataAvailableNotification
                                                 object:dbusFileHandle];
        [dbusFileHandle waitForDataInBackgroundAndNotify];
      } else {
      }
    } else {
    }
  }
#endif

}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
  [self resetSelectedPaths];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app 
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  
#define TEST_CLOSE(o, w) if ((o) && ([w isVisible])) [w close]
  
  if ([fileOpsManager operationsPending]) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Wait the operations to terminate!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
    return NSTerminateCancel;  
  }

  // Stop global shortcuts manager if it was started
  if (globalShortcutsManager) {
    [globalShortcutsManager stop];
    DESTROY(globalShortcutsManager);
  }
  
  [wsnc removeObserver: self];
  
  fswnotifications = NO;
  terminating = YES;

  /* Write out any icon positions still waiting on the debounce timer. */
  [[GWIconPositionStore sharedStore] flushPending];
  
  [self updateDefaults];
  
  TEST_CLOSE (prefController, [prefController myWin]);
  TEST_CLOSE (history, [history myWin]); 
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
          NS_ENDHANDLER
          DESTROY (fswatcher);
        }
    }

  [inspector updateDefaults];

  [finder stopAllSearchs];
  
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
  
  [lowDiskWarn stopMonitoring];

  /* Unmount all network volumes */
  [[NetworkVolumeManager sharedManager] unmountAll];
  		
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
  FSNode *targetNode = [FSNode nodeWithPath: path];


  /* Route through the canonical open: a folder opens a viewer (growing from
   * the focused viewer's icon when it is shown there). */
  if (targetNode && [targetNode hasValidPath]) {
    [vwrsManager openNode: targetNode fromViewer: nil];
  }
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

  if ([[prefController myWin] isVisible])
    {
      [prefController updateDefaults]; 
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

	[defaults synchronize];
}

- (void)setContextHelp
{
  NSHelpManager *manager = [NSHelpManager sharedHelpManager];
  NSString *help;

  help = @"History.rtfd";
  [manager setContextHelp: (NSAttributedString *)help 
                forObject: [[history myWin] contentView]];

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

}

- (StartAppWin *)startAppWin
{
  return startAppWin;
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)anItem
{
  SEL action = [anItem action];

  // CRITICAL: Disable ALL menu items when a modal window is active
  if ([NSApp modalWindow] != nil) {
    return NO;
  }

  // "Set Browsing/Spatial as Default" are always available: they change the
  // default viewer type for newly opened windows regardless of the current
  // selection or window.
  if (sel_isEqual(action, @selector(setDefaultBrowsingBehaviour:))
      || sel_isEqual(action, @selector(setDefaultSpatialBehaviour:)))
    {
      BOOL isSpatial = sel_isEqual(action, @selector(setDefaultSpatialBehaviour:));
      [anItem setState: ([self defaultViewerType] == (isSpatial ? SPATIAL : BROWSING))
                       ? NSOnState : NSOffState];
      return YES;
    }

  // Submenu container items (menu titles) are never disabled.
  if (sel_isEqual(action, @selector(submenuAction:)))
    {
      return YES;
    }

  // === App-level items handled directly by Workspace ===

  if (sel_isEqual(action, @selector(emptyTrash:))) {
    return ([trashContents count] != 0);
  }
  if (sel_isEqual(action, @selector(activateContextHelp:))) {
    return ([NSHelpManager isContextHelpModeActive] == NO);
  }

  // Cut/copy/paste for file operations
  if (sel_isEqual(action, @selector(cut:))
      || sel_isEqual(action, @selector(copy:)))
    {
      // Enable if there's a file selection in the current viewer/desktop
      NSWindow *kwin = [NSApp keyWindow];
      if (kwin && ([vwrsManager hasViewerWithWindow: kwin]
                   || [dtopManager hasWindow: kwin]))
        {
          id nodeView;
          if ([vwrsManager hasViewerWithWindow: kwin])
            nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
          else
            nodeView = [dtopManager desktopView];
          NSArray *selection = [nodeView selectedPaths];
          NSArray *basesel = [NSArray arrayWithObject: [[nodeView baseNode] path]];
          return ([selection count] > 0
                  && [selection isEqual: basesel] == NO);
        }
      return NO;
    }
  if (sel_isEqual(action, @selector(paste:))) {
    return [self pasteboardHasValidContent];
  }

  // Go To menu navigation commands are always available: they jump to a
  // fixed location and never depend on the current selection or window.
  if (sel_isEqual(action, @selector(goToComputer:))
      || sel_isEqual(action, @selector(goToHome:))
      || sel_isEqual(action, @selector(goToApplications:))
      || sel_isEqual(action, @selector(goToUtilities:))
      || sel_isEqual(action, @selector(goToDocuments:))
      || sel_isEqual(action, @selector(goToDesktop:))
      || sel_isEqual(action, @selector(goToDownloads:))
      || sel_isEqual(action, @selector(goToMusic:))
      || sel_isEqual(action, @selector(goToPictures:))
      || sel_isEqual(action, @selector(goToVideos:))
      || sel_isEqual(action, @selector(goToNetwork:))
      || sel_isEqual(action, @selector(goToFolder:))
      || sel_isEqual(action, @selector(connectToServer:))
      || sel_isEqual(action, @selector(showHistory:))
      || sel_isEqual(action, @selector(openParentFolder:)))
    {
      return YES;
    }

  // Always-enabled app-level commands
  if (sel_isEqual(action, @selector(showViewer:))
      || sel_isEqual(action, @selector(runCommand:))
      || sel_isEqual(action, @selector(showFinder:))
      || sel_isEqual(action, @selector(showPreferences:))
      || sel_isEqual(action, @selector(terminate:))
      || sel_isEqual(action, @selector(hide:))
      || sel_isEqual(action, @selector(hideOtherApplications:))
      || sel_isEqual(action, @selector(unhideAllApplications:))
      || sel_isEqual(action, @selector(orderFrontStandardAboutPanel:))
      || sel_isEqual(action, @selector(orderFrontStandardInfoPanel:))
      || sel_isEqual(action, @selector(orderFrontStandardInfoPanelWithOptions:))
      || sel_isEqual(action, @selector(showInfo:))
      || sel_isEqual(action, @selector(showAboutThisComputer:))
      || sel_isEqual(action, @selector(workspaceHelp:))
      || sel_isEqual(action, @selector(openGershwinHelp:))
      || sel_isEqual(action, @selector(openFeedback:))
      || sel_isEqual(action, @selector(openLegal:))
      || sel_isEqual(action, @selector(makeThumbnails:))
      || sel_isEqual(action, @selector(removeThumbnails:))
      || sel_isEqual(action, @selector(notImplemented:)))
    {
      return YES;
    }

  // === Window-level standard operations — forward to key window ===
  if (sel_isEqual(action, @selector(performClose:))
      || sel_isEqual(action, @selector(performMiniaturize:))
      || sel_isEqual(action, @selector(performZoom:))
      || sel_isEqual(action, @selector(undo:))
      || sel_isEqual(action, @selector(redo:))
      || sel_isEqual(action, @selector(toggleToolbarShown:)))
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if ([keyWindow respondsToSelector:@selector(validateMenuItem:)])
        return [keyWindow validateMenuItem:anItem];
      return NO;
    }

  // === View type / behaviour — enabled whenever a viewer window exists ===
  if (sel_isEqual(action, @selector(setViewerType:))
      || sel_isEqual(action, @selector(setViewerBehaviour:))
      || sel_isEqual(action, @selector(toggleInspector:))
      || sel_isEqual(action, @selector(toggleSidebar:))) {
      /* With a detached global menu (Menu.app) the viewer is not always the
       * key window when the menu validates, so resolve the target viewer from
       * the key window, else the main window, else the first live viewer.
       * Only when no viewer window exists at all (pure desktop context) are
       * these items greyed out. */
      id viewer = [self _viewerForKeyWindow];
      if (sel_isEqual(action, @selector(toggleInspector:)))
        {
          if (viewer && [viewer respondsToSelector: @selector(isInspectorShown)])
            {
              [anItem setState: [viewer isInspectorShown] ? NSOnState : NSOffState];
            }
          return (viewer != nil);
        }
      if (sel_isEqual(action, @selector(toggleSidebar:)))
        {
          /* The sidebar exists only in browsing viewers; spatial viewers do
           * not respond, so the item is greyed out there.  Mirrors the
           * Inspector item: fixed "Show Sidebar" title, checkmark when the
           * sidebar is showing. */
          if (viewer && [viewer respondsToSelector: @selector(toggleSidebar:)]
              && [viewer respondsToSelector: @selector(isSidebarShown)])
            {
              [anItem setState: [viewer isSidebarShown] ? NSOnState : NSOffState];
              return YES;
            }
          return NO;
        }
      if (sel_isEqual(action, @selector(setViewerType:)))
        {
          if (viewer && [viewer respondsToSelector: @selector(viewType)])
            {
              GWViewType vtype = [viewer viewType];
              [anItem setState: ([anItem tag] == vtype) ? NSOnState : NSOffState];
              return YES;
            }
        }
      else if (sel_isEqual(action, @selector(setViewerBehaviour:)))
        {
          if (viewer && [viewer respondsToSelector: @selector(vtype)])
            {
              int vt = [viewer vtype];
              [anItem setState: ([anItem tag] == vt) ? NSOnState : NSOffState];
              return YES;
            }
        }
      /* No viewer window: this is the desktop context. */
      return NO;
    }

  // === Context-dependent file/viewer operations ===
  // Forward to the key window's delegate (GWViewer, GWSpatialViewer,
  // GWDesktopManager) via validateItem: which checks selection state,
  // writability, trash path, etc.
  NSWindow *keyWindow = [NSApp keyWindow];
  id delegate = [keyWindow delegate];
  if ([delegate respondsToSelector:@selector(validateItem:)])
    {
      return [delegate validateItem:anItem];
    }

  // Fallback: if no window handles it, disable the item
  return NO;
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
      
      [self updateOpenWithMenu];
      
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

    /* Check if this is a network virtual path */
    if ([NetworkFSNode isNetworkPath:apath]) {
      FSNode *node = [FSNode nodeWithPath:apath];

      if ([node isKindOfClass:[NetworkFSNode class]]) {
        NetworkFSNode *networkNode = (NetworkFSNode *)node;

        if ([networkNode isNetworkService]) {
          /* This is a network service item - try to open/mount it */
          NSString *mountPoint = [networkNode openNetworkService];

          if (mountPoint && newv) {
            /* Successfully mounted or opened - show viewer at mount point */
            FSNode *target = [FSNode nodeWithPath: mountPoint];
            if (target) {
              [vwrsManager openNode: target fromViewer: nil];
            }
          }
          /* If mount failed, openNetworkService already showed an error */
          continue;
        } else if ([networkNode isNetworkRoot]) {
          /* This is the /Network root - just open a viewer */
          if (newv) {
            [vwrsManager openNode: node fromViewer: nil];
          }
          continue;
        }
      }
    }

    if ([fm fileExistsAtPath: apath]) {
      FSNode *node = [FSNode nodeWithPath: apath];
      if (node == nil || [node hasValidPath] == NO) {
        continue;
      }

      NS_DURING
        {
          /* The canonical open: folders open a viewer (growing from the
           * focused viewer's icon), everything else launches its app.  When
           * newv is NO, directories are not opened at all. */
          if (newv || [node isDirectory] == NO) {
            [vwrsManager openNode: node fromViewer: nil];
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


  /* Early ELF detection: catch executables regardless of the reported type
     so we can prompt the user before any external app (like TextEdit)
     opens the file. This mirrors the later ELF handling but runs first. */
  {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath: fullPath];
    if (fh) {
      NSData *hdr = [fh readDataOfLength:4];
      [fh closeFile];
      const unsigned char *bytes = (const unsigned char *)[hdr bytes];
      if ([hdr length] >= 4 && bytes[0] == 0x7f && bytes[1] == 'E' && bytes[2] == 'L' && bytes[3] == 'F') {
        NSError *err = nil;
        NSDictionary *attrs = [fm attributesOfItemAtPath: fullPath error: &err];
        if (attrs) {
          NSNumber *permNum = [attrs objectForKey: NSFilePosixPermissions];
          unsigned short perms = [permNum unsignedShortValue];
          if ((perms & S_IXUSR) != 0) {
            /* Already executable - launch directly without prompting */
            [self launchElfAndMonitor: fullPath];
            return YES;
          } else {
            /* Not executable - ask user to trust */
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText: @"Trust This Application?"];
            [alert setInformativeText: [NSString stringWithFormat: @"Do you want to trust and run the application \"%@\"?", [fullPath lastPathComponent]]];
            [alert addButtonWithTitle: @"Cancel"];
            [alert addButtonWithTitle: @"Trust and Run"];
            NSInteger resp = [alert runModal];
            if (resp == NSAlertSecondButtonReturn) {
              unsigned short newPerms = perms | S_IXUSR | S_IXGRP | S_IXOTH;
              NSDictionary *newAttrs = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedShort: newPerms]
                                                                   forKey: NSFilePosixPermissions];
              NSError *err2 = nil;
              BOOL ok = [fm setAttributes: newAttrs ofItemAtPath: fullPath error: &err2];
              if (!ok) {
                NSAlert *errAlert = [[[NSAlert alloc] init] autorelease];
                [errAlert setMessageText: @"Error"];
                [errAlert setInformativeText: [NSString stringWithFormat: @"Could not set executable permissions on \"%@\": %@", [fullPath lastPathComponent], [err2 localizedDescription]]];
                [errAlert addButtonWithTitle: @"OK"];
                [errAlert runModal];
                return NO;
              }

              [self launchElfAndMonitor: fullPath];
              return YES;
            } else {
              return NO;
            }
          }
        }
      }
    }
  }

  /* Check if this is a network virtual path first.
   *
   * The network branch should only handle (a) the /Network root itself, or
   * (b) a direct child of /Network that matches a known, unmounted network
   * service.  Deeper paths — i.e. real files and directories on an
   * already-mounted share — must fall through to regular file handling
   * (disk images, AVFS archives, application dispatch, etc.).  Otherwise
   * double-clicking e.g. /Network/host/images/foo.squashfs would dead-end
   * here instead of reaching the squashfs mounter below. */
  BOOL handleAsNetwork = NO;
  if ([NetworkFSNode isNetworkPath:fullPath]) {
    if ([fullPath isEqualToString:NetworkVirtualPath]) {
      handleAsNetwork = YES;
    } else {
      /* Only direct children of /Network are candidates for service dispatch. */
      NSArray *comps = [fullPath pathComponents];
      if ([comps count] == 3) {
        NSString *directChild = [fullPath lastPathComponent];
        NetworkServiceManager *mgr = [NetworkServiceManager sharedManager];
        for (NetworkServiceItem *it in [mgr allServices]) {
          if ([[it displayName] isEqualToString:directChild]) {
            handleAsNetwork = YES;
            break;
          }
        }
      }
    }
  }

  if (handleAsNetwork) {

    /* For network paths, we need to create the appropriate NetworkFSNode */
    NetworkFSNode *networkNode = nil;

    if ([fullPath isEqualToString:NetworkVirtualPath]) {
      /* This is the /Network root */
      networkNode = [NetworkFSNode networkRootNode];
    } else {
      /* This is a service under /Network - need to find the service item */
      NSString *serviceName = [fullPath lastPathComponent];
      
      NetworkServiceManager *manager = [NetworkServiceManager sharedManager];
      NSArray *services = [manager allServices];
      
      for (NetworkServiceItem *item in services) {
        if ([[item displayName] isEqualToString:serviceName]) {
          networkNode = [NetworkFSNode nodeWithServiceItem:item];
          break;
        }
      }
      
      if (!networkNode) {
        return NO;
      }
    }
    
    
    if ([networkNode isNetworkService]) {
      /* This is a network service item - try to open/mount it */
      NSString *mountPoint = nil;
      
      NS_DURING
        {
          mountPoint = [networkNode openNetworkService];
        }
      NS_HANDLER
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""), 
              [NSString stringWithFormat: @"Error mounting network service: %@", 
               [localException reason]],
                                            NSLocalizedString(@"OK", @""), 
                                            nil, 
                                            nil);
          return NO;
        }
      NS_ENDHANDLER
      
        
        if (mountPoint) {
          /* Successfully mounted - show viewer at mount point */
          [self newViewerAtPath:mountPoint];
          return YES;
        }
        /* If mount failed, openNetworkService already showed an error */
        return NO;
      } else if ([networkNode isNetworkRoot]) {
        /* This is the /Network root - just open a viewer */
        [self newViewerAtPath:fullPath];
        return YES;
      } else {
      }
  } else {
  }

  /* Check if this is a disk image file */
  NSString *ext = [[fullPath pathExtension] lowercaseString];
  if ([ext isEqualToString:@"dmg"]) {
    VolumeManager *volMgr = [VolumeManager sharedManager];
    NSString *mountPoint = [volMgr mountDMGFile:fullPath];
    if (mountPoint) {
      /* Wait for filesystem to populate before opening viewer */
      usleep(500000);  /* 0.5 second delay */
      [self newViewerAtPath:mountPoint];
      return YES;
    }
    return NO;
  } else if ([ext isEqualToString:@"iso"] || [ext isEqualToString:@"bin"] ||
             [ext isEqualToString:@"nrg"] || [ext isEqualToString:@"img"] ||
             [ext isEqualToString:@"mdf"] ||
             [ext isEqualToString:@"squashfs"] || [ext isEqualToString:@"sqsh"] ||
             [ext isEqualToString:@"sfs"]) {
    VolumeManager *volMgr = [VolumeManager sharedManager];
    NSString *mountPoint = [volMgr mountFuseisoImage:fullPath];
    if (mountPoint) {
      /* Wait for filesystem to populate before opening viewer */
      usleep(500000);  /* 0.5 second delay */
      [self newViewerAtPath:mountPoint];
      return YES;
    }
    return NO;
  }
  
  /* Check if this is an archive file that AVFS can handle.
   * Note: sshfs is given precedence for SSH/SFTP - those are handled
   * by the Network subsystem above. AVFS handles:
   * - Archives: tar, zip, rar, 7z, ar, cpio, lha, zoo, rpm, deb, jar, etc.
   * - Compressed: gz, bz2, xz, lzma, zstd, lzip
   * - Compressed archives: tar.gz, tar.bz2, tar.xz, tgz, tbz2, etc.
   */
  VolumeManager *volMgr = [VolumeManager sharedManager];
  if ([volMgr isAvfsSupportedFile:fullPath]) {
    NSString *virtualPath = [volMgr openAvfsArchive:fullPath];
    if (virtualPath) {
      /* Wait briefly for AVFS to process the archive */
      usleep(300000);  /* 0.3 second delay */
      [self newViewerAtPath:virtualPath];
      return YES;
    }
    /* If AVFS failed, fall through to try opening with an application */
  }

  aURL = nil;

  /* Mac Creator code lookup + Stationery handling */
  {
    GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: fullPath];
    if (md)
    {
      /* Creator code -> application mapping */
      if ([md creatorCode] != 0)
        {
          NSString *appPath = [self applicationForCreatorCode: [md creatorCode]];
          if (appPath)
            {
              return [[NSWorkspace sharedWorkspace] openFile: fullPath withApplication: appPath];
            }
        }

      /* Stationery: create a copy and open the copy instead */
      if ([md isStationery])
        {
          NSString *dir  = [fullPath stringByDeletingLastPathComponent];
          NSString *name = [fullPath lastPathComponent];
          NSString *ext  = [name pathExtension];
          NSString *base = [name stringByDeletingPathExtension];

          NSString *copyName;
          if ([ext length] > 0)
            copyName = [NSString stringWithFormat: @"%@ copy.%@", base, ext];
          else
            copyName = [NSString stringWithFormat: @"%@ copy", name];

          NSString *copyPath = [dir stringByAppendingPathComponent: copyName];
          NSFileManager *fileMgr = [NSFileManager defaultManager];

          if ([fileMgr fileExistsAtPath: copyPath])
            {
              NSUInteger n = 2;
              do {
                NSString *tryName;
                if ([ext length] > 0)
                  tryName = [NSString stringWithFormat: @"%@ copy %lu.%@", base, (unsigned long)n, ext];
                else
                  tryName = [NSString stringWithFormat: @"%@ copy %lu", name, (unsigned long)n];
                copyPath = [dir stringByAppendingPathComponent: tryName];
                n++;
              } while ([fileMgr fileExistsAtPath: copyPath]);
            }

          if ([fileMgr copyPath: fullPath toPath: copyPath handler: nil])
            {
              GSFileMetadata *copyMd = [GSFileMetadata metadataForFileAtPath: copyPath];
              if (!copyMd) copyMd = [[[GSFileMetadata alloc] init] autorelease];
              [copyMd setStationery: NO];
              [copyMd writeToFileAtPath: copyPath error: nil];

              return [self openFile: copyPath];
            }
          else
            {
              return NO;
            }
        }
    }
  }

  [ws getInfoForFile: fullPath application: &appName type: &type];

  /* If file is a plain file, check for ELF magic and handle executable prompting.

   * This mirrors how archives are intercepted earlier: special-case before
   * falling through to the generic "open with application" handler.
   */
  if (type == NSPlainFileType) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath: fullPath];
    if (fh) {
      NSData *hdr = [fh readDataOfLength:4];
      [fh closeFile];
      const unsigned char *bytes = (const unsigned char *)[hdr bytes];
      if ([hdr length] >= 4 && bytes[0] == 0x7f && bytes[1] == 'E' && bytes[2] == 'L' && bytes[3] == 'F') {
        /* Looks like an ELF binary. Check executable bit. */
        NSError *err = nil;
        NSDictionary *attrs = [fm attributesOfItemAtPath: fullPath error: &err];
        if (attrs) {
          NSNumber *permNum = [attrs objectForKey: NSFilePosixPermissions];
          unsigned short perms = [permNum unsignedShortValue];
          /* If owner execute is set, launch directly without prompting. */
          if ((perms & S_IXUSR) != 0) {
            [self launchElfAndMonitor: fullPath];
            return YES;
          } else {
            /* Owner execute not set, ask the user whether to trust and set it. */
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText: @"Trust This Application?"];
            [alert setInformativeText: [NSString stringWithFormat: @"Do you want to trust and run the application \"%@\"?", [fullPath lastPathComponent]]];
            [alert addButtonWithTitle: @"Cancel"];
            [alert addButtonWithTitle: @"Trust and Run"];
            NSInteger resp = [alert runModal];
            if (resp == NSAlertSecondButtonReturn) {
              unsigned short newPerms = perms | S_IXUSR | S_IXGRP | S_IXOTH;
              NSDictionary *newAttrs = [NSDictionary dictionaryWithObject: [NSNumber numberWithUnsignedShort: newPerms]
                                                                   forKey: NSFilePosixPermissions];
              NSError *err2 = nil;
              BOOL ok = [fm setAttributes: newAttrs ofItemAtPath: fullPath error: &err2];
              if (!ok) {
                NSAlert *errAlert = [[[NSAlert alloc] init] autorelease];
                [errAlert setMessageText: @"Error"];
                [errAlert setInformativeText: [NSString stringWithFormat: @"Could not set executable permissions on \"%@\": %@", [fullPath lastPathComponent], [err2 localizedDescription]]];
                [errAlert addButtonWithTitle: @"OK"];
                [errAlert runModal];
                return NO;
              }

              /* Launch and monitor the program in background; return YES since we handled it. */
              [self launchElfAndMonitor: fullPath];
              return YES;
            } else {
              /* User declined - do not open */
              return NO;
            }
          }
        }
      }
    }
  }

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


/**
 * Return the full path of the application to use for a given Mac
 * creator code (FourCharCode), or nil if no mapping is known.
 *
 * Uses a hardcoded dictionary of known creator code -> app name
 * mappings, then looks up the app via NSWorkspace. If no app is
 * found, returns nil so the caller falls through to extension-based
 * lookup.
 */
- (NSString *)applicationForCreatorCode:(GSOType)creatorCode
{
  static NSDictionary *creatorMap = nil;
  if (!creatorMap)
    {
      creatorMap = [[NSDictionary alloc] initWithObjectsAndKeys:
        @"TextEdit",                 @"ttxt",       // SimpleText / plain text
        @"LibreOffice",              @"MSWD",       // Microsoft Word
        @"LibreOffice",              @"exel",       // Microsoft Excel
        @"LibreOffice",              @"PPT3",       // Microsoft PowerPoint
        @"Preview",                  @"prvw",       // Preview (images / PDF)
        @"Preview",                  @"pdf ",       // PDF
        @"GV",                       @"xviz",       // GraphicConverter (XV preview)
        @"ImageMagick",              @"PNGf",       // PNG image
        @"ImageMagick",              @"JPEG",       // JPEG image
        @"ImageMagick",              @"GIFf",       // GIF image
        @"Terminal",                 @"trmx",       // Terminal
        @"TextEdit",                 @"R*ch",       // Rich text
        @"GWorkspace",               @"GWSP",       // GWorkspace itself
        nil];
    }

  /* Convert GSOType (32-bit FourCharCode) to a 4-character NSString. */
  char code[5] = {
    (char)((creatorCode >> 24) & 0xFF),
    (char)((creatorCode >> 16) & 0xFF),
    (char)((creatorCode >> 8) & 0xFF),
    (char)(creatorCode) & 0xFF,
    0
  };
  NSString *codeStr = [NSString stringWithCString: code encoding: NSASCIIStringEncoding];
  NSString *appName = [creatorMap objectForKey: codeStr];

  if (appName)
    {
      NSString *fullPath = [[NSWorkspace sharedWorkspace] fullPathForApplication: appName];
      return fullPath;
    }

  return nil;
}

- (void)launchElfAndMonitor:(NSString *)path
{
  /* Launch and monitor in background thread to avoid blocking UI. */
  [GWApplicationLauncher launchAndMonitor:path withArguments:nil];
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

- (void)newFolder:(id)sender
{
  NSString *basePath = nil;
  NSWindow *keyWindow = [NSApp keyWindow];
  
  // Try to get the path from the active viewer
  if (keyWindow && [keyWindow respondsToSelector: @selector(delegate)]) {
    id delegate = [(NSWindow *)keyWindow delegate];
    if (delegate && [delegate respondsToSelector: @selector(newFolder)]) {
      [delegate newFolder];
      return;
    }
  }
  
  // Fall back to using selected paths
  if (selectedPaths && [selectedPaths count] > 0) {
    basePath = [selectedPaths objectAtIndex: 0];
    
    // If it's a file, use its parent directory
    BOOL isDir = NO;
    if ([fm fileExistsAtPath: basePath isDirectory: &isDir] && !isDir) {
      basePath = [basePath stringByDeletingLastPathComponent];
    }
  }
  
  // If no path was determined, use home directory
  if (!basePath) {
    basePath = NSHomeDirectory();
  }
  
  [self newObjectAtPath: basePath isDirectory: YES];
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
    fileName = @"New Folder";
    operation = @"WorkspaceCreateDirOperation";
  } else {
    fileName = @"NewFile";
    operation = @"WorkspaceCreateFileOperation";
  }

  fullPath = [basePath stringByAppendingPathComponent: fileName];
  	
  if ([fm fileExistsAtPath: fullPath]) {    
    suff = 1;
    while (1) {    
      NSString *s = [fileName stringByAppendingFormat: @"-%i", suff];
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

- (void)openSelection:(id)sender
{
  [self openSelectionInNewViewer: YES];
}

- (void)openSelectionAsFolder:(id)sender
{
  if (selectedPaths && [selectedPaths count] == 1) {
    NSString *path = [selectedPaths objectAtIndex: 0];
    [self openSelectedPaths: [NSArray arrayWithObject: path] newViewer: YES];
  }
}

- (void)print:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  if (kwin && [kwin respondsToSelector: @selector(print:)]) {
    [kwin print: sender];
  }
}

- (void)performClose:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  NSLog(@"Workspace performClose: called, keyWindow=%@ (class=%@), sender=%@", 
        kwin, (kwin ? [kwin className] : @"nil"), sender);
  
  // Don't close the desktop or dock window. If either is the key window (or
  // there is no key window), find the first visible non-persistent window.
  if (kwin == nil || [kwin isKindOfClass: [GWDesktopWindow class]]
      || [kwin isKindOfClass: [GWDockWindow class]]) {
    NSLog(@"Workspace performClose: desktop/dock is key or no key window, searching for another window");
    NSArray *windows = [NSApp windows];
    for (NSWindow *win in windows) {
      if (![win isKindOfClass: [GWDesktopWindow class]]
          && ![win isKindOfClass: [GWDockWindow class]]
          && [win isVisible]) {
        kwin = win;
        break;
      }
    }
    // If we still have no suitable window, do nothing
    if (kwin == nil || [kwin isKindOfClass: [GWDesktopWindow class]]
        || [kwin isKindOfClass: [GWDockWindow class]]) {
      NSLog(@"Workspace performClose: no suitable window to close");
      return;
    }
  }
  
  if (kwin) {
    NSLog(@"Workspace performClose: closing window: %@ (class=%@)", 
          [kwin title], [kwin className]);
    [kwin close];
  } else {
  }
}

- (void)recycleFiles:(id)sender
{
  if (selectedPaths && [selectedPaths count] > 0) {
    [self moveToTrash];
  }
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
    NSString *umpath = [umountPaths objectAtIndex: i];
    
    // Don't allow ejecting root filesystem
    if ([self isRootFilesystem: umpath]) {
      NSString *err = NSLocalizedString(@"Error", @"");
      NSString *msg = NSLocalizedString(@"You cannot eject the root filesystem", @"");
      NSString *buttstr = NSLocalizedString(@"OK", @"");
      NSRunAlertPanel(err, msg, buttstr, nil, nil);
      continue;
    }
    
    /* Mark as expected unmount so the desktop does not show a spurious
       "Volume Removed Unexpectedly" warning. */
    [self noteUserInitiatedUnmountAtPath: umpath];
    NSDictionary *unmountInfo = @{ @"NSDevicePath": umpath };
    [[NSNotificationCenter defaultCenter]
      postNotificationName:NSWorkspaceWillUnmountNotification
                    object:ws
                  userInfo:unmountInfo];
    [ws unmountAndEjectDeviceAtPath: umpath];
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

- (void)noteUserInitiatedUnmountAtPath:(NSString *)path
{
  if (!path) return;
  if (recentUserUnmounts == nil) {
    recentUserUnmounts = [[NSMutableSet alloc] init];
  }
  [recentUserUnmounts addObject: path];
  
  /* Also mark on the desktop view directly, providing redundancy.
   * Use the class method to ensure we always get the valid singleton. */
  id deskMgr = [GWDesktopManager desktopManager];
  id deskView = [deskMgr desktopView];
  if ([deskView respondsToSelector: @selector(workspaceWillUnmountVolumeAtPath:)]) {
    [deskView workspaceWillUnmountVolumeAtPath: path];
  }
  
  /* Schedule cleanup after timeout */
  [self performSelector: @selector(_cleanupRecentUnmount:)
             withObject: path
             afterDelay: recentUserUnmountTimeout];
}

- (void)workspaceWillUnmountFromCLI:(NSNotification *)notif
{
  NSDictionary *userInfo = [notif userInfo];
  if (!userInfo) return;
  
  NSString *path = [userInfo objectForKey: @"GWUnmountPath"];
  if (!path) return;
  
  [self noteUserInitiatedUnmountAtPath: path];
}

- (void)workspaceDidUnmountFromCLI:(NSNotification *)notif
{
  NSDictionary *userInfo = [notif userInfo];
  if (!userInfo) return;

  NSString *path = [userInfo objectForKey: @"GWUnmountPath"];
  if (!path) return;

  [self noteUserInitiatedUnmountAtPath: path];

  /* Remove the desktop icon and update volumes list */
  [[dtopManager desktopView] workspaceDidUnmountVolumeAtPath: path];

  /* Also clear FSNode mount state */
  @try {
    FSNode *vnode = [FSNode nodeWithPath: path];
    if (vnode) {
      [vnode setMountPoint: NO];
    }
    [[FSNodeRep sharedInstance] removeVolumeAt: path];
  } @catch (NSException *e) {
  }
}

- (BOOL)isRecentUserUnmount:(NSString *)path
{
  return [recentUserUnmounts containsObject: path];
}

- (void)_cleanupRecentUnmount:(NSString *)path
{
  [recentUserUnmounts removeObject: path];
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
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  [vwrsManager hiddenFilesDidChange: paths];
  [dtopManager hiddenFilesDidChange: paths];
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

      // Start a timer to poll for fswatcher availability
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
    }
  }
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
	                    name: NSConnectionDidDieNotification
	                  object: connection];

  /* Defensive: only assert match if fswatcher is still valid */
  if (fswatcher && [fswatcher connectionForProxy] == connection) {
    RELEASE (fswatcher);
    fswatcher = nil;
  } else if (fswatcher) {
    /* Mismatch or fswatcher already released; clean up anyway */
    RELEASE (fswatcher);
    fswatcher = nil;
  } else {
    /* fswatcher already nil; connection died notification is stale */
    return;
  }

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
                    NSLocalizedString(@"OK", @""),
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

    if ([event isEqual: @"GWFileCreatedInWatchedDirectory"]
        && [fsnodeRep usesThumbnails]) {
      Thumbnailer *t = [Thumbnailer sharedThumbnailer];
      [t makeThumbnails: path];
      [t release];
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
	}
    }
}  
  
- (void)ddbdConnectionDidDie:(NSNotification *)notif
{
  id connection = [notif object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
						  name: NSConnectionDidDieNotification
						object: connection];

  // Don't access [ddbd connectionForProxy] here - the connection is already dead
  // and accessing the proxy can cause a segfault
  RELEASE (ddbd);
  ddbd = nil;
  
  NSRunAlertPanel(nil,
                  NSLocalizedString(@"ddbd connection died.", @""),
                  NSLocalizedString(@"OK", @""),
                  nil,
                  nil);                
}

- (BOOL)ddbdactive
{
  return ((terminating == NO) && (ddbd != nil));
}

- (void)ddbdInsertPath:(NSString *)path
{
  if (ddbd != nil && [[(NSDistantObject *)ddbd connectionForProxy] isValid]) {
    [ddbd insertPath: path];
  }
}

- (void)ddbdRemovePath:(NSString *)path
{
  if (ddbd != nil && [[(NSDistantObject *)ddbd connectionForProxy] isValid]) {
    [ddbd removePath: path];
  }
}

- (NSString *)ddbdGetAnnotationsForPath:(NSString *)path
{
  if (ddbd != nil && [[(NSDistantObject *)ddbd connectionForProxy] isValid]) {
    return [ddbd annotationsForPath: path];
  }
  
  return nil;
}

- (void)ddbdSetAnnotations:(NSString *)annotations
                   forPath:(NSString *)path
{
  if (ddbd != nil && [[(NSDistantObject *)ddbd connectionForProxy] isValid]) {
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
    fswnotifications = YES;
    
    // Register all queued watchers
    if ([watchedPaths count] > 0) {
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
    
    return;
  }
  
  if ([[NSDate date] compare:deadline] != NSOrderedAscending) {
    [timer invalidate];
    fswnotifications = NO;
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

- (void)showAboutThisComputer:(id)sender
{
  [[AboutController sharedController] showAboutWindow:sender];
}

- (void)showInfo:(id)sender
{
  GSInfoPanel *panel = [[GSInfoPanel alloc] initWithDictionary: nil];
  [panel setReleasedWhenClosed: YES];
  [panel setTitle: [NSString stringWithFormat: _(@"About %@"),
                             [[NSProcessInfo processInfo] processName]]];
  [panel orderFront: self];
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

- (void)workspaceHelp:(id)sender
{
  NSAlert *alert = [NSAlert new];
  [alert setMessageText: _(@"Workspace Help")];
  [alert setInformativeText: _(@"You can get help by pressing the Option key (the mouse cursor becomes a question mark) and then clicking on any user interface element.")];
  [alert addButtonWithTitle: _(@"OK")];
  [alert runModal];
  RELEASE (alert);
}

- (void)openGershwinHelp:(id)sender
{
  NSString *url = @"https://github.com/gershwin-desktop/gershwin-desktop/wiki";
  NSTask *task = [NSTask new];
  [task setLaunchPath: @"/usr/bin/xdg-open"];
  [task setArguments: [NSArray arrayWithObject: url]];
  
  NSError *error = nil;
  if (![task launchAndReturnError: &error]) {
    NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                    [NSString stringWithFormat: _(@"Could not open URL:\n\n%@"), url], 
                    _(@"OK"), nil, nil);
  }
  RELEASE (task);
}

- (void)openFeedback:(id)sender
{
  NSString *url = @"https://github.com/orgs/gershwin-desktop/discussions";
  NSTask *task = [NSTask new];
  [task setLaunchPath: @"/usr/bin/xdg-open"];
  [task setArguments: [NSArray arrayWithObject: url]];
  
  NSError *error = nil;
  if (![task launchAndReturnError: &error]) {
    NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                    [NSString stringWithFormat: _(@"Could not open URL:\n\n%@"), url], 
                    _(@"OK"), nil, nil);
  }
  RELEASE (task);
}

- (void)openLegal:(id)sender
{
  NSString *url = @"https://raw.githubusercontent.com/gershwin-desktop/gershwin-workspace/refs/heads/main/COPYING";
  NSTask *task = [NSTask new];
  [task setLaunchPath: @"/usr/bin/xdg-open"];
  [task setArguments: [NSArray arrayWithObject: url]];
  
  NSError *error = nil;
  if (![task launchAndReturnError: &error]) {
    NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                    [NSString stringWithFormat: _(@"Could not open URL:\n\n%@"), url], 
                    _(@"OK"), nil, nil);
  }
  RELEASE (task);
}

- (void)goToComputer:(id)sender
{
  // Go to /
  [self openSelectedPaths: [NSArray arrayWithObject: path_separator()] newViewer: YES];
}

- (void)goToHome:(id)sender
{
  NSString *homePath = NSHomeDirectory();
  [self openSelectedPaths: [NSArray arrayWithObject: homePath] newViewer: YES];
}

- (void)goToApplications:(id)sender
{
  NSArray *appPaths = NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSSystemDomainMask, YES);
  if ([appPaths count] > 0) {
    [self openSelectedPaths: [NSArray arrayWithObject: [appPaths objectAtIndex: 0]] newViewer: YES];
  }
}

- (void)navigateToDirectory:(NSString *)dirPath withLabel:(NSString *)label
{
  // Check if directory exists
  BOOL isDir = NO;
  if (![fm fileExistsAtPath: dirPath isDirectory: &isDir] || !isDir) {
    // Try to create the directory if it doesn't exist
    NSError *error = nil;
    if (![fm createDirectoryAtPath: dirPath withIntermediateDirectories: YES attributes: nil error: &error]) {
      NSAlert *alert = [NSAlert alertWithError: error];
      [alert setMessageText: [NSString stringWithFormat: _(@"Cannot access %@"), label]];
      [alert setInformativeText: [NSString stringWithFormat: _(@"Could not create or access the %@ folder"), label]];
      [alert runModal];
      return;
    }
  }
  
  // Navigate to the directory
  [self openSelectedPaths: [NSArray arrayWithObject: dirPath] newViewer: YES];
}

- (void)goToDocuments:(id)sender
{
  NSString *documentsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Documents"];
  [self navigateToDirectory: documentsPath withLabel: _(@"Documents")];
}

- (void)goToDesktop:(id)sender
{
  NSString *desktopPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Desktop"];
  [self navigateToDirectory: desktopPath withLabel: _(@"Desktop")];
}

- (void)goToDownloads:(id)sender
{
  NSString *downloadsPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Downloads"];
  [self navigateToDirectory: downloadsPath withLabel: _(@"Downloads")];
}

- (void)goToMusic:(id)sender
{
  NSString *musicPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Music"];
  [self navigateToDirectory: musicPath withLabel: _(@"Music")];
}

- (void)goToPictures:(id)sender
{
  NSString *picturesPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Pictures"];
  [self navigateToDirectory: picturesPath withLabel: _(@"Pictures")];
}

- (void)goToVideos:(id)sender
{
  NSString *videosPath = [NSHomeDirectory() stringByAppendingPathComponent: @"/Videos"];
  [self navigateToDirectory: videosPath withLabel: _(@"Videos")];
}

- (void)goToNetwork:(id)sender
{
  
  /* Start network service discovery if not already running */
  NetworkServiceManager *manager = [NetworkServiceManager sharedManager];

  /* If mDNS/DNS-SD support is not available, show a helpful alert and avoid
     opening the network viewer to prevent crashes on systems without dns-sd. */
  if (![manager isMDNSAvailable]) {
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:@"Service Discovery: Not Available"];
    [alert setInformativeText:@"mDNS/DNS-SD support is not available on this system.\nBuild GNUstep with libdns_sd to enable network service discovery\nand/or start the daemon needed for discovery."];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return;
  }

  if (![manager isBrowsing]) {
    [manager startBrowsing];
  }
  
  /* Create a NetworkFSNode for the /Network virtual location */
  NetworkFSNode *networkNode = [NetworkFSNode networkRootNode];
  
  /* Respect the default viewer mode (Spatial vs Browsing) */
  if ([self defaultViewerType] == SPATIAL) {
    [vwrsManager viewerOfType: SPATIAL
                     showType: nil
                      forNode: networkNode
                showSelection: NO
               closeOldViewer: nil
                     forceNew: NO];
  } else {
    [vwrsManager viewerForNode: networkNode
                      showType: 0
                 showSelection: NO
                      forceNew: YES
                       withKey: @"network_viewer"];
  }
}


- (void)goToFolder:(id)sender
{
  /* Start with an empty field so the user types the path (or relies on the
   * grey typeahead suggestion); no pre-filled home directory. */
  GWDialog *dialog = [[GWDialog alloc] initWithTitle: _(@"Go to Folder:")
                                             editText: @""
                                          switchTitle: nil];
  [dialog setValidator: ^BOOL(NSString *path) {
    if ([path length] == 0) return NO;
    BOOL isDir = NO;
    return ([fm fileExistsAtPath: [path stringByExpandingTildeInPath]
                     isDirectory: &isDir] && isDir);
  }];

  if ([dialog runModal] == NSAlertDefaultReturn) {
    NSString *path = [dialog getEditFieldText];
    if ([path length] > 0) {
      [self openSelectedPaths: [NSArray arrayWithObject: [path stringByExpandingTildeInPath]]
                    newViewer: YES];
    }
  }

  RELEASE (dialog);
}

- (void)performMountInBackground:(NSDictionary *)mountInfo
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NetworkServiceItem *serviceItem = [mountInfo objectForKey:@"serviceItem"];
  NSPanel *progressPanel = [mountInfo objectForKey:@"progressPanel"];
  NSString *hostname = [mountInfo objectForKey:@"hostname"];
  id passwordObj = [mountInfo objectForKey:@"password"];
  NSString *password = (passwordObj != [NSNull null]) ? passwordObj : nil;
  NSString *username = [serviceItem username];
  NSString *scheme = [mountInfo objectForKey:@"scheme"];
  
  /* Perform the mount operation based on scheme */
  NetworkVolumeManager *volumeManager = [NetworkVolumeManager sharedManager];
  NSString *mountPoint = nil;
  
  if ([scheme isEqualToString:@"sftp"]) {
    mountPoint = [volumeManager mountSFTPService:serviceItem
                                        username:username
                                        password:password];
  } else if ([scheme isEqualToString:@"webdav"] || [scheme isEqualToString:@"webdavs"]) {
    mountPoint = [volumeManager mountWebDAVService:serviceItem
                                          username:username
                                          password:password];
  }
  
  /* Get any detailed error message from the volume manager */
  NSString *errorMessage = mountPoint ? nil : [volumeManager lastErrorMessage];
  
  /* Return to main thread to update UI */
  dispatch_async(dispatch_get_main_queue(), ^{
    NSMutableDictionary *resultDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 mountPoint ? mountPoint : [NSNull null], @"mountPoint",
                                 progressPanel, @"progressPanel",
                                 hostname, @"hostname",
                                 nil];
    if (errorMessage) {
      [resultDict setObject:errorMessage forKey:@"errorMessage"];
    }
    [self finishMountOperation:resultDict];
  });
  
  [mountInfo release];
  [pool release];
}

- (void)finishMountOperation:(NSDictionary *)result
{
  NSPanel *progressPanel = [result objectForKey:@"progressPanel"];
  id mountPointObj = [result objectForKey:@"mountPoint"];
  NSString *hostname = [result objectForKey:@"hostname"];
  NSString *mountPoint = (mountPointObj != [NSNull null]) ? mountPointObj : nil;
  
  [progressPanel close];
  [progressPanel release];
  
  if (mountPoint) {
    /* Successfully mounted - open it in a viewer */
    [self openSelectedPaths:[NSArray arrayWithObject:mountPoint] newViewer:YES];
  } else {
    /* Show a detailed error from the mount operation, or a generic fallback */
    NSString *errorMessage = [result objectForKey:@"errorMessage"];
    if (errorMessage && [errorMessage length] > 0) {
      NSRunAlertPanel(NSLocalizedString(@"Connection Failed", @""),
                      @"%@",
                      _(@"OK"), nil, nil,
                      errorMessage);
    } else {
      NSRunAlertPanel(NSLocalizedString(@"Connection Failed", @""),
                      [NSString stringWithFormat:
                       NSLocalizedString(@"Could not connect to %@\n\nCheck the hostname and try again.", @""),
                       hostname],
                      _(@"OK"), nil, nil);
    }
  }
}

- (void)connectToServer:(id)sender
{
  GWDialog *dialog = [[GWDialog alloc] initWithTitle: _(@"Connect to Server:") 
                                             editText: @"sftp://"
                                          switchTitle: nil];
  NSModalResponse response = [dialog runModal];
  
  if (response == NSAlertDefaultReturn) {
    NSString *urlString = [dialog getEditFieldText];
    if (urlString && [urlString length] > 0) {
      /* Parse the URL */
      NSURL *url = [NSURL URLWithString:urlString];
      if (!url) {
        NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                        _(@"Invalid URL format"), 
                        _(@"OK"), nil, nil);
        RELEASE(dialog);
        return;
      }
      
      NSString *scheme = [[url scheme] lowercaseString];
      if (!scheme) {
        NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                        _(@"URL must include a scheme (sftp://, webdav://, webdavs://)"), 
                        _(@"OK"), nil, nil);
        RELEASE(dialog);
        return;
      }
      
      /* Check for supported schemes */
      BOOL isSFTP = [scheme isEqualToString:@"sftp"];
      BOOL isWebDAV = [scheme isEqualToString:@"webdav"];
      BOOL isWebDAVS = [scheme isEqualToString:@"webdavs"];
      
      if (!isSFTP && !isWebDAV && !isWebDAVS) {
        NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                        _(@"Supported URL schemes: sftp://, webdav://, webdavs://"), 
                        _(@"OK"), nil, nil);
        RELEASE(dialog);
        return;
      }
      
      NSString *hostname = [url host];
      if (!hostname || [hostname length] == 0) {
        NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                        _(@"URL must include a hostname"), 
                        _(@"OK"), nil, nil);
        RELEASE(dialog);
        return;
      }
      
      /* Extract components */
      NSString *username = [url user];
      NSNumber *portNum = [url port];
      /* Default port: 22 for SFTP, 80 for WebDAV, 443 for WebDAVS */
      int defaultPort = isSFTP ? 22 : (isWebDAVS ? 443 : 80);
      int port = portNum ? [portNum intValue] : defaultPort;
      NSString *remotePath = [url path];
      NSString *password = nil;
      
      /* If no username in URL, prompt for credentials NOW (on main thread) */
      if (!username || [username length] == 0) {
        
        NSString *dialogTitle = isSFTP ? NSLocalizedString(@"Connect to SFTP Server", @"")
                                       : NSLocalizedString(@"Connect to WebDAV Server", @"");
        NSDictionary *creds = [NetworkVolumeManager runCredentialsPanelWithTitle:dialogTitle
                                                                        hostname:hostname];
        if (creds) {
          username = [[creds objectForKey:@"username"] retain];
          password = [[creds objectForKey:@"password"] retain];
        } else {
          RELEASE(dialog);
          return;
        }
        
        if (!username || [username length] == 0) {
          [password release];
          RELEASE(dialog);
          return;
        }
        
        [username autorelease];
        
        /* Keep password for mount (will autorelease later) */
        if (password && [password length] > 0) {
          [password autorelease];
        } else {
          [password release];
          password = nil;
        }
      }
      
      /* Create a NetworkServiceItem for manual connection */
      NetworkServiceItem *serviceItem = [[NetworkServiceItem alloc] init];
      serviceItem.hostName = hostname;
      serviceItem.port = port;
      serviceItem.name = [NSString stringWithFormat:@"%@", hostname];
      
      /* Set the appropriate service type based on URL scheme */
      if (isSFTP) {
        serviceItem.type = @"_sftp-ssh._tcp.";
      } else if (isWebDAVS) {
        serviceItem.type = @"_webdavs._tcp.";
      } else {
        serviceItem.type = @"_webdav._tcp.";
      }
      serviceItem.domain = @"local.";          /* Default domain */
      if (username && [username length] > 0) {
        [serviceItem setUsername:username];
      }
      if (remotePath && [remotePath length] > 0) {
        [serviceItem setRemotePath:remotePath];
      }
      
      /* Show a connecting dialog */
      NSPanel *progressPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 300, 100)
                                                          styleMask:NSTitledWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
      [progressPanel setTitle:@"Connecting..."];
      [progressPanel center];
      
      NSTextField *progressLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 40, 260, 40)];
      [progressLabel setStringValue:[NSString stringWithFormat:@"Connecting to %@...", hostname]];
      [progressLabel setBezeled:NO];
      [progressLabel setDrawsBackground:NO];
      [progressLabel setEditable:NO];
      [progressLabel setSelectable:NO];
      [progressLabel setAlignment:NSCenterTextAlignment];
      [[progressPanel contentView] addSubview:progressLabel];
      [progressLabel release];
      
      NSProgressIndicator *spinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(130, 15, 40, 40)];
      [spinner setStyle:NSProgressIndicatorSpinningStyle];
      [spinner setDisplayedWhenStopped:NO];
      [spinner startAnimation:nil];
      [[progressPanel contentView] addSubview:spinner];
      [spinner release];
      
      [progressPanel orderFront:nil];
      
      /* Create a dictionary to pass data to the background thread */
      NSDictionary *mountInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                 serviceItem, @"serviceItem",
                                 progressPanel, @"progressPanel",
                                 hostname, @"hostname",
                                 password ? password : [NSNull null], @"password",
                                 scheme, @"scheme",
                                 nil];
      [mountInfo retain];
      
      /* Mount on a background thread to keep UI responsive */
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self performMountInBackground:mountInfo];
      });
      
      [serviceItem release];
    }
  }
  
  RELEASE (dialog);
}

- (void)goToUtilities:(id)sender
{
  NSString *utilitiesPath = @"/System/Applications/Utilities";
  BOOL isDir = NO;
  
  if ([fm fileExistsAtPath: utilitiesPath isDirectory: &isDir] && isDir) {
    [self openSelectedPaths: [NSArray arrayWithObject: utilitiesPath] newViewer: YES];
  } else {
    NSRunAlertPanel(NSLocalizedString(@"Error", @""), 
                    [NSString stringWithFormat: _(@"The Utilities folder could not be found at:\n\n%@"), utilitiesPath], 
                    _(@"OK"), nil, nil);
  }
}

- (void)goBackwardInHistory:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  if (kwin && [vwrsManager hasViewerWithWindow: kwin]) {
    GWViewerWindow *viewer = [vwrsManager viewerWithWindow: kwin];
    if (viewer) {
      [viewer goBackwardInHistory:sender];
    }
  }
}

- (void)goForwardInHistory:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  if (kwin && [vwrsManager hasViewerWithWindow: kwin]) {
    GWViewerWindow *viewer = [vwrsManager viewerWithWindow: kwin];
    if (viewer) {
      [viewer goForwardInHistory:sender];
    }
  }
}

- (void)selectAllInViewer:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin && [vwrsManager hasViewerWithWindow: kwin])
    {
      id viewer = [vwrsManager viewerWithWindow: kwin];
      if (viewer)
        {
          [viewer selectAllInViewer];
        }
    }
  else if (kwin && [dtopManager hasWindow: kwin])
    {
      [[dtopManager desktopView] selectAll];
    }
  else if (kwin)
    {
      // Fallback for dialogs with text fields (e.g., Run, Go to Folder).
      // NSTextView and the field editor both respond to selectAll:.
      NSResponder *fr = [kwin firstResponder];
      if ([fr respondsToSelector: @selector(selectAll:)])
        {
          [fr selectAll: sender];
        }
    }
}

- (void)toggleFullScreen:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  if (kwin && [vwrsManager hasViewerWithWindow: kwin]) {
    GWViewerWindow *viewer = [vwrsManager viewerWithWindow: kwin];
    if (viewer) {
      [viewer toggleFullScreen:sender];
    }
  }
}

- (void)openParentFolder:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  
  if (kwin && [vwrsManager hasViewerWithWindow: kwin]) {
    GWViewer *viewer = [vwrsManager viewerWithWindow: kwin];
    FSNode *baseNode = [viewer baseNode];
    FSNode *parentNode = [baseNode parent];
    
    if (parentNode) {
      [self openSelectedPaths: [NSArray arrayWithObject: [parentNode path]] newViewer: YES];
    } else {
      NSRunAlertPanel(NSLocalizedString(@"Error", @""), _(@"Already at the root directory"), _(@"OK"), nil, nil);
    }
  }
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

- (void)showFinder:(id)sender
{
  [finder activate];   
}

- (void)cut:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];

  if (kwin)
    {
      if ([vwrsManager hasViewerWithWindow: kwin]
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
    if ([vwrsManager hasViewerWithWindow: kwin]
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
    if ([vwrsManager hasViewerWithWindow: kwin]
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

- (void)emptyTrash:(id)sender
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

      [opinfo setObject: @"WorkspaceemptyTrashOperation" forKey: @"operation"];
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

- (void)updateOpenWithMenu
{
  if (openWithMenu == nil)
    return;

  while ([openWithMenu numberOfItems] > 0)
    [openWithMenu removeItemAtIndex: 0];

  if (selectedPaths == nil || [selectedPaths count] == 0)
    return;

  NSString *firstext = [[[selectedPaths objectAtIndex: 0] pathExtension] lowercaseString];
  if ([firstext length] == 0)
    {
      firstext = [[[selectedPaths objectAtIndex: 0] lastPathComponent] lowercaseString];
    }
  for (NSUInteger i = 1; i < [selectedPaths count]; i++)
    {
      NSString *ext = [[[selectedPaths objectAtIndex: i] pathExtension] lowercaseString];
      if ([ext length] == 0)
        {
          ext = [[[selectedPaths objectAtIndex: i] lastPathComponent] lowercaseString];
        }
      if ([ext isEqual: firstext] == NO)
        return;
    }

  NSDictionary *apps = [ws infoForExtension: firstext];
  if (apps == nil || [apps count] == 0)
    return;

  NSEnumerator *appEnum = [[apps allKeys] objectEnumerator];
  NSString *key;
  while ((key = [appEnum nextObject]))
    {
      NSMenuItem *appItem = [NSMenuItem new];
      key = [key stringByDeletingPathExtension];
      [appItem setTitle: key];
      [appItem setTarget: self];
      [appItem setAction: @selector(openSelectionWithApp:)];
      [appItem setRepresentedObject: key];
      [appItem setEnabled: YES];
      [openWithMenu addItem: appItem];
      RELEASE (appItem);
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
  // Always add to watchedPaths first - this queues it for later registration if fswatcher isn't available yet
  [watchedPaths addObject: path];
  
  // Only attempt to register with fswatcher if notifications are enabled
  if (fswnotifications) {
    [self connectFSWatcher];
    if (fswatcher && [[(NSDistantObject *)fswatcher connectionForProxy] isValid]) {
      [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
    }
  }
  // If fswnotifications is NO, the path is queued in watchedPaths and will be 
  // registered when fswatcher becomes available via _probeFSWatcherTimer
}

- (void)removeWatcherForPath:(NSString *)path
{
  [watchedPaths removeObject: path];

  if (fswnotifications) {
    [self connectFSWatcher];
    if (fswatcher && [[(NSDistantObject *)fswatcher connectionForProxy] isValid]) {
      [fswatcher client: (id <FSWClientProtocol>)self removeWatcherForPath: path];
    }
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

- (BOOL)isRootFilesystem:(NSString *)path
{
  return [path isEqualToString: @"/"];
}

- (BOOL)pasteboardHasValidContent
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  return ([[pb types] containsObject: NSFilenamesPboardType]);
}

- (NSMenu *)emptySpaceContextMenuForViewer:(id)viewer
{
  NSMenu *menu;
  NSMenuItem *menuItem;

  menu = [[NSMenu alloc] initWithTitle: @""];

  // New Folder
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"New Folder", @"")];
  [menuItem setTarget: viewer];
  [menuItem setAction: @selector(newFolder:)];
  [menu addItem: menuItem];
  RELEASE (menuItem);

  [menu addItem: [NSMenuItem separatorItem]];

  // Paste (if applicable)
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"Paste", @"")];
  [menuItem setTarget: self];
  [menuItem setAction: @selector(paste:)];
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [menuItem setEnabled: ([[pb types] containsObject: NSFilenamesPboardType])];
  [menu addItem: menuItem];
  RELEASE (menuItem);

  [menu addItem: [NSMenuItem separatorItem]];

  // Clean Up
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"Clean Up", @"")];
  [menuItem setTarget: self];
  [menuItem setAction: @selector(cleanUp:)];
  [menu addItem: menuItem];
  RELEASE (menuItem);

  // Clean Up By submenu
  {
    NSMenuItem *cleanUpByItem = [NSMenuItem new];
    [cleanUpByItem setTitle: NSLocalizedString(@"Clean Up By", @"")];
    NSMenu *submenu = [[NSMenu alloc] initWithTitle: @""];
    NSArray *opts = @[@"Name", @"Kind", @"Date Modified", @"Size"];
    NSArray *tags = @[@0, @1, @2, @3];
    NSUInteger oi;
    for (oi = 0; oi < [opts count]; oi++)
      {
        NSMenuItem *it = [NSMenuItem new];
        [it setTitle: NSLocalizedString([opts objectAtIndex: oi], @"")];
        [it setTarget: self];
        [it setAction: @selector(cleanUpBy:)];
        [it setTag: [[tags objectAtIndex: oi] integerValue]];
        [submenu addItem: it];
        RELEASE (it);
      }
    [cleanUpByItem setSubmenu: submenu];
    RELEASE (submenu);
    [menu addItem: cleanUpByItem];
    RELEASE (cleanUpByItem);
  }

  return [menu autorelease];
}

- (NSMenu *)contextMenuForNodes:(NSArray *)nodes
                     openTarget:(id)openTarget
                  openWithTarget:(id)openWithTarget
                     infoTarget:(id)infoTarget
                duplicateTarget:(id)duplicateTarget
                  recycleTarget:(id)recycleTarget
                    ejectTarget:(id)ejectTarget
                     openAction:(SEL)openAction
                duplicateAction:(SEL)duplicateAction
                  recycleAction:(SEL)recycleAction
                    ejectAction:(SEL)ejectAction
               includeOpenWith:(BOOL)includeOpenWith
{
  NSMenu *menu;
  NSMenuItem *menuItem;
  NSString *firstext;
  NSDictionary *apps;
  NSEnumerator *app_enum;
  id key;
  NSUInteger i;
  BOOL isMountPoint = NO;
  BOOL allMountPoints = YES;
  
  if (!nodes || [nodes count] == 0) {
    return nil;
  }
  
  firstext = [[[nodes objectAtIndex: 0] path] pathExtension];
  if ([firstext length] == 0)
    {
      firstext = [[[[nodes objectAtIndex: 0] path] lastPathComponent] lowercaseString];
    }
  
  // Check if any selected items are mount points
  for (i = 0; i < [nodes count]; i++) {
    FSNode *node = [nodes objectAtIndex: i];
    if ([node isMountPoint]) {
      isMountPoint = YES;
    } else {
      allMountPoints = NO;
    }
  }
  
  menu = [[NSMenu alloc] initWithTitle: @""];
  
  // Open
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"Open", @"")];
  [menuItem setTarget: openTarget];
  [menuItem setAction: openAction];
  [menuItem setEnabled: YES];
  [menu addItem: menuItem];
  RELEASE (menuItem);
  
  // Open as Folder - only for bundles (packages)
  {
    BOOL allBundles = YES;
    for (i = 0; i < [nodes count]; i++) {
      if ([[nodes objectAtIndex: i] isPackage] == NO) {
        allBundles = NO;
        break;
      }
    }
    if (allBundles) {
      menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Open as Folder", @"")];
      [menuItem setTarget: openTarget];
      [menuItem setAction: @selector(openSelectionAsFolder:)];
      [menuItem setEnabled: YES];
      [menu addItem: menuItem];
      RELEASE (menuItem);
    }
  }
  
  // Open With submenu - only for files with same extension
  if (includeOpenWith) {
    BOOL canShowOpenWith = YES;
    for (i = 0; i < [nodes count]; i++) {
      FSNode *node = [nodes objectAtIndex: i];
      NSString *ext = [[node path] pathExtension];
      if ([ext length] == 0)
        {
          ext = [[[node path] lastPathComponent] lowercaseString];
        }
      
      if ([ext isEqual: firstext] == NO) {
        canShowOpenWith = NO;
        break;
      }
      
      if ([node isDirectory] == NO) {
        if ([node isPlain] == NO) {
          canShowOpenWith = NO;
          break;
        }
      } else {
        if (([node isPackage] == NO) || [node isApplication]) {
          canShowOpenWith = NO;
          break;
        }
      }
    }
    
    if (canShowOpenWith) {
      menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Open With", @"")];
      [menuItem setEnabled: YES];
      NSMenu *owMenu = [[NSMenu alloc] initWithTitle: @""];
      
      apps = [[NSWorkspace sharedWorkspace] infoForExtension: firstext];
      app_enum = [[apps allKeys] objectEnumerator];
      
      while ((key = [app_enum nextObject])) {
        NSMenuItem *appItem = [NSMenuItem new];
        key = [key stringByDeletingPathExtension];
        [appItem setTitle: key];
        [appItem setTarget: openWithTarget];
        [appItem setAction: @selector(openSelectionWithApp:)];
        [appItem setRepresentedObject: key];
        [appItem setEnabled: YES];
        [owMenu addItem: appItem];
        RELEASE (appItem);
      }
      
      [menuItem setSubmenu: owMenu];
      RELEASE (owMenu);
      [menu addItem: menuItem];
      RELEASE (menuItem);
    }
  }
  
  [menu addItem: [NSMenuItem separatorItem]];
  
  // Copy
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"Copy", @"")];
  [menuItem setTarget: [Workspace gworkspace]];
  [menuItem setAction: @selector(copy:)];
  [menuItem setEnabled: YES];
  [menu addItem: menuItem];
  RELEASE (menuItem);

  [menu addItem: [NSMenuItem separatorItem]];
  
  // Get Info
  menuItem = [NSMenuItem new];
  [menuItem setTitle: NSLocalizedString(@"Get Info", @"")];
  [menuItem setTarget: infoTarget];
  [menuItem setAction: @selector(showAttributesInspector:)];
  [menuItem setEnabled: YES];
  [menu addItem: menuItem];
  RELEASE (menuItem);

  // Label submenu + Compress or Extract — only for non-mount-points
  if (!isMountPoint) {
    [menu addItem: [NSMenuItem separatorItem]];
    menuItem = [NSMenuItem new];
    [menuItem setTitle: NSLocalizedString(@"Label", @"")];
    [menuItem setEnabled: YES];
    [menuItem setSubmenu: [self labelColorSubmenu]];
    [menu addItem: menuItem];
    RELEASE (menuItem);

    // Check if the single selected item is an archive supported by libarchive
    BOOL isArchiveFile = NO;
    if ([nodes count] == 1) {
      FSNode *singleNode = [nodes objectAtIndex: 0];
      NSString *ext = [[[singleNode path] pathExtension] lowercaseString];
      if ([GWMetaArchive isArchiveExtension: ext])
        isArchiveFile = YES;
    }

    if (isArchiveFile) {
      // Extract — single archive selected
      [menu addItem: [NSMenuItem separatorItem]];
      menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Extract", @"")];
      [menuItem setTarget: [Workspace gworkspace]];
      [menuItem setAction: @selector(extractArchive:)];
      [menuItem setEnabled: YES];
      [menu addItem: menuItem];
      RELEASE (menuItem);
    } else {
      // Compress — any non-zip selection
      [menu addItem: [NSMenuItem separatorItem]];
      menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Compress", @"")];
      [menuItem setTarget: [Workspace gworkspace]];
      [menuItem setAction: @selector(compressFiles:)];
      [menuItem setEnabled: YES];
      [menu addItem: menuItem];
      RELEASE (menuItem);
    }
  }

  // Only show Duplicate if not all mount points
  if (!allMountPoints) {
    [menu addItem: [NSMenuItem separatorItem]];
    
    // Duplicate
    menuItem = [NSMenuItem new];
    [menuItem setTitle: NSLocalizedString(@"Duplicate", @"")];
    [menuItem setTarget: duplicateTarget];
    [menuItem setAction: duplicateAction];
    [menuItem setEnabled: YES];
    [menu addItem: menuItem];
    RELEASE (menuItem);
    
    [menu addItem: [NSMenuItem separatorItem]];
  }
  
  // Show Eject for mount points, Move to Recycler for regular files
  if (isMountPoint) {
    BOOL hasRootFS = NO;
    NSMutableArray *formatCandidates = [NSMutableArray array];
    // Check if any selected item is the root filesystem
    for (i = 0; i < [nodes count]; i++) {
      FSNode *node = [nodes objectAtIndex: i];
      if ([self isRootFilesystem: [node path]]) {
        hasRootFS = YES;
        break;
      }

      if (allMountPoints && [node isMountPoint]) {
        [formatCandidates addObject:[node path]];
      }
    }
    
    menuItem = [NSMenuItem new];
    [menuItem setTitle: NSLocalizedString(@"Eject", @"")];
    [menuItem setTarget: ejectTarget];
    [menuItem setAction: ejectAction];
    [menuItem setEnabled: !hasRootFS];
    [menu addItem: menuItem];
    RELEASE (menuItem);

    if ([formatCandidates count] > 0) {
      [menu addItem: [NSMenuItem separatorItem]];

      menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Format Disk...", @"")];
      [menuItem setTarget: self];
      [menuItem setAction: @selector(formatSelectedMountPoints:)];
      [menuItem setRepresentedObject: formatCandidates];
      [menuItem setEnabled: !hasRootFS];
      [menu addItem: menuItem];
      RELEASE (menuItem);
    }
  } else {
    // Move to Recycler
    BOOL canRecycle = YES;
    
    // Check if items are in trash or not writable
    for (i = 0; i < [nodes count]; i++) {
      FSNode *node = [nodes objectAtIndex: i];
      NSString *nodePath = [node path];
      
      // Disable if item is in trash
      if ([nodePath hasPrefix: trashPath]) {
        canRecycle = NO;
        break;
      }
      
      // Disable if item is not writable
      if ([node isWritable] == NO) {
        canRecycle = NO;
        break;
      }
    }
    
    menuItem = [NSMenuItem new];
    [menuItem setTitle: NSLocalizedString(@"Move to Recycler", @"")];
    [menuItem setTarget: recycleTarget];
    [menuItem setAction: recycleAction];
    [menuItem setEnabled: canRecycle];
    [menu addItem: menuItem];
    RELEASE (menuItem);
  }
  
  return AUTORELEASE (menu);
}

- (id)workspaceApplication
{
  return [Workspace gworkspace];
}

/*
 * =================================================================
 * Label Color support
 * =================================================================
 */

/**
 * Build and return a "Label" submenu with items for each Finder label
 * colour (None + 7 colours). Each item's tag is set to the GSFileLabel
 * value (0-7), target is [Workspace gworkspace], and action is
 * setLabelForNodes:.
 */
- (NSMenu *)labelColorSubmenu
{
  NSMenu *labelMenu = [[NSMenu alloc] initWithTitle: @""];

  /* Label names in the shared GSFileLabel / DSStoreLabelColor order:
   * 0=None, 1=Red, 2=Orange, 3=Yellow, 4=Green, 5=Blue, 6=Purple, 7=Grey. */
  NSString *labelNames[] = {
    NSLocalizedString(@"None", @""),
    NSLocalizedString(@"Red", @""),
    NSLocalizedString(@"Orange", @""),
    NSLocalizedString(@"Yellow", @""),
    NSLocalizedString(@"Green", @""),
    NSLocalizedString(@"Blue", @""),
    NSLocalizedString(@"Purple", @""),
    NSLocalizedString(@"Grey", @""),
  };

  for (NSInteger i = 0; i < 8; i++)
    {
      NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: labelNames[i]
                                                     action: @selector(setLabelForNodes:)
                                              keyEquivalent: @""];
      [item setTarget: [Workspace gworkspace]];
      [item setTag: i];  /* tag holds the GSFileLabel value */
      [item setEnabled: YES];
      [labelMenu addItem: item];
      RELEASE(item);
    }

  return AUTORELEASE(labelMenu);
}

/**
 * Action for label colour menu items.
 * Reads the label number from [sender tag] (0-7, where 0 = None),
 * applies it to all selected files in the active viewer, and updates
 * the display.
 */
/**
 * Convert GSFileLabel (from xattr FinderInfo) to DSStoreLabelColor
 * (from .DS_Store lclr entries).  Both enums use the same encoding
 * (1=Red, 2=Orange, 3=Yellow, 4=Green, 5=Blue, 6=Purple, 7=Grey), so the
 * conversion is the identity; kept as a named function so the shared
 * encoding is explicit at the call site.
 */
static DSStoreLabelColor GSFileLabelToDSStoreLabelColor(GSFileLabel gsLabel)
{
  return (DSStoreLabelColor)gsLabel;
}

- (void)setLabelForNodes:(id)sender
{
  NSInteger labelNumber = [sender tag];
  NSWindow *kwin = [NSApp keyWindow];

  if (!kwin)
    return;

  id nodeView = nil;
  NSArray *selection = nil;

  if ([vwrsManager hasViewerWithWindow: kwin])
    {
      nodeView = [[vwrsManager viewerWithWindow: kwin] nodeView];
    }
  else if ([dtopManager hasWindow: kwin])
    {
      nodeView = [dtopManager desktopView];
    }

  if (!nodeView)
    return;

  selection = [nodeView selectedPaths];
  if (!selection || [selection count] == 0)
    {
      /* If no selection, use the base node (current directory) */
      selection = [NSArray arrayWithObject: [[nodeView baseNode] path]];
    }

  NSUInteger i;
  NSUInteger count = [selection count];

  /* ================================================================
   * 1. Write label via xattr (com.apple.FinderInfo) — existing path
   * ================================================================ */
  for (i = 0; i < count; i++)
    {
      NSString *path = [selection objectAtIndex: i];

      GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
      if (md == nil)
        {
          md = [[[GSFileMetadata alloc] init] autorelease];
        }

      [md setLabelNumber: labelNumber];

      NSError *error = nil;
      if (![md writeToFileAtPath: path error: &error])
        {
        }
    }

  /* ================================================================
   * 2. Write lclr entries to .DS_Store / per-volume cache
   *    (handles non-writable volumes via ~/Library/Caches)
   * ================================================================ */
  {
    NSMutableDictionary *pathsByDir = [NSMutableDictionary dictionary];
    DSStoreLabelColor dsColor = GSFileLabelToDSStoreLabelColor((GSFileLabel)labelNumber);

    for (i = 0; i < count; i++)
      {
        NSString *path = [selection objectAtIndex: i];
        NSString *parent = [path stringByDeletingLastPathComponent];
        NSString *filename = [path lastPathComponent];

        NSMutableArray *files = [pathsByDir objectForKey: parent];
        if (!files)
          {
            files = [NSMutableArray array];
            [pathsByDir setObject: files forKey: parent];
          }
        [files addObject: filename];
      }

    for (NSString *dirPath in pathsByDir)
      {
        NSArray *files = [pathsByDir objectForKey: dirPath];

        DSStoreInfo *dsInfo = [DSStoreInfo infoForDirectoryPath: dirPath
                                                 loadImmediately: NO];
        for (NSString *filename in files)
          {
            DSStoreIconInfo *iconInfo = [DSStoreIconInfo infoForFilename: filename];
            [iconInfo setLabelColor: dsColor];
            [iconInfo setHasLabelColor: YES];  /* Always YES so lclr=0 is persisted */
            [dsInfo setIconInfo: iconInfo forFilename: filename];
          }

        GWViewSettingsManager *sm;
        sm = [GWViewSettingsManager managerForDirectoryPath: dirPath];
        [sm writeSettings: dsInfo];
      }
  }

  /* ================================================================
   * 3. Refresh the viewer and apply visual feedback
   * ================================================================ */
  if ([vwrsManager hasViewerWithWindow: kwin])
    {
      GWViewer *viewer = [vwrsManager viewerWithWindow: kwin];
      [viewer reloadNodeContents];
    }
  else if ([dtopManager hasWindow: kwin])
    {
      [[dtopManager desktopView] reloadContents];
    }

  /* Apply tag colors to selected files for immediate visual feedback */
  if (labelNumber != 0 && nodeView
      && [nodeView respondsToSelector: @selector(setTagColorsFromDictionary:)])
    {
      NSMutableDictionary *tagColors = [NSMutableDictionary dictionary];
      NSColor *color = [GSFileMetadata colorForLabel: (GSFileLabel)labelNumber];
      if (color)
        {
          for (i = 0; i < count; i++)
            {
              NSString *path = [selection objectAtIndex: i];
              NSString *filename = [path lastPathComponent];
              [tagColors setObject: color forKey: filename];
            }
          [(id)nodeView setTagColorsFromDictionary: tagColors];
        }
    }
}

/*
 * =================================================================
 * Compress / Extract with Mac metadata
 * =================================================================
 */

/**
 * Action: compress selected files into a .zip archive, preserving
 * macOS metadata (FinderInfo, ResourceFork, etc.) via AppleDouble.
 */
- (id)activeIconView
{
  NSWindow *kwin = [NSApp keyWindow];
  if (!kwin) return nil;

  if ([vwrsManager hasViewerWithWindow: kwin])
    return [[vwrsManager viewerWithWindow: kwin] nodeView];
  else if ([dtopManager hasWindow: kwin])
    return [dtopManager desktopView];
  return nil;
}

- (void)cleanUp:(id)sender
{
  id iconView = [self activeIconView];
  if (!iconView) return;
  [self cleanUpWithSort: FSNInfoNameType iconView: iconView
           sortSelector: @selector(compareAccordingToName:)];
}

- (void)cleanUpBy:(id)sender
{
  id iconView = [self activeIconView];
  if (!iconView) return;

  NSInteger tag = [sender tag];
  FSNInfoType sortType;
  SEL sortSel = @selector(compareAccordingToName:);

  switch (tag)
    {
    case 0: sortType = FSNInfoNameType;
            sortSel = @selector(compareAccordingToName:); break;
    case 1: sortType = FSNInfoKindType;
            sortSel = @selector(compareAccordingToKind:); break;
    case 2: sortType = FSNInfoDateType;
            sortSel = @selector(compareAccordingToDate:); break;
    case 3: sortType = FSNInfoSizeType;
            sortSel = @selector(compareAccordingToSize:); break;
    case 5: sortType = FSNInfoDateType;  /* creation date */
            sortSel = @selector(compareAccordingToCrDate:); break;
    default: sortType = FSNInfoNameType; break;
    }

  if ([iconView respondsToSelector: @selector(setCustomIconPositions:)])
    [iconView setCustomIconPositions: nil];

  [self cleanUpWithSort: sortType iconView: iconView sortSelector: sortSel];
}

- (void)cleanUpWithSort:(FSNInfoType)sortType iconView:(id)iconView sortSelector:(SEL)sortSel
{
  [[FSNodeRep sharedInstance] setDefaultSortOrder: (int)sortType];

  /* Sort the icon array in place */
  if ([iconView respondsToSelector: @selector(icons)])
    {
      NSMutableArray *all = (NSMutableArray *)[iconView icons];

      /* Desktop special sort: "/" first, other mounted volumes next,
       * then everything else in the requested sort order. */
      if (NSClassFromString(@"GWDesktopView")
          && [iconView isKindOfClass: NSClassFromString(@"GWDesktopView")])
        {
          NSMutableArray *rootItems = [NSMutableArray array];
          NSMutableArray *volumeItems = [NSMutableArray array];
          NSMutableArray *otherItems = [NSMutableArray array];

          for (id icon in all)
            {
              FSNode *n = [icon node];
              NSString *p = [n path];
              if ([p isEqualToString: @"/"])
                [rootItems addObject: icon];
              else if ([n isMountPoint])
                [volumeItems addObject: icon];
              else
                [otherItems addObject: icon];
            }

          [volumeItems sortUsingSelector: sortSel];
          [otherItems sortUsingSelector: sortSel];

          [all removeAllObjects];
          [all addObjectsFromArray: rootItems];
          [all addObjectsFromArray: volumeItems];
          [all addObjectsFromArray: otherItems];
        }
      else
        {
          [all sortUsingSelector: sortSel];
        }
    }

  /* Snapshot icon positions for smooth animation */
  NSMutableDictionary *oldFrames = nil;
  if ([iconView respondsToSelector: @selector(icons)])
    {
      oldFrames = [NSMutableDictionary dictionary];
      for (id ic in [iconView icons])
        {
          NSString *name = [[ic node] name];
          [oldFrames setObject: [NSValue valueWithRect: [ic frame]]
                        forKey: name];
        }
    }

  if ([iconView respondsToSelector: @selector(cleanupIconPositions)])
    {
      [iconView cleanupIconPositions];
    }

  /* Write positions to DS_Store for each icon after cleanup */
  if ([iconView respondsToSelector: @selector(batchRepositionIcons:toCenterPoints:)]
      && [iconView respondsToSelector: @selector(icons)])
    {
      NSArray *all = [iconView icons];
      NSMutableArray *centers = [NSMutableArray arrayWithCapacity: [all count]];
      NSUInteger i;
      for (i = 0; i < [all count]; i++)
        {
          id ic = [all objectAtIndex: i];
          NSRect frm = [ic frame];
          NSPoint c = NSMakePoint(frm.origin.x + frm.size.width / 2.0,
                                   frm.origin.y + frm.size.height / 2.0);
          [centers addObject: [NSValue valueWithPoint: c]];
        }
      [iconView batchRepositionIcons: all toCenterPoints: centers];
    }

  /* Invalidate old + new icon areas on the container BEFORE reverting
   * frames for animation.  cleanupIconPositions + tile mark only the new
   * positions dirty; reverting to old frames leaves stale dirty rects
   * pointing at the wrong coordinates, causing screen artifacts. */
  if (oldFrames && [iconView respondsToSelector: @selector(icons)])
    {
      for (id ic in [iconView icons])
        {
          NSString *name = [[ic node] name];
          NSValue *oldVal = [oldFrames objectForKey: name];
          if (oldVal)
            {
              [iconView setNeedsDisplayInRect: [oldVal rectValue]];
              [iconView setNeedsDisplayInRect: [ic frame]];
            }
        }
    }

  /* Animate icons smoothly from old positions to new positions */
  if (oldFrames && [iconView respondsToSelector: @selector(icons)])
    {
      NSMutableArray *animations = [NSMutableArray array];
      for (id ic in [iconView icons])
        {
          NSString *name = [[ic node] name];
          NSValue *oldVal = [oldFrames objectForKey: name];
          if (oldVal)
            {
              NSRect oldFrame = [oldVal rectValue];
              NSRect newFrame = [ic frame];
              if (!NSEqualRects(oldFrame, newFrame))
                {
                  /* Set icon back to its old frame so NSViewAnimation
                   * has a visible starting position to interpolate from. */
                  [ic setFrame: oldFrame];
                  [animations addObject:
                    [NSDictionary dictionaryWithObjectsAndKeys:
                      ic, NSViewAnimationTargetKey,
                      [NSValue valueWithRect: oldFrame], NSViewAnimationStartFrameKey,
                      [NSValue valueWithRect: newFrame], NSViewAnimationEndFrameKey,
                      nil]];
                }
            }
        }

      if ([animations count] > 0)
        {
          NSViewAnimation *animation =
            [[NSViewAnimation alloc] initWithViewAnimations: animations];
          [animation setDuration: 0.35];
          [animation setAnimationCurve: NSAnimationEaseInOut];
          [animation setAnimationBlockingMode: NSAnimationNonblocking];
          [animation startAnimation];
          /* Don't release - NSAnimation releases itself on completion
           * via animatorDidStop (NSAnimation.m:990). External release
           * causes use-after-free in GSAnimator's dealloc chain. */

          /* Flush dirty rects at every run loop iteration during the
           * animation so intermediate icon positions are cleaned up.
           * NSViewAnimation's setFrame: does not invalidate the prior
           * frame on the container, leaving ghost pixels. */
          if ([iconView respondsToSelector: @selector(displayIfNeeded)])
            {
              NSTimeInterval flushDuration = [animation duration] + 0.05;
              NSTimer *flushTimer = [NSTimer scheduledTimerWithTimeInterval: 1.0/60.0
                                                                     target: iconView
                                                                   selector: @selector(displayIfNeeded)
                                                                   userInfo: nil
                                                                    repeats: YES];
              [flushTimer performSelector: @selector(invalidate)
                               withObject: nil
                               afterDelay: flushDuration];
              [iconView performSelector: @selector(display)
                             withObject: nil
                             afterDelay: flushDuration];
            }
        }
    }

}

- (void)compressFiles:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  NSArray *selection = nil;

  if (!kwin)
    return;

  if ([vwrsManager hasViewerWithWindow: kwin])
    selection = [[[vwrsManager viewerWithWindow: kwin] nodeView] selectedPaths];
  else if ([dtopManager hasWindow: kwin])
    selection = [[dtopManager desktopView] selectedPaths];

  if (!selection || [selection count] == 0)
    return;

  /* Build a default output name from the first item */
  NSString *firstName = [[selection objectAtIndex: 0] lastPathComponent];
  NSString *baseName  = [firstName stringByDeletingPathExtension];
  if ([baseName length] == 0)
    baseName = firstName;

  NSString *parentDir = [[selection objectAtIndex: 0] stringByDeletingLastPathComponent];
  NSString *outputPath = [parentDir stringByAppendingPathComponent:
                           [baseName stringByAppendingPathExtension: @"zip"]];

  /* If the default name already exists, append a number */
  NSFileManager *fileMgr = [NSFileManager defaultManager];
  if ([fileMgr fileExistsAtPath: outputPath])
    {
      NSUInteger n = 1;
      do {
        NSString *tryName = [NSString stringWithFormat: @"%@ %lu", baseName, (unsigned long)n];
        outputPath = [parentDir stringByAppendingPathComponent:
                       [tryName stringByAppendingPathExtension: @"zip"]];
        n++;
      } while ([fileMgr fileExistsAtPath: outputPath]);
    }

  /* Run with progress panel */
  [GWArchiveOperation compressPaths: selection toArchive: outputPath];

  /* Refresh the viewer so the new .zip appears */
  if ([vwrsManager hasViewerWithWindow: kwin])
    [[vwrsManager viewerWithWindow: kwin] reloadNodeContents];
  else if ([dtopManager hasWindow: kwin])
    [[dtopManager desktopView] reloadContents];
}

/**
 * Action: extract a .zip archive preserving macOS metadata.
 * The archive is extracted into a folder named after the archive
 * (without .zip extension) in the same directory.
 */
- (void)extractArchive:(id)sender
{
  NSWindow *kwin = [NSApp keyWindow];
  NSArray *selection = nil;

  if (!kwin)
    return;

  if ([vwrsManager hasViewerWithWindow: kwin])
    selection = [[[vwrsManager viewerWithWindow: kwin] nodeView] selectedPaths];
  else if ([dtopManager hasWindow: kwin])
    selection = [[dtopManager desktopView] selectedPaths];

  if (!selection || [selection count] != 1)
    return;

  NSString *archivePath = [selection objectAtIndex: 0];

  /* Destination: same directory, folder named after the archive.
   * Strip all archive-related extensions so "file.tar.gz" yields "file". */
  NSString *baseName = [archivePath lastPathComponent];
  while (1)
    {
      NSString *ext = [baseName pathExtension];
      if ([ext length] == 0 || ![GWMetaArchive isArchiveExtension: ext])
        break;
      baseName = [baseName stringByDeletingPathExtension];
    }
  NSString *parentDir = [archivePath stringByDeletingLastPathComponent];
  NSString *destDir   = [parentDir stringByAppendingPathComponent: baseName];

  /* If the destination already exists, append a number */
  NSFileManager *fileMgr = [NSFileManager defaultManager];
  if ([fileMgr fileExistsAtPath: destDir])
    {
      NSUInteger n = 1;
      do {
        NSString *tryName = [NSString stringWithFormat: @"%@ %lu", baseName, (unsigned long)n];
        destDir = [parentDir stringByAppendingPathComponent: tryName];
        n++;
      } while ([fileMgr fileExistsAtPath: destDir]);
    }

  /* Run with progress panel */
  [GWArchiveOperation extractArchive: archivePath toDirectory: destDir];

  /* Refresh the viewer so the new folder appears */
  if ([vwrsManager hasViewerWithWindow: kwin])
    [[vwrsManager viewerWithWindow: kwin] reloadNodeContents];
  else if ([dtopManager hasWindow: kwin])
    [[dtopManager desktopView] reloadContents];
}

- (oneway void)terminateApplication
{
  [NSApp terminate: self];
}

- (BOOL)terminating
{
  return terminating;
}


- (void)createStandardUserDirectories
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  NSString *homeDirectory = NSHomeDirectory();
  NSArray *standardDirectories = @[
    @"Applications",
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
          } else {
          }
        }
      NS_HANDLER
        {
        }
      NS_ENDHANDLER
    } else if (!isDirectory) {
    }
  }
}

- (void)setViewerBehaviour:(id)sender
{
  /* The kind is carried by the item's tag (BROWSING/SPATIAL), not its title —
   * titles are localized, so comparing them broke on non-English locales. */
  unsigned int viewerType = (unsigned int)[sender tag];

  /* Resolve the source viewer from the key window, falling back to the main
   * window.  With a detached global menu (Menu.app) the viewer is not always
   * the key window when the item fires, which otherwise made this a silent
   * no-op ("sometimes nothing happens"). */
  id viewer = [vwrsManager viewerWithWindow: [NSApp keyWindow]];
  if (!viewer) {
    viewer = [vwrsManager viewerWithWindow: [NSApp mainWindow]];
  }
  if (!viewer) {
    return;
  }

  // Get the base node (current path) from the viewer
  FSNode *currentNode = [viewer baseNode];
  if (!currentNode) {
    return;
  }


  // Replace the current viewer window with one of the selected kind

  id newViewer = [vwrsManager replaceViewer: viewer
                             withViewerType: viewerType];

  if (newViewer) {
    /* viewerOfType:… already activates the new viewer; activating again here
     * would, for spatial, re-run viewer:didShowNode:. */
  } else {
  }

}

- (void)setViewerType:(id)sender
{
  NSInteger tag = [sender tag];

  if (tag <= 0)
    return;

  /* Resolve the viewer from the key window, falling back to the main window,
   * then to the first live viewer.  With a detached global menu (Menu.app)
   * the viewer is not always the key window when the item fires, which would
   * otherwise make this a silent no-op.  Only viewer windows get the new view
   * type; the desktop ignores the item entirely (disabled via validation). */
  id viewer = [self _viewerForKeyWindow];
  if (!viewer) {
    return;
  }

  if ([viewer respondsToSelector: @selector(setViewerType:)])
    {
      [viewer setViewerType: sender];
    }
}

/* Resolves the target viewer the same way setViewerType: does, so menu
 * actions and their validation agree on which viewer window is meant. */
- (id)_viewerForKeyWindow
{
  id viewer = [vwrsManager viewerWithWindow: [NSApp keyWindow]];
  if (!viewer) {
    viewer = [vwrsManager viewerWithWindow: [NSApp mainWindow]];
  }
  if (!viewer) {
    NSArray *wins = [vwrsManager viewerWindows];
    if ([wins count]) {
      viewer = [vwrsManager viewerWithWindow: [wins objectAtIndex: 0]];
    }
  }
  return viewer;
}

- (void)toggleInspector:(id)sender
{
  id viewer = [self _viewerForKeyWindow];
  if (viewer && [viewer respondsToSelector: @selector(toggleInspector:)])
    {
      [viewer toggleInspector: sender];
    }
}

- (void)toggleSidebar:(id)sender
{
  id viewer = [self _viewerForKeyWindow];
  if (viewer && [viewer respondsToSelector: @selector(toggleSidebar:)])
    {
      [viewer toggleSidebar: sender];
      /* Update the menu item checkmark right away so the item reflects the
       * new state without waiting for the next menu validation (menu_invoke
       * and the UITest's select menu resolve by the item's current title, which
       * no longer changes). */
      if ([viewer respondsToSelector: @selector(isSidebarShown)]) {
        [self _setSidebarMenuItemState: [viewer isSidebarShown]];
      }
    }
}

/* Updates the checkmark of the "Show Sidebar" menu item to match the given
 * state, so an in-process toggle (no menu display, no validation) still
 * leaves the menu state consistent. */
- (void)_setSidebarMenuItemState:(BOOL)shown
{
  SEL act = @selector(toggleSidebar:);
  NSMenu *mainMenu = [NSApp mainMenu];
  for (NSMenuItem *top in [mainMenu itemArray])
    {
      NSMenu *sub = [top submenu];
      if (sub == nil) continue;
      for (NSMenuItem *item in [sub itemArray])
        {
          if ([item action] == act)
            {
              [item setState: shown ? NSOnState : NSOffState];
              return;
            }
        }
    }
}

- (void)setDefaultBrowsingBehaviour:(id)sender
{
  [self setDefaultViewerType: BROWSING];

  /* Informational confirmation.  Do NOT raise a modal here: dismissing it
   * under a real X11 click (as the UI tests do) can segfault the app, and a
   * headless/CI session would leave it up forever, freezing the Workspace and
   * the DriveUI server.  The change is already visible via the menu
   * checkmark, so log it and move on. */
  NSLog(@"Default viewer type set to Browsing for new viewer windows.");
}

- (void)setDefaultSpatialBehaviour:(id)sender
{
  [self setDefaultViewerType: SPATIAL];

  /* Informational confirmation; see setDefaultBrowsingBehaviour:. */
  NSLog(@"Default viewer type set to Spatial for new viewer windows.");
}

- (void)notImplemented:(id)sender
{
  NSString *title = nil;
  NSString *message;
  
  if ([sender respondsToSelector:@selector(title)]) {
    title = [sender title];
  }
  
  if (title) {
    message = [NSString stringWithFormat:@"The \"%@\" feature is not yet implemented.", title];
  } else {
    message = @"This feature is not yet implemented.";
  }
  
  NSRunAlertPanel(@"Not Implemented Yet", message, @"OK", nil, nil);
  return;  // Explicit return to avoid noreturn inference
}

- (void)undo:(id)sender
{
  [self notImplemented:sender];
}

- (void)redo:(id)sender
{
  [self notImplemented:sender];
}

- (void)toggleHiddenFiles
{
  // This would toggle the display of hidden files
  NSRunAlertPanel(@"Not Implemented Yet",
                  @"Toggle hidden files is not yet implemented.",
                  @"OK", nil, nil);
}

- (void)quickLook:(id)sender
{
  NSRunAlertPanel(@"Not Implemented Yet",
                  @"Quick Look is not yet implemented.",
                  @"OK", nil, nil);
}

+ (NSArray *)volumeMountRoots
{
  NSString *user = NSUserName();
  NSMutableArray *roots = [NSMutableArray arrayWithObjects:
                           @"/media",
                           @"/Volumes",
                           nil];
  if ([user length] > 0) {
    [roots addObject: [@"/run/media" stringByAppendingPathComponent: user]];
    [roots addObject: [@"/media" stringByAppendingPathComponent: user]];
  }
  return roots;
}

- (BOOL)unmountVolumeAtPath:(NSString *)path
{
  if (!path) {
    return NO;
  }
  

  /* Record this as a user-initiated unmount BEFORE doing anything else.
   * This is the authoritative record that showMountedVolumes checks to
   * suppress the "Volume Removed Unexpectedly" dialog.
   * Multiple covering mechanisms (expectedUnmountPaths in GWDesktopView,
   * NSWorkspaceWillUnmountNotification) also exist, but this direct
   * tracking is the guaranteed fallback that works on all platforms. */
  [self noteUserInitiatedUnmountAtPath: path];
  {
    id deskMgr = [GWDesktopManager desktopManager];
    id deskView = [deskMgr desktopView];
    if ([deskView respondsToSelector: @selector(workspaceWillUnmountVolumeAtPath:)]) {
      [deskView workspaceWillUnmountVolumeAtPath: path];
    }
  }
  
  // Check if this is a disk image mount managed by VolumeManager
  BOOL isDiskImageVolume = NO;
  id volumeManager = nil;
  
  Class VolumeManagerClass = NSClassFromString(@"VolumeManager");
  if (VolumeManagerClass) {
    if ([VolumeManagerClass respondsToSelector:@selector(isDiskImageMount:)]) {
      isDiskImageVolume = [VolumeManagerClass isDiskImageMount:path];
      if (isDiskImageVolume) {
        volumeManager = [VolumeManagerClass sharedManager];
      }
    }
  }
  
  if (isDiskImageVolume && volumeManager) {
    return [volumeManager unmountPath: path];
  }
  
  // Check if this is a network volume managed by NetworkVolumeManager
  id networkVolumeManager = nil;
  
  Class NetworkVolumeManagerClass = NSClassFromString(@"NetworkVolumeManager");
  if (NetworkVolumeManagerClass) {
    networkVolumeManager = [NetworkVolumeManagerClass sharedManager];
    if (networkVolumeManager && [networkVolumeManager respondsToSelector:@selector(unmountPath:)]) {
      NSSet *netPaths = [networkVolumeManager allMountedPaths];
      if ([netPaths containsObject: path]) {
        return [networkVolumeManager unmountPath: path];
      }
    }
  }
  
  // Use standard system unmount+eject for regular volumes (drag to trash)
  BOOL result = [GWUnmountHelper unmountAndEjectPath:path];
  
  if (!result) {
    NSString *err = NSLocalizedString(@"Error", @"");
    NSString *msg = NSLocalizedString(@"You are not allowed to umount\n", @"");
    NSString *buttstr = NSLocalizedString(@"Continue", @"");
    NSRunAlertPanel(err, [NSString stringWithFormat: @"%@ \"%@\"!\n", msg, path], buttstr, nil, nil);
  }
  
  [dtopManager unlockVolumeAtPath: path];
  return result;
}

- (void)formatSelectedMountPoints:(id)sender
{
  id representedObject = nil;
  NSArray *mountPoints = nil;

  if (sender && [sender respondsToSelector:@selector(representedObject)]) {
    representedObject = [sender representedObject];
  }

  if ([representedObject isKindOfClass:[NSArray class]]) {
    mountPoints = representedObject;
  } else if ([selectedPaths count] > 0) {
    mountPoints = selectedPaths;
  }

  if (!mountPoints || [mountPoints count] == 0) {
    return;
  }

  for (NSString *mountPoint in mountPoints) {
    if ([self isRootFilesystem:mountPoint]) {
      NSRunAlertPanel(NSLocalizedString(@"Error", @""),
                      NSLocalizedString(@"You cannot format the root filesystem.", @""),
                      NSLocalizedString(@"OK", @""),
                      nil,
                      nil);
      continue;
    }

    NSString *resolveError = nil;
    BlockDeviceInfo *info = [DiskFormatOperation deviceInfoForMountPoint:mountPoint error:&resolveError];
    if (!info || !info.isValid) {
      NSString *errText = resolveError;
      if (!errText || [errText length] == 0) {
        errText = NSLocalizedString(@"Cannot determine device information for the selected mount point.", @"");
      }
      NSRunAlertPanel(NSLocalizedString(@"Format Failed", @""),
                      @"%@",
                      NSLocalizedString(@"OK", @""),
                      nil,
                      nil,
                      errText);
      continue;
    }

    NSString *safetyError = [info safetyCheckForWriting];
    if (safetyError) {
      NSRunAlertPanel(NSLocalizedString(@"Format Failed", @""),
                      @"%@",
                      NSLocalizedString(@"OK", @""),
                      nil,
                      nil,
                      safetyError);
      continue;
    }

    DeviceEraseConfirmation *confirmation = [DeviceEraseConfirmation confirmationForDiskFormatWithMountPoint:mountPoint
                                                                                                   deviceInfo:info];
    NSInteger result = [confirmation runModal];
    if (result != NSModalResponseOK) {
      continue;
    }

    NSString *errorMessage = nil;
    BOOL ok = [DiskFormatOperation formatMountPoint:mountPoint error:&errorMessage];
    if (!ok) {
      NSString *errorText = errorMessage;
      if (!errorText || [errorText length] == 0) {
        errorText = NSLocalizedString(@"Formatting failed.", @"");
      }

      NSRunAlertPanel(NSLocalizedString(@"Format Failed", @""),
                      @"%@",
                      NSLocalizedString(@"OK", @""),
                      nil,
                      nil,
                      errorText);
      continue;
    }

    NSRunAlertPanel(NSLocalizedString(@"Format Complete", @""),
                    NSLocalizedString(@"The disk was formatted as FAT32.", @""),
                    NSLocalizedString(@"OK", @""),
                    nil,
                    nil);
  }
}

- (void)emptyTrash
{
  [self emptyTrash:nil];
}

#if HAVE_DBUS
- (void)processDBusMessages:(NSNotification *)notification
{
  // Process D-Bus messages for FileManager1 service
  // This is called automatically when data is available on the D-Bus file descriptor
  if (fileManagerDBusInterface && [fileManagerDBusInterface dbusConnection]) {
    [[fileManagerDBusInterface dbusConnection] processMessages];
  }
  
  // Re-arm the notification for next message
  NSFileHandle *fileHandle = [notification object];
  if (fileHandle) {
    [fileHandle waitForDataInBackgroundAndNotify];
  }
}
#endif

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

