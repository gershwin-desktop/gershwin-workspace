/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/*
 * See DSBuddyAllocator.h for the rationale.  Ported from the reference
 * `ds_store' Allocator (al45tair/ds_store), which emits Finder-readable files.
 */

#import "DSBuddyAllocator.h"
#import <string.h>

static inline uint32_t BE32(uint32_t x) { return NSSwapHostIntToBig(x); }
static inline uint32_t fromBE32(uint32_t x) { return NSSwapBigIntToHost(x); }
static inline uint16_t fromBE16(uint16_t x) { return NSSwapBigShortToHost(x); }
static inline uint16_t BE16(uint16_t x) { return NSSwapHostShortToBig(x); }

static NSUInteger bitLengthOf(NSUInteger n)
{
    NSUInteger bits = 0;
    while (n) { n >>= 1; bits++; }
    if (bits == 0) bits = 1;
    return bits;
}

/* ds_store's 16-byte header trailer (unused by Finder, but keep it consistent
 * with the allocator layout: root block at logical offset 2048). */
static const uint8_t kHeaderTrailer[16] = {
    0x00, 0x00, 0x10, 0x0c, 0x00, 0x00, 0x00, 0x87,
    0x00, 0x00, 0x20, 0x0b, 0x00, 0x00, 0x00, 0x00
};

@implementation DSBuddyAllocator

- (id)initWithFile:(NSString *)filePath
{
    if ((self = [super init])) {
        _filePath = [filePath copy];
        _data = nil;
        _dirty = NO;
        _offsets = [[NSMutableArray alloc] init];
        _toc = [[NSMutableDictionary alloc] init];
        _free = [[NSMutableArray alloc] init];
        for (int i = 0; i < 32; i++) {
            [_free addObject:[NSMutableArray array]];
        }
    }
    return self;
}

- (void)dealloc
{
    [_filePath release];
    [_data release];
    [_offsets release];
    [_toc release];
    [_free release];
    [super dealloc];
}

#pragma mark - Low-level byte access

- (NSData *)dataAtOffset:(NSUInteger)offset length:(NSUInteger)length
{
    if (offset + length > [_data length]) {
        NSUInteger have = [_data length] > offset ? [_data length] - offset : 0;
        NSMutableData *d = [NSMutableData dataWithLength:length];
        if (have > 0) {
            [d replaceBytesInRange:NSMakeRange(0, have)
                         withBytes:[_data bytes] + offset];
        }
        return d;
    }
    return [_data subdataWithRange:NSMakeRange(offset, length)];
}

- (void)setData:(NSData *)data atOffset:(NSUInteger)offset
{
    NSUInteger end = offset + [data length];
    if (end > [_data length]) {
        [_data setLength:end];
    }
    [_data replaceBytesInRange:NSMakeRange(offset, [data length])
                     withBytes:[data bytes]];
    _dirty = YES;
}

#pragma mark - Open / create

- (BOOL)open
{
    NSData *fileData = [NSData dataWithContentsOfFile:_filePath];
    if (fileData == nil || [fileData length] < 36) {
        return NO;
    }
    _data = [[NSMutableData alloc] initWithData:fileData];

    /* Header */
    if (fromBE32(*(const uint32_t *)[_data bytes]) != 1) return NO;
    if (memcmp([_data bytes] + 4, "Bud1", 4) != 0) return NO;

    uint32_t rootOffset = fromBE32(*(const uint32_t *)([_data bytes] + 8));
    memcpy(_unknown1, [_data bytes] + 20, 16);
    _rootBlock = rootOffset;

    /* Root block content at rootOffset + 4 */
    NSUInteger base = rootOffset + 4;
    if (base + 8 > [_data length]) return NO;

    uint32_t offsetCount = fromBE32(*(const uint32_t *)([_data bytes] + base));
    uint32_t unknown2    = fromBE32(*(const uint32_t *)([_data bytes] + base + 4));
    _unknown2 = unknown2;

    [_offsets removeAllObjects];
    const uint32_t *otab =
        (const uint32_t *)([_data bytes] + base + 8);
    for (uint32_t i = 0; i < offsetCount && i < 256; i++) {
        [_offsets addObject:[NSNumber numberWithUnsignedInt:fromBE32(otab[i])]];
    }

    /* TOC */
    NSUInteger p = base + 8 + 256 * 4;
    if (p + 4 > [_data length]) return NO;
    uint32_t tocCount = fromBE32(*(const uint32_t *)([_data bytes] + p));
    p += 4;
    [_toc removeAllObjects];
    for (uint32_t i = 0; i < tocCount; i++) {
        if (p + 1 > [_data length]) return NO;
        uint8_t nlen = *((const uint8_t *)([_data bytes] + p));
        p += 1;
        if (p + nlen + 4 > [_data length]) return NO;
        NSString *name = [[NSString alloc] initWithBytes:[_data bytes] + p
                                                  length:nlen
                                                encoding:NSASCIIStringEncoding];
        p += nlen;
        uint32_t bnum = fromBE32(*(const uint32_t *)([_data bytes] + p));
        p += 4;
        if (name) {
            [_toc setObject:[NSNumber numberWithUnsignedInt:bnum] forKey:name];
            [name release];
        }
    }

    /* Free lists (32 buckets) */
    [_free removeAllObjects];
    for (int i = 0; i < 32; i++) [_free addObject:[NSMutableArray array]];
    for (int i = 0; i < 32; i++) {
        if (p + 4 > [_data length]) return NO;
        uint32_t cnt = fromBE32(*(const uint32_t *)([_data bytes] + p));
        p += 4;
        NSMutableArray *bucket = [NSMutableArray arrayWithCapacity:cnt];
        for (uint32_t j = 0; j < cnt; j++) {
            if (p + 4 > [_data length]) return NO;
            uint32_t off = fromBE32(*(const uint32_t *)([_data bytes] + p));
            p += 4;
            [bucket addObject:[NSNumber numberWithUnsignedInt:off]];
        }
        [_free replaceObjectAtIndex:i withObject:bucket];
    }

    _dirty = NO;
    return YES;
}

- (BOOL)openForWriting
{
    _data = [[NSMutableData alloc] init];

    /* Header (root offset/size are rewritten in flush). */
    uint8_t header[36];
    uint32_t magic = BE32(1);
    memcpy(header, &magic, 4);
    memcpy(header + 4, "Bud1", 4);
    uint32_t ro = BE32(0x1000);
    memcpy(header + 8, &ro, 4);     /* root offset */
    uint32_t rs = BE32(32);
    memcpy(header + 12, &rs, 4);    /* root size (placeholder) */
    memcpy(header + 16, &ro, 4);    /* copy of root offset */
    memcpy(header + 20, kHeaderTrailer, 16);
    [_data appendBytes:header length:36];

    /* The buddy root is block 0.  macOS writes it at file offset 0x1000 (a
     * 2048-byte, width-11 block); Finder rejects the file if it lives
     * anywhere else, so we reserve block 0 there up front.  DSDB and the
     * B-tree nodes then take blocks 1, 2, ...  The exact free-list contents
     * are not checked by Finder (verified empirically), but the seed must
     * avoid colliding with the two reserved blocks. */
    [_data setLength:0x1800];

    /* Live state */
    [_offsets removeAllObjects];
    /* Block 0 = buddy root at 0x1000, width 11 (0x100b). */
    [_offsets addObject:[NSNumber numberWithUnsignedInt:0x100b]];
    _rootBlock = 0x100b;
    _unknown2 = 0;
    [_toc removeAllObjects];
    [_free removeAllObjects];
    for (int i = 0; i < 32; i++) [_free addObject:[NSMutableArray array]];
    for (int i = 5; i <= 30; i++) {
        uint32_t off;
        if (i == 5) {
            /* DSDB (the first ~20-byte allocation) must land at 0x40, so seed
             * the width-5 bucket with 0x40 rather than the default 0x20. */
            off = 0x40;
        } else if (i == 6 || i == 12) {
            /* 0x40 is taken by DSDB (as a width-5 block) and 0x1000 by the
             * root, so skip those widths' default seed. */
            continue;
        } else {
            off = (1U << i);
        }
        [[_free objectAtIndex:i] addObject:[NSNumber numberWithUnsignedInt:off]];
    }

    _dirty = YES;
    return YES;
}

- (void)close { [self flush]; }
- (void)flush
{
    if (!_dirty) return;
    [self writeRootBlock];
    [_data writeToFile:_filePath atomically:YES];
    _dirty = NO;
}

- (void)writeRootBlock
{
    NSMutableData *root = [NSMutableData data];

    /* Offsets */
    uint32_t oc = BE32((uint32_t)[_offsets count]);
    [root appendBytes:&oc length:4];
    uint32_t u2 = BE32(_unknown2);
    [root appendBytes:&u2 length:4];
    for (NSUInteger i = 0; i < [_offsets count]; i++) {
        uint32_t a = BE32([[_offsets objectAtIndex:i] unsignedIntValue]);
        [root appendBytes:&a length:4];
    }
    /* Pad offset table to a multiple of 256 entries. */
    NSUInteger padded = ([_offsets count] + 255) & ~255UL;
    for (NSUInteger i = [_offsets count]; i < padded; i++) {
        uint32_t z = 0;
        [root appendBytes:&z length:4];
    }

    /* TOC (sorted by name, for stability) */
    NSArray *names = [[_toc allKeys] sortedArrayUsingSelector:@selector(compare:)];
    uint32_t tc = BE32((uint32_t)[names count]);
    [root appendBytes:&tc length:4];
    for (NSString *name in names) {
        NSData *nb = [name dataUsingEncoding:NSASCIIStringEncoding];
        uint8_t nlen = (uint8_t)[nb length];
        [root appendBytes:&nlen length:1];
        [root appendData:nb];
        uint32_t bnum = BE32([[_toc objectForKey:name] unsignedIntValue]);
        [root appendBytes:&bnum length:4];
    }

    /* Free lists */
    for (int i = 0; i < 32; i++) {
        NSArray *bucket = [_free objectAtIndex:i];
        uint32_t cnt = BE32((uint32_t)[bucket count]);
        [root appendBytes:&cnt length:4];
        for (NSNumber *n in bucket) {
            uint32_t off = BE32([n unsignedIntValue]);
            [root appendBytes:&off length:4];
        }
    }

    /* The root block is addressed by _rootBlock (set by the caller, save).
     * It was allocated large enough (pageSize) to hold the root content, so
     * write it directly without reallocating (reallocating would move it and
     * orphan the B-tree's child pointers). */
    uint32_t rootAddr = _rootBlock;
    if (rootAddr == 0 && [_offsets count] > 0) {
        rootAddr = [[_offsets objectAtIndex:0] unsignedIntValue];
    }

    uint32_t rootBase = rootAddr & ~0x1FU;
    /* Rewrite header (root offset/size derived from block 0). */
    uint32_t ro = BE32(rootBase);
    [_data replaceBytesInRange:NSMakeRange(8, 4) withBytes:&ro];
    [_data replaceBytesInRange:NSMakeRange(16, 4) withBytes:&ro];
    uint32_t rs = BE32(1U << (rootAddr & 0x1FU));
    [_data replaceBytesInRange:NSMakeRange(12, 4) withBytes:&rs];

    /* Pad the root content out to the full block size so the on-disk file
     * covers the whole block (the header advertises rootSize = block size). */
    NSUInteger rsize = 1U << (rootAddr & 0x1FU);
    if ([root length] < rsize) {
        [root setLength:rsize];
    }

    /* Write root block content at rootBase + 4. */
    [self setData:root atOffset:rootBase + 4];
}

#pragma mark - Blocks

- (DSBuddyBlock *)blockAtOffset:(NSUInteger)offset size:(NSUInteger)size
{
    return [[[DSBuddyBlock alloc] initWithAllocator:self
                                     contentOffset:offset
                                               size:size] autorelease];
}

- (DSBuddyBlock *)getBlock:(int)block
{
    if (block < 0 || block >= (int)[_offsets count]) return nil;
    uint32_t addr = [[_offsets objectAtIndex:block] unsignedIntValue];
    uint32_t offset = addr & ~0x1FU;
    uint32_t size = 1U << (addr & 0x1FU);
    return [[[DSBuddyBlock alloc] initWithAllocator:self
                                      contentOffset:(offset + 4)
                                                size:size] autorelease];
}

- (uint32_t)addressForBlock:(int)block
{
    if (block < 0 || block >= (int)[_offsets count]) return 0;
    return [[_offsets objectAtIndex:block] unsignedIntValue];
}

#pragma mark - Allocation

- (int)allocate:(NSUInteger)bytes
{
    int block = 0;
    while (block < (int)[_offsets count] &&
           [[_offsets objectAtIndex:block] unsignedIntValue] != 0) {
        block++;
    }
    if (block == (int)[_offsets count]) {
        [_offsets addObject:[NSNumber numberWithUnsignedInt:0]];
    }
    return [self allocate:bytes block:block];
}

- (int)allocate:(NSUInteger)bytes block:(int)block
{
    /* Buddy block size is 2^width; we need 2^width >= bytes, i.e.
     * width = ceil(log2(bytes)).  bitLengthOf(n) == floor(log2(n))+1,
     * which is one too high for exact powers of two, so use n-1. */
    NSUInteger width = MAX((bytes > 1 ? (NSUInteger)bitLengthOf(bytes - 1) : 5UL), 5UL);

    uint32_t addr = [[_offsets objectAtIndex:block] unsignedIntValue];
    if (addr) {
        uint32_t ow = addr & 0x1FU;
        if (ow == (uint32_t)width) {
            return block;
        }
        [self releaseBlock:block];
    }

    uint32_t offset = [self _alloc:(uint32_t)width];
    [_offsets replaceObjectAtIndex:block
                        withObject:[NSNumber numberWithUnsignedInt:(offset | (uint32_t)width)]];
    return block;
}

- (void)releaseBlock:(int)block
{
    uint32_t addr = [[_offsets objectAtIndex:block] unsignedIntValue];
    if (!addr) return;
    uint32_t width = addr & 0x1FU;
    uint32_t offset = addr & ~0x1FU;
    [self _release:offset width:width];
    if (block == (int)[_offsets count] - 1) {
        [_offsets removeLastObject];
    } else {
        [_offsets replaceObjectAtIndex:block
                            withObject:[NSNumber numberWithUnsignedInt:0]];
    }
}

- (uint32_t)_alloc:(uint32_t)width
{
    uint32_t w = width;
    while (w < 32 && [[_free objectAtIndex:w] count] == 0) w++;
    while (w > width) {
        uint32_t offset = [[[_free objectAtIndex:w] objectAtIndex:0] unsignedIntValue];
        [[_free objectAtIndex:w] removeObjectAtIndex:0];
        w -= 1;
        uint32_t buddy = offset ^ (1U << w);
        [_free replaceObjectAtIndex:w
                         withObject:[NSMutableArray arrayWithObjects:
                                     [NSNumber numberWithUnsignedInt:offset],
                                     [NSNumber numberWithUnsignedInt:buddy], nil]];
    }
    _dirty = YES;
    uint32_t offset = [[[_free objectAtIndex:w] objectAtIndex:0] unsignedIntValue];
    [[_free objectAtIndex:w] removeObjectAtIndex:0];
    return offset;
}

- (void)_release:(uint32_t)offset width:(uint32_t)width
{
    while (YES) {
        uint32_t buddy = offset ^ (1U << width);
        NSMutableArray *bucket = [_free objectAtIndex:width];
        NSUInteger idx = [bucket indexOfObject:[NSNumber numberWithUnsignedInt:buddy]];
        if (idx == NSNotFound) break;
        [bucket removeObjectAtIndex:idx];
        offset &= buddy;
        width += 1;
    }
    NSMutableArray *bucket = [_free objectAtIndex:width];
    /* insert keeping sorted (ascending) */
    NSUInteger i = 0;
    while (i < [bucket count] &&
           [[bucket objectAtIndex:i] unsignedIntValue] < offset) i++;
    [bucket insertObject:[NSNumber numberWithUnsignedInt:offset] atIndex:i];
    _dirty = YES;
}

#pragma mark - TOC

- (int)blockNumberForTOCName:(NSString *)name
{
    NSNumber *n = [_toc objectForKey:name];
    return n ? [n intValue] : -1;
}

- (void)setTOCName:(NSString *)name blockNumber:(int)block
{
    [_toc setObject:[NSNumber numberWithInt:block] forKey:name];
    _dirty = YES;
}

- (void)setRootBlockAddress:(uint32_t)address
{
    _rootBlock = address;
    _dirty = YES;
}

#pragma mark - Misc

- (NSUInteger)fileSize { return [_data length]; }
- (BOOL)isDirty { return _dirty; }

@end


@implementation DSBuddyBlock

- (id)initWithAllocator:(DSBuddyAllocator *)allocator
         contentOffset:(NSUInteger)contentOffset
                   size:(NSUInteger)size
{
    if ((self = [super init])) {
        _allocator = [allocator retain];
        _contentOffset = contentOffset;
        _size = size;
        _pos = 0;
        _dirty = NO;
    }
    return self;
}

- (void)dealloc
{
    [self close];
    [_allocator release];
    [super dealloc];
}

- (void)close { _dirty = NO; }
- (void)invalidate { _dirty = NO; }

- (NSUInteger)tell { return _pos; }
- (void)seek:(NSUInteger)position { _pos = position; }

- (NSData *)readBytes:(NSUInteger)length
{
    NSData *d = [_allocator dataAtOffset:(_contentOffset + _pos) length:length];
    _pos += length;
    return d;
}

- (void)writeBytes:(NSData *)data
{
    [_allocator setData:data atOffset:(_contentOffset + _pos)];
    _pos += [data length];
    _dirty = YES;
}

- (uint8_t)readUInt8
{
    NSData *d = [self readBytes:1];
    return d.length ? *(const uint8_t *)[d bytes] : 0;
}
- (uint16_t)readUInt16
{
    NSData *d = [self readBytes:2];
    if ([d length] < 2) return 0;
    uint16_t v; memcpy(&v, [d bytes], 2); return fromBE16(v);
}
- (uint32_t)readUInt32
{
    NSData *d = [self readBytes:4];
    if ([d length] < 4) return 0;
    uint32_t v; memcpy(&v, [d bytes], 4); return fromBE32(v);
}
- (uint64_t)readUInt64
{
    NSData *d = [self readBytes:8];
    if ([d length] < 8) return 0;
    uint64_t v; memcpy(&v, [d bytes], 8); return NSSwapBigLongLongToHost(v);
}

- (void)writeUInt8:(uint8_t)value
{
    [self writeBytes:[NSData dataWithBytes:&value length:1]];
}
- (void)writeUInt16:(uint16_t)value
{
    uint16_t v = BE16(value);
    [self writeBytes:[NSData dataWithBytes:&v length:2]];
}
- (void)writeUInt32:(uint32_t)value
{
    uint32_t v = BE32(value);
    [self writeBytes:[NSData dataWithBytes:&v length:4]];
}
- (void)writeUInt64:(uint64_t)value
{
    uint64_t v = NSSwapHostLongLongToBig(value);
    [self writeBytes:[NSData dataWithBytes:&v length:8]];
}

- (void)zeroFill
{
    NSUInteger len = _size - _pos;
    NSMutableData *z = [NSMutableData dataWithLength:len];
    [self writeBytes:z];
}

@end
