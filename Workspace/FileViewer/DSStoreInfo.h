/* DSStoreInfo.h
 *  
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "../DSStore/DSStore.h"

/**
 * DSStoreIconInfo - Icon-specific information from DS_Store
 */
@interface DSStoreIconInfo : NSObject <NSCopying>
{
    NSString *_filename;
    NSPoint _position;      // Iloc - icon position (.DS_Store coordinates, origin top-left)
    BOOL _hasPosition;
    NSString *_comments;    // cmmt - Spotlight comments
    DSStoreLabelColor _labelColor;  // lclr - Label color (0-7)
    BOOL _hasLabelColor;
}

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, assign) NSPoint position;
@property (nonatomic, assign) BOOL hasPosition;
@property (nonatomic, copy) NSString *comments;
@property (nonatomic, assign) DSStoreLabelColor labelColor;
@property (nonatomic, assign) BOOL hasLabelColor;

+ (instancetype)infoForFilename:(NSString *)filename;
- (NSPoint)gnustepPositionForViewHeight:(CGFloat)viewHeight iconHeight:(CGFloat)iconHeight;
+ (NSColor *)colorForLabelColor:(DSStoreLabelColor)labelColor;

@end

/**
 * DSStoreInfo - Complete DS_Store information for a directory
 *
 * This class reads and holds all available DS_Store metadata:
 * - Window geometry (fwi0)
 * - View style (vstl)
 * - Icon size (icvo/icvp)
 * - Icon arrangement (icvo/icvp)
 * - Label position (icvo/icvp)
 * - Background settings (BKGD/bwsp)
 * - Per-file icon positions (Iloc)
 * - Sidebar width (fwsw)
 */
@interface DSStoreInfo : NSObject
{
    NSString *_directoryPath;
    BOOL _loaded;
    
    // Window geometry (fwi0)
    NSRect _windowFrame;
    BOOL _hasWindowFrame;
    
    // View settings
    DSStoreViewStyle _viewStyle;
    BOOL _hasViewStyle;
    
    // Icon view settings (icvo/icvp)
    int _iconSize;
    BOOL _hasIconSize;
    DSStoreIconArrangement _iconArrangement;
    BOOL _hasIconArrangement;
    DSStoreLabelPosition _labelPosition;
    BOOL _hasLabelPosition;
    CGFloat _gridSpacing;
    BOOL _hasGridSpacing;
    
    // Background (BKGD/bwsp)
    DSStoreBackgroundType _backgroundType;
    NSColor *_backgroundColor;
    NSString *_backgroundImagePath;
    
    // Sidebar (fwsw)
    int _sidebarWidth;
    BOOL _hasSidebarWidth;
    
    // List view settings (lsvp/lsvP)
    int _listTextSize;
    BOOL _hasListTextSize;
    int _listIconSize;
    BOOL _hasListIconSize;
    NSString *_sortColumn;
    BOOL _hasSortColumn;
    BOOL _sortAscending;
    NSDictionary *_columnWidths;  // column name -> width
    NSDictionary *_columnVisible;  // column name -> BOOL
    
    // Icon positions (Iloc)
    NSMutableDictionary *_iconInfoDict;  // filename -> DSStoreIconInfo
}

// Directory info
@property (nonatomic, copy, readonly) NSString *directoryPath;
@property (nonatomic, assign, readonly) BOOL loaded;

// Window geometry
@property (nonatomic, assign) NSRect windowFrame;
@property (nonatomic, assign) BOOL hasWindowFrame;

// View style
@property (nonatomic, assign) DSStoreViewStyle viewStyle;
@property (nonatomic, assign) BOOL hasViewStyle;

// Icon view settings
@property (nonatomic, assign) int iconSize;
@property (nonatomic, assign) BOOL hasIconSize;
@property (nonatomic, assign) DSStoreIconArrangement iconArrangement;
@property (nonatomic, assign) BOOL hasIconArrangement;
@property (nonatomic, assign) DSStoreLabelPosition labelPosition;
@property (nonatomic, assign) BOOL hasLabelPosition;
@property (nonatomic, assign) CGFloat gridSpacing;
@property (nonatomic, assign) BOOL hasGridSpacing;

// Background
@property (nonatomic, assign) DSStoreBackgroundType backgroundType;
@property (nonatomic, retain) NSColor *backgroundColor;
@property (nonatomic, copy) NSString *backgroundImagePath;

// Sidebar
@property (nonatomic, assign) int sidebarWidth;
@property (nonatomic, assign) BOOL hasSidebarWidth;

// List view settings
@property (nonatomic, assign) int listTextSize;
@property (nonatomic, assign) BOOL hasListTextSize;
@property (nonatomic, assign) int listIconSize;
@property (nonatomic, assign) BOOL hasListIconSize;
@property (nonatomic, copy) NSString *sortColumn;
@property (nonatomic, assign) BOOL hasSortColumn;
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, retain) NSDictionary *columnWidths;
@property (nonatomic, retain) NSDictionary *columnVisible;

// Factory methods
+ (instancetype)infoForDirectoryPath:(NSString *)path;
+ (instancetype)infoForDirectoryPath:(NSString *)path loadImmediately:(BOOL)load;

// Initialization
- (instancetype)initWithDirectoryPath:(NSString *)path;

// Loading
- (BOOL)load;
- (BOOL)reload;

/**
 * Mark this instance as loaded after manual population.
 * Used by GWVolumeCache which populates properties directly
 * without going through the per-folder .DS_Store load path.
 */
- (void)markAsLoaded;

// === Writing ===

/**
 * Save all current settings to the per-folder .DS_Store file
 * at directoryPath/.DS_Store.
 * Writes atomically (temp file + rename).
 * Returns YES on success.
 */
- (BOOL)save;

/**
 * Save all current settings to a specific .DS_Store file path.
 * Useful for writing to the per-volume cache.
 */
- (BOOL)saveToPath:(NSString *)dsStorePath;

/**
 * Populate receiver's properties from a GNUstep viewerPrefs dictionary
 * (as produced by nodeView's updateNodeInfo: and the spatial viewer's
 * updateDefaults).  Keys recognised:
 *   @"geometry" — frame string
 *   @"viewtype" — @"Icon", @"List", @"Browser"
 *   @"iconsize" — NSNumber int
 *   @"iconspos" — NSString (e.g. @"bottom", @"right")
 *   @"iconsarr" — NSString (e.g. @"none", @"grid")
 */
- (void)takeValuesFromViewerPrefs:(NSDictionary *)prefs;

/* Like -takeValuesFromViewerPrefs: but, when preserve is YES, leaves any field
 * whose corresponding has* flag is already set untouched.  Used by migration so
 * a stale source (e.g. a legacy .gwdir) only fills gaps and never clobbers newer
 * values already present in the .DS_Store. */
- (void)takeValuesFromViewerPrefs:(NSDictionary *)prefs
                preservingExisting:(BOOL)preserve;

/**
 * Set all "has*" flags to NO and release all values,
 * returning the receiver to its default-initialised state
 * (as if initWithDirectoryPath: were just called).
 */
- (void)resetToDefaults;

// Icon position access
- (DSStoreIconInfo *)iconInfoForFilename:(NSString *)filename;
- (NSDictionary *)allIconInfo;
- (BOOL)hasAnyIconPositions;
- (NSArray *)filenamesWithPositions;

/**
 * Add or update the per-file icon info for @p filename.
 * This is the public write-side counterpart of the read-only
 * iconInfoForFilename:/allIconInfo accessors.  Used by the
 * per-volume cache reader to populate icon positions, label
 * colors, and comments when loading from cache.
 */
- (void)setIconInfo:(DSStoreIconInfo *)iconInfo forFilename:(NSString *)filename;

// Coordinate conversion utilities for .DS_Store interoperability
- (NSRect)gnustepWindowFrameForScreen:(NSScreen *)screen;
- (NSPoint)gnustepPositionForDSStorePoint:(NSPoint)dsPoint 
                           viewHeight:(CGFloat)viewHeight 
                           iconHeight:(CGFloat)iconHeight;

// Sort column conversion (DS_Store column name -> FSNInfoType)
// Returns -1 if column name not recognized
+ (int)infoTypeForSortColumnName:(NSString *)columnName;
+ (NSString *)sortColumnNameForInfoType:(int)infoType;

/* Canonical view-type name for a DS_Store view style: @"Icon", @"List" or
 * @"Browser" (Column -> Browser), defaulting to @"Icon".  Single source so
 * the browser and spatial viewers decode DSStoreViewStyle identically. */
+ (NSString *)viewTypeNameForViewStyle:(DSStoreViewStyle)style;

// Debugging
- (NSString *)debugDescription;
- (void)logAllInfo;

@end
