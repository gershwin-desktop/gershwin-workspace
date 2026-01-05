/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "SimpleColor.h"
#import "DSBuddyAllocator.h"
#import "DSStoreEntry.h"
#import "DSStoreCodecs.h"

#ifdef __cplusplus
extern "C" {
#endif

// Global verbose flag for debug output
extern BOOL gDSStoreVerbose;

/**
 * DSStore - .DS_Store file interoperability library
 *
 * This library provides read/write access to .DS_Store files for
 * GNUstep/Workspace .DS_Store interoperability.
 *
 * Coordinate System Notes:
 *   .DS_Store format: origin top-left, y increases downward
 *   GNUstep format: origin bottom-left, y increases upward
 *
 * Use the coordinate conversion methods to translate between systems.
 */

// View style enums matching .DS_Store vstl field values
typedef NS_ENUM(NSInteger, DSStoreViewStyle) {
    DSStoreViewStyleIcon = 0,       // icnv
    DSStoreViewStyleList = 1,       // Nlsv
    DSStoreViewStyleColumn = 2,     // clmv
    DSStoreViewStyleGallery = 3,    // glyv
    DSStoreViewStyleCoverflow = 4   // Flwv
};

// Background type from BKGD field
typedef NS_ENUM(NSInteger, DSStoreBackgroundType) {
    DSStoreBackgroundDefault = 0,   // DefB
    DSStoreBackgroundColor = 1,     // ClrB
    DSStoreBackgroundPicture = 2    // PctB
};

// Icon arrangement from icvo/icvp
typedef NS_ENUM(NSInteger, DSStoreIconArrangement) {
    DSStoreIconArrangementNone = 0,
    DSStoreIconArrangementGrid = 1
};

// Label position from icvo/icvp
typedef NS_ENUM(NSInteger, DSStoreLabelPosition) {
    DSStoreLabelPositionBottom = 0,  // botm
    DSStoreLabelPositionRight = 1    // rght
};

// Label color indices (0-7)
typedef NS_ENUM(NSInteger, DSStoreLabelColor) {
    DSStoreLabelColorNone = 0,
    DSStoreLabelColorRed = 1,
    DSStoreLabelColorOrange = 2,
    DSStoreLabelColorYellow = 3,
    DSStoreLabelColorGreen = 4,
    DSStoreLabelColorBlue = 5,
    DSStoreLabelColorPurple = 6,
    DSStoreLabelColorGrey = 7
};

// Sort by options
typedef NS_ENUM(NSInteger, DSStoreSortBy) {
    DSStoreSortByNone = 0,
    DSStoreSortByName = 1,
    DSStoreSortByDateModified = 2,
    DSStoreSortByDateCreated = 3,
    DSStoreSortBySize = 4,
    DSStoreSortByKind = 5,
    DSStoreSortByLabel = 6,
    DSStoreSortByDateAdded = 7
};

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus
extern "C" {
#endif

@interface DSStore : NSObject
{
    NSString *_filePath;
    DSBuddyAllocator *_allocator;
    NSMutableArray *_entries;
    BOOL _isLoaded;
    BOOL _dirty;
    
    // B-tree structure fields
    uint32_t _rootNode;
    uint32_t _levels;
    uint32_t _records;
    uint32_t _nodes;
    uint32_t _pageSize;
}

// Factory methods
+ (id)storeWithPath:(NSString *)path;
+ (id)createStoreAtPath:(NSString *)path withEntries:(NSArray *)entries;

// Initialization
- (id)initWithPath:(NSString *)path;

// Properties
- (NSString *)filePath;
- (NSArray *)entries;

// File operations
- (BOOL)load;
- (BOOL)save;

// Entry access
- (DSStoreEntry *)entryForFilename:(NSString *)filename code:(NSString *)code;
- (void)setEntry:(DSStoreEntry *)entry;
- (void)removeEntryForFilename:(NSString *)filename code:(NSString *)code;
- (void)removeAllEntriesForFilename:(NSString *)filename;
- (NSArray *)allFilenames;
- (NSArray *)allCodesForFilename:(NSString *)filename;

// Icon position - raw .DS_Store coordinates (top-left origin)
- (NSPoint)iconLocationForFilename:(NSString *)filename;
- (void)setIconLocationForFilename:(NSString *)filename x:(int)x y:(int)y;

// Background
- (SimpleColor *)backgroundColorForDirectory;
- (void)setBackgroundColorForDirectory:(SimpleColor *)color;
- (NSString *)backgroundImagePathForDirectory;
- (void)setBackgroundImagePathForDirectory:(NSString *)imagePath;

// View settings
- (NSString *)viewStyleForDirectory;
- (void)setViewStyleForDirectory:(NSString *)style;
- (int)iconSizeForDirectory;
- (void)setIconSizeForDirectory:(int)size;

// Icon view options
- (int)gridSpacingForDirectory;
- (void)setGridSpacingForDirectory:(int)spacing;
- (int)textSizeForDirectory;
- (void)setTextSizeForDirectory:(int)size;
- (DSStoreLabelPosition)labelPositionForDirectory;
- (void)setLabelPositionForDirectory:(DSStoreLabelPosition)position;
- (BOOL)showItemInfoForDirectory;
- (void)setShowItemInfoForDirectory:(BOOL)show;
- (BOOL)showIconPreviewForDirectory;
- (void)setShowIconPreviewForDirectory:(BOOL)show;
- (DSStoreIconArrangement)iconArrangementForDirectory;
- (void)setIconArrangementForDirectory:(DSStoreIconArrangement)arrangement;

// Sort options
- (NSString *)sortByForDirectory;
- (void)setSortByForDirectory:(NSString *)sortBy;

// Window chrome
- (int)sidebarWidthForDirectory;
- (void)setSidebarWidthForDirectory:(int)width;
- (BOOL)showToolbarForDirectory;
- (void)setShowToolbarForDirectory:(BOOL)show;
- (BOOL)showSidebarForDirectory;
- (void)setShowSidebarForDirectory:(BOOL)show;
- (BOOL)showPathBarForDirectory;
- (void)setShowPathBarForDirectory:(BOOL)show;
- (BOOL)showStatusBarForDirectory;
- (void)setShowStatusBarForDirectory:(BOOL)show;

// File label colors
- (DSStoreLabelColor)labelColorForFilename:(NSString *)filename;
- (void)setLabelColorForFilename:(NSString *)filename color:(DSStoreLabelColor)color;

// Column view configuration
- (BOOL)showRelativeDatesForDirectory;
- (void)setShowRelativeDatesForDirectory:(BOOL)show;
- (int)columnWidthForDirectory:(NSString *)columnName;
- (void)setColumnWidthForDirectory:(NSString *)columnName width:(int)width;
- (BOOL)columnVisibleForDirectory:(NSString *)columnName;
- (void)setColumnVisibleForDirectory:(NSString *)columnName visible:(BOOL)visible;
- (NSArray *)visibleColumnsForDirectory;
- (void)setVisibleColumnsForDirectory:(NSArray *)columns;

// File metadata
- (NSString *)commentsForFilename:(NSString *)filename;
- (void)setCommentsForFilename:(NSString *)filename comments:(NSString *)comments;
- (long long)logicalSizeForFilename:(NSString *)filename;
- (void)setLogicalSizeForFilename:(NSString *)filename size:(long long)size;
- (long long)physicalSizeForFilename:(NSString *)filename;
- (void)setPhysicalSizeForFilename:(NSString *)filename size:(long long)size;
- (NSDate *)modificationDateForFilename:(NSString *)filename;
- (void)setModificationDateForFilename:(NSString *)filename date:(NSDate *)date;

// Generic field access
- (BOOL)booleanValueForFilename:(NSString *)filename code:(NSString *)code;
- (void)setBooleanValueForFilename:(NSString *)filename code:(NSString *)code value:(BOOL)value;
- (int32_t)longValueForFilename:(NSString *)filename code:(NSString *)code;
- (void)setLongValueForFilename:(NSString *)filename code:(NSString *)code value:(int32_t)value;

// Coordinate conversion for .DS_Store interoperability
// viewHeight: the height of the containing view in pixels (REQUIRED)
// iconHeight: the height of the icon in pixels (REQUIRED)
+ (NSPoint)gnustepPointFromDSStorePoint:(NSPoint)dsPoint
                             viewHeight:(CGFloat)viewHeight
                             iconHeight:(CGFloat)iconHeight;
+ (NSPoint)dsStorePointFromGNUstepPoint:(NSPoint)gnustepPoint
                             viewHeight:(CGFloat)viewHeight
                             iconHeight:(CGFloat)iconHeight;

// Internal methods
- (void)readBTreeNode:(DSBuddyBlock *)block address:(uint32_t)address isLeaf:(BOOL)isLeaf;

@end

#ifdef __cplusplus
}
#endif
