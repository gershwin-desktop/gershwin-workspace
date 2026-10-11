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
- Not answered: what a user's drag of a column border or header writes
  (System Events cannot drag in 10.6); the read side above is unaffected.
- Fixtures: `E10-list-records.parent.DS_Store` (la1..la4 inputs, ua2 written
  by the UI click), `E10-applescript-columns.parent.DS_Store` (w1..w6 of c),
  `E10-input-*.plist|hex` (inputs), `E10-la2-lsvp-honoured.png`,
  `E10-la4-lsvp-wins.png`, `E10-w4-applescript-visible-noop.png`.
