# Assertions: FSNode display and rename rules (I-fsnode)

Owner: I-fsnode. Code: `FSNode/FSNode.m`, `FSNodeRep.*`, `FSNFunctions.*`,
the three views' rename entry points, `FSNode/Resources/*.lproj`.
Tests: `Tests/FSNodeDisplay/` (ids below are the test names).

Tags as in assertions-p-list.md.

## Hidden extension

- MI-FSN-1..9 The display name drops the extension when the file's own bit is set, unless the global mode shows all extensions; only the last extension goes; dot files and names without extension are unchanged [S:Finder "Hide extension"; G: numeric extension also hidden]
- MI-FSN-10..14 FSNodeRep answers NO without a provider or with one that lacks `-isExtensionHiddenForPath:` (called through respondsToSelector:) [G: fail soft for old providers]
- MI-FSN-15..21 FSNode `-displayName` follows the bit; `-name` and `-lastPathComponent` never do [S:Finder]
- MI-FSN-22 The global "show all filename extensions" choice wins over the bit. It is the existing Workspace preference `GSFilenameExtensionDisplayMode` = 0 (GSFilenameExtensionDisplayAll); no new key, so the two cannot disagree [G]
- MI-FSN-41 The browser cell uses the same display name
- MI-FSN-38 The in-place rename editor starts with the full name including the extension (list view; the icon and browser editors already took `-name`) [G: Finder shows the full name while editing]

## Name locked

- MI-FSN-30..32 `-isNameLockedForPath:` reaches FSNodeRep and `-[FSNode isNameLocked]`; it is not `-isLocked` [G]
- MI-FSN-33..35 Icon view: a name-locked icon refuses `canStartRepNameEditing`
- MI-FSN-37, 39 List view: no editor for a name-locked row
- MI-FSN-42, 43 Browser: no editor for a name-locked cell

## Text cell

- MI-FSN-50..52 A list column keeps its text cell when the text size changes; `-[FSNTextCell setFont:]` forgets the fitted title (it already did on dev; the list view's fresh-cell workaround is gone)

## Strings

- t_FSNLocalizedStrings: 13 keys (Today, Yesterday, "%@ at %@", Date Created, Date Last Opened, Label, Version, Comments, item counts, byte counts) exist in all five lprojs, translated, with the same number of conversions
- The item/byte strings are now looked up in the framework bundle, not the application's

## Confirmed, nothing to do

- FSNIcon `-loadLabelIndex` already asks `-labelIndexForPath:` (respondsToSelector:); the list columns already ask `-commentForPath:` / `-labelNameForPath:`
