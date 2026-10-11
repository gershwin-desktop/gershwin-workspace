/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The global "show all filename extensions" choice (the Workspace
 * preference GSFilenameExtensionDisplayMode = 0) beats a file's own
 * hide-extension bit.  The mode is cached for the life of the process, so
 * this runs as a tool of its own. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"

@interface HidingProvider : NSObject <FSNMetadataProvider>
@end

@implementation HidingProvider
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSMakePoint(-1, -1); }
- (void)invalidateCaches {}
- (BOOL)isExtensionHiddenForPath:(NSString *)path { return YES; }
@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_FSNHiddenExtensionShowAll_%d", (int)getpid ()]];
  NSString *txt = [dir stringByAppendingPathComponent: @"report.txt"];
  HidingProvider *provider = [HidingProvider new];

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [@"x" writeToFile: txt atomically: YES];

  [[NSUserDefaults standardUserDefaults] setInteger: 0 forKey: @"GSFilenameExtensionDisplayMode"];
  [[FSNodeRep sharedInstance] setMetadataProvider: provider];

  PASS_EQUAL ([[FSNode nodeWithPath: txt] displayName], @"report.txt",
              "MI-FSN-22 show-all mode: the bit does not hide the extension");

  [[FSNodeRep sharedInstance] setMetadataProvider: nil];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
