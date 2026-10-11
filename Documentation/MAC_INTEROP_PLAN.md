# Mac interoperability plan (Workspace <-> Finder 10.6.8)

Source of truth for the gaps: `Documentation/FEATURES.md` (feature table with
status). Background: `Documentation/INTEROPERABILITY.md`, `INTEROP_DSSTORE.md`,
`INTEROP_TESTING.md`, `INTEROP_VNC_TESTING.md`, `Workspace/FileViewer/Differences.md`.

Oracle: Mac mini `Users-Mac-mini.local`, Mac OS X 10.6.8 (10K549), ssh
`user`/`user` (legacy ssh-rsa flags, see `Tools/mac-metadata-interop/`),
VNC port 5900 password `1234`. Principle (unchanged): the Mac is always right.

## What we take from Renaissance

| Renaissance | Here |
|---|---|
| Scout owns one guest slot exclusively, writes numbered evidence | ONE Scout owns the Mac mini; nobody else touches it (Finder state is global, parallel drivers corrupt each other's observations) |
| Assertions: one behaviour, stable id, source tag `[O:]` `[F:]` `[G:]` | `Documentation/interop/assertions.md`, ids `MI-<area>-<n>`, tags `[F:10.6 <file>]` (bytes Finder wrote), `[O:<date> eN]` (observed), `[S:]` spec, `[G:]` guess |
| Evidence file `spec/behaviors.md` | `Documentation/interop/evidence.md` + fixtures in `Tests/GWMetadata/interop/fixtures/finder106/` |
| Porter: one feature, spec -> test -> model -> UI on screen, same day | Porter per FEATURES.md row group, red/green ObjectTesting, DriveUI check in isolated uitest slot |
| Referee: compares our output with the original's, reports, never fixes | Referee runs the round-trip matrix (forward + reverse) and reports diffs |
| Toolsmith: when a step was done by hand twice | Builds the Mac oracle tool first (below) |
| "Speed over ceremony"; `[G:]` for cheap guesses, source only structural things | Byte formats and coordinate conventions MUST be `[F:]`-sourced; UI niceties may be `[G:]` |
| Recipes instead of hand-driving the GUI | Drive Finder via `osascript` (scriptable in 10.6), VNC only for visual confirmation |

Key insight: 10.6 Finder is AppleScript-scriptable for nearly all view
options (`icon view options`: icon size, text size, label position,
arrangement, shows item info, shows icon preview, background color/picture;
`list view options`: sort column, text size, calculates folder sizes, uses
relative dates, per-column visible/width/index; window `toolbar visible`,
`statusbar visible`, `bounds`, `current view`, `sidebar width`; item
`comment`, `label index`, `locked`, `extension hidden`). So the Scout can
make Finder WRITE every record deterministically and READ back what it
honoured, without clicking.

## Phase 0 - Decisions (user)

1. Scope: Finder metadata only (FEATURES.md), or also "Mac interop" beyond
   it? Candidates: Finder aliases (`kIsAlias` + alias resource), `.webloc` /
   `.inetloc` / `.fileloc`, `__MACOSX` in zips (GWMetaArchive), SMB/AFP
   browsing of the Mac's shares + Bonjour `_afpovertcp`, quarantine xattr.
   Recommendation: FEATURES.md first, aliases + webloc + quarantine as wave 6.
2. 10.6 view/window limit (open item in `INTEROP_DSSTORE.md`). Hypothesis to
   test FIRST (Scout E1): 10.6 only stores per-folder view style when "Always
   open in <view>" is ticked (`icvp`/`lsvp` with that flag) and only in
   toolbar-hidden (spatial) windows; the earlier "ignored" finding came from
   browser mode. Recommendation: decide (a)/(b)/(c) after E1, not before.
3. Agent definitions: add `.claude/agents/ws-scout.md`, `ws-porter.md`,
   `ws-referee.md` in gershwin-workspace (modelled on ren-*), or reuse
   general-purpose with prompts. Recommendation: add the three files.

## Phase 1 - Toolsmith (1 agent, sonnet)

`Tools/mac-oracle/mac-oracle` (shell, reuses `verify-*.sh` ssh setup):

- `run '<applescript>'` / `sh '<cmd>'` on the Mac
- `push <localdir> <name>` / `pull <name> <localdir>` (keeps xattrs: `ditto`
  / `xattr -l` dump, `._` via `ditto -c -k --sequesterRsrc`)
- `finder-set <folder> <option> <value>` (osascript recipe), `finder-get`
- `dump <name>` -> `.DS_Store` + all xattrs per item, decoded locally with our
  own DSStore dumper (`DSStore/` tool) into a stable text form for diffing
- `shot <folder>` -> `screencapture` of the Finder window, pulled back
- `reset` -> close Finder windows, restore the known Finder defaults baseline
- recipes in `Tools/mac-oracle/recipes/*.recipe` (one command per line,
  Renaissance `ren-oracle` style)

Done when: a recipe sets icon size 96 on a fresh folder, the pulled
`.DS_Store` dumps `icvp` with 96, and a Gershwin-written folder pushed back
reads 96 via `finder-get`.

## Phase 2 - Scout (1 agent, sonnet, exclusive Mac owner)

For every FEATURES.md row not **Implemented**: set it in Finder, record which
record/bytes changed (before/after dump diff), store the fixture, write the
evidence entry and the assertion. Also E1 (decision 2) and the unknown keys
(preview pane, toolbar/statusbar in `bwsp`). Output is consumed by Porters;
the Scout never edits Workspace code. Batches answered in order of the waves.

## Phase 3 - Porters (parallel, split by OWNED files to avoid merge conflicts)

Settings are applied in `GWViewer.m`, `GWSpatialViewer.m` and `DSStoreInfo.m`,
which every view feature would touch. So view Porters only add capabilities
(API + rendering + tests) to their own view class; ONE Integrator later wires
`.DS_Store` records to those APIs.

Wave A (now, parallel with the Toolsmith; no Mac needed, sources are
existing fixtures, `DSStore/fields.md` and public specs):

| Agent | Owns (only these may be edited) | Rows |
|---|---|---|
| P-icons | `FSNode/FSNIconsView.*`, `FSNode/FSNIcon.*` | text size, show item info, show icon preview, arrange by (+ grouping), snap to grid, scroll position API |
| P-list | `FSNode/FSNListView.*` | sort direction, column visibility + order, relative dates, calculate all sizes, text/icon size API |
| P-inspector | `Inspector/` (incl. its Resources) | hidden extension, name locked, stationery, invisible, comment edit, custom icon set/clear, type/creator UI (uses existing `GSFileMetadata` API; new API needs are reported, not added) |
| P-preserve | `GWMetadata/GSAppleDouble.*`, `Operation/` | unknown xattrs kept on copy/move/duplicate, AppleDouble rewrite keeps unknown entries, quarantine round-trip |

Wave B (after Toolsmith + Scout evidence and wave A):

| Agent | Owns | Rows |
|---|---|---|
| Integrator | `Workspace/FileViewer/` (`DSStoreInfo`, `GWViewer`, `GWSpatialViewer`, `GWVolumeCache`), `DSStore/` | wire every wave A API to its record; window chrome (toolbar/statusbar/pathbar/sidebar); background image write; GSFileMetadata additions requested by P-inspector |
| W6 Porter | new files | aliases, webloc/inetloc, quarantine UI |

Rules for every Porter:
- Own worktree: `git -C /Developer/Library/Sources/gershwin-workspace worktree
  add /Developer/Library/Sources/gw-wt/<agent> -b mi/<agent> dev`; build and
  test there; never touch the main checkout. Do NOT commit (user rule):
  leave changes uncommitted; the coordinator integrates them.
- Edit only owned files. Needed outside changes (GNUmakefile lines,
  strings, other classes) go in the report as exact hunks.
- Assertions in `Documentation/interop/assertions-<agent>.md` (own file).
  Do not edit FEATURES.md; report the new status per row.
- Red/green ObjectTesting in a test dir of its own; DriveUI checks only in a
  free isolated uitest slot (gershwin-wm-headless-testing skill); never :0,
  never install.
- Clean build, no warnings. BSD-2-Clause OR GPL header (project is GPL) on
  new files. No em dashes. Comments say why, not what.

## Phase 4 - Referee (1 agent, sonnet; uses the Mac only via the Scout's slot when the Scout is idle)

Round-trip matrix per feature: Finder writes -> Workspace shows the same
(DriveUI read of view state); Workspace writes -> Finder reports the same
(`finder-get`) and looks the same (`shot`); plus cooperative-editor check
(Finder-only records survive a Workspace save byte-for-byte). Results table
appended to `INTEROP_DSSTORE.md` / FEATURES.md. Reports, never fixes.

## Coordination rules

- Before spawning: ListAgents + message peers (done 2026-10-11: SUPERAGENT
  not in gershwin-workspace; "Continue previous session" did not receive the message (approval
  expired); re-check before spawning).
- Foreign untracked files in gershwin-workspace (`CloudContextMenu/`,
  `Tests/CloudContextMenu/`) and the SMB WIP in `TODO.md` are not ours.
- One `gnustep-tests` run at a time in the shared checkout; Porters test in
  their worktrees.
- Install to SYSTEM only, user tests before any commit/push.

## Scout queue (filled from Porter reports)

- S1 [ANSWERED E15] (P-preserve OPEN-1): real 10.6 `._` fixtures: FinderInfo only, one
  xattr, many xattrs, resource fork + xattrs (via `ditto -c --sequesterRsrc`
  / copy to a FAT/SMB volume). Padding to 4096? debug_tag? Commit them under
  `Tests/GWMetadata/interop/fixtures/finder106/` (the old fixtures are
  generated, not in git).
- S2 [ANSWERED E16] (OPEN-2): 10.6 `cp -p`, `ditto`, Finder copy: is
  `com.apple.quarantine` copied verbatim, changed or dropped?
- S3 [ANSWERED E15] (OPEN-4): are ATTR header/record flags ever non-zero on 10.6?
- S4 [ANSWERED E17] (OPEN-5): FinderInfo xattr of length != 32 in a sidecar: entry 9 or ATTR?
- S5 [ANSWERED E20] (P-list): first-click sort direction per column; lsvp `ascending`
  semantics for dates/size; sort column when it gets hidden.
- S6 [ANSWERED E21] (P-list): can Name be dragged off the left edge?
- S7 [ANSWERED E22] (P-list): relative date wording/format and older dates; Date Last
  Opened source and empty display; empty Version/Comments display.
- S8 [ANSWERED E23 (partly)] (P-list): folder/package size display without calculate-all-sizes;
  logical vs physical, hard links, mounts; display while calculating; live
  re-sort while sizes arrive.
- S9 [ANSWERED E24] (P-list): Label column sort order and content; row heights for list
  icon sizes 16/32 and text sizes 10-16.
- S10 [ANSWERED E23 (partly)] (P-icons): item info wording (bytes/KB/MB, base 10?), for apps,
  packages, volumes; folder count includes hidden files?
- S11 [ANSWERED E25] (P-icons): arrange by label/kind/size/date order (folders first?
  newest/largest first?); snap-to-grid collision on drop.
- S12 [ANSWERED E11, E26] (P-icons): icvp scrollPositionX/Y origin + units; show icon preview
  off = generic icon? default showIconPreview without icvp.
- S13 [ANSWERED E18] (P-inspector): hide extension = fdFlags 0x0010 on 10.6? (dump after
  Finder hides one). PNG-in-icns resource fork custom icon shown by 10.6?
  Locked also sets kNameLocked; kNameLocked honoured on rename? Folder
  custom icon layout (Icon\r + fork + 0x0400 on folder).

Toolsmith done 2026-10-11 (gw-wt/toolsmith): mac-oracle + evidence E1-E9.
Key facts: view records live in the PARENT store under the folder name,
"." ignored by 10.6 (E1/E2); vstl only with "always open in" (E5); icvp
needs full key set (E6); bwsp bottom-left origin (E7). Fixtures dir is
gitignored (Tests/GWMetadata/interop/.gitignore "fixtures/") -> add an
exception for fixtures/finder106/ at integration.
- D3: sudo round trip of the Locked helper untested (classifier blocked
  the agent): user runs it, or authorizes a narrow test.

- S14 [ANSWERED E19, E28] (P-links): does 10.6 Finder resolve our alias (file + `._` or
  xattrs)? Fixtures: Finder alias to file on another volume, to a folder;
  'alis' id/payload, data fork empty?; classic .webloc with only 'url '
  resource (id 256?); does Finder open our XML .webloc?

Scout done 2026-10-11 (gw-wt/toolsmith, evidence E10-E28): A1 lsvp honoured
and wins over LSVO/lsvo/lsvt (E10, E21); A2 scrollPositionX/Y top-left,
points, in icvp and lsvp (E11); A3 icvp backgroundType 2 +
backgroundImageAlias, CNID-less alias needs tag 2 (E12); A4 bwsp ShowToolbar,
SidebarWidth per folder, bar flags global (E13); A5 volume root and home use
"." in their own store, read-only places persist nothing (E14). S15 (E27, E28).
DSStore 'shor' decode bug reported (E10).


- D1 DECIDED 2026-10-11: sidecar fallback for E2BIG/ENOSPC only (P-preserve implements). Was: ext4 caps one xattr at about a block, so a large
  ResourceFork xattr fails on copy. Fail hard (current) or sidecar
  fallback for E2BIG/ENOSPC only (what GSFileMetadata already does)?
- D2 DECIDED 2026-10-11: privileged helper on Linux (P-inspector implements). Was: "Locked" = immutable flag; on Linux needs privilege,
  so it errors for normal users. Options: disable checkbox when not
  permitted / remove write bits / privileged helper.

## Integrator inbox (outside hunks from Porters)

- P-preserve: GSFileMetadata `-writeSidecarToFileAtPath:error:` must merge
  via `+[GSAppleDouble appleDoubleDataByUpdatingSidecar:withContent:managedXattrNames:]`
  (keeps unknown entries). libOperation now links libGSMetadata: install both.
- P-list: FSNode Localizable.strings: "Today", "Yesterday", "%@ at %@",
  "Date Created", "Date Last Opened", "Label", "Version", "Comments".
  Metadata provider: implement `-commentForPath:` / `-labelNameForPath:`.
  FSNTextCell `-setFont:` must clear fittedTitle (stale cache).
  DSStoreInfo `sortColumnNameForInfoType:` -> map via
  `+columnIdForTableIdentifier:`; apply order: visibility, order, sort,
  widths, text size, icon size, relative dates, calculate sizes; write back
  on FSNListViewOptionsDidChangeNotification.
- P-icons: provider `-labelIndexForPath:` (GSFileMetadata labelNumber);
  strings "1 item", "%lu items", "Zero bytes", "1 byte", "%lu bytes";
  arrangeBy "grid" -> setSnapsToGrid:YES + arrangement None, others map to
  FSNIconsArrangement; clamp text size via +clampedLabelTextSize:.
  Check: t_FSNAliasCreate 3 failures - pre-existing on dev?
  Pre-existing: name-only icon rows overlap labels in offscreen render.
- P-inspector: fix docs: FEATURES.md hidden-extension bit is 0x0010 not
  0x0400; INTEROPERABILITY.md section 3 flag bit numbers are wrong
  (GSFileMetadata.h matches Finder.h). GSFileMetadata: remove comment xattr
  when empty, remove ResourceFork xattr after clearCustomIcon, move
  +resourceForkWithICNS: into setCustomIconData: (raw icns is unreadable
  for Finder), add extensionHidden property. Apply nameLocked in rename;
  cmmt in .DS_Store; views must hide extensions when the bit is set.

## Wave B (started 2026-10-11, wave A bundled in gw-wt/patches/wave-a.patch)

| Agent | Model | Owns |
|---|---|---|
| I-viewers | opus | Workspace/FileViewer/, DSStore/ |
| I-metadata | sonnet | GSFileMetadata, GWMetadataProvider, FSNMetadataProvider.h |
| I-fsnode | sonnet | FSNode/ except FSNMetadataProvider.h and FSNAlias* |
| P-links | sonnet | FSNAlias*, new webloc/inetloc/fileloc files |
| P-inspector (cont.) | sonnet | Inspector/, privileged helper action for Locked |
| verify | haiku | read-only build + suites of wave A |
| Toolsmith | sonnet | Tools/mac-oracle, the Mac |
- P-inspector (Locked helper): Workspace/main.m: `#include "FinderInfoLocker.h"`
  and at the top of main(), before killOtherInstances:
  `if (argc >= 3 && strcmp(argv[1], FinderInfoLockHelperFlag) == 0) return FinderInfoLockHelperMain(argv[2]);`
  Re-run ./configure after GNUmakefile.in change. Drop Inspector's
  FinderInfoIconBuilder +resourceForkWithICNS: and the redundant
  -setResourceFork: at FinderInfoModel.m:453-454 (I-metadata's
  -setCustomIconData: now writes the fork). Sudo round trip UNTESTED.
- P-links: FSNode/GNUmakefile(+.in?) add FSNMacFork/FSNAliasFile/
  FSNLocationFile; Workspace.m openFile: (~2060) use
  +[FSNAlias aliasWithContentsOfFile:]; ~2422 use FSNLocationFile for
  webloc/inetloc/fileloc/url, cannot-open alert when URL nil; URL drop on
  folder -> writeWeblocForURL:title:inDirectory:. PENDING: replace
  FSNMacFork with GSFileMetadata API (I-metadata adds generic resource
  lookup/writer); alias writer should use xattrs when supported (same
  policy as GSFileMetadata), sidecar otherwise.
- Scout group A (E10-E14) answered and forwarded to I-viewers: lsvp
  honoured; scrollPosition offsets; background = AliasRecord v2 with HFS
  path; bwsp ShowToolbar/SidebarWidth per folder, other bars global;
  root + home use "." in own store; RO folders persist nothing on 10.6.
- Merged tree: gw-wt/merged (all but I-viewers), 0 warnings, all suites
  green. Follow-ups running: old alias compat, alias tools, URL drop.
