/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* On a FAT volume the Mac kernel, not Finder, writes and reads the "._"
 * files, in one fixed padded layout (evidence E35).  Since nothing says the
 * kernel accepts the compact tar layout, Workspace writes exactly that
 * layout there; the fixtures are the kernel's own files. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSAppleDouble.h"

static NSString * const kDir =
  @"interop/fixtures/finder106/E35-nonhfs-fat32";

static NSData *
fixture(NSString *name)
{
  return [NSData dataWithContentsOfFile:
    [kDir stringByAppendingPathComponent: name]];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSArray *names = [NSArray arrayWithObjects:
    @"fat-._a.txt", @"fat-._b.txt", @"fat-._c.txt", @"fat-._c-alias",
    @"fat-._.Trashes", @"fat-lf.._.DS_Store.bin", @"fat-lf-._sub",
    @"fat-._big.txt-5000B-xattr+quarantine", nil];

  START_SET("the kernel's own files come out byte for byte")
    for (NSString *n in names)
      {
        NSData *raw = fixture(n);
        PASS(raw != nil, "%s present", [n UTF8String]);
        PASS_EQUAL([GSAppleDouble volumeLayoutFromAppleDoubleData: raw], raw,
                   "%s: parse and write again gives the same bytes",
                   [n UTF8String]);
      }
  END_SET("the kernel's own files come out byte for byte")

  START_SET("built from scratch")
    NSData *store = fixture(@"fat-lf.._.DS_Store.bin");
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    NSMutableData *fi = [NSMutableData dataWithLength: 32];
    ((uint8_t *)[fi mutableBytes])[8] = 0x40;   /* kIsInvisible */
    [ad setFinderInfo: fi];
    PASS_EQUAL([ad appleDoubleDataInVolumeLayout], store,
               "an invisible .DS_Store's sidecar is the kernel's");

    GSAppleDouble *b = [[[GSAppleDouble alloc] initWithData:
      fixture(@"fat-._b.txt")] autorelease];
    GSAppleDouble *fresh = [[[GSAppleDouble alloc] init] autorelease];
    [fresh setFinderInfo: [b finderInfo]];
    NSDictionary *x = [b extendedAttributes];
    for (NSString *k in [[x allKeys] sortedArrayUsingSelector: @selector(compare:)])
      [fresh setXattr: [x objectForKey: k] forKey: k];
    PASS_EQUAL([fresh appleDoubleDataInVolumeLayout], fixture(@"fat-._b.txt"),
               "label, comment and an extra attribute as the kernel lays them out");
    NSData *out = [fresh appleDoubleDataInVolumeLayout];
    PASS([out length] == 4096, "one 4096-byte block");
  END_SET("built from scratch")

  START_SET("the kernel's empty fork is no fork")
    GSAppleDouble *b = [[[GSAppleDouble alloc] initWithData:
      fixture(@"fat-._b.txt")] autorelease];
    PASS(![b hasResourceFork], "the 286-byte placeholder in entry 2 is not a fork");
    GSAppleDouble *a = [[[GSAppleDouble alloc] initWithData:
      fixture(@"fat-._a.txt")] autorelease];
    PASS([[a resourceFork] length] == 83547, "a real fork is kept");
  END_SET("the kernel's empty fork is no fork")

  [arp release];
  return 0;
}
