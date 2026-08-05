/* DSStoreInfo.m
 *  
 * DS_Store information model for .DS_Store interoperability in Spatial mode.
 *
 */

#import "DSStoreInfo.h"
#import "DSStore.h"

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

@implementation DSStoreInfo

@synthesize directoryPath = _directoryPath;
@synthesize loaded = _loaded;
@synthesize windowFrame = _windowFrame;
@synthesize hasWindowFrame = _hasWindowFrame;
@synthesize viewStyle = _viewStyle;
@synthesize hasViewStyle = _hasViewStyle;
@synthesize iconSize = _iconSize;
@synthesize hasIconSize = _hasIconSize;
@synthesize iconArrangement = _iconArrangement;
@synthesize hasIconArrangement = _hasIconArrangement;
@synthesize labelPosition = _labelPosition;
@synthesize hasLabelPosition = _hasLabelPosition;
@synthesize gridSpacing = _gridSpacing;
@synthesize hasGridSpacing = _hasGridSpacing;
@synthesize backgroundType = _backgroundType;
@synthesize backgroundColor = _backgroundColor;
@synthesize backgroundImagePath = _backgroundImagePath;
@synthesize sidebarWidth = _sidebarWidth;
@synthesize hasSidebarWidth = _hasSidebarWidth;
@synthesize listTextSize = _listTextSize;
@synthesize hasListTextSize = _hasListTextSize;
@synthesize listIconSize = _listIconSize;
@synthesize hasListIconSize = _hasListIconSize;
@synthesize sortColumn = _sortColumn;
@synthesize hasSortColumn = _hasSortColumn;
@synthesize sortAscending = _sortAscending;
@synthesize columnWidths = _columnWidths;
@synthesize columnVisible = _columnVisible;

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

#pragma mark - Sort Column Conversion

+ (int)infoTypeForSortColumnName:(NSString *)columnName
{
    // DS_Store column names to FSNInfoType mapping
    // These are the standard macOS Finder column identifiers
    if (!columnName) return -1;
    
    if ([columnName isEqualToString:@"name"] || 
        [columnName isEqualToString:@"Name"]) {
        return 0;  // FSNInfoNameType
    }
    if ([columnName isEqualToString:@"kind"] || 
        [columnName isEqualToString:@"Kind"]) {
        return 1;  // FSNInfoKindType
    }
    if ([columnName isEqualToString:@"dateModified"] ||
        [columnName isEqualToString:@"Date Modified"] ||
        [columnName isEqualToString:@"modificationDate"]) {
        return 2;  // FSNInfoDateType
    }
    if ([columnName isEqualToString:@"size"] || 
        [columnName isEqualToString:@"Size"]) {
        return 3;  // FSNInfoSizeType
    }
    if ([columnName isEqualToString:@"owner"] || 
        [columnName isEqualToString:@"Owner"]) {
        return 4;  // FSNInfoOwnerType
    }
    if ([columnName isEqualToString:@"dateCreated"] ||
        [columnName isEqualToString:@"Date Created"] ||
        [columnName isEqualToString:@"creationDate"]) {
        return 2;  // Map to FSNInfoDateType (we don't have separate creation date)
    }
    if ([columnName isEqualToString:@"dateAdded"] ||
        [columnName isEqualToString:@"Date Added"]) {
        return 2;  // Map to FSNInfoDateType
    }
    
    return -1;  // Unknown column
}

+ (NSString *)sortColumnNameForInfoType:(int)infoType
{
    switch (infoType) {
        case 0:  // FSNInfoNameType
            return @"name";
        case 1:  // FSNInfoKindType
            return @"kind";
        case 2:  // FSNInfoDateType
            return @"dateModified";
        case 3:  // FSNInfoSizeType
            return @"size";
        case 4:  // FSNInfoOwnerType
            return @"owner";
        default:
            return @"name";
    }
}

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
        _iconArrangement = DSStoreIconArrangementNone;
        _hasIconArrangement = NO;
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
    [_iconInfoDict release];
    [_sortColumn release];
    [_columnWidths release];
    [_columnVisible release];
    [super dealloc];
}

#pragma mark - Loading

- (BOOL)load
{
    NSString *dsStorePath = [_directoryPath stringByAppendingPathComponent:@".DS_Store"];
    
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dsStorePath]) {
        return NO;
    }
    
    
    DSStore *store = [DSStore storeWithPath:dsStorePath];
    if (![store load]) {
        return NO;
    }
    
    
    // Get all entries to see what's available
    NSArray *allFilenames = [store allFilenames];
    
    // Process directory-level entries (filename = ".")
    [self loadDirectoryEntriesFromStore:store];
    
    // Process per-file entries (icon positions, comments, etc.)
    [self loadIconEntriesFromStore:store filenames:allFilenames];
    
    _loaded = YES;
    
    
    
    return YES;
}

- (BOOL)reload
{
    // Reset all state
    _hasWindowFrame = NO;
    _hasViewStyle = NO;
    _hasIconSize = NO;
    _hasIconArrangement = NO;
    _hasLabelPosition = NO;
    _hasGridSpacing = NO;
    _hasSidebarWidth = NO;
    _backgroundType = DSStoreBackgroundDefault;
    [_backgroundColor release]; _backgroundColor = nil;
    [_backgroundImagePath release]; _backgroundImagePath = nil;
    [_iconInfoDict removeAllObjects];
    _loaded = NO;
    
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
            [dataString release];
            
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

- (void)loadDirectoryEntriesFromStore:(DSStore *)store
{
    
    
    // IMPORTANT: Format Preferences for Interoperability
    // Modern .DS_Store files use binary plist formats which are preferred:
    //   - bwsp: Window settings (preferred over legacy fwi0)
    //   - icvp: Icon view settings (preferred over legacy icvo)
    //   - lsvp/lsvP: List view settings (preferred over legacy lsvo)
    // Background images are stored in icvp's backgroundImageAlias for modern files
    
    // Load window geometry - prefer modern format (bwsp) over legacy (fwi0)
    // bwsp: Modern binary plist with WindowBounds string and sidebar settings
    // fwi0: Legacy 16-byte binary format with window rect only
    [self loadBrowserWindowSettingsFromStore:store];  // Modern format (includes geometry)
    [self loadWindowGeometryFromStore:store];          // Legacy format (fallback)
    
    // Load view style (vstl)
    [self loadViewStyleFromStore:store];
    
    // Load icon view options - prefer modern format (icvp) over legacy (icvo)
    // icvp: Modern binary plist with comprehensive settings including backgrounds
    // icvo: Legacy 18-26 byte binary format with limited settings
    [self loadIconViewPlistFromStore:store];   // New format (try first)
    [self loadIconViewOptionsFromStore:store]; // Old format (fallback)
    
    
    // Load background settings (BKGD, bwsp)
    [self loadBackgroundFromStore:store];
    
    // Load sidebar width (fwsw)
    [self loadSidebarWidthFromStore:store];
    
    // Load list view settings (lsvp, lsvP, lsvo)
    [self loadListViewSettingsFromStore:store];
}

- (void)loadWindowGeometryFromStore:(DSStore *)store
{
    // fwi0: Legacy window geometry format (pre-10.6)
    // Only used as fallback if bwsp is not present
    // Modern .DS_Store files use bwsp with WindowBounds instead
    
    if (_hasWindowFrame) {
        return;
    }
    
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"fwi0"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        if ([data length] >= 16) {
            const uint8_t *bytes = (const uint8_t *)[data bytes];
            
            // fwi0 format: 16 bytes total
            // - Bytes 0-1: top (2-byte big-endian integer)
            // - Bytes 2-3: left (2-byte big-endian integer)
            // - Bytes 4-5: bottom (2-byte big-endian integer)
            // - Bytes 6-7: right (2-byte big-endian integer)
            // - Bytes 8-11: view style (4CC: icnv/clmv/Nlsv/Flwv)
            // - Bytes 12-15: flags/unknown
            // These define the content area rect in .DS_Store screen coordinates
            
            uint16_t top    = (bytes[0] << 8) | bytes[1];
            uint16_t left   = (bytes[2] << 8) | bytes[3];
            uint16_t bottom = (bytes[4] << 8) | bytes[5];
            uint16_t right  = (bytes[6] << 8) | bytes[7];
            
            // Convert from top/left/bottom/right edges to x/y/width/height
            CGFloat x = left;
            CGFloat y = top;
            CGFloat width = right - left;
            CGFloat height = bottom - top;
            
            _windowFrame = NSMakeRect(x, y, width, height);
            _hasWindowFrame = YES;
            
            
        } else {
        }
    } else {
    }
}

- (void)loadViewStyleFromStore:(DSStore *)store
{
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"vstl"];
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
        } else {
        }
    } else {
    }
}

- (void)loadBrowserWindowSettingsFromStore:(DSStore *)store
{
    // bwsp: Modern browser window settings format (10.6+)
    // Binary plist containing WindowBounds, sidebar settings, toolbar visibility, etc.
    // This is the preferred source for window geometry on modern systems
    
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"bwsp"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        
        NSError *error = nil;
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
        if (plist && [plist isKindOfClass:[NSDictionary class]]) {
            // Extract WindowBounds if present
            NSString *windowBounds = [plist objectForKey:@"WindowBounds"];
            if (windowBounds && [windowBounds isKindOfClass:[NSString class]]) {
                // Parse WindowBounds string format: "{{x, y}, {width, height}}"
                NSRect rect = NSRectFromString(windowBounds);
                if (rect.size.width > 0 && rect.size.height > 0) {
                    _windowFrame = rect;
                    _hasWindowFrame = YES;
                } else {
                }
            }
            
            // Extract sidebar width
            id sidebarWidthObj = [plist objectForKey:@"SidebarWidth"];
            if (sidebarWidthObj) {
                _sidebarWidth = [sidebarWidthObj intValue];
                _hasSidebarWidth = YES;
            }
            
        } else {
        }
    } else {
    }
}

- (void)loadIconViewOptionsFromStore:(DSStore *)store
{
    // icvo: Legacy icon view options format (pre-10.6)
    // Only used as fallback if icvp is not present
    // Modern .DS_Store files use icvp binary plist instead
    
    // Skip if we already have settings from icvp (new format)
    if (_hasIconSize && _hasIconArrangement && _hasLabelPosition) {
        return;
    }
    
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"icvo"];
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
                if (len >= 18) {
                    char arr[5] = {bytes[14], bytes[15], bytes[16], bytes[17], 0};
                    if (strcmp(arr, "none") == 0) {
                        _iconArrangement = DSStoreIconArrangementNone;
                        _hasIconArrangement = YES;
                    } else if (strcmp(arr, "grid") == 0) {
                        _iconArrangement = DSStoreIconArrangementGrid;
                        _hasIconArrangement = YES;
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
                if (strcmp(arr, "none") == 0) {
                    _iconArrangement = DSStoreIconArrangementNone;
                    _hasIconArrangement = YES;
                } else if (strcmp(arr, "grid") == 0) {
                    _iconArrangement = DSStoreIconArrangementGrid;
                    _hasIconArrangement = YES;
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

- (void)loadIconViewPlistFromStore:(DSStore *)store
{
    // icvp: Modern icon view properties format (10.6+)
    // Binary plist with comprehensive icon view settings
    // Supersedes the older icvo binary format
    
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"icvp"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        
        // Try to parse as binary plist
        NSError *error = nil;
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
        if (plist && [plist isKindOfClass:[NSDictionary class]]) {
            
            // Extract icon size
            id sizeObj = [plist objectForKey:@"iconSize"];
            if (sizeObj) {
                int size = [sizeObj intValue];
                if (size > 0 && size <= 512) {
                    _iconSize = size;
                    _hasIconSize = YES;
                }
            }
            
            // Extract arrangement
            id arrObj = [plist objectForKey:@"arrangeBy"];
            if (arrObj) {
                NSString *arr = [arrObj description];
                if ([arr isEqualToString:@"none"] || [arr isEqualToString:@"0"]) {
                    _iconArrangement = DSStoreIconArrangementNone;
                    _hasIconArrangement = YES;
                } else if ([arr isEqualToString:@"grid"]) {
                    _iconArrangement = DSStoreIconArrangementGrid;
                    _hasIconArrangement = YES;
                }
            }
            
            // Extract grid spacing
            id spacingObj = [plist objectForKey:@"gridSpacing"];
            if (spacingObj) {
                _gridSpacing = [spacingObj floatValue];
                _hasGridSpacing = YES;
            }
            
            // Extract label position
            id labelObj = [plist objectForKey:@"labelOnBottom"];
            if (labelObj) {
                _labelPosition = [labelObj boolValue] ? DSStoreLabelPositionBottom : DSStoreLabelPositionRight;
                _hasLabelPosition = YES;
            }
            
            // Extract background settings
            // Check background type first
            id bgTypeObj = [plist objectForKey:@"backgroundType"];
            int bgType = bgTypeObj ? [bgTypeObj intValue] : 0;
            
            if (bgType == 2) {
                // Picture background
                _backgroundType = DSStoreBackgroundPicture;
                
                // Try to extract background image alias
                id bgImageAlias = [plist objectForKey:@"backgroundImageAlias"];
                if (bgImageAlias && [bgImageAlias isKindOfClass:[NSData class]]) {
                    // This is an alias record - try to resolve it to a path
                    NSData *aliasData = (NSData *)bgImageAlias;
                    NSString *resolvedPath = [self resolveAliasData:aliasData relativeTo:_directoryPath];
                    if (resolvedPath) {
                        [_backgroundImagePath release];
                        _backgroundImagePath = [resolvedPath copy];
                    } else {
                    }
                }
            } else if (bgType == 1) {
                // Color background
                id bgColorObj = [plist objectForKey:@"backgroundColorRed"];
                if (bgColorObj) {
                    CGFloat r = [[plist objectForKey:@"backgroundColorRed"] floatValue];
                    CGFloat g = [[plist objectForKey:@"backgroundColorGreen"] floatValue];
                    CGFloat b = [[plist objectForKey:@"backgroundColorBlue"] floatValue];
                    _backgroundColor = [[NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0] retain];
                    _backgroundType = DSStoreBackgroundColor;
                }
            } else {
            }
            
        } else {
        }
    } else {
    }
}

- (void)loadBackgroundFromStore:(DSStore *)store
{
    // Check BKGD entry first
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"BKGD"];
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
                
                // Use DSStore's method to resolve the background image path
                NSString *imagePath = [store backgroundImagePathForDirectory];
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

- (void)loadListViewSettingsFromStore:(DSStore *)store
{
    // List view settings: Prefer modern plist formats over legacy binary
    // lsvp/lsvP: Modern binary plist (10.6+) - try first
    // lsvo: Legacy 76-byte binary format (pre-10.6) - fallback
    
    // Try modern binary plist formats first (lsvp, lsvP)
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"lsvp"];
    if (!entry) {
        entry = [store entryForFilename:@"." code:@"lsvP"];
    }
    
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        
        NSError *error = nil;
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
        if (plist && [plist isKindOfClass:[NSDictionary class]]) {
            
            // Text size (font size for list entries)
            id textSizeObj = [plist objectForKey:@"textSize"];
            if (textSizeObj && [textSizeObj respondsToSelector:@selector(intValue)]) {
                _listTextSize = [textSizeObj intValue];
                _hasListTextSize = YES;
            }
            
            // Icon size (small icon size in list view)
            id iconSizeObj = [plist objectForKey:@"iconSize"];
            if (iconSizeObj && [iconSizeObj respondsToSelector:@selector(intValue)]) {
                _listIconSize = [iconSizeObj intValue];
                _hasListIconSize = YES;
            }
            
            // Sort column - the column used for sorting
            id sortColumnObj = [plist objectForKey:@"sortColumn"];
            if (sortColumnObj && [sortColumnObj isKindOfClass:[NSString class]]) {
                [_sortColumn release];
                _sortColumn = [(NSString *)sortColumnObj copy];
                _hasSortColumn = YES;
            }
            
            // Sort ascending
            id ascendingObj = [plist objectForKey:@"ascending"];
            if (ascendingObj && [ascendingObj respondsToSelector:@selector(boolValue)]) {
                _sortAscending = [ascendingObj boolValue];
            } else {
                _sortAscending = YES;  // Default to ascending
            }
            
            // Column widths dictionary
            id columnsObj = [plist objectForKey:@"columns"];
            if (columnsObj && [columnsObj isKindOfClass:[NSArray class]]) {
                NSMutableDictionary *widths = [NSMutableDictionary dictionary];
                NSMutableDictionary *visible = [NSMutableDictionary dictionary];
                
                for (NSDictionary *col in (NSArray *)columnsObj) {
                    if ([col isKindOfClass:[NSDictionary class]]) {
                        NSString *identifier = [col objectForKey:@"identifier"];
                        if (identifier) {
                            // Column width
                            id widthObj = [col objectForKey:@"width"];
                            if (widthObj && [widthObj respondsToSelector:@selector(floatValue)]) {
                                [widths setObject:[NSNumber numberWithFloat:[widthObj floatValue]]
                                           forKey:identifier];
                            }
                            
                            // Column visibility
                            id visibleObj = [col objectForKey:@"visible"];
                            if (visibleObj && [visibleObj respondsToSelector:@selector(boolValue)]) {
                                [visible setObject:[NSNumber numberWithBool:[visibleObj boolValue]]
                                            forKey:identifier];
                            } else {
                                // Assume visible if not specified
                                [visible setObject:[NSNumber numberWithBool:YES] forKey:identifier];
                            }
                        }
                    }
                }
                
                if ([widths count] > 0) {
                    [_columnWidths release];
                    _columnWidths = [widths copy];
                }
                if ([visible count] > 0) {
                    [_columnVisible release];
                    _columnVisible = [visible copy];
                }
            }
        } else {
        }
    } else {
    }
    
    // Check for legacy lsvo format (76 bytes)
    entry = [store entryForFilename:@"." code:@"lsvo"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        // TODO: Parse legacy format if needed for older DS_Store files
    }
}


- (void)loadSidebarWidthFromStore:(DSStore *)store
{
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"fwsw"];
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

    NSArray *allFilenames = [store allFilenames];
    for (NSString *fn in allFilenames) {
        if ([fn isEqualToString: keepPath]) continue;
        if ([fn isEqualToString: @"/"]) continue;   /* volume-root record */
        if ([childSet containsObject: fn]) continue;  /* real child */
        [store removeAllEntriesForFilename: fn];
    }
}

+ (NSSet *)ownedDirectoryCodes
{
    /* The codes writeStoreEntriesForInfo: emits for a directory key.  Any
     * other 4CC under the same key (written by Finder) is not owned and must
     * survive a merge write. */
    return [NSSet setWithObjects:
              @"vstl", @"icvo", @"iarr", @"lblp", @"icsp",
              @"BKGD", @"fwsw", @"bwsp", @"fwi0", @"lsvp",
              nil];
}

+ (void)writeStoreEntriesForInfo:(DSStoreInfo *)info
                             key:(NSString *)key
                         toStore:(DSStore *)store
{
    /* --- Directory-level entries --- */

    /* View style */
    if ([info hasViewStyle]) {
        NSString *styleStr = @"icnv";
        switch ([info viewStyle]) {
            case DSStoreViewStyleIcon:     styleStr = @"icnv"; break;
            case DSStoreViewStyleList:     styleStr = @"Nlsv"; break;
            case DSStoreViewStyleColumn:   styleStr = @"clmv"; break;
            case DSStoreViewStyleGallery:  styleStr = @"glyv"; break;
            case DSStoreViewStyleCoverflow:styleStr = @"Flwv"; break;
        }
        DSStoreEntry *e = [DSStoreEntry viewStyleEntryForFile: key style: styleStr];
        if (e) [store setEntry: e];
    }

    /* Icon size - patch the existing icvo if present, preserving unknown
     * fields (arrangement, flags, future trailing bytes). */
    if ([info hasIconSize] && [info iconSize] > 0 && [info iconSize] <= 512) {
        DSStoreEntry *existing = [store entryForFilename: key code: @"icvo"];
        DSStoreEntry *e = [DSStoreEntry iconSizeEntryForFile: key
                                                        size: [info iconSize]
                                                  preserving: existing];
        if (e) [store setEntry: e];
    }

    /* Icon arrangement */
    if ([info hasIconArrangement]) {
        int arr = ([info iconArrangement] == DSStoreIconArrangementGrid) ? 1 : 0;
        DSStoreEntry *e = [DSStoreEntry iconArrangementEntryForFile: key arrangement: arr];
        if (e) [store setEntry: e];
    }

    /* Label position */
    if ([info hasLabelPosition]) {
        int pos = ([info labelPosition] == DSStoreLabelPositionBottom) ? 0 : 1;
        DSStoreEntry *e = [DSStoreEntry labelPositionEntryForFile: key position: pos];
        if (e) [store setEntry: e];
    }

    /* Grid spacing */
    if ([info hasGridSpacing] && [info gridSpacing] > 0) {
        DSStoreEntry *e = [DSStoreEntry gridSpacingEntryForFile: key
                                                        spacing: (int)[info gridSpacing]];
        if (e) [store setEntry: e];
    }

    /* Background color - patch existing BKGD, preserving tag/reserved bytes */
    if ([info backgroundType] == DSStoreBackgroundColor && [info backgroundColor]) {
        CGFloat r, g, b, a;
        [[info backgroundColor] getRed: &r green: &g blue: &b alpha: &a];
        DSStoreEntry *existing = [store entryForFilename: key code: @"BKGD"];
        DSStoreEntry *e = [DSStoreEntry backgroundColorEntryForFile: key
                                                                red: (int)(r * 65535.0)
                                                              green: (int)(g * 65535.0)
                                                               blue: (int)(b * 65535.0)
                                                          preserving: existing];
        if (e) [store setEntry: e];
    }

    /* Background image */
    if ([info backgroundType] == DSStoreBackgroundPicture && [info backgroundImagePath]) {
        DSStoreEntry *e = [DSStoreEntry backgroundImageEntryForFile: key
                                                          imagePath: [info backgroundImagePath]];
        if (e) [store setEntry: e];
    }

    /* Sidebar width */
    if ([info hasSidebarWidth]) {
        DSStoreEntry *e = [DSStoreEntry sidebarWidthEntryForFile: key width: [info sidebarWidth]];
        if (e) [store setEntry: e];
    }

    /* Window geometry (bwsp + fwi0) - patch existing records so unknown plist
     * keys / trailing bytes written by Finder are carried forward. */
    if ([info hasWindowFrame]) {
        NSRect dsFrame = [info dsStoreWindowFrameForScreen: [DSStoreInfo safeMainScreen]];
        DSStoreEntry *oldBwsp = [store entryForFilename: key code: @"bwsp"];
        DSStoreEntry *bwsp = [DSStoreEntry browserWindowEntryForFile: key
                                                       windowBounds: dsFrame
                                                       sidebarWidth: [info sidebarWidth]
                                                         preserving: oldBwsp];
        if (bwsp) [store setEntry: bwsp];

        NSString *styleStr = @"icnv";
        switch ([info viewStyle]) {
            case DSStoreViewStyleIcon:     styleStr = @"icnv"; break;
            case DSStoreViewStyleList:     styleStr = @"Nlsv"; break;
            case DSStoreViewStyleColumn:   styleStr = @"clmv"; break;
            case DSStoreViewStyleGallery:  styleStr = @"glyv"; break;
            case DSStoreViewStyleCoverflow:styleStr = @"Flwv"; break;
        }
        DSStoreEntry *oldFwi0 = [store entryForFilename: key code: @"fwi0"];
        DSStoreEntry *fwi0 = [DSStoreEntry windowGeometryEntryForFile: key
                                                                 rect: dsFrame
                                                            viewStyle: styleStr
                                                          preserving: oldFwi0];
        if (fwi0) [store setEntry: fwi0];
    }

    /* List view settings (lsvp) - patch existing, carrying forward unknown
     * plist keys. */
    if ([info hasListTextSize] || [info hasListIconSize] || [info hasSortColumn]
        || ([[info columnWidths] count] > 0)
        || ([[info columnVisible] count] > 0)) {
        DSStoreEntry *oldLsvp = [store entryForFilename: key code: @"lsvp"];
        DSStoreEntry *e = [DSStoreEntry listViewEntryForFile: key
                                                  sortColumn: ([info hasSortColumn] ? [info sortColumn] : nil)
                                                   ascending: [info sortAscending]
                                                    textSize: ([info hasListTextSize] ? [info listTextSize] : 0)
                                                    iconSize: ([info hasListIconSize] ? [info listIconSize] : 0)
                                                columnWidths: [info columnWidths]
                                               columnVisible: [info columnVisible]
                                                  preserving: oldLsvp];
        if (e) [store setEntry: e];
    }

    /* --- Per-file entries --- */
    for (NSString *filename in [info allIconInfo]) {
        [self writeIconInfo: [[info allIconInfo] objectForKey: filename]
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

- (NSRect)gnustepWindowFrameForScreen:(NSScreen *)screen
{
    if (!_hasWindowFrame) {
        return NSZeroRect;
    }
    
    // .DS_Store fwi0/bwsp stores the CONTENT AREA rect (excluding the title
    // bar / chrome) - see the MozillaWiki DS_Store format notes ("the rect
    // defining the content area of the window") and Finder behavior.  This is
    // also what the OpenStep/Cocoa contentRectForFrameRect: convention calls
    // the content rectangle, and what ICCCM WM_NORMAL_HINTS refers to as the
    // client window size (excluding borders).  The frame (with decorations)
    // is derived by the caller via [NSWindow frameRectForContentRect:].
    //
    // .DS_Store format: origin at TOP-LEFT of screen
    // - _windowFrame.origin.y is the TOP edge of CONTENT area (distance from top of screen downward)
    // - Smaller y values = closer to top of screen
    // 
    // GNUstep format: origin at BOTTOM-LEFT of screen
    // - y is distance from bottom of screen upward
    // - Larger y values = closer to top of screen
    //
    // This method returns the CONTENT AREA rect in GNUstep coordinates.
    // The caller must convert to full window frame using [NSWindow frameRectForContentRect:]
    //
    // Conversion: gnustep_y = screenHeight - dsstore_top - content_height
    CGFloat screenHeight = [screen frame].size.height;
    
    // _windowFrame.origin.y contains the TOP edge of content area from .DS_Store
    CGFloat dsStoreTop = _windowFrame.origin.y;
    CGFloat contentHeight = _windowFrame.size.height;
    
    // Calculate bottom edge position of content area in GNUstep coordinates
    CGFloat gnustepY = screenHeight - dsStoreTop - contentHeight;
    
    NSRect result = NSMakeRect(_windowFrame.origin.x, gnustepY, 
                               _windowFrame.size.width, contentHeight);
    
    
    return result;
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


  return saved;
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
  if (ia && !(preserve && _hasIconArrangement)) {
    _iconArrangement = [ia isEqualToString:@"grid"] ? DSStoreIconArrangementGrid
                       : DSStoreIconArrangementNone;
    _hasIconArrangement = YES;
  }

  /* Sidebar width */
  id sw = [prefs objectForKey:@"sidebarwidth"];
  if (sw && !(preserve && _hasSidebarWidth)) {
    _sidebarWidth = [sw intValue];
    _hasSidebarWidth = YES;
  }

  /* List view sort column - reported by FSNListView as an FSNInfoType int.
   * The workspace's list view only sorts ascending, so mirror that. */
  id htc = [prefs objectForKey: @"hligh_table_col"];
  if (htc && !(preserve && _hasSortColumn)) {
    NSString *name = [DSStoreInfo sortColumnNameForInfoType: [htc intValue]];
    if (name) {
      [_sortColumn release];
      _sortColumn = [name copy];
      _hasSortColumn = YES;
      _sortAscending = YES;
    }
  }

  /* List view column widths - reported by FSNListView's columnsDescription
   * keyed by the FSNInfoType identifier.  Translate to the Finder column
   * names used by lsvp. */
  NSDictionary *cols = [prefs objectForKey: @"list_view_columns"];
  if (cols && [cols isKindOfClass: [NSDictionary class]]
      && !(preserve && _columnWidths)) {
    NSMutableDictionary *widths = [NSMutableDictionary dictionary];
    for (NSString *key in cols) {
      NSDictionary *col = [cols objectForKey: key];
      if (![col isKindOfClass: [NSDictionary class]]) continue;
      id identObj = [col objectForKey: @"identifier"];
      id widthObj = [col objectForKey: @"width"];
      if (!identObj || !widthObj) continue;
      NSString *name = [DSStoreInfo sortColumnNameForInfoType: [identObj intValue]];
      if (name) {
        [widths setObject: [NSNumber numberWithFloat: [widthObj floatValue]]
                   forKey: name];
      }
    }
    if ([widths count] > 0) {
      [_columnWidths release];
      _columnWidths = [widths copy];
    }
  }
}

- (void)resetToDefaults
{
  _hasWindowFrame = NO;
  _hasViewStyle = NO;
  _hasIconSize = NO;
  _hasIconArrangement = NO;
  _hasLabelPosition = NO;
  _hasGridSpacing = NO;
  _hasSidebarWidth = NO;
  _hasListTextSize = NO;
  _hasListIconSize = NO;
  _hasSortColumn = NO;

  _backgroundType = DSStoreBackgroundDefault;
  [_backgroundColor release];  _backgroundColor = nil;
  [_backgroundImagePath release];  _backgroundImagePath = nil;
  [_sortColumn release];  _sortColumn = nil;
  [_columnWidths release];  _columnWidths = nil;
  [_columnVisible release];  _columnVisible = nil;
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
  if (!_hasIconArrangement && [other hasIconArrangement]) {
    _iconArrangement = [other iconArrangement];
    _hasIconArrangement = YES;
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
  if (!_hasSortColumn && [other hasSortColumn]) {
    [_sortColumn release];
    _sortColumn = [[other sortColumn] copy];
    _hasSortColumn = YES;
    _sortAscending = [other sortAscending];
  }
  if (_columnWidths == nil && [other columnWidths]) {
    [_columnWidths release];
    _columnWidths = [[other columnWidths] copy];
  }
  if (_columnVisible == nil && [other columnVisible]) {
    [_columnVisible release];
    _columnVisible = [[other columnVisible] copy];
  }

  /* Background: only copy when the receiver has none at all. */
  if ((_backgroundType == DSStoreBackgroundDefault && _backgroundColor == nil)
      && [other backgroundType] != DSStoreBackgroundDefault) {
    _backgroundType = [other backgroundType];
    [_backgroundColor release];
    _backgroundColor = [[other backgroundColor] retain];
    [_backgroundImagePath release];
    _backgroundImagePath = [[other backgroundImagePath] copy];
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
    if (_hasIconArrangement) {
        [desc appendFormat:@"  iconArrangement: %@\n", 
         _iconArrangement == DSStoreIconArrangementNone ? @"none (free)" : @"grid"];
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
