# Assertions - P-archive (zip, tar and ditto archives exchanged with a Mac)

One behaviour per line. Tests: `Tests/Archive/t_GWMetaArchive.m`. Code:
`GWMetadata/GWMetaArchive.m` (used by `Workspace/GWArchiveOperation.m`).
Tags: `[S:]` spec, `[F:]` bytes a real Mac wrote, `[O:]` observed, `[G:]` guess.
The AppleDouble bytes in the extraction tests are the real 10.6 `._` files of
E15 (`Tests/GWMetadata/interop/fixtures/finder106/E15-appledouble-ditto`).
The archives around them are built by the test; no archive a Mac wrote is in
the repository (see Mac captures needed below).

## Extraction

- MI-AR-1 A zip with `__MACOSX/._name` entries (Finder "Compress") extracts and the data fork is intact. [F: E15 bytes; zip layout S]
- MI-AR-2 FinderInfo, every ATTR attribute (comment, empty value, 300 byte value, other programs' names) are applied as user.* attributes. [F: E15 many.txt]
- MI-AR-3 The resource fork (custom icon) is applied. [F: E15 rsrc.txt]
- MI-AR-4 A folder's `__MACOSX/.../._folder` is applied to the folder; the directory entry ends in a slash, the companion's name does not. [F: E15 dir]
- MI-AR-5 Nested items get their own companion (`__MACOSX/dir/._name`). [S]
- MI-AR-6 No `__MACOSX` folder and no `._` file is left where attributes work. [G]
- MI-AR-7 An item without companion gets no metadata. [G]
- MI-AR-8 With two top-level items nothing is stripped and a folder keeps its label. [G]
- MI-AR-9 tar / ditto / cpio archives with `._name` beside the item give the item the same metadata, and the companion is not extracted. [F: E15 says tar and ditto layouts are the same]
- MI-AR-10 A file named `._x` that is not AppleDouble (no magic) is extracted as a file. [G: not ours to drop]
- MI-AR-11 A read-only item in the archive gets its attributes and stays read-only. [G]
- Volume without attributes (or a value that does not fit, E2BIG/ENOSPC): all metadata stays in the `._` sidecar next to the item, the way a Mac keeps it there. Any other failure aborts the extraction with an error (code 17). [G]
- MI-AR-20 The real 10.6 Finder zip (E29 proj-labelled-folder-finder.zip) extracts; labeled.txt gets FinderInfo, 70 KB icon fork and comment (too big for ext4 attributes, so all of it stays in the sidecar byte for byte). [F: E29]
- MI-AR-21 When the archive's single top folder is stripped, its `__MACOSX/._proj` (Finder writes it only when the folder has a label; ditto --keepParent writes none) is applied to the folder extracted into. [F: E29]
- MI-AR-22 The zipped `.DS_Store` is the folder's own store and is extracted; its companion (FinderInfo 0x4000, invisible) is applied. [F: E29]
- MI-AR-23 A `.DS_Store` that already exists where the archive would write one is kept. [G: the user's view settings win]
- MI-AR-24 The real ditto zip (no `._proj`) leaves the folder extracted into without FinderInfo; labeled.txt and subfolder get theirs. [F: E29]
- MI-AR-26 A folder that existed before the extraction never gets the top folder metadata (Workspace always creates a new folder; the API can be called with an existing one). [G]
- MI-AR-27 A quarantine value goes into a companion with the "q/" prefix 10.6 needs, never doubled (GSFileMetadata sidecarQuarantine:). [F: Referee]
- MI-AR-28 Extraction strips "q/" into the plain xattr (GSFileMetadata plainQuarantine:). [F: Referee]
- MI-AR-25 A companion whose only content is an all-zero FinderInfo sets nothing (and none is written on compression). [F: E29 listing, 82-byte companions]

## Compression

- MI-AR-12 `__MACOSX/<dir>/._name` is written for every item that carries metadata. [S: ditto --sequesterRsrc]
- MI-AR-14 It is AppleDouble v2 with exactly entries 9 then 2, FinderInfo 32 bytes at entry 9 (ATTR block behind it when there are attributes). [F: E15, E17]
- MI-AR-15 FinderInfo and resource fork are those of the file (label, custom icon flag, icon fork). [F: E18]
- MI-AR-16 All user.* attributes travel, not only those GSFileMetadata models (comment, tags, quarantine, other programs'). A FinderInfo of a length other than 32 is not emitted (10.6 drops it, E17). [F: E15, E17]
- MI-AR-17 A folder with a label gets `__MACOSX/<dir>/._folder`. [F: E15 dir]
- MI-AR-18 An item with no metadata (no attributes, FinderInfo absent or all zero) gets no companion. [O: E15, ditto wrote none for plain files; G for the all-zero case]
- MI-AR-19 Compress then extract is the identity for FinderInfo, resource fork, other attributes and folder labels. [G]
- A `._` sidecar next to an item on a volume without attributes is the base of its companion; attributes win over it. [G]

## OPEN

- OPEN-1 (closed by E29) Finder writes `__MACOSX/._<folder>` only for a labelled folder; the label goes on the destination folder.
- OPEN-2 Names: Mac zips may store file names in NFD and 10.6 ditto zips use a different Unicode form than ours. Not handled; names are used as stored.
- OPEN-3 `ditto -c -k` skipped `._one.txt` for a file with xattr but no FinderInfo (E15, unexplained); we write one. Harmless on extraction.

## Mac captures needed (Scout)

1. `ditto -c -k --sequesterRsrc --keepParent proj proj.zip` and Finder "Compress" of the same folder (right click) on 10.6, for a folder `proj` holding: file with label + comment + custom icon, a file with only a comment, a plain file, a subfolder with a label and custom icon (`Icon\r`), a file with a 300 byte xattr. Fetch both zips unchanged to `Tests/GWMetadata/interop/fixtures/finder106/E29-zips/` and list the entries with `unzip -l` and `zipinfo -v` (does `__MACOSX/` itself, `__MACOSX/._proj`, extra fields, UNIX attributes appear).
2. Our output: `GWMetaArchive` zip of the same tree (`Tools/mac-metadata-interop/write-sidecars` with the zip option), unzipped on the Mac with `unzip`, `ditto -x -k` and Finder double click; report with `xattr -l`, label, icon and comment per item whether the metadata arrived (does the 10.6 Archive Utility apply `._` with an ATTR block and entry 2 of length 0).
3. Same for `tar` (`COPYFILE_DISABLE` unset) of the tree, extracted by us.
