/* DSStoreInfo.m
 *  
 * Copyright (C) 2025 Free Software Foundation, Inc.
 *
 * Date: January 2025
 *
 * DS_Store information model for .DS_Store interoperability in Spatial mode.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import "DSStoreInfo.h"
#import "DSStore.h"

#pragma mark - DSStoreIconInfo Implementation

@implementation DSStoreIconInfo

@synthesize filename = _filename;
@synthesize position = _position;
@synthesize hasPosition = _hasPosition;
@synthesize comments = _comments;

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
    return copy;
}

- (NSPoint)gnustepPositionForViewHeight:(CGFloat)viewHeight iconHeight:(CGFloat)iconHeight
{
    // Delegate to DSStore class method for .DS_Store interoperability coordinate conversion
    return [DSStore gnustepPointFromDSStorePoint:_position viewHeight:viewHeight iconHeight:iconHeight];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<DSStoreIconInfo: %@ pos:(%.0f,%.0f) hasPos:%@>",
            _filename, _position.x, _position.y, _hasPosition ? @"YES" : @"NO"];
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
    [super dealloc];
}

#pragma mark - Loading

- (BOOL)load
{
    NSString *dsStorePath = [_directoryPath stringByAppendingPathComponent:@".DS_Store"];
    
    NSLog(@"╔══════════════════════════════════════════════════════════════════╗");
    NSLog(@"║             DS_STORE COMPREHENSIVE LOADING                       ║");
    NSLog(@"╠══════════════════════════════════════════════════════════════════╣");
    NSLog(@"║ Directory: %@", _directoryPath);
    NSLog(@"║ DS_Store path: %@", dsStorePath);
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dsStorePath]) {
        NSLog(@"║ ✗ No .DS_Store file found");
        NSLog(@"╚══════════════════════════════════════════════════════════════════╝");
        return NO;
    }
    
    NSLog(@"║ ✓ Found .DS_Store file");
    
    DSStore *store = [DSStore storeWithPath:dsStorePath];
    if (![store load]) {
        NSLog(@"║ ✗ Failed to load .DS_Store file");
        NSLog(@"╚══════════════════════════════════════════════════════════════════╝");
        return NO;
    }
    
    NSLog(@"║ ✓ Successfully parsed .DS_Store");
    NSLog(@"╟──────────────────────────────────────────────────────────────────╢");
    
    // Get all entries to see what's available
    NSArray *allFilenames = [store allFilenames];
    NSLog(@"║ Files with entries: %lu", (unsigned long)[allFilenames count]);
    
    // Process directory-level entries (filename = ".")
    [self loadDirectoryEntriesFromStore:store];
    
    // Process per-file entries (icon positions, comments, etc.)
    [self loadIconEntriesFromStore:store filenames:allFilenames];
    
    _loaded = YES;
    
    NSLog(@"╟──────────────────────────────────────────────────────────────────╢");
    NSLog(@"║                      LOADING COMPLETE                            ║");
    NSLog(@"╚══════════════════════════════════════════════════════════════════╝");
    
    [self logAllInfo];
    
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
    
    const unsigned char *bytes = [aliasData bytes];
    NSUInteger len = [aliasData length];
    
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
    NSLog(@"║ --- Directory-level entries (filename '.') ---");
    
    NSArray *dirCodes = [store allCodesForFilename:@"."];
    NSLog(@"║ Available codes for directory: %@", dirCodes);
    
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
    
    // Load grid/spacing options (icgo, icsp)
    [self loadIconGridOptionsFromStore:store];
    
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
        NSLog(@"║ ○ Skipping fwi0 (already have geometry from bwsp)");
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
            
            NSLog(@"║ ✓ fwi0 (Window Geometry):");
            NSLog(@"║   Edges: top=%d left=%d bottom=%d right=%d", top, left, bottom, right);
            NSLog(@"║   Rect: x=%.0f y=%.0f w=%.0f h=%.0f", x, y, width, height);
            
            // Log view style from bytes 8-11 if present
            if ([data length] >= 12) {
                char viewStyle[5] = {bytes[8], bytes[9], bytes[10], bytes[11], 0};
                NSLog(@"║   View style: %s", viewStyle);
            }
        } else {
            NSLog(@"║ ⚠ fwi0 data too short: %lu bytes", (unsigned long)[data length]);
        }
    } else {
        NSLog(@"║ ○ No fwi0 (window geometry) entry");
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
            NSLog(@"║ ✓ vstl (View Style): Icon view (icnv)");
        } else if ([style isEqualToString:@"Nlsv"]) {
            _viewStyle = DSStoreViewStyleList;
            _hasViewStyle = YES;
            NSLog(@"║ ✓ vstl (View Style): List view (Nlsv)");
        } else if ([style isEqualToString:@"clmv"]) {
            _viewStyle = DSStoreViewStyleColumn;
            _hasViewStyle = YES;
            NSLog(@"║ ✓ vstl (View Style): Column view (clmv)");
        } else if ([style isEqualToString:@"glyv"]) {
            _viewStyle = DSStoreViewStyleGallery;
            _hasViewStyle = YES;
            NSLog(@"║ ✓ vstl (View Style): Gallery view (glyv)");
        } else if ([style isEqualToString:@"Flwv"]) {
            _viewStyle = DSStoreViewStyleCoverflow;
            _hasViewStyle = YES;
            NSLog(@"║ ✓ vstl (View Style): Coverflow view (Flwv)");
        } else {
            NSLog(@"║ ⚠ vstl (View Style): Unknown style '%@'", style);
        }
    } else {
        NSLog(@"║ ○ No vstl (view style) entry");
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
        NSLog(@"║ ✓ bwsp (Browser Window Settings - Modern): %lu bytes", (unsigned long)[data length]);
        
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
                    NSLog(@"║   ✓ Window bounds extracted: %@", windowBounds);
                    NSLog(@"║     Parsed as: x=%.0f y=%.0f w=%.0f h=%.0f", 
                          rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
                } else {
                    NSLog(@"║   ⚠ Window bounds string present but invalid");
                }
            }
            
            // Extract sidebar width
            id sidebarWidthObj = [plist objectForKey:@"SidebarWidth"];
            if (sidebarWidthObj) {
                _sidebarWidth = [sidebarWidthObj intValue];
                _hasSidebarWidth = YES;
                NSLog(@"║   Sidebar width: %d", _sidebarWidth);
            }
            
            NSLog(@"║   Show sidebar: %@", [plist objectForKey:@"ShowSidebar"]);
            NSLog(@"║   Show toolbar: %@", [plist objectForKey:@"ShowToolbar"]);
        } else {
            NSLog(@"║   ⚠ Failed to parse bwsp as plist: %@", error);
        }
    } else {
        NSLog(@"║ ○ No bwsp (browser window settings) entry");
    }
}

- (void)loadIconViewOptionsFromStore:(DSStore *)store
{
    // icvo: Legacy icon view options format (pre-10.6)
    // Only used as fallback if icvp is not present
    // Modern .DS_Store files use icvp binary plist instead
    
    // Skip if we already have settings from icvp (new format)
    if (_hasIconSize && _hasIconArrangement && _hasLabelPosition) {
        NSLog(@"║ ○ Skipping icvo (already have settings from icvp)");
        return;
    }
    
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"icvo"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        const uint8_t *bytes = (const uint8_t *)[data bytes];
        NSUInteger len = [data length];
        
        NSLog(@"║ ✓ icvo (Icon View Options): %lu bytes", (unsigned long)len);
        
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
                    NSLog(@"║   Format: icvo, Icon size: %d", _iconSize);
                }
                
                // Arrangement at bytes 14-17
                if (len >= 18) {
                    char arr[5] = {bytes[14], bytes[15], bytes[16], bytes[17], 0};
                    if (strcmp(arr, "none") == 0) {
                        _iconArrangement = DSStoreIconArrangementNone;
                        _hasIconArrangement = YES;
                        NSLog(@"║   Arrangement: none");
                    } else if (strcmp(arr, "grid") == 0) {
                        _iconArrangement = DSStoreIconArrangementGrid;
                        _hasIconArrangement = YES;
                        NSLog(@"║   Arrangement: grid");
                    }
                }
            } else if (strcmp(magic, "icv4") == 0 && len >= 14) {
                // New "icv4" format: size at bytes 4-5
                uint16_t size = (bytes[4] << 8) | bytes[5];
                if (size > 0 && size <= 512) {
                    _iconSize = size;
                    _hasIconSize = YES;
                    NSLog(@"║   Format: icv4, Icon size: %d", _iconSize);
                }
                
                // Arrangement at bytes 6-9
                char arr[5] = {bytes[6], bytes[7], bytes[8], bytes[9], 0};
                if (strcmp(arr, "none") == 0) {
                    _iconArrangement = DSStoreIconArrangementNone;
                    _hasIconArrangement = YES;
                    NSLog(@"║   Arrangement: none");
                } else if (strcmp(arr, "grid") == 0) {
                    _iconArrangement = DSStoreIconArrangementGrid;
                    _hasIconArrangement = YES;
                    NSLog(@"║   Arrangement: grid");
                }
                
                // Label position at bytes 10-13
                if (len >= 14) {
                    char lbl[5] = {bytes[10], bytes[11], bytes[12], bytes[13], 0};
                    if (strcmp(lbl, "botm") == 0) {
                        _labelPosition = DSStoreLabelPositionBottom;
                        _hasLabelPosition = YES;
                        NSLog(@"║   Label position: bottom");
                    } else if (strcmp(lbl, "rght") == 0) {
                        _labelPosition = DSStoreLabelPositionRight;
                        _hasLabelPosition = YES;
                        NSLog(@"║   Label position: right");
                    }
                }
            } else {
                NSLog(@"║   ⚠ Unknown icvo format variant (magic: %s)", magic);
            }
        }
    } else {
        NSLog(@"║ ○ No icvo (icon view options) entry");
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
        NSLog(@"║ ✓ icvp (Icon View Plist): %lu bytes", (unsigned long)[data length]);
        
        // Try to parse as binary plist
        NSError *error = nil;
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
        if (plist && [plist isKindOfClass:[NSDictionary class]]) {
            NSLog(@"║   Parsed plist keys: %@", [plist allKeys]);
            
            // Extract icon size
            id sizeObj = [plist objectForKey:@"iconSize"];
            if (sizeObj) {
                int size = [sizeObj intValue];
                if (size > 0 && size <= 512) {
                    _iconSize = size;
                    _hasIconSize = YES;
                    NSLog(@"║   Icon size from plist: %d", _iconSize);
                }
            }
            
            // Extract arrangement
            id arrObj = [plist objectForKey:@"arrangeBy"];
            if (arrObj) {
                NSString *arr = [arrObj description];
                if ([arr isEqualToString:@"none"] || [arr isEqualToString:@"0"]) {
                    _iconArrangement = DSStoreIconArrangementNone;
                    _hasIconArrangement = YES;
                    NSLog(@"║   Arrangement from plist: none");
                } else if ([arr isEqualToString:@"grid"]) {
                    _iconArrangement = DSStoreIconArrangementGrid;
                    _hasIconArrangement = YES;
                    NSLog(@"║   Arrangement from plist: grid");
                }
            }
            
            // Extract grid spacing
            id spacingObj = [plist objectForKey:@"gridSpacing"];
            if (spacingObj) {
                _gridSpacing = [spacingObj floatValue];
                _hasGridSpacing = YES;
                NSLog(@"║   Grid spacing from plist: %.1f", _gridSpacing);
            }
            
            // Extract label position
            id labelObj = [plist objectForKey:@"labelOnBottom"];
            if (labelObj) {
                _labelPosition = [labelObj boolValue] ? DSStoreLabelPositionBottom : DSStoreLabelPositionRight;
                _hasLabelPosition = YES;
                NSLog(@"║   Label position from plist: %@", 
                      _labelPosition == DSStoreLabelPositionBottom ? @"bottom" : @"right");
            }
            
            // Extract background settings
            // Check background type first
            id bgTypeObj = [plist objectForKey:@"backgroundType"];
            int bgType = bgTypeObj ? [bgTypeObj intValue] : 0;
            
            if (bgType == 2) {
                // Picture background
                _backgroundType = DSStoreBackgroundPicture;
                NSLog(@"║   Background type from plist: picture (2)");
                
                // Try to extract background image alias
                id bgImageAlias = [plist objectForKey:@"backgroundImageAlias"];
                if (bgImageAlias && [bgImageAlias isKindOfClass:[NSData class]]) {
                    // This is an alias record - try to resolve it to a path
                    NSData *aliasData = (NSData *)bgImageAlias;
                    NSString *resolvedPath = [self resolveAliasData:aliasData relativeTo:_directoryPath];
                    if (resolvedPath) {
                        [_backgroundImagePath release];
                        _backgroundImagePath = [resolvedPath copy];
                        NSLog(@"║   Background image from alias: %@", _backgroundImagePath);
                    } else {
                        NSLog(@"║   ⚠ Could not resolve background image alias (%lu bytes)", 
                              (unsigned long)[aliasData length]);
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
                    NSLog(@"║   Background type from plist: color (1) R=%.2f G=%.2f B=%.2f", r, g, b);
                }
            } else {
                NSLog(@"║   Background type from plist: default (0)");
            }
            
        } else {
            NSLog(@"║   ⚠ Failed to parse icvp as plist: %@", error);
        }
    } else {
        NSLog(@"║ ○ No icvp (icon view plist) entry");
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
                NSLog(@"║ ✓ BKGD: Default background (DefB)");
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
                    NSLog(@"║ ✓ BKGD: Color (ClrB) R=0x%04x G=0x%04x B=0x%04x (%.3f, %.3f, %.3f)", 
                          rVal, gVal, bVal, r, g, b);
                }
            } else if (strncmp(bytes, "PctB", 4) == 0) {
                _backgroundType = DSStoreBackgroundPicture;
                NSLog(@"║ ✓ BKGD: Picture background (PctB)");
                
                // Use DSStore's method to resolve the background image path
                NSString *imagePath = [store backgroundImagePathForDirectory];
                if (imagePath && [imagePath length] > 0) {
                    [_backgroundImagePath release];
                    _backgroundImagePath = [imagePath copy];
                    NSLog(@"║   Background image path: %@", _backgroundImagePath);
                } else {
                    NSLog(@"║   ⚠ Could not resolve background image path");
                }
            }
        }
    } else {
        NSLog(@"║ ○ No BKGD (background) entry");
    }
}

- (void)loadIconGridOptionsFromStore:(DSStore *)store
{
    // icgo: Icon grid options (8 bytes, probably two 32-bit integers)
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"icgo"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        if ([data length] >= 8) {
            const uint8_t *bytes = (const uint8_t *)[data bytes];
            uint32_t val1 = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
            uint32_t val2 = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
            NSLog(@"║ ✓ icgo (Icon Grid Options): %u, %u", val1, val2);
        }
    } else {
        NSLog(@"║ ○ No icgo (icon grid options) entry");
    }
    
    // icsp: Icon spacing (8 bytes)
    entry = [store entryForFilename:@"." code:@"icsp"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        if ([data length] >= 8) {
            const uint8_t *bytes = (const uint8_t *)[data bytes];
            // Usually mostly zeros except last two bytes
            uint16_t spacing = (bytes[6] << 8) | bytes[7];
            NSLog(@"║ ✓ icsp (Icon Spacing): %u", spacing);
        }
    } else {
        NSLog(@"║ ○ No icsp (icon spacing) entry");
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
        NSLog(@"║ ✓ lsvp/lsvP (List View Properties): %lu bytes", (unsigned long)[data length]);
        
        NSError *error = nil;
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                        options:NSPropertyListImmutable
                                                                         format:NULL
                                                                          error:&error];
        if (plist && [plist isKindOfClass:[NSDictionary class]]) {
            NSLog(@"║   Parsed plist keys: %@", [plist allKeys]);
            
            id textSizeObj = [plist objectForKey:@"textSize"];
            if (textSizeObj) {
                NSLog(@"║   Text size: %@", textSizeObj);
            }
            
            id iconSizeObj = [plist objectForKey:@"iconSize"];
            if (iconSizeObj) {
                NSLog(@"║   Icon size: %@", iconSizeObj);
            }
            
            id sortColumnObj = [plist objectForKey:@"sortColumn"];
            if (sortColumnObj) {
                NSLog(@"║   Sort column: %@", sortColumnObj);
            }
        } else {
            NSLog(@"║   ⚠ Failed to parse as plist: %@", error);
        }
    } else {
        NSLog(@"║ ○ No lsvp/lsvP (list view properties) entry");
    }
    
    // Check for legacy lsvo format (76 bytes)
    entry = [store entryForFilename:@"." code:@"lsvo"];
    if (entry && [[entry type] isEqualToString:@"blob"]) {
        NSData *data = (NSData *)[entry value];
        NSLog(@"║ ✓ lsvo (List View Options - Legacy): %lu bytes", (unsigned long)[data length]);
    }
}


- (void)loadSidebarWidthFromStore:(DSStore *)store
{
    DSStoreEntry *entry = [store entryForFilename:@"." code:@"fwsw"];
    if (entry && [[entry type] isEqualToString:@"long"]) {
        _sidebarWidth = [[entry value] intValue];
        _hasSidebarWidth = YES;
        NSLog(@"║ ✓ fwsw (Sidebar Width): %d pixels", _sidebarWidth);
    } else {
        NSLog(@"║ ○ No fwsw (sidebar width) entry");
    }
}

- (void)loadIconEntriesFromStore:(DSStore *)store filenames:(NSArray *)filenames
{
    NSLog(@"║ --- Per-file entries (icon positions, comments) ---");
    
    NSUInteger positionCount = 0;
    NSUInteger commentCount = 0;
    
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
                positionCount++;
                
                NSLog(@"║   Iloc '%@': (%d, %d) [icon center]", filename, x, y);
            }
        }
        
        // Check for cmmt (comments)
        DSStoreEntry *cmmtEntry = [store entryForFilename:filename code:@"cmmt"];
        if (cmmtEntry && [[cmmtEntry type] isEqualToString:@"ustr"]) {
            if (!info) {
                info = [DSStoreIconInfo infoForFilename:filename];
            }
            info.comments = (NSString *)[cmmtEntry value];
            commentCount++;
            NSLog(@"║   cmmt '%@': \"%@\"", filename, info.comments);
        }
        
        // Store the info if we have any data
        if (info) {
            [_iconInfoDict setObject:info forKey:filename];
        }
    }
    
    NSLog(@"║ Total icon positions found: %lu", (unsigned long)positionCount);
    NSLog(@"║ Total comments found: %lu", (unsigned long)commentCount);
}

#pragma mark - Icon Position Access

- (DSStoreIconInfo *)iconInfoForFilename:(NSString *)filename
{
    return [_iconInfoDict objectForKey:filename];
}

- (NSDictionary *)allIconInfo
{
    return [NSDictionary dictionaryWithDictionary:_iconInfoDict];
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
    
    // IMPORTANT: .DS_Store fwi0 stores the CONTENT AREA rect (excluding titlebar/chrome)
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
    
    NSLog(@"Coordinate conversion:");
    NSLog(@"  .DS_Store content area: top=%.0f left=%.0f width=%.0f height=%.0f", 
          dsStoreTop, _windowFrame.origin.x, _windowFrame.size.width, contentHeight);
    NSLog(@"  Screen height: %.0f", screenHeight);
    NSLog(@"  GNUstep content rect: %@", NSStringFromRect(result));
    
    return result;
}

- (NSPoint)gnustepPositionForDSStorePoint:(NSPoint)dsPoint 
                           viewHeight:(CGFloat)viewHeight 
                           iconHeight:(CGFloat)iconHeight
{
    // Delegate to DSStore class method for .DS_Store interoperability coordinate conversion
    return [DSStore gnustepPointFromDSStorePoint:dsPoint viewHeight:viewHeight iconHeight:iconHeight];
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

- (void)logAllInfo
{
    NSLog(@"╔══════════════════════════════════════════════════════════════════╗");
    NSLog(@"║                   DS_STORE INFO SUMMARY                          ║");
    NSLog(@"╠══════════════════════════════════════════════════════════════════╣");
    NSLog(@"║ Directory: %@", _directoryPath);
    NSLog(@"╟──────────────────────────────────────────────────────────────────╢");
    
    if (_hasWindowFrame) {
        NSLog(@"║ Window Geometry: x=%.0f y=%.0f w=%.0f h=%.0f", 
              _windowFrame.origin.x, _windowFrame.origin.y,
              _windowFrame.size.width, _windowFrame.size.height);
    } else {
        NSLog(@"║ Window Geometry: (not set)");
    }
    
    if (_hasViewStyle) {
        NSString *styleName = @"unknown";
        switch (_viewStyle) {
            case DSStoreViewStyleIcon: styleName = @"Icon"; break;
            case DSStoreViewStyleList: styleName = @"List"; break;
            case DSStoreViewStyleColumn: styleName = @"Column"; break;
            case DSStoreViewStyleGallery: styleName = @"Gallery"; break;
            case DSStoreViewStyleCoverflow: styleName = @"Coverflow"; break;
        }
        NSLog(@"║ View Style: %@", styleName);
    } else {
        NSLog(@"║ View Style: (not set, defaulting to Icon)");
    }
    
    if (_hasIconSize) {
        NSLog(@"║ Icon Size: %d pixels", _iconSize);
    } else {
        NSLog(@"║ Icon Size: (not set, using default)");
    }
    
    if (_hasIconArrangement) {
        NSLog(@"║ Icon Arrangement: %@", 
              _iconArrangement == DSStoreIconArrangementNone ? 
              @"NONE (free positioning enabled)" : @"Grid (snapping enabled)");
    } else {
        NSLog(@"║ Icon Arrangement: (not set)");
    }
    
    if (_hasLabelPosition) {
        NSLog(@"║ Label Position: %@",
              _labelPosition == DSStoreLabelPositionBottom ? @"Bottom" : @"Right");
    }
    
    if (_backgroundColor) {
        NSLog(@"║ Background: Color - %@", _backgroundColor);
    } else if (_backgroundImagePath) {
        NSLog(@"║ Background: Image - %@", _backgroundImagePath);
    } else {
        NSLog(@"║ Background: Default");
    }
    
    NSArray *positionedFiles = [self filenamesWithPositions];
    NSLog(@"╟──────────────────────────────────────────────────────────────────╢");
    NSLog(@"║ Icons with custom positions: %lu", (unsigned long)[positionedFiles count]);
    
    for (NSString *filename in positionedFiles) {
        DSStoreIconInfo *info = [_iconInfoDict objectForKey:filename];
        NSLog(@"║   '%@' -> (%.0f, %.0f)", filename, info.position.x, info.position.y);
    }
    
    NSLog(@"╚══════════════════════════════════════════════════════════════════╝");
}

@end
