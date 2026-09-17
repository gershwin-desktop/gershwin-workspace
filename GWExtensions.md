# GWorkspace Extensions (`.gwext` bundles)

This documents the **GWorkspace extension** mechanism: how to write a loadable
add-on (a "plugin") for the Gershwin Workspace without touching Workspace or
FSNode source. The reference implementation is `GitContextMenu/` (adds a `Git`
context-menu submenu and a badge on git-repository folders). Read that folder
alongside this file.

## Name and concepts

- **Extension** = a GNUstep *bundle* with the file extension **`.gwext`** (note
  the leading dot, matching the `.inspector` convention used by the Inspector).
- The bundle's **principal class** conforms to the **`GWorkspaceExtension`**
  protocol (`Workspace/GWorkspaceExtension.h`).
- A single manager, **`GWExtensionsManager`** (`Workspace/GWExtensionsManager.{h,m}`),
  discovers the bundles, instantiates each once, and fans requests out to them.
- The core (Workspace, FSNode) contains **no application-specific knowledge**
  about any extension. An extension decides for itself what nodes it cares
  about (e.g. "folders containing a `.git`"). This is deliberate: git support,
  or any other feature, lives entirely in its bundle.

Two integration points exist today:

1. **Context menu** — append items to the right-click / action menu of a node
   selection (`GWorkspaceExtension` menu methods).
2. **Node-icon badge** — supply a small overlay image for an `FSNode`
   (`badgeImageForNode:`), drawn on icon views and the desktop.

## The protocol

Defined in `Workspace/GWorkspaceExtension.h`. Every method is `@optional`;
implement only what you need.

```objc
@protocol GWorkspaceExtension <NSObject>
@optional

// Return YES to be given a chance to append menu items for this selection.
- (BOOL)extensionCanHandleNodes:(NSArray *)nodes;

// Append your NSMenuItems to `menu`. `nodes` is an NSArray of FSNode.
- (void)extensionAppendToContextMenu:(NSMenu *)menu
                           forNodes:(NSArray *)nodes;

// Return an NSImage (typically 16x16) to overlay on the node's icon, or nil.
- (NSImage *)badgeImageForNode:(FSNode *)node;
@end
```

### How the menu is wired

`Workspace/Workspace.m` builds its own context menu in `contextMenuForNodes:...`
and, just before returning, hands the assembled menu to the manager:

- `Workspace.m:4775` — `[[GWExtensionsManager defaultManager]
  appendContextMenuItems: menu forNodes: nodes];`

The manager calls `extensionCanHandleNodes:` on each loaded extension; if it
returns YES, it calls `extensionAppendToContextMenu:forNodes:`.

### How the badge is wired

Badges go through FSNode's existing **`FSNodeRepDecorationDelegate`** protocol
(`FSNode/FSNodeRep.h:353`), which the manager adopts
(`GWExtensionsManager <FSNodeRepDecorationDelegate>`). At startup Workspace
installs the manager as FSNode's decoration delegate:

- `Workspace.m:814` — `[fsnodeRep setDecorationDelegate:
  [GWExtensionsManager defaultManager]];`
- `Workspace.m:815` — `[[GWExtensionsManager defaultManager] loadExtensions];`

`FSNIcon` (`FSNode/FSNIcon.m`) asks the delegate for a badge in `setNode:` and
draws it top-right in `drawRect:`. **Badges render only on `FSNIcon`-based
views (icon view and the desktop), not on list/column views** — that is a known
v1 limitation of the cell, not the extension API.

## Discovery and loading

`GWExtensionsManager -loadExtensions` (`GWExtensionsManager.m:43`):

- Searches every `NSLibraryDirectory` across **all domains**
  (`NSAllDomainsMask`) for a `Bundles/` subdirectory.
- A bundle is loaded iff its name has suffix **`.gwext`**
  (`GWExtensionsManager.m:63`, matched via `hasSuffix:` so base names may
  contain other dots).
- Its `principalClass` must conform to `GWorkspaceExtension`; otherwise it is
  skipped.
- The manager instantiates the principal class once (`[[principalClass alloc]
  init]`) and retains it for the process lifetime.

Bundles are loaded once, at Workspace startup. There is no unload/reload UI.

## Writing a new extension bundle

Create a subfolder, e.g. `MyExtension/`, with `MyExtension.h/.m` and a
`GNUmakefile` (the static, force-added file — see below).

### GNUmakefile (static, must be force-added)

`GitContextMenu/GNUmakefile` is the canonical template. Key points:

```make
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM        # always SYSTEM, never LOCAL

BUNDLE_NAME = MyExtension
MyExtension_PRINCIPAL_CLASS = MyExtension
MyExtension_OBJC_FILES = MyExtension.m

ADDITIONAL_GUI_LIBS += -lFSNode
ADDITIONAL_INCLUDE_DIRS += -I../Workspace    # for GWorkspaceExtension.h
ADDITIONAL_INCLUDE_DIRS += -I../FSNode

BUNDLE_EXTENSION = .gwext                    # leading dot, required
BUNDLE_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Bundles

include $(GNUSTEP_MAKEFILES)/bundle.make
```

- `BUNDLE_EXTENSION` **must be `.gwext`** (with the dot). A missing dot makes
  the bundle install as `MyExtensiongwext` and the scanner never finds it.
- `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM` and install only to SYSTEM.
- Link `-lFSNode` and include `-I../Workspace` (for the protocol header) and
  `-I../FSNode`.
- The build artifact (`MyExtension.gwext/`) is gitignored; the `GNUmakefile`
  itself is also normally gitignored, so **`git add -f` it**.
- Add the subproject to the **root `GNUmakefile.in`** `SUBPROJECTS` list (edit
  the `.in` template, not the generated `GNUmakefile`):

  ```
  SUBPROJECTS = ... GitContextMenu MyExtension
  ```

  Then `./configure` (or `make` with `PACKAGE_NEEDS_CONFIGURE=YES`) regenerates
  the root `GNUmakefile`, and a plain `make` builds your bundle.

### Building out-of-tree (separate repo, no Workspace source)

You do **not** need the Workspace or FSNode source trees to build a `.gwext`.
The extension API is deliberately Workspace-free: the protocol imports only
Foundation, AppKit, and `FSNode.h`, and everything you link against is already
installed by the Gershwin stack in the SYSTEM domain.

Prerequisites (all satisfied by an installed Gershwin system):

- FSNode public headers:
  `/System/Library/Frameworks/FSNode.framework/Headers/FSNode.h`
- FSNode library: `/System/Library/Libraries/libFSNode.so`, so a bare
  `-lFSNode` resolves with no `-L` workaround.

The one piece not yet published as an installed header is `GWorkspaceExtension.h`
(it still lives only in `Workspace/` source). Until it is installed, copy that
single file into your project (it is 38 lines and has no Workspace-internal
imports) and `#import` it locally. In-tree builds instead pass `-I../Workspace`.

Standalone `GNUmakefile` (no `PACKAGE_NAME`, no root `GNUmakefile.in`, no
`SUBPROJECTS` wiring — it is a self-contained bundle project):

```make
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM        # always SYSTEM, never LOCAL

BUNDLE_NAME = MyExtension
MyExtension_PRINCIPAL_CLASS = MyExtension
MyExtension_OBJC_FILES = MyExtension.m

# FSNode is installed in SYSTEM, so a bare -lFSNode resolves.
ADDITIONAL_GUI_LIBS += -lFSNode
# FSNode public headers + your local copy of GWorkspaceExtension.h.
ADDITIONAL_INCLUDE_DIRS += -I/System/Library/Frameworks/FSNode.framework/Headers
ADDITIONAL_INCLUDE_DIRS += -I.              # for the copied GWorkspaceExtension.h

BUNDLE_EXTENSION = .gwext
BUNDLE_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Bundles

include $(GNUSTEP_MAKEFILES)/bundle.make
```

Build and install from your repo:

```sh
make
sudo make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
```

Restart Workspace to load the new bundle. Compared with the in-tree template,
the only differences are: no `PACKAGE_NAME = gworkspace`, no `-I../Workspace` /
`-I../FSNode` sibling paths (use the installed FSNode include path instead), no
root `GNUmakefile.in` / `SUBPROJECTS` registration, and no
`-L../FSNode/FSNode.framework` workaround (unnecessary here because FSNode is
installed).

### Principal class

```objc
#import "GWorkspaceExtension.h"
#import "FSNode.h"

@interface MyExtension : NSObject <GWorkspaceExtension>
@end
```

No nib is required; the principal class is a plain `NSObject` subclass. It is
allocated once at load time, so instance state is shared process-wide. Keep an
eye on thread safety if you spawn async work (see below).

### Context-menu pattern

To pass data back to your action method, stash it on the menu item:

```objc
- (BOOL)extensionCanHandleNodes:(NSArray *)nodes
{
  return ([self interestingPathForNodes: nodes] != nil);
}

- (void)extensionAppendToContextMenu:(NSMenu *)menu forNodes:(NSArray *)nodes
{
  NSString *path = [self interestingPathForNodes: nodes];
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: @"Do Thing"
                                                action: @selector(doThing:)
                                         keyEquivalent: @""];
  [item setTarget: self];
  [item setRepresentedObject: path];   // handed back when invoked
  [menu addItem: item];
  RELEASE (item);
}
```

`nodes` elements are `FSNode`; use `-path`, `-isDirectory`, etc.

### Badge pattern

```objc
- (NSImage *)badgeImageForNode:(FSNode *)node
{
  if ([node isDirectory] == NO) return nil;
  if ([[NSFileManager defaultManager]
        fileExistsAtPath: [[node path] stringByAppendingPathComponent: @".flag"]])
    {
      return [self cachedBadgeImage];   // build once, cache, return nil if absent
    }
  return nil;
}
```

Badges are queried per icon, so keep this cheap and never throw.

## Safety contract (MANDATORY)

**A GWorkspace extension must never crash, hang, or otherwise take down
Workspace.** Workspace loads third-party bundles into its own process; a bug in
your bundle is a bug in Workspace as far as the user is concerned. The manager
wraps every call to your bundle in `@try/@catch`, but that only catches
Objective-C exceptions — a SIGSEGV, a deadlock, or a runaway allocation will
still kill the app. Therefore:

1. **Never block the main thread.** Any I/O, subprocess, or network call must be
   asynchronous. In particular, when driving a subprocess with `NSTask`,
   **never call `waitUntilExit` before draining its pipe.** If the child writes
   more than the pipe buffer (~64 KB) while the parent waits, the child blocks
   on write, `waitUntilExit` never returns, and the UI deadlocks (this is exactly
   what crashed the first GitContextMenu `Diff` on large repos). Instead, read
   the pipe asynchronously and run the task on a background path:

   ```objc
   NSPipe *pipe = [NSPipe pipe];
   [task setStandardOutput: pipe];
   [task setStandardError: pipe];
   NSFileHandle *readHandle = [pipe fileHandleForReading];
   [readHandle readToEndOfFileInBackgroundAndNotify];   // drains as it writes
   [task launch];
   // deliver results on the main thread when the notification fires
   ```

   See `GitContextMenu.m` (`runGitCommand:title:repo:` +
   `gitReadCompleted:` + a 60 s `gitTimeout:` watchdog) for a complete,
   crash-proof pattern.

2. **Validate everything.** Resolve external tools from `PATH` (do not hardcode
   `/usr/bin/git`); check that paths still exist before touching them; guard
   against `nil` nodes/arguments.

3. **Touch UI only on the main thread** (e.g. `performSelectorOnMainThread:
   withObject: waitUntilDone:`). Background completion handlers run off the
   main thread.

4. **Wrap your own entry points in `@try/@catch`** as defense in depth, so a
   stray exception in your code can never escape into Workspace even if the
   manager's wrapper is somehow bypassed. Log with `NSLog` and degrade
   gracefully (e.g. show an error string in your window) rather than throwing.

5. **Keep decorations cheap.** `badgeImageForNode:` runs for every visible icon;
   cache any image you build and return `nil` quickly when you don't apply.

## Debugging

- Bundles load at Workspace startup from `*/Library/Bundles/*.gwext` (all
  domains; SYSTEM is the install target). After changing a bundle, **restart
  Workspace** to reload it.
- To run a second Workspace under a debugger next to the live, session-managed
  one without the single-instance "kill-war", launch it with
  `GW_NO_KILL_INSTANCES=1` (e.g. `env GW_NO_KILL_INSTANCES=1 lldb Workspace`).
  This env hook is debug-only and has no effect unless set.
- Confirm a bundle is discovered by checking
  `/System/Library/Bundles/MyExtension.gwext` exists after install, and that its
  `Info-gnustep.plist` `NSPrincipalClass` is your class name.

## License / headers

New files use the repo's dual header:

```objc
/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
```
