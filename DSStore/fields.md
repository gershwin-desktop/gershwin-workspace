# .DS_Store Field Reference

Complete reference for .DS_Store file field codes, data types, and coordinate systems used by libDSStore.

## Data Types

| Type Code | Name | Format | Description |
|-----------|------|--------|-------------|
| `bool` | Boolean | 1 byte | Single byte: 0x00 (false) or 0x01 (true) |
| `shor` | Short Integer | 4 bytes | 16-bit signed integer with 2 padding bytes |
| `long` | Long Integer | 4 bytes | 32-bit signed integer, big-endian |
| `comp` | Composite | 8 bytes | 64-bit signed integer, big-endian |
| `dutc` | Date/Time | 8 bytes | 1/65536 seconds since January 1, 1904 |
| `type` | Type Code | 4 bytes | Four-character ASCII string |
| `blob` | Binary Data | Variable | Length-prefixed binary data |
| `ustr` | Unicode String | Variable | UTF-16 Big-Endian string |

## Field Codes Reference

### Background and View Settings

| Field Code | Type | Description |
|------------|------|-------------|
| `BKGD` | blob | **Background Settings** - 12 bytes: DefB/ClrB/PctB type + data |
| `vstl` | type | **View Style** - 4 chars: icnv, clmv, glyv, Nlsv, Flwv |
| `bwsp` | blob | **Browser Window Settings (Modern, 10.6+)** - Binary plist with layout data |
| `fwi0` | blob | **Window Info (Legacy, pre-10.6)** - 16 bytes: top/left/bottom/right + view style |
| `fwsw` | long | **Sidebar Width** - Sidebar width in pixels |
| `fwvh` | long | **Window Height** - Window height override |

### Icon Positioning and Layout

| Field Code | Type | Description |
|------------|------|-------------|
| `Iloc` | blob | **Icon Location** - 16 bytes: x, y (4-byte ints, icon center) + 8 bytes padding |
| `dilc` | blob | **Desktop Icon Location** - 32 bytes: percentage coordinates (÷1000) |
| `icgo` | blob | **Icon Grid Options** - 8 bytes, grid spacing data |
| `icsp` | blob | **Icon Spacing** - 8 bytes, icon spacing data |
| `icvp` | blob | **Icon View Properties (Modern, 10.6+)** - Binary plist with icon view settings |
| `icvo` | blob | **Icon View Options (Legacy, pre-10.6)** - 18+ bytes (icvo/icv4 variants) |

### List View Configuration

| Field Code | Type | Description |
|------------|------|-------------|
| `lsvp` | blob | **List View Properties (Modern, 10.6+)** - Binary plist with settings |
| `lsvP` | blob | **List View Properties Alt (Modern, 10.7+)** - Binary plist variant |
| `lsvC` | blob | **List View Properties Alt 2 (Modern)** - Binary plist variant |
| `lsvo` | blob | **List View Options (Legacy, pre-10.6)** - 76 bytes legacy format |
| `lssp` | blob | **List View Scroll Position** - 8 bytes scroll data |
| `lsvt` | long | **List View Text Size** - Text size in points |

### File Metadata

| Field Code | Type | Description |
|------------|------|-------------|
| `cmmt` | ustr | **Comments** - Spotlight comments for files/folders |
| `logS` | long | **Logical Size (Legacy)** - File/folder size in bytes |
| `lg1S` | long | **Logical Size** - File/folder logical size (newer) |
| `phyS` | long | **Physical Size (Legacy)** - Physical size in bytes |
| `ph1S` | long | **Physical Size** - Physical size (newer) |
| `modD` | dutc/blob | **Modification Date** - File modification timestamp |
| `moDD` | dutc/blob | **Modification Date (Alt)** - Alternative timestamp |
| `extn` | ustr | **Extension** - File extension information |
| `info` | blob | **File Info** - Additional file information |

### Other Settings

| Field Code | Type | Description |
|------------|------|-------------|
| `ICVO` | bool | **Icon View Options** - Icon view boolean flag |
| `LSVO` | bool | **List View Options** - List view boolean flag |
| `dscl` | bool | **Default List View** - Whether to open in list view |
| `GRP0` | ustr | **Group/Sort Settings** - Grouping parameters |
| `pict` | blob | **Background Picture** - Alias record to background image |
| `vSrn` | long | **Version/Serial Number** - Version identifier |

## Reference Tables

### View Style Codes (vstl field)

| Code | View Mode |
|------|-----------|
| `icnv` | Icon view |
| `clmv` | Column view |
| `glyv` | Gallery view |
| `Nlsv` | List view |
| `Flwv` | Coverflow view |

### Background Type Codes (BKGD field)

| Code | Background Type |
|------|----------------|
| `DefB` | Default background |
| `ClrB` | Solid color background |
| `PctB` | Picture background |

### Icon Arrangement Codes

| Code | Arrangement |
|------|-------------|
| `none` | No arrangement |
| `grid` | Snap to grid |

### Label Position Codes

| Code | Position |
|------|----------|
| `botm` | Bottom |
| `rght` | Right |

## Implementation Notes

1. **Legacy vs Modern - Format Preference**: Many fields have legacy/modern pairs. **Always prefer the modern format when both are present:**
   - **Window Geometry**: Use `bwsp` (10.6+) over `fwi0` (pre-10.6)
   - **Icon View Settings**: Use `icvp` (10.6+) over `icvo` (pre-10.6)
   - **List View Settings**: Use `lsvp/lsvP` (10.6+) over `lsvo` (pre-10.6)
   - **File Sizes**: Use `lg1S`/`ph1S` (10.8+) over `logS`/`phyS` (10.7)
   
   Modern formats use binary property lists (fields ending in 'p') with richer data and extensibility.
   Legacy formats use fixed binary structures that are less flexible.

2. **Binary Plists**: Fields ending with 'p' often contain binary property lists parseable with standard plist libraries.

3. **Coordinate Systems**: 
   - **Iloc**: Absolute pixel coordinates of **icon center** from **top-left** of window content area
     - Format: [x(4 bytes), y(4 bytes), padding(8 bytes)] = 16 bytes total
     - Data type: Two 4-byte big-endian **signed integers** (int32)
     - Origin: (0,0) = top-left of window content area
     - Increases rightward (x) and downward (y)
   - **dilc**: Percentage-based coordinates for desktop icons
     - Format: 32-byte structure with coordinates at offset 16-24
     - Values in thousandths (divide by 1000.0 for percentages)
     - Origin: (0,0) = top-left of desktop screen

4. **Timestamps**: `dutc` format uses 1/65536 seconds from January 1, 1904; `blob` format varies by field.

5. **Window Info (fwi0) Structure**:
   - **Bytes 0-7**: Window rect as four 2-byte big-endian unsigned integers
     - Bytes 0-1: top edge
     - Bytes 2-3: left edge  
     - Bytes 4-5: bottom edge
     - Bytes 6-7: right edge
   - **Bytes 8-11**: View style (4CC: icnv/clmv/Nlsv/Flwv)
   - **Bytes 12-15**: Flags/unknown (often zeros or 00 01 00 00)

6. **Icon View Options (icvo) Structure** - Two variants:
   - **"icvo" format** (18 bytes minimum):
     - 4 bytes: magic "icvo"
     - 8 bytes: flags (unknown purpose)
     - 2 bytes: icon size (big-endian uint16)
     - 4 bytes: arrangement ("none" or "grid")
   - **"icv4" format** (26 bytes):
     - 4 bytes: magic "icv4"
     - 2 bytes: icon size in pixels (big-endian uint16)
     - 4 bytes: arrangement 4CC ("none" or "grid")
     - 4 bytes: label position 4CC ("botm" or "rght")
     - 12 bytes: flags (bit 1 of byte 2 = "Show item info", bit 0 of byte 12 = "Show icon preview")

7. **Background Settings (BKGD) Structure** (12 bytes):
   - **"DefB"**: Default background + 8 bytes (likely garbage)
   - **"ClrB"**: Color background + 6 bytes RGB (2 bytes per channel, big-endian uint16) + 2 unknown bytes
   - **"PctB"**: Picture background + 4 bytes length + 4 unknown bytes (actual image in 'pict' field as Alias record)

8. **Partially Understood**: Some fields have known structure but unknown semantics or partial reverse-engineering.
