/* fswatcher-kqueue.m
 *
 * Copyright (C) 2007-2015 Free Software Foundation, Inc.
 *
 * kqueue (BSD) backend for fswatcher, mirroring the inotify backend's
 * client/protocol behaviour.  Only compiled on systems with <sys/event.h>.
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

#import "fswatcher-kqueue.h"
#include "config.h"
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdint.h>


static BOOL	auto_stop = NO;		/* Should we shut down when unused? */

static NSString *GWWatchedPathDeleted = @"GWWatchedPathDeleted";
static NSString *GWWatchedFileModified = @"GWWatchedFileModified";


@implementation	FSWClientInfo

- (void)dealloc
{
  RELEASE (conn);
  RELEASE (client);
  RELEASE (wpaths);
  [super dealloc];
}

- (id)init
{
  self = [super init];

  if (self)
    {
      client = nil;
      conn = nil;
      wpaths = [[NSCountedSet alloc] initWithCapacity: 1];
      global = NO;
    }

  return self;
}

- (void)setConnection:(NSConnection *)connection
{
  ASSIGN (conn, connection);
}

- (NSConnection *)connection
{
  return conn;
}

- (void)setClient:(id <FSWClientProtocol>)clnt
{
  ASSIGN (client, clnt);
}

- (id <FSWClientProtocol>)client
{
  return client;
}

- (void)addWatchedPath:(NSString *)path
{
  [wpaths addObject: path];
}

- (void)removeWatchedPath:(NSString *)path
{
  [wpaths removeObject: path];
}

- (BOOL)isWathchingPath:(NSString *)path
{
  return [wpaths containsObject: path];
}

- (NSSet *)watchedPaths
{
  return wpaths;
}

- (void)setGlobal:(BOOL)value
{
  global = value;
}

- (BOOL)isGlobal
{
  return global;
}

@end


@implementation	FSWatcher

- (void)dealloc
{
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++)
    {
      NSConnection *connection = [[clientsInfo objectAtIndex: i] connection];

      if (connection)
        {
          [nc removeObserver: self
                         name: NSConnectionDidDieNotification
                       object: connection];
        }
    }

  if (conn) {
    [nc removeObserver: self
                  name: NSConnectionDidDieNotification
                object: conn];
  }

  [dnc removeObserver: self];

  RELEASE (clientsInfo);
  if (kq != -1)
    {
      close (kq);
      kq = -1;
    }
  NSZoneFree (NSDefaultMallocZone(), (void *)watchers);
  NSZoneFree (NSDefaultMallocZone(), (void *)watchDescrMap);
  freeTree(includePathsTree);
  freeTree(excludePathsTree);
  RELEASE (excludedSuffixes);
  DESTROY (watchersLock);

  [super dealloc];
}

- (id)init
{
  self = [super init];

  if (self)
    {
      kq = kqueue();

      if (kq == -1)
        {
          DESTROY (self);
          return self;
        }

      fm = [NSFileManager defaultManager];
      nc = [NSNotificationCenter defaultCenter];
      dnc = [NSDistributedNotificationCenter defaultCenter];

      conn = [NSConnection defaultConnection];
      [conn setRootObject: self];
      [conn setDelegate: self];

      if ([conn registerName: @"fswatcher"] == NO)
        {
          DESTROY (self);
          return self;
        }

      watchersLock = [NSLock new];

      clientsInfo = [NSMutableArray new];
      watchers = NSCreateMapTable(NSObjectMapKeyCallBacks,
                                  NSObjectMapValueCallBacks, 0);

      watchDescrMap = NSCreateMapTable(NSIntMapKeyCallBacks,
                                       NSNonOwnedPointerMapValueCallBacks, 0);

      includePathsTree = newTreeWithIdentifier(@"incl_paths");
      excludePathsTree = newTreeWithIdentifier(@"excl_paths");
      excludedSuffixes = [[NSMutableSet alloc] initWithCapacity: 1];

      [self setDefaultGlobalPaths];

      [nc addObserver: self
             selector: @selector(connectionBecameInvalid:)
                 name: NSConnectionDidDieNotification
               object: conn];

      [dnc addObserver: self
              selector: @selector(globalPathsChanged:)
                  name: @"GSMetadataIndexedDirectoriesChanged"
                object: nil];

      /* The kqueue monitor runs on its own thread for the life of the process. */
      [NSThread detachNewThreadSelector: @selector (kqueueLoop)
                               toTarget: self
                             withObject: nil];
    }

  return self;
}

- (BOOL)connection:(NSConnection *)ancestor
             shouldMakeNewConnection:(NSConnection *)newConn;
{
  FSWClientInfo *info = [FSWClientInfo new];

  [info setConnection: newConn];
  [clientsInfo addObject: info];
  RELEASE (info);

  [nc addObserver: self
         selector: @selector(connectionBecameInvalid:)
             name: NSConnectionDidDieNotification
           object: newConn];

  [newConn setDelegate: self];

  return YES;
}

- (void)connectionBecameInvalid:(NSNotification *)notification
{
  id connection = [notification object];

  [nc removeObserver: self
                name: NSConnectionDidDieNotification
              object: connection];

  if (connection == conn)
    {
      exit(EXIT_FAILURE);
    }
  else
    {
      FSWClientInfo *info = [self clientInfoWithConnection: connection];

      if (info)
        {
          NSSet *wpaths = [info watchedPaths];
          NSEnumerator *enumerator = [wpaths objectEnumerator];
          NSString *wpath;

          while ((wpath = [enumerator nextObject]))
            {
              Watcher *watcher = [self watcherForPath: wpath];

              if (watcher)
                [watcher removeListener];
            }

          [clientsInfo removeObject: info];
        }

      if (auto_stop == YES && [clientsInfo count] <= 1)
        {
          /* If there is nothing else using this process, and this is not
           * a daemon, then we can quietly terminate.
           */
          exit(EXIT_SUCCESS);
        }
    }
}

- (void)setDefaultGlobalPaths
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id entry;
  NSUInteger i;

  [defaults synchronize];

  entry = [defaults arrayForKey: @"GSMetadataIndexablePaths"];

  if (entry) {
    for (i = 0; i < [entry count]; i++) {
      insertComponentsOfPath([entry objectAtIndex: i], includePathsTree);
    }

  } else {
    insertComponentsOfPath(NSHomeDirectory(), includePathsTree);

    entry = NSSearchPathForDirectoriesInDomains(NSAllApplicationsDirectory,
                                                NSAllDomainsMask, YES);
    for (i = 0; i < [entry count]; i++) {
      insertComponentsOfPath([entry objectAtIndex: i], includePathsTree);
    }

    entry = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                NSAllDomainsMask, YES);
    for (i = 0; i < [entry count]; i++) {
      NSString *dir = [entry objectAtIndex: i];
      NSString *path = [dir stringByAppendingPathComponent: @"Headers"];

      if ([fm fileExistsAtPath: path]) {
        insertComponentsOfPath(path, includePathsTree);
      }

      path = [dir stringByAppendingPathComponent: @"Documentation"];

      if ([fm fileExistsAtPath: path]) {
        insertComponentsOfPath(path, includePathsTree);
      }
    }
  }

  entry = [defaults arrayForKey: @"GSMetadataExcludedPaths"];

  if (entry) {
    for (i = 0; i < [entry count]; i++) {
      insertComponentsOfPath([entry objectAtIndex: i], excludePathsTree);
    }
  }

  entry = [defaults arrayForKey: @"GSMetadataExcludedSuffixes"];

  if (entry == nil) {
    entry = [NSArray arrayWithObjects: @"a", @"d", @"dylib", @"er1",
                                   @"err", @"extinfo", @"frag", @"la",
                                   @"log", @"o", @"out", @"part",
                                   @"sed", @"so", @"status", @"temp",
                                   @"tmp",
                                   nil];
  }

  [excludedSuffixes addObjectsFromArray: entry];
}

- (void)globalPathsChanged:(NSNotification *)notification
{
  NSDictionary *info = [notification userInfo];
  NSArray *indexable = [info objectForKey: @"GSMetadataIndexablePaths"];
  NSArray *excluded = [info objectForKey: @"GSMetadataExcludedPaths"];
  NSArray *suffixes = [info objectForKey: @"GSMetadataExcludedSuffixes"];

  NSUInteger i;

  emptyTreeWithBase(includePathsTree);

  for (i = 0; i < [indexable count]; i++) {
    insertComponentsOfPath([indexable objectAtIndex: i], includePathsTree);
  }

  emptyTreeWithBase(excludePathsTree);

  for (i = 0; i < [excluded count]; i++) {
    insertComponentsOfPath([excluded objectAtIndex: i], excludePathsTree);
  }

  [excludedSuffixes removeAllObjects];
  [excludedSuffixes addObjectsFromArray: suffixes];
}

- (oneway void)registerClient:(id <FSWClientProtocol>)client
               isGlobalWatcher:(BOOL)global
{
  NSConnection *connection = [(NSDistantObject *)client connectionForProxy];
  FSWClientInfo *info = [self clientInfoWithConnection: connection];

  if (info == nil)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"registration with unknown connection"];
    }

  if ([info client] != nil)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"registration with registered client"];
    }

  if ([(id)client isProxy] == YES) {
    [(id)client setProtocolForProxy: @protocol(FSWClientProtocol)];
    [info setClient: client];
    [info setGlobal: global];
  }
}

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client
{
  NSConnection *connection = [(NSDistantObject *)client connectionForProxy];
  FSWClientInfo *info = [self clientInfoWithConnection: connection];
  NSSet *wpaths;
  NSEnumerator *enumerator;
  NSString *wpath;

  if (info == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"unregistration with unknown connection"];
  }

  if ([info client] == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"unregistration with unregistered client"];
  }

  wpaths = [info watchedPaths];
  enumerator = [wpaths objectEnumerator];

  while ((wpath = [enumerator nextObject])) {
    Watcher *watcher = [self watcherForPath: wpath];

    if (watcher) {
      [watcher removeListener];
    }
  }

  [nc removeObserver: self
                name: NSConnectionDidDieNotification
              object: connection];

  [clientsInfo removeObject: info];

  if (auto_stop == YES && [clientsInfo count] <= 1)
    {
      /* If there is nothing else using this process, and this is not
       * a daemon, then we can quietly terminate.
       */
      exit(EXIT_SUCCESS);
    }
}

- (FSWClientInfo *)clientInfoWithConnection:(NSConnection *)connection
{
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *info = [clientsInfo objectAtIndex: i];

    if ([info connection] == connection) {
      return info;
    }
  }

  return nil;
}

- (FSWClientInfo *)clientInfoWithRemote:(id)remote
{
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++)
    {
      FSWClientInfo *info = [clientsInfo objectAtIndex: i];

      if ([info client] == remote)
        return info;
    }

  return nil;
}

- (oneway void)client:(id <FSWClientProtocol>)client
                               addWatcherForPath:(NSString *)path
{
  NSConnection *connection = [(NSDistantObject *)client connectionForProxy];
  FSWClientInfo *info = [self clientInfoWithConnection: connection];
  Watcher *watcher = [self watcherForPath: path];

  if (info == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"adding watcher from unknown connection"];
  }

  if ([info client] == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"adding watcher for unregistered client"];
  }

  if (watcher) {
    [info addWatchedPath: path];
    [watcher addListener];
  } else {
    BOOL isdir;

    if ([fm fileExistsAtPath: path isDirectory: &isdir]) {
      /* O_EVTONLY (Darwin) opens for event monitoring without blocking
       * unmount; it is not present on all *BSD kqueue systems, so fall
       * back to a plain O_RDONLY open there. */
      int openflags = O_RDONLY;
#ifdef O_EVTONLY
      openflags |= O_EVTONLY;
#endif
      int fd = open([path UTF8String], openflags);

      if (fd != -1) {
        struct kevent change;
        EV_SET(&change, fd, EVFILT_VNODE,
               EV_ADD | EV_CLEAR,
               NOTE_DELETE | NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB
                 | NOTE_LINK | NOTE_RENAME | NOTE_REVOKE,
               0, 0);

        if (kevent(kq, &change, 1, NULL, 0, NULL) != -1) {
          [info addWatchedPath: path];
          watcher = [[Watcher alloc] initWithWatchedPath: path
                                         watchDescriptor: fd
                                               fswatcher: self];
          [watchersLock lock];
          NSMapInsert (watchers, path, watcher);
          NSMapInsert (watchDescrMap, (void *)(intptr_t)fd, (void *)watcher);
          [watchersLock unlock];
          RELEASE (watcher);
        } else {
          close(fd);
        }
      }
    }
  }
}

- (oneway void)client:(id <FSWClientProtocol>)client
                             removeWatcherForPath:(NSString *)path
{
  NSConnection *connection = [(NSDistantObject *)client connectionForProxy];
  FSWClientInfo *info = [self clientInfoWithConnection: connection];
  Watcher *watcher = [self watcherForPath: path];

  if (info == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"removing watcher from unknown connection"];
  }

  if ([info client] == nil) {
    [NSException raise: NSInternalInconsistencyException
                format: @"removing watcher for unregistered client"];
  }

  if (watcher) {
    [info removeWatchedPath: path];
    [watcher removeListener];
  }
}

- (Watcher *)watcherForPath:(NSString *)path
{
  Watcher *w;
  [watchersLock lock];
  w = (Watcher *)NSMapGet(watchers, path);
  [watchersLock unlock];
  return w;
}

- (Watcher *)watcherWithWatchDescriptor:(int)fd
{
  Watcher *w;
  [watchersLock lock];
  w = (Watcher *)NSMapGet(watchDescrMap, (void *)(intptr_t)fd);
  [watchersLock unlock];
  return w;
}

- (void)removeWatcher:(Watcher *)watcher
{
  NSString *path = [watcher watchedPath];
  int fd = [watcher watchDescriptor];

  if (fd != -1) {
    struct kevent change;
    EV_SET(&change, fd, EVFILT_VNODE, EV_DELETE, 0, 0, 0);
    kevent(kq, &change, 1, NULL, 0, NULL);
    close(fd);
  }

  RETAIN (path);
  [watchersLock lock];
  NSMapRemove(watchDescrMap, (void *)(intptr_t)fd);
  NSMapRemove(watchers, path);
  [watchersLock unlock];
  RELEASE (path);
}

- (void)notifyClients:(NSDictionary *)info
{
  CREATE_AUTORELEASE_POOL(pool);
  NSString *path = [info objectForKey: @"path"];
  NSData *data = [NSArchiver archivedDataWithRootObject: info];
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *clinfo = [clientsInfo objectAtIndex: i];

    if ([clinfo isWathchingPath: path]) {
      [[clinfo client] watchedPathDidChange: data];
    }
  }

  RELEASE (pool);
}

- (void)notifyGlobalWatchingClients:(NSDictionary *)info
{
  NSUInteger i;

  for (i = 0; i < [clientsInfo count]; i++) {
    FSWClientInfo *clinfo = [clientsInfo objectAtIndex: i];

    if ([clinfo isGlobal]) {
      [[clinfo client] globalWatchedPathDidChange: info];
    }
  }
}

/* Runs on the main thread (marshalled from the kqueue monitor thread) so the
 * client DO proxies are used on the thread that created them. */
- (void)deliverNotification:(NSDictionary *)info
{
  NSString *path = [info objectForKey: @"path"];

  [self notifyClients: info];

  if (([excludedSuffixes containsObject:
         [[path pathExtension] lowercaseString]] == NO)
      && (isDotFile(path) == NO)
      && inTreeFirstPartOfPath(path, includePathsTree)
      && (inTreeFirstPartOfPath(path, excludePathsTree) == NO)) {
    [self notifyGlobalWatchingClients: info];
  }
}

- (void)kqueueLoop
{
  CREATE_AUTORELEASE_POOL(pool);

  while (1) {
    struct kevent ev;
    int n;

    /* A single-event blocking wait; the loop lives for the process lifetime.
     * Registrations (add/remove) happen concurrently from the main thread via
     * kevent() on the same kq, which is safe. */
    n = kevent(kq, NULL, 0, &ev, 1, NULL);

    if (n < 0) {
      if (errno == EINTR) {
        continue;
      }
      break;
    }
    if (n == 0) {
      continue;
    }

    [self handleKevent: &ev];
  }

  RELEASE (pool);
}

- (void)handleKevent:(struct kevent *)ev
{
  int fd = (int)ev->ident;
  uint32_t fflags = ev->fflags;
  Watcher *watcher = [self watcherWithWatchDescriptor: fd];

  if (watcher == nil) {
    return;
  }

  NSString *path = [watcher watchedPath];
  NSMutableDictionary *notifdict = [NSMutableDictionary dictionary];
  [notifdict setObject: path forKey: @"path"];

  BOOL deleted = (fflags & (NOTE_DELETE | NOTE_RENAME | NOTE_REVOKE)) ? YES : NO;
  BOOL changed = (fflags & (NOTE_WRITE | NOTE_EXTEND | NOTE_ATTRIB
                              | NOTE_LINK)) ? YES : NO;

  if (deleted) {
    [notifdict setObject: GWWatchedPathDeleted forKey: @"event"];
    [self performSelectorOnMainThread: @selector (deliverNotification:)
                           withObject: notifdict
                        waitUntilDone: NO];
    /* The watched path itself is gone: drop our watch for it. */
    [self removeWatcher: watcher];
    return;
  }

  if (changed) {
    [notifdict setObject: GWWatchedFileModified forKey: @"event"];
    [self performSelectorOnMainThread: @selector (deliverNotification:)
                           withObject: notifdict
                        waitUntilDone: NO];
  }
}

static inline BOOL isDotFile(NSString *path)
{
  int len = ([path length] - 1);
  static unichar sep = 0;
  unichar c;
  int i;

  if (sep == 0) {
#if defined(__MINGW32__)
    sep = '\\';
#else
    sep = '/';
#endif
  }

  for (i = len; i >= 0; i--) {
    c = [path characterAtIndex: i];

    if (c == '.') {
      if ((i > 0) && ([path characterAtIndex: (i - 1)] == sep)) {
        return YES;
      }
    }
  }

  return NO;
}

@end


@implementation Watcher

- (void)dealloc
{
  RELEASE (watchedPath);
  [super dealloc];
}

- (id)initWithWatchedPath:(NSString *)path
           watchDescriptor:(int)wdesc
                 fswatcher:(id)fsw
{
  self = [super init];

  if (self) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm fileAttributesAtPath: path traverseLink: YES];

    ASSIGN (watchedPath, path);
    watchDescriptor = wdesc;
    isdir = ([attributes fileType] == NSFileTypeDirectory);
    listeners = 1;
    fswatcher = fsw;
  }

  return self;
}

- (void)addListener
{
  listeners++;
}

- (void)removeListener
{
  listeners--;
  if (listeners <= 0) {
    [fswatcher removeWatcher: self];
  }
}

- (BOOL)isWathcingPath:(NSString *)apath
{
  return ([watchedPath isEqual: apath]);
}

- (NSString *)watchedPath
{
  return watchedPath;
}

- (int)watchDescriptor
{
  return watchDescriptor;
}

- (BOOL)isDirWatcher
{
  return isdir;
}

@end


int main(int argc, char** argv)
{
  CREATE_AUTORELEASE_POOL(pool);
  NSProcessInfo *info = [NSProcessInfo processInfo];
  NSMutableArray *args = AUTORELEASE ([[info arguments] mutableCopy]);
  BOOL subtask = YES;

  if ([[info arguments] containsObject: @"--auto"] == YES)
    {
      auto_stop = YES;
    }

  if ([[info arguments] containsObject: @"--daemon"])
    {
      subtask = NO;
    }

  if (subtask) {
    NSTask *task = [NSTask new];

    NS_DURING
      {
        [args removeObjectAtIndex: 0];
        [args addObject: @"--daemon"];
        [task setLaunchPath: [[NSBundle mainBundle] executablePath]];
        [task setArguments: args];
        [task setEnvironment: [info environment]];
        [task launch];
        DESTROY (task);
      }
    NS_HANDLER
      {
        fprintf (stderr, "unable to launch the fswatcher task. exiting.\n");
        DESTROY (task);
      }
    NS_ENDHANDLER

    exit(EXIT_FAILURE);
  }

  RELEASE(pool);

  {
    CREATE_AUTORELEASE_POOL (pool);
    FSWatcher *fsw = [[FSWatcher alloc] init];
    RELEASE (pool);

    if (fsw != nil) {
      CREATE_AUTORELEASE_POOL (pool);
      [[NSRunLoop currentRunLoop] run];
      RELEASE (pool);
    }
  }

  exit(EXIT_SUCCESS);
}
