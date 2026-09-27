/* t_FileOpInfoRemoveProcessedFiles.m - ObjectTesting coverage for
 * -[FileOpInfo removeProcessedFiles].
 *
 * Reproduces the "pause a multi-file operation" crash: the inner scan that
 * matches an already-processed name against the pending `files' array must
 * advance ITS OWN index on a mismatch, not the outer per-processed-name
 * index.  Getting this wrong leaves the scan stuck at the first pending
 * file forever while the outer index keeps climbing, which eventually reads
 * past the end of the processed-names array and raises NSRangeException.
 *
 * FileOpInfo.m is linked as a separate object (it pulls in most of AppKit
 * plus the FSNode framework for FSNAlias); constructed with usewindow:NO so
 * no nib is loaded and the test stays headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FileOpInfo.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *tmp = NSTemporaryDirectory();
  NSArray *pendingFiles = @[ @{ @"name": @"a" },
                             @{ @"name": @"b" },
                             @{ @"name": @"c" } ];

  FileOpInfo *info = [FileOpInfo operationOfType: NSWorkspaceMoveOperation
                                              ref: 1
                                           source: tmp
                                      destination: tmp
                                            files: pendingFiles
                                     confirmation: NO
                                        usewindow: NO
                                          winrect: NSZeroRect
                                       controller: nil];
  PASS(info != nil, "FileOpInfo constructs headless with usewindow:NO");

  /* "b" and "c" were already moved before the user hit Pause; "a" is still
   * pending.  This is exactly the shape -removeProcessedFiles is fed from
   * the executor's -processedFiles reply. */
  NSArray *alreadyProcessed = @[ @"b", @"c" ];
  NSData *archived = [NSArchiver archivedDataWithRootObject: alreadyProcessed];
  [info cacheProcessedFiles: archived];

  BOOL raised = NO;
  @try
    {
      [info removeProcessedFiles];
    }
  @catch (NSException *e)
    {
      raised = YES;
      NSLog (@"removeProcessedFiles raised %@: %@", [e name], [e reason]);
    }
  PASS(raised == NO,
       "removeProcessedFiles does not raise when resuming a paused operation");

  NSArray *remaining = [info files];
  PASS([remaining count] == 1,
       "removeProcessedFiles leaves only the file not yet processed");
  if ([remaining count] == 1)
    {
      PASS_EQUAL([[remaining objectAtIndex: 0] objectForKey: @"name"], @"a",
                 "the survivor is the pending file, not one of the processed ones");
    }

  [arp release];
  return 0;
}
