# Interop evidence (Mac OS X 10.6.8 Finder oracle)

Each entry: id, date, steps, observed result, fixture. Oracle: Users-Mac-mini.local,
Mac OS X 10.6.8, screen 1024x768, driven with `Tools/mac-oracle/mac-oracle`.
Fixtures are under `Tests/GWMetadata/interop/fixtures/finder106/`. "Parent store"
means the `.DS_Store` of the directory that contains the folder in question.
Dumps below come from `mac-oracle dump`, i.e. decoded by this repo's DSStore code.

## E1 - Finder keeps a folder's window and view records in the PARENT's .DS_Store

- Date: 2026-10-11
- Steps: fresh folder `eA` under `~/Desktop/mi`; `open` it in Finder, then
  `set icon size of icon view options of window to 96` and
  `set bounds of window to {200,200,700,600}` by AppleScript; Finder quit
  (flush, see E4); pulled `~/Desktop/mi/.DS_Store` and `eA/.DS_Store`.
- Observed: `eA/.DS_Store` holds only `Iloc` records (for `.DS_Store` itself and
  the items). `~/Desktop/mi/.DS_Store` holds records named `eA`: `bwsp`
  (WindowBounds, ShowToolbar, ShowSidebar, ShowStatusBar, ShowPathbar,
  SidebarWidth) and `icvp` (iconSize 96.0, textSize, gridSpacing, ...). No record
  named `.` is ever written to the folder's own store by Finder 10.6.8.
- Consequence: Workspace's DSStoreInfo, which reads and writes `.` in the
  folder's own `.DS_Store`, does not interoperate with 10.6 Finder for window
  and view settings (see E2 for the read direction).
- Fixture: `E1-parent-icvp-bwsp.DS_Store` (records eA, eB, f1, t1).

## E2 - records named `.` in the folder's own .DS_Store are ignored by Finder

- Date: 2026-10-11
- Steps: our DSStore code (`dstool put`) wrote `icvp` (iconSize 96.0, complete
  key set from E6) and `bwsp` (WindowBounds {{300, 300}, {600, 400}}) under
  record `.` into `c4/.DS_Store`; folder pushed to the Mac; Finder restarted;
  `icon size` and `bounds` read through AppleScript. Repeated for `vstl` = clmv
  in `w5/.DS_Store` with the global last-used view set to icon.
- Observed: icon size 48 (default), default bounds, icon view. Nothing from the
  own store was honoured. The same icvp content under the record named after
  the folder in the parent store was honoured (96).
- Fixture: none needed (input was generated; recipe `reverse-icon-size`).

## E3 - when Finder writes .DS_Store after an AppleScript change

- Date: 2026-10-11
- Steps: python on the Mac sampled the parent store's mtime and size every 0.1 s
  after `set icon size ...` returned (osascript itself takes 0.07 s).
- Observed: when Finder had not written that store for a while the store changed
  0.1 to 0.4 s after the call (3 of 3 runs). A second change within about 5 s of
  a write is held back and written 5.1 to 5.2 s after the change. The first write
  that creates a parent store also appeared about 5 s late. A wait of more than 6 s after the last change always sufficed.
- Conclusion: writes are coalesced on a roughly 5 s timer; do not read the files
  back sooner than 6 s after the last change unless you flush (E4).
- Fixture: `E3-icon-size-96.parent.DS_Store` (record `@`, as pulled by recipe
  `icon-size`).

## E4 - what forces a flush

- Date: 2026-10-11
- Steps: change inside the 5 s hold-back window, then (a) wait, (b) `close every
  window`, (c) `tell application "Finder" to quit`, (d) `killall Finder`; poll
  the parent store.
- Observed: (a) flushed after 5.18 s; (b) closing windows did NOT flush earlier
  (5.16 s, 5.17 s); (c) AppleScript quit flushed after 0.54 s and launchd
  respawns Finder in about 2 s; (d) SIGTERM lost the pending change, nothing was
  written in 9 s and the record never appeared.
- Conclusion: reliable flush = `mac-oracle flush` (AppleScript quit, wait for the
  new Finder). Windows are closed by it, which is also what resets state for
  `finder-get` to read what was persisted.
- Fixture: none (timing).

## E5 - per-folder view style (vstl) needs "Always open in <view>"

- Date: 2026-10-11
- Steps: (a) by AppleScript `set current view of window to list view` (also icon,
  column, flow in turn), Finder quit after each, stores dumped; closing the window
  and reopening after a Finder restart. (b) With UI scripting (System Events,
  accessibility flag created and removed again, Finder restarted) the View Options
  window was opened with Cmd-J and the "Always open in list view" checkbox was
  clicked, then Finder quit and the stores dumped.
- Observed: (a) no `vstl` record anywhere; the window nevertheless reopened in
  list view because Finder remembers the last used view globally
  (`FXPreferredViewStyle`, here `Nlsv`) and applies it to any folder without a
  stored style; a second fresh folder opened as list too. (b) the parent store
  gained `g1 vstl type: Nlsv` and nothing else for that folder. The other styles
  are `icnv`, `clmv`, `Flwv`.
- Read side: a `vstl` record under the folder's name in the parent store is
  honoured for all four codes (icon view, column view, list view, flow view read
  back through AppleScript with the global last-used view set to icon); a `.`
  record in the folder's own store is ignored (E2).
- Conclusion: the AppleScript `current view` cannot be used to make Finder write a
  per-folder view style; recipes needing `vstl` must use GUI scripting or write
  the record themselves with `dsput`.
- Fixture: none kept for the GUI case (text dump above); recipe `view-style`
  checks (a).

## E6 - what Finder needs in an `icvp` record before it honours it

- Date: 2026-10-11
- Steps: one parent store with 18 `icvp` records (named drop1..drop13, ver1,
  onlysz, sz_text, sz_grid, sz_arr) all with iconSize 96, the full key set minus
  one key each, installed with Finder stopped, `icon size` read per folder.
- Observed: 96 (honoured) only when textSize, gridSpacing, labelOnBottom,
  showItemInfo, showIconPreview, arrangeBy and the three backgroundColor keys
  were all present. Records lacking any of those were ignored as a whole (48).
  Records lacking backgroundType, gridOffsetX, gridOffsetY or viewOptionsVersion
  were honoured. `viewOptionsVersion` = 1 was ignored (Finder writes 0). Integer
  values are accepted in place of the reals Finder itself writes (iconSize 96
  as integer read 96). A record with only iconSize and viewOptionsVersion was
  ignored.
- Fixture: `E6-icvp-key-matrix.parent.DS_Store` (the 18 records).

## E7 - bwsp WindowBounds coordinates

- Date: 2026-10-11
- Steps: records `bwsp` with chosen WindowBounds pushed, bounds read back; and
  the other way round (AppleScript bounds set, record dumped).
- Observed: AppleScript `bounds` {l, t, r, b} of a window with toolbar maps to
  `WindowBounds = {{l, screenH - b}, {r - l, (b - t) + 22}}`; origin is bottom
  left, y up, and the height includes the 22 px title bar. Screen height 768.
  Examples: bounds {200,200,700,600} -> {{200, 168}, {500, 422}};
  WindowBounds {{100,100},{500,300}} -> bounds 100,390,600,668;
  {{50,400},{400,250}} -> 50,140,450,368; {{300,300},{600,400}} -> 300,90,900,468.
- Fixture: `E1-parent-icvp-bwsp.DS_Store` for the first example.

## E8 - which AppleScript option writes which record (single pass)

- Date: 2026-10-11
- Steps: 24 fresh folders, one option each set by AppleScript, one Finder quit,
  every folder dumped (parent records, own store, xattrs).
- Observed, per option:
  - icon-size, icon-text-size, label-position (labelOnBottom 0 for right),
    arrangement (snap to grid -> arrangeBy `grid`), shows-item-info,
    shows-icon-preview: `icvp` keys iconSize, textSize, labelOnBottom, arrangeBy,
    showItemInfo, showIconPreview. background-color: icvp backgroundType 1 and
    backgroundColorRed/Green/Blue as reals (65535,0,0 stored as 0.985948, 0.0,
    0.0287831, so not exact).
  - toolbar-visible false: `bwsp` ShowToolbar 0, ShowSidebar 0, SidebarWidth 193
    and a changed WindowBounds. sidebar-width 150: bwsp SidebarWidth 150 (the
    property reads 0 while the toolbar is hidden). bounds: bwsp WindowBounds.
  - statusbar-visible false: no record at all.
  - current-view list: no record (E5). list-sort-column, list-text-size,
    list-icon-size (small/large -> 16.0/32.0), list-calculates-folder-sizes,
    list-uses-relative-dates: `lsvp` with sortColumn, textSize, iconSize,
    calculateAllSizes, useRelativeDates and a `columns` dictionary (comments,
    dateCreated, dateLastOpened, dateModified, kind, label, name, size, version,
    each with ascending, index, visible, width).
  - list-column-width and list-column-index by script: CORRECTED by E10 (the
    first reading went through the repo decoder, which loses records after a
    `shor`): width writes `lsvp` columns.<col>.width; index rewrites only that
    column's 0-based index (duplicates possible) and has no visible effect.
    list-column-visible:comment produced the legacy triple `LSVO` bool, `lsvo`
    blob and `lsvt` shor (value 12, not 0) and no lsvp change; no visible effect.
  - item comment: xattr `com.apple.metadata:kMDItemFinderComment` AND a `cmmt`
    ustr record in the folder's own .DS_Store. item label-index: only
    FinderInfo (flags bits). item locked: BSD uchg flag, no xattr, no record
    (blocks deleting the folder until `chflags nouchg`). item extension-hidden:
    FinderInfo.
- Fixtures: `E8-option-matrix.parent.DS_Store`, `E8-option-matrix.dump.txt`,
  `E8-comment.own.DS_Store`, `E8-list-view-lsvp.parent.DS_Store`.

## E9 - oracle plumbing facts

- Date: 2026-10-11
- `screencapture` over ssh returns 0 and writes nothing (no window server
  access); `launchctl bsexec` under sudo did not help either.
  `CGWindowListCreateImage` through the Mac's system python (Quartz) works from
  ssh and is what `mac-oracle shot` uses; `-l` and `-R` do not exist in 10.6's
  screencapture and `sips` has no crop offset. Finder's AppleScript bounds start
  below the 32 px title and toolbar, so the grab extends upwards by 32 px.
- `pgrep` does not exist in 10.6; use `ps -axco pid,command`.
- UI scripting from ssh needs `/private/var/db/.AccessibilityAPIEnabled`
  (root-owned, created with sudo and removed again after the test) and a restart
  of both System Events and Finder before it takes effect; with the flag absent
  System Events refuses with -1719/-1728.
- A Finder quit is undone within about 2 s by launchd; anything that must be
  written while Finder is down has to be done with the process stopped
  (`killall -STOP Finder`, edit, `killall -KILL Finder`), which is how `reset`
  restores the preference baseline (`defaults read com.apple.finder` identical
  to the recorded baseline after reset, checked by diff).
- Fixture: none.

## E10 - list view columns: 10.6 honours `lsvp`; the legacy triple loses

- Date: 2026-10-11
- Steps: (a) parent records pushed (`dsplist`, `dsraw`) with `vstl` Nlsv, then
  window shown (`shot --at`), View Options panel read by UI scripting
  (`view-options`) and AppleScript `list view options` read: la1/la2 `lsvp`
  only (distinct widths, order, kind hidden, comments and label visible, sort
  size, text 13, icon 32); la3 legacy only (`LSVO` true, hand-made `lsvo`,
  `lsvt` 0); la4 both, with conflicting values. (b) fresh folder ua2, View
  Options checkbox "Version" clicked by UI scripting (`view-option-click`),
  Finder quit. (c) fresh folders, AppleScript `width`, `index`, `visible` of a
  column (and icon size, sort, text size, relative dates first), Finder quit.
  All stores read with `dsread` (independent parser).
- Observed (a): `lsvp` alone is honoured completely: widths, order (by
  `index`, 0-based), visibility, sortColumn, textSize, iconSize. Legacy alone
  is honoured too (order = blob order, widths, visibility; text size came out 0
  = `lsvt`). With both present `lsvp` wins in every field. The View Options
  panel shows the `lsvp` state. AppleScript `visible` of a column does NOT
  report lsvp: it reports the legacy record, or the defaults when none exists.
- Observed (b): the UI click writes only `lsvp` (version.visible true, all
  other keys as defaults: viewOptionsVersion 0, textSize 12.0, iconSize 16.0,
  sortColumn name, calculateAllSizes false, useRelativeDates true,
  showIconPreview true, nine columns with ascending/index/visible/width), no
  legacy triple.
- Observed (c): AppleScript `width` -> lsvp width (honoured). AppleScript
  `index` 2 on kind -> lsvp kind.index 1 while dateModified keeps index 1
  (duplicate); the window order did not change. AppleScript `visible` -> only
  `LSVO` true + `lsvo` + `lsvt` 12; the lsvo it writes is a constant default
  layout (same header, sort `dnam`, lsvt 12) with only that column's
  visible byte flipped, even when lsvp says icon 32, sort size or text 14; the
  column does not appear. AppleScript is therefore useless for visibility.
- `lsvo` layout as Finder wrote it (bytes): `lsv1`, 0x09 0x00 0x10 (constant in
  every sample, meaning unknown), sort column fourcc, count (0x08), then per column fourcc, width (u16 BE),
  sort direction (1 ascending, 2 descending), visible (0/1). Codes: dnam name,
  modd modified, ascd created, phys size, kind, labl label, shvr version, cmmt
  comments; no date-last-opened. `lsvt` shor = text size (stored in 4 bytes).
- Consequence for Workspace: read and write `lsvp`; reading `lsvo`/`lsvt` is
  only a fallback when no lsvp exists; never write the legacy triple.
- Decoder bug found on the way: the repo DSStore loader read `shor` as 2 bytes
  (it is 4), losing every later record; reported to the coordinator. The oracle
  now reads stores with `Tools/mac-oracle/dsread`, and `push` refuses to merge
  into a parent store holding `shor` records.
- User drags (answered later with `mac-oracle drag`, see E21): a border drag
  writes lsvp width, a header drag rewrites all nine indexes as 0..8.
- Fixtures: `E10-list-records.parent.DS_Store` (la1..la4 inputs, ua2 written
  by the UI click), `E10-applescript-columns.parent.DS_Store` (w1..w6 of c),
  `E10-input-*.plist|hex` (inputs), `E10-la2-lsvp-honoured.png`,
  `E10-la4-lsvp-wins.png`, `E10-w4-applescript-visible-noop.png`.

## E11 - scrollPositionX/Y in icvp and lsvp: top-left origin, points

- Date: 2026-10-11
- Steps: (a) s1, 80 files, icon view, window bounds {10,470,600,725}; the scroll
  bars set by UI scripting (value 0, 0.5, 1), AX position of the scroll area and
  of its content group read, window closed, Finder quit, parent record dumped.
  (b) s2/s3 pushed with an icvp carrying scrollPositionX/Y (s3 has one icon
  placed at Iloc 1500,700 so the content is wider than the window), the AX
  geometry read after opening. (c) s4 list view, both scroll bars to 0.5, same.
- Observed (a): Finder writes `scrollPositionX`/`scrollPositionY` (reals) into
  the folder's icvp in the parent store when the window closes. Values equal
  the offset of the visible area's top-left corner from the content's top-left
  corner in points, y growing downwards: top 0.0/0.0; v 0.5 -> Y 1154.0 (content
  moved up 1154 px); end -> X 94.0, Y 2309.0 (content 2493 high, visible 184
  above the horizontal scroller).
- Observed (b): read side honoured: icvp X 300, Y 200 opened with the content
  shifted by exactly 300/200 px. X is only applied when the content is wider
  than the view (s2: X 50 with no horizontal scroller -> 0).
- Observed (c): list view stores the same keys in `lsvp` (X 156.0, Y 676.0).
  Finder additionally keeps `ListViewScrollOrigin` in the window restore state
  (com.apple.finder BrowserWindowState), not per folder.
- Fixtures: `E11-scroll.parent.DS_Store` (s1..s4), `E11-s3-input.own.DS_Store`
  (Iloc input), `E11-s1-scrolled.png`.

## E12 - background picture: icvp backgroundType 2 + backgroundImageAlias

- Date: 2026-10-11
- Steps: (a) b1 with bg.png inside, AppleScript `set background picture of icon
  view options of w to file "bg.png" of folder f`, Finder quit, dumped. (b)
  pushed icvp (complete E6 key set) with backgroundType 2 and a hand-built
  AliasRecord to `bg.png` (a green PNG) in the case folder: b3 with tags
  0 (parent name), 2 (HFS path), 14, 15 (Unicode names), 18 (POSIX path), 19
  ("/"), all IDs and dates 0; b4 only tag 2; b5 only tag 18; b6 no tags.
  Checked with AppleScript `background picture` and `shot` (pixel colour). (c)
  legacy records without icvp: b7 `BKGD` blob `ClrB` ffff 0000 0000 (red);
  b8 `BKGD` `PctB` + length and `pict` blob = b4's alias.
- Observed (a): only the icvp changed: `backgroundType` 2 and
  `backgroundImageAlias` = a classic AliasRecord (Alias Manager, not a
  bookmark): userType 0, size 0x0160, version 2, kind 0, volume name Str27
  "Macintosh HD", volume date, 'H+', parent dir ID, Str63 name "bg.png", file
  ID, file date, type/creator 0, nlvlFrom/To 0xffff, volume attrs 0x0920; then
  tags 0 "b1", 1 (5 dir IDs up to the root), 2 "Macintosh
  HD:Users:user:Desktop:mi:b1:bg.png", 14 Unicode name, 15 Unicode volume
  name, 18 "Users/user/Desktop/mi/b1/bg.png" (no leading slash), 19 "/",
  21 0x000b, end 0xffff. No `BKGD`/`pict` record written.
- Observed (b): b3 and b4 shown with the green background (and AppleScript
  returns the file); b5 (POSIX path only) and b6 fall back to white with
  AppleScript error "AppleEvent handler failed". So without CNIDs the HFS
  path (tag 2, "Volume:dir:...:file") is what 10.6 resolves; tag 18 alone is
  not enough. Finder did not rewrite the minimal alias after resolving it.
- Observed (c): both legacy BKGD records were ignored (white).
- Consequence: write icvp backgroundType 2 with an alias carrying at least
  the header (volume name, file name) and tag 2; read both CNID-less and full
  aliases by their path tags.
- Not answered: whether a picture on another volume or in a hidden
  `.background` folder needs more than tag 2 (not tried).
- Fixtures: `E12-background.parent.DS_Store` (b1 Finder-written, b3..b8
  inputs), `E12-finder-written-background.alias`,
  `E12-input-hfs-path-only.alias`, `E12-input-posix-path-only.alias`,
  `E12-b3-minimal-alias-honoured.png`.

## E13 - bwsp: toolbar and sidebar width are per folder, the bars are global

- Date: 2026-10-11
- Steps: (a) pushed `bwsp` per folder (list view): t1 ShowPathbar true,
  ShowSidebar false, ShowStatusBar false, ShowToolbar true, SidebarWidth 250;
  t2 the opposite bars, width 250; t3 ShowToolbar false; read by AppleScript
  and `shot`. (b) View menu clicked by UI scripting ("Pfadleiste einblenden",
  "Statusleiste ausblenden", "Seitenleiste ausblenden"), windows closed,
  Finder quit, bwsp and `com.apple.finder` read; fresh folders opened after.
- Observed (a): ShowToolbar false is honoured per folder (t3: no toolbar, no
  sidebar, item info line under the title). SidebarWidth is honoured per folder
  (250 shown and read back by `sidebar width`). ShowPathbar, ShowSidebar and
  ShowStatusBar in bwsp are ignored on read (t1 and t2 looked the same:
  sidebar, status bar, no path bar).
- Observed (b): path bar and sidebar are global settings: the menu writes
  `com.apple.finder` `ShowPathBar` = 1 (capital B) / `ShowSidebar` = 0 and every
  window, including folders whose bwsp says otherwise, follows. Finder copies
  the current global state into each window's bwsp when it saves it
  (ShowPathbar true, ShowSidebar false after the change). The status bar
  cannot be hidden while the toolbar is shown (menu click had no effect,
  AppleScript `statusbar visible false` writes nothing, E8); bwsp
  ShowStatusBar stayed true. With the toolbar hidden the status text moves
  under the title bar.
- Consequence: per folder, honour ShowToolbar, SidebarWidth and WindowBounds;
  treat the three bar flags as a snapshot of global settings (write the current
  globals, do not let them override the global on read).
- Fixtures: `E13-bwsp.parent.DS_Store` (t1..t5), `E13-t1-t2-bwsp-bars-ignored.png`,
  `E13-t3-toolbar-hidden.png`, `E13-global-sidebar-hidden.png`.

## E14 - where 10.6 keeps view records for the volume root, home, Desktop and read-only places

- Date: 2026-10-11
- Steps: (a) existing `/.DS_Store` and `~/.DS_Store` read; AppleScript icon size
  set for the startup disk window (68) and the home window (76), Finder quit,
  stores read, values read back after a restart. (b) `~/Desktop` opened as a
  window, icon size 100; the desktop itself (`window of desktop`) icon size
  64. (c) folder `ro/child` with `ro` mode 555, icon size 96 set; then a `.`
  icvp (96) planted in `child/.DS_Store`. (d) `/Users/Shared` (parent `/Users`
  root-owned), icon size 92. (e) read-only UDZO disk image mounted, icon size
  set for its root and a subfolder. All Mac files restored byte-identical from
  backups afterwards; `reset` restored the preferences.
- Observed (a): volume root and home folder use records named `.` in their OWN
  store (the exception to E1/E2): `/.DS_Store` `.` bwsp/icvp, `~/.DS_Store` `.`
  bwsp/icvp; written there (iconSize 68.0 / 76.0) and honoured on read (home
  icvp iconSize 84 and both bwsp WindowBounds matched the open windows).
- Observed (b): the Desktop folder window follows the normal rule (records
  `Desktop` bwsp/icvp in `~/.DS_Store`). The desktop background itself keeps its
  icon view options in `com.apple.finder` `DesktopViewSettings` ->
  `IconViewSettings` (the icvp key set, iconSize 64); its item positions are
  `dilc` records (32-byte blobs) in `~/Desktop/.DS_Store`, not `Iloc`; Finder
  rewrites every dilc on each launch with bytes 24..27 changed (a running
  stamp, e.g. 078d3133 -> 078d326c after ~25 min of Finder restarts), the other bytes
  (positions) unchanged. Volume
  icons on the desktop are positioned via `com.apple.finder`
  `FXDesktopVolumePositions`.
- Observed (c), (d), (e): when the parent store cannot be written the setting
  lives only for the session: nothing in the parent, no `.` record in the
  folder's own store, nothing in `~/Library/Caches` (no
  `com.apple.finder` cache dir exists) or the preferences; after a Finder
  restart the default (48) is back. A planted `.` record in such a folder is
  ignored (48). The read-only volume root also got nothing.
- Fixtures: `E14-volume-root-dot.own.DS_Store`, `E14-home-dot.own.DS_Store`,
  `E14-home-with-Desktop-record.DS_Store`, `E14-desktop-dilc.own.DS_Store`,
  `E14-ro-child.own.DS_Store`.

## E15 - real 10.6 AppleDouble (`._`) files: two layouts (S1, S3)

- Date: 2026-10-11
- Steps: on the Mac (HFS+) files with: FinderInfo only (fi.txt, fdFlags 0x0010),
  one xattr (one.txt), FinderInfo + five xattrs incl. a comment, a 300-byte
  value and an empty value (many.txt), a 300-byte resource fork + FinderInfo +
  one xattr (rsrc.txt), quarantine only (quar.txt), one 3700- and one
  3802-byte xattr (big*), a folder with FinderInfo 0x0400 (dir). Copied with
  `cp -Rp` and with a Finder `duplicate` onto an MS-DOS (FAT) disk image, packed
  with `tar -c` and `ditto -c -k --sequesterRsrc`; the raw `._` files fetched
  with `COPYFILE_DISABLE=1 tar`. Parsed byte by byte.
- Observed, common: magic 0x00051607, version 0x00020000, filler "Mac OS X"
  + 8 spaces, always 2 entries in the order 9 (Finder Info) at offset 50, then
  2 (resource fork). The ATTR block follows the 32 FinderInfo bytes after 2
  zero pad bytes (ATTR header at 84, entries at 120, each entry 11 bytes +
  NUL-terminated name, padded to 4). Entries are sorted by name
  (com.apple.metadata:... before org.example.*); values are packed back to back
  without alignment, data_start right after the last entry. ATTR header flags
  and every entry's flags are 0 in every file from all producers (S3: never
  non-zero seen).
  A file without FinderInfo gets 32 zero bytes. No ATTR block when there are no
  xattrs besides FinderInfo.
- FAT layout (cp -p and Finder copy produce byte-identical files): padded to
  4096; entry 9 length 3760 (ATTR total_size 3810, debug_tag 0x3b9ac9ff),
  entry 2 at 3810 holding an EMPTY resource map of 286 bytes (starts
  00000100 00000100 00000000 0000001e) when the file has no fork, or the fork
  itself (rsrc.txt: 300 bytes, file 4110). With 3802 bytes of xattrs the file
  grows to 8192 (entry 9 length 7856, rsrc at 7906). Empty value: offset =
  end of data, length 0.
- tar / ditto layout (compact, identical between both): no padding, entry 9
  length 32 when only FinderInfo (file 82 bytes), entry 2 length 0 when no
  fork, otherwise the fork right after the ATTR data; debug_tag is a
  per-file number (0x000f4618, ...); an empty value is written with offset 0.
  `ditto -c -k --sequesterRsrc` put no `._one.txt` (xattr only, no FinderInfo)
  into `__MACOSX` but did for quar.txt (unexplained, observed once).
- HFS+ on 10.6 refuses one xattr longer than 3802 bytes (E2BIG), and a
  com.apple.FinderInfo of any length but 32 (ERANGE).
- Fixtures: `E15-appledouble-fat/`, `E15-appledouble-tar/`,
  `E15-appledouble-ditto/`; `<name>.ad` is the `._<name>` file.

## E16 - com.apple.quarantine on copies (S2)

- Date: 2026-10-11
- Steps: files with com.apple.quarantine values `0000;4e8f1c2a;Safari;`,
  `0001;...;Safari;|com.apple.Safari`, `0002;...`, `0041;...` and a Mail one
  with an event UUID; copied with `cp`, `cp -p`, `ditto`, Finder `duplicate`
  (HFS+ to HFS+), `tar -c | tar -x`, `ditto -x -k`, and `cp -Rp` / Finder copy
  to a FAT volume.
- Observed: `ditto` (file to file) copies every value verbatim. `cp`, `cp -p`,
  Finder duplicate and `tar -x` copy the value verbatim only when the flags
  field is 0000; with any non-zero flags (0001, 0002, 0041) the copy has NO
  quarantine. Archives keep it: `tar -c` and `ditto -c -k` store it in the `._`
  entry verbatim (E15 quar.txt); extracting with `tar -x` or `ditto -x -k`
  drops it again (flags 0002). Copies onto FAT (cp -Rp, Finder) wrote no `._`
  for the quarantine-only file at all.
- Not answered: why the copy engine drops flagged values (probably the
  quarantine library re-applying, not a plain xattr copy); values were
  synthetic, no real download exists on the oracle.
- Fixture: `E15-appledouble-tar/quar.txt.ad`.

## E17 - FinderInfo of length != 32 and FinderInfo inside ATTR in a sidecar (S4)

- Date: 2026-10-11
- Steps: hand-made compact `._` files (the E15 tar layout) on a FAT volume:
  a: entry 9 of 16 bytes, no ATTR; b: entry 9 zero (32) + ATTR entry
  `com.apple.FinderInfo` of 16 bytes; c: entry 9 "TEXTttxt..." + ATTR entry
  `com.apple.FinderInfo` "AAAABBBB..." (32); d: entry 9 + ATTR
  `org.example.one`. Read with `xattr` on the FAT volume, copied to HFS+ with
  `cp -Rp` and Finder `duplicate`.
- Observed: a: no FinderInfo at all (the 16 bytes are ignored), copies get
  nothing. b: `xattr -l` lists com.apple.FinderInfo but reading it fails
  ("No such xattr"); `cp -Rp` reports "could not copy extended attributes ...
  Attribute not found", Finder drops it silently; the copy has no FinderInfo.
  c: entry 9 wins, the ATTR copy is ignored. d: accepted completely, so the
  compact layout written by our side is read by 10.6.
- Added later (E28): e: a sidecar with only entry 2 (n = 1, fork at offset
  38) is rejected by 10.6 copyfile ("copyfile unpack failed: File exists",
  dot_clean "Merging failed"), the file gets no fork; f: the same fork with an
  all-zero entry 9 first (n = 2, fork at 82) is unpacked fine.
- Consequence: FinderInfo belongs in entry 9 with exactly 32 bytes; never
  emit it as an ATTR entry; on read ignore an ATTR com.apple.FinderInfo; always
  write entry 9 (zeros if needed) before entry 2.
- Fixtures: `E17-odd-sidecars/` (`._a.txt` .. `._d.txt`, `._e-rsrc-only-n1.txt`,
  `._f-zero-finderinfo-plus-rsrc.txt` as pushed).

## E18 - custom icons, hidden extension, Locked, kNameLocked (S13)

- Date: 2026-10-11
- Steps: (a) reference written by 10.6 itself: `NSWorkspace setIcon:forFile:`
  (system python, AppKit) with a 512 px PNG on a file and on a folder; fetched
  with tar as `._` files. (b) pushed: x1.txt with a classic resource fork
  holding one `icns` resource id -16455 whose icns has ONLY ic08 (256 PNG) and
  ic09 (512 PNG), FinderInfo 0x0400; x2.txt with the bare icns bytes as the
  whole fork (what `GSFileMetadata -setCustomIconData:` writes today), 0x0400;
  folder `fold` 0x0400 with `Icon\r` (empty data fork, FinderInfo 0x4000, fork
  as x1); fold2 = Icon\r but no 0x0400 on the folder; fold3 = 0x0400 and an
  Icon\r with zero FinderInfo. Window at icon size 128, `shot`. (c)
  AppleScript `extension hidden` true, `locked` true, rename of a file whose
  FinderInfo has 0x1000 (kNameLocked) by AppleScript and by UI (Return, type,
  Return), rename of the locked file.
- Observed (a): file: FinderInfo fdFlags 0x0400 only (type/creator stay 0),
  fork 71566 bytes: data offset 256, map at the end (map length 50, no names),
  one `icns` id -16455 with members is32 s8mk il32 l8mk it32 t8mk ic08 ic09,
  ic08/ic09 are JPEG 2000 (0000000c 6a502020). Folder: FinderInfo 0x0400 on
  the folder, empty data fork file `Icon\r` with FinderInfo fdFlags 0x4000
  (invisible, type/creator 0), xattr com.apple.TextEncoding "macintosh;0",
  and the same fork.
- Observed (b): x1 shows the custom icon (PNG-only icns in a proper resource
  fork is enough for 10.6). x2 does NOT (generic text preview): a fork without
  resource map is not read, so GSFileMetadata must wrap the icns in a resource
  map (type `icns`, id -16455). fold and fold3 show the icon, fold2 does not:
  the folder needs 0x0400; Icon\r does not need the invisible flag.
- Observed (c): hide extension = FinderInfo fdFlags 0x0010 (bytes 8-9 `00 10`),
  nothing else. Locked = BSD `uchg` only: no FinderInfo, no kNameLocked; an
  AppleScript rename of it returns without error but nothing changes.
  kNameLocked (0x1000) is not honoured: both the AppleScript and the UI rename
  succeeded and the flag stayed on the renamed file.
- Fixtures: `E18-custom-icon/` (nsworkspace-file.ad, nsworkspace-folder.ad,
  nsworkspace-folder-Icon_CR.ad = the `._Icon\r`, input-png-icns-resource-fork.rsrc,
  input-raw-icns-as-fork.rsrc, icon256/512.png, hidden-extension-a.txt.ad, two
  shots).

## E19 - alias files and internet location files (S14)

- Date: 2026-10-11
- Steps: (a) Finder AppleScript `make new alias file` to a file (a.txt), a
  folder (tdir) and a file on a mounted HFS+ disk image (ALVOL/remote.txt);
  `make new internet location file` for http, ftp and mailto URLs. Fetched
  with tar, forks and records decoded. (b) Aliases with only the data fork or
  only the resource fork left (copies of alias-file). (c) Pushed what the
  p-links code writes (`mklinks.m`, built from gw-wt/p-links FSNode):
  `+writeAliasFileForTargetPath:` for a file and a folder, `+writeAliasBookmark...`
  for a file, `+[FSNLocationFile writeWeblocForURL:...]`, plus a hand-made
  classic webloc with only a `url ` resource; Finder asked for `class`, `kind`,
  `original item` and `location`; `shot`.
- Observed (a) aliases: FinderInfo type `alis` (folder: `fdrp`), creator
  `MACS`, fdFlags 0x8400 (kIsAlias + kHasCustomIcon). The data fork is NOT
  empty: it holds a bookmark (`book` 0000 0000 `mark` 0000 0000 ...,
  43368 / 519072 / 44296 bytes incl. icon data). The resource fork holds `alis`
  id 0 (classic AliasRecord v2, 348 / 344 / 656 bytes) and `icns` id -16496
  (the target's icon). AliasRecord tags written: 0 parent name, 16 and 17
  (8-byte high-res dates), 1 dir IDs, 2 HFS path, 14 Unicode name, 15 Unicode
  volume name, 18 POSIX path relative to the mount point (boot volume:
  "Users/user/.../a.txt" without leading slash; other volume: "/remote.txt"),
  19 mount point ("/" or "/Volumes/ALVOL"), 21 0x000b; the other-volume alias
  adds tag 20 (an alias to the disk image file alvol.dmg) and drive type 5,
  volume attrs 0x0d02.
- Observed (a) location files: name gets `.webloc` / `.ftploc` /
  `.mailtoloc`, FinderInfo type `ilht` / `ilft` / `ilma`, creator `MACS`,
  fdFlags 0x0010 (extension hidden). Data fork = XML plist with key `URL`;
  resource fork = `drag` 128 (48 bytes), `TEXT` 256 and `url ` 256 (both the
  URL bytes, no terminator).
- Observed (b): only the resource fork counts on 10.6: rsrc-only resolves,
  data-fork bookmark only does not ("Can't make original item").
- Observed (c): our classic alias files (empty data fork, `alis` 0 in the
  fork, FinderInfo `alis`/`MACS` 0x8000, CNIDs and dates 0, tags 0, 1 empty,
  14, 15, 2, 18 with a leading slash, 19) resolve for the file and the folder
  (even with type `alis` instead of `fdrp`). Our bookmark-only alias is an
  "alias file" but does not resolve. Both our XML-only `.webloc` (no FinderInfo,
  no fork) and the `url `-only classic webloc (id 256, empty data fork,
  `ilht`/`MACS`) are internet location files with the right `location`.
  Cosmetic: without 0x0400 + icns -16496 our aliases show a generic
  application icon with the alias arrow, not the target's icon.
- Not answered: opening the location files (would launch a browser on the
  oracle); whether 10.6 needs `fdrp` for anything beyond the icon.
- Fixtures: `E19-links/finder/` (Finder-written, data + `._`; alias-folder is
  ~1 MB because of the icon), `E19-links/ours/` (pushed inputs, mklinks.m,
  shot.png).

## E20 - list view sorting: first click, `ascending`, hidden sort column (S5)

- Date: 2026-10-11
- Steps: fresh folders (default sort by name) with alpha.txt 10 KB mtime
  2026-10-10, beta.dat 1 KB 2020-01-01, gamma.rtf 100 KB 2023-01-01; a column
  header (Größe, Änderungsdatum, Art, Name) clicked three times by UI
  scripting, row order and AppleScript sort direction read after each click;
  Finder quit, lsvp read. Then the folder reopened, and the sort column (size)
  hidden in View Options.
- Observed, first click: Size -> largest first (gamma, alpha, beta);
  Date Modified -> newest first (alpha, gamma, beta); Kind -> A to Z by kind
  string (beta "Dokument", gamma, alpha); Name (already the sort column) ->
  toggles to Z to A. Every further click on the sort column toggles.
- `ascending` is literal: size/date with largest/newest first are stored as
  ascending false, kind A-Z as true, name Z-A as false; AppleScript calls
  ascending "normal" and descending "reversed". The defaults (E10) are
  therefore the first-click directions: name, kind, label, version, comments
  true; dateModified, dateCreated, dateLastOpened, size false. Each column keeps
  its own direction; reopening honours sortColumn + that column's ascending.
- Hiding the sort column: sortColumn becomes `name` (order by that column's
  stored direction, here A-Z), the hidden column keeps its ascending value.
- Fixtures: `E20-header-clicks.parent.DS_Store` (records s5d248 = size,
  s50e3f = date, s5978d = kind, s549ee = name), `E20-sort-column-hidden.parent.DS_Store`.

## E21 - user column drags; Name cannot leave the left edge (S6)

- Date: 2026-10-11
- Steps: fresh list view folder s6 (window {10,470,1014,725}); header
  geometry read by AX; Quartz mouse drags posted with `mac-oracle drag`:
  (1) Name/Date border from x 502 to 582; (2) the Größe header dragged to x 210
  (left of Name); (3) the Name header dragged to x 900; Finder quit, lsvp read.
- Observed: (1) Name width 300 -> 380. (2) Größe moved only to the second
  place, directly after Name. (3) Name did not move. So Name is pinned as the
  first column; no column can be placed before it.
- Written lsvp: name width 380 index 0; size index 1, dateModified 2,
  dateCreated 3 (hidden), kind 4, label 5, version 6, comments 7,
  dateLastOpened 8: a reorder renumbers every column, visible or not, as a
  contiguous 0..8 permutation (unlike AppleScript `index`, E10).
- Fixtures: `E21-user-drag.parent.DS_Store`, `E21-user-drag.png`.

## E22 - list view date wording, Date Last Opened, empty cells (S7)

- Date: 2026-10-11 (oracle locale German, clock 09:51 CEST)
- Steps: lsvp pushed with Modified, Created, Last Opened, Version, Comments
  visible, useRelativeDates true (s7rel) and false (s7abs); files with mtimes
  now, -1 h, yesterday 10:15, -3 days, 2025-03-15, 2001-07-04, tomorrow 08:00,
  2030; one file born 2020 and modified now; a copy of Calculator.app; one
  comment. `shot`, `mdls`.
- Observed, relative on: today "Heute, 09:51", yesterday "Gestern, 10:15",
  everything else (3 days ago, last year, 2001, tomorrow, 2030) the short
  absolute form "08.10.2026 09:30" (date dd.mm.yyyy, time HH:MM, no seconds,
  no weekday); there is no "Morgen" and no weekday names. Relative off: every
  date in the absolute form, also for today. Same wording in all three date
  columns.
- Date Last Opened shows Spotlight's kMDItemLastUsedDate; a never-opened file
  gets one at import time (equal to its creation date for the 2020-born file,
  to the mtime for touched files), so the column is never empty in these
  samples. One anomaly: i-future showed 01.01.2030 while mdls said today
  09:52 (not explained).
- Empty Version and empty Comments show "--" (also for folders/.DS_Store);
  Version shows "4.5.3" for the app (= its kMDItemVersion); the app is
  listed under its localized display name "Rechner" without extension.
- Not answered: wording in other locales (oracle only has German).
- Fixtures: `E22-dates-rel-abs.png`, `E22-dates-more.png`,
  `E22-input-lsvp-rel.plist`.

## E23 - size column and icon view item info (S8, S10)

- Date: 2026-10-11 (German locale; NOTE the oracle has AppleShowAllFiles = 1)
- Steps: list view with Size and Kind, calculateAllSizes true (s8calc) and
  false (s8nocalc) pushed as lsvp; files of 1, 1000, 1024, 1000000, 1048576,
  5500000 bytes, a hard link, folder `sub` (300000-byte file + 2-byte hidden
  file), a Calculator.app copy (3772855 bytes logical, 4216 KiB allocated);
  `shot`. Then icon view with `shows item info` true, plus an empty folder,
  a one-file folder and a 2560x1600 JPEG.
- Observed sizes: units are base 10 and the value is the ALLOCATED (physical)
  size: 1..1024-byte files "4 KB" (one 4 KiB block), 1000000 and 1048576 "1 MB",
  5500000 "5,5 MB" (5.24 if it were base 2), the app "4,3 MB" (4216 KiB
  allocated = 4.32 MB; logical would be 3.8 MB), `sub` "307 KB" (300 KiB incl.
  the hidden file's block). One decimal only when below 10 and not .0
  ("1 MB", "5,5 MB", "4,3 MB"); German decimal comma. Packages show their size
  even with calculateAllSizes false; plain folders show "--" then. A hard link
  is listed with its own size like any file.
- Observed item info (icon view, blue text under the name): folders "Keine
  Objekte", "1 Objekt", "2 Objekte" (the hidden file counted - with
  AppleShowAllFiles on); pictures "2.560 × 1.600" (pixel size, thousands dot,
  multiplication sign); plain files and the application: nothing.
- Not answered: display while sizes are being calculated and live re-sort
  (folders here were too small to catch it); volumes' item info; counts with
  AppleShowAllFiles off (baseline preference of the oracle, left alone).
- Fixtures: `E23-sizes-calc-nocalc.png`, `E23-item-info-1.png`,
  `E23-item-info-2.png`.

## E24 - Label column and list row heights (S9)

- Date: 2026-10-11 (German locale)
- Steps: L0..L7.txt with AppleScript `label index` 0..7, list view, Label
  column switched on by UI click, header clicked twice, cells read by AX;
  FinderInfo dumped. Then text size 10..16 and icon size small/large set by
  AppleScript, AX size and pitch of the rows read.
- Observed labels: FinderInfo fdFlags color bits (mask 0x000E) = 8 - index:
  index 1 -> 0x0E Orange, 2 -> 0x0C Rot, 3 -> 0x0A Gelb, 4 -> 0x08 Blau,
  5 -> 0x06 Violett, 6 -> 0x04 Grün, 7 -> 0x02 Grau. The Label column shows
  the localized label NAME as text ("--" for none). First click on the header
  sorts ascending: no label first, then alphabetical by that localized name
  (Blau, Gelb, Grau, Grün, Orange, Rot, Violett); second click reverses
  exactly (no label last).
- Observed rows: small icons (16): row height = pitch = text size + 7
  (10 -> 17, 11 -> 18, 12 -> 19, 13 -> 20, 14 -> 21, 15 -> 22, 16 -> 23);
  large icons (32): 39 for every text size 10..16.
- Fixture: `E24-label-sort.png`.

## E25 - icon view "arrange by" orders and snap-to-grid drops (S11)

- Date: 2026-10-11 (German locale, AppleShowAllFiles on so .DS_Store shows)
- Steps: s11 with big.bin (100 kB, 2020, label Orange), mid.txt (10 kB,
  2026-10-10, no label), small.rtf (1 kB, 2023, Rot), folder dir (2021, Blau)
  and .DS_Store (6 kB, now). AppleScript `arrangement` set to each "arranged
  by" value; order read from the AX grid. Then `snap to grid`, and the
  .DS_Store icon dragged (`mac-oracle drag`) onto mid.txt's cell; Finder quit,
  own store read.
- Observed orders (row-major):
  name: .DS_Store, big.bin, dir, mid.txt, small.rtf (folders NOT first);
  modification date and creation date: newest first (.DS_Store, mid, small,
  dir, big); size: SMALLEST first, folder first (dir, small 1 kB,
  .DS_Store 6 kB, mid 10 kB, big 100 kB) - the opposite of the list view's
  first click (E20); kind: alphabetical by kind string (Dokument, Formatierter
  Text, MacBinary-Archiv, Ordner, Reiner Text); label: unlabelled first, then
  alphabetical by localized label name (Blau, Orange, Rot).
- Snap to grid drop on an occupied cell: no collision handling; the dropped
  icon takes the same cell and both records get the same Iloc (448,22), the
  older icon is hidden underneath.
- Fixtures: `E25-snap-collision.png`, `E25-snap-collision.own.DS_Store`.

## E26 - showIconPreview default and "off" (S12; scroll position is E11)

- Date: 2026-10-11
- Steps: fresh folder (no icvp) with a 2560x1600 JPEG and an RTF file, icon
  view; AppleScript `shows icon preview` read; `shot`; then set to false,
  `shot` again.
- Observed: without any icvp `shows icon preview` is true (the global default)
  and the JPEG is drawn as its thumbnail, the RTF as a content preview page
  with the "RTF" tag. Off: each file shows its document type icon from the
  owning application (TextEdit RTF icon, Preview JPEG icon), not a blank
  generic document.
- Fixture: `E26-icon-preview-default-off.png` (top default, bottom off).

## E27 - location file names Finder picks itself (S15 part 1)

- Date: 2026-10-11
- Context: the E19 names `ex.webloc`, `ftp.ftploc`, `mail.mailtoloc` came from
  AppleScript `make new internet location file ... with properties {name:"ex"}`:
  the base name was ours, the extension was appended by Finder.
- Steps: the strings `mailto:a@example.com`, `ftp://ftp.example.org/`,
  `http://example.com/x` selected in TextEdit and dragged (`mac-oracle drag`)
  into a Finder window; TextEdit quit without saving.
- Observed: Finder named them `a@example.com.mailtoloc`,
  `ftp.example.org/.ftploc` and `example.com/x.webloc` (Finder names; the "/" is
  ":" on disk): the base name is the URL without the scheme and "//", the
  extension is chosen by scheme (http -> .webloc, ftp -> .ftploc, mailto ->
  .mailtoloc). Content as in E19: XML plist (tab indented), resources drag 128,
  TEXT 256, url 256, FinderInfo ilht/ilft/ilma + MACS, fdFlags 0x0010.
- Fixtures: `E27-dragged-locations/` (data + `._` as fetched with tar).

## E28 - p-links2 952191a2 aliases and location files on 10.6 (S15 part 2)

- Date: 2026-10-11
- Steps: the commit's FSNode + GWMetadata sources exported with `git archive`
  (p-links2 not touched) and linked into a small writer (`mklinks2.m`, run on a
  private Xvfb because FSNAliasIcon needs AppKit): `writeAliasFileForTargetPath`
  for a file and a folder on the Mac, `writeAliasBookmarkForTargetPath` for a
  file, `writeWeblocForURL` for http, ftp, mailto; then `-writeSidecarToFileAtPath:`
  for each. Pushed (tar onto HFS+), Finder asked for class/kind/original
  item/location, `shot`; the http webloc opened by Finder `open` (Safari
  started, URL read, Safari quit, every file it created in ~/Library removed
  again, diff of the ~/Library listing empty).
- Observed aliases: all three resolve (file, folder, and the bookmark writer's
  file, which now also carries `alis` 0). FinderInfo `alis`/`MACS` 0x8400,
  `icns` -16496 with PNG ic07 + ic08: the badge artwork IS shown (page with
  the alias arrow) and Finder adds its own small arrow at the bottom left.
  The folder alias is typed `alis`, not `fdrp`, and shows the page badge, not a
  folder badge: the writer cannot know the foreign target is a folder.
  Tag 18 now without leading slash.
- Observed location files: the sidecars written by
  `-writeSidecarToFileAtPath:` for the three location files hold ONLY entry 2
  (n = 1, fork at offset 38), no entry 9, although the Linux xattr
  user.com.apple.FinderInfo (ilht MACS 0x0010) exists. 10.6 cannot unpack
  them: tar says "copyfile unpack (./web.webloc) failed: File exists" and
  dot_clean "Merging ._ftp.ftploc failed" (cause isolated in E17 e/f: no entry
  9); the files arrive with neither
  FinderInfo nor fork. Then web.webloc and ftp.ftploc are still internet
  location files (by extension) but mail.mailtoloc is a plain "Dokument" with a
  blank icon. With hand-fixed sidecars (entry 9 = the xattr FinderInfo, entry 2
  = the xattr fork, E15 tar layout) all three are internet location files with
  the right URL, ftp and http with hidden extension, the mailto one still showing
  ".mailtoloc". Opening webfix.webloc from Finder opened Safari at
  http://example.com/gw?q=1. ftp/mailto were not opened (would start a network
  mount / Mail setup on the oracle).
- Fixtures: `E28-p-links2/as-written/` (incl. the n = 1 sidecars),
  `E28-p-links2/fixed-sidecars/`, `shot-1.png`, `shot-2.png`, `mklinks2.m`.

## E30 - column view options are global, in com.apple.finder, not in any .DS_Store

- Date: 2026-10-11
- Steps: folder c1 (a.txt, b.txt, pic.jpg, sub/deep) opened and switched to
  column view by AppleScript; the View Options panel (Cmd-J) listed and each
  checkbox clicked by UI scripting (`view-option-click`), the popups set by UI
  scripting; Finder quit after every change (`flush`), then
  `com.apple.finder.plist` and the stores of mi, c1, c1/sub, c1/sub/deep
  diffed against the previous snapshot. The same options set by AppleScript
  `column view options` and read back in a second folder c2.
- Observed: the panel has text size, "Symbole einblenden" (show icons),
  "Symbolvorschau einblenden" (show icon preview, disabled while icons are
  off), "Vorschau einblenden" (show preview column), "Ausrichten nach"
  (arrange by) and "Immer in Spaltendarstellung oeffnen"; there is no "Als
  Standard verwenden" button. No change wrote anything into any .DS_Store (no
  record in the parent, none in the folder's own store, none in the subfolders).
  The first change creates `StandardViewOptions` -> `ColumnViewOptions` in
  com.apple.finder.plist (absent in the baseline), with: ArrangeBy (string,
  four-char code), ColumnShowFolderArrow (bool), ColumnShowIcons (bool),
  ColumnWidth (integer, 205), FontSize (integer, 12), PreviewDisclosureState
  (bool), SharedArrangeBy (string, kipl), ShowIconThumbnails (bool),
  ShowPreview (bool). A value set in c2 is at once the value in c1: the options
  are global.
- Key mapping (two of the names are swapped against their meaning; proven by
  single AppleScript changes, the panel state, screenshots and E31):
  show icons = `ShowPreview`; show preview column = `ColumnShowIcons`; show icon
  preview = `ShowIconThumbnails`; text size = `FontSize` (10..16); preview pane
  disclosure ("Vorschau:" triangle, AppleScript `discloses preview pane`) =
  `PreviewDisclosureState`; column width = `ColumnWidth`.
- ArrangeBy codes: Name `dnam`, Date Modified `modd`, Date Created `ascd`,
  Size `phys`, Kind `kipl`, Label `labl`. SharedArrangeBy stayed `kipl` (no
  UI for it on a local folder).
- Switching a window to column view also sets the global last-used view
  `FXPreferredViewStyle` = `clmv` (E5).
- Fixtures: `E30-column-view/finder-written-first-ColumnViewOptions.plist`
  (the excerpt Finder wrote), `shot-icons-on-preview-off.png`.

## E31 - written ColumnViewOptions are honoured, if typed correctly

- Date: 2026-10-11
- Steps: Finder stopped (`killall -STOP`), StandardViewOptions.ColumnViewOptions
  written with typed values (`setcvo.py`, Foundation on the Mac), Finder killed
  and relaunched by launchd; c1 opened in column view, AppleScript `column view
  options` read, View Options panel and AX column widths read, item order of the
  c1 column read (AXFilename), `shot`. Three rounds: (1) ShowPreview false,
  ColumnShowIcons true, ShowIconThumbnails false, FontSize 14, ColumnWidth 300,
  ArrangeBy phys; (2) ShowPreview true, ArrangeBy kipl, FontSize 10,
  PreviewDisclosureState false, ColumnShowFolderArrow false; (3)
  ShowIconThumbnails true, ColumnShowIcons false, FontSize 16, ColumnWidth 180,
  ArrangeBy dnam. Before that, the same keys written with `defaults write` in
  the old-style plist syntax.
- Observed: (1) icons hidden, preview column shown, text 14, every column 300
  wide, order b.txt, a.txt, sub, pic.jpg (495932 B), big.bin (500000 B), i.e.
  size smallest first, as in icon view (E25). (2) icons shown, text 10, order
  by kind (pic.jpg JPEG-Bild, big.bin, sub Ordner, a.txt, b.txt). (3) text 16,
  columns 180, name order, pic.jpg drawn as a thumbnail, no preview column.
  So FontSize, ColumnWidth, ArrangeBy, ShowPreview, ColumnShowIcons and
  ShowIconThumbnails are honoured on read. ColumnShowFolderArrow false had no
  visible effect (folder arrows still drawn). PreviewDisclosureState was not
  honoured from the file: file 0 read as disclosed, file 1 read as collapsed;
  only changes made inside Finder took effect (not explained).
- `defaults write` with the old plist syntax stores every value as a string;
  Finder then logs `-[NSCFString _getValue:forType:]: unrecognized selector`
  repeatedly and stops answering AppleScript for its windows. The types must be
  integer and boolean as Finder writes them.
- Fixtures: `E30-column-view/setcvo.py`,
  `shot-written-prefs-noicons-preview-w300-size.png`,
  `shot-written-prefs-thumbs-text16-w180.png`, `shot-preview-collapsed.png`.

## E32 - column widths: only Option-drag persists, and globally

- Date: 2026-10-11
- Steps: the resize grip at the bottom right of a column (under its vertical
  scroller, AX geometry read first) dragged by `mac-oracle drag` (+80 px), then
  window closed and reopened in the same Finder session, another folder opened,
  Finder relaunched; the same with `drag --mods alt` (Option held, +60 px).
- Observed: a plain drag widens only that column (205 -> 285); after closing
  and reopening the window, or opening another folder, all columns are 205
  again, and nothing was written anywhere. An Option-drag widens every column
  (205 -> 265), sets `ColumnWidth` = 265 in ColumnViewOptions, applies to
  other folders and survives a Finder relaunch. There is no per-column or
  per-folder width.
- Fixture: none (geometry numbers above).

## E33 - per folder in column view: vstl clmv and bwsp; Workspace's writer is honoured

- Date: 2026-10-11
- Steps: (a) fresh folders c3, c7: "Immer in Spaltendarstellung oeffnen"
  clicked by UI scripting, window closed, Finder quit, stores dumped; c7 and c8
  also switched to column view by AppleScript with bounds set, without the
  click. (b) Reverse: a tool built from this tree's
  Workspace/FileViewer/DSStoreInfo.m (+ DSStore, GWMetadata; run on a private
  Xvfb :613) set viewStyle column, a window frame, sidebar width and toolbar
  and called `-saveToParentStore` for c4 (frame {{40,300},{800,300}}, sidebar
  260, toolbar on) and c5 ({{100,200},{700,250}}, sidebar 180, toolbar off);
  the records were pushed with the global last-used view set to icon; Finder
  read current view, bounds, toolbar, sidebar width; `shot`.
- Observed (a): the checkbox writes `vstl` type `clmv` into the PARENT store
  under the folder's name, nothing else; AppleScript `current view` writes no
  vstl (as E5). Window geometry, toolbar and sidebar width in column view are
  the same `bwsp` record in the parent store as in the other views. Once (c1,
  trigger not reproduced in c7/c8) Finder also wrote a legacy `fwi0` blob
  023f000a02d803f6636c6d7600010000 (top 575, left 10, bottom 728, right 1014,
  view clmv, then 0001 0000) next to vstl clmv.
- Observed (b): both folders open in column view although the global view is
  icon; c4 bounds 31,306,646,537 = WindowBounds {{31, 231}, {615, 253}} by the
  E7 formula, toolbar on, sidebar width 260; c5 toolbar off, bounds
  77,422,615,614 = {{77, 154}, {538, 214}} (sidebar width reads 0 while the
  toolbar is hidden, E8). All honoured.
- Notes on the writer: DSStoreInfo divided the frame by GSScaleFactor 1.3 of
  this host (pixels -> points, intended) and also wrote a default `icvp` for
  these column view folders although no icon option was changed; Finder 10.6
  never writes an icvp for a column view folder (harmless, but not what Finder
  does).
- Fixtures: `E30-column-view/workspace-written-c4-c5.parent.DS_Store`,
  `parent-after-all.DS_Store` (Finder-written c1 bwsp/fwi0/vstl, c3 vstl,
  c6/c7/c8 bwsp), `cvwriter.m`, `shot-workspace-c4-c5.png` (a Bluetooth setup
  dialog of the oracle covers part of it).

## E34 - selected path and scroll positions in column view are window restore state only

- Date: 2026-10-11
- Steps: c1 opened in column view, window target set to c1/sub/deep and d.txt
  selected; window closed and c1 reopened; Finder relaunched with the window
  open; com.apple.finder `BrowserWindowState` read. Reverse: with no window
  open and Finder stopped, a BrowserWindowState with one entry (TargetURL
  c1/sub, ViewStyle Column, WindowBounds {{100, 100}, {800, 300}}, SidebarWidth
  150, `setbws.py`) written; Finder killed and relaunched.
- Observed: no per-folder record of the selected path or the column scroll
  positions exists. Reopening c1 shows c1 again, not the deeper path. Only the
  windows open when Finder quits are stored, globally, in
  `BrowserWindowState` (array of dicts: TargetURL, TargetPath = every folder
  from the Desktop down to the target, ViewStyle `Column`, WindowBounds,
  ShowToolbar, ShowSidebar, ShowStatusBar, ShowPathbar, SidebarWidth,
  BrowserViewState with ColumnViewInnerScrollOrigins = one "{x, y}" string per
  column and ColumnViewOuterScrollOrigin), next to BrowserWindowRestoreAttempted
  0. The written state was honoured at relaunch: one window on c1/sub, column
  view, bounds 100,390,900,668 (E7 formula), sidebar width 150.
- Fixtures: `E30-column-view/finder-written-BrowserWindowState-column.plist`,
  `setbws.py`.
