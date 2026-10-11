# Assertions: Look Inside (space bar preview)

Owner: P-lookinside. Code: `Workspace/LookInside/`. Tests:
`Tests/Workspace/t_GWLookInsideKeys.m`, `t_GWLookInsideGeometry.m`,
`t_GWLookInsidePreviewKind.m`, `t_GWLookInsideInfo.m`, `t_GWLookInsideToggle.m`
(ids below are the test names).

Behaviour follows the 10.6 Finder's space bar preview; wording, artwork and
key choices for things the Finder does differently are our own.

Tags: [S:x] documented Finder behaviour, [G:reason] guess or our own design,
[O:date eN] observed on the oracle. Nothing here was observed on the Mac in
this round (see OPEN).

## Opening and closing

- MI-LI-1 Space closes the open panel [S:Finder 10.6]
- MI-LI-2 Escape closes the panel, also from the overview [S:Finder 10.6]
- MI-LI-19 Option-Space opens straight into full screen; Space alone opens the panel [S:Finder 10.6]
- (no test id) Cmd-Y (File > Look Inside) toggles the panel for Workspace's current selection [S:Finder 10.6 Cmd-Y]
- (t_GWLookInsideToggle, no id) Space with nothing selected does nothing; a second Space closes whatever is open [S:Finder 10.6]
- (no test id) The panel grows from the item's icon and shrinks back into it through the WindowManager's birth and close animations; no animation into full screen [G:Finder zooms from the icon]

## Moving through items

- MI-LI-3 With one item, the arrow keys move the folder window's selection [S:Finder 10.6]
- MI-LI-20 The open panel follows the selection (arrow keys, clicks in any folder window); an emptied selection keeps the last preview [S:Finder 10.6; emptied selection G]
- MI-LI-24 A click on empty space in a folder window does not make the panel show that folder; the last item stays [G: Finder 10.6 shows the last item or nothing; the same rule as MI-LI-20]
- MI-LI-25 Folder windows and the Desktop handle the space bar through one code path (`handleSpaceKeyWithCommand:...`), so Option-Space works on the Desktop too [G]
- MI-LI-4 With several items, the arrow keys step through them [S:Finder 10.6]
- MI-LI-8 Stepping wraps around at both ends [G: no dead end]
- MI-LI-5 Command-Return shows the overview of several items; Return in it shows the highlighted item; a click on an item shows it [G: own key; Finder has an index sheet]
- MI-LI-10 The overview is a grid read left to right, top row first, cells no larger than 256 points, clicks in the gaps pick nothing [G]

## Panel

- MI-LI-6 Option-Space while open switches full screen (through _NET_WM_STATE_FULLSCREEN, so the WindowManager hides menu bar and Dock) [G: own key]
- MI-LI-7 Command-O and Command-Down open the item with its application, as a double-click would, and close the panel [S:Finder 10.6 has an open-with button]
- MI-LI-9 The panel comes back at the size it had when it was last closed (not a full-screen size), centered, cut to the screen and never below 420 x 300 [S:Finder 10.6 remembers the size]
- (no test id) With several items the strip shows previous/next, "n of m" and All Items; the right side always has Full Screen and "Open with <application>" [G: own layout]

## Previews

- MI-LI-11 A missing item has no preview [G]
- MI-LI-12 A folder gets icon, name, kind, item count, size (added up in the background) and date; an application or other package is one item [S:Finder 10.6]
- MI-LI-13 Images NSImage can decode are shown at their own size, scaled down to fit [S:Finder 10.6]
- MI-LI-14 RTF and RTFD are shown as rich text [S:Finder 10.6]
- MI-LI-15 The first 20 pages of a PDF are shown, rendered by poppler's pdftoppm; without it a PDF gets icon and facts [G: this AppKit reads no PDF]
- MI-LI-16 Audio gets icon, facts and a Play button when NSSound can play the format; video gets icon, facts, a poster frame (first representative frame made by ffmpeg when installed, never required) and a Play button that opens the file in its application [G: no video playback in Workspace]
- MI-LI-17 Plain text is recognised by its bytes (UTF-8, no NUL), whatever its extension; the first 512 KB are shown [G]
- MI-LI-18 Everything else, empty files included, gets a large icon with name, kind, size and date [S:Finder 10.6]
- MI-LI-21 The facts: name, kind (Workspace's kind), size as everywhere in Workspace, modification date [S:Finder 10.6]
- MI-LI-22 A folder counts the items a folder window shows (no dot files), singular for one [G]

## Preview column of the column view

- MI-LI-23 The preview column gets a picture of the content for images, text, rich text and PDF from `GWLookInsideColumnPreviewProvider`; folders, audio, video and everything else keep the column's own large icon [G]
