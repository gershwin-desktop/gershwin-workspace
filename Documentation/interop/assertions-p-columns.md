# Assertions: column view options (P-columns)

Tests: `Tests/FSNodeBrowser/t_FSNBrowserLayout.m`, `t_FSNColumnViewOptions.m`,
`t_FSNBrowserViewOptions.m`.
Tags: [O:] observed on the 10.6 oracle (evidence.md), [S:] Finder's options
panel / public behaviour, [G:] guess, not measured.

## Where the options live
- MI-CLM-80..82 ArrangeBy is kept as Finder's code: dnam, kipl, modd, ascd, phys, labl; None (Workspace only) has none [O:2026-10-11 E30]
- MI-CLM-83 icons, icon preview and the preview column are on by default [O:2026-10-11 E30]
- MI-CLM-84 arranged by name by default [O:2026-10-11 E30]
- MI-CLM-85 columns are 205 points wide by default [O:2026-10-11 E30]
- MI-CLM-86 without a text size of its own the NSFontSize default is used, else 12 [O:2026-10-11 E30 for 12; G: NSFontSize kept from the old browser]
- MI-CLM-87..92 the options are global, one key each in the application's defaults, written typed (integer, bool, code string) and only when changed [O:2026-10-11 E30, E31]
- MI-CLM-93..96 every change is posted once (FSNColumnViewOptionsDidChangeNotification); a change in the defaults from outside is taken over [O:2026-10-11 E30: a value set in one folder is at once the value in another]
- MI-CLM-60..62 an open browser follows the global options at once [O:2026-10-11 E30]

## Text size
- MI-CLM-35 sizes are held to 10..16 [O:2026-10-11 E30]
- MI-CLM-36..39 the names are drawn at the size, rows grow with it, the folder stays shown [S]

## Show icons, show icon preview
- MI-CLM-40, 44..46 without icons the rows show the names alone, in columns opened later too [O:2026-10-11 E31]
- MI-CLM-41..43 with icon preview an image shows its own picture, without it the icon of its type [O:2026-10-11 E31 (pic.jpg drawn as a thumbnail); same rule as the icon view, E26]
- Finder greys "show icon preview" out while icons are off [O:2026-10-11 E30]; the option has no effect then (UI of the options panel, not FSNode)

## Arrange by
- MI-CLM-47 by name: A to Z, folders not first [O:2026-10-11 E25, E31 round 3]
- MI-CLM-48 by size: folders first, then smallest first [O:2026-10-11 E31 round 1]
- MI-CLM-49 by date modified: newest first [O:2026-10-11 E25; column view G]
- MI-CLM-50 by label: unlabelled first, then by label name [O:2026-10-11 E25; column view G]
- MI-CLM-51 by kind: alphabetical by the kind string [O:2026-10-11 E31 round 2]
- MI-CLM-52 an item that appears takes its place in the arrangement [S]
- MI-CLM-53 None: the folder's own sort order (Workspace only; Finder's column view has no None) [O:2026-10-11 E30]

## Column widths
- MI-CLM-4..7, 9..13 columns lie side by side one point apart, keep their width, the one at the right edge is cut off, not squeezed [G: layout]
- MI-CLM-14..17 the last loaded column is shown whole at the right with as many before it as fit [G]
- MI-CLM-18..20 widths are whole points, never below 100 [G: Finder's minimum not measured]
- MI-CLM-54, 63, 75 a column is 205 points wide and empty columns fill the view [O:2026-10-11 E30, E32]
- MI-CLM-55..59 one column can be wider than the others; setting the width of all columns replaces single widths [O:2026-10-11 E32]
- MI-CLM-60 an Option-drag sets the global width, every column takes it [O:2026-10-11 E32]
- a plain drag of a column's grip widens only that column, for this window only, nothing is kept [O:2026-10-11 E32] (on screen, see report; not in a test)
- the grip sits under the column's vertical scroller [O:2026-10-11 E32]
- MI-CLM-76 the deepest column is scrolled into view whole [G]

## Preview column
- MI-CLM-64 a selected file is previewed in the column after it [S]
- MI-CLM-65 the picture is the provider's (Look Inside) view [S]
- MI-CLM-66 without one, the file's large icon [G]
- MI-CLM-67, 68 under the picture: Name, Kind, Size, Created, Modified [G: Finder 10.6 also shows Last opened and a More Info button, not measured]
- MI-CLM-69 a selected folder shows its contents, not a preview [S]
- MI-CLM-70..72 the option removes and brings back the preview at once [O:2026-10-11 E31]
- MI-CLM-73 several selected files have no preview [G]
- PreviewDisclosureState (the "Preview:" disclosure triangle) is not implemented [O:2026-10-11 E30, E31: not honoured from the file either]
