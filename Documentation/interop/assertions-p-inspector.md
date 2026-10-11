# Assertions: Inspector "Finder Info" pane (P-inspector)

Tags: [S:] published spec, [F:] bytes Finder wrote, [G:] guess pending the Mac oracle.
Tests: `Tests/Inspector/t_FinderInfoModel.m`.

- MI-INS-1 Hide extension is fdFlags bit 0x0010 in the big-endian word at FinderInfo bytes 8-9. [G: widely reported for Mac OS X; Apple's Finder.h omits it, applefile.h lists 0x0010 as reserved - OPEN, Scout to confirm]
- MI-INS-1a FEATURES.md names 0x0400 for this bit; 0x0400 is kHasCustomIcon, so the table is wrong. [S: Finder.h kHasCustomIcon 0x0400]
- MI-INS-2 Stationery pad is 0x0800, Name locked 0x1000, Invisible 0x4000. [S: Finder.h kIsStationery, kNameLocked, kIsInvisible]
- MI-INS-3 Type code is FinderInfo bytes 0-3, creator code bytes 4-7, plain big-endian four characters; empty field means four zero bytes. [S: FInfo fdType, fdCreator]
- MI-INS-4 A code field is valid when empty or exactly four printable ASCII characters; anything else is refused with an error and nothing is written. [G: Mac OS Roman high bytes are legal but not offered]
- MI-INS-5 Editing flags leaves FinderInfo bytes 10-31 (fdLocation, fdFldr, extended info) untouched. [S: FileInfo layout; cooperative editor rule]
- MI-INS-6 Label colour is fdFlags bits 1-3, 0 = none, 1..7 = Red, Orange, Yellow, Green(4), Blue(5), Purple, Grey, and does not disturb the hide-extension bit. [S: TN1150 / Finder.h kColor]
- MI-INS-7 The Spotlight/Finder comment is kMDItemFinderComment as a binary plist (bplist00) holding one string; an empty comment removes the xattr. [F: 10.6 writes bplist00 string] [G: removal on empty]
- MI-INS-8 A custom icon is stored as a classic resource fork with one 'icns' resource, id -16455, plus kHasCustomIcon 0x0400. [S: Icons.h kCustomIconResource]
- MI-INS-8a The icns holds PNG elements ic07, ic08, ic09 (128, 256, 512 px). [G: PNG-in-icns accepted by 10.6 Finder - OPEN]
- MI-INS-9 Clearing the custom icon clears 0x0400 and removes the resource fork. [S: TN1150 custom icon needs both]
- MI-INS-10 Finder's "Locked" is the user-immutable file flag (BSD UF_IMMUTABLE / uchg, Linux FS_IMMUTABLE_FL), not kNameLocked. [F: Finder Get Info "Locked" sets uchg on 10.6, per the plan's oracle notes] [G: Linux mapping]
- MI-INS-10a A locked file is unlocked for the metadata write and locked again; if locking fails the error is shown, not hidden. [G: fail hard]
- MI-INS-11 Folders: type, creator and stationery are not written (the custom icon is MI-INS-14), because a folder's FinderInfo is a DInfo (bytes 0-7 window rectangle) and Finder keeps a folder icon in an "Icon\r" file. [S: DInfo layout, GSFileMetadata.h]
- MI-INS-12 Name locked is shown and written as its own checkbox (kNameLocked), separate from Locked. [G: whether 10.6 Finder honours it on rename - OPEN]
- MI-INS-10b On Linux the immutable flag is set and cleared by re-executing the application binary under `sudo -A` with `--set-immutable <plist>`; on BSD the owner uses chflags UF_IMMUTABLE directly. [G: D2 = B, Gershwin privileged helper pattern]
- MI-INS-10c The model unlocks before the metadata write and locks again after it, through the locker, and reports a refused unlock or lock. [G]
- MI-INS-13 The privileged action refuses relative paths, symbolic links (never followed), missing files, anything but regular files and folders, and files not owned by the invoking user (SUDO_UID). [G: narrow single-purpose action]
- MI-INS-14 A folder's custom icon is kHasCustomIcon 0x0400 on the folder plus a file named "Icon" and a carriage return inside it: empty data fork, FinderInfo fdFlags 0x4000 (invisible, no 0x0400), the icns as resource 'icns' -16455 in its resource fork. Clearing drops the flag and removes that file. [F: E18, fold shows the icon; fold2 (no 0x0400) does not]
- MI-INS-15 Writing the comment also writes the item's `cmmt` (ustr) record in the parent folder's .DS_Store, replacing only that record (load, patch, save); an empty comment removes only it; an unreadable store is an error, not replaced. [F: E8, Finder writes xattr and cmmt]
