/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSStore.h"
#import "DSStoreCodecs.h"

// Global verbose flag for debug output
BOOL gDSStoreVerbose = NO;

// Byte order conversion macros for GNUstep
#define CFSwapInt32BigToHost(x) NSSwapBigIntToHost(x)
#define CFSwapInt16BigToHost(x) NSSwapBigShortToHost(x)

// Constants from .DS_Store format specification
#define DSDB_MAGIC 0x44534442  // "DSDB"

@interface DSStore (Private)
- (NSMutableDictionary *)_lsvpDict;
- (void)_setLsvpDict:(NSMutableDictionary *)d;
@end

@implementation DSStore

+ (id)storeWithPath:(NSString *)path {
    return [[[self alloc] initWithPath:path] autorelease];
}

+ (id)createStoreAtPath:(NSString *)path withEntries:(NSArray *)entries {
    DSStore *store = [[[self alloc] initWithPath:path] autorelease];
    if (!store) {
        return nil;
    }
    
    // Initialize with provided entries
    if (entries) {
        [store->_entries addObjectsFromArray:entries];
    }
    
    store->_isLoaded = YES;
    return store;
}

- (id)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _filePath = [path copy];
        _allocator = nil;
        _entries = [[NSMutableArray alloc] init];
        _isLoaded = NO;
    }
    return self;
}

- (void)dealloc {
    [_filePath release];
    [_allocator release];
    [_entries release];
    [super dealloc];
}

- (NSString *)filePath {
    return _filePath;
}

- (NSArray *)entries {
    if (!_isLoaded) {
        [self load];
    }
    return [NSArray arrayWithArray:_entries];
}

- (BOOL)load {
    // Initialize buddy allocator
    _allocator = [[DSBuddyAllocator alloc] initWithFile:_filePath];
    if (![_allocator open]) {
        return NO;
    }
    
    // Check file size
    NSUInteger fileSize = [_allocator fileSize];
    if (fileSize < 36) {
        return NO;
    }
    
    // Read buddy allocator header (first 32 bytes)
    DSBuddyBlock *headerBlock = [_allocator blockAtOffset:0 size:32];
    if (!headerBlock) {
        return NO;
    }
    
    // Check buddy allocator magic
    uint32_t magic1 = [headerBlock readUInt32];
    uint32_t magic2 = [headerBlock readUInt32];
    
    if (magic1 != 0x00000001 || magic2 != 0x42756431) { // "Bud1"
        [headerBlock close];
        return NO;
    }
    
    // Read offset and size of root block
    uint32_t rootOffset = [headerBlock readUInt32];
    uint32_t rootSize = [headerBlock readUInt32];
    uint32_t rootOffset2 __attribute__((unused)) = [headerBlock readUInt32]; // Duplicate
    
    [headerBlock close];
    
    // Validate offsets
    if (rootOffset >= fileSize || rootOffset + rootSize > fileSize) {
        return NO;
    }
    
    // Read root block (contains buddy allocator metadata)
    // NOTE: Reference library skips first 4 bytes of root block
    DSBuddyBlock *rootBlock = [_allocator blockAtOffset:rootOffset + 4 size:rootSize - 4];
    if (!rootBlock) {
        return NO;
    }
    
    // Read block offsets count and unknown value
    uint32_t offsetCount = [rootBlock readUInt32];
    uint32_t unknown2 __attribute__((unused)) = [rootBlock readUInt32];
    
    
    // Read offset table (always 256 entries, padded with zeros)
    NSMutableArray *offsets = [NSMutableArray arrayWithCapacity:offsetCount];
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t offset = [rootBlock readUInt32];
        if (i < offsetCount) {
            [offsets addObject:[NSNumber numberWithUnsignedInt:offset]];
        }
    }
    
    // Read TOC count
    uint32_t tocCount = [rootBlock readUInt32];
    
    // Parse ALL directory entries robustly (not just DSDB)
    NSMutableDictionary *directoryEntries = [NSMutableDictionary dictionaryWithCapacity:tocCount];
    for (uint32_t i = 0; i < tocCount; i++) {
        uint8_t nameLen = [rootBlock readUInt8];
        NSData *nameData = [rootBlock readBytes:nameLen];
        uint32_t blockNum = [rootBlock readUInt32];
        
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSASCIIStringEncoding];
        
        // Store ALL directory entries for future extensibility
        [directoryEntries setObject:[NSNumber numberWithUnsignedInt:blockNum] forKey:name];
        [name release];
    }
    
    [rootBlock close];
    
    // Look for DSDB directory entry (robust approach)
    NSNumber *dsdbBlockNumObj = [directoryEntries objectForKey:@"DSDB"];
    if (!dsdbBlockNumObj) {
        return NO;
    }
    
    uint32_t dsdbBlockNum = [dsdbBlockNumObj unsignedIntValue];
    if (dsdbBlockNum >= [offsets count]) {
        return NO;
    }
    
    // Get DSDB block address from offset table
    uint32_t dsdbAddr = [[offsets objectAtIndex:dsdbBlockNum] unsignedIntValue];
    uint32_t dsdbOffset = dsdbAddr & ~0x1F;  // Remove size bits
    uint32_t dsdbSize = 1 << (dsdbAddr & 0x1F);  // Extract size bits
    
    
    // Read DSDB superblock (NOTE: +4 for reference library file offset correction)
    DSBuddyBlock *dsdbBlock = [_allocator blockAtOffset:dsdbOffset + 4 size:dsdbSize];
    if (!dsdbBlock) {
        return NO;
    }
    
    // Read DSDB superblock header (5 uint32_t values).  The node count must
    // still be read (even though unused) because readUInt32 advances the
    // block's read position; skipping it would shift every later field.
    uint32_t rootAddress = [dsdbBlock readUInt32];
    uint32_t levelsNumber __attribute__((unused)) = [dsdbBlock readUInt32];
    uint32_t recordsNumber = [dsdbBlock readUInt32];
    uint32_t nodesNumber __attribute__((unused)) = [dsdbBlock readUInt32];
    uint32_t pageSize = [dsdbBlock readUInt32];
    
    
    [_entries removeAllObjects];
    
    if (recordsNumber == 0) {
        [dsdbBlock close];
        _isLoaded = YES;
        return YES;
    }
    
    [dsdbBlock close];
    
    // The B-tree root address points to another block in the offset table
    // If rootAddress >= offsetCount, it's likely an offset relative to DSDB block
    if (rootAddress < [offsets count]) {
        // Root address is a block number
        uint32_t btreeAddr = [[offsets objectAtIndex:rootAddress] unsignedIntValue];
        uint32_t btreeOffset = btreeAddr & ~0x1F;
        uint32_t btreeSize = 1 << (btreeAddr & 0x1F);
        
        
        // Read B-tree data (+4 for file offset correction)
        DSBuddyBlock *btreeBlock = [_allocator blockAtOffset:btreeOffset + 4 size:btreeSize - 4];
        if (!btreeBlock) {
            return NO;
        }
        
        @try {
            [self readBTreeNode:btreeBlock];
            _isLoaded = YES;
            [btreeBlock close];
            return YES;
        }
        @catch (NSException *exception) {
            [btreeBlock close];
            return NO;
        }
    } else {
        // Root address is relative to DSDB block
        // Seek to rootAddress within DSDB block data 
        NSUInteger btreeOffset = dsdbOffset + 4 + rootAddress;
        NSUInteger btreeSize = pageSize;  // Use pageSize from DSDB
        
        
        // Read B-tree data
        DSBuddyBlock *btreeBlock = [_allocator blockAtOffset:btreeOffset size:btreeSize - 4];
        if (!btreeBlock) {
            return NO;
        }
        
        @try {
            [self readBTreeNode:btreeBlock];
            _isLoaded = YES;
            [btreeBlock close];
            return YES;
        }
        @catch (NSException *exception) {
            [btreeBlock close];
            return NO;
        }
    }
}

/* Reads one record (filename + code + type + value) and advances the
 * block position.  Returns an autoreleased DSStoreEntry, or nil on a bad
 * record length. */
- (DSStoreEntry *)_readRecord:(DSBuddyBlock *)block
{
    uint32_t filenameLength = [block readUInt32];
    if (filenameLength == 0 || filenameLength > 1024) {
        return nil;
    }
    NSData *unicodeData = [block readBytes:filenameLength * 2];
    NSString *filename = [[[NSString alloc] initWithData:unicodeData
                                              encoding:NSUTF16BigEndianStringEncoding] autorelease];
    NSData *codeData = [block readBytes:4];
    NSString *code = [[[NSString alloc] initWithData:codeData
                                          encoding:NSASCIIStringEncoding] autorelease];
    NSData *typeData = [block readBytes:4];
    NSString *type = [[[NSString alloc] initWithData:typeData
                                          encoding:NSASCIIStringEncoding] autorelease];

    id value = nil;
    if ([type isEqualToString:@"bool"]) {
        uint8_t boolVal = [block readUInt8];
        value = [NSNumber numberWithBool:(boolVal != 0)];
    } else if ([type isEqualToString:@"long"]) {
        value = [NSNumber numberWithUnsignedInt:[block readUInt32]];
    } else if ([type isEqualToString:@"shor"]) {
        value = [NSNumber numberWithUnsignedShort:[block readUInt16]];
    } else if ([type isEqualToString:@"blob"]) {
        uint32_t blobLen = [block readUInt32];
        if (blobLen > 0 && blobLen < 65536) {
            value = [block readBytes:blobLen];
        }
    } else if ([type isEqualToString:@"ustr"]) {
        uint32_t strLen = [block readUInt32];
        if (strLen > 0 && strLen < 1024) {
            NSData *strData = [block readBytes:strLen * 2];
            value = [[[NSString alloc] initWithData:strData
                                           encoding:NSUTF16BigEndianStringEncoding] autorelease];
        }
    } else if ([type isEqualToString:@"type"]) {
        value = [[[NSString alloc] initWithData:[block readBytes:4]
                                       encoding:NSASCIIStringEncoding] autorelease];
    } else if ([type isEqualToString:@"comp"] || [type isEqualToString:@"dutc"]) {
        value = [NSNumber numberWithUnsignedLongLong:[block readUInt64]];
    } else {
        uint32_t valueLen = [block readUInt32];
        if (valueLen > 0 && valueLen < 65536) {
            value = [block readBytes:valueLen];
        }
    }

    return [[[DSStoreEntry alloc] initWithFilename:filename
                                             code:code
                                             type:type
                                            value:value] autorelease];
}

- (void)readBTreeNode:(DSBuddyBlock *)block
{
    uint32_t nextNode = [block readUInt32];
    uint32_t recordsCount = [block readUInt32];

    /* Mirror ds_store's _traverse exactly.  A node is internal iff its
     * nextNode word is non-zero; nextNode is the RIGHTMOST child (not a
     * sibling).  Internal nodes store, for each of `recordsCount' pivots, a
     * leading child block-number followed by the record; the rightmost child
     * is reached via nextNode.  Leaf nodes store only records.  Pivots are
     * real entries and are kept. */
    if (nextNode != 0) {
        for (uint32_t i = 0; i < recordsCount; i++) {
            uint32_t childNum = [block readUInt32];
            if (childNum != 0) {
                uint32_t childAddr = [_allocator addressForBlock:childNum];
                uint32_t childOffset = (childAddr & ~0x1FU) + 4;
                uint32_t childSize = (1U << (childAddr & 0x1FU)) - 4;
                DSBuddyBlock *childBlock = [_allocator blockAtOffset:childOffset
                                                              size:childSize];
                if (childBlock) {
                    [self readBTreeNode:childBlock];
                    [childBlock close];
                }
            }
            DSStoreEntry *pivot = [self _readRecord:block];
            if (pivot) {
                [_entries addObject:pivot];
            }
        }
        if (nextNode != 0) {
            uint32_t sibAddr = [_allocator addressForBlock:nextNode];
            uint32_t sibOffset = (sibAddr & ~0x1FU) + 4;
            uint32_t sibSize = (1U << (sibAddr & 0x1FU)) - 4;
            DSBuddyBlock *sibBlock = [_allocator blockAtOffset:sibOffset
                                                        size:sibSize];
            if (sibBlock) {
                [self readBTreeNode:sibBlock];
                [sibBlock close];
            }
        }
    } else {
        for (uint32_t i = 0; i < recordsCount; i++) {
            DSStoreEntry *entry = [self _readRecord:block];
            if (entry) {
                [_entries addObject:entry];
            }
        }
    }
}

- (BOOL)save
{
    if (!_isLoaded) {
        if (![self load]) {
            return NO;
        }
    }

    DSBuddyAllocator *alloc = [[DSBuddyAllocator alloc] initWithFile:_filePath];
    if (![alloc openForWriting]) {
        [alloc release];
        return NO;
    }

    const uint32_t pageSize = 4096;

    /* DSDB superblock (the B-tree's root pointer lives here). */
    int superblk = [alloc allocate:20];
    [alloc setTOCName:@"DSDB" blockNumber:superblk];

    NSArray *entries = [_entries sortedArrayUsingSelector:@selector(compare:)];

    int rootNode = 0;
    uint32_t levels = 0, records = 0, nodes = 0;

    if ([entries count] == 0) {
        int leaf = [alloc allocate:256];   /* empty leaf node */
        DSBuddyBlock *b = [alloc getBlock:leaf];
        [b writeUInt32:0];   /* next node (leaf) */
        [b writeUInt32:0];   /* record count */
        [b zeroFill];
        [b close];
        rootNode = leaf;
        /* Block 0 (reserved at 0x1000 in openForWriting) is the buddy root. */
        [alloc setRootBlockAddress:0x100b];
        levels = 0; records = 0; nodes = 1;
    } else {
        /* Build the B-tree from the sorted entries.  This is a faithful port
         * of the reference `ds_store' (al45tair) algorithm, which emits files
         * that macOS Finder reads unchanged. */
        NSMutableArray *currentLevel = [NSMutableArray arrayWithArray:entries];
        NSMutableArray *nextLevel = [NSMutableArray array];
        NSMutableArray *levelNodes = [NSMutableArray array];
        uint32_t ptrSize = 0;
        NSUInteger nodeCount = 0;

        while (YES) {
            uint32_t total = 8;
            NSMutableArray *nodesArr = [NSMutableArray array];
            NSMutableArray *node = [NSMutableArray array];
            for (DSStoreEntry *e in currentLevel) {
                uint32_t newTotal = total + ptrSize + (uint32_t)[e byteLength];
                if (newTotal > pageSize) {
                    [nodesArr addObject:node];
                    [nextLevel addObject:e];
                    total = 8;
                    node = [NSMutableArray array];
                } else {
                    total = newTotal;
                    [node addObject:e];
                }
            }
            if ([node count]) [nodesArr addObject:node];
            nodeCount += [nodesArr count];
            [levelNodes addObject:nodesArr];
            if ([nodesArr count] == 1) break;
            currentLevel = nextLevel;
            nextLevel = [NSMutableArray array];
            ptrSize = 4;
        }

        /* Allocate each B-tree node at its actual content size (rounded up
         * to a buddy block).  macOS writes nodes at their real size, not at a
         * fixed page_size, and Finder rejects files whose nodes are padded out
         * to 8 KiB blocks.  A minimum of 256 bytes matches macOS's smallest
         * node.  Internal nodes carry one extra 4-byte child pointer per
         * record, leaf nodes do not. */
        NSMutableArray *ptrs = [NSMutableArray arrayWithCapacity:nodeCount];
        for (NSUInteger li = 0; li < [levelNodes count]; li++) {
            NSArray *level = [levelNodes objectAtIndex:li];
            BOOL isLeaf = (li == 0);
            for (NSArray *node in level) {
                uint32_t nodeSize = 8;  /* next + count header */
                for (DSStoreEntry *e in node) {
                    nodeSize += (uint32_t)[e byteLength];
                    if (!isLeaf) nodeSize += 4;  /* child pointer per record */
                }
                if (nodeSize < 256) nodeSize = 256;
                [ptrs addObject:[NSNumber numberWithInt:[alloc allocate:nodeSize]]];
            }
        }

        NSMutableArray *pointers = [NSMutableArray array];
        NSArray *prevPointers = nil;
        for (NSArray *level in levelNodes) {
            NSUInteger ppndx = 0;
            NSUInteger idxInLevel = 0;
            /* Consume blocks FIFO: ptrs were allocated leaf-first (level 0
             * first), matching the order levels are written here, so the
             * leaves map to the blocks reserved for them. */
            NSMutableArray *lptrs = [NSMutableArray arrayWithArray:
                [ptrs subarrayWithRange:NSMakeRange(0, [level count])]];
            [ptrs removeObjectsInRange:NSMakeRange(0, [level count])];
            for (NSArray *node in level) {
                int ndx = [[lptrs objectAtIndex:idxInLevel] intValue];
                DSBuddyBlock *b = [alloc getBlock:ndx];
                if (prevPointers == nil) {
                    [b writeUInt32:0];
                    [b writeUInt32:(uint32_t)[node count]];
                    for (DSStoreEntry *e in node) {
                        [b writeBytes:[e encode]];
                    }
                } else {
                    /* Internal node: an internal node with `len(node)' pivot
                     * records references `len(node)+1' children.  The first
                     * `len(node)' children are the left children of each pivot
                     * (nodePtrs); the final, rightmost child is stored in the
                     * node's nextNode word.  This exactly mirrors ds_store's
                     * _save (next_node = prev_pointers[ppndx+len(node)]) and is
                     * what macOS Finder expects: a B-tree whose internal node
                     * carries count+1 children.  Child pointers and next_node
                     * are BLOCK NUMBERS (indices into the allocator's offset
                     * table), not addresses. */
                    int nextNodeSlot = (ppndx + [node count] < [prevPointers count]) ?
                        [[prevPointers objectAtIndex:(ppndx + [node count])] intValue] : 0;
                    NSArray *nodePtrs = [prevPointers subarrayWithRange:
                        NSMakeRange(ppndx, [node count])];
                    [b writeUInt32:(uint32_t)nextNodeSlot];
                    [b writeUInt32:(uint32_t)[node count]];
                    for (NSUInteger k = 0; k < [node count]; k++) {
                        DSStoreEntry *e = [node objectAtIndex:k];
                        uint32_t childNum = [[nodePtrs objectAtIndex:k] intValue];
                        [b writeUInt32:childNum];
                        [b writeBytes:[e encode]];
                    }
                }
                [b zeroFill];
                [b close];
                [pointers addObject:[NSNumber numberWithInt:ndx]];
                ppndx += [node count];
                idxInLevel++;
            }
            prevPointers = [NSArray arrayWithArray:pointers];
            [pointers removeAllObjects];
        }

        rootNode = [[prevPointers objectAtIndex:0] intValue];
        /* Block 0 (reserved at 0x1000 in openForWriting) is the buddy root. */
        [alloc setRootBlockAddress:0x100b];
        /* The DSDB superblock's `levels' field is the number of INTERNAL
         * levels, i.e. (tree depth - 1).  A leaf-only tree is depth 1 and
         * stores levels = 0, exactly as a real Mac .DS_Store does.  Finder
         * rejects the file if this is off by one. */
        levels = (int)[levelNodes count] - 1;
        records = [entries count];
        nodes = nodeCount;
    }

    DSBuddyBlock *s = [alloc getBlock:superblk];
    [s writeUInt32:(uint32_t)rootNode];
    [s writeUInt32:levels];
    [s writeUInt32:records];
    [s writeUInt32:nodes];
    [s writeUInt32:pageSize];
    [s zeroFill];
    [s close];

    [alloc flush];
    [alloc release];
    return YES;
}

- (DSStoreEntry *)entryForFilename:(NSString *)filename code:(NSString *)code {
    if (!_isLoaded) {
        [self load];
    }
    
    for (DSStoreEntry *entry in _entries) {
        if ([[entry filename] isEqualToString:filename] && 
            [[entry code] isEqualToString:code]) {
            return entry;
        }
    }
    return nil;
}

- (void)setEntry:(DSStoreEntry *)entry {
    if (!_isLoaded) {
        [self load];
    }
    
    // Remove existing entry with same filename and code
    DSStoreEntry *existing = [self entryForFilename:[entry filename] code:[entry code]];
    if (existing) {
        [_entries removeObject:existing];
    }
    
    [_entries addObject:entry];
    _dirty = YES;  // Mark as modified
}

- (void)removeEntryForFilename:(NSString *)filename code:(NSString *)code {
    if (!_isLoaded) {
        [self load];
    }
    
    DSStoreEntry *entry = [self entryForFilename:filename code:code];
    if (entry) {
        [_entries removeObject:entry];
        _dirty = YES;  // Mark as modified
    }
}

// CRUD methods for all DS_Store field types

- (NSDictionary *)backgroundPictureForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"bwsp"];
    if (!entry) {
        entry = [self entryForFilename:@"." code:@"pBBk"];
    }
    
    if (entry && ([[entry code] isEqualToString:@"bwsp"] || [[entry code] isEqualToString:@"pBBk"])) {
        return (NSDictionary *)[entry value];
    }
    return nil;
}

- (void)setBackgroundPicture:(NSDictionary *)pictureInfo {
    DSStoreEntry *entry = [[DSStoreEntry alloc] initWithFilename:@"." 
                                                            code:@"bwsp" 
                                                            type:@"blob"
                                                           value:pictureInfo];
    [self setEntry:entry];
    [entry release];
}

- (NSDictionary *)listViewSettingsForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"lsvp"];
    if (!entry) {
        entry = [self entryForFilename:@"." code:@"lsvP"];
    }
    
    if (entry && ([[entry code] isEqualToString:@"lsvp"] || [[entry code] isEqualToString:@"lsvP"])) {
        // The value should be a blob containing plist data - just return the raw value for now
        return (NSDictionary *)[entry value];
    }
    return nil;
}

- (void)setListViewSettings:(NSDictionary *)settings {
    DSStoreEntry *entry = [DSStoreEntry plistEntryForFile:@"." code:@"lsvp" dictionary:settings];
    if (entry) [self setEntry:entry];
}

// CRUD methods for all DS_Store field types

- (NSPoint)iconLocationForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"Iloc"];
    if (entry) {
        return [entry iconLocation];
    }
    return NSMakePoint(0, 0);
}

- (void)setIconLocationForFilename:(NSString *)filename x:(int)x y:(int)y {
    DSStoreEntry *entry = [DSStoreEntry iconLocationEntryForFile:filename x:x y:y];
    [self setEntry:entry];
}

- (SimpleColor *)backgroundColorForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"BKGD"];
    if (entry) {
        return [entry backgroundColor];
    }
    return nil;
}

- (void)setBackgroundColorForDirectory:(SimpleColor *)color {
    float red, green, blue, alpha;
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    
    int redInt = (int)(red * 65535);
    int greenInt = (int)(green * 65535);
    int blueInt = (int)(blue * 65535);
    
    DSStoreEntry *entry = [DSStoreEntry backgroundColorEntryForFile:@"." red:redInt green:greenInt blue:blueInt];
    [self setEntry:entry];
}

- (NSString *)backgroundImagePathForDirectory {
    // Check for pict entry with ustr type (our simplified format)
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"pict"];
    if (entry && [[entry type] isEqualToString:@"ustr"]) {
        return (NSString *)[entry value];
    }
    
    // Check for pict entry with blob type (alias record - native format)
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        // For .DS_Store files with alias records, try to extract path
        // This is a simplified extraction - real alias parsing is complex
        return [entry backgroundImagePath];
    }
    
    return nil;
}

- (void)setBackgroundImagePathForDirectory:(NSString *)imagePath {
    // Set BKGD entry to indicate picture background
    DSStoreEntry *bkgdEntry = [DSStoreEntry backgroundImageEntryForFile:@"." imagePath:imagePath];
    [self setEntry:bkgdEntry];
    
    // Store the actual path in a "pict" entry as ustr for simplicity
    // (For full interoperability, native systems use alias records which are more complex)
    DSStoreEntry *pictEntry = [[[DSStoreEntry alloc] initWithFilename:@"." 
                                                                 code:@"pict" 
                                                                 type:@"ustr" 
                                                                value:imagePath] autorelease];
    [self setEntry:pictEntry];
}

- (NSString *)viewStyleForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"vstl"];
    if (entry) {
        return [entry viewStyle];
    }
    return nil;
}

- (void)setViewStyleForDirectory:(NSString *)style {
    DSStoreEntry *entry = [DSStoreEntry viewStyleEntryForFile:@"." style:style];
    [self setEntry:entry];
}

- (int)iconSizeForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"icvo"];
    if (entry) {
        return [entry iconSize];
    }
    return 0;
}

- (void)setIconSizeForDirectory:(int)size {
    DSStoreEntry *entry = [DSStoreEntry iconSizeEntryForFile:@"." size:size];
    [self setEntry:entry];
}

// Icon view options

- (int)gridSpacingForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"icsp"];
    if (entry) {
        return [entry gridSpacing];
    }
    return 0;
}

- (void)setGridSpacingForDirectory:(int)spacing {
    DSStoreEntry *entry = [DSStoreEntry gridSpacingEntryForFile:@"." spacing:spacing];
    [self setEntry:entry];
}

- (int)textSizeForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"lsvt"];
    if (entry) {
        return [entry textSize];
    }
    return 0;
}

- (void)setTextSizeForDirectory:(int)size {
    DSStoreEntry *entry = [DSStoreEntry textSizeEntryForFile:@"." size:size];
    [self setEntry:entry];
}

- (DSStoreLabelPosition)labelPositionForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"lblp"];
    if (entry) {
        return (DSStoreLabelPosition)[entry labelPosition];
    }
    return DSStoreLabelPositionBottom;
}

- (void)setLabelPositionForDirectory:(DSStoreLabelPosition)position {
    DSStoreEntry *entry = [DSStoreEntry labelPositionEntryForFile:@"." position:(int)position];
    [self setEntry:entry];
}

- (BOOL)showItemInfoForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"info"];
    if (entry) {
        return [entry showItemInfo];
    }
    return NO;
}

- (void)setShowItemInfoForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showItemInfoEntryForFile:@"." show:show];
    [self setEntry:entry];
}

- (BOOL)showIconPreviewForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"prvw"];
    if (entry) {
        return [entry showIconPreview];
    }
    return NO;
}

- (void)setShowIconPreviewForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showIconPreviewEntryForFile:@"." show:show];
    [self setEntry:entry];
}

- (DSStoreIconArrangement)iconArrangementForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"iarr"];
    if (entry) {
        return (DSStoreIconArrangement)[entry iconArrangement];
    }
    return DSStoreIconArrangementNone;
}

- (void)setIconArrangementForDirectory:(DSStoreIconArrangement)arrangement {
    DSStoreEntry *entry = [DSStoreEntry iconArrangementEntryForFile:@"." arrangement:(int)arrangement];
    [self setEntry:entry];
}

// Sort options

- (NSString *)sortByForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"GRP0"];
    if (entry) {
        return [entry sortBy];
    }
    return nil;
}

- (void)setSortByForDirectory:(NSString *)sortBy {
    DSStoreEntry *entry = [DSStoreEntry sortByEntryForFile:@"." sortBy:sortBy];
    [self setEntry:entry];
}

// Window chrome

- (int)sidebarWidthForDirectory {
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"fwsw"];
    if (entry) {
        return [entry sidebarWidth];
    }
    return 0;
}

- (void)setSidebarWidthForDirectory:(int)width {
    DSStoreEntry *entry = [DSStoreEntry sidebarWidthEntryForFile:@"." width:width];
    [self setEntry:entry];
}

- (BOOL)showToolbarForDirectory {
    return [self booleanValueForFilename:@"." code:@"stbr"];
}

- (void)setShowToolbarForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showToolbarEntryForFile:@"." show:show];
    [self setEntry:entry];
}

- (BOOL)showSidebarForDirectory {
    return [self booleanValueForFilename:@"." code:@"ssbr"];
}

- (void)setShowSidebarForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showSidebarEntryForFile:@"." show:show];
    [self setEntry:entry];
}

- (BOOL)showPathBarForDirectory {
    return [self booleanValueForFilename:@"." code:@"pbar"];
}

- (void)setShowPathBarForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showPathBarEntryForFile:@"." show:show];
    [self setEntry:entry];
}

- (BOOL)showStatusBarForDirectory {
    return [self booleanValueForFilename:@"." code:@"sbar"];
}

- (void)setShowStatusBarForDirectory:(BOOL)show {
    DSStoreEntry *entry = [DSStoreEntry showStatusBarEntryForFile:@"." show:show];
    [self setEntry:entry];
}

// File label colors

- (DSStoreLabelColor)labelColorForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"lclr"];
    if (entry) {
        return (DSStoreLabelColor)[entry labelColor];
    }
    return DSStoreLabelColorNone;
}

- (void)setLabelColorForFilename:(NSString *)filename color:(DSStoreLabelColor)color {
    DSStoreEntry *entry = [DSStoreEntry labelColorEntryForFile:filename color:(int)color];
    [self setEntry:entry];
}

// Column view configuration (spatial/icon view only)

- (BOOL)showRelativeDatesForDirectory {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return NO;
    }
    
    DSStoreEntry *entry = [self entryForFilename:@"." code:@"cvlc"];
    if (entry) {
        // clvs is typically stored in a blob; for now return a simple boolean
        // Real implementation would parse the blob
        return YES;
    }
    return NO;
}

- (void)setShowRelativeDatesForDirectory:(BOOL)show {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return;
    }
    if (show) {
        [self setEntry:[DSStoreEntry booleanEntryForFile:@"." code:@"cvlc" value:YES]];
    } else {
        [self removeEntryForFilename:@"." code:@"cvlc"];
    }
}

- (NSMutableDictionary *)_lsvpDict {
    DSStoreEntry *e = [self entryForFilename:@"." code:@"lsvp"];
    if (e && [[e value] isKindOfClass:[NSData class]]) {
        NSDictionary *d = [NSPropertyListSerialization propertyListWithData:(NSData *)[e value]
                                                                     options:NSPropertyListImmutable
                                                                      format:NULL
                                                                       error:NULL];
        if ([d isKindOfClass:[NSDictionary class]]) {
            return [d mutableCopy];
        }
    }
    return [NSMutableDictionary dictionary];
}

- (void)_setLsvpDict:(NSMutableDictionary *)d {
    DSStoreEntry *e = [DSStoreEntry plistEntryForFile:@"." code:@"lsvp" dictionary:d];
    if (e) [self setEntry:e];
}

- (int)columnWidthForDirectory:(NSString *)columnName {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return 0;
    }
    NSDictionary *d = [self _lsvpDict];
    for (NSDictionary *c in [d objectForKey:@"columns"]) {
        if ([[c objectForKey:@"identifier"] isEqual:columnName]) {
            return [[c objectForKey:@"width"] intValue];
        }
    }
    return 0;
}

- (void)setColumnWidthForDirectory:(NSString *)columnName width:(int)width {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return;
    }
    NSMutableDictionary *d = [self _lsvpDict];
    NSMutableArray *cols = [[d objectForKey:@"columns"] mutableCopy];
    if (cols == nil) cols = [NSMutableArray array];
    BOOL found = NO;
    for (NSMutableDictionary *c in cols) {
        if ([[c objectForKey:@"identifier"] isEqual:columnName]) {
            [c setObject:[NSNumber numberWithInt:width] forKey:@"width"];
            found = YES;
            break;
        }
    }
    if (!found) {
        NSMutableDictionary *c = [NSMutableDictionary dictionary];
        [c setObject:columnName forKey:@"identifier"];
        [c setObject:[NSNumber numberWithInt:width] forKey:@"width"];
        [c setObject:[NSNumber numberWithBool:YES] forKey:@"visible"];
        [cols addObject:c];
    }
    [d setObject:cols forKey:@"columns"];
    [self _setLsvpDict:d];
}

- (BOOL)columnVisibleForDirectory:(NSString *)columnName {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return NO;
    }
    NSDictionary *d = [self _lsvpDict];
    for (NSDictionary *c in [d objectForKey:@"columns"]) {
        if ([[c objectForKey:@"identifier"] isEqual:columnName]) {
            return [[c objectForKey:@"visible"] boolValue];
        }
    }
    return YES;
}

- (void)setColumnVisibleForDirectory:(NSString *)columnName visible:(BOOL)visible {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return;
    }
    NSMutableDictionary *d = [self _lsvpDict];
    NSMutableArray *cols = [[d objectForKey:@"columns"] mutableCopy];
    if (cols == nil) cols = [NSMutableArray array];
    BOOL found = NO;
    for (NSMutableDictionary *c in cols) {
        if ([[c objectForKey:@"identifier"] isEqual:columnName]) {
            [c setObject:[NSNumber numberWithBool:visible] forKey:@"visible"];
            found = YES;
            break;
        }
    }
    if (!found) {
        NSMutableDictionary *c = [NSMutableDictionary dictionary];
        [c setObject:columnName forKey:@"identifier"];
        [c setObject:[NSNumber numberWithBool:visible] forKey:@"visible"];
        [cols addObject:c];
    }
    [d setObject:cols forKey:@"columns"];
    [self _setLsvpDict:d];
}

- (NSArray *)visibleColumnsForDirectory {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return nil;
    }
    NSDictionary *d = [self _lsvpDict];
    NSMutableArray *visible = [NSMutableArray array];
    for (NSDictionary *c in [d objectForKey:@"columns"]) {
        if ([[c objectForKey:@"visible"] boolValue]) {
            [visible addObject:[c objectForKey:@"identifier"]];
        }
    }
    return visible;
}

- (void)setVisibleColumnsForDirectory:(NSArray *)columns {
    // Check if in spatial mode first
    NSString *style = [self viewStyleForDirectory];
    if (style && ![style isEqual:@"icnv"]) {
        return;
    }
    NSMutableDictionary *d = [self _lsvpDict];
    NSMutableArray *cols = [NSMutableArray array];
    for (NSString *name in columns) {
        NSMutableDictionary *c = [NSMutableDictionary dictionary];
        [c setObject:name forKey:@"identifier"];
        [c setObject:[NSNumber numberWithBool:YES] forKey:@"visible"];
        [cols addObject:c];
    }
    [d setObject:cols forKey:@"columns"];
    [self _setLsvpDict:d];
}

- (NSString *)commentsForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"cmmt"];
    if (entry) {
        return [entry comments];
    }
    return nil;
}

- (void)setCommentsForFilename:(NSString *)filename comments:(NSString *)comments {
    DSStoreEntry *entry = [DSStoreEntry commentsEntryForFile:filename comments:comments];
    [self setEntry:entry];
}

- (long long)logicalSizeForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"lg1S"];
    if (!entry) {
        entry = [self entryForFilename:filename code:@"logS"]; // Fallback to legacy
    }
    if (entry) {
        return [entry logicalSize];
    }
    return 0;
}

- (void)setLogicalSizeForFilename:(NSString *)filename size:(long long)size {
    DSStoreEntry *entry = [DSStoreEntry logicalSizeEntryForFile:filename size:size];
    [self setEntry:entry];
}

- (long long)physicalSizeForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"ph1S"];
    if (!entry) {
        entry = [self entryForFilename:filename code:@"phyS"]; // Fallback to legacy
    }
    if (entry) {
        return [entry physicalSize];
    }
    return 0;
}

- (void)setPhysicalSizeForFilename:(NSString *)filename size:(long long)size {
    DSStoreEntry *entry = [DSStoreEntry physicalSizeEntryForFile:filename size:size];
    [self setEntry:entry];
}

- (NSDate *)modificationDateForFilename:(NSString *)filename {
    DSStoreEntry *entry = [self entryForFilename:filename code:@"modD"];
    if (!entry) {
        entry = [self entryForFilename:filename code:@"moDD"]; // Alternative
    }
    if (entry) {
        return [entry modificationDate];
    }
    return nil;
}

- (void)setModificationDateForFilename:(NSString *)filename date:(NSDate *)date {
    DSStoreEntry *entry = [DSStoreEntry modificationDateEntryForFile:filename date:date];
    [self setEntry:entry];
}

- (BOOL)booleanValueForFilename:(NSString *)filename code:(NSString *)code {
    DSStoreEntry *entry = [self entryForFilename:filename code:code];
    if (entry) {
        return [entry booleanValue];
    }
    return NO;
}

- (void)setBooleanValueForFilename:(NSString *)filename code:(NSString *)code value:(BOOL)value {
    DSStoreEntry *entry = [DSStoreEntry booleanEntryForFile:filename code:code value:value];
    [self setEntry:entry];
}

- (int32_t)longValueForFilename:(NSString *)filename code:(NSString *)code {
    DSStoreEntry *entry = [self entryForFilename:filename code:code];
    if (entry) {
        return [entry longValue];
    }
    return 0;
}

- (void)setLongValueForFilename:(NSString *)filename code:(NSString *)code value:(int32_t)value {
    DSStoreEntry *entry = [DSStoreEntry longEntryForFile:filename code:code value:value];
    [self setEntry:entry];
}

// Directory entry management methods

- (BOOL)saveChanges {
    if (!_dirty) {
        return YES; // No changes to save
    }
    
    @try {
        // Save changes back to file
        if (![self save]) {
            return NO;
        }
        _dirty = NO;
        return YES;
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)removeAllEntriesForFilename:(NSString *)filename {
    NSMutableArray *toRemove = [NSMutableArray array];
    
    for (DSStoreEntry *entry in _entries) {
        if ([[entry filename] isEqualToString:filename]) {
            [toRemove addObject:entry];
        }
    }
    
    for (DSStoreEntry *entry in toRemove) {
        [_entries removeObject:entry];
        _dirty = YES;
    }
}

- (void)removeEntriesForFilename:(NSString *)filename codes:(NSSet *)codes {
    NSMutableArray *toRemove = [NSMutableArray array];
    
    for (DSStoreEntry *entry in _entries) {
        if ([[entry filename] isEqualToString:filename]
            && [codes containsObject: [entry code]]) {
            [toRemove addObject:entry];
        }
    }
    
    for (DSStoreEntry *entry in toRemove) {
        [_entries removeObject:entry];
        _dirty = YES;
    }
}

- (NSArray *)allFilenames {
    NSMutableSet *filenames = [NSMutableSet set];
    
    for (DSStoreEntry *entry in _entries) {
        [filenames addObject:[entry filename]];
    }
    
    return [filenames allObjects];
}

- (NSArray *)allCodesForFilename:(NSString *)filename {
    NSMutableArray *codes = [NSMutableArray array];
    
    for (DSStoreEntry *entry in _entries) {
        if ([[entry filename] isEqualToString:filename]) {
            [codes addObject:[entry code]];
        }
    }
    
    return codes;
}

#pragma mark - Coordinate Conversion for .DS_Store Interoperability

+ (NSPoint)gnustepPointFromDSStorePoint:(NSPoint)dsPoint viewHeight:(CGFloat)viewHeight iconHeight:(CGFloat)iconHeight {
    // .DS_Store format: origin top-left, y increases downward (coordinates = icon center)
    // GNUstep format: origin bottom-left, y increases upward
    // dsPoint is center of icon, convert by flipping Y coordinate
    // The iconHeight parameter is provided for API compatibility but icon centers
    // don't need iconHeight adjustment - just coordinate system flip
    CGFloat gnustepY = viewHeight - dsPoint.y;
    return NSMakePoint(dsPoint.x, gnustepY);
}

+ (NSPoint)dsStorePointFromGNUstepPoint:(NSPoint)gnustepPoint viewHeight:(CGFloat)viewHeight iconHeight:(CGFloat)iconHeight {
    // Reverse conversion for .DS_Store interoperability
    // Convert GNUstep coordinates (icon center, bottom-origin) to .DS_Store center-based coordinates (top-origin)
    // The iconHeight parameter is provided for API compatibility but icon centers
    // don't need iconHeight adjustment - just coordinate system flip
    CGFloat dsY = viewHeight - gnustepPoint.y;
    return NSMakePoint(gnustepPoint.x, dsY);
}

@end
