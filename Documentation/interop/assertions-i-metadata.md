# Assertions - I-metadata (GSFileMetadata writes, flags, provider)

Tests: `Tests/IMetadata/t_IMetaWrite.m`, `Tests/IMetadata/t_IMetaProvider.m`.
Tags: `[S:]` spec/documented, `[F:]` bytes a real Mac wrote, `[O:]` observed,
`[G:]` guess.

- MI-META-1 Rewriting a sidecar keeps entries and attributes we do not manage (merge via GSAppleDouble). [G: data loss otherwise]
- MI-META-2 A nil or empty Finder comment removes the comment xattr and the sidecar record. [G: stale comment would reappear]
- MI-META-3 -setCustomIconData: stores a classic resource fork with one 'icns' resource, ID -16455, not the raw icns bytes. [S: Inside Macintosh, More Macintosh Toolbox, Resource Manager, resource file format; ID -16455 = custom icon resource]
- MI-META-3 An 'icns' resource with another ID is not the custom icon. [S]
- MI-META-4 A fork that is a bare icns container (stored by older versions) is still read. [G: existing files]
- MI-META-5 After -clearCustomIcon a write removes the ResourceFork xattr; a sidecar write carries no fork. [G]
- MI-META-6 extensionHidden is fdFlags 0x0010 (kExtensionIsHidden); nameLocked is 0x1000 (kNameLocked), independent bits. [S: Finder.h; Scout confirmation pending S13 for 10.6 behaviour - G until then]
- MI-META-7 GWMetadataProvider answers -labelIndexForPath:, -labelNameForPath:, -commentForPath:, -isExtensionHiddenForPath:, -isNameLockedForPath: from GSFileMetadata. [G]
- MI-META-8 Answers come from GSFileMetadata's path cache until -invalidateCaches. [G: no extra syscalls per row]

NOT DONE: icon preview of PNG-in-icns forks on 10.6 (Scout S13); folder custom icon layout (Icon\r file).
