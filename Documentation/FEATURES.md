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
| **Under investigation** | Finder's behaviour is being measured on the Mac; nothing is promised yet |

Every row also says how it was verified: **Mac-verified (Referee)** means a
Finder 10.6.8 on a real Mac wrote it and Workspace read it, Workspace wrote it
and Finder honoured it, and a Finder-written record survived a Workspace save
(`Documentation/interop/referee-2026-10-11.md`); **tests only** means the
behaviour is pinned by the ObjectTesting suites against bytes a 10.6 Finder
wrote (`Tests/GWMetadata/interop/fixtures/finder106/`) but the reverse
direction was not shown on the Mac.  `E<n>` cites
`Documentation/interop/evidence.md`.  The oracle is Finder 10.6.8: the Mac is
always right.

Where the records live (E1, E2, E14): the view and window records of a folder
(`icvp`, `lsvp`, `bwsp`, `vstl`) are kept in the **parent folder's**
`.DS_Store`, under the folder's name.  Finder 10.6 ignores `.` records in the
folder's own store.  Only a volume root and the home folder keep them as `.`
in their own store.  Per-item records (`Iloc`, `cmmt`, `dilc`) are in the
store of the folder the item sits in.  Finder 10.6 does not use `vSrn`,
`LSVO`, `ICVO` or `fwi0` for any of this, and writes no `lclr` record.


---

# Folder Presentation Features (.DS_Store)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Icon view | `vstl` = `icnv` plus `icvp` record, both in the parent's store | Read/write; a `vstl` is written only after the user chose a view type for that folder ("Always open in"), as Finder does (E5) | Present since classic Finder.  Without `vstl` the default view applies | **Implemented** (Mac-verified (Referee); E5, E6, E8) |
| List view | `vstl` = `Nlsv` plus `lsvp` record, parent's store | Same as above | Present since classic Finder | **Implemented** (Mac-verified (Referee); E5, E10) |
| Column view | `vstl` = `clmv` | Read and written; `clmv` maps to Workspace's browser (column) view | Introduced in Mac OS X 10.2.  See the column view section below | **Implemented** (view style only, tests only; column view options are under investigation; E5, E8) |
| Gallery view | `vstl` = `Flwv`/`glyv` | Decoded on read; UI falls back to icon view | Introduced in macOS 10.15 | **Preserved** (re-save writes the view actually used; tests only) |
| Cover Flow view | `vstl` = `Flwv`/`flcw` | Decoded on read; UI falls back to icon view | Mac OS X 10.5 to 10.8 | **Preserved** (tests only) |
| Always open in <view> | `vstl` in the parent's store | Written only when the user switched the view type in that window; unticking removes `vstl` from the parent's store, the folder's own store and the volume cache | Finder 10.6 writes no `vstl` without the checkbox (E5) | **Implemented** (Mac-verified (Referee); E5) |
| Window geometry | `bwsp` `WindowBounds` (parent's store), string `{{x,y},{w,h}}`, origin bottom left, y up, height includes the 22 pt title bar | Read/write; converted between points and device pixels so it comes back right at any GSScaleFactor | Not `fwi0` (that is the pre-10.6 record and is no longer written) | **Implemented** (Mac-verified (Referee); E7) |
| Sidebar width | `bwsp` `SidebarWidth`, honoured per folder | Read/write; applied in the browsing viewer | Only width 192 tried on the Mac | **Partial** (applied in browsing viewer only; Mac-verified (Referee) for 192, other widths tests only; E13) |
| Toolbar visibility / spatial vs browsing window | `bwsp` `ShowToolbar`, per folder | A spatial window records `ShowToolbar` 0, a browsing window 1; a folder whose record says so opens as that kind of window.  Only a window of another kind than the folder would open in is recorded, as Finder writes nothing for an untouched window | Finder's windows without a toolbar are its spatial ones (E13) | **Implemented** (tests only; E13) |
| Status bar visibility | `ShowStatusBar` in `bwsp` snapshot; real state is Finder's global `com.apple.finder` setting | View menu "Show Status Bar" with a checkmark, a setting of all windows, kept under Finder's name by GWViewerChrome; all open windows follow at once | Bars are global in Finder 10.6, not per folder (E13) | **Implemented** (tests only; E13) |
| Path bar visibility | `ShowPathbar`, same as above | View menu "Show Path Bar", same mechanism | Introduced in Mac OS X 10.4 | **Implemented** (tests only; E13) |
| Sidebar visibility | `bwsp` `ShowSidebar` (snapshot of Finder's global setting) | Read and written as a snapshot | Global in Finder (E13) | **Partial** (kept, not toggled per window) |
| Preview pane visibility | not found in 10.6 | 10.6 Finder has no preview pane record | Preview column belongs to column view (see below) | **Not implemented** (kept in user defaults only) |
| Tab bar visibility | not in 10.6 | Not applicable to the 10.6 oracle | Introduced in OS X 10.9 | **Not implemented** |
| View Options window | `icvp` / `lsvp` options, `vstl` | Cmd-J opens the View Options panel (Workspace/ViewOptions/): icon and text size, grid spacing, arrange by, label position, show item info, show icon preview, background, list columns, calculate all sizes, relative dates, "Always open in"; edits go to the records of the folder shown | Panel created only changes an `icvp` or `lsvp` when an option really changed | **Implemented** (tests only; MI-VO) |
| Icon size | `icvp` `iconSize`, real number | Read/write 16-512; applied in icon and list view | | **Implemented** (Mac-verified (Referee); E6, E8) |
| Text size | `icvp` / `lsvp` `textSize`, clamped to 10-16 | Read/write; applied to icon and list view | | **Implemented** (Mac-verified (Referee); E8) |
| Grid spacing | `icvp` `gridSpacing`, real | Read/write and applied to the icon view (range 54-100 in the panel) | Slider range is a guess | **Implemented** (tests only; E8) |
| Label position | `icvp` `labelOnBottom` | Read/write; applied | | **Implemented** (Mac-verified (Referee); E8) |
| Arrange by | `icvp` `arrangeBy`: `none`, `grid`, `name`, `kind`, `dateModified`, `dateCreated`, `size`, `label` | Read/write and applied; `grid` is snap to grid; a newer Finder's value Workspace cannot show is kept until the user changes the arrangement | Orders measured in E25 | **Implemented** (Mac-verified (Referee) for none/grid; other values tests only; E8, E25) |
| Snap to grid | `icvp` `arrangeBy` = `grid` | Mapped to the icon view's snap | | **Implemented** (Mac-verified (Referee); E8, E25) |
| Show item info | `icvp` `showItemInfo` | Read/write; wording per E23 | | **Implemented** (Mac-verified (Referee); E8, E23) |
| Show icon preview | `icvp` `showIconPreview` | Read/write; applied | Default and "off" per E26 | **Implemented** (Mac-verified (Referee); E8, E26) |
| Background color | `icvp` `backgroundType` 1 plus RGB reals | Read/write; applied; a legacy `BKGD` colour Finder 10.6 ignores is never turned into an `icvp` | | **Implemented** (Mac-verified (Referee); E6, E12) |
| Background image | `icvp` `backgroundType` 2 plus `backgroundImageAlias` (classic alias record v2, HFS path) | Read/write; applied by the spatial viewer | Volume name in the alias is a guess; a Finder-written picture was not read back on the Mac | **Partial** (tests only; E12) |
| Scroll position | `icvp` and `lsvp` `scrollPositionX/Y`, reals, points from the top left | Restored when the folder opens and written back on close, for icon and list view; not re-applied when a window only comes to the front | | **Implemented** (tests only; Referee did not cover it; E11) |
| List sort column | `lsvp` `sortColumn` | Read/write; applied | | **Implemented** (Mac-verified (Referee); E10, E20) |
| List sort direction | `lsvp` `columns` -> `<column>` -> `ascending`, kept per column | Read/write; every column keeps its own direction | First-click direction per column measured in E20 | **Implemented** (Mac-verified (Referee); E10, E20) |
| Column visibility | `lsvp` `columns` -> `visible` | Read/write; applied | | **Implemented** (Mac-verified (Referee); E8, E10) |
| Column widths | `lsvp` `columns` -> `width` | Read/write; applied | A width alone does not create list options | **Implemented** (Mac-verified (Referee); E8, E10) |
| Column order | `lsvp` `columns` -> `index` | Read/write; applied; Name cannot leave the left edge | | **Implemented** (Mac-verified (Referee); E8, E21) |
| Show relative dates | `lsvp` `useRelativeDates` | Read/write; applied in list, browser columns and icon info line | Wording per E22; browser and icon info line are a guess | **Implemented** (Mac-verified (Referee) for the record; wording E22) |
| Calculate all sizes | `lsvp` `calculateAllSizes` | Read/write; applied | Display while calculating partly measured (E23) | **Implemented** (Mac-verified (Referee) for the record; E23) |
| Narrow date column | none | A cell too narrow drops the time, then the year digits, then dots the middle | Year step is a guess | **Implemented** (tests only; E22) |
| Legacy view records | `LSVO`, `lsvo`, `lsvt`, `BKGD`, `fwi0`, `vSrn`, `ICVO` | Legacy `lsvo` is read when there is no `lsvp`; none of these is written any more; they stay untouched in the store | Finder 10.6 prefers `lsvp` (E10) and ignores `BKGD` colour (E12) | **Read-only** (tests only; E8, E10) |
| Cooperative save | all Finder records | A save changes only what the user changed: a value not changed keeps its stored type (integers stay integers, `viewOptionsVersion` kept), unknown keys and records are preserved, and no `.` records are added to the folder's own store | Referee M6 found the old behaviour changing a white folder to red | **Implemented** (tests only after the M6 fix; Finder-written records were preserved in the Referee run) |

---

# Per-file Presentation (stored in .DS_Store, FinderInfo xattr or AppleDouble)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Icon position (folder-relative) | `Iloc` record in the store of the folder containing the item | 16-byte blob, icon centre, top-left origin; trailing bytes kept | Present since classic Finder | **Implemented** (Mac-verified (Referee); E1, E8) |
| Finder icon position (file-travelling) | `com.apple.FinderInfo` `fdLocation` | Updated when an icon is dragged, together with `Iloc` | | **Implemented** (tests only) |
| Label colour | `com.apple.FinderInfo` `fdFlags` bits 1-3 with Finder's colour numbers: 1 Grey, 2 Green, 3 Purple, 4 Blue, 5 Yellow, 6 Red, 7 Orange | Workspace's own order (1 Red .. 7 Grey) is converted in one place; also writes `_kMDItemUserTags` | Finder 10.6 writes no `lclr` and ignores one; Workspace still reads `lclr` | **Implemented** (Mac-verified (Referee); E24, referee answer a) |
| Finder tags | `com.apple.metadata:_kMDItemUserTags` binary plist | Read/write; label setter keeps tags in sync; survives push to the Mac byte for byte | 10.6 has no tags | **Implemented** (Mac-verified (Referee) for survival only; tags untested on 10.9+) |
| Finder comment | `cmmt` record in the parent store (what 10.6 Finder shows) plus `com.apple.metadata:kMDItemFinderComment` | Inspector edits both; a copy, duplicate or move writes the `cmmt` record into the destination folder's store and a move removes the old one | Finder 10.6 shows a comment only from `cmmt` (Referee M2) | **Implemented** (Mac-verified (Referee) via the Inspector path; copy/move rows tests only; MI-PRS-24..32) |
| Custom file icon | `fdFlags` 0x0400 plus resource fork `icns` id -16455 | Read, apply, set and clear in the Inspector | Finder-written 256 and 512 px JPEG 2000 members are not decoded (M5) | **Implemented** (Mac-verified (Referee); E18) |
| Custom folder icon | file `Icon\r` inside the folder (empty data fork, fdFlags 0x4000, `icns` fork) plus 0x0400 on the folder | Inspector writes and clears it | Writing through GSFileMetadata on the folder itself fails on a Mac (M7) | **Implemented** (Mac-verified (Referee); E18) |
| Hidden filename extension | `fdFlags` 0x0010 | Inspector toggle; views hide the extension when set | 0x0400 is the custom icon bit; the old table was wrong | **Implemented** (Mac-verified (Referee); E18) |
| Stationery pad | `fdFlags` 0x0800 | Opens a copy; Inspector toggle | | **Implemented** (tests only) |
| Bundle bit | `fdFlags` 0x2000 | Model read/write only; the UI uses its own package detection | | **Partial** (tests only) |
| Invisible flag | `fdFlags` 0x4000 | Read, applied to filtering; Inspector toggle | | **Implemented** (tests only) |
| Name locked | `fdFlags` 0x1000 (`kNameLocked`) | Inspector checkbox; rename is blocked | Finder's "Locked" is the BSD `uchg` flag, a different thing (M1) | **Implemented** (tests only; E18) |
| Locked (`uchg`) | BSD user-immutable flag, not an xattr | Inspector toggle: BSD directly, Linux through a privileged helper (`sudo -A`, single-purpose, refuses symlinks and files not owned by the user) | No archive, sidecar or SMB copy carries it (M1) | **Partial** (Linux sudo round trip untested; Referee: FAIL, not transferable) |
| Aliases | Alias file: `fdFlags` 0x8000, type `alis`/`fdrp`, creator `MACS`, `alis` resource id 0 in the fork, empty data fork | Opens and resolves classic Finder aliases; writes aliases a 10.6 Finder resolves, for files and folders; new alias in the Inspector/menu | Bookmark-only files are not resolved by 10.6 (E19) | **Implemented** (Mac-verified (Referee); E19, E28) |
| .webloc / .ftploc | XML plist (data fork) plus `drag` 128, `TEXT` 256, `url ` 256 resources, type `ilht`/`ilft` | Opens, creates (including URL drop on a folder), matching Finder's layout | Opening on the Mac not tried (would start a browser) | **Implemented** (Mac-verified (Referee); E19, E27, E28) |
| .mailtoloc | type `ilma`, creator `MACS` | Created like the others, with the type and creator Referee M3 found missing | Re-verify on the Mac after the fix | **Implemented** (tests only after M3; Referee: reverse FAIL before the fix) |

---

# File Metadata (extended attributes, resource fork, sidecars)

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| File type code | `FinderInfo` `fdType` | Read, write and validate in the Inspector (four printable characters) | | **Implemented** (tests only) |
| Creator code | `FinderInfo` `fdCreator` | Same; used for open-app selection | | **Implemented** (tests only) |
| Extended attributes (generic) | all `user.*` xattrs | Preserved on copy, duplicate, move (also across file systems, source removed only afterwards); a failed carry stops the move | Only the user namespace; OpenBSD has none and uses sidecars | **Implemented** (Mac-verified (Referee) for unknown attributes through copy and write paths; MI-PRS) |
| AppleDouble fallback (`._` sidecar) | AppleDouble v2: entry 9 FinderInfo, entry 2 resource fork, ATTR block | Written when a volume has no xattrs or a value does not fit (E2BIG/ENOSPC); unknown entries and attributes kept on rewrite; a source sidecar is carried byte for byte | Layout per E15, E17 | **Implemented** (Mac-verified (Referee); `tar` and `dot_clean` apply it fully) |
| Quarantine | `com.apple.quarantine` xattr; in a sidecar the value has a `q/` prefix | Carried unchanged; written with the prefix into sidecars and archives, stripped on extraction, never doubled | An unprefixed value is dropped by 10.6 (Referee addendum); nonzero flags are dropped (E16) | **Implemented** (Mac-verified (Referee); E16) |
| zip / tar `__MACOSX` | `__MACOSX/<dir>/._name` (zip) or `._name` beside the item (tar, ditto) | Workspace Compress writes them for items with metadata; extraction applies FinderInfo, attributes, resource fork and a labelled top folder; a `.DS_Store` already present is kept | Mac copy tools that ignore sidecars: plain `unzip`, `ditto <dir>`, `cp -R` (M8) | **Implemented** (Mac-verified (Referee); E15, E29) |

---

# Local Cache Features (when .DS_Store cannot be written)

| Finder feature | Storage | Implementation | Notes | Implementation Status |
|----------------|---------|----------------|------|-----------------------|
| Read-only folder layout | `~/Library/Caches/com.apple.finder/<volume id>.DS_Store` | When the parent cannot be written the record goes to the cache; never when the parent store was written | Finder 10.6 itself persists nothing for read-only places (E14) | **Implemented** (tests only; E14) |
| Network folder layout | Same cache | `DSDontWriteNetworkStores` policy plus read-only detection | | **Implemented** (tests only) |
| Root volume layout | Same cache; volume root and home keep `.` in their own store (E14) | `/`, `/System`, `/Volumes` route to the cache | | **Implemented** (tests only; E14) |
| Offline / removable media | Cache file named after the file system identity (Linux `/dev/disk/by-uuid`, FreeBSD `/dev/ufsid`, `/dev/gptid`) | Layout survives eject and insert; an old device-id cache is renamed once | Not available on OpenBSD (DUIDs not looked up) | **Implemented** (tests only; MI-IV-87..89) |

---

# Look Inside and Other Features

| Finder feature | Metadata | Implementation | Notes | Implementation Status |
|----------------|----------|----------------|------|-----------------------|
| Look Inside | None | Workspace's own preview window on the space bar (Workspace/QuickLook/), showing a file's contents; not metadata-driven | Being improved | **Partial** (tests only) |
| iCloud integration | ubiquity metadata | Requires iCloud services | | **Not implemented** |
| AirDrop | None | Needs Bonjour and AWDL | | **Not implemented** |
| Finder Sync extensions | extension-specific | Introduced in OS X 10.10 | | **Not implemented** |

---

# Column view options

Finder 10.6 offers these column view options.  A Scout is measuring them on
the Mac now; until the evidence is in, no behaviour or record is claimed.

| Finder option | Metadata | Implementation | Notes | Implementation Status |
|---------------|----------|----------------|------|-----------------------|
| Text size | to be measured | | | **Under investigation** |
| Show icons | to be measured | | | **Under investigation** |
| Show icon preview | to be measured | | | **Under investigation** |
| Show preview column | to be measured | | | **Under investigation** |
| Arrange by | to be measured | | | **Under investigation** |
| Column widths | to be measured | | | **Under investigation** |

---

# Known limits

- Locked (`uchg`) cannot be transferred to Linux: no tar, sidecar, zip or SMB copy carries it, and setting it on Linux needs the privileged helper (Referee M1).
- HFS+ volumes are parked: the Linux hfsplus driver mounts journaled disks read-only, exposes no resource fork, loses the comment record and truncates xattr names; branch `mi/p-hfs` is kept, not merged.
- Metadata over SMB and through Linux `tar` is only as good as the Mac tool unpacking it: `dot_clean`, `tar -x`, `ditto -x -k` and Finder double click apply sidecars; plain `unzip`, `ditto <dir>` and `cp -R` do not (M8).
- Custom icons Finder writes with JPEG 2000 members (256 and 512 px) are shown from the 16, 32 and 128 px members only (M5).
- Languages other than German are unverified: date wording and menu names were measured on a German 10.6 Finder (E22).
- Tags are untested on 10.9 and later; the oracle is 10.6.8, which has none.
