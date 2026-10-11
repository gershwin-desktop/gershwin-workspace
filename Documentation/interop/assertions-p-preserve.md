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

## Volumes a Mac reads through `._` files (referee M3/M8, P-transport)

Tests: `Tests/GWMetadata/t_TransportPolicy.m`, `Tests/GWMetadata/t_VolumeLayout.m`,
`Tests/Preserve/t_TransportCopier.m`, `Tests/Archive/t_GWMetaArchive.m` (MI-AR-29)
(filesystem type injected with +[GSFileMetadata setFilesystemTypeProbe:]).

- MI-PRS-33 One function decides per path: +[GSFileMetadata storesMetadataInAppleDoubleAtPath:] = gs_fs_type_wants_appledouble(gs_fs_type_name(path)); 1 for msdos/msdosfs/vfat/fat*/exfat, cifs/smb/smb2/smb3/smbfs, ntfs/ntfs3/ntfs-3g/fuseblk (fuse./fusefs. prefixes stripped, case ignored), 0 for everything else. [O: E35 for FAT; G for SMB, NTFS, fuseblk - not measurable, no server]
- MI-PRS-34 Type names: Linux statfs magic mapped to mount(8) names, FUSE subtype from /proc/self/mountinfo by device number ("fuse" when absent), an unlisted magic named "0x<hex>"; FreeBSD/OpenBSD f_fstypename; Windows GetVolumeInformationW. [S]
- MI-PRS-38 Only a path that cannot be examined (statfs/GetVolumeInformation fails) is an error: a save or copy fails, a read returns nil. An identified but unlisted type (plain FUSE, unknown magic) keeps the native behaviour. [D: coordinator 2026-10-11]
- MI-PRS-35 Saving metadata there writes only the `._` sidecar even when the mount accepts attributes; no com.apple attribute is set. [O: E35 the kernel shows the `._` content as the xattrs; G for SMB]
- MI-PRS-36 A later save there keeps the sidecar; it is never migrated into attributes and deleted as on a native disk. [G]
- MI-PRS-37 Reading there takes the sidecar first; attributes a Linux tool left on the mount only fill fields the sidecar lacks. [G]
- MI-PRS-43 Every sidecar written there has the kernel's layout: entry 9 at 50 with ATTR (debug tag 3b9ac9ff, total_size = end of entry 9, attributes in file order, new ones appended), zero padded so that header + entry 9 + 286 is a multiple of 4096 (3760, or 7856 for a 5000-byte attribute); entry 2 the fork or the 286-byte empty map. Parse and rewrite of all eight E35 `._` files is byte identical. [O: E35]
- MI-PRS-44 The kernel's 286-byte empty map in entry 2 reads as no resource fork. [O: E35 xattr -l shows no ResourceFork for such files]
- MI-PRS-45 A quarantine set on an item there is stored plain (no q/), as the kernel stores it. [O: E35 big.txt]
- MI-PRS-39 A copy or move onto such a volume puts every attribute of the source into the sidecar (also with attributes supported), merged over the source sidecar, except com.apple.quarantine, which Finder never carries; a quarantine-only source gets no sidecar. [O: E35, E16]
- MI-PRS-40 A kernel-made source sidecar copied to such a volume arrives byte for byte (it is rewritten in the same layout). [O: E35]
- MI-PRS-46 An archive extracted onto such a volume keeps each companion as the item's sidecar, in the kernel's layout, without quarantine; nothing becomes an attribute. [O: E35]
- MI-PRS-41 A copy with a Finder comment onto such a volume writes the cmmt record into that folder's .DS_Store and gives the store the invisible `._.DS_Store` the kernel writes (byte equal to E35 lf/._.DS_Store); no attribute. [O: M2, E35]
- MI-PRS-47 A sidecar that cannot be written on an SMB mount fails the save, copy or extraction with an error naming fruit:veto_appledouble; nothing falls back to attributes. [D: coordinator 2026-10-11]
- MI-PRS-42 Native destinations (ext4, tmpfs, ...) are unchanged: attributes, no sidecar. [S]
- MI-PRS-19 (changed) The sidecar quarantine on a destination without attributes that a Mac does not read (OpenBSD) carries the q/ prefix, as GSFileMetadata's compact sidecar writer does. [fb800d91]
- NOT DONE: other .DS_Store writers (view settings in Workspace/FileViewer, DSStore/) do not create `._.DS_Store` on such volumes; the Mac does not need it to read the store.

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
