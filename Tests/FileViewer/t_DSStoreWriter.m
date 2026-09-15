#include <Foundation/Foundation.h>
#include "DSStore.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { failures++; printf("FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); } else { printf("ok: %s\n", msg); } } while (0)

/* Build a 16-byte Iloc blob (matches the fixture's (40,40) shape). */
static NSData *ilocBlob(int x, int y)
{
    unsigned char b[16];
    memset(b, 0, 16);
    b[0] = (x >> 24) & 0xFF; b[1] = (x >> 16) & 0xFF; b[2] = (x >> 8) & 0xFF; b[3] = x & 0xFF;
    b[4] = (y >> 24) & 0xFF; b[5] = (y >> 16) & 0xFF; b[6] = (y >> 8) & 0xFF; b[7] = y & 0xFF;
    return [NSData dataWithBytes:b length:16];
}

static DSStoreEntry *iloc(NSString *name, int x, int y)
{
    return [[[DSStoreEntry alloc] initWithFilename:name
                                             code:@"Iloc"
                                             type:@"blob"
                                            value:ilocBlob(x, y)] autorelease];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *outPath = @"/tmp/wtest.DS_Store";
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    NSArray *entries = [NSArray arrayWithObjects:
        iloc(@"a.txt", 40, 40),
        iloc(@"b.txt", 200, 60),
        iloc(@"c.txt", 80, 220),
        iloc(@"d.txt", 300, 300),
        [[[DSStoreEntry alloc] initWithFilename:@"e.txt" code:@"vstl" type:@"blob"
                                         value:[NSData dataWithBytes:"ABCD" length:4]] autorelease],
        nil];

    DSStore *store = [DSStore createStoreAtPath:outPath withEntries:entries];
    CHECK([store save], "save returns YES");

    /* Re-read with a fresh store. */
    DSStore *re = [DSStore storeWithPath:outPath];
    NSArray *loaded = [re entries];
    CHECK([loaded count] == 5, "round-trip preserves 5 entries");

    DSStoreEntry *a = [re entryForFilename:@"a.txt" code:@"Iloc"];
    CHECK(a != nil, "a.txt Iloc present after round-trip");
    if (a) {
        NSData *v = [a value];
        int rx = ((const unsigned char *)[v bytes])[3];
        int ry = ((const unsigned char *)[v bytes])[7];
        CHECK(rx == 40 && ry == 40, "a.txt Iloc == (40,40) after round-trip");
    }
    DSStoreEntry *e = [re entryForFilename:@"e.txt" code:@"vstl"];
    CHECK(e != nil, "e.txt vstl present after round-trip");

    printf(failures ? "\nWRITER TEST FAILED (%d)\n" : "\nWRITER TEST PASSED\n", failures);
    [pool release];
    return failures ? 1 : 0;
}
