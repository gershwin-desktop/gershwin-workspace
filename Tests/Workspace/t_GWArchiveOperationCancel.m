/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWArchiveOperationCancel.m - cancelOperation: only set the `cancelled`
 * flag; runCompress/runExtract never checked it, so Cancel visibly did
 * nothing until the whole archive finished. Headless: drives runCompress
 * directly (never calling -run, so no progress window/display is built),
 * setting `cancelled` through KVC (the ivars have no accessors and default
 * access-instance-variables-directly makes this the same write
 * cancelOperation: performs) to prove the checkpoint returns immediately
 * without ever reaching GWMetaArchive. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWArchiveOperation.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWArchiveOperationCancel_%d", (int)getpid()]];
  NSString *srcDir = [tmpDir stringByAppendingPathComponent: @"src"];
  NSString *zipPath = [tmpDir stringByAppendingPathComponent: @"out.zip"];

  [fm removeFileAtPath: tmpDir handler: nil];
  [fm createDirectoryAtPath: tmpDir attributes: nil];
  [fm createDirectoryAtPath: srcDir attributes: nil];
  [@"hello" writeToFile: [srcDir stringByAppendingPathComponent: @"a.txt"]
             atomically: YES];

  {
    GWArchiveOperation *op = [[GWArchiveOperation alloc] init];
    BOOL ok;

    [op setValue: @"compress" forKey: @"operationType"];
    [op setValue: [NSArray arrayWithObject: srcDir] forKey: @"paths"];
    [op setValue: zipPath forKey: @"outputPath"];
    /* Same write cancelOperation: makes when the user clicks Cancel. */
    [op setValue: [NSNumber numberWithBool: YES] forKey: @"cancelled"];

    ok = [op runCompress];

    PASS(ok == NO, "runCompress returns NO immediately once cancelled, before touching GWMetaArchive");
    PASS(![fm fileExistsAtPath: zipPath], "no archive is written once cancelled before the archive call starts");

    RELEASE(op);
  }

  [fm removeFileAtPath: tmpDir handler: nil];
  [arp release];
  return 0;
}
