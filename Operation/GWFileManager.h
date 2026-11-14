/* GWFileManager.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_FILE_MANAGER_H
#define GW_FILE_MANAGER_H

#import <Foundation/Foundation.h>

@class GWDestination;
@class GWDeferredMove;

@protocol GWFileCopyObserver
/* Asked between chunks of a file. */
- (BOOL)fileCopyShouldStop;
/* More bytes of the current file may be shown as copied. */
- (void)fileCopyDidAdvanceBy:(unsigned long long)bytes;
@end

/* NSFileManager walks the folders, recreates links and folders and sets
 * permissions and dates as before; only the data of each regular file is
 * copied here instead of through its 8 KiB read/write loop, so that it
 * goes through the kernel's own file copy where possible and, for a
 * removable or network destination, really reaches the device before the
 * file counts as copied. */
@interface GWFileManager : NSFileManager
{
  GWDestination *_destination;
  id <GWFileCopyObserver> _observer;
  GWDeferredMove *_journal;
  int _lastMethod;
}

@property (nonatomic, retain) GWDestination *destination;
@property (nonatomic, assign) id <GWFileCopyObserver> observer;
/* Gets the state of every source file as its copy starts, when set. */
@property (nonatomic, retain) GWDeferredMove *journal;
/* The GWCopyMethod the last file ended with, for tests. */
@property (nonatomic, readonly) int lastMethod;

@end

#endif
