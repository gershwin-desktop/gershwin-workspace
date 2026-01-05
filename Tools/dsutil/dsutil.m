/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "DSStore.h"
#import "DSStoreEntry.h"

void printUsage(void) {
    printf("dsutil - .DS_Store file manipulation tool\n\n");
    printf("USAGE:\n");
    printf("  dsutil [-v|--verbose] <command> [options] [arguments]\n");
    printf("  dsutil [-v|--verbose] <directory>          Show summary (shorthand for 'summary' command)\n\n");
    
    printf("GLOBAL FLAGS:\n");
    printf("  -v, --verbose            Show debug output and internal structure information\n\n");
    
    printf("FILE COMMANDS:\n");
    printf("  create <path>                Create empty .DS_Store file\n");
    printf("  list [path]                  List all entries (default: .DS_Store)\n");
    printf("  dump [path]                  Dump complete file contents with details\n");
    printf("  info <path>                  Show file information and statistics\n");
    printf("  validate <path>              Validate .DS_Store file structure\n");
    printf("  files <path>                 List all files with metadata entries\n");
    printf("  summary <directory>          Show comprehensive summary with conversions\n\n");
    
    printf("ICON POSITION COMMANDS:\n");
    printf("  get-pos <file> <filename>    Get icon position coordinates\n");
    printf("  set-pos <file> <filename> <x> <y>  Set icon position (icon center, pixels from window top-left)\n\n");
    
    printf("BACKGROUND COMMANDS:\n");
    printf("  get-bg <file>                Get background settings\n");
    printf("  set-bg-color <file> <r> <g> <b>    Set solid color background (0.0-1.0)\n");
    printf("  set-bg-image <file> <path>   Set background image\n");
    printf("  remove-bg <file>             Remove background settings\n\n");
    
    printf("VIEW COMMANDS:\n");
    printf("  get-view <file>              Get view style and settings\n");
    printf("  set-view <file> <style>      Set view style (icon|list|column|gallery|flow)\n");
    printf("  get-iconsize <file>          Get icon size\n");
    printf("  set-iconsize <file> <size>   Set icon size (16-512 pixels)\n");
    printf("  get-gridspacing <file>       Get icon grid spacing\n");
    printf("  set-gridspacing <file> <px>  Set icon grid spacing\n");
    printf("  get-textsize <file>          Get label text size\n");
    printf("  set-textsize <file> <size>   Set label text size\n");
    printf("  get-labelpos <file>          Get label position\n");
    printf("  set-labelpos <file> <pos>    Set label position (bottom|right)\n");
    printf("  get-arrangement <file>       Get icon arrangement\n");
    printf("  set-arrangement <file> <arr> Set icon arrangement (none|grid)\n");
    printf("  get-sortby <file>            Get sort by setting\n");
    printf("  set-sortby <file> <key>      Set sort by (name|date|size|kind|label|none)\n");
    printf("  get-showinfo <file>          Get show item info setting\n");
    printf("  set-showinfo <file> <0|1>    Show item info\n");
    printf("  get-preview <file>           Get show icon previews setting\n");
    printf("  set-preview <file> <0|1>     Show icon previews\n\n");
    
    printf("WINDOW CHROME COMMANDS:\n");
    printf("  get-sidebar-width <file>     Get sidebar width\n");
    printf("  set-sidebar-width <file> <px>    Set sidebar width\n");
    printf("  get-toolbar <file>           Get toolbar visibility\n");
    printf("  set-toolbar <file> <0|1>         Show/hide toolbar\n");
    printf("  get-sidebar <file>           Get sidebar visibility\n");
    printf("  set-sidebar <file> <0|1>         Show/hide sidebar\n");
    printf("  get-pathbar <file>           Get path bar visibility\n");
    printf("  set-pathbar <file> <0|1>         Show/hide path bar\n");
    printf("  get-statusbar <file>         Get status bar visibility\n");
    printf("  set-statusbar <file> <0|1>       Show/hide status bar\n\n");
    
    printf("LABEL COLOR COMMANDS:\n");
    printf("  get-label <file> <filename>      Get file label color\n");
    printf("  set-label <file> <filename> <color>  Set label color\n");
    printf("  COLORS: none, red, orange, yellow, green, blue, purple, grey\n\n");
    
    printf("COLUMN VIEW COMMANDS (spatial/icon view only):\n");
    printf("  get-column-width <file> <column>   Get column width\n");
    printf("  set-column-width <file> <column> <pixels>  Set column width\n");
    printf("  get-column-visible <file> <column>   Get column visibility\n");
    printf("  set-column-visible <file> <column> <0|1>  Show/hide column\n");
    printf("  get-relative-dates <file>        Get relative dates setting\n");
    printf("  set-relative-dates <file> <0|1> Show/hide relative dates\n");
    printf("  COLUMNS: name, date, size, kind, label, version, comments\n\n");
    
    printf("METADATA COMMANDS:\n");
    printf("  get-comment <file> <filename>       Get file comment\n");
    printf("  set-comment <file> <filename> <text>  Set file comment\n\n");
    
    printf("GENERIC FIELD COMMANDS:\n");
    printf("  get <file> <filename> <code>        Get field value by code\n");
    printf("  set <file> <filename> <code> <type> <value>  Set field value\n");
    printf("  remove <file> <filename> <code>     Remove field\n");
    printf("  fields <file> <filename>            List all fields for filename\n\n");
    
    printf("FIELD TYPES: bool, long, shor, ustr, type, blob, comp, dutc\n\n");
    printf("COMMON FIELD CODES:\n");
    printf("  Iloc  - Icon location (16 bytes: x,y as 4-byte signed ints + 8 padding)\n");
    printf("  fwi0  - Window geometry (16 bytes: top/left/bottom/right + view style)\n");
    printf("  vstl  - View style (4CC: icnv/clmv/Nlsv/Flwv/glyv)\n");
    printf("  icvo  - Icon view options (18+ bytes: magic + size + arrangement + labels)\n");
    printf("  icvp  - Icon view plist (binary plist with icon settings)\n");
    printf("  lsvp  - List view plist (binary plist with list settings)\n");
    printf("  bwsp  - Browser window settings plist (window bounds, sidebar, etc.)\n");
    printf("  BKGD  - Background settings (12 bytes: DefB/ClrB/PctB + data)\n");
    printf("  cmmt  - File comments (UTF-16 string)\n");
    printf("  icgo  - Icon grid options (8 bytes)\n");
    printf("  icsp  - Icon spacing (8 bytes)\n");
    printf("  fwsw  - Sidebar width (4-byte integer)\n\n");
    
    printf("EXAMPLES:\n");
    printf("  dsutil create /path/to/.DS_Store\n");
    printf("  dsutil set-pos .DS_Store image.jpg 100 200\n");
    printf("  dsutil set-bg-color .DS_Store 0.9 0.9 1.0\n");
    printf("  dsutil set-view .DS_Store icon\n");
    printf("  dsutil set-label .DS_Store file.txt red\n");
    printf("  dsutil set-sortby .DS_Store name\n");
    printf("  dsutil get . vstl                 # Get directory view style\n");
}

int listEntries(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        printf("Error: File not found: %s\n", [path UTF8String]);
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:path] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSArray *entries = [store entries];
    printf("Found %lu entries in %s:\n", (unsigned long)[entries count], [path UTF8String]);
    
    for (DSStoreEntry *entry in entries) {
        printf("  %-20s %s\n", 
               [[entry filename] UTF8String], 
               [[entry code] UTF8String]);
    }
    
    return 0;
}

int dumpAll(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        printf("Error: File not found: %s\n", [path UTF8String]);
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:path] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSArray *entries = [store entries];
    printf("=== COMPLETE DS_STORE DUMP: %s ===\n", [path UTF8String]);
    printf("Total entries: %lu\n\n", (unsigned long)[entries count]);
    
    // Group entries by filename
    NSMutableDictionary *entriesByFile = [NSMutableDictionary dictionary];
    for (DSStoreEntry *entry in entries) {
        NSString *filename = [entry filename];
        NSMutableArray *fileEntries = [entriesByFile objectForKey:filename];
        if (!fileEntries) {
            fileEntries = [NSMutableArray array];
            [entriesByFile setObject:fileEntries forKey:filename];
        }
        [fileEntries addObject:entry];
    }
    
    // Sort filenames for consistent output  
    NSArray *sortedFilenames = [[entriesByFile allKeys] sortedArrayUsingSelector:@selector(compare:)];
    
    for (NSString *filename in sortedFilenames) {
        printf("File: '%s'\n", [filename UTF8String]);
        NSArray *fileEntries = [entriesByFile objectForKey:filename];
        
        for (DSStoreEntry *entry in fileEntries) {
            NSString *code = [entry code];
            NSString *type = [entry type]; 
            id value = [entry value];
            
            printf("  %s (%s): ", [code UTF8String], [type UTF8String]);
            
            // Interpret known codes
            if ([code isEqualToString:@"Iloc"] && [type isEqualToString:@"blob"]) {
                if ([value isKindOfClass:[NSData class]]) {
                    NSData *data = (NSData *)value;
                    if ([data length] >= 8) {
                        const uint8_t *bytes = [data bytes];
                        // Iloc: two 4-byte big-endian signed integers for x,y (icon center)
                        int32_t x = (int32_t)((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3]);
                        int32_t y = (int32_t)((bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7]);
                        printf("Icon position (%d, %d) [icon center]", x, y);
                        if ([data length] > 8) {
                            printf(" + %lu padding bytes", (unsigned long)[data length] - 8);
                        }
                    } else {
                        printf("Invalid Iloc data (too short)");
                    }
                } else {
                    printf("Invalid Iloc data (not NSData)");
                }
            } else if ([code isEqualToString:@"fwi0"] && [type isEqualToString:@"blob"]) {
                if ([value isKindOfClass:[NSData class]]) {
                    NSData *data = (NSData *)value;
                    if ([data length] >= 16) {
                        const uint8_t *bytes = [data bytes];
                        // fwi0: first 8 bytes = window rect (top/left/bottom/right as 2-byte ints)
                        uint16_t top = (bytes[0] << 8) | bytes[1];
                        uint16_t left = (bytes[2] << 8) | bytes[3];
                        uint16_t bottom = (bytes[4] << 8) | bytes[5];
                        uint16_t right = (bytes[6] << 8) | bytes[7];
                        // Bytes 8-11: view style 4CC
                        char viewStyle[5] = {bytes[8], bytes[9], bytes[10], bytes[11], 0};
                        printf("Window geometry: rect(%d,%d,%d,%d) view=%s", 
                               top, left, bottom, right, viewStyle);
                    } else {
                        printf("Window geometry (too short)");
                    }
                } else {
                    printf("Window geometry (invalid data)");
                }
            } else if ([code isEqualToString:@"bwsp"]) {
                printf("Background/Window settings (plist data)");
            } else if ([code isEqualToString:@"icvp"]) {
                printf("Icon view properties (plist data)");
            } else if ([code isEqualToString:@"lsvp"] || [code isEqualToString:@"lsvP"]) {
                printf("List view properties (plist data)");
            } else if ([code isEqualToString:@"vstl"]) {
                printf("View style");
            } else if ([code isEqualToString:@"BKGD"]) {
                printf("Background (legacy)");
            } else if ([code isEqualToString:@"cmmt"]) {
                printf("Comments");
            } else if ([code isEqualToString:@"dilc"]) {
                printf("Desktop icon location");
            } else if ([code isEqualToString:@"dscl"]) {
                printf("Disclosure state");
            } else if ([code isEqualToString:@"fwsw"]) {
                printf("Sidebar width");
            } else if ([code isEqualToString:@"icgo"]) {
                if ([value isKindOfClass:[NSData class]]) {
                    NSData *data = (NSData *)value;
                    if ([data length] >= 8) {
                        const uint8_t *bytes = [data bytes];
                        uint32_t val1 = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
                        uint32_t val2 = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
                        printf("Icon grid options (%u, %u)", val1, val2);
                    } else {
                        printf("Icon grid options");
                    }
                } else {
                    printf("Icon grid options");
                }
            } else if ([code isEqualToString:@"icsp"]) {
                if ([value isKindOfClass:[NSData class]]) {
                    NSData *data = (NSData *)value;
                    if ([data length] >= 8) {
                        const uint8_t *bytes = [data bytes];
                        uint16_t spacing = (bytes[6] << 8) | bytes[7];
                        printf("Icon spacing (%u)", spacing);
                    } else {
                        printf("Icon spacing");
                    }
                } else {
                    printf("Icon spacing");
                }
            } else if ([code isEqualToString:@"icvo"]) {
                printf("Icon view options");
            } else if ([code isEqualToString:@"ICVO"]) {
                printf("Icon view overlay");
            } else if ([code isEqualToString:@"LSVO"]) {
                printf("List view overlay");
            } else if ([code isEqualToString:@"GRP0"]) {
                printf("Group (unknown)");
            } else {
                printf("Unknown code");
            }
            
            // Show raw value for small data
            if ([value isKindOfClass:[NSData class]]) {
                NSData *data = (NSData *)value;
                if ([data length] <= 16) {
                    printf(" [");
                    const uint8_t *bytes = [data bytes];
                    for (NSUInteger i = 0; i < [data length]; i++) {
                        printf("%02x", bytes[i]);
                        if (i < [data length] - 1) printf(" ");
                    }
                    printf("]");
                } else {
                    printf(" [%lu bytes]", (unsigned long)[data length]);
                }
            } else if ([value isKindOfClass:[NSString class]]) {
                printf(" \"%s\"", [(NSString *)value UTF8String]);
            } else if ([value isKindOfClass:[NSNumber class]]) {
                printf(" %s", [[(NSNumber *)value description] UTF8String]);
            }
            
            printf("\n");
        }
        printf("\n");
    }
    
    return 0;
}

int createStore(NSString *path) {
    NSArray *emptyEntries = [NSArray array];
    DSStore *store = [DSStore createStoreAtPath:path withEntries:emptyEntries];
    if (!store) {
        printf("Error: Failed to create .DS_Store file at %s\n", [path UTF8String]);
        return 1;
    }
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Created empty .DS_Store file: %s\n", [path UTF8String]);
    return 0;
}

int setIconPosition(NSString *storePath, NSString *filename, int x, int y) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![[NSFileManager defaultManager] fileExistsAtPath:storePath]) {
        // Create new store if it doesn't exist
        NSArray *emptyEntries = [NSArray array];
        store = [DSStore createStoreAtPath:storePath withEntries:emptyEntries];
        if (!store) {
            printf("Error: Failed to create .DS_Store file\n");
            return 1;
        }
    } else if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Use the proper API for setting icon position
    [store setIconLocationForFilename:filename x:x y:y];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set icon position for %s:\n", [filename UTF8String]);
    printf("  .DS_Store coordinates: (%d, %d) [icon center]\n", x, y);
    
    // Show what this would be in GNUstep coordinates
    // Note: These are default assumptions - actual values depend on the view configuration
    NSPoint dsPoint = NSMakePoint(x, y);
    CGFloat viewHeight = 600.0;
    CGFloat iconHeight = 64.0;
    NSPoint gnustepPos = [DSStore gnustepPointFromDSStorePoint:dsPoint 
                                                    viewHeight:viewHeight 
                                                    iconHeight:iconHeight];
    printf("  GNUstep equivalent: (%.0f, %.0f) [assuming view height=%.0f, icon height=%.0f]\n",
           gnustepPos.x, gnustepPos.y, viewHeight, iconHeight);
    
    return 0;
}

int getIconPosition(NSString *storePath, NSString *filename) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:storePath]) {
        printf("Error: File not found: %s\n", [storePath UTF8String]);
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSPoint location = [store iconLocationForFilename:filename];
    if (location.x == 0 && location.y == 0) {
        printf("No icon position set for %s\n", [filename UTF8String]);
    } else {
        printf("Icon position for %s:\n", [filename UTF8String]);
        printf("  .DS_Store coordinates: (%.0f, %.0f) [icon center]\n", location.x, location.y);
        
        // Show GNUstep conversions with typical icon dimensions
        // Note: Actual view height depends on window configuration
        CGFloat viewHeight = 600.0;
        CGFloat iconHeight = 64.0;
        NSPoint gnustepPos = [DSStore gnustepPointFromDSStorePoint:location 
                                                        viewHeight:viewHeight 
                                                        iconHeight:iconHeight];
        printf("  GNUstep equivalent: (%.0f, %.0f) [conversion assumes view height=%.0f, icon height=%.0f]\n",
               gnustepPos.x, gnustepPos.y, viewHeight, iconHeight);
        printf("  Note: .DS_Store coordinates = icon center, top-left origin (y↓); GNUstep uses bottom-left origin (y↑)\n");
    }
    
    return 0;
}

// Legacy setBackground and setView functions removed - use specific functions below

int removeEntry(NSString *storePath, NSString *filename, NSString *code) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:storePath]) {
        printf("Error: File not found: %s\n", [storePath UTF8String]);
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store removeEntryForFilename:filename code:code];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Removed entry %s:%s\n", [filename UTF8String], [code UTF8String]);
    return 0;
}

// Background management functions
int getBackground(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Try to get background color entry directly
    DSStoreEntry *colorEntry = [store entryForFilename:@"." code:@"BKGD"];
    if (colorEntry && [[colorEntry type] isEqualToString:@"blob"]) {
        NSData *data = [colorEntry value];
        if ([data length] >= 6) {
            const unsigned char *bytes = [data bytes];
            uint16_t red = (bytes[0] << 8) | bytes[1];
            uint16_t green = (bytes[2] << 8) | bytes[3];
            uint16_t blue = (bytes[4] << 8) | bytes[5];
            printf("Background: color %.3f %.3f %.3f\n", 
                   red/65535.0, green/65535.0, blue/65535.0);
            return 0;
        }
    }
    
    NSString *imagePath = [store backgroundImagePathForDirectory];
    if (imagePath) {
        printf("Background: image %s\n", [imagePath UTF8String]);
    } else {
        printf("Background: default\n");
    }
    
    return 0;
}

int setBackgroundColor(NSString *storePath, float r, float g, float b) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Create a simple RGB color representation without NSColor
    int redInt = (int)(r * 65535);
    int greenInt = (int)(g * 65535);
    int blueInt = (int)(b * 65535);
    
    DSStoreEntry *entry = [DSStoreEntry backgroundColorEntryForFile:@"." red:redInt green:greenInt blue:blueInt];
    [store setEntry:entry];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set background color to %.3f %.3f %.3f\n", r, g, b);
    return 0;
}

int setBackgroundImage(NSString *storePath, NSString *imagePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setBackgroundImagePathForDirectory:imagePath];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set background image to %s\n", [imagePath UTF8String]);
    return 0;
}

int removeBackground(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store removeEntryForFilename:@"." code:@"BKGD"];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Removed background settings\n");
    return 0;
}

// View management functions
int getView(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSString *viewStyle = [store viewStyleForDirectory];
    int iconSize = [store iconSizeForDirectory];
    
    if (viewStyle) {
        printf("View style: %s\n", [viewStyle UTF8String]);
    }
    
    if (iconSize > 0) {
        printf("Icon size: %d\n", iconSize);
    }
    
    if (!viewStyle && iconSize == 0) {
        printf("View: default\n");
    }
    
    return 0;
}

int setViewStyle(NSString *storePath, NSString *style) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setViewStyleForDirectory:style];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set view style to %s\n", [style UTF8String]);
    return 0;
}

int setIconSize(NSString *storePath, int size) {
    if (size < 16 || size > 512) {
        printf("Error: Icon size must be between 16 and 512\n");
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setIconSizeForDirectory:size];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set icon size to %d\n", size);
    return 0;
}

// New view option functions

int setGridSpacing(NSString *storePath, int spacing) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setGridSpacingForDirectory:spacing];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set grid spacing to %d\n", spacing);
    return 0;
}

int setTextSize(NSString *storePath, int size) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setTextSizeForDirectory:size];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set text size to %d\n", size);
    return 0;
}

int setLabelPosition(NSString *storePath, NSString *position) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreLabelPosition pos = DSStoreLabelPositionBottom;
    if ([position isEqualToString:@"right"]) {
        pos = DSStoreLabelPositionRight;
    }
    
    [store setLabelPositionForDirectory:pos];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set label position to %s\n", [position UTF8String]);
    return 0;
}

int setArrangement(NSString *storePath, NSString *arrangement) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreIconArrangement arr = DSStoreIconArrangementNone;
    if ([arrangement isEqualToString:@"grid"]) {
        arr = DSStoreIconArrangementGrid;
    }
    
    [store setIconArrangementForDirectory:arr];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set icon arrangement to %s\n", [arrangement UTF8String]);
    return 0;
}

int setSortBy(NSString *storePath, NSString *sortBy) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setSortByForDirectory:sortBy];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set sort by to %s\n", [sortBy UTF8String]);
    return 0;
}

int setShowInfo(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowItemInfoForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show item info to %s\n", show ? "true" : "false");
    return 0;
}

int setShowPreview(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowIconPreviewForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show icon preview to %s\n", show ? "true" : "false");
    return 0;
}

// Window chrome functions

int setSidebarWidth(NSString *storePath, int width) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setSidebarWidthForDirectory:width];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set sidebar width to %d\n", width);
    return 0;
}

int setShowToolbar(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowToolbarForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show toolbar to %s\n", show ? "true" : "false");
    return 0;
}

int setShowSidebar(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowSidebarForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show sidebar to %s\n", show ? "true" : "false");
    return 0;
}

int setShowPathBar(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowPathBarForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show path bar to %s\n", show ? "true" : "false");
    return 0;
}

int setShowStatusBar(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setShowStatusBarForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set show status bar to %s\n", show ? "true" : "false");
    return 0;
}

// Get functions for view options

int getIconSize(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    int iconSize = [store iconSizeForDirectory];
    if (iconSize > 0) {
        printf("Icon size: %d\n", iconSize);
    } else {
        printf("Icon size: not set (using default)\n");
    }
    return 0;
}

int getGridSpacing(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    int spacing = [store gridSpacingForDirectory];
    if (spacing > 0) {
        printf("Grid spacing: %d\n", spacing);
    } else {
        printf("Grid spacing: not set (using default)\n");
    }
    return 0;
}

int getTextSize(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    int textSize = [store textSizeForDirectory];
    if (textSize > 0) {
        printf("Text size: %d\n", textSize);
    } else {
        printf("Text size: not set (using default)\n");
    }
    return 0;
}

int getLabelPosition(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreLabelPosition position = [store labelPositionForDirectory];
    const char *positionNames[] = {"bottom", "right"};
    printf("Label position: %s\n", positionNames[position]);
    return 0;
}

int getArrangement(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreIconArrangement arrangement = [store iconArrangementForDirectory];
    const char *arrangementNames[] = {"none", "grid"};
    printf("Icon arrangement: %s\n", arrangementNames[arrangement]);
    return 0;
}

int getSortBy(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSString *sortBy = [store sortByForDirectory];
    if (sortBy) {
        printf("Sort by: %s\n", [sortBy UTF8String]);
    } else {
        printf("Sort by: not set (using default)\n");
    }
    return 0;
}

int getShowInfo(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showInfo = [store showItemInfoForDirectory];
    printf("Show item info: %s\n", showInfo ? "true" : "false");
    return 0;
}

int getShowPreview(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showPreview = [store showIconPreviewForDirectory];
    printf("Show icon preview: %s\n", showPreview ? "true" : "false");
    return 0;
}

// Get functions for window chrome

int getSidebarWidth(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    int width = [store sidebarWidthForDirectory];
    if (width > 0) {
        printf("Sidebar width: %d\n", width);
    } else {
        printf("Sidebar width: not set (using default)\n");
    }
    return 0;
}

int getShowToolbar(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showToolbar = [store showToolbarForDirectory];
    printf("Show toolbar: %s\n", showToolbar ? "true" : "false");
    return 0;
}

int getShowSidebar(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showSidebar = [store showSidebarForDirectory];
    printf("Show sidebar: %s\n", showSidebar ? "true" : "false");
    return 0;
}

int getShowPathBar(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showPathBar = [store showPathBarForDirectory];
    printf("Show path bar: %s\n", showPathBar ? "true" : "false");
    return 0;
}

int getShowStatusBar(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    BOOL showStatusBar = [store showStatusBarForDirectory];
    printf("Show status bar: %s\n", showStatusBar ? "true" : "false");
    return 0;
}

// Label color functions

static const char *labelColorNames[] = {"none", "red", "orange", "yellow", "green", "blue", "purple", "grey"};

int getLabelColor(NSString *storePath, NSString *filename) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreLabelColor color = [store labelColorForFilename:filename];
    printf("Label color for %s: %s\n", [filename UTF8String], labelColorNames[color]);
    return 0;
}

int setLabelColor(NSString *storePath, NSString *filename, NSString *colorName) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreLabelColor color = DSStoreLabelColorNone;
    if ([colorName isEqualToString:@"red"]) color = DSStoreLabelColorRed;
    else if ([colorName isEqualToString:@"orange"]) color = DSStoreLabelColorOrange;
    else if ([colorName isEqualToString:@"yellow"]) color = DSStoreLabelColorYellow;
    else if ([colorName isEqualToString:@"green"]) color = DSStoreLabelColorGreen;
    else if ([colorName isEqualToString:@"blue"]) color = DSStoreLabelColorBlue;
    else if ([colorName isEqualToString:@"purple"]) color = DSStoreLabelColorPurple;
    else if ([colorName isEqualToString:@"grey"] || [colorName isEqualToString:@"gray"]) color = DSStoreLabelColorGrey;
    
    [store setLabelColorForFilename:filename color:color];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set label color for %s to %s\n", [filename UTF8String], [colorName UTF8String]);
    return 0;
}

// Comment management functions
int getComment(NSString *storePath, NSString *filename) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSString *comment = [store commentsForFilename:filename];
    if (comment) {
        printf("Comment for %s: %s\n", [filename UTF8String], [comment UTF8String]);
    } else {
        printf("No comment for %s\n", [filename UTF8String]);
    }
    
    return 0;
}

int setComment(NSString *storePath, NSString *filename, NSString *comment) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store setCommentsForFilename:filename comments:comment];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set comment for %s: %s\n", [filename UTF8String], [comment UTF8String]);
    return 0;
}

// Column view configuration functions (spatial/icon view only)

int getColumnWidth(NSString *storePath, NSString *columnName) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    int width = [store columnWidthForDirectory:columnName];
    printf("Column width for '%s': %d pixels\n", [columnName UTF8String], width);
    return 0;
}

int setColumnWidth(NSString *storePath, NSString *columnName, int width) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    [store setColumnWidthForDirectory:columnName width:width];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set column '%s' width to %d pixels\n", [columnName UTF8String], width);
    return 0;
}

int getColumnVisible(NSString *storePath, NSString *columnName) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    BOOL visible = [store columnVisibleForDirectory:columnName];
    printf("Column '%s' visibility: %s\n", [columnName UTF8String], visible ? "visible" : "hidden");
    return 0;
}

int setColumnVisible(NSString *storePath, NSString *columnName, BOOL visible) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    [store setColumnVisibleForDirectory:columnName visible:visible];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set column '%s' to %s\n", [columnName UTF8String], visible ? "visible" : "hidden");
    return 0;
}

int getRelativeDates(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    BOOL show = [store showRelativeDatesForDirectory];
    printf("Show relative dates in columns: %s\n", show ? "yes" : "no");
    return 0;
}

int setRelativeDates(NSString *storePath, BOOL show) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    // Check if in spatial mode
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle && ![viewStyle isEqual:@"icnv"]) {
        printf("Error: Column view settings only available in spatial/icon view mode (current: %s)\n", [viewStyle UTF8String]);
        return 1;
    }
    
    [store setShowRelativeDatesForDirectory:show];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set relative dates in columns to %s\n", show ? "yes" : "no");
    return 0;
}

// Generic field management functions
int getField(NSString *storePath, NSString *filename, NSString *code) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    DSStoreEntry *entry = [store entryForFilename:filename code:code];
    if (entry) {
        printf("Field %s:%s = (%s) ", [filename UTF8String], [code UTF8String], [[entry type] UTF8String]);
        
        id value = [entry value];
        if ([value isKindOfClass:[NSString class]]) {
            printf("\"%s\"\n", [(NSString *)value UTF8String]);
        } else if ([value isKindOfClass:[NSNumber class]]) {
            printf("%s\n", [[(NSNumber *)value stringValue] UTF8String]);
        } else if ([value isKindOfClass:[NSDate class]]) {
            printf("%s\n", [[(NSDate *)value description] UTF8String]);
        } else if ([value isKindOfClass:[NSData class]]) {
            NSData *data = (NSData *)value;
            printf("<%lu bytes>\n", (unsigned long)[data length]);
        } else {
            printf("%s\n", [[value description] UTF8String]);
        }
    } else {
        printf("No field %s:%s\n", [filename UTF8String], [code UTF8String]);
    }
    
    return 0;
}

int setField(NSString *storePath, NSString *filename, NSString *code, NSString *type, NSString *valueStr) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    id value = nil;
    
    if ([type isEqualToString:@"bool"]) {
        BOOL boolValue = [valueStr isEqualToString:@"true"] || [valueStr isEqualToString:@"1"] || [valueStr isEqualToString:@"yes"];
        value = [NSNumber numberWithBool:boolValue];
    } else if ([type isEqualToString:@"shor"] || [type isEqualToString:@"long"]) {
        value = [NSNumber numberWithLong:[valueStr longLongValue]];
    } else if ([type isEqualToString:@"comp"]) {
        value = [NSNumber numberWithLongLong:[valueStr longLongValue]];
    } else if ([type isEqualToString:@"dutc"]) {
        NSTimeInterval timestamp = [valueStr doubleValue];
        value = [NSDate dateWithTimeIntervalSince1970:timestamp];
    } else if ([type isEqualToString:@"ustr"] || [type isEqualToString:@"type"]) {
        value = valueStr;
    } else if ([type isEqualToString:@"blob"]) {
        // For blob, expect hex string
        NSMutableData *data = [NSMutableData data];
        const char *hexStr = [valueStr UTF8String];
        for (int i = 0; i < strlen(hexStr); i += 2) {
            char hex[3] = {hexStr[i], hexStr[i+1], 0};
            unsigned char byte = (unsigned char)strtol(hex, NULL, 16);
            [data appendBytes:&byte length:1];
        }
        value = data;
    } else {
        printf("Error: Unknown type '%s'\n", [type UTF8String]);
        return 1;
    }
    
    DSStoreEntry *entry = [[DSStoreEntry alloc] initWithFilename:filename code:code type:type value:value];
    [store setEntry:entry];
    [entry release];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Set field %s:%s to (%s) %s\n", [filename UTF8String], [code UTF8String], [type UTF8String], [valueStr UTF8String]);
    return 0;
}

int removeField(NSString *storePath, NSString *filename, NSString *code) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    [store removeEntryForFilename:filename code:code];
    
    if (![store save]) {
        printf("Error: Failed to save .DS_Store file\n");
        return 1;
    }
    
    printf("Removed field %s:%s\n", [filename UTF8String], [code UTF8String]);
    return 0;
}

int listFields(NSString *storePath, NSString *filename) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSArray *codes = [store allCodesForFilename:filename];
    if ([codes count] > 0) {
        printf("Fields for %s:\n", [filename UTF8String]);
        for (NSString *code in codes) {
            DSStoreEntry *entry = [store entryForFilename:filename code:code];
            if (entry) {
                printf("  %s (%s)\n", [code UTF8String], [[entry type] UTF8String]);
            }
        }
    } else {
        printf("No fields for %s\n", [filename UTF8String]);
    }
    
    return 0;
}

int listFiles(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSArray *filenames = [store allFilenames];
    if ([filenames count] > 0) {
        printf("Files with entries:\n");
        for (NSString *filename in filenames) {
            NSArray *codes = [store allCodesForFilename:filename];
            printf("  %s (%lu fields)\n", [filename UTF8String], (unsigned long)[codes count]);
        }
    } else {
        printf("No files found\n");
    }
    
    return 0;
}

int validateFile(NSString *storePath) {
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    NSArray *entries = [store entries];
    printf("Validation results for %s:\n", [storePath UTF8String]);
    printf("  Entries: %lu\n", (unsigned long)[entries count]);
    
    // Count by type
    NSMutableDictionary *typeCounts = [NSMutableDictionary dictionary];
    for (DSStoreEntry *entry in entries) {
        NSString *type = [entry type];
        NSNumber *count = [typeCounts objectForKey:type];
        if (count) {
            [typeCounts setObject:[NSNumber numberWithInt:[count intValue] + 1] forKey:type];
        } else {
            [typeCounts setObject:[NSNumber numberWithInt:1] forKey:type];
        }
    }
    
    printf("  Types:\n");
    for (NSString *type in [typeCounts allKeys]) {
        NSNumber *count = [typeCounts objectForKey:type];
        printf("    %s: %d\n", [type UTF8String], [count intValue]);
    }
    
    printf("  Status: Valid DS_Store file\n");
    return 0;
}

int showInfo(NSString *path) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        printf("Error: File not found: %s\n", [path UTF8String]);
        return 1;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&error];
    if (error) {
        printf("Error getting file attributes: %s\n", [[error localizedDescription] UTF8String]);
        return 1;
    }
    
    NSNumber *fileSize = [attrs objectForKey:NSFileSize];
    NSDate *modDate = [attrs objectForKey:NSFileModificationDate];
    
    printf("File: %s\n", [path UTF8String]);
    printf("Size: %llu bytes\n", [fileSize unsignedLongLongValue]);
    printf("Modified: %s", [[modDate description] UTF8String]);
    
    DSStore *store = [[[DSStore alloc] initWithPath:path] autorelease];
    if ([store load]) {
        NSArray *entries = [store entries];
        printf("Entries: %lu\n", (unsigned long)[entries count]);
        
        // Show background settings
        SimpleColor *bgColor = [store backgroundColorForDirectory];
        NSString *bgImage = [store backgroundImagePathForDirectory];
        if (bgColor) {
            float r, g, b, a;
            [bgColor getRed:&r green:&g blue:&b alpha:&a];
            printf("Background: color (%.2f, %.2f, %.2f)\n", r, g, b);
        } else if (bgImage) {
            printf("Background: image %s\n", [bgImage UTF8String]);
        }
        
        // Show view settings
        NSString *viewStyle = [store viewStyleForDirectory];
        int iconSize = [store iconSizeForDirectory];
        if (viewStyle) {
            printf("View style: %s\n", [viewStyle UTF8String]);
        }
        if (iconSize > 0) {
            printf("List view settings found\n");
        }
    }
    
    return 0;
}

int showSummary(NSString *directoryPath) {
    // Ensure the path is a directory
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if (![fm fileExistsAtPath:directoryPath isDirectory:&isDir] || !isDir) {
        printf("Error: Not a directory: %s\n", [directoryPath UTF8String]);
        return 1;
    }
    
    // Build path to .DS_Store file
    NSString *storePath = [directoryPath stringByAppendingPathComponent:@".DS_Store"];
    if (![fm fileExistsAtPath:storePath]) {
        printf("Error: No .DS_Store file found in %s\n", [directoryPath UTF8String]);
        return 1;
    }
    
    DSStore *store = [[[DSStore alloc] initWithPath:storePath] autorelease];
    if (![store load]) {
        printf("Error: Failed to load .DS_Store file\n");
        return 1;
    }
    
    printf("=== .DS_Store Summary for %s ===\n\n", [directoryPath UTF8String]);
    
    // Get window size from fwi0 field (window info)
    DSStoreEntry *windowEntry = [store entryForFilename:@"." code:@"fwi0"];
    CGFloat windowWidth = 0;
    CGFloat windowHeight = 0;
    CGFloat windowX = 0;
    CGFloat windowY = 0;
    
    if (windowEntry && [[windowEntry type] isEqualToString:@"blob"]) {
        NSData *windowInfo = [windowEntry value];
        if (windowInfo && [windowInfo length] >= 16) {
            const uint8_t *bytes = [windowInfo bytes];
            // fwi0 format: 16 bytes = top(4) left(4) bottom(4) right(4)
            uint32_t top = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
            uint32_t left = (bytes[4] << 24) | (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
            uint32_t bottom = (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
            uint32_t right = (bytes[12] << 24) | (bytes[13] << 16) | (bytes[14] << 8) | bytes[15];
            
            windowX = left;
            windowY = top;
            windowWidth = right - left;
            windowHeight = bottom - top;
            
            printf("Window Position (.DS_Store coordinates):\n");
            printf("  Top-left: (%.0f, %.0f)\n", windowX, windowY);
            printf("\nWindow Size:\n");
            printf("  Width: %.0f pixels\n", windowWidth);
            printf("  Height: %.0f pixels\n", windowHeight);
        } else {
            printf("Window Size: Not set\n");
        }
    } else {
        printf("Window Size: Not set\n");
    }
    
    // Get icon size
    int iconSize = [store iconSizeForDirectory];
    if (iconSize > 0) {
        printf("\nIcon Size: %d pixels\n", iconSize);
    } else {
        printf("\nIcon Size: Not set (using default)\n");
        iconSize = 64; // Default assumption
    }
    
    // Get view style
    NSString *viewStyle = [store viewStyleForDirectory];
    if (viewStyle) {
        printf("\nView Style: %s\n", [viewStyle UTF8String]);
    } else {
        printf("\nView Style: Not set (using default)\n");
    }
    
    // Get background settings
    SimpleColor *bgColor = [store backgroundColorForDirectory];
    NSString *bgImage = [store backgroundImagePathForDirectory];
    
    if (bgColor) {
        float r, g, b, a;
        [bgColor getRed:&r green:&g blue:&b alpha:&a];
        printf("\nBackground: Solid color (R:%.2f G:%.2f B:%.2f)\n", r, g, b);
    } else if (bgImage) {
        printf("\nBackground: Image (%s)\n", [bgImage UTF8String]);
    } else {
        printf("\nBackground: Default\n");
    }
    
    // Get all files with icon positions
    NSArray *entries = [store entries];
    NSMutableArray *filesWithPositions = [NSMutableArray array];
    
    for (DSStoreEntry *entry in entries) {
        if ([[entry code] isEqualToString:@"Iloc"]) {
            [filesWithPositions addObject:[entry filename]];
        }
    }
    
    if ([filesWithPositions count] > 0) {
        printf("\n=== Icon Positions ===\n");
        
        // Sort filenames for consistent output
        NSArray *sortedFiles = [filesWithPositions sortedArrayUsingSelector:@selector(compare:)];
        
        for (NSString *filename in sortedFiles) {
            NSPoint dsPos = [store iconLocationForFilename:filename];
            
            printf("\n%s:\n", [filename UTF8String]);
            printf("  .DS_Store coordinates: (%.0f, %.0f)\n", dsPos.x, dsPos.y);
            
            // Show GNUstep conversion only if we have window height and icon size
            if (windowHeight > 0 && iconSize > 0) {
                NSPoint gnustepPos = [DSStore gnustepPointFromDSStorePoint:dsPos
                                                                viewHeight:windowHeight
                                                                iconHeight:iconSize];
                printf("  GNUstep coordinates:   (%.0f, %.0f)\n", gnustepPos.x, gnustepPos.y);
                printf("  [Converted using window height=%.0f, icon height=%d]\n", 
                       windowHeight, iconSize);
            } else {
                printf("  GNUstep coordinates:   (cannot convert - missing window height or icon size)\n");
            }
        }
    } else {
        printf("\n=== Icon Positions ===\n");
        printf("No icon positions set\n");
    }
    
    printf("\n");
    return 0;
}

int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    if (argc < 2) {
        printUsage();
        [pool drain];
        return 1;
    }
    
    // Parse global flags (-v or --verbose) and shift arguments
    int argOffset = 0;  // Number of global arguments consumed
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "-v") == 0 || strcmp(arg, "--verbose") == 0) {
            gDSStoreVerbose = YES;
            argOffset++;
        } else {
            break;  // Stop at first non-flag argument
        }
    }
    
    // After removing flags, need at least command + pool
    if (argc - argOffset < 2) {
        printUsage();
        [pool drain];
        return 1;
    }
    
    const char *command = argv[1 + argOffset];
    // Convenience macro for shifted argv access
#define ARG(n) argv[(n) + argOffset]
#define ARGC_EFFECTIVE (argc - argOffset)
    
    int result = 0;
    
    if (strcmp(command, "list") == 0) {
        NSString *path = @".DS_Store";
        if (ARGC_EFFECTIVE > 2) {
            path = [NSString stringWithUTF8String:ARG(2)];
        }
        result = listEntries(path);
    } else if (strcmp(command, "dump") == 0) {
        NSString *path = @".DS_Store";
        if (ARGC_EFFECTIVE > 2) {
            path = [NSString stringWithUTF8String:ARG(2)];
        }
        result = dumpAll(path);
    } else if (strcmp(command, "create") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: create command requires path\n");
            result = 1;
        } else {
            NSString *path = [NSString stringWithUTF8String:ARG(2)];
            result = createStore(path);
        }
    } else if (strcmp(command, "set-icon-pos") == 0) {
        if (ARGC_EFFECTIVE < 6) {
            printf("Error: set-icon-pos requires <file> <filename> <x> <y>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            int x = atoi(ARG(4));
            int y = atoi(ARG(5));
            result = setIconPosition(storePath, filename, x, y);
        }
    } else if (strcmp(command, "get-pos") == 0 || strcmp(command, "get-icon") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: get-pos requires <file> <filename>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            result = getIconPosition(storePath, filename);
        }
    } else if (strcmp(command, "set-pos") == 0 || strcmp(command, "set-icon") == 0) {
        if (ARGC_EFFECTIVE < 6) {
            printf("Error: set-pos requires <file> <filename> <x> <y>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            int x = atoi(ARG(4));
            int y = atoi(ARG(5));
            result = setIconPosition(storePath, filename, x, y);
        }
    } else if (strcmp(command, "get-bg") == 0 || strcmp(command, "get-background") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-bg requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getBackground(storePath);
        }
    } else if (strcmp(command, "set-bg-color") == 0 || strcmp(command, "set-background-color") == 0) {
        if (ARGC_EFFECTIVE < 6) {
            printf("Error: set-bg-color requires <file> <r> <g> <b>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            float r = atof(ARG(3));
            float g = atof(ARG(4));
            float b = atof(ARG(5));
            result = setBackgroundColor(storePath, r, g, b);
        }
    } else if (strcmp(command, "set-bg-image") == 0 || strcmp(command, "set-background-image") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-bg-image requires <file> <image_path>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *imagePath = [NSString stringWithUTF8String:ARG(3)];
            result = setBackgroundImage(storePath, imagePath);
        }
    } else if (strcmp(command, "remove-bg") == 0 || strcmp(command, "remove-background") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: remove-bg requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = removeBackground(storePath);
        }
    } else if (strcmp(command, "get-view") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-view requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getView(storePath);
        }
    } else if (strcmp(command, "get-iconsize") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-iconsize requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getIconSize(storePath);
        }
    } else if (strcmp(command, "get-gridspacing") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-gridspacing requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getGridSpacing(storePath);
        }
    } else if (strcmp(command, "get-textsize") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-textsize requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getTextSize(storePath);
        }
    } else if (strcmp(command, "get-labelpos") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-labelpos requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getLabelPosition(storePath);
        }
    } else if (strcmp(command, "get-arrangement") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-arrangement requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getArrangement(storePath);
        }
    } else if (strcmp(command, "get-sortby") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-sortby requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getSortBy(storePath);
        }
    } else if (strcmp(command, "get-showinfo") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-showinfo requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowInfo(storePath);
        }
    } else if (strcmp(command, "get-preview") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-preview requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowPreview(storePath);
        }
    } else if (strcmp(command, "get-sidebar-width") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-sidebar-width requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getSidebarWidth(storePath);
        }
    } else if (strcmp(command, "get-toolbar") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-toolbar requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowToolbar(storePath);
        }
    } else if (strcmp(command, "get-sidebar") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-sidebar requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowSidebar(storePath);
        }
    } else if (strcmp(command, "get-pathbar") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-pathbar requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowPathBar(storePath);
        }
    } else if (strcmp(command, "get-statusbar") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-statusbar requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getShowStatusBar(storePath);
        }
    } else if (strcmp(command, "set-view") == 0 || strcmp(command, "set-view-style") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-view requires <file> <style>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *style = [NSString stringWithUTF8String:ARG(3)];
            result = setViewStyle(storePath, style);
        }
    } else if (strcmp(command, "set-iconsize") == 0 || strcmp(command, "set-icon-size") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-iconsize requires <file> <size>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            int size = atoi(ARG(3));
            result = setIconSize(storePath, size);
        }
    } else if (strcmp(command, "set-gridspacing") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-gridspacing requires <file> <spacing>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            int spacing = atoi(ARG(3));
            result = setGridSpacing(storePath, spacing);
        }
    } else if (strcmp(command, "set-textsize") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-textsize requires <file> <size>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            int size = atoi(ARG(3));
            result = setTextSize(storePath, size);
        }
    } else if (strcmp(command, "set-labelpos") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-labelpos requires <file> <position>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *position = [NSString stringWithUTF8String:ARG(3)];
            result = setLabelPosition(storePath, position);
        }
    } else if (strcmp(command, "set-arrangement") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-arrangement requires <file> <arrangement>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *arrangement = [NSString stringWithUTF8String:ARG(3)];
            result = setArrangement(storePath, arrangement);
        }
    } else if (strcmp(command, "set-sortby") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-sortby requires <file> <key>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *sortBy = [NSString stringWithUTF8String:ARG(3)];
            result = setSortBy(storePath, sortBy);
        }
    } else if (strcmp(command, "set-showinfo") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-showinfo requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowInfo(storePath, show);
        }
    } else if (strcmp(command, "set-preview") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-preview requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowPreview(storePath, show);
        }
    } else if (strcmp(command, "set-sidebar-width") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-sidebar-width requires <file> <width>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            int width = atoi(ARG(3));
            result = setSidebarWidth(storePath, width);
        }
    } else if (strcmp(command, "set-toolbar") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-toolbar requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowToolbar(storePath, show);
        }
    } else if (strcmp(command, "set-sidebar") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-sidebar requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowSidebar(storePath, show);
        }
    } else if (strcmp(command, "set-pathbar") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-pathbar requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowPathBar(storePath, show);
        }
    } else if (strcmp(command, "set-statusbar") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-statusbar requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setShowStatusBar(storePath, show);
        }
    } else if (strcmp(command, "get-label") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: get-label requires <file> <filename>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            result = getLabelColor(storePath, filename);
        }
    } else if (strcmp(command, "set-label") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: set-label requires <file> <filename> <color>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            NSString *color = [NSString stringWithUTF8String:ARG(4)];
            result = setLabelColor(storePath, filename, color);
        }
    } else if (strcmp(command, "get-comment") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: get-comment requires <file> <filename>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            result = getComment(storePath, filename);
        }
    } else if (strcmp(command, "set-comment") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: set-comment requires <file> <filename> <comment>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            NSString *comment = [NSString stringWithUTF8String:ARG(4)];
            result = setComment(storePath, filename, comment);
        }
    } else if (strcmp(command, "get-column-width") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: get-column-width requires <file> <column>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *columnName = [NSString stringWithUTF8String:ARG(3)];
            result = getColumnWidth(storePath, columnName);
        }
    } else if (strcmp(command, "set-column-width") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: set-column-width requires <file> <column> <pixels>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *columnName = [NSString stringWithUTF8String:ARG(3)];
            int width = atoi(ARG(4));
            result = setColumnWidth(storePath, columnName, width);
        }
    } else if (strcmp(command, "get-column-visible") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: get-column-visible requires <file> <column>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *columnName = [NSString stringWithUTF8String:ARG(3)];
            result = getColumnVisible(storePath, columnName);
        }
    } else if (strcmp(command, "set-column-visible") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: set-column-visible requires <file> <column> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *columnName = [NSString stringWithUTF8String:ARG(3)];
            BOOL visible = atoi(ARG(4)) != 0;
            result = setColumnVisible(storePath, columnName, visible);
        }
    } else if (strcmp(command, "get-relative-dates") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: get-relative-dates requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = getRelativeDates(storePath);
        }
    } else if (strcmp(command, "set-relative-dates") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: set-relative-dates requires <file> <0|1>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            BOOL show = atoi(ARG(3)) != 0;
            result = setRelativeDates(storePath, show);
        }
    } else if (strcmp(command, "get") == 0 || strcmp(command, "get-field") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: get requires <file> <filename> <code>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            NSString *code = [NSString stringWithUTF8String:ARG(4)];
            result = getField(storePath, filename, code);
        }
    } else if (strcmp(command, "set") == 0 || strcmp(command, "set-field") == 0) {
        if (ARGC_EFFECTIVE < 7) {
            printf("Error: set requires <file> <filename> <code> <type> <value>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            NSString *code = [NSString stringWithUTF8String:ARG(4)];
            NSString *type = [NSString stringWithUTF8String:ARG(5)];
            NSString *value = [NSString stringWithUTF8String:ARG(6)];
            result = setField(storePath, filename, code, type, value);
        }
    } else if (strcmp(command, "remove") == 0 || strcmp(command, "remove-field") == 0) {
        if (ARGC_EFFECTIVE < 5) {
            printf("Error: remove requires <file> <filename> <code>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            NSString *code = [NSString stringWithUTF8String:ARG(4)];
            result = removeField(storePath, filename, code);
        }
    } else if (strcmp(command, "fields") == 0 || strcmp(command, "list-fields") == 0) {
        if (ARGC_EFFECTIVE < 4) {
            printf("Error: fields requires <file> <filename>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            NSString *filename = [NSString stringWithUTF8String:ARG(3)];
            result = listFields(storePath, filename);
        }
    } else if (strcmp(command, "files") == 0 || strcmp(command, "list-files") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: files requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = listFiles(storePath);
        }
    } else if (strcmp(command, "validate") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: validate requires <file>\n");
            result = 1;
        } else {
            NSString *storePath = [NSString stringWithUTF8String:ARG(2)];
            result = validateFile(storePath);
        }

    } else if (strcmp(command, "info") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: info command requires path\n");
            result = 1;
        } else {
            NSString *path = [NSString stringWithUTF8String:ARG(2)];
            result = showInfo(path);
        }
    } else if (strcmp(command, "summary") == 0) {
        if (ARGC_EFFECTIVE < 3) {
            printf("Error: summary command requires directory path\n");
            result = 1;
        } else {
            NSString *dirPath = [NSString stringWithUTF8String:ARG(2)];
            result = showSummary(dirPath);
        }
    } else {
        // Check if single argument is a directory (shorthand for summary)
        if (ARGC_EFFECTIVE == 2) {
            NSString *path = [NSString stringWithUTF8String:ARG(1)];
            NSFileManager *fm = [NSFileManager defaultManager];
            BOOL isDir = NO;
            if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
                result = showSummary(path);
            } else {
                printf("Error: Unknown command: %s\n", command);
                printUsage();
                result = 1;
            }
        } else {
            printf("Error: Unknown command: %s\n", command);
            printUsage();
            result = 1;
        }
    }
    
#undef ARG
#undef ARGC_EFFECTIVE
    
    [pool drain];
    return result;
}
