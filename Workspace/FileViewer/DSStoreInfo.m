/* DSStoreInfo.m
 *  
 * DS_Store information model for .DS_Store interoperability in Spatial mode.
 *
 */

#import "DSStoreInfo.h"
#import "DSStore.h"
#import "GSFileMetadata.h"
#include <sys/stat.h>

#pragma mark - DSStoreIconInfo Implementation

@implementation DSStoreIconInfo

@synthesize filename = _filename;
@synthesize position = _position;
@synthesize hasPosition = _hasPosition;
@synthesize comments = _comments;
@synthesize labelColor = _labelColor;
@synthesize hasLabelColor = _hasLabelColor;

+ (instancetype)infoForFilename:(NSString *)filename
{
    return [[[self alloc] initWithFilename:filename] autorelease];
}

- (instancetype)initWithFilename:(NSString *)filename
{
    self = [super init];
    if (self) {
        _filename = [filename copy];
        _position = NSZeroPoint;
        _hasPosition = NO;
        _comments = nil;
        _labelColor = DSStoreLabelColorNone;
        _hasLabelColor = NO;
    }
    return self;
}

- (void)dealloc
{
    [_filename release];
    [_comments release];
    [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
    DSStoreIconInfo *copy = [[DSStoreIconInfo allocWithZone:zone] initWithFilename:_filename];
    copy.position = _position;
    copy.hasPosition = _hasPosition;
    copy.comments = _comments;
    copy.labelColor = _labelColor;
    copy.hasLabelColor = _hasLabelColor;
    return copy;
}

- (NSPoint)gnustepPositionForViewHeight:(CGFloat)viewHeight iconHeight:(CGFloat)iconHeight
{
    // Delegate to DSStore class method for .DS_Store interoperability coordinate conversion
    return [DSStore gnustepPointFromDSStorePoint:_position viewHeight:viewHeight iconHeight:iconHeight];
}

+ (NSColor *)colorForLabelColor:(DSStoreLabelColor)labelColor
{
    // macOS Finder label colors (approximate values)
    switch (labelColor) {
        case DSStoreLabelColorRed:
            return [NSColor colorWithCalibratedRed:1.0 green:0.23 blue:0.19 alpha:1.0];
        case DSStoreLabelColorOrange:
            return [NSColor colorWithCalibratedRed:1.0 green:0.58 blue:0.0 alpha:1.0];
        case DSStoreLabelColorYellow:
            return [NSColor colorWithCalibratedRed:1.0 green:0.87 blue:0.0 alpha:1.0];
        case DSStoreLabelColorGreen:
            return [NSColor colorWithCalibratedRed:0.3 green:0.85 blue:0.39 alpha:1.0];
        case DSStoreLabelColorBlue:
            return [NSColor colorWithCalibratedRed:0.25 green:0.61 blue:0.98 alpha:1.0];
        case DSStoreLabelColorPurple:
            return [NSColor colorWithCalibratedRed:0.69 green:0.32 blue:0.87 alpha:1.0];
        case DSStoreLabelColorGrey:
            return [NSColor colorWithCalibratedRed:0.6 green:0.6 blue:0.6 alpha:1.0];
        case DSStoreLabelColorNone:
        default:
            return nil;
    }
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<DSStoreIconInfo: %@ pos:(%.0f,%.0f) hasPos:%@ labelColor:%ld>",
            _filename, _position.x, _position.y, _hasPosition ? @"YES" : @"NO", (long)_labelColor];
}

@end

#pragma mark - DSStoreInfo Implementation

/* The title bar height of the Mac the bwsp records were taken on [O:E7]. */
const CGFloat DSStoreInfoFinderTitleBarHeight = 22.0;

@implementation DSStoreInfo

@synthesize directoryPath = _directoryPath;
@synthesize loaded = _loaded;
@synthesize windowFrame = _windowFrame;
@synthesize hasWindowFrame = _hasWindowFrame;
@synthesize viewStyle = _viewStyle;
@synthesize hasViewStyle = _hasViewStyle;
@synthesize iconSize = _iconSize;
@synthesize hasIconSize = _hasIconSize;
@synthesize arrangeBy = _arrangeBy;
@synthesize iconTextSize = _iconTextSize;
@synthesize hasIconTextSize = _hasIconTextSize;
@synthesize showItemInfo = _showItemInfo;
@synthesize hasShowItemInfo = _hasShowItemInfo;
@synthesize showIconPreview = _showIconPreview;
@synthesize hasShowIconPreview = _hasShowIconPreview;
@synthesize scrollPosition = _scrollPosition;
@synthesize hasScrollPosition = _hasScrollPosition;
@synthesize labelPosition = _labelPosition;
@synthesize hasLabelPosition = _hasLabelPosition;
@synthesize gridSpacing = _gridSpacing;
@synthesize hasGridSpacing = _hasGridSpacing;
@synthesize backgroundType = _backgroundType;
@synthesize backgroundColor = _backgroundColor;
@synthesize backgroundImagePath = _backgroundImagePath;
@synthesize backgroundImageAlias = _backgroundImageAlias;
@synthesize sidebarWidth = _sidebarWidth;
@synthesize hasSidebarWidth = _hasSidebarWidth;
@synthesize showToolbar = _showToolbar;
@synthesize hasShowToolbar = _hasShowToolbar;
@synthesize showStatusBar = _showStatusBar;
@synthesize hasShowStatusBar = _hasShowStatusBar;
@synthesize showPathbar = _showPathbar;
@synthesize hasShowPathbar = _hasShowPathbar;
@synthesize showSidebar = _showSidebar;
@synthesize hasShowSidebar = _hasShowSidebar;
@synthesize listTextSize = _listTextSize;
@synthesize hasListTextSize = _hasListTextSize;
@synthesize listIconSize = _listIconSize;
@synthesize hasListIconSize = _hasListIconSize;
@synthesize sortColumn = _sortColumn;
@synthesize hasSortColumn = _hasSortColumn;
@synthesize listColumns = _listColumns;
@synthesize useRelativeDates = _useRelativeDates;
@synthesize hasUseRelativeDates = _hasUseRelativeDates;
@synthesize calculateAllSizes = _calculateAllSizes;
@synthesize hasCalculateAllSizes = _hasCalculateAllSizes;

#pragma mark - Factory Methods

+ (instancetype)infoForDirectoryPath:(NSString *)path
{
    return [self infoForDirectoryPath:path loadImmediately:YES];
}

+ (instancetype)infoForDirectoryPath:(NSString *)path loadImmediately:(BOOL)load
{
    DSStoreInfo *info = [[[self alloc] initWithDirectoryPath:path] autorelease];
    if (load) {
        [info load];
    }
    return info;
}

#pragma mark - Derived Options

- (DSStoreIconArrangement)iconArrangement
{
    return [_arrangeBy isEqualToString:@"grid"] ? DSStoreIconArrangementGrid
                                                : DSStoreIconArrangementNone;
}

- (void)setIconArrangement:(DSStoreIconArrangement)arrangement
{
    [self setArrangeBy:(arrangement == DSStoreIconArrangementGrid) ? @"grid" : @"none"];
}

- (BOOL)hasIconArrangement
{
    return _arrangeBy != nil;
}

- (void)setHasIconArrangement:(BOOL)flag
{
    if (flag == NO) {
        [self setArrangeBy:nil];
    } else if (_arrangeBy == nil) {
        [self setArrangeBy:@"none"];
    }
}

- (BOOL)sortAscending
{
    NSDictionary *col = _sortColumn ? [_listColumns objectForKey:_sortColumn] : nil;
    id ascending = [col objectForKey:@"ascending"];
    return [ascending isKindOfClass:[NSNumber class]] ? [ascending boolValue] : _sortAscending;
}

- (void)setSortAscending:(BOOL)ascending
{
    _sortAscending = ascending;
    if (_sortColumn == nil) {
        return;
    }
    NSMutableDictionary *columns = [NSMutableDictionary dictionaryWithDictionary:_listColumns];
    NSMutableDictionary *col =
      [NSMutableDictionary dictionaryWithDictionary:[columns objectForKey:_sortColumn]];
    [col setObject:[NSNumber numberWithBool:ascending] forKey:@"ascending"];
    [columns setObject:col forKey:_sortColumn];
    [self setListColumns:columns];
}

- (NSDictionary *)columnValuesForKey:(NSString *)key
{
    if (_listColumns == nil) {
        return nil;
    }
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSString *columnId in _listColumns) {
        id v = [[_listColumns objectForKey:columnId] objectForKey:key];
        if (v) {
            [values setObject:v forKey:columnId];
        }
    }
    return values;
}

- (NSDictionary *)columnWidths
{
    return [self columnValuesForKey:@"width"];
}

- (NSDictionary *)columnVisible
{
    return [self columnValuesForKey:@"visible"];
}

- (NSArray *)listColumnOrder
{
    NSMutableArray *visible = [NSMutableArray array];
    for (NSString *columnId in _listColumns) {
        if ([[[_listColumns objectForKey:columnId] objectForKey:@"visible"] boolValue]) {
            [visible addObject:columnId];
        }
    }
    /* Finder can leave two columns with one index [F:E8 m_lci: kind and
     * dateModified both 1]; which one it shows first is OPEN, so the order
     * of Finder's own column list decides, for a stable result. */
    NSArray *finderOrder = [NSArray arrayWithObjects:@"name", @"dateModified", @"dateCreated",
                                    @"size", @"kind", @"label", @"version", @"comments",
                                    @"dateLastOpened", nil];
    NSDictionary *columns = _listColumns;
    return [visible sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        int ia = [[[columns objectForKey:a] objectForKey:@"index"] intValue];
        int ib = [[[columns objectForKey:b] objectForKey:@"index"] intValue];
        if (ia != ib) {
            return ia < ib ? NSOrderedAscending : NSOrderedDescending;
        }
        NSUInteger fa = [finderOrder indexOfObject:a];
        NSUInteger fb = [finderOrder indexOfObject:b];
        if (fa != fb) {
            return fa < fb ? NSOrderedAscending : NSOrderedDescending;
        }
        return [a compare:b];
    }];
}

- (BOOL)hasListViewOptions
{
    return _hasSortColumn || _hasListTextSize || _hasListIconSize || _hasUseRelativeDates
           || _hasCalculateAllSizes || [_listColumns count] > 0;
}

- (BOOL)hasIconViewOptions
{
    return _hasIconSize || _hasIconTextSize || _arrangeBy != nil || _hasLabelPosition
           || _hasGridSpacing || _hasShowItemInfo || _hasShowIconPreview || _hasScrollPosition
           || (_backgroundType == DSStoreBackgroundColor && _backgroundColor != nil)
           || (_backgroundType == DSStoreBackgroundPicture && _backgroundImageAlias != nil);
}

- (BOOL)hasWindowChrome
{
    return _hasShowToolbar || _hasShowStatusBar || _hasShowPathbar || _hasShowSidebar;
}

- (BOOL)hasFinderViewRecords
{
    return _hasViewStyle || _hasWindowFrame || [self hasIconViewOptions]
           || [self hasListViewOptions];
}

#pragma mark - View Style

+ (NSString *)viewTypeNameForViewStyle:(DSStoreViewStyle)style
{
    switch (style) {
        case DSStoreViewStyleList:   return @"List";
        case DSStoreViewStyleColumn: return @"Browser";
        case DSStoreViewStyleIcon:
        default:                     return @"Icon";
    }
}

#pragma mark - Initialization

- (instancetype)initWithDirectoryPath:(NSString *)path
{
    self = [super init];
    if (self) {
        _directoryPath = [path copy];
        _loaded = NO;
        
        // Initialize defaults
        _windowFrame = NSZeroRect;
        _hasWindowFrame = NO;
        
        _viewStyle = DSStoreViewStyleIcon;
        _hasViewStyle = NO;
        
        _iconSize = 48;  // Default icon size
        _hasIconSize = NO;
        _arrangeBy = nil;
        _showIconPreview = YES;
        _sortAscending = YES;
        _labelPosition = DSStoreLabelPositionBottom;
        _hasLabelPosition = NO;
        _gridSpacing = 0;
        _hasGridSpacing = NO;
        
        _backgroundType = DSStoreBackgroundDefault;
        _backgroundColor = nil;
        _backgroundImagePath = nil;
        
        _sidebarWidth = 0;
        _hasSidebarWidth = NO;
        
        _iconInfoDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [_directoryPath release];
    [_backgroundColor release];
    [_backgroundImagePath release];
    [_backgroundImageAlias release];
    [_iconInfoDict release];
    [_sortColumn release];
    [_arrangeBy release];
    [_listColumns release];
    [super dealloc];
}

#pragma mark - Loading

- (BOOL)load
{
    NSString *dsStorePath = [_directoryPath stringByAppendingPathComponent:@".DS_Store"];
    
    DSStore *store = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:dsStorePath]) {
        store = [DSStore storeWithPath:dsStorePath];
        if (![store load]) {
            store = nil;
        }
    }
    
    if (store) {
        /* Records named "." are what newer Finders and older Workspace
         * versions wrote; the per-file records (Iloc, cmmt) live here too. */
        [self takeDirectoryRecordsFromStore:store key:@"."];
        [self loadIconEntriesFromStore:store filenames:[store allFilenames]];
    }

    /* Finder 10.6 keeps a folder's view and window records in the parent's
     * store under the folder's name and ignores "." [O:E1, O:E2], so those
     * win over "." */
    BOOL parentHadRecords = [self loadParentStoreRecords];
    
    /* A folder may carry per-folder view/window state purely in its
     * com.apple.FinderInfo DInfo (classic / spatial macOS channel) with no
     * .DS_Store at all - consult that as a fallback regardless. */
    [self loadFinderInfoFallback];

    _loaded = YES;
    
    /* "Loaded" means we found something in .DS_Store or in FinderInfo. */
    return (_hasViewStyle || _hasWindowFrame || store != nil || parentHadRecords);
}

- (BOOL)loadParentStoreRecords
{
    NSString *parentStorePath = [DSStoreInfo parentStorePathForDirectory:_directoryPath];
    if (parentStorePath == nil
        || ![[NSFileManager defaultManager] fileExistsAtPath:parentStorePath]) {
        return NO;
    }
    DSStore *parent = [DSStore storeWithPath:parentStorePath];
    if (![parent load]) {
        return NO;
    }
    NSString *name = [_directoryPath lastPathComponent];
    if ([[parent allCodesForFilename:name] count] == 0) {
        return NO;
    }
    [self takeDirectoryRecordsFromStore:parent key:name];
    return YES;
}

+ (NSString *)parentStorePathForDirectory:(NSString *)path
{
    NSString *standard = [path stringByStandardizingPath];
    if ([standard length] == 0 || [standard isEqualToString:@"/"]) {
        return nil;
    }
    /* A volume's root and the home folder keep their records as "." in
     * their own store [O:E14]. */
    if ([standard isEqualToString:[NSHomeDirectory() stringByStandardizingPath]]) {
        return nil;
    }
    NSString *parent = [standard stringByDeletingLastPathComponent];
    struct stat own, up;
    if (stat([standard fileSystemRepresentation], &own) == 0
        && stat([parent fileSystemRepresentation], &up) == 0
        && own.st_dev != up.st_dev) {
        return nil;
    }
    return [parent stringByAppendingPathComponent:@".DS_Store"];
}

- (BOOL)reload
{
    [self resetToDefaults];
    return [self load];
}

#pragma mark - Manual population support

- (void)markAsLoaded
{
    _loaded = YES;
}

#pragma mark - Alias Resolution

/**
 * Resolve an alias record to a file path.
 * This is a simplified implementation that looks for common path patterns.
 * Native alias records are complex and contain multiple fallback strategies.
 */
- (NSString *)resolveAliasData:(NSData *)aliasData relativeTo:(NSString *)baseDir
{
    if (!aliasData || [aliasData length] < 150) {
        return nil;
    }
    
    // Alias records are complex, but typically contain:
    // - Volume name
    // - Directory IDs
    // - Full path as UTF-16 or UTF-8 string
    // For now, we'll try to find ASCII/UTF-8 path strings in the data
    
    // TS: unused variables
    // const unsigned char *bytes = [aliasData bytes];
    // NSUInteger len = [aliasData length];
    
    // Look for path-like strings in the alias data
    // Common patterns: starts with '/' or contains '.bg/' etc.
    NSString *dataString = [[NSString alloc] initWithData:aliasData 
                                                  encoding:NSUTF8StringEncoding];
    if (dataString) {
        // Try to extract paths using regex
        NSRegularExpression *regex = [NSRegularExpression 
            regularExpressionWithPattern:@"(/[^\\x00-\\x1F]+\\.(png|jpg|jpeg|tiff|gif|bmp))"
            options:NSRegularExpressionCaseInsensitive
            error:nil];
        
        NSArray *matches = [regex matchesInString:dataString
                                          options:0
                                            range:NSMakeRange(0, [dataString length])];
        
        if ([matches count] > 0) {
            NSTextCheckingResult *match = [matches objectAtIndex:0];
            NSString *path = [dataString substringWithRange:[match range]];
            
            // Check if file exists
            if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
                return path;
            }
            
            // Try relative to base directory
            NSString *relativePath = [baseDir stringByAppendingPathComponent:path];
            if ([[NSFileManager defaultManager] fileExistsAtPath:relativePath]) {
                return relativePath;
            }
        }
        [dataString release];
    }
    
    // Fallback: Look for common .bg folder pattern
    NSString *bgPath = [baseDir stringByAppendingPathComponent:@".bg"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bgPath]) {
        NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bgPath error:nil];
        for (NSString *file in contents) {
            if ([[file pathExtension] isEqualToString:@"png"] ||
                [[file pathExtension] isEqualToString:@"jpg"] ||
                [[file pathExtension] isEqualToString:@"jpeg"]) {
                return [bgPath stringByAppendingPathComponent:file];
            }
        }
    }
    
    return nil;
}

#pragma mark - Private Loading Methods

- (void)takeDirectoryRecordsFromStore:(DSStore *)store key:(NSString *)key
{
    if (store == nil || key == nil) {
        return;
    }
    /* Modern plist records first, then the legacy binary ones, which only
     * fill what the modern ones left open. */
    [self loadBrowserWindowSettingsFromStore:store key:key];
    [self loadWindowGeometryFromStore:store key:key];
    [self loadViewStyleFromStore:store key:key];
    [self loadIconViewPlistFromStore:store key:key];
    [self loadIconViewOptionsFromStore:store key:key];
    [self loadBackgroundFromStore:store key:key];
    [self loadSidebarWidthFromStore:store key:key];
    [self loadListViewSettingsFromStore:store key:key];
}

- (void)loadWindowGeometryFromStore:(DSStore *)store key:(NSString *)key
{
    /* fwi0 is the pre-10.6 record; bwsp, read before, wins. */
    if (_hasWindowFrame) {
        return;
    }

    DSStoreEntry *entry = [store entryForFilename:key code:@"fwi0"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        if ([data length] >= 16) {
            const uint8_t *bytes = (const uint8_t *)[data bytes];
            /* top, left, bottom, right of the content area, y measured down
             * from the top of the screen, then the view style and flags. */
            uint16_t top    = (bytes[0] << 8) | bytes[1];
            uint16_t left   = (bytes[2] << 8) | bytes[3];
            uint16_t bottom = (bytes[4] << 8) | bytes[5];
            uint16_t right  = (bytes[6] << 8) | bytes[7];

            _windowFrame = [DSStoreInfo gnustepRectFromDSStoreRect:
                              NSMakeRect(left, top, right - left, bottom - top)];
            _hasWindowFrame = YES;
        }
    }
}

- (void)loadViewStyleFromStore:(DSStore *)store key:(NSString *)key
{
    DSStoreEntry *entry = [store entryForFilename:key code:@"vstl"];
    if (entry && [[entry type] isEqualToString:@"type"]) {
        NSString *style = (NSString *)[entry value];
        
        if ([style isEqualToString:@"icnv"]) {
            _viewStyle = DSStoreViewStyleIcon;
            _hasViewStyle = YES;
        } else if ([style isEqualToString:@"Nlsv"]) {
            _viewStyle = DSStoreViewStyleList;
            _hasViewStyle = YES;
        } else if ([style isEqualToString:@"clmv"]) {
            _viewStyle = DSStoreViewStyleColumn;
            _hasViewStyle = YES;
        } else if ([style isEqualToString:@"glyv"]) {
            _viewStyle = DSStoreViewStyleGallery;
            _hasViewStyle = YES;
        } else if ([style isEqualToString:@"Flwv"]) {
            _viewStyle = DSStoreViewStyleCoverflow;
            _hasViewStyle = YES;
        }
    }
}

- (void)loadFinderInfoFallback
{
    GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: _directoryPath];
    if (md == nil)
        return;

    if (!_hasViewStyle) {
        NSString *code = [md viewStyleCodeForDirectory];
        if ([code isEqualToString: @"icnv"]) {
            _viewStyle = DSStoreViewStyleIcon;     _hasViewStyle = YES;
        } else if ([code isEqualToString: @"Nlsv"]) {
            _viewStyle = DSStoreViewStyleList;     _hasViewStyle = YES;
        } else if ([code isEqualToString: @"clmv"]) {
            _viewStyle = DSStoreViewStyleColumn;   _hasViewStyle = YES;
        } else if ([code isEqualToString: @"glyv"]) {
            _viewStyle = DSStoreViewStyleGallery;  _hasViewStyle = YES;
        } else if ([code isEqualToString: @"Flwv"]) {
            _viewStyle = DSStoreViewStyleCoverflow; _hasViewStyle = YES;
        }
    }

    if (!_hasWindowFrame) {
        NSRect r = [md windowBoundsForDirectory];
        if (!NSEqualRects(r, NSZeroRect)) {
            _windowFrame = [DSStoreInfo gnustepRectFromDSStoreRect: r];
            _hasWindowFrame = YES;
        }
    }
}

/* The binary plist of a blob record, or nil. */
static NSDictionary *plistOfEntry(DSStoreEntry *entry)
{
    if (entry == nil || ![[entry type] isEqualToString:@"blob"]
        || ![[entry value] isKindOfClass:[NSData class]]) {
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:(NSData *)[entry value]
                                                          options:NSPropertyListImmutable
                                                           format:NULL
                                                            error:NULL];
    return [plist isKindOfClass:[NSDictionary class]] ? plist : nil;
}

/* A plist number or boolean, read into *value; NO when absent or not one. */
static BOOL readBool(NSDictionary *plist, NSString *key, BOOL *value)
{
    id v = [plist objectForKey:key];
    if (![v isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    *value = [v boolValue];
    return YES;
}

static BOOL readFloat(NSDictionary *plist, NSString *key, CGFloat *value)
{
    id v = [plist objectForKey:key];
    if (![v isKindOfClass:[NSNumber class]]) {
        return NO;
    }
    *value = [v doubleValue];
    return YES;
}

- (void)loadBrowserWindowSettingsFromStore:(DSStore *)store key:(NSString *)key
{
    NSDictionary *plist = plistOfEntry([store entryForFilename:key code:@"bwsp"]);
    if (plist == nil) {
        return;
    }

    /* WindowBounds is the whole window, title bar included, with the origin
     * at the bottom left of the screen and y going up - the same convention
     * as a GNUstep frame [O:E7].  Only the title bar has to come off to get
     * the content rect this object holds. */
    NSString *windowBounds = [plist objectForKey:@"WindowBounds"];
    if ([windowBounds isKindOfClass:[NSString class]]) {
        NSRect rect = NSRectFromString(windowBounds);
        if (rect.size.width > 0 && rect.size.height > DSStoreInfoFinderTitleBarHeight) {
            rect.size.height -= DSStoreInfoFinderTitleBarHeight;
            _windowFrame = rect;
            _hasWindowFrame = YES;
        }
    }

    CGFloat width;
    if (readFloat(plist, @"SidebarWidth", &width)) {
        _sidebarWidth = (int)width;
        _hasSidebarWidth = YES;
    }
    _hasShowToolbar |= readBool(plist, @"ShowToolbar", &_showToolbar);
    _hasShowStatusBar |= readBool(plist, @"ShowStatusBar", &_showStatusBar);
    _hasShowPathbar |= readBool(plist, @"ShowPathbar", &_showPathbar);
    _hasShowSidebar |= readBool(plist, @"ShowSidebar", &_showSidebar);
}

- (void)loadIconViewOptionsFromStore:(DSStore *)store key:(NSString *)key
{
    // icvo: Legacy icon view options format (pre-10.6)
    // Only used as fallback if icvp is not present
    // Modern .DS_Store files use icvp binary plist instead
    
    // Skip if we already have settings from icvp (new format)
    if (_hasIconSize && _arrangeBy != nil && _hasLabelPosition) {
        return;
    }
    
    DSStoreEntry *entry = [store entryForFilename:key code:@"icvo"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        const uint8_t *bytes = (const uint8_t *)[data bytes];
        NSUInteger len = [data length];
        
        
        // External docs specify two variants:
        // 1) "icvo" format: 4-byte magic + 8 unknown + 2-byte size + 4-byte arrangement ("none")
        // 2) "icv4" format: 2-byte size + 4-byte arrangement + 4-byte label + 12 flags
        
        if (len >= 4) {
            char magic[5] = {bytes[0], bytes[1], bytes[2], bytes[3], 0};
            
            if (strcmp(magic, "icvo") == 0 && len >= 18) {
                // Old "icvo" format: skip magic+flags (12 bytes), then size at offset 12
                uint16_t size = (bytes[12] << 8) | bytes[13];
                if (size > 0 && size <= 512) {
                    _iconSize = size;
                    _hasIconSize = YES;
                }
                
                // Arrangement at bytes 14-17
                if (len >= 18 && _arrangeBy == nil) {
                    char arr[5] = {bytes[14], bytes[15], bytes[16], bytes[17], 0};
                    if (strcmp(arr, "none") == 0 || strcmp(arr, "grid") == 0) {
                        [self setArrangeBy:[NSString stringWithUTF8String:arr]];
                    }
                }
            } else if (strcmp(magic, "icv4") == 0 && len >= 14) {
                // New "icv4" format: size at bytes 4-5
                uint16_t size = (bytes[4] << 8) | bytes[5];
                if (size > 0 && size <= 512) {
                    _iconSize = size;
                    _hasIconSize = YES;
                }
                
                // Arrangement at bytes 6-9
                char arr[5] = {bytes[6], bytes[7], bytes[8], bytes[9], 0};
                if (_arrangeBy == nil
                    && (strcmp(arr, "none") == 0 || strcmp(arr, "grid") == 0)) {
                    [self setArrangeBy:[NSString stringWithUTF8String:arr]];
                }
                
                // Label position at bytes 10-13
                if (len >= 14) {
                    char lbl[5] = {bytes[10], bytes[11], bytes[12], bytes[13], 0};
                    if (strcmp(lbl, "botm") == 0) {
                        _labelPosition = DSStoreLabelPositionBottom;
                        _hasLabelPosition = YES;
                    } else if (strcmp(lbl, "rght") == 0) {
                        _labelPosition = DSStoreLabelPositionRight;
                        _hasLabelPosition = YES;
                    }
                }
            } else {
            }
        }
    } else {
    }
}

- (void)loadIconViewPlistFromStore:(DSStore *)store key:(NSString *)key
{
    /* icvp, the 10.6 icon view record [F:E1, F:E8].  Finder writes sizes
     * and spacing as reals but reads integers as well [O:E6]. */
    NSDictionary *plist = plistOfEntry([store entryForFilename:key code:@"icvp"]);
    if (plist == nil) {
        return;
    }

    CGFloat value;
    if (readFloat(plist, @"iconSize", &value) && value > 0 && value <= 512) {
        _iconSize = (int)value;
        _hasIconSize = YES;
    }
    if (readFloat(plist, @"textSize", &value) && value > 0) {
        _iconTextSize = value;
        _hasIconTextSize = YES;
    }
    if (readFloat(plist, @"gridSpacing", &value)) {
        _gridSpacing = value;
        _hasGridSpacing = YES;
    }

    id arrangeBy = [plist objectForKey:@"arrangeBy"];
    if ([arrangeBy isKindOfClass:[NSString class]]) {
        [self setArrangeBy:arrangeBy];
    }

    BOOL onBottom;
    if (readBool(plist, @"labelOnBottom", &onBottom)) {
        _labelPosition = onBottom ? DSStoreLabelPositionBottom : DSStoreLabelPositionRight;
        _hasLabelPosition = YES;
    }
    _hasShowItemInfo |= readBool(plist, @"showItemInfo", &_showItemInfo);
    _hasShowIconPreview |= readBool(plist, @"showIconPreview", &_showIconPreview);

    /* Not in a 10.6 record [F:E8]; newer Finders write these [G: key names,
     * origin top-left, OPEN S12]. */
    CGFloat x, y;
    if (readFloat(plist, @"scrollPositionX", &x) && readFloat(plist, @"scrollPositionY", &y)) {
        _scrollPosition = NSMakePoint(x, y);
        _hasScrollPosition = YES;
    }

    id bgType = [plist objectForKey:@"backgroundType"];
    int type = [bgType isKindOfClass:[NSNumber class]] ? [bgType intValue] : 0;
    if (type == 2) {
        _backgroundType = DSStoreBackgroundPicture;
        id alias = [plist objectForKey:@"backgroundImageAlias"];
        if ([alias isKindOfClass:[NSData class]]) {
            [self setBackgroundImageAlias:alias];
            NSString *resolved = [self resolveAliasData:alias relativeTo:_directoryPath];
            if (resolved) {
                [self setBackgroundImagePath:resolved];
            }
        }
    } else if (type == 1) {
        CGFloat r = 1.0, g = 1.0, b = 1.0;
        readFloat(plist, @"backgroundColorRed", &r);
        readFloat(plist, @"backgroundColorGreen", &g);
        readFloat(plist, @"backgroundColorBlue", &b);
        [self setBackgroundColor:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0]];
        _backgroundType = DSStoreBackgroundColor;
    }
}

- (void)loadBackgroundFromStore:(DSStore *)store key:(NSString *)key
{
    DSStoreEntry *entry = [store entryForFilename:key code:@"BKGD"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        if ([data length] >= 4) {
            const char *bytes = (const char *)[data bytes];
            
            if (strncmp(bytes, "DefB", 4) == 0) {
                _backgroundType = DSStoreBackgroundDefault;
            } else if (strncmp(bytes, "ClrB", 4) == 0) {
                _backgroundType = DSStoreBackgroundColor;
                // External docs: 4CC "ClrB" + RGB in 6 bytes (2 bytes per channel, big-endian)
                if ([data length] >= 10) {
                    const uint8_t *cBytes = (const uint8_t *)bytes;
                    uint16_t rVal = (cBytes[4] << 8) | cBytes[5];
                    uint16_t gVal = (cBytes[6] << 8) | cBytes[7];
                    uint16_t bVal = (cBytes[8] << 8) | cBytes[9];
                    CGFloat r = rVal / 65535.0;
                    CGFloat g = gVal / 65535.0;
                    CGFloat b = bVal / 65535.0;
                    [_backgroundColor release];
                    _backgroundColor = [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] retain];
                }
            } else if (strncmp(bytes, "PctB", 4) == 0) {
                _backgroundType = DSStoreBackgroundPicture;
                
                NSString *imagePath = [self backgroundImagePathFromStore:store key:key];
                if (imagePath && [imagePath length] > 0) {
                    [_backgroundImagePath release];
                    _backgroundImagePath = [imagePath copy];
                } else {
                }
            }
        }
    } else {
    }
}

/* The image path Workspace keeps in a "pict" ustr next to BKGD PctB; 10.6
 * reads the picture from icvp instead [O:E12]. */
- (NSString *)backgroundImagePathFromStore:(DSStore *)store key:(NSString *)key
{
    DSStoreEntry *entry = [store entryForFilename:key code:@"pict"];
    if (entry && [[entry type] isEqualToString:@"ustr"]
        && [[entry value] isKindOfClass:[NSString class]]) {
        return (NSString *)[entry value];
    }
    return nil;
}

/* lsvo column codes in the order of the lsvp column ids of the same folder
 * [F:E8 m_lcv lsvo against m_lci lsvp].  Date last opened has no code there. */
static NSString *columnIdForLegacyCode(NSString *code)
{
    static NSDictionary *map = nil;
    if (map == nil) {
        map = [[NSDictionary alloc] initWithObjectsAndKeys:
                 @"name", @"dnam", @"dateModified", @"modd", @"dateCreated", @"ascd",
                 @"size", @"phys", @"kind", @"kind", @"label", @"labl",
                 @"version", @"shvr", @"comments", @"cmmt", nil];
    }
    return [map objectForKey:code];
}

/* lsvo, what 10.6 writes when a column is shown or hidden by script
 * [F:E8 m_lcv]: "lsv1", three bytes of unknown meaning, the 4CC of the sort
 * column, the number of columns, then one 8-byte entry per column in display
 * order: 4CC, width (BE16), 1 ascending / 2 descending, 1 visible / 0 hidden.
 * The meaning of each field was read off the lsvp Finder wrote for the same
 * settings. */
- (void)loadLegacyListViewOptions:(NSData *)data
{
    const uint8_t *b = (const uint8_t *)[data bytes];
    NSUInteger len = [data length];
    if (len < 12 || memcmp(b, "lsv1", 4) != 0) {
        return;
    }
    NSString *sortCode = [[[NSString alloc] initWithBytes:b + 7 length:4
                                                 encoding:NSASCIIStringEncoding] autorelease];
    NSMutableDictionary *columns = [NSMutableDictionary dictionary];
    NSUInteger index = 0;
    NSUInteger off;
    for (off = 12; off + 8 <= len && index < b[11]; off += 8, index++) {
        NSString *code = [[[NSString alloc] initWithBytes:b + off length:4
                                                 encoding:NSASCIIStringEncoding] autorelease];
        NSString *columnId = columnIdForLegacyCode(code);
        if (columnId == nil) {
            continue;
        }
        [columns setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithInt:(b[off + 4] << 8) | b[off + 5]], @"width",
                              [NSNumber numberWithBool:(b[off + 6] == 1)], @"ascending",
                              [NSNumber numberWithBool:(b[off + 7] != 0)], @"visible",
                              [NSNumber numberWithInt:(int)index], @"index", nil]
                    forKey:columnId];
    }
    if ([columns count] > 0) {
        [self setListColumns:columns];
    }
    NSString *sortId = columnIdForLegacyCode(sortCode);
    if (sortId) {
        [self setSortColumn:sortId];
        _hasSortColumn = YES;
    }
}

- (void)loadListViewSettingsFromStore:(DSStore *)store key:(NSString *)key
{
    DSStoreEntry *entry = [store entryForFilename:key code:@"lsvp"];
    if (entry == nil) {
        entry = [store entryForFilename:key code:@"lsvP"];
    }
    NSDictionary *plist = plistOfEntry(entry);
    if (plist == nil) {
        DSStoreEntry *legacy = [store entryForFilename:key code:@"lsvo"];
        if (legacy && [[legacy type] isEqualToString:@"blob"]) {
            [self loadLegacyListViewOptions:(NSData *)[legacy value]];
        }
        return;
    }

    CGFloat value;
    if (readFloat(plist, @"textSize", &value) && value > 0) {
        _listTextSize = (int)value;
        _hasListTextSize = YES;
    }
    if (readFloat(plist, @"iconSize", &value) && value > 0) {
        _listIconSize = (int)value;
        _hasListIconSize = YES;
    }
    id sortColumn = [plist objectForKey:@"sortColumn"];
    if ([sortColumn isKindOfClass:[NSString class]]) {
        [self setSortColumn:sortColumn];
        _hasSortColumn = YES;
    }
    _hasUseRelativeDates |= readBool(plist, @"useRelativeDates", &_useRelativeDates);
    _hasCalculateAllSizes |= readBool(plist, @"calculateAllSizes", &_calculateAllSizes);

    /* Older Workspace versions wrote a top-level "ascending"; 10.6 keeps
     * the direction per column [F:E8]. */
    readBool(plist, @"ascending", &_sortAscending);

    id columns = [plist objectForKey:@"columns"];
    if ([columns isKindOfClass:[NSDictionary class]]) {
        /* 10.6: column id -> {ascending, index, visible, width} [F:E8]. */
        NSMutableDictionary *byId = [NSMutableDictionary dictionary];
        for (NSString *columnId in columns) {
            id col = [columns objectForKey:columnId];
            if ([columnId isKindOfClass:[NSString class]] && [col isKindOfClass:[NSDictionary class]]) {
                [byId setObject:col forKey:columnId];
            }
        }
        [self setListColumns:byId];
    } else if ([columns isKindOfClass:[NSArray class]]) {
        /* The array of {identifier, width, visible} older Workspace versions
         * wrote; its order is the column order. */
        NSMutableDictionary *byId = [NSMutableDictionary dictionary];
        int index = 0;
        for (id col in columns) {
            id columnId = [col isKindOfClass:[NSDictionary class]] ? [col objectForKey:@"identifier"] : nil;
            if (![columnId isKindOfClass:[NSString class]]) {
                continue;
            }
            NSMutableDictionary *entryDict = [NSMutableDictionary dictionaryWithDictionary:col];
            [entryDict removeObjectForKey:@"identifier"];
            [entryDict setObject:[NSNumber numberWithInt:index++] forKey:@"index"];
            if ([entryDict objectForKey:@"visible"] == nil) {
                [entryDict setObject:[NSNumber numberWithBool:YES] forKey:@"visible"];
            }
            [byId setObject:entryDict forKey:columnId];
        }
        [self setListColumns:byId];
    }
}

- (void)loadSidebarWidthFromStore:(DSStore *)store key:(NSString *)key
{
    /* fwsw is the pre-10.6 record; bwsp, read before, wins. */
    if (_hasSidebarWidth) {
        return;
    }
    DSStoreEntry *entry = [store entryForFilename:key code:@"fwsw"];
    if (entry && [[entry type] isEqualToString:@"long"]) {
        _sidebarWidth = [[entry value] intValue];
        _hasSidebarWidth = YES;
    } else {
    }
}

- (void)loadIconEntriesFromStore:(DSStore *)store filenames:(NSArray *)filenames
{
    

    /* On-disk children of this directory, used to drop ghost entries. */
    NSSet *children = [DSStoreInfo childrenOfDirectory: _directoryPath];
    
    for (NSString *filename in filenames) {
        // Skip directory entry
        if ([filename isEqualToString:@"."]) continue;
        
        DSStoreIconInfo *info = nil;
        
        // Check for Iloc (icon location)
        DSStoreEntry *ilocEntry = [store entryForFilename:filename code:@"Iloc"];
        if (ilocEntry && [[ilocEntry type] isEqualToString:@"blob"]) {
            NSData *data = (NSData *)[ilocEntry value];
            if ([data length] >= 8) {
                const uint8_t *bytes = (const uint8_t *)[data bytes];
                
                // Iloc format per external docs:
                // - 16-byte blob: Two 4-byte big-endian signed integers for x,y
                // - Coordinates are CENTER of icon (not top-left)
                // - Origin at top-left of window content area
                // - Remaining 8 bytes: 6 bytes 0xff + 2 bytes 0x00
                int32_t x = (int32_t)((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]);
                int32_t y = (int32_t)((bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7]);
                
                if (!info) {
                    info = [DSStoreIconInfo infoForFilename:filename];
                }
                info.position = NSMakePoint((CGFloat)x, (CGFloat)y);
                info.hasPosition = YES;
                
            }
        }
        
        // Check for cmmt (comments)
        DSStoreEntry *cmmtEntry = [store entryForFilename:filename code:@"cmmt"];
        if (cmmtEntry && [[cmmtEntry type] isEqualToString:@"ustr"]) {
            if (!info) {
                info = [DSStoreIconInfo infoForFilename:filename];
            }
            info.comments = (NSString *)[cmmtEntry value];
        }
        
        // Check for lclr (label color)
        DSStoreEntry *lclrEntry = [store entryForFilename:filename code:@"lclr"];
        if (lclrEntry && [[lclrEntry type] isEqualToString:@"long"]) {
            if (!info) {
                info = [DSStoreIconInfo infoForFilename:filename];
            }
            int32_t colorValue = [[lclrEntry value] intValue];
            info.labelColor = (DSStoreLabelColor)colorValue;
            info.hasLabelColor = YES;
            
        }
        
        // Store the info if we have any data
        if (info) {
            /* Skip ghost entries: a foreign Finder (or a removed/renamed
             * file) can leave an Iloc/cmmt/lclr for a filename that is no
             * longer a child of this directory.  Honoring it would place a
             * nonexistent icon and, worse, collide with a live file that now
             * has the same position.  Only keep entries whose name is an
             * on-disk child (or the directory itself). */
            if (children && [children containsObject: filename] == NO)
                continue;   /* ghost - drop */
            [_iconInfoDict setObject:info forKey:filename];
        }
    }
    
}

#pragma mark - Icon Position Access

- (DSStoreIconInfo *)iconInfoForFilename:(NSString *)filename
{
    return [_iconInfoDict objectForKey:filename];
}

- (void)setIconInfo:(DSStoreIconInfo *)iconInfo forFilename:(NSString *)filename
{
    if (iconInfo && filename) {
        [_iconInfoDict setObject:iconInfo forKey:filename];
    }
}

- (void)setLiveIconPositions:(NSDictionary *)livePositions
{
    /* Reset the icon-info map entirely, then re-add only the live icons with
     * their positions, so a stale/foreign .DS_Store never survives a close. */
    [_iconInfoDict removeAllObjects];
    for (NSString *filename in livePositions) {
        NSValue *v = [livePositions objectForKey: filename];
        if (v == nil) continue;
        NSPoint iloc = [v pointValue];
        DSStoreIconInfo *ii = [DSStoreIconInfo infoForFilename: filename];
        [ii setPosition: iloc];
        [ii setHasPosition: YES];
        [_iconInfoDict setObject: ii forKey: filename];
    }
}

- (NSDictionary *)allIconInfo
{
    return [NSDictionary dictionaryWithDictionary:_iconInfoDict];
}

/* === Shared per-file entry helpers (also used by GWVolumeCache) === */

+ (DSStoreIconInfo *)iconInfoForFile:(NSString *)filename
                            bareName:(NSString *)bareName
                           fromStore:(DSStore *)store
{
    DSStoreIconInfo *ii = nil;

    /* Iloc: icon location - 16-byte blob, two 4-byte big-endian signed ints
     * (the icon CENTER, origin at top-left of the window content area). */
    DSStoreEntry *iloc = [store entryForFilename:filename code:@"Iloc"];
    if (iloc && [[iloc type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[iloc value];
        if ([data length] >= 8) {
            const uint8_t *b = (const uint8_t *)[data bytes];
            int32_t x = (int32_t)((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]);
            int32_t y = (int32_t)((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]);
            if (!ii) ii = [DSStoreIconInfo infoForFilename:bareName];
            [ii setPosition:NSMakePoint((CGFloat)x, (CGFloat)y)];
            [ii setHasPosition:YES];
        }
    }

    /* lclr: label color */
    DSStoreEntry *lclr = [store entryForFilename:filename code:@"lclr"];
    if (lclr && [[lclr type] isEqualToString:@"long"]) {
        if (!ii) ii = [DSStoreIconInfo infoForFilename:bareName];
        [ii setLabelColor:(DSStoreLabelColor)[[lclr value] intValue]];
        [ii setHasLabelColor:YES];
    }

    /* cmmt: comments */
    DSStoreEntry *cmmt = [store entryForFilename:filename code:@"cmmt"];
    if (cmmt && [[cmmt type] isEqualToString:@"ustr"]) {
        if (!ii) ii = [DSStoreIconInfo infoForFilename:bareName];
        [ii setComments:(NSString *)[cmmt value]];
    }

    return ii;
}

+ (void)writeIconInfo:(DSStoreIconInfo *)ii
             forFile:(NSString *)filename
             toStore:(DSStore *)store
{
    if ([ii hasPosition]) {
        /* Patch the existing Iloc so Finder's trailing bytes are preserved. */
        DSStoreEntry *old = [store entryForFilename: filename code: @"Iloc"];
        DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile: filename
                                                                x: (int)[ii position].x
                                                                y: (int)[ii position].y
                                                    preserving: old];
        if (e) [store setEntry:e];
    }
    if ([ii comments]) {
        DSStoreEntry *e = [DSStoreEntry commentsEntryForFile:filename
                                                    comments:[ii comments]];
        if (e) [store setEntry:e];
    }
    if ([ii hasLabelColor]) {
        DSStoreEntry *e = [DSStoreEntry labelColorEntryForFile:filename
                                                          color:(int)[ii labelColor]];
        if (e) [store setEntry:e];
    }
}

+ (NSSet *)childrenOfDirectory:(NSString *)directoryPath
{
    BOOL isDir = NO;
    BOOL dirExists = [[NSFileManager defaultManager]
                       fileExistsAtPath: directoryPath isDirectory: &isDir];
    if (!(dirExists && isDir)) return nil;
    NSArray *children = [[NSFileManager defaultManager]
                          contentsOfDirectoryAtPath: directoryPath error: NULL];
    if (children == nil) return nil;
    return [NSSet setWithArray: children];
}

+ (void)pruneNonChildEntriesInStore:(DSStore *)store
                       forDirectory:(NSString *)directoryPath
                           keepPath:(NSString *)keepPath
{
    NSSet *childSet = [self childrenOfDirectory: directoryPath];
    if (childSet == nil) return;

    NSMutableSet *ghosts = [NSMutableSet set];
    for (NSString *fn in [store allFilenames]) {
        if ([fn isEqualToString: keepPath]) continue;
        if ([fn isEqualToString: @"/"]) continue;   /* volume-root record */
        if ([childSet containsObject: fn]) continue;  /* real child */
        [ghosts addObject: fn];
    }
    [store removeAllEntriesForFilenames: ghosts];
}

+ (NSSet *)ownedDirectoryCodes
{
    /* The codes writeStoreEntriesForInfo: emits for a directory key.  Any
     * other 4CC under the same key (written by Finder) is not owned and must
     * survive a merge write. */
    return [NSSet setWithObjects:
              @"vstl", @"icvo", @"icvp", @"iarr", @"lblp", @"icsp",
              @"BKGD", @"pict", @"fwsw", @"bwsp", @"fwi0", @"lsvp",
              nil];
}

static NSString *viewStyleCode(DSStoreViewStyle style)
{
    switch (style) {
        case DSStoreViewStyleList:      return @"Nlsv";
        case DSStoreViewStyleColumn:    return @"clmv";
        case DSStoreViewStyleGallery:   return @"glyv";
        case DSStoreViewStyleCoverflow: return @"Flwv";
        case DSStoreViewStyleIcon:
        default:                        return @"icnv";
    }
}

/* @p defaults, overlaid with the plist already stored in @p existing (so that
 * keys only Finder knows survive), overlaid with @p owned. */
static DSStoreEntry *mergedPlistEntry(NSString *key, NSString *code, DSStoreEntry *existing,
                                      NSDictionary *defaults, NSDictionary *owned)
{
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:defaults];
    NSDictionary *stored = plistOfEntry(existing);
    if (stored) {
        [merged addEntriesFromDictionary:stored];
    }
    [merged addEntriesFromDictionary:owned];
    return [DSStoreEntry plistEntryForFile:key code:code dictionary:merged];
}

/* An icvp as 10.6 Finder writes it for a fresh folder [F:E8].  Finder drops
 * an icvp that lacks any of textSize, gridSpacing, labelOnBottom,
 * showItemInfo, showIconPreview, arrangeBy or the background colors, and one
 * with a viewOptionsVersion other than 0 [O:E6], so every record we write
 * starts from this complete set. */
static NSDictionary *finderIconViewDefaults(void)
{
    static NSDictionary *defaults = nil;
    if (defaults == nil) {
        NSNumber *one = [NSNumber numberWithDouble:1.0];
        NSNumber *zero = [NSNumber numberWithDouble:0.0];
        defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
          @"none", @"arrangeBy",
          one, @"backgroundColorBlue", one, @"backgroundColorGreen", one, @"backgroundColorRed",
          [NSNumber numberWithInt:0], @"backgroundType",
          zero, @"gridOffsetX", zero, @"gridOffsetY",
          [NSNumber numberWithDouble:100.0], @"gridSpacing",
          [NSNumber numberWithDouble:48.0], @"iconSize",
          [NSNumber numberWithBool:YES], @"labelOnBottom",
          [NSNumber numberWithBool:YES], @"showIconPreview",
          [NSNumber numberWithBool:NO], @"showItemInfo",
          [NSNumber numberWithDouble:12.0], @"textSize",
          [NSNumber numberWithInt:0], @"viewOptionsVersion", nil];
    }
    return defaults;
}

/* The lsvp columns 10.6 Finder writes for a fresh folder [F:E8]. */
static NSDictionary *finderListColumnDefaults(void)
{
    static NSDictionary *defaults = nil;
    if (defaults == nil) {
        /* id, index, width, ascending, visible */
        struct { const char *columnId; int index, width; BOOL ascending, visible; } cols[] = {
            { "name", 0, 300, YES, YES }, { "dateModified", 1, 181, NO, YES },
            { "dateCreated", 2, 181, NO, NO }, { "size", 3, 97, NO, YES },
            { "kind", 4, 115, YES, YES }, { "label", 5, 100, YES, NO },
            { "version", 6, 75, YES, NO }, { "comments", 7, 300, YES, NO },
            { "dateLastOpened", 8, 200, NO, NO } };
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        unsigned i;
        for (i = 0; i < sizeof(cols) / sizeof(cols[0]); i++) {
            [d setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSNumber numberWithBool:cols[i].ascending], @"ascending",
                            [NSNumber numberWithInt:cols[i].index], @"index",
                            [NSNumber numberWithBool:cols[i].visible], @"visible",
                            [NSNumber numberWithInt:cols[i].width], @"width", nil]
                  forKey:[NSString stringWithUTF8String:cols[i].columnId]];
        }
        defaults = [d copy];
    }
    return defaults;
}

static NSDictionary *finderListViewDefaults(void)
{
    static NSDictionary *defaults = nil;
    if (defaults == nil) {
        defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
          [NSNumber numberWithBool:NO], @"calculateAllSizes",
          finderListColumnDefaults(), @"columns",
          [NSNumber numberWithDouble:16.0], @"iconSize",
          [NSNumber numberWithBool:YES], @"showIconPreview",
          @"name", @"sortColumn",
          [NSNumber numberWithDouble:12.0], @"textSize",
          [NSNumber numberWithBool:YES], @"useRelativeDates",
          [NSNumber numberWithInt:0], @"viewOptionsVersion", nil];
    }
    return defaults;
}

/* bwsp as 10.6 Finder writes it [F:E1 eA]. */
static NSDictionary *finderWindowDefaults(void)
{
    static NSDictionary *defaults = nil;
    if (defaults == nil) {
        defaults = [[NSDictionary alloc] initWithObjectsAndKeys:
          [NSNumber numberWithBool:NO], @"ShowPathbar",
          [NSNumber numberWithBool:YES], @"ShowSidebar",
          [NSNumber numberWithBool:YES], @"ShowStatusBar",
          [NSNumber numberWithBool:YES], @"ShowToolbar",
          [NSNumber numberWithInt:192], @"SidebarWidth", nil];
    }
    return defaults;
}

+ (DSStoreEntry *)iconViewEntryForInfo:(DSStoreInfo *)info key:(NSString *)key
                              existing:(DSStoreEntry *)existing
{
    NSMutableDictionary *owned = [NSMutableDictionary dictionary];
    if ([info hasIconSize]) {
        [owned setObject:[NSNumber numberWithDouble:[info iconSize]] forKey:@"iconSize"];
    }
    if ([info hasIconTextSize]) {
        [owned setObject:[NSNumber numberWithDouble:[info iconTextSize]] forKey:@"textSize"];
    }
    if ([info hasGridSpacing] && [info gridSpacing] > 0) {
        [owned setObject:[NSNumber numberWithDouble:[info gridSpacing]] forKey:@"gridSpacing"];
    }
    if ([info arrangeBy]) {
        [owned setObject:[info arrangeBy] forKey:@"arrangeBy"];
    }
    if ([info hasLabelPosition]) {
        [owned setObject:[NSNumber numberWithBool:([info labelPosition] == DSStoreLabelPositionBottom)]
                  forKey:@"labelOnBottom"];
    }
    if ([info hasShowItemInfo]) {
        [owned setObject:[NSNumber numberWithBool:[info showItemInfo]] forKey:@"showItemInfo"];
    }
    if ([info hasShowIconPreview]) {
        [owned setObject:[NSNumber numberWithBool:[info showIconPreview]] forKey:@"showIconPreview"];
    }
    if ([info hasScrollPosition]) {
        [owned setObject:[NSNumber numberWithDouble:[info scrollPosition].x] forKey:@"scrollPositionX"];
        [owned setObject:[NSNumber numberWithDouble:[info scrollPosition].y] forKey:@"scrollPositionY"];
    }
    if ([info backgroundType] == DSStoreBackgroundColor && [info backgroundColor]) {
        NSColor *rgb = [[info backgroundColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        [owned setObject:[NSNumber numberWithInt:1] forKey:@"backgroundType"];
        [owned setObject:[NSNumber numberWithDouble:[rgb redComponent]] forKey:@"backgroundColorRed"];
        [owned setObject:[NSNumber numberWithDouble:[rgb greenComponent]] forKey:@"backgroundColorGreen"];
        [owned setObject:[NSNumber numberWithDouble:[rgb blueComponent]] forKey:@"backgroundColorBlue"];
    } else if ([info backgroundType] == DSStoreBackgroundDefault) {
        [owned setObject:[NSNumber numberWithInt:0] forKey:@"backgroundType"];
    }
    /* A picture is backgroundType 2 with an alias record Finder resolves by
     * its HFS path [O:E12]; without one the stored type and alias are left as
     * they are (the path still goes into "pict" for us). */
    if ([info backgroundType] == DSStoreBackgroundPicture && [info backgroundImageAlias]) {
        [owned setObject:[NSNumber numberWithInt:2] forKey:@"backgroundType"];
        [owned setObject:[info backgroundImageAlias] forKey:@"backgroundImageAlias"];
    }
    [owned setObject:[NSNumber numberWithInt:0] forKey:@"viewOptionsVersion"];
    return mergedPlistEntry(key, @"icvp", existing, finderIconViewDefaults(), owned);
}

+ (DSStoreEntry *)listViewEntryForInfo:(DSStoreInfo *)info key:(NSString *)key
                              existing:(DSStoreEntry *)existing
{
    NSMutableDictionary *owned = [NSMutableDictionary dictionary];
    if ([info hasSortColumn] && [info sortColumn]) {
        [owned setObject:[info sortColumn] forKey:@"sortColumn"];
    }
    if ([info hasListTextSize] && [info listTextSize] > 0) {
        [owned setObject:[NSNumber numberWithDouble:[info listTextSize]] forKey:@"textSize"];
    }
    if ([info hasListIconSize] && [info listIconSize] > 0) {
        [owned setObject:[NSNumber numberWithDouble:[info listIconSize]] forKey:@"iconSize"];
    }
    if ([info hasUseRelativeDates]) {
        [owned setObject:[NSNumber numberWithBool:[info useRelativeDates]] forKey:@"useRelativeDates"];
    }
    if ([info hasCalculateAllSizes]) {
        [owned setObject:[NSNumber numberWithBool:[info calculateAllSizes]] forKey:@"calculateAllSizes"];
    }

    /* Merge column by column, so a key Finder keeps inside one column's
     * dictionary survives as well.  A stored "columns" in the array form older
     * Workspace versions wrote is replaced by Finder's dictionary form. */
    NSMutableDictionary *columns = [NSMutableDictionary dictionaryWithDictionary:finderListColumnDefaults()];
    id storedColumns = [plistOfEntry(existing) objectForKey:@"columns"];
    NSMutableSet *ids = [NSMutableSet setWithArray:[columns allKeys]];
    if ([storedColumns isKindOfClass:[NSDictionary class]]) {
        [ids addObjectsFromArray:[storedColumns allKeys]];
    }
    [ids addObjectsFromArray:[[info listColumns] allKeys]];
    for (NSString *columnId in ids) {
        NSMutableDictionary *col = [NSMutableDictionary dictionary];
        [col addEntriesFromDictionary:[columns objectForKey:columnId]];
        if ([storedColumns isKindOfClass:[NSDictionary class]]
            && [[storedColumns objectForKey:columnId] isKindOfClass:[NSDictionary class]]) {
            [col addEntriesFromDictionary:[storedColumns objectForKey:columnId]];
        }
        [col addEntriesFromDictionary:[[info listColumns] objectForKey:columnId]];
        [columns setObject:col forKey:columnId];
    }
    [owned setObject:columns forKey:@"columns"];
    [owned removeObjectForKey:@"ascending"];

    NSMutableDictionary *defaults = [NSMutableDictionary dictionaryWithDictionary:finderListViewDefaults()];
    DSStoreEntry *e = mergedPlistEntry(key, @"lsvp", existing, defaults, owned);
    /* The top-level "ascending" of older Workspace versions would contradict
     * the per-column direction now written. */
    NSMutableDictionary *plist = [NSMutableDictionary dictionaryWithDictionary:plistOfEntry(e)];
    if ([plist objectForKey:@"ascending"] == nil) {
        return e;
    }
    [plist removeObjectForKey:@"ascending"];
    return [DSStoreEntry plistEntryForFile:key code:@"lsvp" dictionary:plist];
}

+ (DSStoreEntry *)windowEntryForInfo:(DSStoreInfo *)info key:(NSString *)key
                            existing:(DSStoreEntry *)existing
{
    NSMutableDictionary *owned = [NSMutableDictionary dictionary];
    /* GNUstep content rect -> whole window, bottom-left origin [O:E7]. */
    NSRect frame = [info windowFrame];
    frame.size.height += DSStoreInfoFinderTitleBarHeight;
    [owned setObject:[NSString stringWithFormat:@"{{%d, %d}, {%d, %d}}",
                        (int)round(frame.origin.x), (int)round(frame.origin.y),
                        (int)round(frame.size.width), (int)round(frame.size.height)]
              forKey:@"WindowBounds"];
    if ([info hasSidebarWidth] && [info sidebarWidth] > 0) {
        [owned setObject:[NSNumber numberWithInt:[info sidebarWidth]] forKey:@"SidebarWidth"];
    }
    if ([info hasShowToolbar]) {
        [owned setObject:[NSNumber numberWithBool:[info showToolbar]] forKey:@"ShowToolbar"];
    }
    if ([info hasShowStatusBar]) {
        [owned setObject:[NSNumber numberWithBool:[info showStatusBar]] forKey:@"ShowStatusBar"];
    }
    if ([info hasShowPathbar]) {
        [owned setObject:[NSNumber numberWithBool:[info showPathbar]] forKey:@"ShowPathbar"];
    }
    if ([info hasShowSidebar]) {
        [owned setObject:[NSNumber numberWithBool:[info showSidebar]] forKey:@"ShowSidebar"];
    }
    return mergedPlistEntry(key, @"bwsp", existing, finderWindowDefaults(), owned);
}

+ (void)writeFinderViewRecordsForInfo:(DSStoreInfo *)info
                                  key:(NSString *)key
                              toStore:(DSStore *)store
{
    /* Only a view the user chose for this folder is stored; without vstl
     * Finder uses its global last-used view [O:E5]. */
    if ([info hasViewStyle]) {
        DSStoreEntry *e = [DSStoreEntry viewStyleEntryForFile:key
                                                        style:viewStyleCode([info viewStyle])];
        if (e) [store setEntry:e];
    }
    /* Finder has no WindowBounds without a window; a bwsp without one is not
     * written (whether Finder takes one is OPEN). */
    if ([info hasWindowFrame]) {
        DSStoreEntry *e = [self windowEntryForInfo:info key:key
                                          existing:[store entryForFilename:key code:@"bwsp"]];
        if (e) [store setEntry:e];
    }
    if ([info hasIconViewOptions]) {
        DSStoreEntry *e = [self iconViewEntryForInfo:info key:key
                                            existing:[store entryForFilename:key code:@"icvp"]];
        if (e) [store setEntry:e];
    }
    if ([info hasListViewOptions]) {
        DSStoreEntry *e = [self listViewEntryForInfo:info key:key
                                            existing:[store entryForFilename:key code:@"lsvp"]];
        if (e) [store setEntry:e];
    }
}

+ (void)writeStoreEntriesForInfo:(DSStoreInfo *)info
                             key:(NSString *)key
                         toStore:(DSStore *)store
{
    [self writeFinderViewRecordsForInfo:info key:key toStore:store];

    /* --- Pre-10.6 records, kept for older readers --- */

    /* Icon size - patch the existing icvo if present, preserving unknown
     * fields (arrangement, flags, future trailing bytes). */
    if ([info hasIconSize] && [info iconSize] > 0 && [info iconSize] <= 512) {
        DSStoreEntry *existing = [store entryForFilename: key code: @"icvo"];
        DSStoreEntry *e = [DSStoreEntry iconSizeEntryForFile: key
                                                        size: [info iconSize]
                                                  preserving: existing];
        if (e) [store setEntry: e];
    }

    if ([info hasIconArrangement]) {
        int arr = ([info iconArrangement] == DSStoreIconArrangementGrid) ? 1 : 0;
        DSStoreEntry *e = [DSStoreEntry iconArrangementEntryForFile: key arrangement: arr];
        if (e) [store setEntry: e];
    }

    if ([info hasLabelPosition]) {
        int pos = ([info labelPosition] == DSStoreLabelPositionBottom) ? 0 : 1;
        DSStoreEntry *e = [DSStoreEntry labelPositionEntryForFile: key position: pos];
        if (e) [store setEntry: e];
    }

    if ([info hasGridSpacing] && [info gridSpacing] > 0) {
        DSStoreEntry *e = [DSStoreEntry gridSpacingEntryForFile: key
                                                        spacing: (int)[info gridSpacing]];
        if (e) [store setEntry: e];
    }

    /* Background color - patch existing BKGD, preserving tag/reserved bytes */
    if ([info backgroundType] == DSStoreBackgroundColor && [info backgroundColor]) {
        CGFloat r, g, b, a;
        [[[info backgroundColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace]
          getRed: &r green: &g blue: &b alpha: &a];
        DSStoreEntry *existing = [store entryForFilename: key code: @"BKGD"];
        DSStoreEntry *e = [DSStoreEntry backgroundColorEntryForFile: key
                                                                red: (int)(r * 65535.0)
                                                              green: (int)(g * 65535.0)
                                                               blue: (int)(b * 65535.0)
                                                          preserving: existing];
        if (e) [store setEntry: e];
    }

    /* Background image: BKGD PctB plus the path in a "pict" ustr.  10.6
     * ignores both [O:E12]; they are kept as the path form older Workspace
     * versions read. */
    if ([info backgroundType] == DSStoreBackgroundPicture && [info backgroundImagePath]) {
        DSStoreEntry *e = [DSStoreEntry backgroundImageEntryForFile: key
                                                          imagePath: [info backgroundImagePath]];
        if (e) [store setEntry: e];
        DSStoreEntry *pict = [[[DSStoreEntry alloc] initWithFilename: key
                                                                code: @"pict"
                                                                type: @"ustr"
                                                               value: [info backgroundImagePath]]
                               autorelease];
        [store setEntry: pict];
    }

    if ([info hasSidebarWidth]) {
        DSStoreEntry *e = [DSStoreEntry sidebarWidthEntryForFile: key width: [info sidebarWidth]];
        if (e) [store setEntry: e];
    }

    /* fwi0 - patch existing so trailing bytes written by Finder are kept. */
    if ([info hasWindowFrame]) {
        NSRect dsFrame = [info dsStoreWindowFrameForScreen: [DSStoreInfo safeMainScreen]];
        DSStoreEntry *oldFwi0 = [store entryForFilename: key code: @"fwi0"];
        DSStoreEntry *fwi0 = [DSStoreEntry windowGeometryEntryForFile: key
                                                                 rect: dsFrame
                                                            viewStyle: viewStyleCode([info viewStyle])
                                                          preserving: oldFwi0];
        if (fwi0) [store setEntry: fwi0];
    }

    /* --- Per-file entries --- */
    /* -allIconInfo hands out a copy, so asking for it per file copied the
       whole dictionary once per file: a folder of a few thousand icons cost
       hundreds of megabytes and seconds of work while it was saved. */
    NSDictionary *iconInfo = [info allIconInfo];

    for (NSString *filename in iconInfo) {
        [self writeIconInfo: [iconInfo objectForKey: filename]
                    forFile: filename
                    toStore: store];
    }
}

- (BOOL)hasAnyIconPositions
{
    for (DSStoreIconInfo *info in [_iconInfoDict allValues]) {
        if (info.hasPosition) {
            return YES;
        }
    }
    return NO;
}

- (NSArray *)filenamesWithPositions
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *filename in _iconInfoDict) {
        DSStoreIconInfo *info = [_iconInfoDict objectForKey:filename];
        if (info.hasPosition) {
            [result addObject:filename];
        }
    }
    return result;
}

#pragma mark - Coordinate Conversion

/* Every window rect this object holds is in GNUstep screen coordinates
   (origin bottom-left), whatever it was loaded from: the .DS_Store fwi0/bwsp
   rect, the folder FinderInfo or a viewer's own prefs all pass through
   +gnustepRectFromDSStoreRect: on the way in.  One convention throughout is
   what keeps a load-modify-save cycle from flipping the window: reading a
   stored rect and writing it back out again used to hand the top-left value
   to the save-time flip a second time, so the window came back mirrored
   about the middle of the screen after something rewrote the record.

   Both rects exclude the window decoration, matching the fwi0/bwsp format
   (the .DS_Store rect is the content area); callers turn it into a full
   frame with -frameRectForContentRect:. */
+ (NSRect)gnustepRectFromDSStoreRect:(NSRect)dsRect
{
  CGFloat screenHeight = [[DSStoreInfo safeMainScreen] frame].size.height;

  return NSMakeRect(dsRect.origin.x,
                    screenHeight - dsRect.origin.y - dsRect.size.height,
                    dsRect.size.width, dsRect.size.height);
}

- (NSRect)gnustepWindowFrameForScreen:(NSScreen *)screen
{
    if (!_hasWindowFrame) {
        return NSZeroRect;
    }

    return _windowFrame;
}

- (NSRect)dsStoreWindowFrameForScreen:(NSScreen *)screen
{
    if (!_hasWindowFrame) {
        return NSZeroRect;
    }

    /* Inverse of -gnustepWindowFrameForScreen:: the receiver's GNUstep
     * CONTENT rect (origin bottom-left) becomes the .DS_Store content-area
     * rect (origin top-left, y is the top edge measured downward).  Both
     * rects exclude the window decoration, matching the fwi0/bwsp format.
     * Do NOT pass a full frame here: the decoration height would then be
     * added a second time on restore (frameRectForContentRect:), making the
     * window grow and drift upward every open/close cycle. */
    if (screen == nil) {
      screen = [DSStoreInfo safeMainScreen];
    }
    CGFloat screenHeight = [screen frame].size.height;
    CGFloat dsStoreTop = screenHeight - _windowFrame.origin.y - _windowFrame.size.height;

    NSRect result = NSMakeRect(_windowFrame.origin.x, dsStoreTop,
                               _windowFrame.size.width, _windowFrame.size.height);


    return result;
}

+ (NSScreen *)safeMainScreen
{
  @try {
    return [NSScreen mainScreen];
  } @catch (NSException *e) {
    return nil;
  }
}

- (NSPoint)gnustepPositionForDSStorePoint:(NSPoint)dsPoint 
                           viewHeight:(CGFloat)viewHeight 
                           iconHeight:(CGFloat)iconHeight
{
    // Delegate to DSStore class method for .DS_Store interoperability coordinate conversion
    return [DSStore gnustepPointFromDSStorePoint:dsPoint viewHeight:viewHeight iconHeight:iconHeight];
}

#pragma mark - Writing / Saving

- (BOOL)save
{
  return [self saveToPath:[_directoryPath stringByAppendingPathComponent:@".DS_Store"]];
}

- (BOOL)saveToPath:(NSString *)dsStorePath
{
  if (!dsStorePath || [dsStorePath length] == 0) return NO;


  /* Build the DSStore object with all current settings */
  DSStore *store = [DSStore createStoreAtPath:dsStorePath withEntries:nil];
  if (!store) {
    return NO;
  }

  [store load];  /* Load existing entries so we merge, not replace */

  /* --- Directory-level + per-file entries (keyed by ".") --- */
  [DSStoreInfo writeStoreEntriesForInfo: self
                                    key: @"."
                                toStore: store];

  /* Prune ghost per-file entries on write: remove Iloc/lclr/cmmt entries for
   * files that are no longer on-disk children of this directory (renamed,
   * removed, or localized standard-folder names written by a foreign Finder).
   * Leaving them would collide with a live file that now has the same
   * position; the folder's own record ("." / the path) is kept. */
  [DSStoreInfo pruneNonChildEntriesInStore: store
                              forDirectory: _directoryPath
                                  keepPath: @"."];

  /* --- Write atomically --- */
  BOOL saved = [store save];
  if (saved) {
  } else {
  }

  /* Mirror per-folder view style + window geometry into the folder's own
   * com.apple.FinderInfo DInfo (the classic / spatial macOS channel) so the
   * values interoperate with Finder on systems that read it, and so Gershwin's
   * own spatial viewer persists them.  Best-effort only: failures (e.g. a
   * filesystem without xattr support) are logged and ignored; .DS_Store
   * remains the primary on-disk channel.  Only written when we actually have a
   * value, to avoid stamping a spurious zeroed FinderInfo on folders we know
   * nothing about. */
  if (saved && (_hasViewStyle || _hasWindowFrame)) {
    GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: _directoryPath];
    if (md == nil)
      md = [[[GSFileMetadata alloc] init] autorelease];
    if (md != nil) {
      if (_hasViewStyle) {
        NSString *styleStr = @"icnv";
        switch (_viewStyle) {
          case DSStoreViewStyleIcon:     styleStr = @"icnv"; break;
          case DSStoreViewStyleList:     styleStr = @"Nlsv"; break;
          case DSStoreViewStyleColumn:   styleStr = @"clmv"; break;
          case DSStoreViewStyleGallery:  styleStr = @"glyv"; break;
          case DSStoreViewStyleCoverflow:styleStr = @"Flwv"; break;
        }
        [md setViewStyleCodeForDirectory: styleStr];
      }
      if (_hasWindowFrame) {
        NSRect dsFrame = [self dsStoreWindowFrameForScreen:
                            [DSStoreInfo safeMainScreen]];
        [md setWindowBoundsForDirectory: dsFrame];
      }
      NSError *fiErr = nil;
      if ([md writeToFileAtPath: _directoryPath error: &fiErr] == NO && fiErr) {
        NSLog(@"DSStoreInfo: FinderInfo write failed for %@: %@",
              _directoryPath, fiErr);
      }
    }
  }

  return saved;
}

- (BOOL)saveToParentStore
{
  NSString *parentStorePath = [DSStoreInfo parentStorePathForDirectory: _directoryPath];
  if (parentStorePath == nil || [self hasFinderViewRecords] == NO) {
    return NO;
  }
  NSString *parentDir = [parentStorePath stringByDeletingLastPathComponent];
  if ([[NSFileManager defaultManager] isWritableFileAtPath: parentDir] == NO) {
    return NO;
  }

  DSStore *store = [DSStore createStoreAtPath: parentStorePath withEntries: nil];
  if (store == nil) {
    return NO;
  }
  /* Merge into what the parent already holds: its own icons and the records
   * of its other subfolders are not ours. */
  [store load];
  [DSStoreInfo writeFinderViewRecordsForInfo: self
                                         key: [_directoryPath lastPathComponent]
                                     toStore: store];
  return [store save];
}

- (void)takeValuesFromViewerPrefs:(NSDictionary *)prefs
{
  [self takeValuesFromViewerPrefs:prefs preservingExisting:NO];
}

- (void)takeValuesFromViewerPrefs:(NSDictionary *)prefs
                preservingExisting:(BOOL)preserve
{
  if (!prefs) return;

  /* Window geometry.  We persist the CONTENT rect (the area inside the title
   * bar / border), because .DS_Store fwi0/bwsp stores the content area per
   * the DS_Store format notes (MozillaWiki, forensiclunch).  Callers supply
   * it either as a GNUstep NSStringFromRect value "{{x, y}, {w, h}}" or as a
   * legacy "<x> <y> <w> <h>" space-separated string.  Both parse here; the
   * rect is interpreted in GNUstep screen coords (bottom-left origin).  The
   * final flip to DS_Store top-left coords happens in
   * dsStoreWindowFrameForScreen: when writing. */
  NSString *geo = [prefs objectForKey:@"geometry"];
  if (geo && !(preserve && _hasWindowFrame)) {
    NSRect parsed = NSRectFromString(geo);
    if (parsed.size.width > 0 && parsed.size.height > 0) {
      _windowFrame = parsed;
      _hasWindowFrame = YES;
    } else {
      NSScanner *scanner = [NSScanner scannerWithString: geo];
      int x = 0, y = 0, w = 0, h = 0;
      BOOL ok = ([scanner scanInt: &x]
                 && [scanner scanInt: &y]
                 && [scanner scanInt: &w]
                 && [scanner scanInt: &h]);
      if (ok && w > 0 && h > 0) {
        _windowFrame = NSMakeRect(x, y, w, h);
        _hasWindowFrame = YES;
      }
    }
  }

  /* View type */
  NSString *vt = [prefs objectForKey:@"viewtype"];
  if (vt && !(preserve && _hasViewStyle)) {
    if ([vt isEqualToString:@"Icon"]) {
      _viewStyle = DSStoreViewStyleIcon;
    } else if ([vt isEqualToString:@"List"]) {
      _viewStyle = DSStoreViewStyleList;
    } else if ([vt isEqualToString:@"Browser"]) {
      _viewStyle = DSStoreViewStyleColumn;
    }
    _hasViewStyle = YES;
  }

  /* Icon size */
  id iconSizeObj = [prefs objectForKey:@"iconsize"];
  if (iconSizeObj && !(preserve && _hasIconSize)) {
    int sz = [iconSizeObj intValue];
    if (sz > 0 && sz <= 512) {
      _iconSize = sz;
      _hasIconSize = YES;
    }
  }

  /* Icon position (label position) */
  NSString *ip = [prefs objectForKey:@"iconspos"];
  if (ip && !(preserve && _hasLabelPosition)) {
    _labelPosition = [ip isEqualToString:@"bottom"] ? DSStoreLabelPositionBottom
                     : DSStoreLabelPositionRight;
    _hasLabelPosition = YES;
  }

  /* Icon arrangement */
  NSString *ia = [prefs objectForKey:@"iconsarr"];
  if (ia && !(preserve && _arrangeBy != nil)) {
    [self setArrangeBy: [ia isEqualToString:@"grid"] ? @"grid" : @"none"];
  }

  /* Sidebar width */
  id sw = [prefs objectForKey:@"sidebarwidth"];
  if (sw && !(preserve && _hasSidebarWidth)) {
    _sidebarWidth = [sw intValue];
    _hasSidebarWidth = YES;
  }

  /* List view options are not taken from the prefs: they follow the
   * list view's own user-change notification (GWFolderViewOptions). */
}

- (void)resetToDefaults
{
  _hasWindowFrame = NO;
  _hasViewStyle = NO;
  _hasIconSize = NO;
  _hasLabelPosition = NO;
  _hasGridSpacing = NO;
  _hasSidebarWidth = NO;
  _hasListTextSize = NO;
  _hasListIconSize = NO;
  _hasSortColumn = NO;
  _hasIconTextSize = NO;
  _hasShowItemInfo = NO;
  _showIconPreview = YES;
  _hasShowIconPreview = NO;
  _hasScrollPosition = NO;
  _hasShowToolbar = NO;
  _hasShowStatusBar = NO;
  _hasShowPathbar = NO;
  _hasShowSidebar = NO;
  _hasUseRelativeDates = NO;
  _hasCalculateAllSizes = NO;
  _sortAscending = YES;

  _backgroundType = DSStoreBackgroundDefault;
  [_backgroundColor release];  _backgroundColor = nil;
  [_backgroundImagePath release];  _backgroundImagePath = nil;
  [_backgroundImageAlias release];  _backgroundImageAlias = nil;
  [_sortColumn release];  _sortColumn = nil;
  [_arrangeBy release];  _arrangeBy = nil;
  [_listColumns release];  _listColumns = nil;
  [_iconInfoDict removeAllObjects];

  _loaded = NO;
}

- (void)mergeMissingFieldsFromInfo:(DSStoreInfo *)other
{
  if (other == nil) return;

  if (!_hasWindowFrame && [other hasWindowFrame]) {
    _windowFrame = [other windowFrame];
    _hasWindowFrame = YES;
  }
  if (!_hasViewStyle && [other hasViewStyle]) {
    _viewStyle = [other viewStyle];
    _hasViewStyle = YES;
  }
  if (!_hasIconSize && [other hasIconSize]) {
    _iconSize = [other iconSize];
    _hasIconSize = YES;
  }
  if (_arrangeBy == nil && [other arrangeBy]) {
    [self setArrangeBy: [other arrangeBy]];
  }
  if (!_hasIconTextSize && [other hasIconTextSize]) {
    _iconTextSize = [other iconTextSize];
    _hasIconTextSize = YES;
  }
  if (!_hasShowItemInfo && [other hasShowItemInfo]) {
    _showItemInfo = [other showItemInfo];
    _hasShowItemInfo = YES;
  }
  if (!_hasShowIconPreview && [other hasShowIconPreview]) {
    _showIconPreview = [other showIconPreview];
    _hasShowIconPreview = YES;
  }
  if (!_hasScrollPosition && [other hasScrollPosition]) {
    _scrollPosition = [other scrollPosition];
    _hasScrollPosition = YES;
  }
  if (!_hasShowToolbar && [other hasShowToolbar]) {
    _showToolbar = [other showToolbar];
    _hasShowToolbar = YES;
  }
  if (!_hasShowStatusBar && [other hasShowStatusBar]) {
    _showStatusBar = [other showStatusBar];
    _hasShowStatusBar = YES;
  }
  if (!_hasShowPathbar && [other hasShowPathbar]) {
    _showPathbar = [other showPathbar];
    _hasShowPathbar = YES;
  }
  if (!_hasShowSidebar && [other hasShowSidebar]) {
    _showSidebar = [other showSidebar];
    _hasShowSidebar = YES;
  }
  if (!_hasUseRelativeDates && [other hasUseRelativeDates]) {
    _useRelativeDates = [other useRelativeDates];
    _hasUseRelativeDates = YES;
  }
  if (!_hasCalculateAllSizes && [other hasCalculateAllSizes]) {
    _calculateAllSizes = [other calculateAllSizes];
    _hasCalculateAllSizes = YES;
  }
  if (!_hasLabelPosition && [other hasLabelPosition]) {
    _labelPosition = [other labelPosition];
    _hasLabelPosition = YES;
  }
  if (!_hasGridSpacing && [other hasGridSpacing]) {
    _gridSpacing = [other gridSpacing];
    _hasGridSpacing = YES;
  }
  if (!_hasSidebarWidth && [other hasSidebarWidth]) {
    _sidebarWidth = [other sidebarWidth];
    _hasSidebarWidth = YES;
  }
  if (!_hasListTextSize && [other hasListTextSize]) {
    _listTextSize = [other listTextSize];
    _hasListTextSize = YES;
  }
  if (!_hasListIconSize && [other hasListIconSize]) {
    _listIconSize = [other listIconSize];
    _hasListIconSize = YES;
  }
  if (_listColumns == nil && [other listColumns]) {
    [self setListColumns: [other listColumns]];
  }
  if (!_hasSortColumn && [other hasSortColumn]) {
    [_sortColumn release];
    _sortColumn = [[other sortColumn] copy];
    _hasSortColumn = YES;
    if ([[_listColumns objectForKey: _sortColumn] objectForKey: @"ascending"] == nil) {
      _sortAscending = [other sortAscending];
    }
  }

  /* Background: only copy when the receiver has none at all. */
  if ((_backgroundType == DSStoreBackgroundDefault && _backgroundColor == nil)
      && [other backgroundType] != DSStoreBackgroundDefault) {
    _backgroundType = [other backgroundType];
    [_backgroundColor release];
    _backgroundColor = [[other backgroundColor] retain];
    [_backgroundImagePath release];
    _backgroundImagePath = [[other backgroundImagePath] copy];
    [self setBackgroundImageAlias: [other backgroundImageAlias]];
  }

  /* Per-file icon info: for entries the receiver lacks entirely, copy them
   * wholesale; for entries present in both, fill in sub-fields the receiver
   * did not touch (so e.g. a label-color-only write keeps existing positions
   * and comments). */
  NSDictionary *otherIcons = [other allIconInfo];
  for (NSString *name in otherIcons) {
    DSStoreIconInfo *oi = [otherIcons objectForKey: name];
    DSStoreIconInfo *mine = [self iconInfoForFilename: name];
    if (mine == nil) {
      [self setIconInfo: oi forFilename: name];
    } else {
      if (![mine hasPosition] && [oi hasPosition]) {
        [mine setPosition: [oi position]];
        [mine setHasPosition: YES];
      }
      if ([mine comments] == nil && [oi comments]) {
        [mine setComments: [oi comments]];
      }
      if (![mine hasLabelColor] && [oi hasLabelColor]) {
        [mine setLabelColor: [oi labelColor]];
        [mine setHasLabelColor: YES];
      }
    }
  }
}

#pragma mark - Debugging

- (NSString *)debugDescription
{
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<DSStoreInfo: %@>\n", _directoryPath];
    [desc appendFormat:@"  loaded: %@\n", _loaded ? @"YES" : @"NO"];
    
    if (_hasWindowFrame) {
        [desc appendFormat:@"  windowFrame: %@\n", NSStringFromRect(_windowFrame)];
    }
    if (_hasViewStyle) {
        NSString *styleName = @"unknown";
        switch (_viewStyle) {
            case DSStoreViewStyleIcon: styleName = @"icon"; break;
            case DSStoreViewStyleList: styleName = @"list"; break;
            case DSStoreViewStyleColumn: styleName = @"column"; break;
            case DSStoreViewStyleGallery: styleName = @"gallery"; break;
            case DSStoreViewStyleCoverflow: styleName = @"coverflow"; break;
        }
        [desc appendFormat:@"  viewStyle: %@\n", styleName];
    }
    if (_hasIconSize) {
        [desc appendFormat:@"  iconSize: %d\n", _iconSize];
    }
    if (_arrangeBy) {
        [desc appendFormat:@"  arrangeBy: %@\n", _arrangeBy];
    }
    if (_hasLabelPosition) {
        [desc appendFormat:@"  labelPosition: %@\n",
         _labelPosition == DSStoreLabelPositionBottom ? @"bottom" : @"right"];
    }
    if (_backgroundColor) {
        [desc appendFormat:@"  backgroundColor: %@\n", _backgroundColor];
    }
    [desc appendFormat:@"  iconPositions: %lu files\n", (unsigned long)[self filenamesWithPositions].count];
    
    return desc;
}

@end
