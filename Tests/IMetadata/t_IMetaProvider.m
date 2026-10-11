/* t_IMetaProvider.m - GWMetadataProvider answers the per-path queries FSNode
 * makes (label index and name, comment, hidden extension, locked name).
 * Headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSFileMetadata.h"
#import "GWMetadataProvider.h"
#include <unistd.h>

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"imetaprov-%d", (int)getpid()]];
  NSString *f = [dir stringByAppendingPathComponent: @"x.txt"];
  NSString *plain = [dir stringByAppendingPathComponent: @"plain.txt"];
  GWMetadataProvider *p = [GWMetadataProvider sharedProvider];

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createFileAtPath: f contents: [NSData data] attributes: nil];
  [fm createFileAtPath: plain contents: [NSData data] attributes: nil];

  PASS([p respondsToSelector: @selector(labelIndexForPath:)]
       && [p respondsToSelector: @selector(commentForPath:)]
       && [p respondsToSelector: @selector(labelNameForPath:)]
       && [p respondsToSelector: @selector(isExtensionHiddenForPath:)]
       && [p respondsToSelector: @selector(isNameLockedForPath:)],
       "MI-META-7 provider implements the optional selectors");

  GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
  [md setLabelNumber: GSFileLabelGreen];
  [md setFinderComment: @"a comment"];
  [md setExtensionHidden: YES];
  [md setNameLocked: YES];
  [md writeToFileAtPath: f error: NULL];
  [p invalidateCaches];

  PASS([p labelIndexForPath: f] == GSFileLabelGreen,
       "MI-META-7 label index");
  PASS_EQUAL([p labelNameForPath: f],
             [GSFileMetadata tagNameForLabel: GSFileLabelGreen],
             "MI-META-7 label name is the Finder tag name");
  PASS_EQUAL([p commentForPath: f], @"a comment", "MI-META-7 comment");
  PASS([p isExtensionHiddenForPath: f], "MI-META-7 hidden extension");
  PASS([p isNameLockedForPath: f], "MI-META-7 locked name");

  PASS([p labelIndexForPath: plain] == 0, "no label on a plain file");
  PASS([p labelNameForPath: plain] == nil, "no label name on a plain file");
  PASS([p commentForPath: plain] == nil, "no comment on a plain file");
  PASS(![p isExtensionHiddenForPath: plain], "extension shown on a plain file");
  PASS(![p isNameLockedForPath: plain], "name unlocked on a plain file");

  /* Same cache as the existing queries: a second ask must not re-read. */
  [md setFinderComment: @"changed"];
  [md writeToFileAtPath: f error: NULL];
  PASS_EQUAL([p commentForPath: f], @"a comment",
             "MI-META-8 answers come from the provider cache until invalidated");
  [p invalidateCaches];
  PASS_EQUAL([p commentForPath: f], @"changed",
             "MI-META-8 invalidateCaches refreshes them");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
