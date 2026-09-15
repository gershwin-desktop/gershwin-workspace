/* fswatcher-kqueue.h
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

#ifndef FSWATCHER_KQUEUE_H
#define FSWATCHER_KQUEUE_H

#include <sys/types.h>
#include <sys/event.h>
#import <Foundation/Foundation.h>
#include "DBKPathsTree.h"

@class Watcher;

@protocol	FSWClientProtocol <NSObject>

- (oneway void)watchedPathDidChange:(NSData *)dirinfo;

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo;

@end


@protocol	FSWatcherProtocol

- (oneway void)registerClient:(id <FSWClientProtocol>)client
               isGlobalWatcher:(BOOL)global;

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client;

- (oneway void)client:(id <FSWClientProtocol>)client
                           addWatcherForPath:(NSString *)path;

- (oneway void)client:(id <FSWClientProtocol>)client
                           removeWatcherForPath:(NSString *)path;

- (oneway void)logDataReady:(NSData *)data;

@end

@interface FSWClientInfo: NSObject
{
  NSConnection *conn;
  id <FSWClientProtocol> client;
  NSCountedSet *wpaths;
  BOOL global;
}

- (void)setConnection:(NSConnection *)connection;

- (NSConnection *)connection;

- (void)setClient:(id <FSWClientProtocol>)clnt;

- (id <FSWClientProtocol>)client;

- (void)addWatchedPath:(NSString *)path;

- (void)removeWatchedPath:(NSString *)path;

- (BOOL)isWathchingPath:(NSString *)path;

- (NSSet *)watchedPaths;

- (void)setGlobal:(BOOL)value;

- (BOOL)isGlobal;

@end


@interface FSWatcher: NSObject
{
  NSConnection *conn;
  NSMutableArray *clientsInfo;
  NSMapTable *watchers;
  NSMapTable *watchDescrMap;
  int kq;

  pcomp *includePathsTree;
  pcomp *excludePathsTree;
  NSMutableSet *excludedSuffixes;

  NSFileManager *fm;
  NSNotificationCenter *nc;
  NSNotificationCenter *dnc;

  /* Guards watchers / watchDescrMap, which are read from the kqueue monitor
   * thread (handleKevent) and written from the main thread (add/remove). */
  NSLock *watchersLock;
}

- (BOOL)connection:(NSConnection *)ancestor
             shouldMakeNewConnection:(NSConnection *)newConn;

- (void)connectionBecameInvalid:(NSNotification *)notification;

- (void)setDefaultGlobalPaths;

- (void)globalPathsChanged:(NSNotification *)notification;

- (oneway void)registerClient:(id <FSWClientProtocol>)client
               isGlobalWatcher:(BOOL)global;

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client;

- (FSWClientInfo *)clientInfoWithConnection:(NSConnection *)connection;

- (FSWClientInfo *)clientInfoWithRemote:(id)remote;

- (oneway void)client:(id <FSWClientProtocol>)client
                                 addWatcherForPath:(NSString *)path;

- (oneway void)client:(id <FSWClientProtocol>)client
                              removeWatcherForPath:(NSString *)path;

- (Watcher *)watcherForPath:(NSString *)path;

- (Watcher *)watcherWithWatchDescriptor:(int)fd;

- (void)removeWatcher:(Watcher *)awatcher;

- (void)notifyClients:(NSDictionary *)info;

- (void)notifyGlobalWatchingClients:(NSDictionary *)info;

/* Runs on the main thread (marshalled from the kqueue monitor thread) so the
 * client DO proxies are invoked on the thread that created them. */
- (void)deliverNotification:(NSDictionary *)info;

/* kqueue monitor loop, run on a dedicated background thread. */
- (void)kqueueLoop;

@end


@interface Watcher: NSObject
{
  NSString *watchedPath;
  int watchDescriptor;
  BOOL isdir;
  int listeners;
  FSWatcher *fswatcher;
}

- (id)initWithWatchedPath:(NSString *)path
           watchDescriptor:(int)wdesc
                 fswatcher:(id)fsw;

- (void)addListener;

- (void)removeListener;

- (BOOL)isWathcingPath:(NSString *)apath;

- (NSString *)watchedPath;

- (int)watchDescriptor;

- (BOOL)isDirWatcher;

@end

#endif // FSWATCHER_KQUEUE_H
