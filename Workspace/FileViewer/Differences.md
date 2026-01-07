# DS_Store Interoperability - Feature Differences

This document lists features present in .DS_Store files that are not fully supported in Workspace, along with implementation hints for achieving full interoperability.

## Icon View

### ✅ Supported
- **Icon size** (`icvo`/`icvp` → `iconSize`) - Applied via `setIconSize:`
- **Label position** (`icvo`/`icvp` → `labelOnBottom`) - Bottom or right positioning
- **Background color** (`bwsp`/`BKGD` → `backgroundColor`) - Solid color backgrounds
- **Background image** (`bwsp` → `backgroundImagePath`) - Picture backgrounds
- **Free icon positioning** (`Iloc`) - Custom icon positions with coordinate conversion
- **Grid spacing** (`icvp` → `gridSpacing`) - Additional spacing between icons
- **Label colors/tags** (`lclr`) - Colored dots rendered on icons
- **Spotlight comments** (`cmmt`) - Displayed as tooltips

### ⚠️ Partial Support
| Feature | DS_Store Field | Current Status | Implementation Hint |
|---------|---------------|----------------|---------------------|
| Icon arrangement | `icvo`/`icvp` → `arrangeBy` | Parsed but not applied | Add `setSortType:` calls based on arrangement value (name, date, size, kind) |
| Text size | `icvp` → `textSize` | Parsed but not applied | Modify `FSNIcon` to support variable `labelTextSize` per-view |
| Show icon preview | `icvp` → `showIconPreview` | Not parsed | Add boolean property to enable/disable thumbnail previews |
| Show item info | `icvo`/`icvp` → `showItemInfo` | Not parsed | Display file size/date below icon when enabled |

### ❌ Not Supported
| Feature | DS_Store Field | Implementation Hint |
|---------|---------------|---------------------|
| Scroll position | `icvp` → `scrollPositionX/Y` | Store scroll offset, restore in `showContentsOfNode:` |
| View options inheritance | `icvo` → `viewOptionsVersion` | Track version for per-folder vs inherited settings |

---

## List View

### ✅ Supported
- **Sort column** (`lsvp` → `sortColumn`) - Applied via `setSortColumn:`
- **Column widths** (`lsvp` → `columns[].width`) - Applied via `setColumnWidth:forIdentifier:`

### ⚠️ Partial Support
| Feature | DS_Store Field | Current Status | Implementation Hint |
|---------|---------------|----------------|---------------------|
| Text size | `lsvp` → `textSize` | Parsed, not applied | Modify `FSNListViewDataSource` to set row height and font size |
| Icon size | `lsvp` → `iconSize` | Parsed, not applied | Add `setRowIconSize:` to control small icon dimensions |
| Sort ascending | `lsvp` → `ascending` | Parsed, not applied | Add `setSortAscending:` method, reverse sort order |
| Column visibility | `lsvp` → `columns[].visible` | Parsed, not applied | Add/remove columns dynamically based on visibility |

### ❌ Not Supported
| Feature | DS_Store Field | Implementation Hint |
|---------|---------------|---------------------|
| Column order | `lsvp` → `columns[].index` | Reorder columns via `moveColumn:toColumn:` |
| Calculate all sizes | `lsvp` → `calculateAllSizes` | Pre-calculate folder sizes in background |
| Use relative dates | `lsvp` → `useRelativeDates` | Format dates as "Today", "Yesterday" etc. |

---

## Browser (Column) View

### ✅ Supported
- **Sidebar width** (`fwsw`) - Parsed and logged

### ❌ Not Supported
| Feature | DS_Store Field | Implementation Hint |
|---------|---------------|---------------------|
| Variable column widths | `clw*` entries | **Major redesign needed**: `FSNBrowser` uses uniform `columnSize` calculated from `frameWidth / visibleColumns`. Need to store per-column widths in array and adjust `tile` method |
| Column visibility | `cv*` entries | Add column show/hide capability |
| Preview column | `pBB*` entries | Add optional preview pane on right side |
| Column width per-directory | Per-directory `clw*` | Track column widths by directory path |

**Architecture change required**: Replace fixed `columnSize` with `NSMutableArray *columnWidths` and modify:
```objc
// In FSNBrowser.h
NSMutableArray *columnWidths;  // CGFloat values per column

// In -tile method
for (i = 0; i < [columns count]; i++) {
    CGFloat colWidth = [[columnWidths objectAtIndex:i] floatValue];
    colrect.size.width = colWidth;
    colrect.origin.x = currentX;
    currentX += colWidth;
    // ... position column
}
```

---

## Window Geometry

### ✅ Supported
- **Window frame** (`fwi0`/`bwsp`) - Position and size with coordinate conversion
- **View style** (`vstl`/`icvp`) - Icon, list, or column view selection

### ⚠️ Partial Support
| Feature | DS_Store Field | Current Status | Implementation Hint |
|---------|---------------|----------------|---------------------|
| Sidebar width | `fwsw` | Parsed, not applied | No sidebar in spatial mode; useful for browser mode |

### ❌ Not Supported
| Feature | DS_Store Field | Implementation Hint |
|---------|---------------|---------------------|
| Window toolbar | `bwsp` → `showToolbar` | Add toolbar show/hide state |
| Window sidebar | `bwsp` → `showSidebar` | Add sidebar visibility state |
| Tab state | `bwsp` → `tabs` | Workspace doesn't support tabbed windows |

---

## Per-File Metadata

### ✅ Supported
- **Icon location** (`Iloc`) - 16-byte blob with x,y coordinates
- **Label color** (`lclr`) - 1-7 color index
- **Comments** (`cmmt`) - UTF-16 string for Spotlight comments

### ❌ Not Supported
| Feature | DS_Store Field | Implementation Hint |
|---------|---------------|---------------------|
| Finder flags | `fwi0` per-file | Extended attributes for stationery pad, alias, etc. |
| Icon location in dock | `dilc` | Dock icon positioning |
| Discovery level | `dscl` | Alias resolution depth |
| Extended finder info | `extn` | Custom file type info |
| Logical size | `lg1S` | Logical file size for display |
| Physical size | `ph1S` | Physical file size for display |
| Put away folder | `ptbL`/`ptbN` | Original location for items in Trash |

---

## DS_Store Saving

### ❌ Not Implemented
Currently, Workspace only **reads** .DS_Store files. Writing is not supported.

**Required for full interoperability:**

1. **Track dirty state**: Set flag when user modifies:
   - Window position/size
   - Icon positions (drag)
   - View type
   - Sort column
   - Column widths

2. **Save on window close**: In `GWSpatialViewer -windowWillClose:`:
   ```objc
   - (void)windowWillClose:(NSNotification *)notification
   {
       if (dsStoreInfo && dsStoreInfoDirty) {
           [dsStoreInfo saveToFile];
       }
   }
   ```

3. **DSStore library modifications**: Add write support:
   ```objc
   // DSStore.h
   - (BOOL)setEntry:(DSStoreEntry *)entry forFilename:(NSString *)filename;
   - (BOOL)writeToFile:(NSString *)path error:(NSError **)error;
   
   // DSStoreInfo.h  
   - (BOOL)save;
   - (BOOL)saveToPath:(NSString *)path;
   ```

4. **Coordinate conversion for save**: Reverse the Y-axis conversion:
   ```objc
   - (NSPoint)dsStorePointForGNUstepPosition:(NSPoint)gnustepPos
                                  viewHeight:(CGFloat)viewHeight
                                  iconHeight:(CGFloat)iconHeight
   {
       return NSMakePoint(gnustepPos.x, 
                          viewHeight - gnustepPos.y - iconHeight);
   }
   ```

---

## Priority Implementation Order

1. **DS_Store saving** - Critical for bidirectional interoperability
2. **Variable browser column widths** - Common user expectation
3. **Sort ascending/descending** - Simple addition
4. **Column visibility in list view** - Moderate complexity
5. **Text size in list/icon views** - Font handling complexity
6. **Preview column in browser** - Major feature addition
