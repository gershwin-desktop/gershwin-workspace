/* AboutController.m
 *
 * Date: January 2026
 */

#import "AboutController.h"
#import "Workspace.h"
#import <GNUstepBase/GNUstep.h>
#include <sys/utsname.h>
#include <X11/Xlib.h>

@implementation AboutController

static AboutController *sharedController = nil;

+ (AboutController *)sharedController
{
  if (sharedController == nil) {
    sharedController = [AboutController new];
  }
  return sharedController;
}

- (id)init
{
  self = [super init];
  if (self) {
    [self createAboutWindow];
  }
  return self;
}

- (void)createAboutWindow
{
  NSRect rect = NSMakeRect(0, 0, 320, 420);
  unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask;
  
  aboutWindow = [[NSWindow alloc] initWithContentRect:rect
                                            styleMask:styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:YES];
  [aboutWindow setReleasedWhenClosed:YES];
  [aboutWindow setDelegate:self];
  [aboutWindow setTitle:_(@"About This Computer")];
  [aboutWindow center];

  NSView *contentView = [aboutWindow contentView];
  
  // Computer Image
  computerImageView = [[NSImageView alloc] initWithFrame:NSMakeRect(96, 290, 128, 128)];
  NSImage *image = [NSImage imageNamed:@"NSComputer"];
  if (!image) image = [NSImage imageNamed:@"FileManager"]; // Fallback
  [computerImageView setImage:image];
  [contentView addSubview:computerImageView];
  RELEASE(computerImageView);

  // OS Pretty Name
  osNameField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 250, 280, 24)];
  [osNameField setEditable:NO];
  [osNameField setBezeled:NO];
  [osNameField setBordered:NO];
  [osNameField setDrawsBackground:NO];
  [osNameField setSelectable:NO];
  [osNameField setAlignment:NSCenterTextAlignment];
  [osNameField setFont:[NSFont boldSystemFontOfSize:18]];
  [contentView addSubview:osNameField];
  RELEASE(osNameField);

  // OS Version
  osVersionField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 230, 280, 20)];
  [osVersionField setEditable:NO];
  [osVersionField setBezeled:NO];
  [osVersionField setBordered:NO];
  [osVersionField setDrawsBackground:NO];
  [osVersionField setSelectable:NO];
  [osVersionField setAlignment:NSCenterTextAlignment];
  [osVersionField setFont:[NSFont systemFontOfSize:12]];
  [contentView addSubview:osVersionField];
  RELEASE(osVersionField);

  float y = 190;
  float labelX = 20;
  float valueX = 120;
  float width = 180;
  float labelWidth = 90;
  float rowHeight = 18;

  // Labels for system info
  NSArray *labels = @[_(@"Processor"), _(@"Memory"), _(@"Kernel"), _(@"X11 Server"), _(@"Product"), _(@"Manufacturer"), _(@"Serial Number")];
  NSMutableArray *fields = [NSMutableArray array];

  for (NSString *labelText in labels) {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(labelX, y, labelWidth, rowHeight)];
    [label setEditable:NO];
    [label setBezeled:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:NO];
    [label setAlignment:NSRightTextAlignment];
    [label setFont:[NSFont boldSystemFontOfSize:11]];
    [label setStringValue:[labelText stringByAppendingString:@":"]];
    [contentView addSubview:label];
    RELEASE(label);

    NSTextField *value = [[NSTextField alloc] initWithFrame:NSMakeRect(valueX, y, width, rowHeight)];
    [value setEditable:NO];
    [value setBezeled:NO];
    [value setBordered:NO];
    [value setDrawsBackground:NO];
    [value setSelectable:NO];
    [value setFont:[NSFont systemFontOfSize:11]];
    [value setAlignment:NSLeftTextAlignment];
    [contentView addSubview:value];
    [fields addObject:value];
    RELEASE(value);

    y -= rowHeight;
  }

  processorField = [fields objectAtIndex:0];
  memoryField = [fields objectAtIndex:1];
  kernelField = [fields objectAtIndex:2];
  x11Field = [fields objectAtIndex:3];
  modelField = [fields objectAtIndex:4];
  manufacturerField = [fields objectAtIndex:5];
  serialNumberField = [fields objectAtIndex:6];

  // More Info button calls Workspace "notImplemented:" so behavior is consistent
  NSButton *moreInfo = [[NSButton alloc] initWithFrame:NSMakeRect(110, 20, 100, 24)];
  [moreInfo setTitle:_(@"More Info...")];
  [moreInfo setBezelStyle:NSRoundedBezelStyle];
  [moreInfo setTarget:[Workspace gworkspace]];
  [moreInfo setAction:@selector(notImplemented:)];
  [contentView addSubview:moreInfo];
  RELEASE(moreInfo);
}

- (void)updateSystemInfo
{
  NSDictionary *osRelease = [self parseOSRelease];
  NSString *name = [osRelease objectForKey:@"NAME"];
  if (!name) name = [osRelease objectForKey:@"PRETTY_NAME"];
  [osNameField setStringValue:name ?: @"GNU/Linux"];
  
  NSString *version = [osRelease objectForKey:@"VERSION_ID"];
  if (!version) version = [osRelease objectForKey:@"VERSION"];
  [osVersionField setStringValue:[NSString stringWithFormat:@"%@ %@", _(@"Version"), version ?: @""]];

  [kernelField setStringValue:[self kernelInfo]];
  [x11Field setStringValue:[self x11VersionInfo]];

  NSString *product = nil;
  NSString *manufacturer = nil;
  NSString *serial = nil;
  NSString *processor = nil;

#ifdef __linux__
  if (![self isX86Architecture] && [self isDeviceTreeSystem]) {
    product = [self readTextFileTrimmingNulls:@"/sys/firmware/devicetree/base/model"];
    NSString *compatible = [self readTextFileTrimmingNulls:@"/sys/firmware/devicetree/base/compatible"];
    processor = [self processorNameFromCompatibleString:compatible];
    serial = [self cpuInfoValueForKey:@"Serial"];
  } else {
    product = [self smbiosValueForLinux:@"product_name"
                              bsdSysctl:@"hw.smbios.product"
                                bsdKenv:@"smbios.system.product"];
    manufacturer = [self smbiosValueForLinux:@"sys_vendor"
                                   bsdSysctl:@"hw.smbios.maker"
                                     bsdKenv:@"smbios.system.maker"];
    serial = [self smbiosValueForLinux:@"product_serial"
                             bsdSysctl:@"hw.smbios.serial"
                               bsdKenv:@"smbios.system.serial"];
  }
#else
  if (![self isX86Architecture]) {
    product = [self runCommand:@"sysctl" withArguments:@[@"-n", @"hw.model"]];
    NSString *compatible = [self runCommand:@"sysctl" withArguments:@[@"-n", @"hw.compatible"]];
    processor = [self processorNameFromCompatibleString:compatible];
    serial = [self runCommand:@"sysctl" withArguments:@[@"-n", @"hw.serialno"]];
  } else {
    product = [self smbiosValueForLinux:nil
                              bsdSysctl:@"hw.smbios.product"
                                bsdKenv:@"smbios.system.product"];
    manufacturer = [self smbiosValueForLinux:nil
                                   bsdSysctl:@"hw.smbios.maker"
                                     bsdKenv:@"smbios.system.maker"];
    serial = [self smbiosValueForLinux:nil
                             bsdSysctl:@"hw.smbios.serial"
                               bsdKenv:@"smbios.system.serial"];
  }
#endif

  if (!processor) {
    processor = [self getProcessorInfo];
  }

  [processorField setStringValue:processor ?: @"Unknown"];
  [modelField setStringValue:product ?: @"Unknown"];
  [manufacturerField setStringValue:manufacturer ?: @"Unknown"];
  [serialNumberField setStringValue:serial ?: @""];
  
  // Memory info
  unsigned long long mem = [[NSProcessInfo processInfo] physicalMemory];
  if (mem > 0) {
    [memoryField setStringValue:[NSString stringWithFormat:@"%llu MB", mem / (1024 * 1024)]];
  } else {
    [memoryField setStringValue:@"Unknown"];
  }
}

- (void)showAboutWindow:(id)sender
{
  if (!aboutWindow) {
    [self createAboutWindow];
  }
  [self updateSystemInfo];
  [aboutWindow makeKeyAndOrderFront:sender];
}

- (void)moreInfo:(id)sender
{
  // Placeholder - routed to Workspace:notImplemented:
}

- (BOOL)windowShouldClose:(id)sender
{
  return YES;
}

- (void)windowWillClose:(NSNotification *)notification
{
  // The window will be released if releasedWhenClosed is YES; clear our ivar so we can recreate later.
  if ([notification object] == aboutWindow) {
    aboutWindow = nil;
  }
}

// Helpers

- (NSString *)runCommand:(NSString *)command withArguments:(NSArray *)args
{
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:command];
  [task setArguments:args];
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:[NSPipe pipe]]; // Silence errors

  @try {
    [task launch];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    if ([task terminationStatus] == 0) {
      NSString *val = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
      return [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
  } @catch (NSException *e) {
    // Command might not exist
  } @finally {
    RELEASE(task);
  }
  return nil;
}

- (BOOL)isX86Architecture
{
  struct utsname name;
  if (uname(&name) != 0) {
    return NO;
  }

  NSString *machine = [NSString stringWithUTF8String:name.machine];
  if (!machine) {
    return NO;
  }

  return [machine hasPrefix:@"x86"] || [machine hasPrefix:@"i386"] || [machine hasPrefix:@"i486"] ||
         [machine hasPrefix:@"i586"] || [machine hasPrefix:@"i686"] || [machine hasPrefix:@"amd64"];
}

- (BOOL)isDeviceTreeSystem
{
  return [[NSFileManager defaultManager] fileExistsAtPath:@"/sys/firmware/devicetree/base"];
}

- (NSString *)readTextFileTrimmingNulls:(NSString *)path
{
  NSData *data = [NSData dataWithContentsOfFile:path];
  if (!data || [data length] == 0) {
    return nil;
  }

  NSString *value = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
  if (!value) {
    return nil;
  }

  value = [value stringByReplacingOccurrencesOfString:@"\0" withString:@""];
  value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [value length] > 0 ? value : nil;
}

- (NSString *)cpuInfoValueForKey:(NSString *)key
{
  if (!key || [key length] == 0) {
    return nil;
  }

  NSString *cpuinfo = [NSString stringWithContentsOfFile:@"/proc/cpuinfo"
                                                 encoding:NSUTF8StringEncoding
                                                    error:NULL];
  if (!cpuinfo) {
    return nil;
  }

  NSString *prefix = [key stringByAppendingString:@":"];
  NSArray *lines = [cpuinfo componentsSeparatedByString:@"\n"];
  for (NSString *line in lines) {
    if ([line hasPrefix:prefix]) {
      NSArray *parts = [line componentsSeparatedByString:@":"];
      if ([parts count] > 1) {
        NSString *value = [[parts objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return [value length] > 0 ? value : nil;
      }
    }
  }

  return nil;
}

- (NSString *)vendorNameForCompatiblePrefix:(NSString *)prefix
{
  NSDictionary *map = @{
    @"brcm": @"Broadcom",
    @"qcom": @"Qualcomm",
    @"rockchip": @"Rockchip",
    @"amlogic": @"Amlogic"
  };
  return [map objectForKey:[prefix lowercaseString]];
}

- (NSString *)processorNameFromCompatibleString:(NSString *)compatible
{
  if (!compatible || [compatible length] == 0) {
    return nil;
  }

  NSCharacterSet *splitSet = [NSCharacterSet characterSetWithCharactersInString:@", \t\n"];
  NSArray *tokens = [compatible componentsSeparatedByCharactersInSet:splitSet];

  NSArray *preferredPrefixes = @[@"brcm", @"qcom", @"rockchip", @"amlogic"];
  for (NSString *prefix in preferredPrefixes) {
    NSString *needle = [prefix stringByAppendingString:@","];
    NSRange range = [compatible rangeOfString:needle options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound) {
      NSString *tail = [compatible substringFromIndex:(range.location + range.length)];
      NSArray *tailParts = [tail componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([tailParts count] > 0) {
        NSString *soc = [[tailParts objectAtIndex:0] uppercaseString];
        NSString *vendor = [self vendorNameForCompatiblePrefix:prefix];
        if (vendor && [soc length] > 0) {
          return [NSString stringWithFormat:@"%@ %@", vendor, soc];
        }
      }
    }
  }

  for (NSString *token in tokens) {
    if ([token length] == 0) {
      continue;
    }
    NSRange commaRange = [token rangeOfString:@","];
    if (commaRange.location == NSNotFound) {
      continue;
    }

    NSString *prefix = [token substringToIndex:commaRange.location];
    NSString *soc = [[token substringFromIndex:(commaRange.location + 1)] uppercaseString];
    NSString *vendor = [self vendorNameForCompatiblePrefix:prefix];
    if (vendor && [soc length] > 0) {
      return [NSString stringWithFormat:@"%@ %@", vendor, soc];
    }
  }

  return nil;
}

- (NSDictionary *)parseOSRelease 
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSString *content = [NSString stringWithContentsOfFile:@"/etc/os-release" encoding:NSUTF8StringEncoding error:NULL];
  if (content) {
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line containsString:@"="]) {
        NSArray *parts = [line componentsSeparatedByString:@"="];
        if ([parts count] >= 2) {
          NSString *key = [parts objectAtIndex:0];
          NSString *value = [[parts subarrayWithRange:NSMakeRange(1, [parts count] - 1)] componentsJoinedByString:@"="];
          value = [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"'"]];
          [dict setObject:value forKey:key];
        }
      }
    }
  }
  return dict;
}

- (NSString *)smbiosValueForLinux:(NSString *)linuxFile 
                        bsdSysctl:(NSString *)bsdSysctl 
                          bsdKenv:(NSString *)bsdKenv 
{
#ifdef __linux__
  if (linuxFile) {
    NSString *path = [@"/sys/class/dmi/id/" stringByAppendingString:linuxFile];
    NSString *val = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    if (val) {
      val = [val stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([val length] > 0) return val;
    }
  }
#else
  NSString *val = nil;
  // Try kenv first as it's often more descriptive on some BSDs
  if (bsdKenv) {
    val = [self runCommand:@"kenv" withArguments:@[@"-q", bsdKenv]];
    if (val && [val length] > 0) return val;
  }
  // Fallback to sysctl
  if (bsdSysctl) {
    val = [self runCommand:@"sysctl" withArguments:@[@"-n", bsdSysctl]];
    if (val && [val length] > 0) return val;
  }
#endif
  return nil;
}

- (NSString *)kernelInfo 
{
  struct utsname name;
  if (uname(&name) == 0) {
    return [NSString stringWithFormat:@"%s %s", name.sysname, name.release];
  }
  return @"Unknown";
}

- (NSString *)x11VersionInfo 
{
  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) return @"Unknown";
  const char *vendor = XServerVendor(dpy);
  int release = XVendorRelease(dpy);
  XCloseDisplay(dpy);
  
  NSString *vendorStr = [NSString stringWithUTF8String:vendor];
  NSString *displayName = nil;
  if ([vendorStr rangeOfString:@"XLibre"].location != NSNotFound) {
    displayName = @"XLibre";
  } else if ([vendorStr rangeOfString:@"X.Org"].location != NSNotFound ||
             [vendorStr rangeOfString:@"The X.Org Foundation"].location != NSNotFound) {
    displayName = @"X.Org";
  }
  if (displayName) {
    int major = release / 10000000;
    int minor = (release % 10000000) / 100000;
    int patch = (release % 100000) / 1000;
    return [NSString stringWithFormat:@"%@ %d.%d.%d", displayName, major, minor, patch];
  }
  return [NSString stringWithFormat:@"%@ %d", vendorStr, release];
}

- (NSString *)getProcessorInfo
{
#ifdef __linux__
  NSString *cpuinfo = [NSString stringWithContentsOfFile:@"/proc/cpuinfo" encoding:NSUTF8StringEncoding error:NULL];
  if (cpuinfo) {
    NSArray *lines = [cpuinfo componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line rangeOfString:@"model name"].location != NSNotFound) {
        NSArray *parts = [line componentsSeparatedByString:@":"];
        if ([parts count] > 1) {
          return [[parts objectAtIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
      }
    }
  }
#else
  NSString *val = [self runCommand:@"sysctl" withArguments:@[@"-n", @"hw.model"]];
  if (val) return val;
#endif
  return @"Unknown";
}

@end
