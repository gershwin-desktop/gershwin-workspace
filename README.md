# Workspace

Workspace is Gershwin's Workspace Manager and offers a File Manager and an optional Desktop with associated services and tools.

* Classical column browser view
* List view
* Icons view with possibility of Thumbnails

Trash (stand-alone or integrated in Desktop's Dock)

Desktop (can be shown or hidden) with Dock to keep order in favourites and running applications.

Contents inspector with image previewing and extensible through plug-in bundles.

Volume checking and unmounting.

Optional search (database backed) and live folders.

Workspace implements NSWorkspace, so it offers to GNUstep applications services to open files through it as well as copy and recycle operations.

Workspace implements a [Spatial](https://arstechnica.com/gadgets/2003/04/finder/) mode.

## Info.plist keys read by Workspace

* `GSX11WindowClass` (string or array of strings): for a `.app` bundle that wraps a non-GNUstep program, the `WM_CLASS` instance or class the program's windows carry when it differs from the bundle's name (for example `vlc` for `VLC media player.app`). The Dock uses it to recognise the program's windows when it did not start the program itself, e.g. after Workspace restarted. Case, spaces, hyphens and underscores are ignored, so `Brave Origin.app` needs no key for `brave-origin`. Windows are never tied to an application by their title.
