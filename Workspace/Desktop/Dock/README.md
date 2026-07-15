# DockService Protocol

Two transports for external clients to inspect and modify Dock icon state (badge count, progress bar, urgent indicator), compatible with the Unity LauncherEntry API.

## Transports

| Transport | Service name | Dependency | Use case |
|-----------|-------------|------------|----------|
| Distributed Objects | `com.canonical.Unity.LauncherEntry` on `[NSConnection defaultConnection]` | None (always built) | GNUstep-native apps |
| D-Bus | `com.canonical.Unity.LauncherEntry` on session bus | libdbus (optional, `HAVE_DBUS`) | Legacy Linux/GTK apps (Firefox, Thunderbird, etc.) |

Both transports use the same properties dictionary (see below) and share the URI-to-icon matching and property-clamping logic.

## Properties

### `update:properties:` (DO) / `Update` D-Bus method

Sets properties on a Dock icon identified by `app_id` / `appUri`.

**app_id format:** `application://<AppName>.desktop` or just `<AppName>`.  
The service strips the `application://` prefix and `.desktop` suffix before matching against the Dock's icon list.

**D-Bus method signature:**
```
Interface: com.canonical.Unity.LauncherEntry
Object path: /com/canonical/unity/launcherentry
Method: Update(string app_id, dict<string, variant> properties)
```

**Properties dictionary:**

| Key | D-Bus type | Range | Description |
|-----|-----------|-------|-------------|
| `count` | INT64 | >= 0 | Badge number (clamped to 0) |
| `count-visible` | BOOLEAN | — | Show/hide the badge |
| `progress` | DOUBLE | -1.0 to 1.0 | Progress value (clamped). -1 = indeterminate |
| `progress-visible` | BOOLEAN | — | Show/hide the progress bar |
| `urgent` | BOOLEAN | — | Glow the icon orange when YES |

All keys are optional; only present keys are applied.

### `query` (DO only)

Returns a dictionary with the last known `appUri` and `properties` for the most recently updated entry.

## DockIcon Rendering

| Feature | Visual |
|---------|--------|
| Urgent | Orange oval glow behind the icon |
| Badge count | Red circle with white number, top-right of the icon |
| Progress bar | Green bar over dark-grey background at the bottom edge |

## Test Clients

`Tools/BadgeTest/` and `Tools/ProgressTest/` are GNUstep applications that connect to the DO service and manipulate their own Dock icon.

### Build

```bash
make -C Tools
```

### BadgeTest

Opens a window with +/- buttons to adjust the badge count on its Dock icon.

### ProgressTest

Opens a window that animates a progress bar (0→1→0) on its Dock icon.

### Custom URIs (DO)

```objc
#import <Foundation/Foundation.h>

NSConnection *conn = [NSConnection connectionWithRegisteredName:@"com.canonical.Unity.LauncherEntry" host:nil];
id<DockService> dock = (id<DockService>)[conn rootProxy];

[dock update:@"application://GWorkspace.desktop" properties:@{
  @"count": @5,
  @"count-visible": @YES,
  @"urgent": @YES
}];
```

### Legacy apps via D-Bus

Legacy Linux/GTK applications (Firefox, Thunderbird, etc.) that already speak the Unity LauncherEntry D-Bus protocol will automatically update their Dock icon when Workspace is built with D-Bus support. No changes to those applications are needed.

## Building with D-Bus

D-Bus support is auto-detected by `./configure` and can be forced on/off with:

```bash
./configure --enable-dbus
./configure --disable-dbus
```

When D-Bus is enabled, `config.h` defines `HAVE_DBUS` and the build includes `DBusConnection.m`, `FileManagerDBusInterface.m`, and `DockServiceDBus.m`.

## Implementation Files

- `DockService.h` — protocol declaration, shared C helpers (`DockServiceAppNameFromUri`, `DockServiceApplyProperties`), and C `DockServiceStart`/`Stop`
- `DockService.m` — DO service implementation, shared helper implementations
- `DockServiceDBus.h` / `DockServiceDBus.m` — D-Bus service implementation (conditional on `HAVE_DBUS`)
- `DockIcon.h` / `DockIcon.m` — ivars, accessors, `drawRect:` rendering
- `Dock.m` — both services' startup/shutdown wiring (DO always, D-Bus conditional)
