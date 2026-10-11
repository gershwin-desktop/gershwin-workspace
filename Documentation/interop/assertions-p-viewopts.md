# Assertions - View Options panel (P-viewopts)

Tests: Tests/ViewOptions/t_ViewOptionsModel.m (needs a display for the view part).
Code: Workspace/ViewOptions/GWViewOptionsModel (state <-> views <-> records),
GWViewOptionsPanel (code-built panel, strings table ViewOptions.strings).

| id | behaviour | source |
|---|---|---|
| MI-VO-1..4 | icon size 16..512, text size 10..16, clamped | [S: task] |
| MI-VO-5 | list text size 10..16 | [S: task] |
| MI-VO-6..7 | grid spacing 54..100 | [G: Finder 10.6 slider range] |
| MI-VO-8 | arrange by: none, grid, name, kind, dateModified, dateCreated, size, label | [F:E8] |
| MI-VO-9 | the name column is not optional | [O:E8] |
| MI-VO-10..16 | icon options into icvp | [F:E8] |
| MI-VO-17 | list options into lsvp; small/large icons are 16/32 | [O:E5] |
| MI-VO-18, 21 | vstl only with "Always open in", dropped without | [O:E5] |
| MI-VO-19..20 | records back into the panel state | [S] |
| MI-VO-22..28 | panel state onto and back from real icon and list views | [S] |
| MI-VO-29..30 | a panel writes only the options of the kind of view shown | [G] |

OPEN
- Grid spacing and the background are stored (icvp) but the icon view has no
  setter for the spacing; a picture or colour background is applied to the
  view as GWSpatialViewer does.
- Dropping vstl is done on the parent store only; a volume root or the home
  folder keep theirs as "." in their own store [O:E14] and are not cleaned.
