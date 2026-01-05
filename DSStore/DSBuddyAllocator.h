/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class DSBuddyBlock;

@interface DSBuddyAllocator : NSObject 
{
    NSMutableData *_data;
    NSString *_filePath;
    BOOL _dirty;
    NSMutableArray *_freeBlocks;
    NSMutableArray *_usedBlocks;
}

- (id)initWithFile:(NSString *)filePath;
- (id)initWithData:(NSMutableData *)data;

- (BOOL)open;
- (void)close;
- (void)flush;

- (NSData *)readAtOffset:(NSUInteger)offset length:(NSUInteger)length;
- (void)writeAtOffset:(NSUInteger)offset data:(NSData *)data;

- (DSBuddyBlock *)allocateBlockWithSize:(NSUInteger)size;
- (DSBuddyBlock *)blockAtOffset:(NSUInteger)offset size:(NSUInteger)size;
- (void)deallocateBlock:(DSBuddyBlock *)block;

- (NSUInteger)fileSize;
- (BOOL)isDirty;

@end

@interface DSBuddyBlock : NSObject 
{
    DSBuddyAllocator *_allocator;
    NSUInteger _offset;
    NSUInteger _size;
    NSMutableData *_data;
    NSUInteger _position;
    BOOL _dirty;
}

- (id)initWithAllocator:(DSBuddyAllocator *)allocator 
                 offset:(NSUInteger)offset 
                   size:(NSUInteger)size;

- (void)close;
- (void)flush;
- (void)invalidate;

- (NSUInteger)tell;
- (void)seek:(NSUInteger)position;
- (void)seek:(NSUInteger)position whence:(int)whence;

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

- (NSString *)readUTF16String;
- (void)writeUTF16String:(NSString *)string;

- (void)zeroFill;

@property (readonly) NSUInteger offset;
@property (readonly) NSUInteger size;
@property (readonly) BOOL isDirty;

@end
