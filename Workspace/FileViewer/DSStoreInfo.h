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
    /* icvp arrangeBy as Finder writes it ("none", "grid", "name", ...);
     * nil while unknown.  iconArrangement is derived from it. */
    NSString *_arrangeBy;
    CGFloat _iconTextSize;
    BOOL _hasIconTextSize;
    BOOL _showItemInfo;
    BOOL _hasShowItemInfo;
    BOOL _showIconPreview;
    BOOL _hasShowIconPreview;
    NSPoint _scrollPosition;
    BOOL _hasScrollPosition;
    DSStoreLabelPosition _labelPosition;
    BOOL _hasLabelPosition;
    CGFloat _gridSpacing;
    BOOL _hasGridSpacing;
    
    // Background (BKGD/bwsp)
    DSStoreBackgroundType _backgroundType;
    NSColor *_backgroundColor;
    NSString *_backgroundImagePath;
    NSData *_backgroundImageAlias;
    
    // Sidebar (fwsw)
    int _sidebarWidth;
    BOOL _hasSidebarWidth;

    // Window chrome (bwsp)
    BOOL _showToolbar;
    BOOL _hasShowToolbar;
    BOOL _showStatusBar;
    BOOL _hasShowStatusBar;
    BOOL _showPathbar;
    BOOL _hasShowPathbar;
    BOOL _showSidebar;
    BOOL _hasShowSidebar;
    
    // List view settings (lsvp/lsvP)
    int _listTextSize;
    BOOL _hasListTextSize;
    int _listIconSize;
    BOOL _hasListIconSize;
    NSString *_sortColumn;
    BOOL _hasSortColumn;
    /* Used only when listColumns has no entry for the sort column. */
    BOOL _sortAscending;
    /* lsvp "columns" in Finder's own shape: column id -> {ascending, index,
     * visible, width}; keys Workspace does not know are kept. */
    NSDictionary *_listColumns;
    BOOL _useRelativeDates;
    BOOL _hasUseRelativeDates;
    BOOL _calculateAllSizes;
    BOOL _hasCalculateAllSizes;
    NSPoint _listScrollPosition;
    BOOL _hasListScrollPosition;

    /* The icvp / lsvp values as loaded, to tell what Workspace changed. */
    NSDictionary *_loadedIconValues;
    NSDictionary *_loadedListValues;
    
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

/* icvp keys of the same names.  arrangeBy is one of "none", "grid" (snap to
 * grid), "name", "kind", "dateModified", "dateCreated", "size", "label". */
@property (nonatomic, copy) NSString *arrangeBy;
@property (nonatomic, assign) CGFloat iconTextSize;
@property (nonatomic, assign) BOOL hasIconTextSize;
@property (nonatomic, assign) BOOL showItemInfo;
@property (nonatomic, assign) BOOL hasShowItemInfo;
@property (nonatomic, assign) BOOL showIconPreview;
@property (nonatomic, assign) BOOL hasShowIconPreview;
/* icvp scrollPositionX/Y: points from the left and top edge of the content. */
@property (nonatomic, assign) NSPoint scrollPosition;
@property (nonatomic, assign) BOOL hasScrollPosition;

// Background
@property (nonatomic, assign) DSStoreBackgroundType backgroundType;
@property (nonatomic, retain) NSColor *backgroundColor;
@property (nonatomic, copy) NSString *backgroundImagePath;
/* The classic alias record (version 2) Finder resolves the picture with,
 * icvp backgroundImageAlias [O:E12]; written with backgroundType 2. */
@property (nonatomic, copy) NSData *backgroundImageAlias;

// Sidebar
@property (nonatomic, assign) int sidebarWidth;
@property (nonatomic, assign) BOOL hasSidebarWidth;

// Window chrome (bwsp ShowToolbar, ShowStatusBar, ShowPathbar, ShowSidebar)
@property (nonatomic, assign) BOOL showToolbar;
@property (nonatomic, assign) BOOL hasShowToolbar;
@property (nonatomic, assign) BOOL showStatusBar;
@property (nonatomic, assign) BOOL hasShowStatusBar;
@property (nonatomic, assign) BOOL showPathbar;
@property (nonatomic, assign) BOOL hasShowPathbar;
@property (nonatomic, assign) BOOL showSidebar;
@property (nonatomic, assign) BOOL hasShowSidebar;

// List view settings
@property (nonatomic, assign) int listTextSize;
@property (nonatomic, assign) BOOL hasListTextSize;
@property (nonatomic, assign) int listIconSize;
@property (nonatomic, assign) BOOL hasListIconSize;
@property (nonatomic, copy) NSString *sortColumn;
@property (nonatomic, assign) BOOL hasSortColumn;
/* The direction of the sort column: its "ascending" in listColumns. */
@property (nonatomic, assign) BOOL sortAscending;
@property (nonatomic, copy) NSDictionary *listColumns;
@property (nonatomic, assign) BOOL useRelativeDates;
@property (nonatomic, assign) BOOL hasUseRelativeDates;
@property (nonatomic, assign) BOOL calculateAllSizes;
@property (nonatomic, assign) BOOL hasCalculateAllSizes;
/* lsvp scrollPositionX/Y, the icon view's convention [O:E11]. */
@property (nonatomic, assign) NSPoint listScrollPosition;
@property (nonatomic, assign) BOOL hasListScrollPosition;
/* Views of listColumns: column id -> width, column id -> visible. */
@property (nonatomic, readonly) NSDictionary *columnWidths;
@property (nonatomic, readonly) NSDictionary *columnVisible;
/* Ids of the visible columns, left to right. */
- (NSArray *)listColumnOrder;
/* The icvp / lsvp keys this object would write, with their values. */
- (NSDictionary *)iconViewRecordValues;
- (NSDictionary *)listViewRecordValues;

/* Takes the current values as the loaded ones; -load and -markAsLoaded do
 * this, a caller that merges more stored values in does it again. */
- (void)rememberLoadedOptions;

/* Whether the icon or list options differ from the loaded ones, i.e. were
 * changed in Workspace.  Only then is a missing icvp / lsvp created. */
- (BOOL)iconViewOptionsChanged;
- (BOOL)listViewOptionsChanged;

/* Whether any list view option (lsvp) is known. */
- (BOOL)hasListViewOptions;
/* Whether any icon view option (icvp) is known. */
- (BOOL)hasIconViewOptions;

/* The height Finder adds to a bwsp WindowBounds for the title bar. */
extern const CGFloat DSStoreInfoFinderTitleBarHeight;

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

/* Merge fields that the receiver does not have set (has* == NO / nil) from
 * @p other.  Used when persisting a partial DSStoreInfo (e.g. icon positions
 * only, or label colors only) into the per-volume cache so that fields the
 * caller did not touch (window geometry, view style, ...) are preserved
 * rather than clobbered. */
- (void)mergeMissingFieldsFromInfo:(DSStoreInfo *)other;

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

/* Replace the receiver's per-file icon positions with @p livePositions
 * (filename -> NSValue(NSPoint) iloc), dropping any position the caller no
 * longer displays.  Used to persist the live on-screen layout on window close
 * rather than re-writing whatever a stale .DS_Store contained. */
- (void)setLiveIconPositions:(NSDictionary *)livePositions;

/* === Shared per-file entry helpers (used by DSStoreInfo and GWVolumeCache) === */

/* Decode the Iloc/lclr/cmmt entries for @p filename from @p store into a
 * DSStoreIconInfo (named @p bareName), or nil if the file has none of them. */
+ (DSStoreIconInfo *)iconInfoForFile:(NSString *)filename
                            bareName:(NSString *)bareName
                           fromStore:(DSStore *)store;

/* Write a file's Iloc/lclr/cmmt entries into @p store (via setEntry:). */
+ (void)writeIconInfo:(DSStoreIconInfo *)ii
             forFile:(NSString *)filename
             toStore:(DSStore *)store;

/* Prune per-file entries in @p store whose filename is not an on-disk child
 * of @p directoryPath and not equal to @p keepPath (the directory's own
 * record).  Drops ghost entries (renamed/removed files, or localized names a
 * foreign Finder wrote) that would collide with live files on reopen.  No-op
 * when @p directoryPath is not a real directory. */
+ (void)pruneNonChildEntriesInStore:(DSStore *)store
                       forDirectory:(NSString *)directoryPath
                           keepPath:(NSString *)keepPath;

/* The names of the immediate children of @p directoryPath, or nil when it is
 * not a readable directory.  Shared by the per-file ghost filtering. */
+ (NSSet *)childrenOfDirectory:(NSString *)directoryPath;

/* Read the directory-level records stored under @p key (".", the folder's
 * name in its parent's store, or its path in a volume cache).  Values found
 * replace the receiver's; values not found are left alone. */
- (void)takeDirectoryRecordsFromStore:(DSStore *)store key:(NSString *)key;

/* The store and key Finder 10.6 keeps a folder's view and window records
 * under: the parent's .DS_Store, the folder's own name.  nil for "/". */
+ (NSString *)parentStorePathForDirectory:(NSString *)path;

/* Write the records Finder reads for a folder (vstl, bwsp, icvp, lsvp) into
 * the parent's .DS_Store under the folder's name.  NO when there is no
 * parent, it cannot be written, or there is nothing to write. */
- (BOOL)saveToParentStore;

/* Whether the receiver holds anything saveToParentStore would write. */
- (BOOL)hasFinderViewRecords;

/* Write the per-file Iloc/lclr/cmmt entries of @p info. */
+ (void)writePerFileEntriesForInfo:(DSStoreInfo *)info toStore:(DSStore *)store;

/* Write the Finder view records (vstl, bwsp, icvp, lsvp) of @p info under
 * @p key, merged over any record already there. */
+ (void)writeFinderViewRecordsForInfo:(DSStoreInfo *)info
                                  key:(NSString *)key
                              toStore:(DSStore *)store;

/* Write every persisted setting of @p info into @p store under the given
 * @p key: directory-level entries (view style, icon size, arrangement, label
 * position, grid spacing, background, sidebar, window geometry bwsp/fwi0, list
 * view lsvp) plus the per-file Iloc/lclr/cmmt entries.  Shared by
 * -saveToPath: (key ".") and GWVolumeCache -writeInfo: (key = dir path). */
+ (void)writeStoreEntriesForInfo:(DSStoreInfo *)info
                             key:(NSString *)key
                         toStore:(DSStore *)store;

/* The directory-level 4CC codes Workspace owns and may replace when writing
 * under a given key.  Used to drop only the caller's records (not unknown
 * Finder codes) before a cooperative merge write. */
+ (NSSet *)ownedDirectoryCodes;

// Coordinate conversion utilities for .DS_Store interoperability
/* A window rect as stored in .DS_Store (origin top-left, y measured down)
   converted to GNUstep screen coordinates (origin bottom-left).  Everything
   that loads a stored rect goes through this, so the receiver's windowFrame
   is always in GNUstep coordinates and the flip back to .DS_Store happens
   once, at save time. */
+ (NSRect)gnustepRectFromDSStoreRect:(NSRect)dsRect;

/* Stored rects are in points, as Finder means them; the window frames this
 * object holds are screen pixels, as measured from the X window.  This is
 * the factor between the two (GSScaleFactor). */
+ (CGFloat)scaleFactor;

- (NSRect)gnustepWindowFrameForScreen:(NSScreen *)screen;
- (NSPoint)gnustepPositionForDSStorePoint:(NSPoint)dsPoint 
                           viewHeight:(CGFloat)viewHeight 
                           iconHeight:(CGFloat)iconHeight;

/* Inverse of -gnustepWindowFrameForScreen:: express the receiver's GNUstep
 * window frame as the .DS_Store content-area rect (origin top-left, y is the
 * top edge measured downward from the top of the screen). */
- (NSRect)dsStoreWindowFrameForScreen:(NSScreen *)screen;

/* The main screen, or nil when the window server is unavailable (e.g. a
 * headless test run).  Geometry conversion falls back to a zero-height screen
 * in that case, which still round-trips because read and write share it. */
+ (NSScreen *)safeMainScreen;


/* Canonical view-type name for a DS_Store view style: @"Icon", @"List" or
 * @"Browser" (Column -> Browser), defaulting to @"Icon".  Single source so
 * the browser and spatial viewers decode DSStoreViewStyle identically. */
+ (NSString *)viewTypeNameForViewStyle:(DSStoreViewStyle)style;

// Debugging
- (NSString *)debugDescription;

@end
