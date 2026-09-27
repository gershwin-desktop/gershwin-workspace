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
#import <dispatch/dispatch.h>
#import "GWThumbnailer.h"

static Thumbnailer *sharedThumbnailerInstance = nil;
static NSInteger countInstances = 0;

static NSString *GWThumbnailsDidChangeNotification = @"GWThumbnailsDidChangeNotification";



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
      RELEASE (thumbnailDir);
      RELEASE (dictPath);
      RELEASE (thumbsDict);
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
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id entry;
    BOOL isdir;

    if (!dictLock)
      dictLock = [[NSLock alloc] init];

    pathsInProcessing = [[NSMutableArray alloc] init];

    fm = [NSFileManager defaultManager];
    extProviders = [NSMutableDictionary new];
    [self loadThumbnailers];

    entry = [defaults objectForKey: @"thumbref"];
    if (entry) {
      thumbref = [(NSNumber *)entry longValue];
    } else {
      thumbref = 0;
    }
    
    thumbnailDir = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject];
    thumbnailDir = [thumbnailDir stringByAppendingPathComponent: @"Thumbnails"];
    RETAIN (thumbnailDir);

    if (([fm fileExistsAtPath: thumbnailDir isDirectory: &isdir] && isdir) == NO) {
      if ([fm createDirectoryAtPath: thumbnailDir attributes: nil] == NO) {
        return nil;
      }
    }
    
    ASSIGN (dictPath, [thumbnailDir stringByAppendingPathComponent: @"thumbnails.plist"]);    
    
    if ([fm fileExistsAtPath: dictPath]) {
      NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile: dictPath];
    
      if (dict) {
        thumbsDict = [dict mutableCopy];
      } else {
        thumbsDict = [NSMutableDictionary new];
      }
    } else {
      thumbsDict = [NSMutableDictionary new];
    }  

    [self writeDictToFile];



    /* FIXME: this could be a problem with different instances for View
    timer = [NSTimer scheduledTimerWithTimeInterval: 10.0 target: self 
          										      selector: @selector(checkThumbnails:) 
                                                userInfo: nil repeats: YES];   
    */                                          
  }

  return self;
}

- (void)writeDictToFile
{
  [dictLock lock];
  [thumbsDict writeToFile: dictPath atomically: YES];
  [dictLock unlock];
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

- (void)checkThumbnails:(id)sender
{
  /* thumbsDict is also written from the detached make/remove worker
   * threads (see makeThumbnails:/removeThumbnails:), so every read or
   * mutation here has to go through dictLock too, not just the plist
   * write at the end. */
  [dictLock lock];
  BOOL hasEntries = (thumbsDict != nil) && ([thumbsDict count] > 0);
  NSArray *paths = hasEntries ? RETAIN ([thumbsDict allKeys]) : nil;
  [dictLock unlock];

  if (hasEntries) {
    NSMutableArray *deleted = [NSMutableArray array];
    NSUInteger i;

    for (i = 0; i < [paths count]; i++) {
      NSString *path = [paths objectAtIndex: i];

      [dictLock lock];
      NSString *tname = [thumbsDict objectForKey: path];
      [dictLock unlock];

      if ([fm fileExistsAtPath: path] == NO) {
        NSString *tpath = [thumbnailDir stringByAppendingPathComponent: tname];

        if ([fm fileExistsAtPath: tpath]) {
          [fm removeFileAtPath: tpath handler: nil];
        }

        [deleted addObject: path];
        [dictLock lock];
        [thumbsDict removeObjectForKey: path];
        [dictLock unlock];
      }
    }

    RELEASE (paths);

    if ([deleted count])
      {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];

        [info setObject: deleted forKey: @"deleted"];	
        [info setObject: [NSArray array] forKey: @"created"];

        [self writeDictToFile];
      
        [[NSDistributedNotificationCenter defaultCenter] 
            postNotificationName: GWThumbnailsDidChangeNotification
                          object: nil 
                        userInfo: info];
      }
  }   
}

- (NSString *)nextThumbName
{
  thumbref++;
  if (thumbref >= (LONG_MAX - 1)) {
    thumbref = 0;
  }
  return [NSString stringWithFormat: @"%lx", thumbref];
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

          [dictLock lock];
          alreadyHave = ([thumbsDict objectForKey: fullPath] != nil);
          [dictLock unlock];

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
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSMutableDictionary *info = [NSMutableDictionary dictionary];

      [defaults setObject: [NSNumber numberWithLong: thumbref] 
                   forKey: @"thumbref"];
      [defaults synchronize];
	
      [info setObject: added forKey: @"created"];	

      [self writeDictToFile];

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
  BOOL hasEntries;
  NSUInteger i;
  NSAutoreleasePool *arp;

  arp = [NSAutoreleasePool new];

  [dictLock lock];
  hasEntries = (thumbsDict != nil) && ([thumbsDict count] > 0);
  [dictLock unlock];

  if (hasEntries) {
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

      [self writeDictToFile];
      
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
  if (data && [data length]) {
    NSString *tname;
    NSString *tpath;

    /* nextThumbName reads and increments thumbref, and the dict entry it
     * feeds must land as one step - lock across the whole naming/write/
     * bookkeeping sequence so two threads registering thumbnails at the
     * same time can never hand out the same tname or race on thumbsDict. */
    [dictLock lock];

    tname = [self nextThumbName];
    tname = [tname stringByAppendingPathExtension: ext];
    tpath = [thumbnailDir stringByAppendingPathComponent: tname];

    if ([data writeToFile: tpath atomically: YES]) {
      NSString *oldtname = [thumbsDict objectForKey: path];

      if (oldtname) {
        NSString *oldtpath = [thumbnailDir stringByAppendingPathComponent: oldtname];

        if ([fm fileExistsAtPath: oldtpath]) {
          [fm removeFileAtPath: oldtpath handler: nil];
        }
      }

      [thumbsDict setObject: tname forKey: path];
      [dictLock unlock];
      return YES;
    } else {
      [dictLock unlock];
      return NO;
    }
  }

  return NO;
}

- (BOOL)removeThumbnailForPath:(NSString *)path
{
  NSString *tname;
  BOOL removed = NO;

  [dictLock lock];
  tname = [thumbsDict objectForKey: path];

  if (tname) {
    NSString *tpath = [thumbnailDir stringByAppendingPathComponent: tname];

    if ([fm fileExistsAtPath: tpath]) {
      [fm removeFileAtPath: tpath handler: nil];
    }
    [thumbsDict removeObjectForKey: path];
    removed = YES;
  }

  [dictLock unlock];
  return removed;
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

