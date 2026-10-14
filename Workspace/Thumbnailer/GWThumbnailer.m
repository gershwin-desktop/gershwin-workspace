/* GWThumbnailer.m
 *  
 * Copyright (C) 2003-2015 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola <rm@gnu.org>
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

#include <math.h>
#include <limits.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#ifndef _WIN32
#import <dispatch/dispatch.h>
#endif
#import "GWThumbnailer.h"
#import "GWThumbnailStore.h"

static Thumbnailer *sharedThumbnailerInstance = nil;
static NSInteger countInstances = 0;

/* The automatic cleanup waits until startup is long over, then repeats at
 * most daily: the store only has to keep up with files that came and went,
 * no reason to compete with the desktop coming up. */
#define THUMBNAIL_CHECK_FIRST_DELAY 60.0
#define THUMBNAIL_CHECK_INTERVAL 86400.0

/* The Software text chunk Workspace's entries carried in ~/.cache/thumbnails. */
static NSString * const OldCacheSoftware = @"Gershwin Workspace";



@implementation Thumbnailer

/* Immortal singleton — one Thumbnailer for the lifetime of the process.
   retain/release/autorelease are no-ops (overridden below) so callers
   like Workspace.m:2595 that do `[t release]` after sharedThumbnailer
   don't trip the legacy release-counted dealloc whose partial-cleanup
   branch left the singleton in a half-dead zombie state under
   concurrent file-watch storms (e.g. pasting many files at once). */

+ (Thumbnailer *)sharedThumbnailer
{
  static Thumbnailer *instance = nil;
  /* GNUstep thread-safe singleton, no libdispatch. */
  @synchronized ([Thumbnailer class])
    {
      if (instance == nil)
        {
          instance = [[Thumbnailer allocWithZone: NULL] init];
        }
    }
  return instance;
}

- (id)retain                  { return self; }
- (oneway void)release        { /* no-op: immortal singleton */ }
- (id)autorelease             { return self; }
- (NSUInteger)retainCount     { return NSUIntegerMax; }

- (void)dealloc
{
  countInstances--;

  if (countInstances < 0)
  if (countInstances == 0)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self];

      if (timer && [timer isValid])
        [timer invalidate];
  
      RELEASE (thumbnailers);
      RELEASE (extProviders);
      RELEASE (store);
      DESTROY (conn);
      DESTROY (dictLock);
      RELEASE (pathsInProcessing);
      sharedThumbnailerInstance = nil;
      [super dealloc];
    }
}

- (id)init
{
  self = [super init];

  if (self) {
    if (!dictLock)
      dictLock = [[NSLock alloc] init];

    pathsInProcessing = [[NSMutableArray alloc] init];

    fm = [NSFileManager defaultManager];
    extProviders = [NSMutableDictionary new];
    [self loadThumbnailers];

    store = RETAIN ([GWThumbnailStore sharedStore]);
    if (store == nil) {
      [self release];
      return nil;
    }
  }

  return self;
}

- (void)loadThumbnailers
{
  NSString *bundlesDir;
  NSEnumerator *enumerator;
  NSMutableArray *bundlesPaths;
  NSArray *bPaths;
  NSUInteger i;
  
  RELEASE (thumbnailers);
  thumbnailers = [NSMutableArray new];
  
  bundlesPaths = [NSMutableArray array]; 

  bPaths = [self bundlesWithExtension: @"thumb" 
                          inDirectory: [[NSBundle mainBundle] resourcePath]];
  NSLog(@"Thumbnailer search in app bundle: %@ -> %lu bundles", [[NSBundle mainBundle] resourcePath], (unsigned long)[bPaths count]);
  [bundlesPaths addObjectsFromArray: bPaths];

  enumerator = [NSSearchPathForDirectoriesInDomains
		 (NSLibraryDirectory, NSAllDomainsMask, YES) objectEnumerator];
  while ((bundlesDir = [enumerator nextObject]) != nil)
    {
      bundlesDir = [bundlesDir stringByAppendingPathComponent: @"Bundles"];
      NSArray *found = [self bundlesWithExtension: @"thumb" inDirectory: bundlesDir];
      NSLog(@"Thumbnailer search in %@ -> %lu bundles", bundlesDir, (unsigned long)[found count]);
      [bundlesPaths addObjectsFromArray: found];
    }

  NSLog(@"Total thumbnailer bundles found: %lu", (unsigned long)[bundlesPaths count]);

  for (i = 0; i < [bundlesPaths count]; i++)
    {
      NSString *bpath = [bundlesPaths objectAtIndex: i];
      NSBundle *bundle = [NSBundle bundleWithPath: bpath]; 
      
      if (bundle)
        {
          Class principalClass = [bundle principalClass];
          
          if (principalClass)
            {
              if ([principalClass conformsToProtocol: @protocol(TMBProtocol)])
                {
                  id<TMBProtocol> tmb = [[principalClass alloc] init];

                  [self addThumbnailer: tmb];
                  RELEASE ((id)tmb);
          NSLog(@"Thumbnailer loaded: %@", bpath);
              }
            else
              {
                NSLog(@"Thumbnailer bundle %@ does not conform to TMBProtocol", bpath);
              }
          }
        else
          {
            NSLog(@"Thumbnailer bundle %@ has no principal class", bpath);
          }
      }
    else
      {
        NSLog(@"Thumbnailer bundle %@ could not be loaded", bpath);
      }
    }
  NSLog(@"Thumbnailers loaded: %lu", (unsigned long)[thumbnailers count]);
}

- (BOOL)addThumbnailer:(id)tmb
{
  NSString *description = [tmb description];
  BOOL found = NO;
  NSUInteger i = 0;
  
  if ([tmb conformsToProtocol: @protocol(TMBProtocol)])
    {
      for (i = 0; i < [thumbnailers count]; i++)
	{
	  id<TMBProtocol> thumb = [thumbnailers objectAtIndex: i];
	  
	  if ([[thumb description] isEqual: description])
	    {
	      found = YES;
	      break;
	    }
	}

      if (found == NO)
	{
	  [thumbnailers addObject: tmb];
	  return YES;
	}
    }
  
  return NO;
}

- (id)thumbnailerForPath:(NSString *)path
{
  NSUInteger i;
  
  for (i = 0; i < [thumbnailers count]; i++)
    {
      id<TMBProtocol> thumb = [thumbnailers objectAtIndex: i];
      
      if ([thumb canProvideThumbnailForPath: path])
	{
	  return thumb;
	}
    }  

  return nil;
}

/* Where an earlier Workspace build kept its AppImage icons. */
static NSString *
OldCacheDirectory(void)
{
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *cache = [env objectForKey: @"XDG_CACHE_HOME"];

  if ([cache isAbsolutePath] == NO)
    {
      cache = [NSHomeDirectory() stringByAppendingPathComponent: @".cache"];
    }
  return [cache stringByAppendingPathComponent: @"thumbnails"];
}

- (void)postDeleted:(NSArray *)deleted
{
  if ([deleted count])
    {
      NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
        deleted, @"deleted", [NSArray array], @"created", nil];

      [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName: GWThumbnailsDidChangeNotification
                      object: nil
                    userInfo: info];
    }
}

- (void)checkThumbnails:(id)sender
{
  [self postDeleted: [store removeStaleEntries]];
  [store flush];
}

/* Right at start, so the icons an earlier build kept are there for the
 * first views; once moved they are gone from there, so later starts find
 * nothing to do. */
- (void)importOldCacheInBackground:(id)unused
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUInteger moved;

  [NSThread setThreadPriority: 0.0];
  moved = [store importEntriesFromCacheDirectory: OldCacheDirectory()
                                        software: OldCacheSoftware];
  if (moved > 0)
    {
      NSLog(@"Moved %lu cached icons from %@ to %@", (unsigned long)moved,
            OldCacheDirectory(), [store directory]);
      [store flush];
    }
  [arp release];
}

- (void)startAutomaticChecks
{
  [[NSNotificationCenter defaultCenter]
    addObserver: self
       selector: @selector(fileSystemDidChange:)
           name: @"GWFileSystemDidChangeNotification"
         object: nil];
  [NSThread detachNewThreadSelector: @selector(importOldCacheInBackground:)
                           toTarget: self
                         withObject: nil];
  [self scheduleCheckAfter: THUMBNAIL_CHECK_FIRST_DELAY];
}

- (void)scheduleCheckAfter:(NSTimeInterval)delay
{
  [NSTimer scheduledTimerWithTimeInterval: delay
                                   target: self
                                 selector: @selector(startCheck:)
                                 userInfo: nil
                                  repeats: NO];
}

/* The check reads the head of every stored file, so it runs on a
 * low-priority GNUstep thread (not libdispatch, see makeThumbnails:),
 * never on the UI. */
- (void)startCheck:(NSTimer *)t
{
  [NSThread detachNewThreadSelector: @selector(checkInBackground:)
                           toTarget: self
                         withObject: nil];
}

- (void)checkInBackground:(id)unused
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  [NSThread setThreadPriority: 0.0];
  [self checkThumbnails: nil];
  [self performSelectorOnMainThread: @selector(checkFinished:)
                         withObject: nil
                      waitUntilDone: NO];
  [arp release];
}

- (void)checkFinished:(id)unused
{
  [self scheduleCheckAfter: THUMBNAIL_CHECK_INTERVAL];
}

/* Workspace moving, renaming, trashing or deleting files itself is the
 * cheap moment to drop their entries, and those of everything inside a
 * moved folder, instead of waiting for the daily check. Entries whose
 * source is still there are left alone, so copies cost only a stat. */
+ (NSArray *)sourcePathsOfFileOperation:(id)info
{
  NSString *source;
  NSArray *files;
  NSMutableArray *paths;
  NSUInteger i;

  if ([info isKindOfClass: [NSDictionary class]] == NO)
    {
      return [NSArray array];
    }
  source = [info objectForKey: @"source"];
  files = [info objectForKey: @"files"];
  if ([[info objectForKey: @"operation"] isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [source lastPathComponent]];
      source = [source stringByDeletingLastPathComponent];
    }
  if ([source length] == 0)
    {
      return [NSArray array];
    }
  paths = [NSMutableArray arrayWithCapacity: [files count]];
  for (i = 0; i < [files count]; i++)
    {
      [paths addObject: [source stringByAppendingPathComponent: [files objectAtIndex: i]]];
    }
  return paths;
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  NSArray *paths = [Thumbnailer sourcePathsOfFileOperation: [notif object]];

  if ([paths count] > 0)
    {
      [NSThread detachNewThreadSelector: @selector(removeEntriesInBackground:)
                               toTarget: self
                             withObject: paths];
    }
}

- (void)removeEntriesInBackground:(NSArray *)paths
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  [self postDeleted: [store removeStaleEntriesForPaths: paths]];
  [arp release];
}

- (void)_makeThumbnails:(NSString *)path
{
  NSData *data;
  NSMutableArray *added;
  BOOL isdir;
  NSUInteger i;
  NSAutoreleasePool *arp;

  arp = [NSAutoreleasePool new];
  added = [NSMutableArray array];

  if ([fm fileExistsAtPath: path isDirectory: &isdir] && isdir)
    {
      NSArray *contents = [fm directoryContentsAtPath: path];
      
      for (i = 0; i < [contents count]; i++)
        {
          NSString *fname = [contents objectAtIndex: i];
          NSString *fullPath = [path stringByAppendingPathComponent: fname];
          BOOL alreadyHave;

          alreadyHave = ([store fileForPath: fullPath
                                       kind: GWThumbnailKindThumbnail
                                     source: nil] != nil);

          if (alreadyHave)
            continue;

          id<TMBProtocol> tmb = [self thumbnailerForPath: fullPath];
          
          if (tmb)
            {
              data = [tmb makeThumbnailForPath: fullPath];
              
              if (data && [self registerThumbnailData: data 
                                              forPath: fullPath
                                        nameExtension: [tmb fileNameExtension]])
                {
                  [added addObject: fullPath];
                }
            }
        }
    }
      
    if ([added count]) {
      NSMutableDictionary *info = [NSMutableDictionary dictionary];

      [info setObject: added forKey: @"created"];	

      [store flush];

      [[NSDistributedNotificationCenter defaultCenter] 
	postNotificationName: GWThumbnailsDidChangeNotification
	object: nil
	userInfo: info];
    }
  [dictLock lock];
  [pathsInProcessing removeObject:path];
  [dictLock unlock];
  [arp drain];
}

- (void)makeThumbnails:(NSString *)path
{
  /* Check-and-insert must be one atomic step under dictLock: two threads
   * racing makeThumbnails: for the same path (several folders opened at
   * once) must not both pass the containsObject: test and both detach a
   * worker for it. */
  [dictLock lock];
  if ([pathsInProcessing containsObject:path])
    {
      [dictLock unlock];
      return;
    }
  [pathsInProcessing addObject:path];
  [dictLock unlock];
  /* GNUstep thread, not libdispatch: a GCD worker thread running ObjC races
   * the main thread's +load dispatch and crashes the app (GPF in libobjc's
   * load_messages_insert) - the window_placement flake. */
  [NSThread detachNewThreadSelector: @selector(_makeThumbnails:)
                           toTarget: self
                         withObject: path];
}

- (void)_removeThumbnails:(NSString *)path
{
  NSMutableArray *deleted;
  BOOL isdir;
  NSUInteger i;
  NSAutoreleasePool *arp;

  arp = [NSAutoreleasePool new];

  {
    deleted = [NSMutableArray array];

    if ([fm fileExistsAtPath: path isDirectory: &isdir])
      {
        if (isdir) {
          NSArray *contents = [fm directoryContentsAtPath: path];
          
          for (i = 0; i < [contents count]; i++) {
            NSString *fname = [contents objectAtIndex: i];
            NSString *fullPath = [path stringByAppendingPathComponent: fname];

            if ([self removeThumbnailForPath: fullPath]) {
              [deleted addObject: fullPath];
            }
          }
        } else {
          if ([self removeThumbnailForPath: path]) {
            [deleted addObject: path];
          }
        }
      }
        
    if ([deleted count])
      {
      NSMutableDictionary *info = [NSMutableDictionary dictionary];
      
      [info setObject: deleted forKey: @"deleted"];	

      [store flush];
      
      [[NSDistributedNotificationCenter defaultCenter] 
            postNotificationName: GWThumbnailsDidChangeNotification
                          object: nil 
                        userInfo: info];
      }
  }

  /* Always release the in-processing marker, even when there was nothing
   * to remove - the old early return above left the path in
   * pathsInProcessing forever, so a later removeThumbnails: for the same
   * path silently became a permanent no-op. */
  [dictLock lock];
  [pathsInProcessing removeObject:path];
  [dictLock unlock];
  [arp drain];
}


- (void)removeThumbnails:(NSString *)path
{
  /* Same atomic check-and-insert as makeThumbnails:; see there. */
  [dictLock lock];
  if ([pathsInProcessing containsObject:path])
    {
      [dictLock unlock];
      return;
    }
  [pathsInProcessing addObject:path];
  [dictLock unlock];
  /* GNUstep thread, not libdispatch; see makeThumbnails:. */
  [NSThread detachNewThreadSelector: @selector(_removeThumbnails:)
                           toTarget: self
                         withObject: path];
}

- (BOOL)registerThumbnailData:(NSData *)data
                      forPath:(NSString *)path
                nameExtension:(NSString *)ext
{
  /* The bundles hand back whatever format they like; the store keeps it
   * as PNG, at most at its one size, with the source's stamp. */
  return [store storeImageData: data
                       forPath: path
                          kind: GWThumbnailKindThumbnail
                        source: nil] != nil;
}

/* Only thumbnails: icons kept in the same store are not this command's. */
- (BOOL)removeThumbnailForPath:(NSString *)path
{
  if ([[[store entryForPath: path] objectForKey: GWThumbnailEntryKind]
        isEqualToString: GWThumbnailKindThumbnail] == NO)
    {
      return NO;
    }
  return [store removeEntryForPath: path];
}

- (NSArray *)bundlesWithExtension:(NSString *)extension 
		      inDirectory:(NSString *)dirpath
{
  NSMutableArray *bundleList = [NSMutableArray array];
  NSEnumerator *enumerator;
  NSString *dir;
  BOOL isDir;
    
  if ((([fm fileExistsAtPath: dirpath isDirectory: &isDir]) && isDir) == NO) {
    return nil;
  }
	  
  enumerator = [[fm directoryContentsAtPath: dirpath] objectEnumerator];
  while ((dir = [enumerator nextObject])) {
    if ([[dir pathExtension] isEqualToString: extension])
      {
        [bundleList addObject: [dirpath stringByAppendingPathComponent: dir]];
      }
  }
  
  return bundleList;
}



@end

