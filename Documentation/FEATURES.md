# Features and Finder metadata interoperability

## Intent

Workspace's intent is to be **interoperable with Finder regarding the use of
metadata**: a folder opened in Finder after Workspace modified it, and a
folder opened in Workspace after Finder modified it, must show the same view
settings, icon positions, labels, and other metadata.

That intent makes it necessary to implement a **comparable feature set that
uses and supports that metadata** - the features below exist so Workspace can
read, write, preserve, and interoperate with the metadata Finder relies on,
using the same on-disk encodings and the same storage locations.

Each table lists a Finder feature, the metadata it uses, how Workspace
implements it, and its **implementation status**.  Status values:

| Status | Meaning |
|--------|---------|
| **Implemented** | Workspace reads and writes this feature's metadata and applies it in the UI |
| **Partial** | Partly implemented (e.g. reads but does not write, or stored but not applied in the UI) |
| **Read-only** | Workspace reads/preserves the metadata but does not modify or apply it |
| **Preserved** | The metadata is carried forward on load/save but not interpreted |
| **Not implemented** | No handling in Workspace |

---

# Folder Presentation Features (.DS_Store)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Icon view | `vSrn` record field `viewMode` (`icnv`) | Read/write `vSrn.viewMode`; also ensure `ICVO` record exists for legacy compatibility | Present since classic Finder | **Implemented** |
| List view | `vSrn` record field `viewMode` (`Nlsv`) | Same as above | Present since classic Finder | **Implemented** |
| Column view | `vSrn` record field `viewMode` (`clmv`) | Same as above | Introduced in Mac OS X 10.2 Jaguar | **Implemented** |
| Gallery view | `vSrn` record field `viewMode` (`Flwv`) | Same as above; fallback to icon view if not implemented | Introduced in macOS 10.15 Catalina | **Preserved** (decoded on read; UI falls back to icon view; re-save rewrites as `icnv`) |
| Cover Flow view | `vSrn` record field `viewMode` (`flcw`) | Support only if full backwards compatibility desired; requires a cover-flow style layout | Introduced in Mac OS X 10.5 Leopard, removed in macOS 10.9 Mavericks | **Preserved** (`Flwv` decoded on read; UI falls back to icon view; `flcw` not handled; re-save rewrites as `icnv`) |
| Window geometry | `fwi0` record field `WindowBounds` | Read/write four-byte integers: top, left, bottom, right (as per `Rect`) |  | **Implemented** (read/write `bwsp` + `fwi0`, applied on open) |
| Sidebar width | `fwi0` record field `SidebarWidth` | Read/write 32-bit integer width in points | Sidebar introduced in Mac OS X 10.3 Panther | **Partial** (`fwsw`/`bwsp` read+write; applied in non-spatial viewer only) |
| Toolbar visibility | `fwi0` record field `ToolbarVisible` | Read/write Boolean | Toolbar introduced in Mac OS X 10.0 Cheetah | **Not implemented** |
| Status bar visibility | `fwi0` record field `StatusbarVisible` | Read/write Boolean | Introduced in Mac OS X 10.3 Panther | **Not implemented** |
| Path bar visibility | `fwi0` record field `PathbarVisible` | Read/write Boolean | Introduced in Mac OS X 10.4 Tiger | **Not implemented** |
| Preview pane visibility | `fwi0` record (field name unknown - likely `ShowPreview` or `PreviewPaneVisible`) | Boolean toggle; reverse-engineer by capturing Finder writes after toggling View → Show Preview | Introduced in Mac OS X 10.6 Snow Leopard | **Not implemented** (kept in user defaults only) |
| Tab bar visibility | `fwi0` record (field name unknown - likely `ShowTabBar`) | Boolean toggle; reverse-engineer similarly | Introduced in OS X 10.9 Mavericks | **Not implemented** |
| Icon size | `vSrn` record field `iconSize` (also present in `ICVO`) | Read/write 32-bit integer; range 16-512 points |  | **Partial** (read/write `icvo`; applied in spatial viewer only) |
| Text size | `vSrn` record field `textSize` (also in `ICVO`) | Read/write 32-bit integer (e.g., 10, 12, 14, 16) |  | **Partial** (read/write `lsvp` textSize; not applied in the UI) |
| Grid spacing | `vSrn` record field `gridSpacing` | Read/write floating-point value (grid cell size) |  | **Partial** (read/write; applied in spatial viewer only) |
| Label position | `vSrn` record field `labelPosition` (0 = bottom, 1 = right) | Read/write boolean (or integer) |  | **Implemented** (spatial viewer) |
| Arrange by | `vSrn` record field `arrangeBy` (string: `name`, `kind`, `dateLastOpened`, `dateAdded`, `dateModified`, `dateCreated`, `size`, `tags`, `none`) | Read/write string; grouping headers appear accordingly | Introduced in Mac OS X 10.4 Tiger | **Partial** (read/write `iarr`; not applied in the UI) |
| Snap to grid | `vSrn` record field `snapToGrid` | Read/write Boolean |  | **Partial** (read/write `iarr`; grid snap only via manual Clean Up, not driven by the record) |
| Show item info | `vSrn` record field `showItemInfo` | Read/write Boolean | Introduced in Mac OS X 10.4 Tiger | **Not implemented** |
| Show icon preview | `vSrn` record field `showIconPreview` | Read/write Boolean | Introduced in Mac OS X 10.5 Leopard | **Not implemented** |
| Background color | `vSrn` record fields `backgroundColor` (RGB) or legacy `BKGD` record | Read/write color structure; if modern `vSrn` absent, use `BKGD` |  | **Implemented** (spatial viewer) |
| Background image | `vSrn` record field `backgroundAlias` (alias data) or legacy `BKGD` record | Store an alias bookmark to an image file; apply tiling/stretching as per Finder |  | **Partial** (read via `pict`; write writes only a `PctB` placeholder, no image path) |
| Scroll position | `vSrn` record field `scrollPosition` (two 32-bit ints: horizontal, vertical) | Restore content offset when folder is reopened |  | **Not implemented** |
| List sort column | `LSVO` record field `sortColumn` (string identifier) | e.g., `name`, `dateModified`, `size`, `kind`, `dateCreated`, `dateLastOpened`, `dateAdded`, `tags` |  | **Partial** (read/write `lsvp` sortColumn; applied in spatial viewer) |
| List sort direction | `LSVO` record field `sortDirection` (0 = ascending, 1 = descending) | Read/write integer |  | **Partial** (read/write `lsvp` ascending; always sorted ascending in the UI) |
| Column visibility | `LSVO` record field `columns` (array of structures: {`id`, `width`, `visible`}) | Show/hide each column; if `visible` false, width ignored |  | **Partial** (read/write; visibility flag not applied) |
| Column widths | `LSVO` record field `columns` → each entry’s `width` (integer) | Set width in points |  | **Implemented** (spatial viewer) |
| Column order | `LSVO` record field `columns` array order | The array order defines left-to-right order |  | **Partial** (order lost when read into a dictionary; not applied) |
| Show relative dates | `LSVO` record field `useRelativeDates` (Boolean) | Display “Today” / “Yesterday” instead of absolute dates |  | **Not implemented** |
| Calculate all sizes | `LSVO` record field `calculateAllSizes` (Boolean) | Force calculation of folder sizes for all items (performance warning) |  | **Not implemented** |

---

# Per-file Presentation (stored in .DS_Store or as xattr)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Icon position (folder-relative) | `.DS_Store` `Iloc` record | Per-file: store x,y coordinates (two 32-bit integers) for each file shown in icon view | Present since classic Finder | **Implemented** |
| Finder icon position (file-travelling) | `com.apple.FinderInfo` xattr, field `fdLocation` (four-byte vertical, four-byte horizontal) | Update `fdLocation` when icon is dragged; modern Finder also writes `Iloc` | Present since classic Finder | **Implemented** |
| Label colour | `com.apple.FinderInfo` xattr, `fdFlags` bits 1-3 (3-bit colour index) | Index 0 = no label, 1-7 correspond to colour labels; colour names stored in Finder preferences | Introduced in Mac OS 8; modern tags use separate xattr | **Implemented** (shared encoding 1=Red..7=Grey with `.DS_Store` lclr; also writes `_kMDItemUserTags`) |
| Finder comment | `.DS_Store` `cmmt` record (type `cmmt`) **or** `com.apple.metadata:kMDItemFinderComment` xattr | Store UTF-8 text; the comment record is per-file; modern Finder prefers the xattr |  | **Partial** (reads both; shows cmmt as tooltip; no UI to edit comments) |
| Custom icon | `com.apple.FinderInfo` xattr `fdFlags` bit `kHasCustomIcon` + `com.apple.ResourceFork` xattr (icon image data) | Set the flag; write icon image (icns format) to resource fork | Present since classic Finder | **Partial** (read + apply; write via API `setCustomIconData:`; no UI action to set) |
| Hidden filename extension | `com.apple.FinderInfo` xattr `fdFlags` bit `kHasExtensionHidden` (0x0400) | Toggle this bit; Finder hides extension when bit is set **unless** global “Show all extensions” is enabled | Introduced in Mac OS X 10.3 Panther | **Not implemented** |
| Stationery pad | `com.apple.FinderInfo` xattr `fdFlags` bit `kIsStationery` (0x0040) | Double-click opens a copy; original left unchanged | Present since classic Mac OS | **Partial** (behaviour applied on open; no UI control to set it) |
| Bundle bit | `com.apple.FinderInfo` xattr `fdFlags` bit `kHasBundle` (0x0100) | Treat the file as a package (opaque folder); allows “Show Package Contents” | Present since classic Mac OS | **Partial** (model read/write only; UI uses its own package detection) |
| Invisible flag | `com.apple.FinderInfo` xattr `fdFlags` bit `kIsInvisible` (0x0008) | File hidden unless “Show invisible files” is enabled | Present since classic Mac OS | **Partial** (read + applied to filtering; no UI toggle) |
| Name locked | `com.apple.FinderInfo` xattr `fdFlags` bit `kNameLocked` (0x0080) | Rename operation is blocked by Finder | Present since classic Mac OS | **Partial** (model read/write only; not applied in the UI) |

---

# File Metadata (separate extended attributes & resource fork)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| File type code | `com.apple.FinderInfo` xattr `fdType` (four-character code) | Used for legacy application binding; e.g. `'TEXT'`, `'APPL'` | Present since classic Mac OS | **Partial** (model read/write only; not applied in the UI) |
| Creator code | `com.apple.FinderInfo` xattr `fdCreator` (four-character code) | Binds file to a specific application (creator signature) | Present since classic Mac OS | **Partial** (read + applied to open-app selection; no UI write) |
| Custom icon resource | `com.apple.ResourceFork` xattr (or actual resource fork on HFS+) | Contains icon family (`icns` resources) | Present since classic Mac OS | **Partial** (read + applied; write via API `setCustomIconData:`; no UI action to set) |
| Finder tags | `com.apple.metadata:_kMDItemUserTags` xattr | Property list containing array of tag label strings and colour numbers; write as binary plist | Introduced in OS X 10.9 Mavericks | **Implemented** (read/write binary plist; label setter keeps tags in sync; label display falls back to tags) |
| Extended attributes (generic) | All xattrs on the file system | Preserve any unknown attributes; copy on file duplication/move | Introduced in Mac OS X 10.4 Tiger | **Not implemented** (only the four known xattrs are handled; unknown AppleDouble entries are dropped on sidecar rewrite) |
| AppleDouble fallback (`._` sidecar) | AppleDouble format (contains FinderInfo, resource fork, all xattrs) | Automatically create on FAT/exFAT/UDF/SMB without xattr support; parse when reading | Compatibility mechanism since Mac OS X 10.0 | **Implemented** (read + write fallback on xattr failure; `_kMDItemUserTags` carried in sidecar) |

---

# Local Cache Features (when .DS_Store cannot be written)

| Finder feature | Storage | Implementation | Notes | Implementation Status |
|----------------|---------|----------------|------|-----------------------|
| Read-only folder layout | `~/Library/Caches/com.apple.finder/` cache files (same internal format as `.DS_Store`) | When write to target folder fails, create a cache file keyed by volume ID and inode; fallback read on open |  | **Implemented** (cache keyed by `f_fsid`-derived volume ID; tiered read/write falls back to cache) |
| Network folder layout | Same cache directory | Used when `DSDontWriteNetworkStores` is `true` or network volume is read-only |  | **Implemented** (`DSDontWriteNetworkStores` policy + read-only detection gate the folder write and route to the cache) |
| Root volume layout | Same cache directory | `/`, `/System`, `/Volumes` etc. are read-only for regular users |  | **Implemented** (generic read-only path routes root/System to the cache) |
| Offline / removable media | Same cache directory | Layout preserved even after media ejected |  | **Not implemented** (no preserve-on-eject or read-after-eject path) |

---

# Unsupported Features

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Gallery View | `vSrn` view mode | Can be implemented as an alternative layout; otherwise revert to icon view |  | **Partial** (decoded on read; UI falls back to icon view; re-save rewrites as `icnv`) |
| Cover Flow view | `vSrn` view mode (`flcw`) | Only if full historical compatibility needed |  | **Partial** (`Flwv` decoded; UI falls back to icon view; `flcw` not handled; re-save rewrites as `icnv`) |
| iCloud integration | Various (ubiquity metadata) | Requires iCloud services and daemons |  | **Not implemented** |
| AirDrop | None | System service; relies on Bonjour and AWDL |  | **Not implemented** |
| Quick Look integration | None (framework) | Can invoke `qlmanage` or Quick Look API externally; not metadata-driven |  | **Not implemented** |
| Finder Sync extensions | Various (extension-specific) | Third-party extension API introduced in OS X 10.10 Yosemite |  | **Not implemented** |
