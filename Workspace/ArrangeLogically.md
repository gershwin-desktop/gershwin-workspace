# Specification: “Arrange Logically”

## Semantic Spatial Arrangement for Classic Spatial File Managers

**Version:** 1.0
**Feature:** `View ▸ Arrange Logically`
**Target:** Spatial file manager with `.DS_Info` support
**Primary Goal:** Arrange arbitrary directories into a human-composed, classic spatial layout based on semantic meaning rather than alphabetical, chronological, or purely geometric order.


# 1. Motivation — The “Why”

Traditional automatic arrangement answers:

> **“How can these files be packed into a predictable pattern?”**

`Arrange Logically` should answer a different question:

> **“If a human user had opened this folder and carefully arranged it for another human, where would they have put everything?”**

Spatial organization is powerful because the location of an object can communicate meaning.

A README near the top meant:

> Start here.

An application in the center meant:

> This is the important thing.

Documentation placed to the right meant:

> This is reference material.

Utilities pushed toward the edges meant:

> These are available, but you probably don't need them immediately.

The arrangement itself became a form of navigation.

Modern file managers largely discard this semantic layer. They tend to impose:

* alphabetical ordering
* list hierarchy
* sorting by metadata
* search-driven discovery

Those systems are efficient for retrieval, but they do not create a **spatial mental model**.

`Arrange Logically` exists to restore that layer.


# 2. Design Principle

The feature MUST NOT be treated as:

> “Sort the files and put them into a nice grid.”

It MUST be treated as:

> **“Compose a small spatial interface from the contents of the directory.”**

The algorithm therefore consists of four conceptual stages:

```text
DISCOVER
   ↓
UNDERSTAND
   ↓
COMPOSE
   ↓
PLACE
```

Where:

1. **Discover** what objects exist.
2. **Understand** what role each object probably plays.
3. **Compose** a hierarchy and visual grouping.
4. **Place** the objects into a spatial arrangement.

The output should look intentionally designed rather than algorithmically tiled.


# 3. Goals

`Arrange Logically` SHOULD:

* infer the semantic role of files and folders
* identify likely entry points
* identify primary applications or artifacts
* distinguish user-facing content from technical machinery
* group related objects spatially
* establish a clear visual hierarchy
* preserve meaningful negative space
* favor recognition over density
* produce deterministic layouts
* work without requiring explicit metadata
* respect existing custom icons and file-manager metadata
* write the resulting positions back into `.DS_Info`
* remain editable after arrangement
* feel plausible as a manually composed spatial layout


# 4. Non-Goals

`Arrange Logically` MUST NOT attempt to:

* alphabetize files
* maximize packing density
* eliminate all empty space
* create folders automatically
* rename files
* infer a single objectively correct ordering
* permanently lock the resulting layout
* replace manual spatial arrangement
* behave like a modern application launcher
* continuously rearrange the directory as files change

This is a **composition command**, not a sorting mode.

Once executed, the result should behave like a human-arranged spatial window.


# 5. User Experience

The command appears as:

**View ▸ Arrange Logically**

It is a one-shot operation.

After execution:

1. The contents are analyzed.
2. Semantic roles are assigned.
3. A spatial composition is generated.
4. Icons are placed.
5. Positions are written to `.DS_Info`.
6. The user may manually adjust any icon afterward.

Running `Arrange Logically` again may regenerate the composition.

It SHOULD NOT automatically run whenever the directory changes.


# 6. Mental Model

The algorithm should imagine the directory as a **physical desk**.

Objects have both:

* **semantic importance**
* **physical location**

The resulting layout should answer several questions without opening anything:

### Where do I begin?

Usually the upper portion.

### What is the main thing?

Usually the central visual area.

### What do I need before using it?

Usually the left side.

### What do I consult afterward?

Usually the right side.

### What else is available?

Usually the lower/peripheral areas.

### What is technical machinery?

Usually peripheral and visually de-emphasized.

This is the basic spatial grammar.


# 7. Semantic Classification

Every visible item receives a semantic profile.

The classifier SHOULD consider, in roughly descending order of reliability:

1. explicit application metadata
2. file type / creator metadata
3. filename
4. extension
5. directory name
6. neighboring files
7. directory structure
8. repository conventions
9. content inspection, where available

The system MUST NOT require semantic certainty.

Classification is probabilistic.

An item may have multiple roles with different confidence levels.


# 8. Semantic Roles

The initial role vocabulary SHOULD include:

### `ENTRY_POINT`

Things that tell the user how to begin.

Examples:

* `README`
* `README.md`
* `START HERE`
* `WELCOME`
* `GETTING STARTED`
* `INSTALL`
* `ABOUT`


### `PRIMARY_ARTIFACT`

The central thing the directory appears to exist to contain.

Examples:

* `.app`
* executable
* game
* primary document
* major project artifact
* main package
* viewer
* installer
* `GNUmakefile` (the primary build artifact of a GNUstep project)


### `SOURCE`

Primary implementation material.

Examples:

* `src`
* `source`
* `lib`
* `include`
* `Sources`


### `DOCUMENTATION`

Human-facing explanatory material.

Examples:

* `docs`
* `documentation`
* `manual`
* `guide`
* `reference`
* `CHANGELOG`
* `FAQ`


### `EXAMPLE`

Demonstration material.

Examples:

* `examples`
* `samples`
* `demo`
* `demos`
* `tutorial`


### `BUILD`

Things involved in building or preparing the project.

Examples:

* `Makefile`
* `CMakeLists.txt`
* `package.json`
* `Cargo.toml`
* build scripts
* setup scripts
* installers
* deployment configuration


### `TEST`

Testing material.

Examples:

* `tests`
* `test`
* `spec`
* `fixtures`
* `snapshots`


### `PROJECT_METADATA`

Human-facing project information that is useful but not central.

Examples:

* `LICENSE`
* `AUTHORS`
* `CONTRIBUTORS`
* `CONTRIBUTING`
* `HISTORY`
* `CHANGELOG`


### `DEVELOPMENT_INFRASTRUCTURE`

Technical machinery primarily intended for developers or hosting platforms.

Examples:

* `.github`
* CI configuration
* workflow definitions
* editor configuration
* repository metadata
* deployment configuration


### `ASSET`

Supporting resources.

Examples:

* images
* sounds
* fonts
* themes
* templates
* artwork


### `UTILITY`

Secondary tools or helper applications.


### `CONTAINER`

A folder whose primary purpose is to contain a semantic group.


### `UNKNOWN`

Anything that cannot be confidently classified.

Unknown objects MUST still receive a reasonable location.


# 9. Importance Scoring

Each item receives an approximate **importance score**:

```text
0.0 — disposable / technical
0.25 — peripheral
0.50 — useful secondary material
0.75 — important
1.0 — primary
```

Importance should be derived from semantic role, not merely file size or alphabetical position.

For example:

```text
README.md          1.00
MyApp.app          1.00
src/               0.80
docs/              0.75
examples/          0.60
tests/             0.45
LICENSE            0.30
.github/           0.15
.gitignore         0.10
```

These values are illustrative rather than fixed.


# 10. User-Facingness

Each item SHOULD also receive a **user-facingness** score.

This distinguishes:

> “Something the person using this software should see”

from:

> “Something the person maintaining this software needs.”

For example:

```text
README       → high
Manual       → high
Application  → very high
Examples     → high
src          → medium
tests        → low
.github      → very low
.gitignore   → very low
```

This distinction is critical for Git repositories.

A GitHub repository may contain dozens of technically important files, but a human-oriented spatial window should not give all of them equal visual weight.


# 11. Spatial Zones

The canvas is divided into **semantic zones**, still aligned on the shared
grid (every icon on both a row line and a column line; positions may be left
empty for symmetry)

Conceptually:

```text
                 ┌─────────────────────┐
                 │      ENTRY          │
                 │                     │
                 │   SUPPORT   PRIMARY │
                 │                     │
                 │   SOURCE   DOCUMENT │
                 │                     │
                 │ SECONDARY   SECONDARY
                 └─────────────────────┘
```

The zones are:

### Zone A — Entry

Upper region.

The entry point occupies the single top row, exactly centred on the
horizontal axis, with one blank row beneath it separating it from the rest of
the composition.

Preferred for:

* README
* Start Here
* Welcome
* installation instructions


### Zone B — Primary

Central visual region.

Preferred for:

* application
* executable
* main artifact
* installer


### Zone C — Preparation

Left-middle region.

Preferred for:

* source
* build instructions
* requirements
* drivers
* setup material


### Zone D — Reference

Right-middle region.

Preferred for:

* documentation
* manuals
* examples
* reference material


### Zone E — Secondary

Lower and peripheral regions.

Preferred for:

* tests
* utilities
* assets
* metadata
* optional content


### Zone F — Technical Periphery

Farthest available peripheral locations.

Preferred for:

* `.github`
* `.gitignore`
* CI configuration
* editor configuration
* repository-specific machinery


# 12. Spatial Priority

The algorithm SHOULD follow this approximate hierarchy:

```text
ENTRY
  ↓
PRIMARY
  ↓
PREPARATION / REFERENCE
  ↓
SOURCE / EXAMPLES / ASSETS
  ↓
METADATA / TESTS / UTILITIES
  ↓
TECHNICAL MACHINERY
```

This is not a vertical ordering.

It represents **visual prominence**.


# 13. The Primary Object

The algorithm SHOULD attempt to identify a single primary object.

Possible signals include:

* application bundle
* executable
* obvious main artifact
* installer
* a `GNUmakefile` (the build artifact of a GNUstep project)
* project name matching the directory name
* dominant file type
* application metadata
* README references
* filename conventions

If confidence is high:

> Place the object centrally.

If several candidates have similar scores:

> Do not arbitrarily select one.

Instead, compose a balanced central cluster.

If no primary object exists:

> Use the semantic center for the most important user-facing container or document.

A source-code repository with no application should therefore NOT invent an imaginary “main application.”


# 14. Entry Point Detection

The algorithm SHOULD strongly prioritize conventional entry-point names.

Example ranking:

```text
START HERE
WELCOME
README
GETTING STARTED
INSTALL
ABOUT
MANUAL
```

A README should generally appear **above or near the primary object**, rather than merely being the first item alphabetically.

The chosen entry point is placed alone in the top row, **exactly centred** on
the horizontal axis of the canvas, and **one empty row is left beneath it**
before the rest of the composition begins.  If a README is present it MUST
receive a **green label**, marking it as "start here".

Human-facing status notes - `TODO`, `CHANGELOG`, `NEWS`, `FAQ` and the like -
belong **around the README**: they sit on the row directly beneath it, so the
top band reads as "where do I begin + what is going on".  Examples (folders or
files) are also kept **close to the top**, next to the entry band, because
they answer "what does this look like".  One blank row then separates this
whole top band from the main composition.

If multiple README files exist:

```text
README
README.txt
README.md
README.html
```

the system SHOULD select the most user-facing representation and treat the others as secondary.


# 15. Git Repository Heuristics

GitHub repositories are a particularly important input because they frequently contain large amounts of machine-oriented metadata.

The algorithm SHOULD recognize common repository structures.

Example:

```text
.github/
.gitignore
LICENSE
README.md
CONTRIBUTING.md
CHANGELOG.md
Makefile
package.json
src/
tests/
docs/
examples/
```

A likely composition would be:

```text
                         README


              src/                  docs/


                    PROJECT / APP


          examples/           tests/


       Makefile     LICENSE     CHANGELOG     .github
```

The exact arrangement MUST depend on the actual contents.


# 16. Dotfiles

Hidden or dot-prefixed files deserve special treatment.

The algorithm SHOULD distinguish:

### User-relevant dotfiles

Potentially visible:

* `.env.example`
* `.editorconfig`
* project configuration with meaningful user-facing purpose

### Developer infrastructure

Peripheral:

* `.github`
* `.git`
* `.gitignore`
* `.gitattributes`
* CI metadata
* IDE configuration

The existence of a dot prefix SHOULD NOT automatically determine placement, but it is a strong signal of technical rather than user-facing purpose.


# 17. Containers

Folders SHOULD generally be treated as semantic landmarks.

A folder such as:

```text
Documentation
Examples
Utilities
```

is not merely a collection of files.

Its location should communicate the role of its contents.

Folders should therefore generally occupy more stable and visually distinct positions than arbitrary individual files.


# 18. Composition Before Coordinates

The implementation MUST NOT begin by calculating coordinates for every file.

Instead:

### Phase 1 — Classification

Determine semantic roles.

### Phase 2 — Grouping

Create logical clusters.

Example:

```text
ENTRY
PRIMARY

PREPARATION:
  src
  Makefile

REFERENCE:
  docs
  examples

SECONDARY:
  tests
  assets

TECHNICAL:
  .github
  .gitignore
```

### Phase 3 — Composition

Determine how these groups relate spatially.

### Phase 4 — Placement

Only now calculate icon coordinates.

This distinction prevents the algorithm from becoming a glorified sorting function.


# 19. Grid Alignment

The output MUST be aligned to a grid. Every icon centre falls on a grid line -
in BOTH axes: icons share the horizontal grid lines (rows) AND the vertical
grid lines (columns). A role that fits a single column line has all its icons
on that line, a role that fits several has them on shared column lines, so the
whole composition reads as aligned in both directions. There are no free-form
pixel offsets. Grid alignment is what makes the layout readable, predictable
and easy to refine by hand.

Each semantic role is laid out on ONE shared grid with a single column pitch,
so the icons of that role all share the same column lines. The grid has an ODD
column count, centred on the canvas centreline, giving it a true centre column.

Every row is centred on that centreline, so each line is as symmetric as the
grid allows:

* a row of ODD width sits its middle column on the centre column;
* a row of EVEN width straddles the centreline, leaving its middle column
  EMPTY so the two halves mirror each other - a grid position skipped for
  symmetry.

A row whose items fill fewer columns than the grid simply leaves the outer
grid positions empty; positions are skipped for symmetry, never filled by
nudging an icon off the grid.

Labels MUST never overlap. When a name is too long for the base cell, the item
reserves extra empty columns instead of widening the pitch: the long label
overhangs into space rather than covering a neighbour, and every other item in
the role keeps the same column lines. A reserved span is kept odd so the icon
centre stays on a grid line.

Rows are homogeneous: a row holds folders or files, never a mix. Every item in
a row shares the SAME column span (the widest label in the row), so the spacing
between all items in a row is identical; the widest items lead so an
out-of-scale label isolates itself while equal-width neighbours still pack
into full rows.

The visible viewport width - the part of the viewport that is on screen
without scrolling - is the upper limit for the width of a line: layout is
vertical-scrolling only, so no line may ever exceed the width of the visible
viewport.  A label wider than the whole grid is therefore clamped to the grid
width; its box stays inside the visible viewport instead of overhanging the
canvas edge.

The human character of the layout therefore comes from the COMPOSITION - the
semantic zones, the asymmetric grouping, the negative space left between
groups - not from nudging individual icons off the grid.

The layout SHOULD strive for symmetry where possible: the README and the
primary object are placed exactly on the horizontal centre of the canvas, and
the preparation/reference band is mirrored around that centreline, so the
composition reads as balanced.


# 20. Determinism

Given:

```text
same directory
same metadata
same window size
same algorithm version
```

the result SHOULD be identical.

This is important for:

* testing
* reproducibility
* user trust
* version control
* debugging

If intentional variation is desired, derive it from a deterministic seed such as the directory identity and item names.


# 21. Collision Resolution

After semantic placement, icons MUST be checked for:

* overlap - NO items mus overlap (use on-disk filenames, not user-visible display names which may lack filename extensions)
* label collision
* insufficient spacing
* window boundaries

Collision resolution SHOULD move objects **within their semantic zone** before moving them to another zone.

For example:

A documentation icon colliding with another documentation icon should move within the documentation area.

It should not suddenly appear in the bottom-left corner.


# 22. Density Management

The algorithm SHOULD prefer:

> fewer, more meaningful spatial landmarks

over:

> perfectly distributed icons.

The layout MUST be dense: it MUST contain no more than one empty grid row in
total. A composition that leaves large blank gaps between groups - or ends
with rows of empty space - is a failure. Consecutive groups of icons are
stacked with at most one empty row between them.

Rows hold one kind: folders together on one row, every file together on
another - a row never mixes folders and files.  One kind per row reads as
tidy and hand-arranged.  A row is filled up to the grid's column count before
advancing, so it stays dense; the empty positions that remain - the outer
columns of a partial row, or the skipped centre column of an even row - are
what keep every row symmetric about the canvas centreline.  Every item in a
row shares one column span, so the spacing between the items of a row is
identical.

When many items exist, it MAY cluster them.

For example:

```text
Source
Examples
Tests
Assets
```

may become a coherent lower-left cluster rather than occupying four independent “important” locations.

The layout should communicate hierarchy even when the directory contains dozens of objects.


# 23. Overflow Strategy

If the number of objects exceeds the comfortable capacity of the viewport:

1. preserve entry point
2. preserve primary artifact
3. preserve major documentation
4. preserve major containers
5. compress secondary groups
6. move low-importance technical items toward the periphery

The algorithm MUST NOT sacrifice the primary hierarchy merely to keep every object equally visible.

If necessary, lower-priority items may be placed farther from the primary composition, provided the file manager's spatial model can represent them.


# 24. Existing Spatial Metadata

`Arrange Logically` is an explicit user action and therefore MAY replace existing `.DS_Info` coordinates.

However, the system SHOULD consider existing spatial information as evidence of user intent.

Recommended behavior:

* manually positioned objects may receive a **layout weight**
* automatically generated positions should avoid unnecessarily disturbing explicitly protected objects
* the user MAY choose whether `Arrange Logically` replaces all positions or respects existing placements

Possible future variants:

**Arrange Logically**

> Recompose everything.

**Arrange Remaining Logically**

> Leave manually placed objects alone and arrange everything else.


# 25. Labels and Visual Metadata

`Arrange Logically` MAY optionally assign semantic labels, but labels SHOULD NOT be required for the algorithm to work.

If labels are assigned:

* the README (entry point) MUST receive a **green label**
* primary artifacts may receive an action-oriented label
* documentation may receive a reference-oriented label
* a `GNUmakefile`, when present, MUST receive a blue label (like an
  application) to mark it as the primary build artifact
* technical material should generally remain unlabeled

Color is a reinforcement layer.

Spatial placement remains the primary semantic channel.


# 26. Example: Typical Repository

Input:

```text
README.md
LICENSE
CONTRIBUTING.md
CHANGELOG.md
Makefile
package.json
src/
docs/
examples/
tests/
.github/
.gitignore
```

Semantic interpretation:

```text
README.md        ENTRY_POINT
src/             SOURCE
docs/            DOCUMENTATION
examples/        EXAMPLE
tests/           TEST
Makefile         BUILD
package.json     BUILD / METADATA
LICENSE          PROJECT_METADATA
CONTRIBUTING.md  PROJECT_METADATA
CHANGELOG.md     DOCUMENTATION / METADATA
.github/         DEVELOPMENT_INFRASTRUCTURE
.gitignore       DEVELOPMENT_INFRASTRUCTURE
```

Possible composition:

```text
                         README


             src/                    docs/


                         PROJECT


        examples/                  tests/


   Makefile      package.json    CHANGELOG


        LICENSE       CONTRIBUTING       .github
```

This should feel like something a person **chose**, not something a program **sorted**.


# 27. Example: Application Folder

Input:

```text
MyApp.app
README
Manual
Examples/
Plug-ins/
Preferences/
Resources/
Uninstaller
```

Desired composition:

```text
                         README


              Manual        MyApp.app


          Examples/       Plug-ins/


       Preferences/       Resources/


                         Uninstaller
```

The application becomes the landmark.

Documentation becomes its immediate context.

Supporting material moves outward.

The uninstaller is deliberately de-emphasized.


# 28. Example: Pure Source Repository

Input:

```text
README.md
src/
include/
lib/
tests/
docs/
examples/
LICENSE
Makefile
```

There may be no obvious “primary application.”

The algorithm should therefore avoid placing an arbitrary source directory in the absolute center.

Instead:

```text
                         README


             docs/              examples/


                     src/


              include/    lib/


         tests/     Makefile     LICENSE
```

The source tree becomes the central subject of the directory.


# 29. Relationship to Other Arrangement Commands

`Arrange Logically` SHOULD coexist with conventional commands.

| Command             | Purpose                          |
| ------------------- | -------------------------------- |
| **Clean Up**        | Geometric normalization          |
| **Arrange by Name** | Alphabetical ordering            |
| **Arrange by Kind** | Type-based ordering              |
| **Arrange by Date** | Temporal ordering                |
| **Keep Arranged**   | Continuous automatic arrangement |
| **Arrange Logically** | Semantic spatial composition     |

The distinction is important.

`Arrange Logically` is not another sorting mode.

It is a **layout mode that happens to be invoked as a command**.


# 30. Quality Criteria

A successful implementation should pass the following tests.

### The README Test

If a README exists, can a user immediately identify where they should begin?

### The Main Object Test

If there is an obvious primary application or artifact, does it have the strongest spatial prominence?

### The Peripheral Machinery Test

Are Git/CI/development internals visually subordinate to human-facing content?

### The Spatial Memory Test

Could someone describe the contents using locations?

For example:

> “The documentation is on the right, the source is on the left, and the README is above the app.”

If yes, the layout is working.

### The Human Test

Does the result look like someone arranged it?

If it looks like:

```text
[ ][ ][ ][ ][ ]
[ ][ ][ ][ ][ ]
[ ][ ][ ][ ][ ]
```

the algorithm has failed.

### The Spatial Window Test

Would this layout look plausible in a classic spatial file-manager window?

If it looks like a modern dashboard, launcher, or file-management utility, it has failed aesthetically.


# 31. Core Algorithm

At a high level:

```text
function ArrangeLogically(directory, canvas):

    items = discover(directory)

    for item in items:
        item.profile = classify(item)
        item.importance = calculateImportance(item.profile)
        item.userFacingness = calculateUserFacingness(item.profile)
        item.confidence = calculateConfidence(item.profile)

    entry = chooseEntryPoint(items)

    primary = choosePrimaryArtifact(items)

    groups = createSemanticGroups(items, entry, primary)

    composition = composeSpatialHierarchy(
        entry,
        primary,
        groups,
        canvas
    )

    positions = placeComposition(
        composition,
        canvas
    )

    positions = resolveCollisions(
        positions,
        semanticZones=composition.zones
    )

    positions = applyControlledIrregularity(
        positions,
        deterministicSeed=directoryIdentity(directory)
    )

    positions = validate(
        positions,
        canvas
    )

    writeSpatialMetadata(
        directory,
        positions
    )
```

The important property is that **coordinate generation happens near the end**.

The system first decides:

> “What is this thing?”

then:

> “How important is it?”

then:

> “What does it belong with?”

then:

> “Where would a human put that group?”

and only finally:

> “What are the actual x/y coordinates?”


# 32. The Fundamental Rule

The algorithm should optimize for:

**semantic clarity > spatial memory > visual balance > geometric efficiency**

—not:

**geometric efficiency > sorting consistency > semantic meaning**

The goal is to reproduce a design decision that a person makes by dragging icons around a spatial window.

`Arrange Logically` should therefore feel less like an auto-layout engine and more like:

> **“A very opinionated user just arranged this folder for me.”**

I think that last sentence is the right north star for the feature: **the user should feel that a person arranged the folder, not that a sorting algorithm ran.**
