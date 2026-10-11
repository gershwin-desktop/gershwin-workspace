# Assertions: FSNode model (F-node2)

Owner: F-node2. Code: `FSNode/FSNode.{h,m}`, `FSNode/FSNTextCell.{h,m}`.
Tests: `Tests/FSNodeModel/` (t_FSNodeDates, t_FSNodeNameOrder, t_FSNodeDateCell;
ids below are the test names). Tags as in assertions-p-list.md.

## Dates in browser columns and icon info lines

- MI-FSN-70 The modification date reads as in the list view (relative names on) [O:2026-10-11 E22]
- MI-FSN-71 The English "%b %d %Y %H:%M" wording is gone [O:2026-10-11 E22]
- MI-FSN-72 A file changed today reads with the word for today [O:2026-10-11 E22]
- MI-FSN-73 The creation date reads the same way [O:2026-10-11 E22]

## Name order and application names

- MI-FSN-80 A dot file comes before the others [O:2026-10-11 E25]
- MI-FSN-81 Folders are not sorted first [O:2026-10-11 E25]
- MI-FSN-82 Case does not decide the order [O:2026-10-11 E20]
- MI-FSN-83 Numbers compare by value ("file2" before "file10") [G: Finder's standard compare, not in the evidence]
- MI-FSN-84 An application shows without .app (one path: -displayName) [O:2026-10-11 E22]
- MI-FSN-85 An application sorts by its name without .app [G: Finder orders by the shown name]

## Narrow date cells

- MI-FSN-90 The time is dropped first [O:2026-10-11 E22 wording]
- MI-FSN-91 A 12 hour time with AM/PM goes as a whole [O:2026-10-11 E22 wording]
- MI-FSN-92 The day word stays when the time goes [O:2026-10-11 E22 wording]
- MI-FSN-93 The comma after the day word goes with the time [O:2026-10-11 E22 wording]
- MI-FSN-94 Then the four digit year is shortened to two [G: Finder's narrow-column behaviour not observed]
- MI-FSN-95 Too narrow even for that: the middle is dotted [G: own fallback]

## OPEN

- Name order of dot files among themselves and against digits/symbols is not in the evidence.
- Localized bundle display names ("Rechner", E22) are not produced by FSNode; only .app is hidden.
- Relative dates in the browser/icon info line are a guess (E22 covers the list view only).
