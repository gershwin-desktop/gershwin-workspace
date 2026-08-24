# Metadata Interoperability Testing (macOS <-> Gershwin)

Status: **bidirectional interop green** (2026-08-24).

- Forward  (Mac -> Gershwin): fixtures generated from a real Mac parse
  perfectly - 110 automated checks in `Tests/GWMetadata` (42 of them
  interop).
- Reverse  (Gershwin -> Mac): sidecars written by Gershwin are ingested on
  macOS via `dot_clean -m` and every field matches - 6/6 in
  `Tools/mac-metadata-interop/verify-reverse.sh`.

## Goal

Prove, against a real Mac, that gershwin-workspace's metadata stack
(`GSAppleDouble`, `GWMetaXattr`, `GSFileMetadata`, MDKit) reads and writes
metadata exactly like macOS does.

The reference machine is a Mac mini on the LAN running macOS 10.6.8
(Snow Leopard) - see the `gershwin-remote-systems` skill for access
(credentials are NOT recorded here or anywhere in the tree; they come from
environment variables only).

## Layout

Anything needing a live Mac lives in its own directory and is driven by
environment variables; everything under `Tests/` is hermetic (offline,
deterministic, fixture-based):

```
Tools/mac-metadata-interop/generate-fixtures.sh   REQUIRES a Mac (forward)
Tools/mac-metadata-interop/write-sidecars.m       writer for reverse check
Tools/mac-metadata-interop/verify-reverse.sh      REQUIRES a Mac (reverse)
Tests/GWMetadata/interop/t_GSMetaDataInterop.m    hermetic gnustep-test
Tests/GWMetadata/interop/fixtures/                generated, gitignored
Tests/GWMetadata/interop/fixtures/MANIFEST.plist  ground truth from macOS
```

### Regenerating fixtures

```sh
export MAC_HOST=Users-Mac-mini.local   # hostname, never an IP literal
export MAC_USER=user
export MAC_PASS=...                    # never commit this
./Tools/mac-metadata-interop/generate-fixtures.sh
```

The script builds six files on the Mac using only native tools
(`xattr`, python 2.6 + pyobjc-xattr, `plutil`, `..namedfork/rsrc`,
`mdimport`), captures what macOS itself reports into `MANIFEST.plist`
(XML plist, read back via `xattr`/`mdls`/`plutil` - not what we commanded),
packages them with `ditto --sequesterRsrc` so macOS embeds real AppleDouble
`._` sidecars into the zip, ships it here, and relocates
`__MACOSX/._* -> ._*` beside each data file.

Fixture matrix:

| file                    | FinderInfo | resource fork | tags | comment |
|-------------------------|-----------|---------------|------|---------|
| file01_finderinfo.txt   | TEXT/ttxt, red label, invisible | - | - | - |
| file02_resourcefork.txt | custom-icon bit | CAFEBABE | - | - |
| file03_tags.txt         | - | - | Red, ProjectX | - |
| file04_comment.txt      | - | - | - | yes |
| file05_combined.txt     | TEXT/ttxt, label+icon+invisible | DEADCODE | Green, Release | yes |
| file06_control.txt      | no metadata at all (negative case) | | | |

Run the tests:

```sh
cd Tests/GWMetadata && gnustep-tests .
```

Without staged fixtures the test skips cleanly, so CI without a Mac stays
green.

## Results (2026-08-24)

Forward: all 42 interop assertions pass, plus the pre-existing GWMetadata
unit tests (110 total, zero compiler warnings).  Reverse: 6/6.

What was verified end to end, Mac-produced bytes -> GNUstep objects:

- AppleDouble V2 parsing of real `._` sidecars, including Apple's
  `"Mac OS X"` filler (not zeros).
- Classic entry layout: entry 9 = 32-byte FinderInfo, entry 2 = resource
  fork.  Type/creator codes, Finder flags (fdFlags), colour label bits,
  invisible and custom-icon bits all round-trip.
- fdFlags byte order: big-endian on disk, as TN1150 specifies.
- Resource forks byte-exact (`..namedfork/rsrc` written data == what
  GSFileMetadata returns after the ditto round-trip).
- Finder tags (`com.apple.metadata:_kMDItemUserTags`) stored by macOS as a
  binary plist inside the ATTR blob decode to the exact string arrays.
- Finder comments (`com.apple.metadata:kMDItemFinderComment`) survive.
- Negative case: a file without any sidecar yields nil metadata.

Reverse (Gershwin-written `._` sidecars -> macOS via `dot_clean -m`):

- Gershwin now EMITS the macOS ATTR-blob layout when tags/comments are
  staged (`GSAppleDouble -appleDoubleData`): entry order FinderInfo(9)
  first / ResourceFork(2) last, "Mac OS X" filler, ATTR header at
  FinderInfo+34, records then packed values, `total_size = dstart+dlen`.
  Byte-layout verified field-by-field against a Mac-produced sidecar for
  identical logical metadata (only debug_tag=0 and the plist encoder's
  exact bytes differ; both irrelevant to readers).
- After `dot_clean -m`, macOS holds exactly what Gershwin wrote:
  type/creator codes, fdFlags label/invisible/custom-icon bits,
  byte-exact resource forks, tag lists decoded from our binary plists,
  and Finder comments.
- Emitted classic shape (no xattrs) unchanged: bare 32-byte entry 9 +
  resource fork entry - covered by hermetic structural checks so the
  emitter cannot silently regress without a Mac.

## Findings that required Gershwin changes

1. **Apple's ATTR extended-attribute blob** (implemented in
   `GSAppleDouble.m`).  When a file carries xattrs, macOS stops using the
   classic entries for them and instead extends AppleDouble entry 9 to:
   32-byte FinderInfo + 2 bytes padding + a 36-byte `ATTR` header
   (magic `0x41545452`, big-endian fields) followed by 4-byte-aligned
   records of `{offset(4, absolute), length(4), flags(2), namelen(1 incl.
   NUL), name}` whose values live at absolute offsets in the file.
   Previously GSAppleDouble would have handed out the whole >32-byte
   entry 9 as if it were FinderInfo and silently lost tags/comments.
2. **ATTR emission** for the reverse direction (same file): staged xattrs
   switch `-appleDoubleData` to the macOS layout; FinderInfo and the
   resource fork stay in their classic slots, exactly like Mac-produced
   files.  The private 0x9001 tags entry is no longer emitted (it is
   still READ for backwards compatibility with old sidecars).
3. **Over-release fix** in the parser: truncated xattr names must not be
   released twice (found by the test run aborting at exit).

## Findings about macOS 10.6 behaviour worth remembering

- 10.6's `/usr/bin/zip` does NOT store xattrs/resource forks; use
  `ditto -c -k --sequesterRsrc` (that is what produces `__MACOSX/._*`).
- `xattr -w` cannot take binary or stdin values on 10.6 (no `-f`); use the
  python `xattr` module instead.
- python 2.6 quirks: `plistlib` writes XML only (convert with
  `plutil -convert binary1`), `str` indexing gives chars not ints,
  no `subprocess.check_output`.
- `mdls -raw` with multiple `-name` flags separates values with NUL bytes.
- Spotlight ignores `/tmp`; build fixtures in `$HOME` and force
  `mdimport <file>` (a fresh directory needs a cycle or two).
- An externally-set `kMDItemFinderComment` NEVER surfaces in the Spotlight
  index on 10.6 (`kMDItemComment` stays null even after `mdimport`); only
  comments set through Finder itself appear there.  Our xattr-level
  round-trip works regardless.
- Spotlight types files carrying a resource fork as
  `com.apple.alias-file`.

## Next steps

- Quarantine xattr (`com.apple.quarantine`) round-trip (both directions;
  note copyfile special-cases its encoding).
- More Spotlight attributes (WhereFroms, UserTags as Spotlight sees them
  on a modern macOS reference box).
- Drive the Mac over VNC to eyeball Finder labels/tags on the fixtures.
- Zip-level interop through GWMetaArchive now that appleDoubleData emits
  ATTR blobs (`archive_entry_set_mac_metadata` consumers).
