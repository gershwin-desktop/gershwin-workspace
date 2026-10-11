# Assertions: P-undo (Edit > Undo / Redo of file operations)

Status: [S] Finder behaviour as documented / commonly known, [T] covered by a test in `Tests/Undo`, [M] needs a Mac (OPEN for Scout).

## What is undoable
- U1 [S][T] Undoable: move (drag between folders, cut and paste, drag out of the Trash), copy, duplicate, rename, move to Trash, make alias, new folder. Not undoable: delete, empty Trash, symbolic link, new file. Test: t_UndoRecord "which operations are undoable".
- U2 [T] An operation that did nothing (cancelled, every item failed) leaves no record. A stopped operation records what it had done until then.
- U3 [S][T] History: a stack of 20 operations (Finder 10.6 keeps one; more is harmless because every level is checked against the disk before use). Undo moves the record to the redo list; a new action clears the redo list; a redo pushes a fresh record and keeps the rest of the redo list. Test: t_UndoStack.

## What undo and redo do
- U4 [T] Move: undo moves the items back into the folder they came from; redo moves them again. Metadata (extended attributes, "._" sidecar, whatever else GWMetadataCopier carries) travels because undo runs as an ordinary move through GWMetadataCopier. Test: t_UndoOperations "move".
- U5 [S][T] Copy, duplicate, make alias, new folder: undo moves what was made to the Trash (Finder does not delete on undo); redo performs the operation again (a duplicate may get a new name, which the next undo uses).
- U6 [T] Rename: undo renames back, redo renames again; rename now moves the "._" sidecar along (it used NSFileManager -movePath:, which left the sidecar under the old name).
- U7 [S][T] Move to Trash: undo puts every item back to its original folder under its original name, also when the Trash had to rename it ("x_copy") because it already held an item of that name; the other item in the Trash stays. Redo moves them to the Trash again.
- U8 [T] Undo and redo run through the Operation controller (progress window, locking, change notifications) and never ask for confirmation; an operation started by undo or redo is not itself recorded as a new action.

## Refusals
- U9 [T] Nothing is guessed. Undo is refused with an alert ("The operation cannot be undone." plus the reason) when: an item the operation produced is gone; the path holds a different item now (device and inode differ); the name it goes back to is taken (a dangling symbolic link counts); the folder it goes back to is gone. Redo is refused when an original is gone or a destination name is taken. A refusal changes nothing on disk and keeps the record, so the user can clear the way and try again.
- U10 Known limit: device and inode identify an item; a file deleted and recreated under the same name can get the old inode back (the filesystem reuses it), which the check cannot tell apart.

## Menu
- U11 [S][T] Titles name the action: Undo/Redo Move of "x", Copy of "x", Duplicate of "x", Rename of "x" (old name), Move of "x" to Trash, Make Alias of "x", New Folder; several items: "... of N Items". Plain "Undo"/"Redo", disabled, when there is nothing. Localized in every Workspace lproj (Undo %@ / Redo %@ plus the action phrases).
- U12 [M] OPEN: exact Finder 10.6 wording per language (we use our own wording, e.g. German "Widerrufen: Bewegen von ...").
