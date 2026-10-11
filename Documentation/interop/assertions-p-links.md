# Assertions: P-links (Finder aliases, location files)

Status: [S] public format docs, [F] existing fixture/tool, [M] needs a Mac (OPEN for Scout).

## Alias files
- A1 [S] An alias file is marked by kIsAlias (0x8000 in fdFlags, Finder Info offset 8); a data fork that only looks like a record is not an alias. Test: t_AliasFile "which files count as aliases".
- A2 [S] The record is read from resource 'alis' of the resource fork (xattr user.com.apple.ResourceFork, FreeBSD user namespace, or "._" AppleDouble entry 2), then from the data fork (10.6 bookmark file). Both classic "alis" and "book" payloads parse.
- A3 [S] Resource fork layout per Inside Macintosh (More Toolbox ch.1): 16 byte header, data at 256, map with header copy, type list (count-1), 8 byte type entry, 12 byte reference entry, lengths as 4 byte prefix. The reader rejects out-of-range offsets; the writer output round-trips through the reader. The previous writer emitted an 8 byte reference entry and a type count of 2 (not spec-conformant, never verified on a Mac): fixed.
- A4 Created alias: empty data fork + sidecar (Finder Info kIsAlias, 'alis' fork). Test: t_FSNAliasCreate (was stale: read the data fork).
- A5 [M] OPEN: a 10.6 Finder resolves our created alias (forward fixture exists only for Mac -> us). Needs Scout: copy our file + "._" via a Mac-aware path, double-click.
- A6 [M] OPEN fixtures: alias to a file on another volume made by 10.6 Finder; alias made by 10.6 Finder as seen by xattr (does the data fork carry "book" or stay empty, which resource ids); alias to a folder.

## Location files
- L1 [S] .webloc/.inetloc/.fileloc: plist with string URL; .url: [InternetShortcut] URL=; classic: 'url ' resource (id 256 on Finder-made files). Absolute URL required, no guessing.
- L2 Created .webloc: XML plist {URL}, name from title or host, unique, no "/" ":" or leading dot. Test: t_LocationFile.
- L3 [M] OPEN: a Finder opens a .webloc written by us (expected: yes, plain XML plist); .inetloc with 'url ' only from a Mac.
