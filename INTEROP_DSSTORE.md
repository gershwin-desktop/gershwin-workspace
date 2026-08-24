# .DS_Store Interop (macOS 10.6 Finder <-> Gershwin)

Reference machine: macOS 10.6.8, Finder (browser mode). See `INTEROP_VNC_TESTING.md`
for the test harness. Principle: the Mac is always right; Gershwin must match
what Finder reads and writes on disk.

## Status

| Direction | State | Notes |
|-----------|-------|-------|
| Mac writes -> Gershwin reads | **WORKS** | Iloc (icon positions) parsed exactly; real Mac `.DS_Store` loads cleanly. |
| Gershwin writes -> Mac reads | **WORKS** | Finder preserves Iloc for single-node and multi-node (94-entry) trees. |
| Record-type round-trip (hermetic) | **WORKS** | Every supported record type (folder + per-file) round-trips; a full multi-type Gershwin file is NOT rejected by 10.6 Finder. |
| Per-folder view style (`vstl`) | **NOT honored by 10.6** | Correctly encoded + round-trips in Gershwin, but 10.6 Finder ignores it (shows icon view regardless; see below). |
| Window geometry (`bwsp`/`fwi0`) | **NOT honored by 10.6** | Correctly encoded + round-trips in Gershwin, but 10.6 Finder ignores it (uses default window bounds). |

## Forward: Mac -> Gershwin (verified)

Captured `ds_icon.DS_Store` from a real Finder session (four files dragged to
known positions). Gershwin's `DSStore` reader parses it exactly:

| file  | Finder `position` | `.DS_Store` Iloc | Gershwin read |
|-------|-------------------|------------------|---------------|
| a.txt | {40,40}   | 40,40   | 40,40   |
| b.txt | {200,60}  | 200,60  | 200,60  |
| c.txt | {80,220}  | 80,220  | 80,220  |
| d.txt | {300,300} | 300,300 | 300,300 |

On 10.6 Finder stores the position where the icon is; AppleScript `position`
is the same point as the `Iloc` record (no center/topleft offset observed).

Per-folder `vstl` (view style) and `bwsp` (window geometry) are **absent** in
these fixtures: 10.6 browser mode keeps window/view state global in
`com.apple.Finder` (`BrowserWindowState` -> `WindowBounds`,
`FXPreferredViewStyle=icnv`, `StandardViewSettings`), not per-folder. So a
per-folder `.DS_Store` only carries `Iloc` (plus the `.DS_Store` self-entry).

Hermetic test: `t_DSStoreInterop.m` loads the fixture and asserts the four
Iloc points plus "no per-folder vstl". All 9 assertions pass.

### DEFINITIVE: 10.6 Finder ignores `vstl`/`bwsp`/`fwi0` (verified 2026-08-24)

Gershwin encodes these records correctly and they round-trip hermetically, but
on macOS 10.6.8 the Finder neither writes nor reads them per-folder:

- A Gershwin-written `.DS_Store` with `vstl=Nlsv/clmv/glyv/Flwv` shows **"icon
  view"** for all when opened in Finder (should switch). `Flwv` (cover flow) is
  visually unmistakable from icon view and still shows icon.
- A Gershwin-written `bwsp` `WindowBounds = {100,120,480,360}` is ignored;
  Finder opens the window at its default `{247,225,1017,640}`.
- A `.DS_Store` that macOS **itself writes** for a folder displayed in list view
  contains **only `Iloc`** (`strings` shows `Iloc`/`Bud1`/`DSDB`/`blob` only, no
  `vstl`/`bwsp`/`fwi0`/`lsvp`). The trusted oracle fixture `ds_icon.DS_Store`
  is the same.
- The folder itself carries **no xattr, no `com.apple.FinderInfo`, no `mdls`
  view keys**, so 10.6 stores per-folder view/window state neither in the
  `.DS_Store` nor in the folder's extended attributes in browser mode.
- Setting the global `FXDefaultViewStyle` preference changes the default view,
  confirming view state on 10.6 lives **globally** (the Finder preference
  domain), not per-folder via `.DS_Store`.

**Conclusion:** On 10.6, per-folder view switching / window sizing is **not
achievable via `.DS_Store`**; the only interoperable per-folder surface is
`Iloc` (icon positions) plus per-file metadata. True per-folder view/window
interop would require either a newer macOS (where `vstl`/`bwsp` are honored in
`.DS_Store`) or the global Finder preference channel. Gershwin's writer/reader
support the records correctly either way, so the format-level implementation is
complete and unit-tested.

## Reverse: Gershwin -> Mac (FIXED)

`Tools/mac-dsstore-interop/write-dsstore.m` (and the minimal `/tmp/gen_min.m`
used during debugging) write an `.DS_Store` carrying Iloc for a/b/c/d. When
placed in a fresh folder and opened in Finder, macOS **preserves** the
positions. Verified 4/4 exact on the Mac for both a single-node tree (4
entries) and a multi-node tree (94 entries, 2 B-tree levels). The control
test (Mac's own `ds_icon.DS_Store`) also preserves positions.

### Root causes found and fixed (DSStore/DSStore.m `save`, DSBuddyAllocator)

1. `Bud1` superblock header fixed to the canonical 32-byte header
   (`root_offset = 0x1000`), and the buddy root is now **block 0 at file
   offset `0x1000`** (2048 bytes, width 11, offset entry `0x100b`). Header
   `root_offset = 0x1000`. Finder rejects the file if the root lives anywhere
   else.
2. **DSDB superblock is block 1 at `0x40`** (32 bytes, width 5, entry
   `0x45`). Its `page_size` field stays 4096 (matches the Mac) even though
   actual B-tree nodes are smaller.
3. **B-tree nodes allocated at their actual content size**, not at a fixed 8
   KiB page. Finder rejects 8 KiB-padded nodes; macOS writes them at their
   real size (minimum ~256 bytes). The B-tree node *location* is flexible -
   only block 0 (root) and block 1 (DSDB) addresses are fixed.
4. `allocate:` rounding fixed for exact powers of two (`bit_length(n-1)` so
   256 -> width 8, not 9); free-list contents are not validated by Finder but
   must stay internally consistent.
5. Empty file: buddy root via `setRootBlockAddress:0x100b`, `levels = 0`.
6. Multi-node trees: blocks are allocated leaf-first but consumed FIFO in the
   write pass; the earlier LIFO consumption wrote leaf data into the wrong
   (too-small) blocks and corrupted/clobbered the root (surfaced as an
   `NSMallocException` on >~90 entries).
7. Iloc trail fixed to `ff ff ff ff ff ff 00 00` (unknown1 `0xFFFFFFFF`,
   unknown2 `0xFFFF0000` BE) instead of the little-endian `00 00 ff ff ff ff
   ff ff` from a naive `uint64_t` append.

### Gotchas that produced false "rejected" readings

- **Finder caches .DS_Store positions**; always `killall Finder` (wait ~4s)
  before querying or you read stale default-grid positions and wrongly
  conclude rejection.
- **Finder snaps non-grid-aligned Iloc to its icon grid** on display
  (e.g. `(15,15)` -> `(31,34)`). Use grid-aligned positions (`(40,40)`) for
  exact 4/4 round-trips; the snap is display-only.
- **scp needs `sshpass -p user` + `-o HostKeyAlgorithms=+ssh-rsa
  -o PubkeyAcceptedAlgorithms=+ssh-rsa`** (OpenSSH 5.2). Plain `scp` fails
  silently and leaves a stale file - verify the upload with `md5` on both
  ends.

`DSStore` reading, `DSStoreEntry` encoding, and `DSStoreInfo` round-trip fine
within Gershwin (see `t_DSStoreInfo.m`). The Mac is the oracle; the
`ds_store` python package's *writer* output is itself rejected by Finder and
must not be used as ground truth.

### Record types (hermetic) + view/window getters

`t_DSStoreRecordTypes.m` exercises every record type the writer supports
(folder self-entry settings + per-file records) and round-trips them; a
full multi-type Gershwin `.DS_Store` is confirmed **not rejected** by 10.6
Finder (Mac-read shows default icon view + preserved Iloc). `t_DSStoreVTypes.m`
covers `vstl`/`icvo`/`icsp`/`bwsp` + folder/child `Iloc`.

`DSStore.h` now exposes view/window accessors (all unit-tested):
`viewStyleForDirectory`/`setViewStyleForDirectory:`, `setIconSizeForDirectory:`,
`showRelativeDatesForDirectory`/`setShowRelativeDatesForDirectory:`,
`listViewSettingsForDirectory`/`setListViewSettings:` (serializes to binary plist
`NSData` under the real `lsvp` record; column width/visibility live there, not
in the truncated `clw`/`cv` codes), `browserWindowDictionaryForDirectory`,
`browserWindowBoundsForDirectory` (reads `bwsp` `WindowBounds`), and
`windowGeometryRectForDirectory` (reads legacy `fwi0` rect).

### Spatial channel: folder FinderInfo (`DInfo`)

Per-folder view/window also lives in the folder's own `com.apple.FinderInfo`
xattr as a `DInfo` structure: `frRect` (window bounds, bytes 0-7, four
big-endian int16: top/left/bottom/right) and `frView` (view-style code, bytes
14-15, big-endian int16).  `GSFileMetadata` now reads/writes these via
`viewStyleCodeForDirectory`/`setViewStyleCodeForDirectory:` (mapped to the same
`vstl` 4-char codes as `.DS_Store`: icnv=0, Nlsv=1, clmv=2, Flwv=4, glyv=5) and
`windowBoundsForDirectory`/`setWindowBoundsForDirectory:`.  Covered by
`t_GSFileMetadata.m` (asserts `frView` lands at bytes 14-15 and `frRect` at
bytes 0-7, both big-endian).

Verified on the Mac (2026-08-24): 10.6 browser-mode Finder **ignores** both
`frView` and `frRect` for folders - a folder carrying `frView=0` (icon) still
opens with the global default view, and window bounds always come from the
default browser window, never from `frRect`/FinderInfo.  10.6 keeps per-folder
view/window state in its private `com.apple.finder.plist` (`BrowserWindowState`,
path-keyed), not in per-folder on-disk files.  The FinderInfo `DInfo` channel is
the classic / spatial Finder mechanism (honoured by newer macOS and by
Gershwin's own spatial viewer) - it is the correct thing to write, even though
10.6's browser mode will not read it.

## Reverse verification recipe (needs the Mac)

```
# build the minimal writer against the real DSStore sources, then ship + read
clang `gnustep-config --objc-flags` -I DSStore -fobjc-runtime=gnustep-2.0 \
  /tmp/gen_min.m DSStore/*.m -o /tmp/gen_min \
  `gnustep-config --base-libs` `gnustep-config --gui-libs`
/tmp/gen_min /tmp/ds_min.DS_Store
sshpass -p user scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  /tmp/ds_min.DS_Store user@Users-Mac-mini.local:/Users/user/macfold_min/.DS_Store
sshpass -p user ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  user@Users-Mac-mini.local 'md5 /Users/user/macfold_min/.DS_Store'   # match local
sshpass -p user ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  user@Users-Mac-mini.local 'killall Finder; sleep 4; osascript /Users/user/query_min.scpt'
# expect {40,40},{200,60},{80,220},{300,300} (grid-aligned) when honored
```

## Next steps

- [x] Make Gershwin's `DSStore` writer emit a macOS-valid buddy-allocated
       file (root@0x1000, DSDB@0x40, content-sized B-tree nodes, FIFO block
       consumption). Done - Finder preserves positions (single- and multi-node).
- [x] Verify record types round-trip (hermetic) + that a full multi-type file is
       not rejected by 10.6 Finder (`t_DSStoreRecordTypes.m`,
       `t_DSStoreVTypes.m`). Done.
- [x] Expose view/window getters/setters on `DSStore` (`viewStyleForDirectory`,
       `bwsp`/`fwi0` bounds/rect, `listViewSettingsForDirectory`, etc.) and fix
       `setListViewSettings:` (binary plist under `lsvp`) and
       `setShowRelativeDatesForDirectory:`. Done.
- [x] Reverse-interop test: `t_DSStoreViewWindowInterop.m` round-trips all 5
       view styles + `bwsp` + `fwi0` and reads a real Mac `ds_viewlist.DS_Store`
       (only `Iloc`) without inventing view/window records. Done.
- [x] Document the 10.6 browser-mode limit: per-folder `.DS_Store` only
       carries `Iloc`; `vstl`/`bwsp`/`fwi0` are correctly encoded by Gershwin
       but ignored by 10.6 Finder (view/window state is global).
- [x] Implement the folder `FinderInfo` `DInfo` channel in `GSFileMetadata`
       (`viewStyleCodeForDirectory`/`windowBoundsForDirectory` + setters, mapped
       to the same `vstl` codes as `.DS_Store`); hermetic test in
       `t_GSFileMetadata.m`. Done.  Mac-verified: 10.6 browser mode ignores
       `frView`/`frRect` (uses private `com.apple.finder.plist`), so the
       channel is correct but not 10.6-honored.
- [ ] Decide scope for view/window interop on 10.6: (a) target a newer macOS
       where `.DS_Store` `vstl`/`bwsp` and FinderInfo `DInfo` ARE honored,
       (b) implement global `FXDefaultViewStyle`/window-state interop via the
       Finder preference domain, or (c) accept `.DS_Store` + FinderInfo-level
       (Iloc + per-file metadata + correct-by-spec view/window encoding) interop
       as the achievable surface on 10.6.
