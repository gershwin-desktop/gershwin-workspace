/* t_IMetaResources.m - classic resource fork reader and writer in
 * GSFileMetadata.  Headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSFileMetadata.h"

static NSData *D(const char *s)
{
  return [NSData dataWithBytes: s length: strlen(s)];
}

static NSDictionary *E(const char *type, NSInteger rid, NSData *data)
{
  return [GSFileMetadata resourceEntryWithType:
            [GSFileMetadata osTypeFromString: [NSString stringWithUTF8String: type]]
                                    resourceID: rid
                                          data: data];
}

static GSOType T(const char *type)
{
  return [GSFileMetadata osTypeFromString: [NSString stringWithUTF8String: type]];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- MI-RSRC-1: writer and reader agree, several types and ids --- */
  {
    NSData *fork = [GSFileMetadata resourceForkWithResources:
      [NSArray arrayWithObjects:
        E("alis", 0, D("ALIAS0")),
        E("url ", 256, D("http://example.org/")),
        E("alis", -5, D("ALIASm5")),
        E("alis", 7, [NSData data]),
        nil]];
    PASS(fork != nil, "MI-RSRC-1 fork is built");
    PASS_EQUAL([GSFileMetadata dataForResourceType: T("alis") resourceID: 0
                                            inFork: fork], D("ALIAS0"),
               "MI-RSRC-1 alis 0");
    PASS_EQUAL([GSFileMetadata dataForResourceType: T("url ") resourceID: 256
                                            inFork: fork],
               D("http://example.org/"), "MI-RSRC-1 url 256");
    PASS_EQUAL([GSFileMetadata dataForResourceType: T("alis") resourceID: -5
                                            inFork: fork], D("ALIASm5"),
               "MI-RSRC-1 negative id");
    PASS_EQUAL([GSFileMetadata dataForResourceType: T("alis") resourceID: 7
                                            inFork: fork], [NSData data],
               "MI-RSRC-1 empty resource is empty data, not missing");
    PASS([GSFileMetadata dataForResourceType: T("alis") resourceID: 1
                                      inFork: fork] == nil,
         "MI-RSRC-1 unknown id is nil");
    PASS([GSFileMetadata dataForResourceType: T("icns") resourceID: 0
                                      inFork: fork] == nil,
         "MI-RSRC-1 unknown type is nil");
    PASS_EQUAL([GSFileMetadata firstDataForResourceType: T("alis")
                                                 inFork: fork],
               D("ALIASm5"), "MI-RSRC-2 first resource of a type has the lowest id");
    PASS([GSFileMetadata firstDataForResourceType: T("icns") inFork: fork] == nil,
         "MI-RSRC-2 first of absent type is nil");

    /* MI-RSRC-3: no truncation or byte flip may crash or read outside */
    NSUInteger n = [fork length], i;
    for (i = 0; i < n; i += 7)
      {
        NSData *cut = [fork subdataWithRange: NSMakeRange(0, i)];
        (void)[GSFileMetadata firstDataForResourceType: T("alis") inFork: cut];
        (void)[GSFileMetadata dataForResourceType: T("url ") resourceID: 256
                                           inFork: cut];
      }
    PASS(YES, "MI-RSRC-3 every truncation is survived");
    NSMutableData *bad = [[fork mutableCopy] autorelease];
    uint8_t *p = [bad mutableBytes];
    memset(p + 4, 0xFF, 4);   /* map offset beyond the fork */
    PASS([GSFileMetadata firstDataForResourceType: T("alis") inFork: bad] == nil,
         "MI-RSRC-3 map offset beyond the fork is refused");
    bad = [[fork mutableCopy] autorelease];
    p = [bad mutableBytes];
    memset(p + 256, 0xFF, 4);   /* first resource claims 4 GB */
    PASS([GSFileMetadata dataForResourceType: T("alis") resourceID: 0
                                      inFork: bad] == nil,
         "MI-RSRC-3 resource size beyond the data area is refused");
    bad = [[fork mutableCopy] autorelease];
    p = [bad mutableBytes];
    uint32_t mapOff = (p[4] << 24) | (p[5] << 16) | (p[6] << 8) | p[7];
    uint16_t tl = (p[mapOff + 24] << 8) | p[mapOff + 25];
    p[mapOff + tl] = 0xFF; p[mapOff + tl + 1] = 0xFF;   /* type count - 1 = -1 */
    PASS([GSFileMetadata firstDataForResourceType: T("alis") inFork: bad] == nil,
         "MI-RSRC-3 a type count of -1 is refused");
    PASS([GSFileMetadata firstDataForResourceType: T("alis") inFork: nil] == nil
         && [GSFileMetadata firstDataForResourceType: T("alis")
                                              inFork: [NSData data]] == nil,
         "MI-RSRC-3 nil and empty forks");
  }

  /* --- MI-RSRC-4: writer refuses what it cannot address --- */
  {
    PASS([GSFileMetadata resourceForkWithResources: nil] == nil
         && [GSFileMetadata resourceForkWithResources: [NSArray array]] == nil,
         "MI-RSRC-4 no resources, no fork");
    PASS([GSFileMetadata resourceForkWithResources:
            [NSArray arrayWithObject: E("alis", 70000, D("x"))]] == nil,
         "MI-RSRC-4 an id outside SInt16 is refused");
  }

  /* --- MI-RSRC-5: the icns writer is the generic writer --- */
  {
    NSData *icns = D("icnsXXXXpayload");
    NSData *a = [GSFileMetadata resourceForkWithICNS: icns];
    NSData *b = [GSFileMetadata resourceForkWithResources:
      [NSArray arrayWithObject: E("icns", -16455, icns)]];
    PASS_EQUAL(a, b, "MI-RSRC-5 resourceForkWithICNS: uses the generic writer");
  }

  [arp release];
  return 0;
}
