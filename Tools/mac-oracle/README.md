# mac-oracle

Drives the Mac OS X 10.6.8 Finder over ssh (the oracle) so Workspace's Finder
interoperability is measured on the real thing. Findings are in
`Documentation/interop/evidence.md` (E1..E28); read E1, E2, E4, E5, E10 first.

    Tools/mac-oracle/mac-oracle help

Needs `sshpass`, `tar`, a C compiler and GNUstep (dstool is built from this
tree's `DSStore/` sources into `.build/`). Defaults: host `Users-Mac-mini.local`,
user `user`, password `user`; override with `MAC_HOST`, `MAC_USER`, `MAC_PASS`.
Cases live in `~/Desktop/mi/<name>` on the Mac. Only one agent may use the Mac
at a time.

## Subcommands

- `run '<applescript>'`, `sh '<cmd>'`: osascript or a shell command on the Mac.
- `mkcase <name>`: fresh case folder with a.txt b.txt c.txt. `lcase <dir>`: same locally.
- `push [--force] <dir> <name>`: tar to the Mac; `._` sidecars become native
  xattrs. If `<dir>/.mac-oracle/parent.DS_Store` exists its record `@` is merged
  into the Mac's parent `.DS_Store` under `<name>` (Finder restarted around it).
- `dsplist <dir> <code> <plist>`: same as dsput, record from a plist file (nested
  values such as lsvp `columns`, data such as `backgroundImageAlias`).
- `dsraw <dir> <code> <type> <value>`: raw record for push (blob as hex or
  `@file`, `long`, `shor`, `bool`, `ustr`, `type`), for the legacy records.
- `dsread <.DS_Store> [record]`: decodes a store with an independent Python
  reader (`dump` uses it); `dstool <args>` runs the C helper (put, putplist,
  putraw, rm, copyrec, dump).
- `pull [--no-flush] <name> <dir>`: flushes Finder, brings the folder back; xattrs
  arrive as `._` files, `.mac-oracle/xattrs.txt` has a hex dump of all xattrs and
  `.mac-oracle/parent.DS_Store` the parent records of that folder (record `@`).
- `dsput <dir> <code> k=v ...`: our DSStore code writes a Finder record for the
  next `push` (`icvp`, `bwsp`, `lsvp` as plist; `vstl value=Nlsv|icnv|clmv|Flwv`).
  Integers, `1.0` reals, `true`/`false` and strings are typed by their spelling.
- `dump [--no-flush] <name>`: folder `.DS_Store`, the parent's records for the
  folder, and xattrs, as stable text (diffable).
- `finder-set <name> <option> <value>`, `finder-get <name> <option>`:
  - icon view: `icon-size`, `icon-text-size`, `label-position` (bottom|right),
    `arrangement` (not arranged|snap to grid|left to right|...), `shows-item-info`,
    `shows-icon-preview`, `background-color` (`r,g,b` 0..65535)
  - list view: `list-sort-column` (name|size|kind|...), `list-text-size`,
    `list-icon-size` (small|large), `list-calculates-folder-sizes`,
    `list-uses-relative-dates`, `list-column-visible:<col>`, `list-column-width:<col>`,
    `list-column-index:<col>` (col = name, size, kind, modification date, ...)
  - window: `toolbar-visible`, `statusbar-visible`, `bounds` (`l,t,r,b`),
    `current-view` (icon|list|column|flow), `sidebar-width`
  - items: `comment@<file>`, `label-index@<file>`, `locked@<file>`,
    `extension-hidden@<file>`
- `shot [--at l,t,r,b] <name> [out.png]`: picture of the Finder window, moved to
  `l,t,r,b` first (a system dialog may cover the middle of the screen; the
  free strip on the oracle is about {10,470,1014,725}).
- `ui-on`, `ui-off`: create/remove the root-owned accessibility flag (sudo with
  the Mac password) and restart System Events/Finder; `reset` runs `ui-off`.
  `ui '<applescript>'` runs a System Events script, `view-options <name>` lists
  the View Options panel controls, `view-option-click <name> <title>` clicks a
  checkbox by its (localized) title.
- `drag <x1> <y1> <x2> <y2>`: Quartz mouse drag on the Mac screen (points,
  top-left origin) for what System Events cannot do (column widths/order, icon
  drops, text drags).
- `flush`: make Finder write pending `.DS_Store` changes (E4).
- `expect <name> <opt> <val>`, `expect-dump`, `expect-no-dump <name> <regex>`: assertions.
- `reset [--keep-cases]`: restores the Finder preferences baseline recorded in
  `~/Desktop/mi/.baseline` and wipes the cases. `baseline` records it once.
- `recipe <file|name> [--param k=v ...]`: runs `recipes/<name>.recipe`, one
  subcommand per line, `#` comments, `{k}` placeholders, shell quoting for words
  with spaces. A failing step stops the recipe.

## Things that bite

- Finder holds `.DS_Store` writes back about 5 s and loses them on SIGTERM. Use
  `flush` (or `pull`/`dump`, which flush) before reading files.
- Finder 10.6 stores a folder's window and view records in the PARENT's
  `.DS_Store`, named after the folder, and ignores `.` records in the folder's own
  store (E1, E2). That is why `dump` shows both stores.
- `finder-get` after `push` or `flush` shows what was persisted; before that it
  shows Finder's live state.
- The AppleScript view style is not stored per folder (E5).
- `screencapture` does not work over ssh; `shot` uses Quartz on the Mac.
- A locked item (`locked@`) needs `chflags nouchg` before removal; `reset`, `push
  --force` and `mkcase` do that.
- The repo DSStore loader reads `shor` as 2 bytes and drops every later record
  (E10); `push` therefore refuses to merge into a parent store holding `shor`
  records (`reset` first), and `dump` reads with `dsread`.
- AppleScript column `visible`/`index` do not do what they say (E10); use
  `view-option-click` or `drag`.
- A `._` sidecar without entry 9 is rejected by 10.6 copyfile, so `push` fails
  on it (E17).
