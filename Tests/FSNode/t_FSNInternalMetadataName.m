/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Files that only carry Finder metadata must never show up as items, or a
 * folder with a custom icon would list a stray "Icon" file. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNodeRep.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS([FSNodeRep isInternalMetadataName: @".DS_Store"], "a .DS_Store is internal");
  PASS([FSNodeRep isInternalMetadataName: @"._file"], "an AppleDouble sidecar is internal");
  PASS([FSNodeRep isInternalMetadataName: @"Icon\r"],
       "the Icon\\r file holding a folder's custom icon is internal");
  PASS(![FSNodeRep isInternalMetadataName: @"Icon"], "a plain Icon file is not");
  PASS(![FSNodeRep isInternalMetadataName: @"Icons"], "Icons is not");

  [arp release];
  return 0;
}
