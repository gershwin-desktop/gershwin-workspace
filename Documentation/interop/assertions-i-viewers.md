# Assertions: folder view and window records (I-viewers)

Code: `Workspace/FileViewer/` (DSStoreInfo, GWFolderViewOptions,
GWViewSettingsManager, GWVolumeCache, GWVolumeID, GWViewerBase, GWViewer,
GWSpatialViewer) and `DSStore/`. Tests: `Tests/FinderViewOptions/`
(`t_FinderRecords.m` headless, `t_FolderViewOptions.m` needs a display) and
`Tests/FileViewer/t_GWVolumeID.m`. The ids are the test names.

Tags: [F:Ex] bytes Finder 10.6.8 wrote (fixtures in
`Tests/GWMetadata/interop/fixtures/finder106/`),
[O:Ex] observed on the Mac (Scout evidence `Documentation/interop/evidence.md`),
[S:] spec, [G:] guess.

## Store parsing

- MI-IV-1 A `shor` record is four bytes on disk and is read as such [F:E8 m_lcv lsvt]
- MI-IV-2 The record after a `shor` is not lost (it was: E8's `m_lcw lsvp` was missing from the Scout's own dump) [F:E8 m_lcw]
- MI-IV-3 A record longer than 64 KiB survives a save and load [G: whether Finder takes a node larger than a page is OPEN]
- MI-IV-4 The last record of a level is not lost when it would split the level

## Where a folder's records live

- MI-IV-5 A folder's view and window records are read from its parent's store, under the folder's name [O:E1]
- MI-IV-9 They win over "." in the folder's own store [O:E2]
- MI-IV-79 The root and the home folder keep them as "." in their own store [O:E14]
- MI-IV-80 So does the root of any other volume (a mount point) [O:E14]
- MI-IV-81 Every other folder in its parent's store
- MI-IV-30 Writing goes to the parent's store under the folder's name
- MI-IV-43..46 The settings manager writes both the parent's record and "." (newer Finders read ".") and reads them back
- (no test id) A parent that cannot be written: Finder persists nothing [O:E14]; Workspace keeps the record in its volume cache, never when the parent store was written

## Window (bwsp)

- MI-IV-6 WindowBounds is the whole window, origin bottom left, y up, height including a 22 point title bar [O:E7]
- MI-IV-34 Written back in that convention
- MI-IV-7 ShowToolbar, ShowStatusBar, ShowPathbar, ShowSidebar, SidebarWidth are read [F:E1]
- MI-IV-8 A window without toolbar and sidebar [F:E1 eB]
- MI-IV-35 bwsp is written with every key Finder writes [F:E1]
- (no test id) Only SidebarWidth (and WindowBounds) is applied per folder; ShowPathbar, ShowSidebar, ShowStatusBar are Finder's global settings, written as a snapshot [O:E13]. Workspace keeps path bar and status bar visibility in the global defaults `ShowPathbar` / `ShowStatusBar` (Finder's names) [G: names]
- (no test id) ShowToolbar is kept as stored; Workspace has no toolbar [G: mapping a spatial window to ShowToolbar 0 is a decision for the user]

## Icon view (icvp)

- MI-IV-10..16 textSize, labelOnBottom, arrangeBy grid, showItemInfo, showIconPreview, background colour [F:E8]
- MI-IV-31 Every icvp written carries textSize, gridSpacing, labelOnBottom, showItemInfo, showIconPreview, arrangeBy and the three background colours [O:E6]
- MI-IV-32 viewOptionsVersion is 0 [O:E6]
- MI-IV-33 Sizes are reals [F:E8]
- MI-IV-36 No vstl unless a view was chosen for the folder [O:E5]; the viewers write one only after the user switched the view type in that window or when the folder had one
- MI-IV-82 scrollPositionX/Y are reals, points from the top left of the content [O:E11]
- MI-IV-83 A picture is backgroundType 2 with a classic alias record in backgroundImageAlias [O:E12]
- MI-IV-84 Both are read back
- MI-IV-85 The alias carries the HFS path "<volume>:<path>"; the volume is "Macintosh HD" for the root file system and the mount point's name otherwise [G: what the volume is called on the Mac]
- MI-IV-86 It is a version 2 alias record (FSNAlias) [O:E12]
- MI-IV-47..50 arrangeBy grid is snap to grid without an arrangement, none is neither; name, kind, dateModified, dateCreated, size, label are arrangements [F:E8 grid/none; G: the other values, OPEN S11]
- MI-IV-51..56 Each icvp option reaches a real FSNIconsView
- MI-IV-57 Text sizes are clamped to Finder's 10..16
- MI-IV-58 The scroll position is not re-applied when a window only comes to the front
- MI-IV-59 It is applied when the folder is opened
- MI-IV-60..61 The view's options go back into icvp
- MI-IV-62 An arrangeBy the view has no arrangement for (a newer Finder's) is kept while the user does not touch the arrangement
- MI-IV-63 and replaced once the user does
- (no test id) gridSpacing is read and written but not applied: FSNIconsView has no grid spacing API

## List view (lsvp, lsvo)

- MI-IV-17..24 sortColumn, direction, column order, widths, visibility, textSize, iconSize, calculateAllSizes, useRelativeDates [F:E8]
- MI-IV-18 The direction is the sort column's own `ascending` in the columns dictionary [F:E8; semantics OPEN S5]
- MI-IV-25 Two visible columns with one index keep Finder's column order [F:E8 m_lci; G: which one Finder shows first, OPEN]
- MI-IV-26 A column width set by script is an lsvp [F:E8 m_lcw, contrary to the E8 text]
- MI-IV-27..29 The legacy lsvo is read when there is no lsvp: "lsv1", 3 unknown bytes, sort column 4CC, column count, then per column 4CC, width, 1 ascending / 2 descending, visible [F:E8 m_lcv, decoded against lsvp of the same settings; O:E10 lsvp wins]
- MI-IV-38..42 Writing keeps Finder's dictionary of nine columns, puts the direction into the sort column, keeps keys Workspace does not own and leaves other folders' records and the legacy lsvo/LSVO/lsvt alone [O:E10]
- MI-IV-64..73 Each lsvp option reaches a real FSNListView, in the order visibility, order, sort, widths, text size, icon size, relative dates, calculate sizes
- MI-IV-68 Applying posts no user-change notification
- MI-IV-74..77 The list's options go back into lsvp; a hidden column keeps its index, the other columns their own direction
- MI-IV-78 A width alone does not create list options
- (no test id) Written when FSNListViewOptionsDidChangeNotification arrives; on close only the widths of a folder that already has lsvp are refreshed
- (no test id) lsvp scrollPositionX/Y [O:E11] are kept as stored: the list view has no scroll position API

## Removable media (volume cache)

- MI-IV-87 A volume's cache file is named after the file system's identity (Linux /dev/disk/by-uuid, FreeBSD /dev/ufsid, /dev/gptid), which stays the same when the medium is ejected and inserted again
- MI-IV-88 Something that is not a device has none
- MI-IV-89 The root volume is named after its UUID
- (no test id) A cache file written under the old device id is renamed once when the cache is first used [G: no headless test, it would rename the user's real cache]
- (no test id) OpenBSD has no such directory: DUIDs are not looked up, f_fsid stays the id there (OPEN)
