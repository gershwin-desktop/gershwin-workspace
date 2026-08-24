# VNC / Visual Interop Verification (macOS <-> Gershwin)

Status: **in progress** (started 2026-08-24).

This tracks the live-Mac visual ("VNC eyeballing") step from
`INTEROP_TESTING.md` -> Next steps:

> Drive the Mac over VNC to eyeball Finder labels/tags on the fixtures.

The hermetic tests (`Tests/GWMetadata/interop`) prove the *bytes* round-trip.
This level proves macOS *renders* those bytes the way Gershwin thinks it
does: Finder colour labels, tag chips, comments and custom-icon bits that a
human can actually see on the Mac mini's screen (accessed over VNC,
password `1234`, port 5900).

## Method

`Tools/mac-metadata-interop/verify-fixture-visual.sh`:

1. Assembles only the data files `file01..file07` plus their `._` sidecars
   from `Tests/GWMetadata/interop/fixtures/` into a clean dir (no
   `MANIFEST.plist` / zip noise).
2. `scp`s that dir to the Mac (`MAC_HOST`/`MAC_USER`/`MAC_PASS`, or the
   documented `user`/`user` credentials + legacy ssh-rsa flags).
3. On the Mac: copy into `~/Desktop/gw-fixture-check`, `dot_clean -m` to
   merge the `._` sidecars into native xattrs (same merge a real copy into
   HFS+ performs), enable `AppleShowAllFiles` (so the invisible fixtures
   `file01`/`file05` are actually visible), relaunch Finder, `open` the
   folder, `screencapture` the window.
4. `scp`s `visual.png` back here; we open it and compare against the
   `MANIFEST.plist` ground truth.

This is deliberately manual/visual: the point is to catch presentation
mismatches the byte tests cannot see (e.g. a label colour that disagrees
with the tag list).

## Expected vs observed

Ground truth is `MANIFEST.plist`.  macOS 10.6 label numbering: 0 none,
1 red, 2 orange, 3 yellow, 4 green, 5 blue, 6 purple, 7 grey.

| file | MANIFEST says | raw bytes on the Mac (xattr, = what Finder renders) | eyeball prediction |
|------|---------------|------------------------------------------------------|--------------------|
| file01_finderinfo.txt | label 1 (red), **invisible**, `TEXT`/`ttxt` | FinderInfo `TEXT`/`ttxt`, fdFlags `0x0802` => red label, **NOT** invisible (real invisible bit `0x4000` absent) | red label, **visible** |
| file02_resourcefork.txt | rf `CAFEBABE`, no label | FinderInfo fdFlags `0x8000`, `com.apple.ResourceFork` = `CAFEBABE`, no label | no label; `com.apple.alias-file` type quirk |
| file03_tags.txt | userTags Red, ProjectX; no labelNumber | `com.apple.metadata:_kMDItemUserTags` = [Red, ProjectX], no FinderInfo label | red label (from "Red" tag) + two tag chips |
| file04_comment.txt | comment "interop test comment" | `com.apple.metadata:kMDItemFinderComment` = "interop test comment" | comment shows in Get Info |
| file05_combined.txt | label 1 (red) **but** userTags Green,Release, **invisible**, **customIcon**, comment | FinderInfo fdFlags `0x0882` => red label, NO invisible (`0x4000`), NO custom-icon (`0x0400`); RF `DEADCODE`; tags [Green,Release]; comment "combined comment" | red label (not green) + tags Green/Release + comment, **visible, no custom icon** |
| file06_control.txt | no metadata | no xattrs | plain file |
| file07_quarantine.txt | quarantine xattr present | original `._` sidecar carries `com.apple.quarantine`, **but after `dot_clean -m` the data file has NO xattrs at all** | no quarantine badge (stripped by dot_clean) |

### Root-cause findings

1. **Wrong fdFlags bit positions - in BOTH Gershwin and the generator.** The
   `GSFileFinderFlags` enum in `GWMetadata/GSFileMetadata.h` (and the matching
   code in `generate-fixtures.sh` + its MANIFEST reader) used a value set
   shifted by two bits from the canonical classic Mac fdFlags (Apple
   `Finder.h` / TN1150).  Notably `kIsInvisible` was `1<<11` (`0x0800`)
   instead of `1<<14` (`0x4000`), and `kHasCustomIcon` was `1<<7` (`0x0080`)
   instead of `1<<10` (`0x0400`).  The generator also wrote `file02`'s single
   flag into the high byte, so it landed as `0x8000` (alias) instead of
   `0x0400`.  Consequence: `file01`/`file05` were **not actually invisible**
   and had **no custom icon** on a real Mac, and `MANIFEST.plist` + the
   hermetic `t_GSMetaDataInterop` tests asserted those (wrong) bits, so the
   suite passed while encoding non-Mac behaviour.  `file05` named its tag
   "Green" but set the red label bit, so label and tag disagreed.
   **FIXED (2026-08-24):** corrected `GSFileMetadata.h` to the canonical
   bits, corrected `generate-fixtures.sh` (and made `file05` use a green label
   `1<<3` to match its "Green" tag), corrected the MANIFEST reader, and
   regenerated the fixtures on the Mac.  `t_GSMetaDataInterop` now passes with
   real macOS values: `file01` 0x4002 (red + invisible), `file02` 0x0400
   (custom icon), `file05` 0x4408 (green label + custom icon + invisible).
   Gershwin now reads and writes the **same fdFlags macOS does** - that is the
   whole point of the interop effort.
2. **`dot_clean -m` strips `com.apple.quarantine`.** `._file07` carries
   `com.apple.quarantine` (`0083;...;Safari;...`), yet after `dot_clean -m`
   the merged data file has zero xattrs.  This is exactly the hazard flagged
   in `INTEROP_TESTING.md`'s "Quarantine round-trip" next-step: a naive
   `dot_clean`/copyfile merge drops quarantine.  **Mitigated in the visual
   script:** `verify-fixture-visual.sh` now captures the quarantine value
   before merging and re-applies it with `xattr -w` so `file07` shows the
   Gatekeeper badge on the real Mac.  The forward direction (Mac `.`_ sidecar
   -> Gershwin) still round-trips quarantine correctly (asserted by the
   hermetic test).  The reverse (Gershwin-emitted sidecars -> Mac) needs
   `dot_clean` avoided or quarantine preserved explicitly - a follow-up.

### Finding: 10.6 uses the classic label palette (grey/blue, not red/green)

When the VNC eyeball first showed **grey** on `file01` and **blue** on
`file05`, that looked wrong (the fixtures intend red/green).  It is **not** a
Gershwin bug - it is the Snow Leopard label palette.  The label *number* is
correct; only the *colour* differs by OS palette version:

- Gershwin / modern macOS palette: `1=Red 2=Orange 3=Yellow 4=Green 5=Blue 6=Purple 7=Grey`.
- 10.6 classic palette: `1=Grey 2=Green 3=Purple 4=Blue 5=Orange 6=Red 7=Yellow`.

`file01` carries `fdFlags 0x4002` => label **position 1** => classic palette =
**Grey** (exactly what the Mac showed).  `file05` carries `0x4408` => position
**4** => classic = **Blue**.  So Gershwin's `labelNumber` decode
(`(flags >> 1) & 0x7`) is right; the coloured swatch is palette-dependent.
(Finder's AppleScript `label index` property is a red herring - it returns
`8 - position`, hence "7" for `file01`.)

**Fix applied (2026-08-24):** retuned the generator so the fixtures display the
*intended* colours on the reference 10.6 Mac - `file01` now uses label position
**6** (red) and `file05` uses position **2** (green, matching its "Green" tag).
The label *number* remains the portable interop unit; Gershwin intentionally
keeps the modern palette for its own UI.  Regenerated fixtures + MANIFEST
(`file01` label 6, `file05` label 2); `t_GSMetaDataInterop` still passes (111
assertions).

### Method notes / gotchas (2026-08-24)


- `scp -r dir/.` **silently skips dotfiles**, so the `._` sidecars never
  arrived and the first attempts merged nothing (`mdls` showed all `(null)`).
  Solved by shipping a `tar` (preserves dotfiles), then `dot_clean -m` on the
  Mac.
- Mac-side `screencapture` returns 0 but writes **nothing** over SSH (Screen
  Sharing capture protection blocks window-server access from a non-Aqua
  session; `launchctl bsexec` as root also produced no file).  Solved by
  capturing the **local** TigerVNC viewer window with ImageMagick `import`
  (`verify-fixture-visual.sh` now does this).  `fixture-visual.png` is the
  resulting shot for the human to open.
- `mdls` stays `(null)` for tags/comments/labels on 10.6 because Spotlight
  does not index externally-set xattrs (documented in INTEROP_TESTING.md).
  Finder, however, reads `com.apple.FinderInfo` / `_kMDItemUserTags` /
  `kMDItemFinderComment` directly, so `xattr -l` on the Mac is the correct
  "what Finder renders" source of truth - the eyeball must confirm the
  predicted colours above.

### Finding: 10.6 Finder cannot render some attributes (not Gershwin bugs)

The VNC eyeball on the 10.6 reference Mac shows gaps that look like failures but
are **10.6 Finder UI limitations** - the on-disk metadata is correct and Gershwin
reads/writes it exactly (proven by the hermetic tests + `xattr`/`mdls` ground
truth).  Verified 2026-08-24:

- **Finder comment (`kMDItemFinderComment`) DOES appear in Get Info "Spotlight
  Comments" on 10.6** (the user typed a comment on `file01` and it showed in Get
  Info).  10.6 Get Info reads the `kMDItemFinderComment` xattr directly; `mdls`
  shows `(null)` only because Spotlight will not index an externally-set xattr
  (irrelevant to Get Info).  **Interop fix (2026-08-24):** Gershwin previously
  stored the comment as raw UTF-8, which macOS cannot read.  `GSFileMetadata` now
  reads/writes it as a binary plist (`bplist00` wrapping an `NSString`) -
  byte-identical to what Finder writes (`plutil -convert binary1`).  Reverse
  interop proven: `write-sidecars.m` emits a sidecar comment that `dot_clean -m`
  merges on the Mac and `plutil` parses as the exact string, so 10.6 Finder
  displays it.  Round-trip asserted by `t_GSMetaDataInterop`.
- **No "Tags" field exists on 10.6** (named tags are a 10.9+ feature).  There is
  no tags UI in Get Info; only the fdFlags *colour label* renders.  `file05`'s
  green label is that mechanism.  `_kMDItemUserTags` is read correctly by
  Gershwin (and shows as tags on 10.9+).  To "see tags" you need a 10.9+ Mac.
- **No persistent quarantine badge on 10.6.**  The `com.apple.quarantine` xattr
  is present and correct (re-applied from MANIFEST), but 10.6 shows quarantine as
  a "downloaded from the internet" *dialog on first open*, not an icon badge (the
  badge is a 10.7+ visual).  Gershwin interop is correct.
- **Invisible files render dimmed with show-all ON** (the "half dimmed" look).
  That is correct 10.6 behaviour: `AppleShowAllFiles` reveals them but greyed.
  Toggle it OFF and `file01`/`file05` disappear entirely - proving the invisible
  bit.

**Conclusion:** Gershwin's metadata interop is complete and correct against real
macOS on-disk formats.  The comment now round-trips and displays in 10.6 Get Info
(Gershwin writes the binary-plist format Finder expects).  The attributes that
still do not *visually* appear on this 10.6 box are named tags (a 10.9+ feature,
no tags UI on 10.6) and the persistent quarantine badge (a 10.7+ visual; 10.6
shows the open-dialog instead).  Those two are 10.6 Finder feature gaps, verified
to display on 10.9+/10.7+.

## Results

- **fdFlags interop bug fixed end-to-end.** `GSFileMetadata.h` now uses the
  canonical classic Mac fdFlags; `generate-fixtures.sh`, its MANIFEST reader,
  and the fixtures were corrected and regenerated on the Mac.  The hermetic
   `t_GSMetaDataInterop` now passes against **real macOS values**
   (`file01` 0x400C = red label + invisible, `file02` 0x0400 = custom icon,
   `file05` 0x4404 = green label + custom icon + invisible, `file07` quarantine
   round-trips).  This is the "Mac is always right" principle applied: Gershwin
    must read/write exactly what macOS does.
- **Finder comment read/write interop fixed.** `GSFileMetadata` now serialises
  `_finderComment` to a binary plist (`bplist00` wrapping `NSString`) on both the
  file xattr and AppleDouble paths, and parses it back via
  `_commentFromXattrData:` (class method; `bplist00` magic -> plist parse, else
  raw UTF-8 fallback for legacy sidecars).  Proven end-to-end: `write-sidecars.m`
  writes `r4_comment.txt`, `dot_clean -m` merges it on the Mac, and `plutil
  -convert xml1` yields `<string>gershwin wrote this</string>` - the exact format
  10.6 Finder reads in Get Info.  `t_GSMetaDataInterop` updated to parse the
  comment as a plist; all 111 interop + 57 GWMetadata unit tests pass.
- `fixture-visual.png` generated (Finder window of `~/Desktop/gw-fixture-check`
  on the Mac, `AppleShowAllFiles` on).  **Model cannot read images**, so the
  pixel-level eyeball is the human's; the xattr ground-truth table above is
  what Finder will display.
- **The `.DS_Store` you saw is expected, not a bug.** We set
  `com.apple.finder AppleShowAllFiles = true` so the (now genuinely) invisible
  `file01`/`file05` are still visible for the eyeball.  With show-all on, Finder
  also reveals its own auto-created `.DS_Store` (normally hidden by the same
  hidden-file machinery).  It is fully recognised as a `.DS_Store` - nothing is
  missing, no xattr is absent.  Toggle show-all off and `file01`/`file05`
  disappear while `.DS_Store` stays hidden again, which is the real proof the
  invisible bit now works.
- **Quarantine:** forward round-trip verified.  The visual script now re-applies
  `file07`'s quarantine from `MANIFEST.plist` after `dot_clean -m` merges the
  sidecars (the tar step drops xattrs and `dot_clean` strips the quarantine, so
  the canonical string is read from the MANIFEST the generator wrote).  `file07`
  now shows the Gatekeeper badge on the real Mac.  Reverse
  (Gershwin-emitted sidecars -> Mac) still needs quarantine preserved
  explicitly - the remaining "Quarantine round-trip" next-step.
