/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "MDKQuery.h"
#import "GWSavedSearch.h"
#include <stdlib.h>

/* nil unless MDKit's own parser accepts the text. */
static MDKQuery *
mdk(NSString *text)
{
  MDKQuery *q = nil;

  NS_DURING
    q = [MDKQuery queryFromString: text inDirectories: nil];
  NS_HANDLER
    NSLog(@"MDKit refused \"%@\": %@", text, [localException reason]);
    q = nil;
  NS_ENDHANDLER
  return q;
}

int main(void)
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString *tmp = [NSTemporaryDirectory()
                   stringByAppendingPathComponent: @"gw-mdkparse-defaults"];
  NSDate *now = [NSDate dateWithString: @"2009-10-12 15:30:00 +0000"];
  NSArray *raws;
  NSString *raw;

  /* MDKQuery writes its attribute defaults on first use. */
  setenv("GNUSTEP_USER_DEFAULTS_DIR", [tmp fileSystemRepresentation], 1);
  [[NSFileManager defaultManager] createDirectoryAtPath: tmp
                            withIntermediateDirectories: YES
                                             attributes: nil error: NULL];

  raws = [NSArray arrayWithObjects:
    @"kMDItemFSName = \"*foo*\"cdw",
    @"kMDItemFSContentChangeDate >= $time.today(-7) && kMDItemFSName = \"a\"",
    @"kMDItemPixelWidth > 5 && kMDItemPixelWidth <= 90",
    @"kMDItemContentTypeTree = 'public.image'",
    @"kMDItemContentTypeTree = 'public.folder' || kMDItemFSName = \"a\"c",
    @"InRange(kMDItemFSCreationDate,$time.today(-1),$time.today(1)) && kMDItemFSName = \"a\"",
    @"!(kMDItemFSName = \"a\"c && kMDItemPixelWidth > 5)",
    @"kMDItemTextContent = \"hello\"cdw && "
    @"(kMDItemFSName = \"x*\"c || kMDItemFSName = \"y*\"c)",
    nil];

  for (raw in raws) {
    GWSavedSearch *s = [GWSavedSearch savedSearchWithRawQuery: raw scopes: nil];
    NSString *text = [s mdkQueryStringAtDate: now];
    MDKQuery *q = text ? mdk(text) : nil;

    PASS(q != nil && [q isBuilt], "MDKit parses the translation of %s",
         [raw UTF8String]);
  }

  /* operators written as two characters must not be read as one */
  {
    MDKQuery *q = mdk(@"GSMDItemFSSize >= 5");
    NSString *d = [q description];

    PASS(q != nil && [d rangeOfString: @">="].location != NSNotFound,
         ">= is read as >=, got %s", [d UTF8String]);
    q = mdk(@"GSMDItemFSSize <= 5");
    d = [q description];
    PASS(q != nil && [d rangeOfString: @"<="].location != NSNotFound,
         "<= is read as <=, got %s", [d UTF8String]);
  }
  [[NSFileManager defaultManager] removeItemAtPath: tmp error: NULL];
  RELEASE(arp);
  return 0;
}
