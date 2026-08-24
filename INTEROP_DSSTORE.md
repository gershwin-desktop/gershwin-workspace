# .DS_Store Interop (macOS 10.6 Finder <-> Gershwin)

Reference machine: macOS 10.6.8, Finder (browser mode). See `INTEROP_VNC_TESTING.md`
for the test harness. Principle: the Mac is always right; Gershwin must match
what Finder reads and writes on disk.

## Status

| Direction | State | Notes |
|-----------|-------|-------|
| Mac writes -> Gershwin reads | **WORKS** | Iloc (icon positions) parsed exactly. |
| Gershwin writes -> Mac reads | **WORKS** | Finder preserves Iloc for single-node and multi-node (94-entry) trees. |

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
- [ ] Verify other record types round-trip on the Mac (per-folder `vstl`
      view style, `bwsp` window geometry, folder self-entry). 10.6 browser
      mode keeps most window/view state global, so per-folder `.DS_Store`
      mainly carries `Iloc`.
- [ ] Expose a window-frame getter/setter on `DSStore` (read `bwsp`
      `WindowBounds`, fall back to `fwi0`) and stop misusing `bwsp` in
      `backgroundPictureForDirectory:` (it is window settings, not a
      background picture).
- [ ] Add a reverse-interop test step (documented above) and a hermetic
      writer/reader round-trip in `t_DSStoreInterop.m`.
- [ ] Document the 10.6 browser-mode limit: per-folder `.DS_Store` only
      carries `Iloc`; full window geometry/view is global.
