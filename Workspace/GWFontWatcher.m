/* GWFontWatcher.m

   Copyright (C) 2026 Free Software Foundation, Inc.

   Author: Gershwin Developers
   Date:   September 2026

   This file is part of Gershwin Workspace.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110 USA.
*/

#import <Foundation/Foundation.h>
#import "GWFontWatcher.h"
#import "Workspace.h"

/* The GNUstep distributed notification that tells all running apps
   to refresh their font lists (defined in libs-gui/NSFontManager.m). */
extern NSString * const GSFontManagerAvailableFontsDidChangeNotification;

/* Debounce interval in seconds.  Font drops (especially drag-and-drop
   of a folder containing multiple fonts) generate a burst of file
   system events; we wait this long after the last event before
   rebuilding the cache. */
static const NSTimeInterval kFontCacheDebounceInterval = 2.0;

NSString * const GWFontCacheDidChangeNotification = @"GWFontCacheDidChangeNotification";

@implementation GWFontWatcher

- (instancetype)initWithWorkspace:(Workspace *)workspace
{
  self = [super init];
  if (self)
    {
      _workspace = workspace;
      _cacheUpdatePending = NO;
      _debounceTimer = nil;

      /* Build the set of font directories to watch. */
      NSMutableSet *paths = [NSMutableSet set];

      /* System font directory — always /System/Library/Fonts
         on Gershwin, matching fonts.conf. */
      [paths addObject: @"/System/Library/Fonts"];

      /* User font directory — ~/Library/Fonts.
         NSHomeDirectory() returns the GNUstep home which is
         /Local/Users/<user> on this system. */
      NSString *homeFonts = [NSHomeDirectory()
        stringByAppendingPathComponent: @"Library/Fonts"];
      [paths addObject: homeFonts];

      /* Also watch ~/.local/share/fonts if it exists, which is the
         standard XDG user font directory. */
      NSString *xdgFonts = [NSHomeDirectory()
        stringByAppendingPathComponent: @".local/share/fonts"];
      NSFileManager *fm = [NSFileManager defaultManager];
      BOOL isDir = NO;
      if ([fm fileExistsAtPath: xdgFonts isDirectory: &isDir] && isDir)
        {
          [paths addObject: xdgFonts];
        }

      _fontDirectoryPaths = [paths copy];
    }
  return self;
}

- (void)dealloc
{
  [_debounceTimer invalidate];
  [_debounceTimer release];
  [_fontDirectoryPaths release];
  [super dealloc];
}

- (BOOL)isFontDirectoryPath:(NSString *)path
{
  if (path == nil)
    return NO;

  NSString *standardized = [path stringByStandardizingPath];

  /* Check if the path IS one of the font directories, or is
     inside one (e.g. a subdirectory like ChicagoKare/). */
  NSEnumerator *e = [_fontDirectoryPaths objectEnumerator];
  NSString *fontDir;
  while ((fontDir = [e nextObject]) != nil)
    {
      if ([standardized hasPrefix: fontDir])
        return YES;
    }

  return NO;
}

- (NSArray *)fontDirectoryPaths
{
  return [_fontDirectoryPaths allObjects];
}

- (BOOL)isCacheUpdatePending
{
  return _cacheUpdatePending;
}

- (void)fontDirectoryDidChange:(NSString *)path
{
  if (![self isFontDirectoryPath: path])
    return;

  /* Debounce: invalidate any pending timer and start a new one.
     This coalesces rapid successive events (e.g. copying a folder
     of fonts). */
  if (_debounceTimer != nil)
    {
      [_debounceTimer invalidate];
      [_debounceTimer release];
      _debounceTimer = nil;
    }

  _cacheUpdatePending = YES;

  _debounceTimer = [[NSTimer scheduledTimerWithTimeInterval: kFontCacheDebounceInterval
                                                     target: self
                                                   selector: @selector(_debounceTimerFired:)
                                                   userInfo: nil
                                                    repeats: NO] retain];
}

- (void)_debounceTimerFired:(NSTimer *)timer
{
  [_debounceTimer release];
  _debounceTimer = nil;

  [self performFontCacheUpdate];
}

- (void)performFontCacheUpdate
{
  _cacheUpdatePending = NO;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *fcCachePath = nil;

  /* Locate fc-cache.  Try the GNUstep system tools path first,
     then fall back to a PATH search. */
  NSArray *toolPaths = [NSArray arrayWithObjects:
    @"/usr/bin/fc-cache",
    @"/usr/local/bin/fc-cache",
    @"/System/Library/Tools/fc-cache",
    nil];

  NSEnumerator *e = [toolPaths objectEnumerator];
  NSString *candidate;
  while ((candidate = [e nextObject]) != nil)
    {
      if ([fm isExecutableFileAtPath: candidate])
        {
          fcCachePath = candidate;
          break;
        }
    }

  if (fcCachePath == nil)
    {
      /* fc-cache not found — skip the update silently. */
      NSLog(@"GWFontWatcher: fc-cache not found, skipping font cache update");
      return;
    }

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath: fcCachePath];
  [task setArguments: [NSArray arrayWithObject: @"-f"]];
  [task setEnvironment: [NSDictionary dictionaryWithObject: @"/System/Library/Preferences"
                                                    forKey: @"FONTCONFIG_PATH"]];

  NS_DURING
    {
      [task launch];
      [task waitUntilExit];

      int status = [task terminationStatus];
      if (status == 0)
        {
          /* Success — notify all GNUstep apps to refresh their fonts. */
          [[NSDistributedNotificationCenter defaultCenter]
            postNotificationName: GSFontManagerAvailableFontsDidChangeNotification
                          object: nil];

          /* Also post our own notification for Workspace-internal observers. */
          [[NSNotificationCenter defaultCenter]
            postNotificationName: GWFontCacheDidChangeNotification
                          object: self];

          NSLog(@"GWFontWatcher: font cache updated successfully");
        }
      else
        {
          NSLog(@"GWFontWatcher: fc-cache exited with status %d", status);
        }
    }
  NS_HANDLER
    {
      NSLog(@"GWFontWatcher: failed to run fc-cache: %@", localException);
    }
  NS_ENDHANDLER;

  [task release];
}

@end
