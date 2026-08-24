/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/*
 * DSStore / .DS_Store interop tests.
 *
 * Principle (same as the metadata interop tests): the Mac is always right.
 * These tests load .DS_Store files captured from a real macOS 10.6 Finder and
 * assert Gershwin parses the same values Finder shows, so the on-disk format
 * is read correctly.  Fixtures live next to this file.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DSStore.h"

static NSString *fixture(NSString *name)
{
  NSString *here = [[[NSString stringWithUTF8String:__FILE__]
                       stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
  return here;
}

/* Forward interop (Mac writes, Gershwin reads).  Captured from 10.6 Finder:
 * a folder opened in a *new* window, four files dragged to known positions,
 * then the .DS_Store read back.  In 10.6 browser mode only icon positions
 * (Iloc) are persisted per-folder; view style / window geometry are global,
 * so this fixture carries Iloc only. */
static void test_forward_icon_positions(void)
{
  DSStore *store = [DSStore storeWithPath:fixture(@"ds_icon.DS_Store")];
  PASS([store load], "load ds_icon.DS_Store fixture");

  /* Ground truth from Finder (AppleScript 'position' of each file):
   * a.txt {40,40} b.txt {200,60} c.txt {80,220} d.txt {300,300}.
   * Gershwin's Iloc read must match exactly. */
  NSPoint a = [store iconLocationForFilename:@"a.txt"];
  NSPoint b = [store iconLocationForFilename:@"b.txt"];
  NSPoint c = [store iconLocationForFilename:@"c.txt"];
  NSPoint d = [store iconLocationForFilename:@"d.txt"];

  PASS(NSEqualPoints(a, NSMakePoint(40, 40)), "a.txt Iloc == (40,40) [Mac ground truth]");
  PASS(NSEqualPoints(b, NSMakePoint(200, 60)), "b.txt Iloc == (200,60)");
  PASS(NSEqualPoints(c, NSMakePoint(80, 220)), "c.txt Iloc == (80,220)");
  PASS(NSEqualPoints(d, NSMakePoint(300, 300)), "d.txt Iloc == (300,300)");

  /* Per-folder view style is absent in 10.6 browser mode (global), so the
   * directory vstl must be nil here - Gershwin must not invent one. */
  PASS([store viewStyleForDirectory] == nil, "no per-folder vstl in 10.6 browser mode");
}

/* Gershwin must round-trip an icon position it reads: re-encode the entry and
 * confirm the bytes (and thus what Finder would read back) are identical. */
static void test_iloc_roundtrip(void)
{
  DSStore *store = [DSStore storeWithPath:fixture(@"ds_icon.DS_Store")];
  PASS([store load], "load ds_icon.DS_Store fixture (roundtrip)");
  NSPoint a = [store iconLocationForFilename:@"a.txt"];
  DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile:@"a.txt" x:(int)a.x y:(int)a.y];
  NSData *blob = [e value];
  PASS(blob != nil && [blob length] == 16, "Iloc blob is 16 bytes (x,y + 8-byte tail)");
  int32_t x, y;
  [blob getBytes:&x range:NSMakeRange(0, 4)];
  [blob getBytes:&y range:NSMakeRange(4, 4)];
  x = (int32_t)NSSwapBigIntToHost(x);
  y = (int32_t)NSSwapBigIntToHost(y);
  PASS(x == 40 && y == 40, "re-encoded Iloc blob == (40,40)");
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  test_forward_icon_positions();
  test_iloc_roundtrip();
  [pool release];
  return 0;
}
