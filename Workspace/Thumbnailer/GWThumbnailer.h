/* GWThumbnailer.h
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

#define TMBMAX (64.0)
#define RESZLIM 4

@protocol TMBProtocol

- (BOOL)canProvideThumbnailForPath:(NSString *)path;

- (NSData *)makeThumbnailForPath:(NSString *)path;

- (NSString *)fileNameExtension;

- (NSString *)description;

@end


@class GWThumbnailStore;

/* Makes thumbnails with the Thumbnailer bundles and keeps them, like every
 * other image Workspace caches, in the one GWThumbnailStore; also the one
 * that keeps that store clean. */
@interface Thumbnailer: NSObject
{
  NSMutableArray *thumbnailers;
  NSMutableDictionary *extProviders;
  id current;
  GWThumbnailStore *store;
  NSTimer *timer;
  NSConnection *conn;
  NSFileManager *fm;
  NSLock *dictLock;
  NSMutableArray *pathsInProcessing;
}

+ (Thumbnailer *)sharedThumbnailer;

- (void)loadThumbnailers;

- (BOOL)addThumbnailer:(id)tmb;

- (id)thumbnailerForPath:(NSString *)path;

/* The cleanup: drops entries whose source is gone or changed and files no
 * entry references, and posts GWThumbnailsDidChangeNotification for what
 * went. Does file I/O; run it off the main thread. */
- (void)checkThumbnails:(id)sender;

/* Runs checkThumbnails: by itself, on a low-priority thread, shortly after
 * start and then daily, and for the files Workspace's own move, rename and
 * delete operations take away; right away, moves the entries an earlier
 * Workspace build kept in ~/.cache/thumbnails into the store. Call once,
 * on the main thread. */
- (void)startAutomaticChecks;

/* The paths a GWFileSystemDidChangeNotification's operation info names as
 * its sources: the files of a move, copy, delete or recycle in its source
 * folder, the old path of a rename. */
+ (NSArray *)sourcePathsOfFileOperation:(id)info;

- (BOOL)registerThumbnailData:(NSData *)data 
                      forPath:(NSString *)path
                nameExtension:(NSString *)ext;

- (BOOL)removeThumbnailForPath:(NSString *)path;

- (void)makeThumbnails:(NSString*)path;

- (void)removeThumbnails:(NSString*)path;


- (NSArray *)bundlesWithExtension:(NSString *)extension
inDirectory:(NSString *)dirpath;

@end
