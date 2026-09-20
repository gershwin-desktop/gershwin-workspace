# Dock Icon State Protocol

## Distributed Objects (GNUstep Native)

A clean DO protocol for GNUstep applications to modify their own Dock icon (badge count, progress bar, urgent indicator). Each app can only modify its own icon. Works on Linux, FreeBSD, OpenBSD, NetBSD, and macOS.

### Service

| Field | Value |
|-------|-------|
| DO service name | `DockIcon` on `[NSConnection defaultConnection]` |

### Protocol

```objc
@protocol DockService <NSObject>
- (void)setBadgeCount:(int64_t)count;
- (void)setCountVisible:(BOOL)visible;
- (void)setProgressValue:(double)value;
- (void)setProgressVisible:(BOOL)visible;
- (void)setUrgent:(BOOL)urgent;
- (void)clearAll;
@end
```

### Usage

Connect to the service and call setters directly. The Dock automatically identifies which app is calling (via the DO connection's process PID) and applies changes only to that app's Dock icon. No registration or app name needed.

```objc
NSConnection *conn = [NSConnection connectionWithRegisteredName:@"DockIcon" host:nil];
id<DockService> dock = (id<DockService>)[conn rootProxy];
[dock setBadgeCount:42];
[dock setUrgent:YES];
```

### C Functions

```c
void DockServiceStart(id dock);   // called by Dock on init
void DockServiceStop(void);       // called by Dock on dealloc
```

---

## D-Bus (Interoperability for Legacy Applications)

Implements the Unity LauncherEntry D-Bus protocol for legacy Linux/GTK applications (Firefox, Thunderbird, etc.) that already speak this protocol.

### Transport

| Field | Value |
|-------|-------|
| Bus | session bus (`--session`) |
| Service | `com.canonical.Unity.LauncherEntry` |
| Object path | `/com/canonical/unity/launcherentry` |
| Interface | `com.canonical.Unity.LauncherEntry` |

### Method

**`Update(string app_id, dict<string, variant> properties)`**

`app_id` format: `application://<AppName>.desktop` or just `<AppName>`.  
The service strips the `application://` prefix and `.desktop` suffix before matching against the Dock's icon list.

### Properties

| Key | D-Bus type | Range | Description |
|-----|-----------|-------|-------------|
| `count` | INT64 | >= 0 | Badge number (clamped to 0) |
| `count-visible` | BOOLEAN | — | Show/hide the badge |
| `progress` | DOUBLE | -1.0 to 1.0 | Progress value (clamped). -1 = indeterminate |
| `progress-visible` | BOOLEAN | — | Show/hide the progress bar |
| `urgent` | BOOLEAN | — | Glow the icon orange when YES |

All keys are optional; only present keys are applied.

### Example

```sh
dbus-send --session --dest=com.canonical.Unity.LauncherEntry \
  /com/canonical/unity/launcherentry \
  com.canonical.Unity.LauncherEntry.Update \
  string:"Firefox" \
  "dict:string:variant:count,int64:5,count-visible,boolean:true"
```

### Building

D-Bus support is auto-detected by `./configure` and can be forced on/off:

```bash
./configure --enable-dbus
./configure --disable-dbus
```

---

## Test Clients

### BadgeTest

GNUstep application that connects via DO and adjusts its own badge count.

```bash
make -C Tools BadgeTest
./Tools/BadgeTest/BadgeTest.app/BadgeTest
```

Opens a window with +/- buttons to adjust the badge count on its Dock icon.

### ProgressTest

GNUstep application that connects via DO and animates a progress bar on its own Dock icon.

```bash
make -C Tools ProgressTest
./Tools/ProgressTest/ProgressTest.app/ProgressTest
```

### docktest-dbus.sh

Shell script for testing the D-Bus transport against any pinned Dock icon:

```bash
Tools/docktest-dbus.sh "App Name" self-test
```

---

## Implementation Files

- `DockService.h` — DO protocol declaration, shared C helpers, C `DockServiceStart`/`Stop`
- `DockService.m` — DO service implementation: automatic caller detection via PID, property setters
- `DockServiceDBus.h` / `DockServiceDBus.m` — D-Bus service implementation (conditional on `HAVE_DBUS`)
- `DockIcon.h` / `DockIcon.m` — ivars, accessors, `drawRect:` rendering
- `Dock.m` — both services' startup/shutdown wiring

---

## Magnification

The icons around the pointer grow while it is on the Dock, following the
magnification of the expired patent US7434177 (`DockMagnification.h` holds the
geometry). Two settings in `org.gnustep.Workspace` control it:

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `dockmagnification` | bool | `YES` | Whether the icons grow at all. With it off, the Dock does not even watch the pointer. |
| `docklargesize` | float | `96` | The size the icon under the pointer is drawn at, in the same units as the icons' own size (48 at rest). Values up to 128 are used; anything at or below the resting size means no magnification. |

Both are read again whenever the defaults change, so a running Dock picks a
new value up within a few seconds; there is no need to restart Workspace.
Neither is ever written back, so what is on disk stays what was asked for.

```sh
defaults write org.gnustep.Workspace docklargesize 128
defaults write org.gnustep.Workspace dockmagnification NO
```

Plain values: this `defaults` takes a property list, not the type flags
(`-float`, `-bool`) of other implementations, which it would store as the
string value `-float`.

How large the icons really grow can be less than asked for: the Dock works out
how much room is left beside the bar and narrows the effect, and then the
magnified size itself, rather than letting the bar run past the edge of the
screen. A Dock filling most of a small screen therefore magnifies less than
the same Dock on a large one.
