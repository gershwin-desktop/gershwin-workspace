# Assertions - P-preserve (extended attributes, sidecars, copy/move)

One behaviour per line. Tests: `Tests/Preserve/t_ADPreserve.m`,
`Tests/Preserve/t_MetadataCopier.m`. Tags: `[S:]` spec/documented behaviour,
`[F:]` bytes a real Mac wrote, `[O:]` observed, `[G:]` guess.
No real 10.6 fixtures were available (`Tests/GWMetadata/interop/fixtures`
is absent), so no line is `[F:]` yet; layout lines carry `[O:]` from one
Mac-written `._` file seen on the build machine (modern macOS, not stored).

## AppleDouble rewrite keeps what it does not understand

- MI-PRS-1 A sidecar holding only an unknown entry id is rewritten, never dropped. [G: data loss otherwise]
- MI-PRS-2 Unknown entry ids next to FinderInfo and ATTR survive a rewrite byte for byte. [S: AppleDouble v2, entry ids are open ended]
- MI-PRS-3 An ATTR name unknown to us keeps its value bytes; com.apple.quarantine is carried unchanged. [S: ATTR layout, copyfile]
- MI-PRS-3 A zero-length ATTR value is kept as an attribute with an empty value. [G: marker attributes exist]
- MI-PRS-4 Bytes behind the 32 FinderInfo bytes that are not an ATTR blob are kept. [G: foreign writer]
- MI-PRS-5 Parse, rewrite, parse is the identity on every entry and attribute. [G]
- MI-PRS-10 Merging fresh content over an existing sidecar replaces entries 9 and 2 and the managed attributes, and keeps every other entry and attribute. [G]

## Layout of what we write for a file with attributes

- MI-PRS-6 Magic 00 05 16 07, version 00 02 00 00, filler "Mac OS X" + 8 spaces. [O: 2026-10-11 one modern-macOS ._ file]
- MI-PRS-7 Two entries: FinderInfo (9) first, resource fork (2) second, entry 2 present even when empty. [O: same]
- MI-PRS-8 ATTR magic sits at entry 9 + 32 + 2; total_size is the absolute end of entry 9. [O: same]
- MI-PRS-9 ATTR records are 4-byte aligned (11 + name incl. NUL); data_start and record offsets are absolute file offsets; data_length is the sum of the value sizes. [O: same]
- NOT DONE: modern macOS pads entry 9 and the file to 4096 bytes and writes a non-zero debug_tag (file id); 10.6 unknown. See OPEN-1.

## Copy, duplicate, move across filesystems

- MI-PRS-11 A copy carries com.apple.quarantine, FinderInfo, ResourceFork, tags (name with colon), arbitrary user.* names and empty values. [S: copyfile COPYFILE_XATTR]
- MI-PRS-11 No sidecar appears where attributes work. [S: INTEROPERABILITY.md section 4]
- MI-PRS-12 Duplicate carries all attributes. [S]
- MI-PRS-13 Folder copies carry the attributes of the folder and of every item below it. [S]
- MI-PRS-14 Attributes reach a read-only copy and the copy stays read-only. [G]
- MI-PRS-15 Symbolic links and files without metadata are skipped; no empty sidecar is created. [G]
- MI-PRS-16 A move across filesystems carries all attributes and removes the source only afterwards. [S]
- MI-PRS-17 A move whose metadata cannot be carried fails with an error and leaves the source. [G: never lose the only complete copy]
- MI-PRS-18 A rename within a filesystem needs nothing. [S]

## Destination without extended attributes

- MI-PRS-19 All attributes go into a `._` sidecar: FinderInfo in entry 9, resource fork in entry 2, the rest as ATTR records under their Mac names (no "user." prefix); nothing is also written as an attribute. [S: INTEROPERABILITY.md section 4]
- MI-PRS-20 A source sidecar is carried byte for byte, to destinations with and without attributes. [G]
- MI-PRS-21 Source attributes are merged into the carried sidecar; entries and attributes only the sidecar had are kept. [G]

## Platform wrapper

- MI-PRS-23 When storing an attribute fails with E2BIG or ENOSPC, all metadata of the item goes into the sidecar and attributes already written are removed; any other errno fails hard. [D: user decision 2026-10-11, OPEN-3 option A; GSFileMetadata does the same]
- MI-PRS-22 gs_xattr_list_for_path returns an empty list for a file with no attributes (and on filesystems without), lists empty-valued attributes, and returns NULL only on failure. [G]
- Only the "user" namespace is copied (Linux: user.*; FreeBSD: EXTATTR_NAMESPACE_USER). OpenBSD has none: every copy takes the sidecar path. [S: GWMetaXattr.m]

## Comment record in the destination folder (referee M2)

- MI-PRS-24 A copy of an item with a Finder comment writes the cmmt record for its name into the destination folder's .DS_Store. [O: referee 2026-10-11 M2, Finder 10.6 shows a comment only with the record]
- MI-PRS-25 A duplicate gets its own cmmt record; other records and positions in the store stay. [O: M2]
- MI-PRS-26 A move into another folder writes the record there. [O: M2]
- MI-PRS-27 A move across filesystems writes the record there. [O: M2]
- MI-PRS-28 An item without a comment leaves no .DS_Store behind. [G]
- MI-PRS-29 An unreadable destination .DS_Store is reported, never replaced; the copy stays. [G]
- MI-PRS-30 The shared writer (+[DSStore setComment:forItemAtPath:error:]) creates, replaces and removes only that record. [O: INS E8]
- MI-PRS-31 Every item of a copied folder with a comment gets its cmmt record in the .DS_Store of the folder it sits in; items without a comment get none. [O: M2]
- MI-PRS-32 A move or rename removes the old name's cmmt record from the source folder's .DS_Store (other records stay), within and across filesystems. [G: Finder drops it; a stale record would show on a new item of that name]
