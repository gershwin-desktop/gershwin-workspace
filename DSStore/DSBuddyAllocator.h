/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/*
 * Buddy allocator for .DS_Store files.
 *
 * This is a faithful port of the allocator used by the reference `ds_store'
 * Python package (al45tair/ds_store), which produces files that macOS Finder
 * reads unchanged.  The on-disk format is a "Bud1" superblock followed by a
 * root block that holds the offset table, the table-of-contents (TOC), and 32
 * free lists (one per block size, 2^0 .. 2^31).  Blocks are addressed by a
 * 32-bit word whose low 5 bits are the block-size class (log2) and whose high
 * bits are the file offset of the block's 4-byte lead; the block's content
 * begins 4 bytes later.
 */

#import <Foundation/Foundation.h>

@class DSBuddyBlock;

@interface DSBuddyAllocator : NSObject
{
    NSMutableData *_data;
    NSString *_filePath;
    BOOL _dirty;

    /* Parsed / live allocator state */
    uint32_t _unknown1[4];      /* 16-byte header trailer (unused by Finder) */
    uint32_t _unknown2;         /* root-block unknown field */
    NSMutableArray *_offsets;   /* NSNumber(uint32) per block: offset|class */
    NSMutableDictionary *_toc;  /* TOC name -> NSNumber(block number) */
    NSMutableArray *_free;       /* 32 NSMutableArray of NSNumber(base offset) */
    uint32_t _rootBlock;         /* address (offset|class) of the B-tree root */
}

- (id)initWithFile:(NSString *)filePath;

/* Open an existing .DS_Store for reading/modifying. */
- (BOOL)open;

/* Create a new (empty) .DS_Store and prepare it for writing. */
- (BOOL)openForWriting;

- (void)close;
- (void)flush;

/* Reader support: a block whose content begins at `offset' (caller already
 * adds the +4 lead). */
- (DSBuddyBlock *)blockAtOffset:(NSUInteger)offset size:(NSUInteger)size;

/* Writer support. */
- (int)allocate:(NSUInteger)bytes;
- (void)releaseBlock:(int)block;
- (DSBuddyBlock *)getBlock:(int)block;
- (uint32_t)addressForBlock:(int)block;
- (int)blockNumberForTOCName:(NSString *)name;
- (void)setTOCName:(NSString *)name blockNumber:(int)block;
- (void)setRootBlockAddress:(uint32_t)address;

- (NSUInteger)fileSize;
- (BOOL)isDirty;

/* Low-level byte access used by DSBuddyBlock. */
- (NSData *)dataAtOffset:(NSUInteger)offset length:(NSUInteger)length;
- (void)setData:(NSData *)data atOffset:(NSUInteger)offset;

@end


@interface DSBuddyBlock : NSObject
{
    DSBuddyAllocator *_allocator;
    NSUInteger _contentOffset;  /* file position where pos 0 maps */
    NSUInteger _size;
    NSUInteger _pos;
    BOOL _dirty;
}

- (id)initWithAllocator:(DSBuddyAllocator *)allocator
         contentOffset:(NSUInteger)contentOffset
                   size:(NSUInteger)size;

- (void)close;
- (void)invalidate;

- (NSUInteger)tell;
- (void)seek:(NSUInteger)position;

- (NSData *)readBytes:(NSUInteger)length;
- (void)writeBytes:(NSData *)data;

- (uint8_t)readUInt8;
- (uint16_t)readUInt16;
- (uint32_t)readUInt32;
- (uint64_t)readUInt64;

- (void)writeUInt8:(uint8_t)value;
- (void)writeUInt16:(uint16_t)value;
- (void)writeUInt32:(uint32_t)value;
- (void)writeUInt64:(uint64_t)value;

- (void)zeroFill;

@property (readonly) NSUInteger offset;
@property (readonly) NSUInteger size;
@property (readonly) BOOL isDirty;

@end
