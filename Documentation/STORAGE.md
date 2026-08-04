# Where Workspace stores view settings and icon positions

This document describes the persistence model of the Workspace file manager:
which type of information is stored where, and how the pieces relate.  The
goal is interoperability with macOS Finder where possible.

## Overview

Workspace persists four kinds of data:

1.  **Per-folder view settings and icon positions** - `.DS_Store` files
2.  **Per-file icon metadata (position, label)** - FinderInfo xattr
3.  **Per-file AppleDouble sidecars** - `._` files (fallback)
4.  **Window-level viewer state** - GNUstep user defaults

Writes are routed through `GWViewSettingsManager` (folder `.DS_Store` primary,
volume cache fallback) and `GWIconPositionStore` (icon positions, which also
update the per-file FinderInfo xattr).

```
                 +----------------------------+
                 |  GWViewSettingsManager     |
                 |  (read tiered, write       |
                 |   folder-first)            |
                 +------------+---------------+
                              |
        +---------------------+---------------------+
        |                                           |
        v                                           v
+-----------------------+                +-----------------------------+
| $FOLDER/.DS_Store     |                | ~/Library/Caches/com.apple. |
| (writable folders)    |                |   finder/<VOLID>.DS_Store   |
|                       |                | (read-only/network folders) |
+-----------------------+                +-----------------------------+

+----------------------------+     +-------------------------------+
| user.com.apple.FinderInfo  |     | ._NAME AppleDouble sidecar     |
| xattr (icon position,      |     | (only when xattr unavailable)  |
| label, custom icon)        |     |                               |
+----------------------------+     +-------------------------------+
```

## 1. Per-folder `.DS_Store` (primary for writable directories)

Location: `$FOLDER/.DS_Store`

Written by `DSStoreInfo saveToPath:` via `GWViewSettingsManager writeSettings:`.
Used whenever the folder is writable and network-store writes are not blocked
(`DSDontWriteNetworkStores`).

### Directory-level entries (keyed by `.` in the file)

Stored as DSStore entries on the special filename `.`:

| Setting                         | Code | Notes                              |
| ------------------------------- | ---- | ---------------------------------- |
| View style (icon/list/columns)  | `vstl` / `icnv`, `Nlsv`, `clmv`, `glyv`, `Flwv` | |
| Icon size                       | `icvo` (iconSize slot) | 1-512, 0 = unset |
| Icon arrangement (free/grid)    | `icvo` (arrangement slot) | |
| Label position (bottom/right)   | `icvo` (labelPosition slot) | |
| Grid spacing                    | `icvo` (gridSpacing slot) | |
| Background color                | `BKGD`   | RGB, 16-bit components |
| Background image                | `BKGD`   | path |
| Sidebar width                   | `icvo` (sidebarWidth slot) | |
| Window geometry                 | `bwsp` + `fwi0` | GNUstep saved-frame parsed and stored as DS-Store content rect |
| List view settings (sort column, ascending, text/icon size, column widths/visibility) | `lsvp` | |

These are written by the shared helper
`DSStoreInfo +writeStoreEntriesForInfo:key:toStore:` (key `.` for the folder
file, or the full directory path for the volume cache - see below).

### Per-file entries (keyed by the on-disk filename)

| Setting   | Code   | Notes                              |
| --------- | ------ | ---------------------------------- |
| Icon position | `Iloc` | 16-byte blob; icon CENTER, top-left origin, y grows downward |
| Comment   | `cmmt` | ustr |
| Label color | `lclr` | long |

Keys are the **bare, on-disk filename** (e.g. `Desktop`, not the translated
display name `Schreibtisch`).  This matches the macOS Finder convention
(verified against real Finder volume caches and the authoritative
`ds_store` Python module).  The translated name from `FSNode -name` must
never be used as a persistence key; only `-lastPathComponent` (the
never-translated name) is used.

### Ghost entry pruning

On every write, per-file entries whose filename is not an on-disk child of the
directory are removed (renamed/removed files, and localized standard-folder
names a foreign Finder may have written).  Implemented in
`DSStoreInfo +pruneNonChildEntriesInStore:forDirectory:keepPath:`.  The
directory's own record (`.` / the path) is never pruned.

### Read precedence

`GWViewSettingsManager readSettings:` reads in this order:

1.  `$FOLDER/.DS_Store` (if it loads, it wins)
2.  the volume cache for the folder's volume
3.  empty defaults (fresh, unloaded `DSStoreInfo`)

## 2. Per-volume cache (fallback for read-only / network folders)

Location: `~/Library/Caches/com.apple.finder/<VOLID>.DS_Store`

Same on-disk format as a folder `.DS_Store`.  Used when the folder is not
writable or network writes are blocked.  This is the same location and name
scheme as the macOS Finder volume caches, so a real Finder can read our
positions for `/`, `/dev`, and other non-writable paths.

`<VOLID>` is derived from the filesystem ID (`statfs` `f_fsid`); fallbacks
hash the mount source or mount point.  Managed by `GWVolumeID`.

Keying inside the cache:

- **Directory-level settings** are keyed by the **full directory path**
  (e.g. `/`, `/dev`, `/tmp/test/...`).
- **Per-file entries** are keyed by **bare filename**, volume-global (the Mac
  convention).  Older caches written by this app may carry scoped
  `<path>/<filename>` keys; the read side prefers the bare form and falls back
  to the scoped form.

Reads apply the same ghost filter: a per-file entry whose bare name is not an
on-disk child of the directory is ignored.  Writes prune such entries too.

## 3. Per-file FinderInfo xattr

Location: extended attribute `user.com.apple.FinderInfo` on each file or
folder (32 bytes, the macOS FinderInfo record).

Holds per-file metadata that should travel with the file (Finder stores it the
same way, so it interoperates):

| Field | FinderInfo offset | Notes |
| ----- | ----------------- | ----- |
| Icon position (`fdLocation`) | h at bytes 10-11, v at bytes 12-13 | big-endian int16 |
| Label color (finder flags `l4-7`) | bytes 8-9 (flags), bits 24-26 | |
| Custom icon / resource fork | ResourceFork xattr (`user.com.apple.ResourceFork`) | |

`GSFileMetadata` is the reader/writer.  Icon positions are stored here by
`GWIconPositionStore writeBatch:` (Phase 2/3) alongside the `.DS_Store`
update.  `(0,0)` and `(-1,-1)` are treated as "no position".

## 4. AppleDouble sidecars (fallback)

Location: `._NAME` next to each file (AppleDouble encoding).

Used only when the filesystem has no xattr support (or xattr writes fail).
`GSFileMetadata` transparently falls back to a `._NAME` sidecar for read and
write.  Sidecar path is derived from the **on-disk** file path only - a
localized display name must never be used to build a sidecar path (that would
create orphan `._Schreibtisch`-style files for folders that do not exist).

On xattr-capable filesystems, any existing sidecar is removed when metadata is
written via xattr, so the two never diverge.

## 5. GNUstep user defaults (viewer state)

Location: user defaults (GNUstep preferences database), keys:

| Key prefix | Content |
| ---------- | ------- |
| `viewer_at_<path>` | non-spatial viewer prefs for a folder |
| `spatial_at_<path>` | spatial viewer prefs for a folder |
| `root_viewer` | the first/root viewer window |
| `%lu_viewer_at_<path>` | additional viewer windows of the same folder |

These hold window-level state that is not part of the `.DS_Store` schema:
view type, icon size, label text size, icon/label position, info type, last
selection, inspector toggle/pane, shelf height/dicts (spatial), show-inspector
flags.

Window geometry is deliberately **excluded** from user defaults: it lives in
the `.DS_Store` `bwsp`/`fwi0` entries for interoperability and is stripped
from the defaults dictionary before saving.

## Lifecycle

### Window close (folder view / spatial view)

`updateDefaults` in `GWViewer` / `GWSpatialViewer`:

1.  Collects the current view settings.
2.  Persists the **live on-screen layout**: `FSNIconsView -liveIconPositions`
    (keyed by on-disk names) is fed into `DSStoreInfo -setLiveIconPositions:`,
    replacing any stale/foreign positions.
3.  `writeSettings:` writes the folder `.DS_Store` (or volume cache), pruning
    ghosts, and removes the stale volume-cache record on success.
4.  The remaining non-`.DS_Store` fields go to user defaults.

### Icon drag / Clean Up

`FSNIconsView -batchRepositionIcons:` batches all moved icons by folder and
hands them to `GWIconPositionStore`:

- Phase 1: `.DS_Store` update (via `writeSettings:`).
- Phase 2/3: per-file FinderInfo xattr (or sidecar) update for each moved file.

### Restore on open

`showContentsOfNode:` applies saved positions in this order (only for
position-honoring views - desktop and spatial):

1.  Per-file FinderInfo xattr (`fdLocation`) - travels with the file.
2.  Folder `.DS_Store` / volume cache Iloc (via the settings hierarchy),
    deduplicated: only the first icon claiming a given position keeps it;
    later ones fall through to AUTO placement so nothing overlaps.
3.  Everything else auto-grids.

The same keying rules apply everywhere: on-disk filenames only.

## Cooperative editor contract (forward compatibility)

Workspace is a **cooperative editor** of `.DS_Store`, not the owner of the
file.  It may modify the records it understands, but it must preserve, carry
forward, and avoid overwriting metadata created by Finder or any other
application.  This contract is what allows newer versions of Finder to keep
using a `.DS_Store` after Workspace has written it.

The save path is conceptually:

```
read existing file
  -> parse everything
  -> modify known fields
  -> serialize everything
```

never "create empty store -> write only Workspace fields".

### Unknown record types and blobs

`DSStore` loads every entry generically (filename + 4CC code + type + value).
Unknown 4CC codes and opaque blobs are kept in memory and emitted byte-for-byte
on save.  Workspace does not discard, reinterpret, or regenerate records it
does not understand.

### Partially-understood records

Some record types (`icvo`, `fwi0`, `bwsp`, `lsvp`, `BKGD`, `Iloc`) contain
fields Workspace only partially understands.  The `DSStoreEntry` factories have
`preserving:` variants (`iconSizeEntryForFile:size:preserving:`,
`browserWindowEntryForFile:...preserving:`, etc.) that patch only the fields
Workspace owns and carry every other byte or plist key forward unchanged:

| Record | Workspace owns | Carried forward |
| ------ | -------------- | --------------- |
| `icvo` | icon size (bytes 12-13) | flags, arrangement 4CC, all trailing bytes |
| `fwi0` | bounds (0-7) + view style (8-11) | trailing flags/unknown (12-15) |
| `bwsp` | `WindowBounds`, `SidebarWidth` | every other plist key |
| `lsvp` | `sortColumn`, `ascending`, `textSize`, `iconSize`, `columns` | every other plist key |
| `BKGD` | RGB triplet | "ClrB" tag, reserved byte, trailing bytes |
| `Iloc` | x/y (0-7) | trailing 8 bytes |

`writeStoreEntriesForInfo:` (used by both `DSStoreInfo saveToPath:` and
`GWVolumeCache writeInfo:`) looks up the existing entry and passes it to the
`preserving:` factory, so unknown fields survive every write cycle.  Covered by
`Tests/FileViewer/t_DSStorePreserve.m`.

### Never normalize, never downgrade

- Out-of-range values (e.g. an `icvo` size of 999) are not clamped or
  rewritten unless the user actually changes that setting; they survive a
  load/save cycle unchanged.
- A record is only rewritten when a Workspace-owned field changes.
- The parser ignores additional fields, unknown record types, and unknown
  versions rather than rejecting the file; opening a `.DS_Store` never removes
  metadata written by a newer Finder.

### Duplicates and ordering

- Duplicate records in a foreign file are preserved on a no-op load/save.
  `setEntry:` (which replaces one specific record) is only used when Workspace
  explicitly owns and is updating that record.
- Records are stored in the B-tree's required sorted order (`compare:`); this
  is mandated by the format, not a gratuitous rewrite.

### Atomic writes

`DSStore save` writes via `NSDataWritingAtomic` (temporary file in the same
directory + rename), so an interrupted save leaves either the previous valid
file or the complete new file - never a partial one.  A failed serialize or
write leaves the original file untouched.

### Merging with concurrent writers

`saveToPath:` and `GWVolumeCache writeInfo:` load the latest on-disk copy
immediately before writing and merge Workspace's pending modifications into it,
so a concurrent Finder change to another record survives.  If both apps change
the same field, the most recent completed save wins; no attempt is made to
merge conflicting values.  Unknown records are never considered conflicts and
are always carried forward from the newest on-disk version.

## Key rules to remember

- **Always key by the on-disk filename** (`[node lastPathComponent]`),
  never the localized display name (`[node name]`).  `FSNode -name`
  translates standard folder names (`Desktop` -> `Schreibtisch`) and is only
  for display.
- Per-file `.DS_Store` entries and FinderInfo positions use **bare** names.
- Directory-level cache entries use the **full directory path**.
- Prune on write: entries for files no longer on disk are removed.
- Deduplicate on restore: a position claimed by one icon is not given twice.
- Write the **live layout** on window close, not a re-read of the stale file.
- **Never rebuild a partially-understood record from scratch**: patch only the
  fields Workspace owns and carry everything else forward.
