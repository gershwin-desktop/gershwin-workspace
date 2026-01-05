/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSBuddyAllocator.h"
#import "DSStore.h"
#include <sys/stat.h>

// Constants from buddy.py
#define BUDDY_MAGIC 0x00000001
#define BUDDY_VERSION 0x42756431  // "Bud1"
#define BUDDY_HEADER_SIZE 32

// Byte swapping functions
static uint16_t swap16(uint16_t x) {
    return ((x & 0xFF00) >> 8) | ((x & 0x00FF) << 8);
}

static uint32_t swap32(uint32_t x) {
    return ((x & 0xFF000000) >> 24) | ((x & 0x00FF0000) >> 8) |
           ((x & 0x0000FF00) << 8)  | ((x & 0x000000FF) << 24);
}

static uint64_t swap64(uint64_t x) {
    return ((x & 0xFF00000000000000ULL) >> 56) | ((x & 0x00FF000000000000ULL) >> 40) |
           ((x & 0x0000FF0000000000ULL) >> 24) | ((x & 0x000000FF00000000ULL) >> 8) |
           ((x & 0x00000000FF000000ULL) << 8)  | ((x & 0x0000000000FF0000ULL) << 24) |
           ((x & 0x000000000000FF00ULL) << 40) | ((x & 0x00000000000000FFULL) << 56);
}

@implementation DSBuddyAllocator

- (id)initWithFile:(NSString *)filePath {
    if ((self = [super init])) {
        _filePath = [filePath copy];
        _data = nil;
        _dirty = NO;
        _freeBlocks = [[NSMutableArray alloc] init];
        _usedBlocks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (id)initWithData:(NSMutableData *)data {
    if ((self = [super init])) {
        _filePath = nil;
        _data = [data retain];
        _dirty = NO;
        _freeBlocks = [[NSMutableArray alloc] init];
        _usedBlocks = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc {
    [self close];
    [_filePath release];
    [_data release];
    [_freeBlocks release];
    [_usedBlocks release];
    [super dealloc];
}

- (BOOL)open {
    if (_data) {
        if (gDSStoreVerbose) NSLog(@"DEBUG: Allocator already opened with data");
        return YES; // Already opened with data
    }
    
    if (!_filePath) {
        if (gDSStoreVerbose) NSLog(@"DEBUG: No file path provided");
        return NO;
    }
    
    if (gDSStoreVerbose) NSLog(@"DEBUG: Attempting to open file: %@", _filePath);
    NSData *fileData = [NSData dataWithContentsOfFile:_filePath];
    if (!fileData) {
        if (gDSStoreVerbose) NSLog(@"DEBUG: Failed to read file data from: %@", _filePath);
        return NO;
    }
    
    if (gDSStoreVerbose) NSLog(@"DEBUG: Successfully read %lu bytes from file", (unsigned long)[fileData length]);
    _data = [[NSMutableData dataWithData:fileData] retain];
    return YES;
}

- (void)close {
    if (_dirty) {
        [self flush];
    }
}

- (void)flush {
    if (_dirty && _filePath && _data) {
        [_data writeToFile:_filePath atomically:YES];
        _dirty = NO;
    }
}

- (NSData *)readAtOffset:(NSUInteger)offset length:(NSUInteger)length {
    if (!_data || offset + length > [_data length]) {
        return nil;
    }
    
    return [_data subdataWithRange:NSMakeRange(offset, length)];
}

- (void)writeAtOffset:(NSUInteger)offset data:(NSData *)data {
    if (!_data) {
        return;
    }
    
    NSUInteger dataLength = [data length];
    NSUInteger requiredSize = offset + dataLength;
    
    // Extend data if necessary
    if (requiredSize > [_data length]) {
        [_data setLength:requiredSize];
    }
    
    [_data replaceBytesInRange:NSMakeRange(offset, dataLength) withBytes:[data bytes]];
    _dirty = YES;
}

- (DSBuddyBlock *)allocateBlockWithSize:(NSUInteger)size {
    // Simplified allocation - for full implementation, would need to track free blocks
    NSUInteger offset = [_data length];
    [_data setLength:offset + size];
    
    DSBuddyBlock *block = [[DSBuddyBlock alloc] initWithAllocator:self offset:offset size:size];
    [_usedBlocks addObject:block];
    return [block autorelease];
}

- (DSBuddyBlock *)blockAtOffset:(NSUInteger)offset size:(NSUInteger)size {
    if (!_data || offset + size > [_data length]) {
        return nil;
    }
    
    DSBuddyBlock *block = [[DSBuddyBlock alloc] initWithAllocator:self offset:offset size:size];
    return [block autorelease];
}

- (void)deallocateBlock:(DSBuddyBlock *)block {
    [_usedBlocks removeObject:block];
    // In full implementation, would add to free blocks list
}

- (NSUInteger)fileSize {
    return _data ? [_data length] : 0;
}

- (BOOL)isDirty {
    return _dirty;
}

@end

@implementation DSBuddyBlock

- (id)initWithAllocator:(DSBuddyAllocator *)allocator 
                 offset:(NSUInteger)offset 
                   size:(NSUInteger)size {
    if ((self = [super init])) {
        _allocator = [allocator retain];
        _offset = offset;
        _size = size;
        _position = 0;
        _dirty = NO;
        
        NSData *blockData = [allocator readAtOffset:offset length:size];
        if (blockData) {
            _data = [[NSMutableData dataWithData:blockData] retain];
        } else {
            _data = [[NSMutableData dataWithLength:size] retain];
        }
    }
    return self;
}

- (void)dealloc {
    [self close];
    [_allocator release];
    [_data release];
    [super dealloc];
}

- (void)close {
    if (_dirty) {
        [self flush];
    }
}

- (void)flush {
    if (_dirty) {
        [_allocator writeAtOffset:_offset data:_data];
        _dirty = NO;
    }
}

- (void)invalidate {
    _dirty = NO;
}

- (NSUInteger)tell {
    return _position;
}

- (void)seek:(NSUInteger)position {
    [self seek:position whence:0]; // SEEK_SET
}

- (void)seek:(NSUInteger)position whence:(int)whence {
    switch (whence) {
        case 0: // SEEK_SET
            _position = position;
            break;
        case 1: // SEEK_CUR
            _position += position;
            break;
        case 2: // SEEK_END
            _position = _size + position;
            break;
    }
    
    if (_position > _size) {
        _position = _size;
    }
}

- (NSData *)readBytes:(NSUInteger)length {
    if (_position + length > _size) {
        length = _size - _position;
    }
    
    NSData *result = [_data subdataWithRange:NSMakeRange(_position, length)];
    _position += length;
    return result;
}

- (void)writeBytes:(NSData *)data {
    NSUInteger length = [data length];
    if (_position + length > _size) {
        // Can't write beyond block boundary
        return;
    }
    
    [_data replaceBytesInRange:NSMakeRange(_position, length) withBytes:[data bytes]];
    _position += length;
    _dirty = YES;
}

- (uint8_t)readUInt8 {
    if (_position + 1 > _size) {
        return 0;
    }
    
    uint8_t value;
    [_data getBytes:&value range:NSMakeRange(_position, 1)];
    _position += 1;
    return value;
}

- (uint16_t)readUInt16 {
    if (_position + 2 > _size) {
        return 0;
    }
    
    uint16_t value;
    [_data getBytes:&value range:NSMakeRange(_position, 2)];
    _position += 2;
    return swap16(value); // Convert from big-endian
}

- (uint32_t)readUInt32 {
    if (_position + 4 > _size) {
        return 0;
    }
    
    uint32_t value;
    [_data getBytes:&value range:NSMakeRange(_position, 4)];
    _position += 4;
    return swap32(value); // Convert from big-endian
}

- (uint64_t)readUInt64 {
    if (_position + 8 > _size) {
        return 0;
    }
    
    uint64_t value;
    [_data getBytes:&value range:NSMakeRange(_position, 8)];
    _position += 8;
    return swap64(value); // Convert from big-endian
}

- (void)writeUInt8:(uint8_t)value {
    if (_position + 1 > _size) {
        return;
    }
    
    [_data replaceBytesInRange:NSMakeRange(_position, 1) withBytes:&value];
    _position += 1;
    _dirty = YES;
}

- (void)writeUInt16:(uint16_t)value {
    if (_position + 2 > _size) {
        return;
    }
    
    uint16_t bigEndianValue = swap16(value);
    [_data replaceBytesInRange:NSMakeRange(_position, 2) withBytes:&bigEndianValue];
    _position += 2;
    _dirty = YES;
}

- (void)writeUInt32:(uint32_t)value {
    if (_position + 4 > _size) {
        return;
    }
    
    uint32_t bigEndianValue = swap32(value);
    [_data replaceBytesInRange:NSMakeRange(_position, 4) withBytes:&bigEndianValue];
    _position += 4;
    _dirty = YES;
}

- (void)writeUInt64:(uint64_t)value {
    if (_position + 8 > _size) {
        return;
    }
    
    uint64_t bigEndianValue = swap64(value);
    [_data replaceBytesInRange:NSMakeRange(_position, 8) withBytes:&bigEndianValue];
    _position += 8;
    _dirty = YES;
}

- (NSString *)readUTF16String {
    uint32_t length = [self readUInt32];
    if (length == 0) {
        return @"";
    }
    
    NSData *stringData = [self readBytes:length * 2];
    if (!stringData) {
        return @"";
    }
    
    return [[[NSString alloc] initWithData:stringData 
                                  encoding:NSUTF16BigEndianStringEncoding] autorelease];
}

- (void)writeUTF16String:(NSString *)string {
    NSData *stringData = [string dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    uint32_t length = (uint32_t)([stringData length] / 2);
    
    [self writeUInt32:length];
    [self writeBytes:stringData];
}

- (void)zeroFill {
    NSUInteger remaining = _size - _position;
    if (remaining > 0) {
        NSMutableData *zeros = [NSMutableData dataWithLength:remaining];
        [self writeBytes:zeros];
    }
}

- (NSUInteger)offset {
    return _offset;
}

- (NSUInteger)size {
    return _size;
}

- (BOOL)isDirty {
    return _dirty;
}

@end
