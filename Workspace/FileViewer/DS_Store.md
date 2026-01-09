# `.DS_Store` Integration Architecture

This document describes the architecture for `.DS_Store` file support in Workspace, enabling interoperability with external file managers that use the same format.

## Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           GWSpatialViewer                                │
│                      (Window Controller Layer)                           │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │  dsStoreInfo (retained ivar)                                     │    │
│  │  - Loaded once per directory                                     │    │
│  │  - Reused across view type changes                               │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│         │                    │                      │                    │
│         ▼                    ▼                      ▼                    │
│  ┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐         │
│  │ Icon View   │    │   List View     │    │  Browser View    │         │
│  │ (FSNIcons-  │    │ (FSNListView)   │    │  (FSNBrowser)    │         │
│  │  View)      │    │                 │    │                  │         │
│  └─────────────┘    └─────────────────┘    └──────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
         │                    │                      │
         ▼                    ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                          FSNode Framework                                │
│  ┌─────────────┐    ┌─────────────────┐    ┌──────────────────┐         │
│  │   FSNIcon   │    │ FSNListView-    │    │ FSNBrowserCell   │         │
│  │             │    │  NodeRep        │    │                  │         │
│  │ - tagColor  │    │                 │    │                  │         │
│  │ - spotlight │    │                 │    │                  │         │
│  │   Comment   │    │                 │    │                  │         │
│  └─────────────┘    └─────────────────┘    └──────────────────┘         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Layers

### 1. DSStore Library (Low-Level Parser)

**Location**: `DSStore/`

**Purpose**: Binary file parsing for .DS_Store format

**Key Classes**:
- `DSStore` - Opens and reads .DS_Store files using B-tree structure
- `DSStoreEntry` - Individual record with filename, code (4-char), type, and value

**Entry Types**:
| Type | Description | Value Class |
|------|-------------|-------------|
| `bool` | Boolean flag | NSNumber |
| `long` | 32-bit integer | NSNumber |
| `shor` | 16-bit integer | NSNumber |
| `blob` | Binary data | NSData |
| `ustr` | UTF-16 string | NSString |
| `type` | 4-character code | NSString |

**Usage**:
```objc
DSStore *store = [DSStore storeWithPath:@"/path/to/.DS_Store"];
DSStoreEntry *entry = [store entryForFilename:@"." code:@"icvp"];
NSData *plistData = (NSData *)[entry value];
```

### 2. DSStoreInfo (High-Level Model)

**Location**: `Workspace/FileViewer/DSStoreInfo.h/m`

**Purpose**: Object-oriented wrapper providing typed access to DS_Store data

**Classes**:

#### DSStoreIconInfo
Per-file metadata container:
```objc
@interface DSStoreIconInfo : NSObject
@property NSString *filename;
@property NSPoint position;        // GNUstep coordinates (converted)
@property BOOL hasPosition;
@property NSString *comments;      // Spotlight comment
@property DSStoreLabelColor labelColor;
@property BOOL hasLabelColor;

// Coordinate conversion
- (NSPoint)gnustepPositionForViewHeight:(CGFloat)viewHeight 
                             iconHeight:(CGFloat)iconHeight;
@end
```

#### DSStoreInfo
Directory-level metadata:
```objc
@interface DSStoreInfo : NSObject
// Window geometry
@property NSRect windowFrame;
@property DSStoreViewStyle viewStyle;

// Icon view settings
@property int iconSize;
@property DSStoreIconArrangement iconArrangement;
@property DSStoreLabelPosition labelPosition;
@property CGFloat gridSpacing;

// Background
@property DSStoreBackgroundType backgroundType;
@property NSColor *backgroundColor;
@property NSString *backgroundImagePath;

// List view settings
@property int listTextSize;
@property NSString *sortColumn;
@property NSDictionary *columnWidths;
@property NSDictionary *columnVisible;

// Per-file data
- (DSStoreIconInfo *)iconInfoForFilename:(NSString *)filename;
- (NSDictionary *)allIconInfo;
@end
```

### 3. GWSpatialViewer (Controller)

**Location**: `Workspace/FileViewer/GWSpatialViewer.h/m`

**Purpose**: Coordinates DS_Store loading and application to views

**Key Methods**:
```objc
// Stored as retained ivar for view switching
@interface GWSpatialViewer : NSObject {
    DSStoreInfo *dsStoreInfo;
}

// Apply methods called during init and view type changes
- (void)applyDSStoreSettingsToIconView:(id)iconView;
- (void)applyDSStoreSettingsToListView:(id)listView;
- (void)applyDSStoreSettingsToBrowserView:(id)browserView;

// Accessor for external use
- (DSStoreInfo *)dsStoreInfo;
@end
```

**Lifecycle**:
1. `initForNode:` - Creates and loads DSStoreInfo, applies to initial view
2. `setViewerType:` - Switches view type, calls appropriate apply method
3. `windowWillClose:` - (Future) Save modified DSStoreInfo

### 4. FSNode Framework Views

**Location**: `FSNode/`

**Purpose**: View components that display file system nodes

#### FSNIconsView
Icon grid/free-positioning view:
```objc
@interface FSNIconsView : NSView
// DS_Store support
@property BOOL freePositioningEnabled;
@property NSMutableDictionary *customIconPositions;
@property CGFloat dsStoreGridSpacing;

- (void)setTagColorsFromDictionary:(NSDictionary *)tagDict;
- (void)setCommentsFromDictionary:(NSDictionary *)commentsDict;
- (void)setGridSpacing:(CGFloat)spacing;
@end
```

#### FSNIcon
Individual icon representation:
```objc
@interface FSNIcon : NSView <FSNodeRep>
@property NSColor *tagColor;
@property NSString *spotlightComment;

// Draws tag color dot in drawRect:
// Sets tooltip from spotlightComment
@end
```

#### FSNListView / FSNListViewDataSource
Table-based list view:
```objc
@interface FSNListViewDataSource : NSObject
- (void)setSortColumn:(FSNInfoType)sortType;
- (FSNInfoType)sortColumn;
- (void)setColumnWidth:(float)width forIdentifier:(FSNInfoType)identifier;
@end
```

## Coordinate System Conversion

DS_Store files use a top-left origin coordinate system. GNUstep uses a bottom-left origin (standard PostScript/PDF coordinates).

```
DS_Store Coordinates          GNUstep Coordinates
┌──────────────────┐          ┌──────────────────┐
│(0,0)      (w,0)  │          │                  │(w,h)
│                  │          │                  │
│                  │    →     │                  │
│                  │          │                  │
│(0,h)      (w,h)  │          │(0,0)      (w,0)  │
└──────────────────┘          └──────────────────┘
```

**Conversion Formula**:
```objc
// DS_Store → GNUstep
gnustepY = viewHeight - dsStoreY - iconHeight;

// GNUstep → DS_Store (for saving)
dsStoreY = viewHeight - gnustepY - iconHeight;
```

## Data Flow

### Loading Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   .DS_Store     │────▶│    DSStore      │────▶│  DSStoreEntry   │
│   (binary)      │     │   (B-tree)      │     │   (parsed)      │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                                                        │
                        ┌───────────────────────────────┘
                        ▼
                ┌─────────────────┐
                │   DSStoreInfo   │
                │  (typed model)  │
                └─────────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│ Icon View   │ │ List View   │ │Browser View │
│ Settings    │ │ Settings    │ │ Settings    │
└─────────────┘ └─────────────┘ └─────────────┘
```

### View Type Switching

```
User clicks "List View" button
        │
        ▼
GWSpatialViewer -setViewerType:
        │
        ├── Create new FSNListView
        ├── Call [nodeView showContentsOfNode:]
        └── Call [self applyDSStoreSettingsToListView:nodeView]
                    │
                    ├── Apply sort column
                    ├── Apply column widths
                    └── Apply tag colors (future)
```

## Memory Management

GNUstep uses manual retain/release memory management:

```objc
// In GWSpatialViewer
- (instancetype)initForNode:(FSNode *)anode {
    // ...
    DSStoreInfo *dsInfo = [DSStoreInfo infoForDirectoryPath:path];
    ASSIGN(dsStoreInfo, dsInfo);  // Retains dsInfo
    // ...
}

- (void)dealloc {
    RELEASE(dsStoreInfo);
    [super dealloc];
}
```

**Key Pattern**: Use `ASSIGN()` macro to safely retain new value and release old value.

## DS_Store Field Mapping

### Directory-Level Fields (filename = ".")

| DS_Store Code | Type | DSStoreInfo Property | Description |
|---------------|------|---------------------|-------------|
| `vstl` | `type` | `viewStyle` | View mode (icnv/Nlsv/clmv) |
| `fwi0` | `blob` | `windowFrame` | Window position/size |
| `bwsp` | `blob` | Multiple | Binary plist with window settings |
| `icvo` | `blob` | Icon settings | Legacy icon view options |
| `icvp` | `blob` | Icon settings | Modern icon view plist |
| `lsvp` | `blob` | List settings | List view plist |
| `fwsw` | `long` | `sidebarWidth` | Sidebar width |
| `BKGD` | `type` | `backgroundType` | Background type code |

### Per-File Fields

| DS_Store Code | Type | DSStoreIconInfo Property | Description |
|---------------|------|-------------------------|-------------|
| `Iloc` | `blob` | `position` | Icon x,y position (16 bytes) |
| `lclr` | `blob` | `labelColor` | Label color index (6 bytes) |
| `cmmt` | `ustr` | `comments` | Spotlight comment |

## Protocol Conformance

Views conform to the `FSNodeRepContainer` protocol:
```objc
@protocol FSNodeRepContainer
- (void)showContentsOfNode:(FSNode *)anode;
- (FSNode *)shownNode;
- (NSArray *)selectedNodes;
// ... many more methods
@end
```

Icon representations conform to `FSNodeRep`:
```objc
@protocol FSNodeRep
- (FSNode *)node;
- (BOOL)isSelected;
- (void)select;
// ... many more methods
@end
```

## Error Handling

The implementation is defensive about missing/corrupt DS_Store files:

```objc
- (BOOL)load {
    NSString *dsStorePath = [_directoryPath 
        stringByAppendingPathComponent:@".DS_Store"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dsStorePath]) {
        _loaded = NO;
        return NO;  // No DS_Store file - use defaults
    }
    
    DSStore *store = [DSStore storeWithPath:dsStorePath];
    if (!store) {
        _loaded = NO;
        return NO;  // Corrupt or unreadable
    }
    
    // Parse with nil checks on each field...
}
```

## Extensibility

To add support for a new DS_Store field:

1. **Add property to DSStoreInfo.h**:
   ```objc
   @property (nonatomic, assign) BOOL newFeature;
   @property (nonatomic, assign) BOOL hasNewFeature;
   ```

2. **Add parsing in DSStoreInfo.m**:
   ```objc
   - (void)loadNewFeatureFromStore:(DSStore *)store {
       DSStoreEntry *entry = [store entryForFilename:@"." code:@"nwft"];
       if (entry) {
           _newFeature = [[entry value] boolValue];
           _hasNewFeature = YES;
       }
   }
   ```

3. **Apply in GWSpatialViewer.m**:
   ```objc
   - (void)applyDSStoreSettingsToIconView:(id)iconView {
       if (dsStoreInfo.hasNewFeature) {
           // Apply to view
       }
   }
   ```
