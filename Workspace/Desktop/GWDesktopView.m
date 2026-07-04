/* GWDesktopView.m
 *
 * Copyright (C) 2005-2024 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale
 *         Riccardo Mottola <rm@gnu.org>
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSVersion.h>
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"
#import "FSNIconPositionStore.h"
#import "GWDesktopView.h"
#import "GWDesktopIcon.h"
#import "GWDesktopManager.h"
#import "DSStoreInfo.h"
#import "GWViewSettingsManager.h"
#import "Dock.h"
#import "Workspace.h"
#import "GWViewersManager.h"
#import "../Network/NetworkVolumeManager.h"

#define DEF_ICN_SIZE 48
#define DEF_TEXT_SIZE 12
#define DEF_ICN_POS NSImageAbove

#define X_MARGIN (26)
#define Y_MARGIN (12)
#define TOP_MARGIN (-8)
#define BOTTOM_MARGIN (8)

#define EDIT_MARGIN (4)

#ifndef max
  #define max(a,b) ((a) >= (b) ? (a):(b))
#endif

#ifndef min
  #define min(a,b) ((a) <= (b) ? (a):(b))
#endif

#define DEF_COLOR [NSColor colorWithCalibratedRed: 0.39 green: 0.51 blue: 0.57 alpha: 1.00]


@implementation GWDesktopView

- (void)dealloc
{
  RELEASE (mountedVolumes);
  RELEASE (expectedUnmountPaths);
  RELEASE (desktopInfo);
  RELEASE (backImage);
  RELEASE (imagePath);
  RELEASE (dragIcon);

  [super dealloc];
}

- (id)initForManager:(id)mngr
{
  self = [super init];

  if (self)
    {
      NSSize size;
      NSCachedImageRep *rep;

      manager = mngr;

      // Span the full virtual desktop (union of all screens)
      NSArray *screens = [NSScreen screens];
      screenFrame = [[screens objectAtIndex:0] frame];
      for (NSUInteger si = 1; si < [screens count]; si++) {
        screenFrame = NSUnionRect(screenFrame, [[screens objectAtIndex:si] frame]);
      }
      [self setFrame: screenFrame];

      size = NSMakeSize(screenFrame.size.width, 2);
      horizontalImage = [[NSImage allocWithZone: (NSZone *)[(NSObject *)self zone]]
                                 initWithSize: size];

      rep = [[NSCachedImageRep allocWithZone: (NSZone *)[(NSObject *)self zone]]
                              initWithSize: size
                                     depth: [NSWindow defaultDepthLimit]
                                  separate: YES
                                     alpha: YES];

      [horizontalImage addRepresentation: rep];
      RELEASE (rep);

      size = NSMakeSize(2, screenFrame.size.height);
      verticalImage = [[NSImage allocWithZone: (NSZone *)[(NSObject *)self zone]]
                               initWithSize: size];

      rep = [[NSCachedImageRep allocWithZone: (NSZone *)[(NSObject *)self zone]]
                              initWithSize: size
                                     depth: [NSWindow defaultDepthLimit]
                                  separate: YES
                                     alpha: YES];

      [verticalImage addRepresentation: rep];
      RELEASE (rep);

      ASSIGN (backColor, DEF_COLOR);

      backImageStyle = BackImageCenterStyle;
      mountedVolumes = [NSMutableArray new];
      expectedUnmountPaths = [NSMutableDictionary new];

      /* Set desktop placement direction (top→bottom, right→left) */
      _placementDirection = FSNPlacementDirectionTopToBottomRightToLeft;

      [self getDesktopInfo];
      dragIcon = nil;
    }

  return self;
}

- (void)newVolumeMountedAtPath:(NSString *)vpath
{
  NSDebugLLog(@"gwspace", @"GWDesktopView: newVolumeMountedAtPath called for %@", vpath);
  FSNode *vnode = [FSNode nodeWithPath: vpath];

  [vnode setMountPoint: YES];
  [self removeRepOfSubnode: vnode];
  [self addRepForSubnode: vnode];

  /* Track this volume in mountedVolumes so the periodic timer check
   * (showMountedVolumes) can later detect when it is unmounted and
   * remove the desktop icon + update the sidebar.  Without this, volumes
   * mounted by NetworkVolumeManager (e.g. sshfs) would never be in
   * mountedVolumes if NSWorkspace.mountedLocalVolumePaths does not
   * report FUSE mounts, making them invisible to the timer check. */
  {
    NSString *norm = [vpath stringByStandardizingPath];
    if (norm && [mountedVolumes containsObject: norm] == NO)
      {
        [mountedVolumes addObject: norm];
      }
  }

  /* Mark network volumes as expected unmounts briefly, so transient
   * disconnections (e.g. sshfs reconnecting) don't trigger a spurious
   * "Volume Removed Unexpectedly" dialog.  Regular volumes (USB sticks,
   * etc.) should NOT be marked — if they disappear unexpectedly, the
   * dialog must appear.  We identify network volumes by checking with
   * NetworkVolumeManager. */
  {
    NSSet *netPaths = [[NetworkVolumeManager sharedManager] allMountedPaths];
    if ([netPaths containsObject: vpath])
      {
        [expectedUnmountPaths setObject: [NSDate date] forKey: vpath];
        [[Workspace gworkspace] noteUserInitiatedUnmountAtPath: vpath];
      }
  }

  /* Navigate any viewer showing the parent directory to this new volume,
   * so the user sees the volume contents immediately on mount. */
  {
    NSString *parentPath = [vpath stringByDeletingLastPathComponent];
    FSNode *parentNode = [FSNode nodeWithPath: parentPath];
    FSNode *volumeNode = [FSNode nodeWithPath: vpath];
    NSArray *vwrs = [[[Workspace gworkspace] viewersManager] viewersForBaseNode: parentNode];
    for (id viewer in vwrs)
      {
        NSDebugLLog(@"gwspace", @"GWDesktopView: Navigating viewer %@ from %@ to %@",
                    viewer, parentPath, vpath);
        NS_DURING
          {
            [viewer showContentsOfNode: volumeNode];
          }
        NS_HANDLER
          {
            NSDebugLLog(@"gwspace", @"GWDesktopView: Exception navigating viewer: %@", localException);
          }
        NS_ENDHANDLER
      }
  }

  [self tile];
  NSDebugLLog(@"gwspace", @"GWDesktopView: Added desktop icon for mount %@", vpath);
}

- (void)workspaceWillUnmountVolumeAtPath:(NSString *)vpath
{
  if (vpath)
    {
      [expectedUnmountPaths setObject:[NSDate date] forKey:vpath];
      NSDebugLLog(@"gwspace", @"GWDesktopView: Marked path as expected unmount: %@", vpath);
    }
  [self checkLockedReps];
}

- (void)workspaceDidUnmountVolumeAtPath:(NSString *)vpath
{
  FSNIcon *icon;
  
  if (!vpath)
    {
      NSDebugLLog(@"gwspace", @"GWDesktopView: workspaceDidUnmountVolumeAtPath called with nil path");
      return;
    }
  
  /* Do NOT remove from expectedUnmountPaths here.
   * The polling timer in showMountedVolumes needs to see it
   * to avoid a false "unexpected unmount" warning.
   * showMountedVolumes cleans up after the check. */

  /* Remove from the tracked mountedVolumes array so the periodic
   * timer check doesn't try to process it again.  This is critical
   * for volumes mounted via newVolumeMountedAtPath: (e.g. network
   * volumes) since they are added to mountedVolumes there but would
   * otherwise never be cleaned up. */
  [mountedVolumes removeObject: vpath];

  icon = [self repOfSubnodePath: vpath];

  if (icon)
    {
      @try
        {
          // Retain the icon to prevent premature deallocation
          [[icon retain] autorelease];
          [self removeRep: icon];
          [self tile];
        }
      @catch (NSException *exception)
        {
          NSDebugLLog(@"gwspace", @"Exception while removing icon for volume %@: %@", vpath, exception);
        }
    }
    
  /* Directly close any viewer windows showing this path and post a
   * notification so other listeners (including self) can react too. */
  if (vpath)
    {
      [[[Workspace gworkspace] viewersManager] closeViewersForUnmountedPath: vpath];

      NSString *parent = [vpath stringByDeletingLastPathComponent];
      NSString *name = [vpath lastPathComponent];
      
      if (parent && name)
        {
          NSDictionary *opinfo = @{ @"operation": @"UnmountOperation",
                                    @"source": parent,
                                    @"destination": parent,
                                    @"files": @[name],
                                    @"unmounted": vpath };
          
          [[NSNotificationCenter defaultCenter] postNotificationName:@"GWFileSystemDidChangeNotification" object:opinfo];
        }

      /* Also trigger sidebar rebuild by posting a file watcher notification
         for each mount root that contains this path.  The sidebar listens
         to GWFileWatcherFileDidChangeNotification and rebuilds its Volumes
         section when a path under a mount root changes.  This is the most
         reliable way to update the sidebar after desktop icon removal. */
      {
        NSArray *roots = [Workspace volumeMountRoots];
        for (NSString *root in roots) {
          if ([vpath isEqualToString: root] || [vpath hasPrefix: [root stringByAppendingString: @"/"]]) {
            NSDictionary *winfo = @{ @"path": root };
            [[NSNotificationCenter defaultCenter]
              postNotificationName: @"GWFileWatcherFileDidChangeNotification"
                            object: winfo];
            break;
          }
        }
      }
    }
}

- (void)markExpectedUnmountForPath:(NSString *)vpath
{
  if (vpath)
    {
      [expectedUnmountPaths setObject:[NSDate date] forKey:vpath];
      NSDebugLLog(@"gwspace", @"GWDesktopView: Externally marked path as expected unmount: %@", vpath);
    }
}

- (void)unlockVolumeAtPath:(NSString *)path
{
  [self checkLockedReps];
}

- (void)showMountedVolumes
{
  NSArray *rvPaths;
  NSMutableArray *newVolumes;
  NSMutableArray *volumesToRemove;
  NSUInteger i;
  BOOL added;

  added = NO;

  /*
   * mountedRemovableMedia relies on getmntent + sysfs which is Linux-only.
   * On FreeBSD (and other BSDs) removability detection does not work, so
   * mountedRemovableMedia returns an empty array.  We augment it with any
   * volumes from mountedLocalVolumePaths that live under well-known mount
   * root directories (/media, /Volumes, /run/media/<user>).
   */
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSMutableSet *volumeSet = [NSMutableSet setWithArray:[ws mountedRemovableMedia]];

  NSArray *mountRoots = [NSArray arrayWithObjects:
    @"/media",
    @"/Volumes",
    [@"/run/media" stringByAppendingPathComponent: NSUserName()],
    [@"/media" stringByAppendingPathComponent: NSUserName()],
    nil];

  NSArray *allLocal = [ws mountedLocalVolumePaths];
  for (NSString *vol in allLocal) {
    for (NSString *root in mountRoots) {
      if ([vol hasPrefix: [root stringByAppendingString: @"/"]]
          && ![vol isEqualToString: @"/"]) {
        [volumeSet addObject: vol];
        break;
      }
    }
  }

  rvPaths = [[NSArray arrayWithObject: @"/"] arrayByAddingObjectsFromArray: [volumeSet allObjects]];
  newVolumes = [NSMutableArray arrayWithCapacity:1];
  volumesToRemove = [NSMutableArray arrayWithCapacity:1];

  // First pass: identify volumes that need to be removed
  for (i = 0; i < [mountedVolumes count]; i++)
    {
      NSString *v;

      v = [mountedVolumes objectAtIndex:i];
      if ([rvPaths indexOfObject:v] == NSNotFound)
	{
	  NSDebugLLog(@"gwspace", @"removing: %@", v);
	  [volumesToRemove addObject:v];
	}
    }

  /* Verify volumes-to-remove against /proc/mounts as a reliability check.
   * This catches transient disconnections (e.g. sshfs reconnecting) where
   * the volume temporarily vanishes from mountedLocalVolumePaths but is
   * actually still mounted.  Without this, such transient events would
   * trigger a false "Volume Removed Unexpectedly" dialog. */
  if ([volumesToRemove count] > 0)
    {
      NSSet *procMounted = nil;
      NSString *procContent = [NSString stringWithContentsOfFile: @"/proc/mounts"
                                                       encoding: NSUTF8StringEncoding
                                                          error: NULL];
      if (procContent)
        {
          NSMutableSet *mounts = [NSMutableSet set];
          NSArray *lines = [procContent componentsSeparatedByString: @"\n"];
          for (NSString *line in lines)
            {
              if ([line length] == 0) continue;
              NSArray *parts = [line componentsSeparatedByString: @" "];
              if ([parts count] >= 2)
                {
                  [mounts addObject: [parts objectAtIndex: 1]];
                }
            }
          procMounted = mounts;
        }

      if (procMounted)
        {
          /* Iterate backwards to safely remove while enumerating */
          for (NSInteger j = [volumesToRemove count] - 1; j >= 0; j--)
            {
              NSString *v = [volumesToRemove objectAtIndex: j];
              if ([procMounted containsObject: v])
                {
                  NSDebugLLog(@"gwspace",
                    @"GWDesktopView: %@ is still mounted (found in /proc/mounts), not removing",
                    v);
                  [volumesToRemove removeObjectAtIndex: j];
                }
            }
        }
    }

  /* Check for CLI-triggered unmount flag file.  The eject(1) and umount(1)
   * tools write the unmount path here before executing the real command.
   * If any of the volumes-to-remove match, we mark them as expected to
   * suppress the dialog and let the normal removal flow clean up icons. */
  if ([volumesToRemove count] > 0)
    {
      NSString *flagPath = @"/tmp/.gw-umount-flag";
      NSString *flagContent = [NSString stringWithContentsOfFile: flagPath
                                                        encoding: NSUTF8StringEncoding
                                                           error: NULL];
      if (flagContent)
        {
          flagContent = [flagContent stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
          if ([flagContent length] > 0)
            {
              for (i = 0; i < [volumesToRemove count]; i++)
                {
                  NSString *v = [volumesToRemove objectAtIndex:i];
                  if ([v isEqualToString: flagContent])
                    {
                      /* Mark as expected unmount and record in Workspace */
                      [expectedUnmountPaths setObject: [NSDate date] forKey: v];
                      [[Workspace gworkspace] noteUserInitiatedUnmountAtPath: v];
                      NSDebugLLog(@"gwspace", @"GWDesktopView: CLI unmount flag matched for %@", v);
                    }
                }
            }
          /* Remove the flag file after reading */
          unlink([flagPath fileSystemRepresentation]);
        }
    }
  
  // Check if any volumes were forcibly removed (not in expected unmounts)
  if ([volumesToRemove count] > 0)
    {
      NSMutableArray *unexpectedRemovals = [NSMutableArray arrayWithCapacity:1];
      NSTimeInterval expectedUnmountTimeout = 60.0; // seconds
      NSDate *now = [NSDate date];
      
      for (i = 0; i < [volumesToRemove count]; i++)
        {
          NSString *v = [volumesToRemove objectAtIndex:i];
          if ([v isEqualToString:@"/"])
            continue;

          NSDate *markedDate = [expectedUnmountPaths objectForKey:v];
          if (markedDate != nil
              && [now timeIntervalSinceDate:markedDate] < expectedUnmountTimeout)
            {
              /* This unmount was expected — suppress the warning. */
              NSDebugLLog(@"gwspace", @"GWDesktopView: Suppressing unexpected-unmount warning for %@ (expected)", v);
            }
          else if ([[[NetworkVolumeManager sharedManager] recentlyUnmountedPaths] containsObject: v])
            {
              /* Network volume unmounted through NetworkVolumeManager — suppress. */
              NSDebugLLog(@"gwspace", @"GWDesktopView: Suppressing unexpected-unmount warning for %@ (network)", v);
            }
          else if ([[Workspace gworkspace] isRecentUserUnmount: v])
            {
              /* User-initiated unmount via Workspace's unmountVolumeAtPath: — suppress. */
              NSDebugLLog(@"gwspace", @"GWDesktopView: Suppressing unexpected-unmount warning for %@ (user-initiated)", v);
            }
          else
            {
              [unexpectedRemovals addObject:v];
            }
        }
      
      /* Final safety check: re-scan /proc/mounts for any volume in
       * unexpectedRemovals.  If the volume is still mounted, it was
       * a transient glitch — remove it from the list. */
      if ([unexpectedRemovals count] > 0)
        {
          NSString *procContent = [NSString stringWithContentsOfFile: @"/proc/mounts"
                                                            encoding: NSUTF8StringEncoding
                                                               error: NULL];
          if (procContent)
            {
              for (NSInteger ri = [unexpectedRemovals count] - 1; ri >= 0; ri--)
                {
                  NSString *v = [unexpectedRemovals objectAtIndex: ri];
                  NSRange r = [procContent rangeOfString: v];
                  if (r.location != NSNotFound)
                    {
                      /* The path appears in /proc/mounts — still mounted */
                      NSDebugLLog(@"gwspace",
                        @"GWDesktopView: Final check — %@ is still mounted, removing from unexpected",
                        v);
                      [unexpectedRemovals removeObjectAtIndex: ri];
                      /* Also add to expected to prevent re-trigger next cycle */
                      [expectedUnmountPaths setObject: [NSDate date] forKey: v];
                      [[Workspace gworkspace] noteUserInitiatedUnmountAtPath: v];
                    }
                }
            }
        }

      /* Clean up expected-unmount entries for volumes that are now gone. */
      for (i = 0; i < [volumesToRemove count]; i++)
        {
          [expectedUnmountPaths removeObjectForKey:[volumesToRemove objectAtIndex:i]];
        }

      /* Also purge any stale entries older than the timeout. */
      NSMutableArray *staleKeys = [NSMutableArray arrayWithCapacity:1];
      for (NSString *key in expectedUnmountPaths)
        {
          NSDate *d = [expectedUnmountPaths objectForKey:key];
          if ([now timeIntervalSinceDate:d] >= expectedUnmountTimeout)
            {
              [staleKeys addObject:key];
            }
        }
      [expectedUnmountPaths removeObjectsForKeys:staleKeys];

      // Show alert for unexpected removals
      if ([unexpectedRemovals count] > 0)
        {
          /* Deduplicate the list — the same path may appear multiple times
           * if mountedVolumes had duplicates. */
          NSMutableArray *uniqueRemovals = [NSMutableArray arrayWithCapacity: [unexpectedRemovals count]];
          for (NSString *v in unexpectedRemovals)
            {
              if (![uniqueRemovals containsObject: v])
                {
                  [uniqueRemovals addObject: v];
                }
            }

          /* Mark these volumes as expected before showing the alert, so that
           * if NSRunAlertPanel re-enters the run loop (e.g. via MPointWatcher
           * timer) and showMountedVolumes is called again, the duplicate
           * alert is suppressed.  The entries will be cleaned up below. */
          for (NSString *v in uniqueRemovals)
            {
              [expectedUnmountPaths setObject:[NSDate date] forKey:v];
            }

          NSString *volumeList = [uniqueRemovals componentsJoinedByString:@"\n"];
          NSString *message;
          
          if ([uniqueRemovals count] == 1)
            {
              message = [NSString stringWithFormat:
                NSLocalizedString(@"The volume at the following path was removed without being properly ejected:\n\n%@\n\n"
                @"Always eject removable volumes before unplugging them to prevent data loss and avoid crashes.", @""), 
                volumeList];
            }
          else
            {
              message = [NSString stringWithFormat:
                NSLocalizedString(@"The following volumes were removed without being properly ejected:\n\n%@\n\n"
                @"Always eject removable volumes before unplugging them to prevent data loss and avoid crashes.", @""), 
                volumeList];
            }
          
          NSRunAlertPanel(NSLocalizedString(@"Volume Removed Unexpectedly", @""), 
                         message,
                         NSLocalizedString(@"OK", @""), nil, nil);
          
          /* Clean up the expected-unmount entries we added above, now that
           * the alert has been dismissed and re-entrancy is no longer a risk. */
          for (NSString *v in uniqueRemovals)
            {
              [expectedUnmountPaths removeObjectForKey:v];
            }
        }
    }
  
  // Remove volumes and notify (done separately to avoid iteration issues)
  for (i = 0; i < [volumesToRemove count]; i++)
    {
      NSString *v = [volumesToRemove objectAtIndex:i];
      [mountedVolumes removeObject:v];
      
      @try
        {
          [self workspaceDidUnmountVolumeAtPath: v];
        }
      @catch (NSException *exception)
        {
          NSDebugLLog(@"gwspace", @"Exception while unmounting volume at %@: %@", v, exception);
        }
    }

  for (i = 0; i < [rvPaths count]; i++)
    {
      NSString *v;

      v = [rvPaths objectAtIndex:i];
      if ([mountedVolumes indexOfObject:v] == NSNotFound)
	{
	  [newVolumes addObject:v];
	  //if ([v isEqual: path_separator()] == NO)
	    //{
	      //NSLog(@"new volume: %@", v);
	      //[self newVolumeMountedAtPath:v];
	    //}
    [self newVolumeMountedAtPath:v];
	  added = YES;
	}
    }

  // we add new volumes at once at the end, or we disturb our for cycle
  // we Tile only when adding, since workspaceDidUnmountVolumeAtPath does it for us
  if (added)
    {
      for (NSString *vol in newVolumes)
        {
          NSString *norm = [vol stringByStandardizingPath];
          if (norm && [mountedVolumes containsObject: norm] == NO)
            {
              [mountedVolumes addObject: norm];
            }
        }
      [self tile];
    }
}

- (void)dockPositionDidChange
{
  [self tile];
  [self setNeedsDisplay: YES];
}

/* The region of the desktop where icons may actually live: the screen minus
 * the menu-bar strip, the Dock's reserved side, and the top/bottom margins.
 * Single source for both the AUTO grid origin and the off-screen rescue
 * guard's usable rect, so a manual position under the Dock/menu bar is
 * treated as off-screen and re-flowed instead of hidden. */
- (NSRect)desktopGridRect
{
  NSRect dckr = [manager dockReservedFrame];
  NSRect mmfr = [manager macmenuReservedFrame];
  /* View-local (bounds) coordinates: origin (0,0), size of the spanned
   * screens.  screenFrame is in screen space and its origin is non-zero on a
   * multi-monitor union — icon frames are compared in this view's own space,
   * so build the rect at the origin, not at screenFrame.origin. */
  NSRect gridrect = NSMakeRect(0, 0, screenFrame.size.width,
                                     screenFrame.size.height);

  gridrect.size.height -= mmfr.size.height;
  gridrect.origin.y += BOTTOM_MARGIN;
  gridrect.size.height -= (TOP_MARGIN + BOTTOM_MARGIN);

  if ([manager dockPosition] == DockPositionLeft)
    {
      gridrect.size.width -= dckr.size.width;
      gridrect.origin.x += dckr.size.width;
    }
  else if ([manager dockPosition] == DockPositionRight)
    {
      gridrect.size.width -= dckr.size.width;
    }

  return gridrect;
}

- (NSPoint)gridOriginForLayout
{
  /* Desktop grid origin: top-left of the usable region, inset. */
  NSRect gridrect = [self desktopGridRect];
  CGFloat gridTopOffset = 12.0;

  return NSMakePoint(gridrect.origin.x + X_MARGIN,
                     gridrect.origin.y + gridrect.size.height - gridTopOffset);
}

- (NSRect)usableContentRect
{
  return [self desktopGridRect];
}

- (void)tile
{
  [super tile];
  [self updateNameEditor];
}

- (NSArray *)iconsWithGridOriginX:(float)x
{
  NSMutableArray *icns = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSPoint p = [icon frame].origin;

      if (p.x == x)
	{
	  [icns addObject: icon];
	}
    }

  if ([icns count])
    {
      return icns;
    }

  return nil;
}

- (NSArray *)iconsWithGridOriginY:(float)y
{
  NSMutableArray *icns = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSPoint p = [icon frame].origin;

      if (p.y == y)
	{
	  [icns addObject: icon];
	}
    }

  if ([icns count])
    {
      return icns;
    }

  return nil;
}




- (void)getDesktopInfo
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSDictionary *dskinfo = [defaults objectForKey: @"desktopinfo"];

  if (dskinfo)
    {
      id entry = [dskinfo objectForKey: @"backcolor"];
      FSNInfoType itype;

      if (entry)
	{
	  float red = [[(NSDictionary *)entry objectForKey: @"red"] floatValue];
	  float green = [[(NSDictionary *)entry objectForKey: @"green"] floatValue];
	  float blue = [[(NSDictionary *)entry objectForKey: @"blue"] floatValue];
	  float alpha = [[(NSDictionary *)entry objectForKey: @"alpha"] floatValue];

	  ASSIGN (backColor, [NSColor colorWithCalibratedRed: red
						       green: green
							blue: blue
						       alpha: alpha]);
	}

      entry = [dskinfo objectForKey: @"imagestyle"];
      backImageStyle = entry ? [entry intValue] : backImageStyle;

      entry = [dskinfo objectForKey: @"imagepath"];
      if (entry)
	{
	  CREATE_AUTORELEASE_POOL (pool);
	  NSImage *image = [[NSImage alloc] initWithContentsOfFile: entry];

	  if (image)
	    {
	      ASSIGN (imagePath, entry);
	      [self createBackImage: image];
	      RELEASE (image);
	    }

	  RELEASE (pool);
	}

      entry = [dskinfo objectForKey: @"usebackimage"];
      useBackImage = entry ? [entry boolValue] : NO;

      entry = [dskinfo objectForKey: @"iconsize"];
      iconSize = entry ? [entry intValue] : iconSize;

      entry = [dskinfo objectForKey: @"labeltxtsize"];
      if (entry)
	{
	  labelTextSize = [entry intValue];
	  ASSIGN (labelFont, [NSFont systemFontOfSize: labelTextSize]);
	}

      entry = [dskinfo objectForKey: @"iconposition"];
      iconPosition = entry ? [entry intValue] : iconPosition;

      entry = [dskinfo objectForKey: @"fsn_info_type"];
      itype = entry ? [entry intValue] : infoType;
      if (infoType != itype)
	{
	  infoType = itype;
	  [self calculateGridSize];
	}
      infoType = itype;

      if (infoType == FSNInfoExtendedType)
	{
	  DESTROY (extInfoType);
	  entry = [dskinfo objectForKey: @"ext_info_type"];

	  if (entry)
	    {
	      NSArray *availableTypes = [fsnodeRep availableExtendedInfoNames];

	      if ([availableTypes containsObject: entry])
		{
		  ASSIGN (extInfoType, entry);
		}
	    }

	  if (extInfoType == nil)
	    {
	      infoType = FSNInfoNameType;
	      [self calculateGridSize];
	    }
	}

      desktopInfo = [dskinfo mutableCopy];
    }
  else
    {
      desktopInfo = [NSMutableDictionary new];
    }
}

- (void)updateDefaults
{
  /* All desktop state (positions, appearance, wallpaper) lives in
   * DS_Store now.  This stub exists for backward compat with existing
   * callers that invoke it after property changes. */
}

/* Persist a changed icon-view setting to the desktop folder's .DS_Store via
 * the same tiered store all viewers use, merging into whatever else the
 * store already holds.  This is the write half of the read in
 * -showContentsOfNode:. */
- (void)persistDesktopViewSetting:(void (^)(DSStoreInfo *info))apply
{
  GWViewSettingsManager *sm;
  DSStoreInfo *info;

  if (node == nil)
    return;

  sm = [GWViewSettingsManager managerForDirectoryPath: [node path]];
  info = [sm readSettings];
  if (info == nil)
    return;

  apply(info);
  [sm writeSettings: info];
}

- (void)setIconSize:(int)size
{
  BOOL changed = (size != iconSize);

  [super setIconSize: size];

  /* Only rewrite ~/Desktop/.DS_Store (and fire the directory watcher) on a
   * real change — a same-value re-apply would trigger a needless refresh. */
  if (changed)
    [self persistDesktopViewSetting: ^(DSStoreInfo *info) {
      info.iconSize = size;
      info.hasIconSize = YES;
    }];
}

- (void)setIconPosition:(NSCellImagePosition)pos
{
  BOOL changed = (pos != iconPosition);

  [super setIconPosition: pos];

  if (changed)
    [self persistDesktopViewSetting: ^(DSStoreInfo *info) {
      info.labelPosition = (pos == NSImageAbove)
        ? DSStoreLabelPositionBottom : DSStoreLabelPositionRight;
      info.hasLabelPosition = YES;
    }];
}

- (void)selectIconInPrevLine
{
  /* Pixel-based: find icon with closest Y-origin above the selected one */
  NSUInteger i;
  FSNIcon *selectedIcon = nil;
  for (i = 0; i < [icons count]; i++)
    {
      if ([[icons objectAtIndex: i] isSelected])
	{
	  selectedIcon = [icons objectAtIndex: i];
	  break;
	}
    }
  if (!selectedIcon) return;

  CGFloat selY = [selectedIcon frame].origin.y;
  FSNIcon *best = nil;
  CGFloat bestDist = CGFLOAT_MAX;
  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      if (icon == selectedIcon) continue;
      CGFloat dy = [icon frame].origin.y - selY;
      if (dy < 0 && fabs(dy) < bestDist)
	{
	  best = icon;
	  bestDist = fabs(dy);
	}
    }
  if (best)
    {
      [best select];
      [self scrollIconToVisible: best];
    }
}

- (void)selectIconInNextLine
{
  /* Pixel-based: find icon with closest Y-origin below the selected one */
  NSUInteger i;
  FSNIcon *selectedIcon = nil;
  for (i = 0; i < [icons count]; i++)
    {
      if ([[icons objectAtIndex: i] isSelected])
	{
	  selectedIcon = [icons objectAtIndex: i];
	  break;
	}
    }
  if (!selectedIcon) return;

  CGFloat selY = [selectedIcon frame].origin.y;
  FSNIcon *best = nil;
  CGFloat bestDist = CGFLOAT_MAX;
  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      if (icon == selectedIcon) continue;
      CGFloat dy = [icon frame].origin.y - selY;
      if (dy > 0 && dy < bestDist)
	{
	  best = icon;
	  bestDist = dy;
	}
    }
  if (best)
    {
      [best select];
      [self scrollIconToVisible: best];
    }
}

- (void)selectPrevIcon
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSUInteger index = 0;

      if ([icon isSelected])
	{
	  NSArray *rowicons = [self iconsWithGridOriginY: [icon frame].origin.y];

	  if (rowicons)
	    {
	      FSNIcon *prev;

	      while (index < 0)
		{
		  index++;
		  prev = nil;

		  if (prev && [rowicons containsObject: prev])
		    {
		      [prev select];
		      break;
		    }
		}
	    }

	  break;
	}
    }
}

- (void)selectNextIcon
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSUInteger index = 0;

      if ([icon isSelected])
	{
	  NSArray *rowicons = [self iconsWithGridOriginY: [icon frame].origin.y];

	  if (rowicons)
	    {
	      FSNIcon *next;

	      while (index > 0)
		{
		  next = nil;

		  if (next && [rowicons containsObject: next])
		    {
		      [next select];
		      break;
		    }
		  index--;
		}
	    }

	  break;
	}
    }
}

- (void)mouseUp:(NSEvent *)theEvent
{
  [self setSelectionMask: NSSingleSelectionMask];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if ([theEvent modifierFlags] != NSShiftKeyMask)
    {
      selectionMask = NSSingleSelectionMask;
      selectionMask |= FSNCreatingSelectionMask;
      [self unselectOtherReps: nil];
      selectionMask = NSSingleSelectionMask;

      DESTROY (lastSelection);
      [self selectionDidChange];

      [manager deselectInSpatialViewers];
    }
}

static void GWHighlightFrameRect(NSRect aRect)
{
  NSFrameRectWithWidthUsingOperation(aRect, 1.0, GSCompositeHighlight);
}

- (void)mouseDragged:(NSEvent *)theEvent
{
  unsigned int eventMask = NSLeftMouseUpMask | NSLeftMouseDraggedMask;
  NSPoint	locp;
  NSPoint	startp;
  NSRect oldRect;
  NSRect r;
  float x, y, w, h;
  NSUInteger i;

  transparentSelection = NO;
  if ([[manager dock] style] == DockStyleModern)
    transparentSelection = YES;

  locp = [theEvent locationInWindow];
  locp = [self convertPoint: locp fromView: nil];
  startp = locp;

  oldRect = NSZeroRect;

  [[self window] disableFlushWindow];

  [self lockFocus];

  while ([theEvent type] != NSLeftMouseUp)
    {
      CREATE_AUTORELEASE_POOL (arp);

      theEvent = [[self window] nextEventMatchingMask: eventMask];

      locp = [theEvent locationInWindow];
      locp = [self convertPoint: locp fromView: nil];

      x = min(startp.x, locp.x);
      y = min(startp.y, locp.y);
      w = max(1, max(locp.x, startp.x) - min(locp.x, startp.x));
      h = max(1, max(locp.y, startp.y) - min(locp.y, startp.y));

      r = NSMakeRect(x, y, w, h);


      // Erase the previous rect
      if (transparentSelection)
	{
	  [self setNeedsDisplayInRect: oldRect];
	  [[self window] displayIfNeeded];
	}
      else
	{
	  GWHighlightFrameRect(oldRect);
	}

      // Draw the new rect
      if (transparentSelection)
	{
	  [[NSColor darkGrayColor] set];
	  NSFrameRect(r);
          [[[NSColor darkGrayColor] colorWithAlphaComponent: 0.33] set];
          NSRectFillUsingOperation(r, NSCompositeSourceOver);
	}
      else
	{
	  GWHighlightFrameRect(r);
	}

      oldRect = r;

      [[self window] enableFlushWindow];
      [[self window] flushWindow];
      [[self window] disableFlushWindow];

      DESTROY (arp);
    }

  [self unlockFocus];

  [[self window] postEvent: theEvent atStart: NO];

  // Erase the previous rect
  [self setNeedsDisplayInRect: oldRect];
  [[self window] displayIfNeeded];

  [[self window] enableFlushWindow];
  [[self window] flushWindow];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  x = min(startp.x, locp.x);
  y = min(startp.y, locp.y);
  w = max(1, max(locp.x, startp.x) - min(locp.x, startp.x));
  h = max(1, max(locp.y, startp.y) - min(locp.y, startp.y));

  r = NSMakeRect(x, y, w, h);

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSRect iconBounds = [self convertRect: [icon iconBounds] fromView: icon];

      if (NSIntersectsRect(r, iconBounds))
	{
	  [icon select];
	}
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)keyDown:(NSEvent *)theEvent
{
  unsigned flags = [theEvent modifierFlags];
  NSString *characters = [theEvent characters];

  if ([characters length] > 0)
    {
      unichar character = [characters characterAtIndex: 0];

      NSDebugLLog(@"gwspace", @"GWDesktopView.keyDown: character=0x%x, flags=0x%x", character, flags);

      // Handle arrow keys with modifiers
      if (character == NSDownArrowFunctionKey)
        {
          NSDebugLLog(@"gwspace", @"GWDesktopView: NSDownArrowFunctionKey pressed, flags=0x%x", flags);
          if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
            {
              NSDebugLLog(@"gwspace", @"GWDesktopView: Shift-Down detected - opening selection");
              [manager openSelectionInNewViewer: NO];
              return;
            }
          if ((flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
            {
              NSDebugLLog(@"gwspace", @"GWDesktopView: Command-Shift-Down detected - opening as folder");
              [manager openSelectionAsFolder];
              return;
            }
          if ((flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
            {
              NSDebugLLog(@"gwspace", @"GWDesktopView: Command-Down detected - opening selection");
              [manager openSelectionInNewViewer: NO];
              return;
            }
        }

      if (character == NSCarriageReturnCharacter)
	{
	  [manager openSelectionInNewViewer: NO];
	  return;
	}

      if ((flags & NSCommandKeyMask) || (flags & NSControlKeyMask))
	{
	  if (character == NSBackspaceKey)
	    {
	      if (flags & NSShiftKeyMask)
		{
		  [manager emptyTrash];
		}
	      else
		{
		  [manager moveToTrash];
		}
	      return;
	    }
	}
      if ((character == 'o' || character == 'O') && (flags & NSCommandKeyMask))
	{
	  if (flags & NSShiftKeyMask)
	    {
	      [manager openSelectionAsFolder];
	    }
	  else
	    {
	      [manager openSelectionInNewViewer: NO];
	    }
	  return;
	}
      if (character == 0x01B) // Escape
	{
	  selectionMask = NSSingleSelectionMask;
	  selectionMask |= FSNCreatingSelectionMask;
	  [self unselectOtherReps: nil];
	  selectionMask = NSSingleSelectionMask;
	  [self selectionDidChange];
	  return;
	}
    }

  [super keyDown: theEvent];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
  [super mouseMoved: theEvent];
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect: rect];

  if (backImage && useBackImage)
    {
      // Draw the wallpaper independently for each monitor so it repeats
      // properly rather than being stretched across the virtual desktop.
      NSArray *screens = [NSScreen screens];

      for (NSUInteger si = 0; si < [screens count]; si++)
        {
          NSRect monFrame = [[screens objectAtIndex:si] frame];
          // Convert from screen coordinates to view-local coordinates
          // (screenFrame.origin is the view's origin in screen coords)
          NSRect localRect = NSMakeRect(monFrame.origin.x - screenFrame.origin.x,
                                        monFrame.origin.y - screenFrame.origin.y,
                                        monFrame.size.width,
                                        monFrame.size.height);

          // Only draw if this monitor intersects the dirty rect
          if (!NSIntersectsRect(localRect, rect))
            continue;

          NSSize imsize = [backImage size];
          BackImageStyle style = backImageStyle;

          if ((imsize.width >= localRect.size.width) || (imsize.height >= localRect.size.height))
            {
              if (style == BackImageTileStyle)
                style = BackImageCenterStyle;
            }

          [NSGraphicsContext saveGraphicsState];
          NSBezierPath *clipPath = [NSBezierPath bezierPathWithRect:localRect];
          [clipPath addClip];

          if (style == BackImageFitStyle)
            {
              [backImage drawInRect: localRect
                           fromRect: NSZeroRect
                          operation: NSCompositeSourceOver
                           fraction: 1.0
                     respectFlipped: YES
                              hints: nil];
            }
          else if (style == BackImageTileStyle)
            {
              CGFloat x = localRect.origin.x;
              CGFloat y = NSMaxY(localRect) - imsize.height;

              while (y > (localRect.origin.y - imsize.height))
                {
                  [backImage compositeToPoint: NSMakePoint(x, y)
                                    operation: NSCompositeSourceOver];
                  x += imsize.width;
                  if (x >= NSMaxX(localRect))
                    {
                      y -= imsize.height;
                      x = localRect.origin.x;
                    }
                }
            }
          else if (style == BackImageScaleStyle)
            {
              float imRatio = imsize.width / imsize.height;
              float monRatio = localRect.size.width / localRect.size.height;
              float scale;
              NSPoint imagePoint;

              if (imRatio > monRatio)
                {
                  scale = imsize.width / localRect.size.width;
                  imagePoint = NSMakePoint(localRect.origin.x,
                    localRect.origin.y + (localRect.size.height - imsize.height/scale) / 2);
                }
              else
                {
                  scale = imsize.height / localRect.size.height;
                  imagePoint = NSMakePoint(
                    localRect.origin.x + (localRect.size.width - imsize.width/scale) / 2,
                    localRect.origin.y);
                }
              [backImage drawInRect: NSMakeRect(imagePoint.x, imagePoint.y,
                                                imsize.width / scale, imsize.height / scale)
                           fromRect: NSZeroRect
                          operation: NSCompositeSourceOver
                           fraction: 1.0
                     respectFlipped: YES
                              hints: nil];
            }
          else
            {
              /* Center style */
              NSPoint imagePoint;
              imagePoint = NSMakePoint(
                localRect.origin.x + (localRect.size.width - imsize.width) / 2,
                localRect.origin.y + (localRect.size.height - imsize.height) / 2);
              [backImage compositeToPoint: imagePoint
                                operation: NSCompositeSourceOver];
            }

          [NSGraphicsContext restoreGraphicsState];
        }
    }

  if (dragIcon)
    {
      [dragIcon dissolveToPoint: dragPoint fraction: 0.3];
    }
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown) {
    NSPoint location = [theEvent locationInWindow];
    NSPoint selfloc = [self convertPoint: location fromView: nil];
    GWDesktopIcon *clickedIcon = nil;
    NSUInteger i;

    // Find which icon was clicked
    for (i = 0; i < [icons count]; i++) {
      GWDesktopIcon *icon = [icons objectAtIndex: i];
      if ([self mouse: selfloc inRect: [icon frame]]) {
        clickedIcon = icon;
        break;
      }
    }

    if (clickedIcon) {
      NSArray *selnodes = [self selectedNodes];

      // Check if clicked icon is part of selection
      if (![selnodes containsObject: [clickedIcon node]]) {
        return [super menuForEvent: theEvent];
      }

      return [[Workspace gworkspace] contextMenuForNodes: selnodes
                                              openTarget: [self window]
                                           openWithTarget: [Workspace gworkspace]
                                              infoTarget: [Workspace gworkspace]
                                         duplicateTarget: [self window]
                                           recycleTarget: [self window]
                                             ejectTarget: self
                                              openAction: @selector(openSelection:)
                                         duplicateAction: @selector(duplicateFiles:)
                                           recycleAction: @selector(recycleFiles:)
                                             ejectAction: @selector(ejectSelection:)
                                        includeOpenWith: NO];
    } else {
      // Right-clicked on empty desktop background
      NSMenu *menu = [[Workspace gworkspace] emptySpaceContextMenuForViewer: [self window]];

      // Add Workspace Preferences (desktop-specific)
      [menu addItem: [NSMenuItem separatorItem]];

      NSMenuItem *menuItem = [NSMenuItem new];
      [menuItem setTitle: NSLocalizedString(@"Workspace Preferences", @"")];
      [menuItem setTarget: [Workspace gworkspace]];
      [menuItem setAction: @selector(showPreferences:)];
      [menu addItem: menuItem];
      RELEASE (menuItem);

      return menu;
    }
  }

  return [super menuForEvent: theEvent];
}

- (void)ejectSelection:(id)sender
{
  NSArray *selnodes = [self selectedNodes];
  NSUInteger i;

  for (i = 0; i < [selnodes count]; i++) {
    FSNode *selnode = [selnodes objectAtIndex: i];
    if ([selnode isMountPoint]) {
      NSString *path = [selnode path];
      
      // Don't allow ejecting root filesystem
      if ([[Workspace gworkspace] isRootFilesystem: path]) {
        NSString *err = NSLocalizedString(@"Error", @"");
        NSString *msg = NSLocalizedString(@"You cannot eject the root filesystem", @"");
        NSString *buttstr = NSLocalizedString(@"OK", @"");
        NSRunAlertPanel(err, msg, buttstr, nil, nil);
        continue;
      }
      
      // Use unified unmount method
      [[Workspace gworkspace] unmountVolumeAtPath: path];
    }
  }
}

/* Batch reposition is handled by the base class (DS_Store + fdLocation).
 * No user-defaults persistence needed — DS_Store is the source of truth. */

@end


@implementation GWDesktopView (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode
{
  CREATE_AUTORELEASE_POOL(arp);
  NSArray *subNodes = [anode subNodes];
  NSMutableArray *unsorted = [NSMutableArray array];
  NSUInteger i;

  i = [icons count];
  while (i > 0)
    {
      FSNIcon *icon = [icons objectAtIndex: i-1];

      if ([[icon node] isMountPoint] == NO)
	{
	  [icon removeFromSuperview];
	  [icons removeObject: icon];
	}
      i--;
    }

  ASSIGN (node, anode);

  _gridCached = NO; /* icon properties may have changed */

  /* Folder-scoped icon-view settings come from the same tiered store all
   * viewers use (~/Desktop/.DS_Store via GWViewSettingsManager) as primary,
   * with the desktopinfo defaults loaded at init as fallback — so a size or
   * label-position set in a folder viewer of ~/Desktop (or by Finder) shows
   * on the desktop too.  Desktop-only state (background) stays in
   * desktopinfo. */
  {
    DSStoreInfo *dsInfo =
      [[GWViewSettingsManager managerForDirectoryPath: [anode path]] readSettings];
    BOOL changed = NO;

    if (dsInfo.hasIconSize && dsInfo.iconSize != iconSize)
      {
        iconSize = dsInfo.iconSize;
        changed = YES;
      }
    if (dsInfo.hasLabelPosition)
      {
        NSCellImagePosition pos =
          (dsInfo.labelPosition == DSStoreLabelPositionBottom)
            ? NSImageAbove : NSImageLeft;
        if (pos != iconPosition)
          {
            iconPosition = pos;
            changed = YES;
          }
      }
    if (changed)
      [self calculateGridSize];
  }

  for (i = 0; i < [subNodes count]; i++)
    {
      FSNode *subnode = [subNodes objectAtIndex: i];
      GWDesktopIcon *icon = [[GWDesktopIcon alloc] initForNode: subnode
						  nodeInfoType: infoType
						  extendedType: extInfoType
						      iconSize: iconSize
						  iconPosition: iconPosition
						     labelFont: labelFont
						     textColor: textColor
						     gridIndex: NSNotFound
						     dndSource: YES
						     acceptDnd: YES
						     slideBack: YES];
      [unsorted addObject: icon];
      RELEASE (icon);
    }

  /* Restore positions from fdLocation xattr and DS_Store (Mac-compatible),
   * through the same injected provider/store interfaces the base view uses.
   * The raw iloc (top-left CENTER) is the only stored representation;
   * conversion to view coordinates happens at layout time via the shared
   * mapping, so positions stay correct across re-tiles. */
  {
    NSString *folderPath = [anode path];
    FSNodeRep *rep = [FSNodeRep sharedInstance];

    /* Source 1: fdLocation xattr (per-file, primary).  FinderInfo defaults
     * to (0,0) when no position exists, so skip (0,0) and (-1,-1). */
    NSUInteger i;
    for (i = 0; i < [unsorted count]; i++)
      {
        FSNIcon *icon = [unsorted objectAtIndex: i];
        FSNode *nd = [icon node];
        if (!nd) continue;
        NSPoint floc = [[rep metadataProvider] iconPositionForPath: [nd path]];
        if ((floc.x > 0 || floc.y > 0) && floc.x != -1 && floc.y != -1)
          {
            FSNIconItemData *data = [icon placementData];
            data.ilocPosition = floc;
            data.placementMode = FSNIconPlacementModeManual;
          }
      }

    /* Source 2: DS_Store Iloc (folder-level, secondary fallback).
     * Only fills in icons NOT already positioned by fdLocation. */
    NSDictionary *stored =
      [[rep iconPositionStore] storedIconPositionsForFolder: folderPath];
    if ([stored count])
      {
        NSUInteger ii;
        for (ii = 0; ii < [unsorted count]; ii++)
          {
            FSNIcon *icon = [unsorted objectAtIndex: ii];
            FSNIconItemData *data = [icon placementData];
            if (data.placementMode == FSNIconPlacementModeManual) continue;

            NSValue *v = [stored objectForKey: [[icon node] name]];
            if (v == nil) continue;
            NSPoint iloc = [v pointValue];
            if (iloc.x != 0 || iloc.y != 0)
              {
                data.ilocPosition = iloc;
                data.placementMode = FSNIconPlacementModeManual;
              }
          }
      }
  }

  /* Add all icons to the view */
  for (i = 0; i < [unsorted count]; i++)
    {
      FSNIcon *icon = [unsorted objectAtIndex: i];
      [icons addObject: icon];
      [self addSubview: icon];
    }


  [self tile];
  [self setNeedsDisplay: YES];
  RELEASE (arp);
}

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  NSString *operation = [info objectForKey: @"operation"];
  NSString *source = [info objectForKey: @"source"];
  NSString *destination = [info objectForKey: @"destination"];
  NSArray *files = [info objectForKey: @"files"];
  NSMutableArray *newlyAdded = nil;
  NSUInteger i;

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [source lastPathComponent]];
      source = [source stringByDeletingLastPathComponent];
    }

  if ([[node path] isEqual: source]
      && ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceDestroyOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]))
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];

	  [self removeRepOfSubnode: subnode];
	}
    }

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [destination lastPathComponent]];
      destination = [destination stringByDeletingLastPathComponent];
    }

  /* Only add reps for files whose destination is this folder — otherwise a
   * file moved elsewhere would be re-added as a phantom desktop icon. */
  if ([[node path] isEqual: destination]
      && ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceCopyOperation]
	  || [operation isEqual: NSWorkspaceLinkOperation]
	  || [operation isEqual: NSWorkspaceDuplicateOperation]
	  || [operation isEqual: @"WorkspaceCreateDirOperation"]
	  || [operation isEqual: @"WorkspaceCreateFileOperation"]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]))
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];
	  FSNIcon *icon = [self repOfSubnode: subnode];

	  if (icon)
	    [icon setNode: subnode];
	  else
	    {
	      FSNIcon *added = [self addRepForSubnode: subnode];
	      if (added)
		{
		  if (!newlyAdded) newlyAdded = [NSMutableArray array];
		  [newlyAdded addObject: added];
		}
	    }
	}

      [self sortIcons];
    }

  [self checkLockedReps];
  [self tile];
  /* Persist positions of any items added to the desktop (honor view). */
  [self persistStoredPositionsForIcons: newlyAdded];
  [self setNeedsDisplay: YES];
  [self selectionDidChange];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSDragOperation sourceDragMask;
  NSArray *sourcePaths;
  NSString *basePath;
  NSString *nodePath;
  NSString *prePath;
  NSUInteger count;
  NSUInteger i;

  isDragTarget = NO;

  pb = [sender draggingPasteboard];
  if (pb && [[pb types] containsObject: NSFilenamesPboardType])
    {
      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
    }
  else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];
      sourcePaths = [pbDict objectForKey: @"paths"];
    }
  else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];
      sourcePaths = [pbDict objectForKey: @"paths"];
    }
  else
    {
      return NSDragOperationNone;
    }
  count = [sourcePaths count];
  if (count == 0)
    {
      return NSDragOperationNone;
    }
  dragLocalIcon = YES;
  for (i = 0; i < [sourcePaths count]; i++)
    {
      NSString *srcpath = [sourcePaths objectAtIndex: i];
      if ([self repOfSubnodePath: srcpath] == nil)
        {
          dragLocalIcon = NO;
        }
    }
  if (dragLocalIcon)
    {
      isDragTarget = YES;
      dragPoint = NSZeroPoint;
      DESTROY (dragIcon);
      return NSDragOperationEvery;
    }
  if ([node isWritable] == NO)
    {
      return NSDragOperationNone;
    }
  nodePath = [node path];
  basePath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
  if ([basePath isEqual: nodePath])
    {
      return NSDragOperationNone;
    }
  if ([sourcePaths containsObject: nodePath])
    {
      return NSDragOperationNone;
    }
  prePath = [NSString stringWithString: nodePath];
  while (1)
    {
      if ([sourcePaths containsObject: prePath])
        {
          return NSDragOperationNone;
        }
      if ([prePath isEqual: path_separator()])
        {
          break;
        }
      prePath = [prePath stringByDeletingLastPathComponent];
    }
  if ([node isDirectory] && [node isParentOfPath: basePath])
    {
      NSArray *subNodes = [node subNodes];
      for (i = 0; i < [subNodes count]; i++)
        {
          FSNode *nd = [subNodes objectAtIndex: i];
          if ([nd isDirectory])
            {
              for (NSUInteger j = 0; j < count; j++)
                {
                  NSString *fname = [[sourcePaths objectAtIndex: j] lastPathComponent];
                  if ([[nd name] isEqual: fname])
                    {
                      return NSDragOperationNone;
                    }
                }
            }
        }
    }
  isDragTarget = YES;
  forceCopy = NO;
  dragPoint = NSZeroPoint;
  DESTROY (dragIcon);

  sourceDragMask = [sender draggingSourceOperationMask];

  if (sourceDragMask & NSDragOperationMove)
    {
      if ([[NSFileManager defaultManager] isWritableFileAtPath: basePath])
	{
	  return NSDragOperationMove;
	}
      forceCopy = YES;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationCopy)
    {
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationLink)
    {
      return NSDragOperationLink;
    }

  isDragTarget = NO;
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
  NSPoint dpoint = [sender draggingLocation];

  if (isDragTarget == NO)
    {
      return NSDragOperationNone;
    }

  /* Track drop point for drag feedback without grid snapping */
  dragPoint = dpoint;
  if (dragIcon == nil)
    {
      NSImage *img = [sender draggedImage];
      if (img)
        ASSIGN (dragIcon, img);
    }

  if (sourceDragMask & NSDragOperationMove)
    {
      if (forceCopy)
	{
	  return NSDragOperationCopy;
	}
      return NSDragOperationMove;
    }
  if (sourceDragMask & NSDragOperationCopy)
    {
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationLink)
    {
      return NSDragOperationLink;
    }

  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  DESTROY (dragIcon);
  isDragTarget = NO;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return isDragTarget;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}



- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSDragOperation sourceDragMask;
  NSMutableArray *sourcePaths;
  NSString *operation, *source;
  NSMutableArray *files;
  NSMutableDictionary *opDict;
  NSString *trashPath;
  NSInteger i; // FIXME see if it can be made unsigned

  DESTROY (dragIcon);

  isDragTarget = NO;

  sourceDragMask = [sender draggingSourceOperationMask];
  pb = [sender draggingPasteboard];

  if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];

      [desktopApp concludeRemoteFilesDragOperation: pbData
				       atLocalPath: [node path]];
      return;
    }
  if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];

      [desktopApp lsfolderDragOperation: pbData
			concludedAtPath: [node path]];
      return;
    }

  sourcePaths = [[pb propertyListForType: NSFilenamesPboardType] mutableCopy];
  AUTORELEASE (sourcePaths);



  i = [sourcePaths count];
  while (i > 0)
    {
      NSString *srcpath = [sourcePaths objectAtIndex: i-1];
      FSNIcon *icon = [self repOfSubnodePath: srcpath];

      if (icon && [[icon node] isMountPoint])
	{
	  [sourcePaths removeObject: srcpath];
	}
      i--;
    }

  if ([sourcePaths count] == 0)
    {
      return;
    }

  source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  trashPath = [desktopApp trashPath];

  if ([source isEqual: trashPath])
    {
      operation = @"WorkspaceRecycleOutOperation";
    }
  else
    {
      if (sourceDragMask & NSDragOperationMove)
	{
	  operation = NSWorkspaceMoveOperation;
	}
      else if (sourceDragMask & NSDragOperationCopy)
	{
	  operation = NSWorkspaceCopyOperation;
	}
      else if (sourceDragMask & NSDragOperationLink)
	{
	  operation = NSWorkspaceLinkOperation;
	}
      else
	{
	  if ([[NSFileManager defaultManager] isWritableFileAtPath: source])
	    {
	      operation = NSWorkspaceMoveOperation;
	    }
	  else
	    {
	      operation = NSWorkspaceCopyOperation;
	    }
	}
    }

  files = [NSMutableArray array];
  for(i = 0; i < [sourcePaths count]; i++)
    {
      [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
    }

  opDict = [NSMutableDictionary dictionary];
  [opDict setObject: operation forKey: @"operation"];
  [opDict setObject: source forKey: @"source"];
  [opDict setObject: [node path] forKey: @"destination"];
  [opDict setObject: files forKey: @"files"];

  [desktopApp performFileOperation: opDict];
}

@end


@implementation GWDesktopView (BackgroundColors)

- (NSColor *)currentColor
{
  return backColor;
}

- (void)setCurrentColor:(NSColor *)color
{
  ASSIGN (backColor, color);
  [[self window] setBackgroundColor: backColor];
  [self setNeedsDisplay: YES];
}

- (void)createBackImage:(NSImage *)image
{
  ASSIGN(backImage, image);
}

- (NSImage *)backImage
{
  return backImage;
}

- (NSString *)backImagePath
{
  return imagePath;
}

- (void)setBackImageAtPath:(NSString *)impath
{
  CREATE_AUTORELEASE_POOL (pool);
  NSImage *image = [[NSImage alloc] initWithContentsOfFile: impath];

  if (image)
    {
      ASSIGN (imagePath, impath);
      [self createBackImage: image];
      RELEASE (image);
      [self setNeedsDisplay: YES];
      [self updateDefaults];
    }
  RELEASE (pool);
}

- (BOOL)useBackImage
{
  return useBackImage;
}

- (void)setUseBackImage:(BOOL)value
{
  useBackImage = value;
  [self setNeedsDisplay: YES];
  [self updateDefaults];
}

- (BackImageStyle)backImageStyle
{
  return backImageStyle;
}

- (void)setBackImageStyle:(BackImageStyle)style
{
  if (style != backImageStyle)
    {
      backImageStyle = style;
      if (backImage)
	{
	  [self setBackImageAtPath: imagePath];
	  [self setNeedsDisplay: YES];
	}
      else
        {
          // No image set, just save the style preference
          [self updateDefaults];
        }
    }
}

/* Override addRepForSubnode: to create GWDesktopIcon instances
 * (with proper label rendering and double-click handling) instead of
 * plain FSNIcon.  This is used when volume mount icons are added via
 * newVolumeMountedAtPath:, among others. */
- (id)addRepForSubnode:(FSNode *)anode
{
  /* Never display internal metadata files */
  NSString *fname = [anode name];
  if ([fname isEqualToString: @".DS_Store"]
      || [fname hasPrefix: @"._"]
      || [fname isEqualToString: @"__MACOSX"])
    return nil;

  CREATE_AUTORELEASE_POOL(arp);
  GWDesktopIcon *icon = [[GWDesktopIcon alloc] initForNode: anode
                                              nodeInfoType: infoType
                                              extendedType: extInfoType
                                                  iconSize: iconSize
                                              iconPosition: iconPosition
                                                 labelFont: labelFont
                                                 textColor: textColor
                                                 gridIndex: NSNotFound
                                                 dndSource: YES
                                                 acceptDnd: YES
                                                 slideBack: YES];
  [icons addObject: icon];
  [self addSubview: icon];
  RELEASE (icon);
  RELEASE (arp);

  return icon;
}

@end
