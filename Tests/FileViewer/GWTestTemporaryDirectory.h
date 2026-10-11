/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* A scratch directory of this test process's own.  Saving a folder's
 * settings also writes its record into the parent's .DS_Store, as Finder
 * keeps them there; folders made straight in the shared temporary directory
 * would leave those records in a store every other test and user shares. */

#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <unistd.h>

static NSString *gwTestRoot = nil;

static void
GWTestRemoveTemporaryDirectory(void)
{
  if (gwTestRoot != nil)
    [[NSFileManager defaultManager] removeFileAtPath: gwTestRoot handler: nil];
}

static NSString *
GWTestTemporaryDirectory(void)
{
  if (gwTestRoot == nil)
    {
      gwTestRoot = [[NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"gwtest-%d", (int)getpid()]] retain];
      [[NSFileManager defaultManager] createDirectoryAtPath: gwTestRoot
                                withIntermediateDirectories: YES
                                                 attributes: nil
                                                      error: NULL];
      atexit(GWTestRemoveTemporaryDirectory);
    }
  return gwTestRoot;
}
