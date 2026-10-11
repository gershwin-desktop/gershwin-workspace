/* t_DSStoreComment.m - ObjectTesting coverage for the shared writer of an
 * item's cmmt record in its parent folder's .DS_Store.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DSStore.h"

#include <unistd.h>

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_dsscmt_%d", (int)getpid()]];
  NSString *item = [d stringByAppendingPathComponent: @"doc.txt"];
  NSString *store = [d stringByAppendingPathComponent: @".DS_Store"];
  NSError *err = nil;
  DSStore *s;

  [fm removeFileAtPath: d handler: nil];
  [fm createDirectoryAtPath: d attributes: nil];

  PASS([DSStore setComment: @"" forItemAtPath: item error: &err]
       && ![fm fileExistsAtPath: store],
       "MI-PRS-30 clearing a comment where no store exists creates none");
  PASS([DSStore setComment: @"first" forItemAtPath: item error: &err],
       "MI-PRS-30 a comment is written without an existing store");
  s = [DSStore storeWithPath: store]; [s load];
  PASS_EQUAL([s commentsForFilename: @"doc.txt"], @"first",
             "MI-PRS-30 the store holds the cmmt record");
  [s setIconLocationForFilename: @"doc.txt" x: 40 y: 50];
  [s setCommentsForFilename: @"other.txt" comments: @"theirs"];
  [s save];
  PASS([DSStore setComment: @"second" forItemAtPath: item error: &err],
       "MI-PRS-30 a comment is replaced");
  s = [DSStore storeWithPath: store]; [s load];
  PASS_EQUAL([s commentsForFilename: @"doc.txt"], @"second", "MI-PRS-30 replaced");
  PASS_EQUAL([s commentsForFilename: @"other.txt"], @"theirs",
             "MI-PRS-30 another item's record stays");
  PASS([s iconLocationForFilename: @"doc.txt"].x == 40,
       "MI-PRS-30 positions stay");
  PASS([DSStore setComment: @"" forItemAtPath: item error: &err],
       "MI-PRS-30 an empty comment removes the record");
  s = [DSStore storeWithPath: store]; [s load];
  PASS([s commentsForFilename: @"doc.txt"] == nil
       && [s commentsForFilename: @"other.txt"] != nil, "MI-PRS-30 only that record");
  [@"junk" writeToFile: store atomically: NO];
  err = nil;
  PASS(![DSStore setComment: @"x" forItemAtPath: item error: &err] && err != nil,
       "MI-PRS-30 an unreadable store is an error");
  PASS([DSStore setComment: @"x" forItemAtPath: @"/" error: &err],
       "MI-PRS-30 the root has no parent folder and needs no record");

  [fm removeFileAtPath: d handler: nil];
  [arp release];
  return 0;
}
