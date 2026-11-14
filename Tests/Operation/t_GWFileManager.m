/* t_GWFileManager.m - NSFileManager's folder copy still sends every
 * regular file through GWFileManager's data copy, and that copy keeps the
 * data, the dates and the permissions as before.  Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The unit below needs the GNU declarations, which must come before the
 * first system header. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Operation/GWFileManager.m"

@interface Observer : NSObject <GWFileCopyObserver>
{
@public
  unsigned long long bytes;
  int stopAfter;
  int asked;
}
@end

@implementation Observer
- (BOOL)fileCopyShouldStop
{
  asked++;
  return stopAfter > 0 && asked > stopAfter;
}
- (void)fileCopyDidAdvanceBy:(unsigned long long)n
{
  bytes += n;
}
@end

static NSString *base;

static NSString *
put(NSString *rel, NSUInteger size)
{
  NSString *p = [base stringByAppendingPathComponent: rel];
  NSMutableData *d = [NSMutableData dataWithLength: size];
  NSUInteger i;

  for (i = 0; i < size; i++)
    {
      ((unsigned char *)[d mutableBytes])[i] = (unsigned char)(i * 13);
    }
  [[NSFileManager defaultManager]
    createDirectoryAtPath: [p stringByDeletingLastPathComponent]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [d writeToFile: p atomically: NO];
  return p;
}

static NSString *
at(NSString *rel)
{
  return [base stringByAppendingPathComponent: rel];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *plain = [NSFileManager defaultManager];

  base = [NSTemporaryDirectory() stringByAppendingPathComponent:
           [NSString stringWithFormat: @"t_GWFileManager-%d", getpid()]];
  [plain removeFileAtPath: base handler: nil];
  put(@"src/T/a", 5000);
  put(@"src/T/sub/b", 3 * 1024 * 1024 + 1);
  put(@"src/T/empty", 0);
  /* Dangling: NSFileManager applies a link's attributes through it, which
   * would make its target 0777 whoever copies the data. */
  symlink("nowhere", [at(@"src/T/link") fileSystemRepresentation]);
  chmod([at(@"src/T/a") fileSystemRepresentation], 0640);
  [plain changeFileAttributes:
           @{ NSFileModificationDate: [NSDate dateWithTimeIntervalSince1970: 1e9] }
                       atPath: at(@"src/T/sub/b")];

  START_SET("folder copy through GWFileManager")
    GWFileManager *fm = AUTORELEASE([GWFileManager new]);
    Observer *obs = AUTORELEASE([Observer new]);
    GWDeferredMove *journal = AUTORELEASE([GWDeferredMove new]);
    NSDictionary *attrs;
    BOOL ok;

    [plain createDirectoryAtPath: at(@"dst") attributes: nil];
    [fm setObserver: obs];
    [fm setJournal: journal];
    ok = [fm copyPath: at(@"src/T") toPath: at(@"dst/T") handler: nil];
    PASS(ok, "the folder is copied");
    PASS([fm lastMethod] != GWCopyMethodFailed,
         "the data went through GWFileManager's copy");
    PASS([[NSData dataWithContentsOfFile: at(@"dst/T/sub/b")]
           isEqual: [NSData dataWithContentsOfFile: at(@"src/T/sub/b")]]
         && [[NSData dataWithContentsOfFile: at(@"dst/T/a")]
              isEqual: [NSData dataWithContentsOfFile: at(@"src/T/a")]],
         "the data is the same");
    PASS([[plain pathContentOfSymbolicLinkAtPath: at(@"dst/T/link")]
           isEqual: @"nowhere"], "links are recreated as before");
    attrs = [plain fileAttributesAtPath: at(@"dst/T/a") traverseLink: NO];
    PASS([attrs filePosixPermissions] == 0640, "permissions are kept");
    attrs = [plain fileAttributesAtPath: at(@"dst/T/sub/b") traverseLink: NO];
    PASS([[attrs fileModificationDate] timeIntervalSince1970] == 1e9,
         "modification dates are kept");
    PASS(obs->bytes == 5000 + 3 * 1024 * 1024 + 1,
         "the observer hears of every byte, once");
    {
      struct stat st;
      NSMutableArray *m = [NSMutableArray array];
      NSMutableArray *c = [NSMutableArray array];

      /* Every copied file is in the journal: deleting the sources would
       * keep a file that was not. */
      [journal addItemFrom: at(@"src/T") to: at(@"dst/T") name: @"T"];
      PASS([journal deleteSourcesReporting: NULL moved: m changed: c error: NULL]
           && [m count] == 1 && lstat([at(@"src/T") fileSystemRepresentation],
                                      &st) != 0,
           "the journal holds every file copied");
    }
  END_SET("folder copy through GWFileManager")

  START_SET("stopping")
    GWFileManager *fm = AUTORELEASE([GWFileManager new]);
    Observer *obs = AUTORELEASE([Observer new]);

    put(@"src2/big", 40 * 1024 * 1024);
    obs->stopAfter = 1;
    [fm setObserver: obs];
    PASS(![fm copyPath: at(@"src2/big") toPath: at(@"dst2-big") handler: nil],
         "a stopped copy fails");
    PASS(![plain fileExistsAtPath: at(@"dst2-big")],
         "and leaves no half file behind");
  END_SET("stopping")

  START_SET("removable destination")
    GWFileManager *fm = AUTORELEASE([GWFileManager new]);

    [fm setDestination: [GWDestination destinationWithKind: GWDestinationRemovable
                                            filesystemType: @"vfat"
                                                mountPoint: base]];
    put(@"src3/large", 17 * 1024 * 1024);
    PASS([fm copyPath: at(@"src3/large") toPath: at(@"dst3-large") handler: nil]
         && [[NSData dataWithContentsOfFile: at(@"dst3-large")]
              isEqual: [NSData dataWithContentsOfFile: at(@"src3/large")]],
         "a file larger than any window is copied in windows and flushed");
  END_SET("removable destination")

  [plain removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
