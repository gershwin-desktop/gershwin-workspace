# Assertions: list view options (P-list)

Owner: P-list. Code: `FSNode/FSNListView.{h,m}`. Tests:
`Tests/FSNodeListView/t_FSNListViewOptions.m` (ids below are the test names).

Tags: [S:x] public spec or documentation, [F:x] fixture or file format,
[G:reason] guess to be checked on the Mac (see OPEN list in the report).
Status of every line: implemented and covered by the test of the same id.

## Column ids

- MI-LST-1 The Finder lsvp column ids name, dateModified, dateCreated, size, kind, label, version, comments, dateLastOpened are the ids of the list view's columns, in that order [F:DSStore/DSStoreEntry.m listViewEntryForFile, DSStore/fields.md lsvp]
- MI-LST-2 Every Finder column id maps to a table identifier and back [G: own mapping]
- MI-LST-3 An unknown column id has no table identifier [G: fail hard]
- MI-LST-4 The columns the list always had keep their old identifiers, so stored per-folder column descriptions stay valid [G: compatibility]

## Sort direction

- MI-LST-5 A first click on a column sorts name and kind ascending, dates and size newest/biggest first [O:2026-10-11 E20]
- MI-LST-19 The list is sorted by name at first [S:Finder default]
- MI-LST-20 Ascending at first [S:Finder default]
- MI-LST-21 Name ascending is A to Z [G: FSNode compareAccordingToName order]
- MI-LST-22 Sorting by a shown column id works [G: API]
- MI-LST-23 Size ascending puts the biggest file last [F:DSStore lsvp ascending = values in natural order]
- MI-LST-24 Size descending puts the biggest file first [F:DSStore lsvp ascending]
- MI-LST-25 The direction is kept when the column changes through the API [G: API]
- MI-LST-26 Date modified ascending is oldest first [F:DSStore lsvp ascending]
- MI-LST-27 Date modified descending is newest first [F:DSStore lsvp ascending]
- MI-LST-28 Sorting by a hidden or unknown column is refused [G: API]
- MI-LST-29 The setters do not post the user-change notification [G: applying stored settings must not write back]
- MI-LST-30 Clicking the header of the sorted column reverses the direction [S:Finder behaviour]
- MI-LST-31 The rows follow the new direction [S:Finder behaviour]
- MI-LST-32 Clicking another header sorts by it in its default direction [O:2026-10-11 E20]
- MI-LST-33 Text columns start ascending [O:2026-10-11 E20]
- MI-LST-34 Every header click is reported once as a sort change [G: API]
- (no test id) A header dragged to reorder the columns does not sort; sorting happens on click, not on mouse down [G: Finder]
- (no test id) The sorted column's header shows an arrow, up for ascending, down for descending [S:Finder behaviour; on-screen check]
- (no test id) The sort direction is stored per folder next to the sort column (`hligh_table_asc`) [G: persistence of this list view]

- MI-LST-77 Every column keeps its own direction, its first-click one until changed [O:2026-10-11 E20]
- MI-LST-78 Hiding the sort column sorts by name [O:2026-10-11 E20]
- MI-LST-79 In the direction the name column was last sorted in [O:2026-10-11 E20]

## Column visibility and order

- MI-LST-35 A column can be hidden [S:Finder View Options]
- MI-LST-36 A hidden column is gone from the column order [G: API]
- MI-LST-37 The name column cannot be hidden [G: Finder always shows Name]
- MI-LST-38 An unknown id is refused [G: fail hard]
- MI-LST-39 Hiding the column the list is sorted by sorts by name instead [O:2026-10-11 E20]
- MI-LST-40 In the direction the name column was last sorted in [O:2026-10-11 E20]
- MI-LST-41 A column given a width while hidden comes back with that width [F:lsvp columns[].width exists for hidden columns]
- MI-LST-42 A shown column is appended at the right [G: API]
- MI-LST-43 setColumnOrder moves the listed columns to the left, name first, the rest follow [F:lsvp columns[] array order]
- MI-LST-44 Setting the order does not post the user-change notification [G: as MI-LST-29]
- MI-LST-45 A column dragged by the user stays where it was dropped, but never left of Name [O:2026-10-11 E21]
- MI-LST-46 The new order is reported once, after the drag settled [G: API]
- MI-LST-47 The name column is put back at the left edge when dragged away [O:2026-10-11 E21]
- MI-LST-48 No column is lost by that [G: API]

## New columns

- MI-LST-49 The comments column shows the comment the metadata provider returns [S:Finder column]
- MI-LST-50 An empty comment shows "--" [G: Finder]
- MI-LST-51 A plain file has no version, shown "--" [S:Finder column]
- MI-LST-52 The label column shows the label name the provider returns [S:Finder column]
- MI-LST-53 Date last opened is a date, from the file's access time [G: closest POSIX equivalent]
- MI-LST-54 Sorting by label puts labelled files before those without when descending [G: label index order, none first]
- (no test id) Date created and date last opened rows draw as date cells (shortened to a numeric date when narrow) [G: as date modified]
- (no test id) Version of a package is CFBundleShortVersionString, else CFBundleVersion, else ApplicationRelease [G: Finder shows short version]

## Relative dates

- MI-LST-6 A date of today reads "Today at HH:MM" [S:Finder relative dates]
- MI-LST-7 A date of the day before reads "Yesterday at HH:MM" [S:Finder relative dates]
- MI-LST-8 An older date keeps the plain form [G: Finder prints the localized date]
- MI-LST-9 A date after today is not called Today or Yesterday [G]
- MI-LST-10 With relative dates off today is a plain date [S:Finder]
- MI-LST-55 Dates are plain by default [S:Finder default]
- MI-LST-56 With relative dates on, today's file reads "Today at ..." in the cell value [S:Finder relative dates]
- (no test id) The two words and the join are looked up as the strings "Today", "Yesterday", "%@ at %@" in the FSNode strings table [S:localization]

## Row metrics

- MI-LST-11 The default row height is 28 points [F:existing CELLS_HEIGHT]
- MI-LST-12 The row height follows the icon size (icon + 4) [G: AppearanceMetrics has no list row metric]
- MI-LST-13 A big text makes rows taller than a small icon needs (line + 6) [G]
- MI-LST-57 Default row 28, icon 24 [F:existing ICNSIZE]
- MI-LST-58 A 32 point icon makes the rows 36 points [G]
- MI-LST-59 Icon sizes are limited to 128 [G]
- MI-LST-60 and to 16 at the least [S:Finder list icon sizes 16 and 32]
- MI-LST-61 Back to 24 the rows are 28 again [G]
- MI-LST-62 A 30 point text makes the rows taller and textSize reports it [F:lsvp textSize]
- MI-LST-63 Every column's cells use the text size [F:lsvp textSize]
- MI-LST-64 Text size 0 selects the default [G: API]

## Calculate all sizes

- MI-LST-14 A folder's size is the sum of the sizes of the files below it, symbolic links not followed [G: logical size, as Finder]
- MI-LST-15 The size of a plain file is its own [G]
- MI-LST-16 A walk told to stop does not go on [G: cancellation]
- MI-LST-17 A folder that is not there is 0 bytes [G]
- MI-LST-65 A folder's size is "--" as long as sizes are not calculated [S:Finder]
- MI-LST-66 Turning calculate all sizes on starts the walk on a thread of its own [G: must not block the UI]
- MI-LST-67 The UI does not wait for it [G]
- MI-LST-68 The walk ends [G]
- MI-LST-69 The folder's size is that of its contents [G]
- MI-LST-70 The size column shows it [G]
- MI-LST-71 Sizes sort together with the folders' sizes [G]
- MI-LST-72 Folders sort by their calculated size, the order being redone when the walk is finished [G]
- MI-LST-73 Turning it off forgets the sizes [G]
- MI-LST-74 Folders show "--" again [S:Finder]
- MI-LST-75 Showing another folder cancels the walk; nothing of it is delivered afterwards [G: required by the task]
- MI-LST-76 A folder without subfolders has nothing to walk [G]
- (no test id) Another file system mounted below a folder is not entered [G]
