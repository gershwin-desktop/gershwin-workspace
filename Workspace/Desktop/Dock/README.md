# DockService Protocol

A Distributed Objects protocol for external clients to inspect and modify Dock icon state (badge count, progress bar, urgent indicator). Compatible with the Unity LauncherEntry DBus API.

## Service

| Field | Value |
|-------|-------|
| DO service name | `com.canonical.Unity.LauncherEntry` |
| C functions | `DockServiceStart(id dock)`, `DockServiceStop()` |

The service is vended by the Dock on `[NSConnection defaultConnection]`. Started in `Dock.m` `awakeFromNib`; stopped in `dealloc`.

## Protocol

```objc
@protocol DockService
- (void)update:(NSString *)appUri properties:(NSDictionary *)properties;
- (NSDictionary *)query;
@end
```

### `update:properties:`

Sets properties on the Dock icon identified by `appUri`.

**URI format:** `application://<AppName>.desktop` or just `<AppName>`.  
The service strips the `application://` prefix and `.desktop` suffix before matching against the Dock's icon list.

**Properties dictionary:**

| Key | Type | Range | Description |
|-----|------|-------|-------------|
| `count` | number | >= 0 | Badge number (clamped to 0) |
| `count-visible` | boolean | — | Show/hide the badge |
| `progress` | number | -1.0 to 1.0 | Progress value (clamped). -1 = indeterminate |
| `progress-visible` | boolean | — | Show/hide the progress bar |
| `urgent` | boolean | — | Glow the icon orange when YES |

All keys are optional; only present keys are applied.

### `query`

Returns a dictionary with the last known `appUri` and `properties` for the most recently updated entry.

## DockIcon Rendering

| Feature | Visual |
|---------|--------|
| Urgent | Orange oval glow behind the icon |
| Badge count | Red circle with white number, top-right of the icon |
| Progress bar | Green bar over dark-grey background at the bottom edge |

## Test Clients

`Tools/BadgeTest/` and `Tools/ProgressTest/` are GNUstep applications that connect to the service and manipulate their own Dock icon.

### Build

```bash
make -C Tools
```

### BadgeTest

Opens a window with +/- buttons to adjust the badge count on its Dock icon.

### ProgressTest

Opens a window that animates a progress bar (0→1→0) on its Dock icon.

### Custom URIs

To target a different app's Dock icon from your own client:

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

## Implementation Files

- `DockService.h` — protocol declaration and C helper prototypes
- `DockService.m` — service implementation, URI→icon mapping, property clamping
- `DockIcon.h` / `DockIcon.m` — ivars, accessors, `drawRect:` rendering
- `Dock.m` — service startup/shutdown wiring
