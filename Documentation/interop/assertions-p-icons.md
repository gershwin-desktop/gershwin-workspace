# Assertions: icon view options (P-icons)

Tests: `Tests/FSNodeIcons/t_FSNIconItemInfo.m`, `t_FSNIconsViewOptions.m`.
Tags: [S:] public spec / icvp key semantics, [F:] fixture bytes, [G:] guess
(see OPEN list in the report; Mac oracle not yet consulted).
Fixtures with `icvp` bytes were not available in this tree, so no [F:].

## Show item info
- MI-ICN-1 an empty folder reads "0 items" [G: Finder wording]
- MI-ICN-2 one entry reads "1 item" [G: Finder wording]
- MI-ICN-3 twelve entries read "12 items" [G: Finder wording]
- MI-ICN-4 an empty file reads "Zero bytes" [G: 10.6 wording from memory]
- MI-ICN-5 one byte reads "1 byte" [G]
- MI-ICN-6 below 1000 bytes counted in bytes, decimal units [G: 10.6 uses base 10]
- MI-ICN-7 kilobytes decimal, no fraction ("4 KB") [G]
- MI-ICN-8 megabytes decimal, one fraction digit ("1.2 MB") [G]
- MI-ICN-9 gigabytes decimal, two fraction digits ("3.50 GB") [G]
- MI-ICN-10 an image reads "width x height" in pixels [S: showItemInfo shows image dimensions]
- MI-ICN-17 item info is off by default [G]
- MI-ICN-18 item info can be turned on [S: icvp showItemInfo]
- MI-ICN-19 a folder shows its item count [S: showItemInfo]
- MI-ICN-20 a file shows its size [S: showItemInfo]
- MI-ICN-21 an image shows its pixel size [S: showItemInfo]
- MI-ICN-22 the grid cell grows by the info line [G]
- MI-ICN-23 every icon has an info line while the option is on [G]
- MI-ICN-24 turning it off removes the line [S]
- MI-ICN-25 and restores the cell height [G]

## Label text size
- MI-ICN-11 the text size is the one set [S: icvp textSize]
- MI-ICN-12 every icon draws its name at the new size [S]
- MI-ICN-13 the smallest size is 10 points [S: Finder offers 10-16]
- MI-ICN-14 a larger size makes the cell taller [G]
- MI-ICN-15 a larger size makes the cell wider [G]
- MI-ICN-16 sizes are clamped to 10..16 by +clampedLabelTextSize: [S]

## Show icon preview
- MI-ICN-26 preview can be turned on (default on) [S: icvp showIconPreview; G: default]
- MI-ICN-27 an image file shows a thumbnail of its own pixels [S]
- MI-ICN-28 with preview off an image file shows the generic type icon [S]
- MI-ICN-29 non-image files look the same either way [G]

## Arrange by
- MI-ICN-30 not arranged by default [S: arrangeBy none]
- MI-ICN-31 by name: A to Z, case-insensitive [S]
- MI-ICN-32 by size: largest first [G: direction]
- MI-ICN-33 by date modified: newest first [G: direction]
- MI-ICN-34 by label: label color order, unlabeled last [G: order, placement of unlabeled]
- MI-ICN-35 by kind: folders first [G: Finder groups by kind name]
- MI-ICN-36 same kind ordered by name [G]
- MI-ICN-37 arranging can be switched off [S]
- MI-ICN-38 the order is the reading order of the grid [S]
- MI-ICN-44 an arrangement ignores saved positions; snap is a separate switch [S: Finder keeps "snap to grid" and "arrange by" as different arrangeBy values, grid vs name...]
- MI-ICN-45 icons stay where the arrangement put them when it is switched off [G]
- (date created: arrange by DateCreated sorts newest first, [G]; not asserted, FS birth time unreliable here)

## Snap to grid
- MI-ICN-39 without snap an icon stays exactly where it was put [S]
- MI-ICN-40 snap can be turned on [S: arrangeBy grid]
- MI-ICN-41 with snap an icon moves to the center of the nearest cell [S]
- MI-ICN-42 a snapped icon sits exactly on a cell center [S]
- MI-ICN-43 two icons that want one cell get adjacent cells [G: Finder avoids overlap]

## Scroll position
- MI-ICN-46 a freshly shown folder is at the top left [G]
- MI-ICN-47 the position set is the one reported, measured from the top [S: scrollPositionX/Y; G: origin top-left]
- MI-ICN-48 y counts down from the top edge of the content [G]
- MI-ICN-49 a position beyond the content is held inside it [G]
