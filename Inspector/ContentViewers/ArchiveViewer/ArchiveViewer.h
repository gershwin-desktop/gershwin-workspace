/*
 * ArchiveViewer.h
 *
 * Contents Inspector viewer that lists the files inside an archive file
 * using libarchive (supports all archive formats libarchive does: tar,
 * zip, gzip, bzip2, xz, lzma, 7zip, ar, cpio, etc.).
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Inspector application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import "ContentViewersProtocol.h"

@protocol ArchiveContentInspectorProtocol
- (void)contentsReadyAt:(NSString *)path;
@end

@interface ArchiveViewer : NSView <ContentViewersProtocol, NSTableViewDataSource>
{
  NSScrollView *scrollView;
  NSTableView *tableView;
  NSMutableArray *entries;
  NSString *currentPath;
  id <ArchiveContentInspectorProtocol> inspector;
  NSFileManager *fm;
}

- (void)displayPath:(NSString *)path;
- (void)displayData:(NSData *)data ofType:(NSString *)type;
- (NSString *)path;
- (void)stopTasks;
- (BOOL)canDisplayPath:(NSString *)path;
- (BOOL)canDisplayDataOfType:(NSString *)type;
- (NSString *)winname;
- (NSString *)description;

@end
