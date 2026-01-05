# DSStore Library

A GNUstep library providing .DS_Store interoperability for reading and writing .DS_Store files, built as an integrated subproject of gworkspace.

## Overview

DSStore provides .DS_Store interoperability through a pure GNUstep/Objective-C implementation for manipulating .DS_Store files. These files store metadata about files and folders, including:

- Icon positions and view styles
- Background images and colors  
- Window geometry and view settings
- File comments and labels
- Sort order and column configuration

**Architecture**: Built as an internal gworkspace subproject with companion command-line tool in `Tools/dsutil/`.

**Interoperability**: This library is designed to enable cross-platform compatibility with .DS_Store files created by macOS and other systems. The implementation is based on documentation provided by third-party sources and enables reading and writing of .DS_Store metadata for better interoperability with other operating systems.

## Features

- **File Operations**: Read, write, create, and validate .DS_Store files
- **Entry Types**: Full support for bool, long, blob, ustr, type, comp, dutc formats  
- **Metadata Access**: Icon positions, view settings, backgrounds, comments
- **Blob Decoding**: Automatic parsing of common binary data types
- **Command-Line Tool**: Complete CLI interface for inspection and modification
- **GNUstep Integration**: Native Objective-C with full Foundation compatibility
- **.DS_Store Interoperability**: Coordinate conversion between .DS_Store and GNUstep coordinate systems
- **Cross-Platform Compatibility**: Works with .DS_Store files from macOS and other systems

## Entry Types and Field Codes

**Data Types**:
- `bool`: Boolean values
- `long`/`shor`: 32-bit integers
- `blob`: Binary data (auto-decoded for known formats)
- `ustr`: Unicode strings (UTF-16BE)
- `type`: 4-character type codes
- `comp`/`dutc`: 64-bit integers/timestamps

**Common Field Codes**:
- `Iloc`: Icon coordinates (x, y pixels of icon center from window top-left)
- `bwsp`: Browser window state (binary plist)
- `lsvp`/`lsvP`: List view properties (binary plist)
- `icvp`: Icon view properties (binary plist)  
- `pBBk`: Background picture bookmark
- `cmmt`: File/folder comments
- `vstl`: View style setting

## API Reference

### Basic Operations

```objc
#import <DSStore/DSStore.h>

// Load existing .DS_Store file
DSStore *store = [DSStore storeWithPath:@"/path/to/.DS_Store"];
if ([store load]) {
    NSArray<DSStoreEntry *> *entries = store.entries;
    
    // Get icon position (returns .DS_Store coordinates)
    NSPoint pos = [store iconLocationForFilename:@"file.txt"];
    
    // Set icon position (x, y in .DS_Store coordinates)
    [store setIconLocationForFilename:@"file.txt" x:100 y:200];
    
    // Save changes
    [store save];
}

// Create new .DS_Store file
DSStore *newStore = [DSStore createStoreAtPath:@"/new/.DS_Store" withEntries:nil];
[newStore setIconLocationForFilename:@"document.pdf" x:50 y:100];
[newStore save];
```

### Coordinate Conversion for .DS_Store Interoperability

Convert between .DS_Store and GNUstep coordinate systems:

```objc
// .DS_Store uses top-left origin (y↓), GNUstep uses bottom-left origin (y↑)
// viewHeight and iconHeight are REQUIRED parameters - no defaults assumed

NSPoint dsPoint = NSMakePoint(100, 150);
CGFloat viewHeight = 600.0;  // Height of the containing view
CGFloat iconHeight = 64.0;   // Height of the icon

// Convert .DS_Store coordinates to GNUstep coordinates
NSPoint gnustepPoint = [DSStore gnustepPointFromDSStorePoint:dsPoint 
                                                  viewHeight:viewHeight 
                                                  iconHeight:iconHeight];

// Convert GNUstep coordinates to .DS_Store coordinates
NSPoint backToDSStore = [DSStore dsStorePointFromGNUstepPoint:gnustepPoint 
                                                   viewHeight:viewHeight 
                                                   iconHeight:iconHeight];
```

### Entry Manipulation

```objc
// Create custom entry
DSStoreEntry *entry = [[DSStoreEntry alloc] initWithFilename:@"file.txt"
                                                        code:@"cmmt" 
                                                        type:@"ustr"
                                                       value:@"My note"];
[store setEntry:entry];
[entry release];

// Get specific entry
DSStoreEntry *existing = [store entryForFilename:@"file.txt" code:@"Iloc"];

// Remove entry
[store removeEntryForFilename:@"file.txt" code:@"cmmt"];
```

### View Settings

```objc
// Get/set view style
NSString *style = [store viewStyleForDirectory];
[store setViewStyleForDirectory:@"icon"];

// Get/set icon size
int iconSize = [store iconSizeForDirectory];
[store setIconSizeForDirectory:64];

// Get/set background color
SimpleColor *color = [store backgroundColorForDirectory];
[store setBackgroundColorForDirectory:color];

// Get/set background image
NSString *imagePath = [store backgroundImagePathForDirectory];
[store setBackgroundImagePathForDirectory:@"/path/to/image.jpg"];
```

### Icon View Options

```objc
// Grid spacing
int spacing = [store gridSpacingForDirectory];
[store setGridSpacingForDirectory:100];

// Text size for labels
int textSize = [store textSizeForDirectory];
[store setTextSizeForDirectory:12];

// Label position (bottom or right)
DSStoreLabelPosition pos = [store labelPositionForDirectory];
[store setLabelPositionForDirectory:DSStoreLabelPositionRight];

// Show item info
BOOL showInfo = [store showItemInfoForDirectory];
[store setShowItemInfoForDirectory:YES];

// Show icon previews
BOOL showPreview = [store showIconPreviewForDirectory];
[store setShowIconPreviewForDirectory:YES];

// Icon arrangement (none or grid)
DSStoreIconArrangement arr = [store iconArrangementForDirectory];
[store setIconArrangementForDirectory:DSStoreIconArrangementGrid];

// Sort by
NSString *sortBy = [store sortByForDirectory];
[store setSortByForDirectory:@"name"];
```

### Window Chrome Settings

```objc
// Sidebar width
int sidebarWidth = [store sidebarWidthForDirectory];
[store setSidebarWidthForDirectory:200];

// Toolbar visibility
BOOL showToolbar = [store showToolbarForDirectory];
[store setShowToolbarForDirectory:YES];

// Sidebar visibility
BOOL showSidebar = [store showSidebarForDirectory];
[store setShowSidebarForDirectory:YES];

// Path bar visibility
BOOL showPathBar = [store showPathBarForDirectory];
[store setShowPathBarForDirectory:YES];

// Status bar visibility
BOOL showStatusBar = [store showStatusBarForDirectory];
[store setShowStatusBarForDirectory:YES];
```

### File Label Colors

```objc
// Get/set file label color (0-7: none, red, orange, yellow, green, blue, purple, grey)
DSStoreLabelColor color = [store labelColorForFilename:@"file.txt"];
[store setLabelColorForFilename:@"file.txt" color:DSStoreLabelColorRed];
```

## Command-Line Tool

The `dsutil` tool in `Tools/dsutil/` provides comprehensive .DS_Store manipulation with automatic coordinate conversion display:

```bash
# Global flags (available for all commands)
dsutil -v <command> <args>                # Enable verbose debug output
dsutil --verbose <command> <args>         # Verbose mode (shows B-tree structure, block offsets, etc.)

# Icon positioning (shows both .DS_Store and GNUstep coordinates)
$ dsutil get-pos .DS_Store image.jpg
Icon position for image.jpg:
  .DS_Store coordinates: (100, 150)
  GNUstep equivalent: (100, 386) [assuming view height=600, icon height=64]
  Note: .DS_Store uses top-left origin (y↓), GNUstep uses bottom-left origin (y↑)

$ dsutil set-pos .DS_Store image.jpg 100 200
Set icon position for image.jpg:
  .DS_Store coordinates: (100, 200) [center of icon]
  GNUstep equivalent: (100, 336) [assuming view height=600, icon height=64]

# Directory summary with coordinate conversions
dsutil summary /path/to/directory         # Comprehensive summary
dsutil /path/to/directory                 # Shorthand (directory detection)

# Background settings
dsutil get-bg .DS_Store                   # Show background
dsutil set-bg-color .DS_Store 0.9 0.9 1.0    # Set color background
dsutil set-bg-image .DS_Store /path/to/bg.jpg # Set image background

# View configuration
dsutil set-view .DS_Store icon            # Set view style
dsutil set-iconsize .DS_Store 64          # Set icon size
dsutil set-gridspacing .DS_Store 100      # Set grid spacing
dsutil set-textsize .DS_Store 12          # Set label text size
dsutil set-labelpos .DS_Store right       # Set label position (bottom|right)
dsutil set-arrangement .DS_Store grid     # Set arrangement (none|grid)
dsutil set-sortby .DS_Store name          # Set sort (name|date|size|kind|label|none)
dsutil set-showinfo .DS_Store 1           # Show item info
dsutil set-preview .DS_Store 1            # Show icon previews

# Window chrome
dsutil set-sidebar-width .DS_Store 200    # Set sidebar width
dsutil set-toolbar .DS_Store 1            # Show toolbar
dsutil set-sidebar .DS_Store 1            # Show sidebar
dsutil set-pathbar .DS_Store 1            # Show path bar
dsutil set-statusbar .DS_Store 1          # Show status bar

# Label colors
dsutil get-label .DS_Store file.txt       # Get file label color
dsutil set-label .DS_Store file.txt red   # Set label color
# Colors: none, red, orange, yellow, green, blue, purple, grey

# File operations
dsutil list .DS_Store                     # List entries
dsutil dump .DS_Store                     # Complete dump
dsutil create /new/.DS_Store              # Create new file

# Generic field access
dsutil get .DS_Store file.txt Iloc        # Get any field
dsutil set .DS_Store file.txt cmmt ustr "Note"  # Set field
dsutil fields .DS_Store file.txt          # List all fields
```

The **summary** command provides comprehensive output with automatic coordinate conversions:
- Window position and size (from fwi0 field)
- Icon size and view style
- Background settings
- All icon positions with both .DS_Store and GNUstep coordinates
- Coordinate conversions use actual window height and icon size from .DS_Store file

Example output:
```
=== .DS_Store Summary for /path/to/directory ===

Window Position (.DS_Store coordinates):
  Top-left: (100, 200)

Window Size:
  Width: 800 pixels
  Height: 600 pixels

Icon Size: 64 pixels

View Style: icnv

Background: Default

=== Icon Positions ===

document.pdf:
  .DS_Store coordinates: (150, 100) [icon center]
  GNUstep coordinates:   (150, 436)
  [Converted using window height=600, icon height=64]

image.jpg:
  .DS_Store coordinates: (300, 250) [icon center]
  GNUstep coordinates:   (300, 286)
  [Converted using window height=600, icon height=64]
```

Run `dsutil` without arguments for complete command reference.

## Building

**Requirements**: GNUstep development environment, modern C compiler

**Build as part of gworkspace** (recommended):
```bash
# From gworkspace root directory
make && sudo make install
```

**Build library only** (from `DSStore/` directory):
```bash
make
```

The command-line tool builds automatically with the Tools subproject.

## File Format and Implementation

**.DS_Store Structure**:
1. **Buddy Allocator Header**: Block allocation management
2. **DSDB Superblock**: B-tree metadata 
3. **B-tree Nodes**: Sorted entry storage

**Entry Format**: Each entry contains filename (UTF-16BE), 4-character code, 4-character type, and value data.

**.DS_Store Interoperability**: Works with files created by various .DS_Store-generating applications, Python `ds_store` library, and other .DS_Store tools.

**Thread Safety**: Not thread-safe - use appropriate synchronization for multi-threaded access.

**Limitations**: Complex B-tree structures are simplified during writes; some advanced features may not be fully supported.

## Coordinate System for .DS_Store Interoperability

**Icon Positioning in .DS_Store format**:
- **Origin**: Top-left corner of window content area
- **X-axis**: Increases rightward in pixels  
- **Y-axis**: Increases downward in pixels
- **Coordinates**: Specify center point of icon (not corner)

**GNUstep Coordinate System**:
- **Origin**: Bottom-left corner of view
- **X-axis**: Increases rightward in pixels
- **Y-axis**: Increases upward in pixels

Use the coordinate conversion methods to translate between systems. The viewHeight and iconHeight parameters are REQUIRED - the library does not assume default values.

## Development Notes

### Implemented Features

**View Properties** (per-folder settings now available):
- Label colors (None, Red, Orange, Yellow, Green, Blue, Purple, Grey)
- Icon size and grid spacing
- Text size and label position (bottom/right)
- Item info display and icon previews
- Sort options (None, Name, Date, Size, Kind, Label)
- Sidebar/Toolbar/Path bar/Status bar visibility
- Icon arrangement (None, Grid)
- Column view configuration (relative dates, column widths, visibility)

### Column View Configuration (Spatial Mode Only)

**Current Limitation**: Column view configuration methods and CLI commands are currently limited to directories with spatial/icon view mode enabled. This ensures proper coordination with native .DS_Store implementations where column view metadata is typically stored separately.

**Supported in Spatial/Icon Mode**:
- Getting/setting individual column widths
- Controlling column visibility
- Setting relative date display in column headers

**Not Supported (yet)**:
- Column view configuration for list view mode
- Column view configuration for column view mode  
- Column view configuration for gallery or flow modes

**Roadmap**: Once spatial mode column view is fully tested and stable, support will be extended to other view modes. Use the library in spatial mode for now to ensure compatibility.

### Future Enhancements

**Advanced Features** (planned for future implementation):
- Binary plist parsing for icvp/lsvp fields
- Alias record parsing for background images

### Error Handling

The library provides comprehensive error handling including invalid file format detection, corrupted data recovery attempts, missing file handling, and write permission checks.

## Examples and Documentation

See the `dsutil` command-line tool source code for comprehensive usage examples. The tool serves as both a practical utility and reference implementation demonstrating all library features.

Additional documentation: [DSStore/fields.md](fields.md) - Complete .DS_Store field reference

## About This Implementation

**Based On**: This library is built on documentation provided by third-party sources and research into the .DS_Store file format. It is designed to enable interoperability with .DS_Store files created by macOS and other operating systems, allowing GNUstep and Unix-like systems to read, understand, and manipulate the metadata stored in these files.

**Interoperability Goal**: To provide seamless cross-platform compatibility, enabling users on Unix-like systems to work with .DS_Store metadata without losing formatting or layout information when exchanging files with macOS systems.

**Resources**: 
- [DSStoreParser documentation](https://github.com/forensiclunch/DSStoreParser/blob/495485b263adfb56f13bca0c68d640b2e462948b/README.md#L35)
- [DSStoreView application](https://github.com/macmade/DSStoreView)

## License

Copyright (c) 2025-26 Simon Peter

SPDX-License-Identifier: BSD-2-Clause

## Contributing

Contributions are welcome! Please ensure code follows project standards and includes appropriate tests.
