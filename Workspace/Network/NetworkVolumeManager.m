/* NetworkVolumeManager.m
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "NetworkVolumeManager.h"
#import "NetworkServiceItem.h"
#import "SFTPMount.h"

static NetworkVolumeManager *sharedInstance = nil;

@implementation NetworkVolumeManager

+ (NetworkVolumeManager *)sharedManager
{
  if (sharedInstance == nil) {
    sharedInstance = [[NetworkVolumeManager alloc] init];
  }
  return sharedInstance;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    mountedVolumes = [[NSMutableDictionary alloc] init];
    fm = [NSFileManager defaultManager];
    
    NSLog(@"NetworkVolumeManager: Initialized");
  }
  return self;
}

- (void)dealloc
{
  [self unmountAll];
  [mountedVolumes release];
  [super dealloc];
}

- (BOOL)isSshfsAvailable
{
  /* Check if sshfs command exists in PATH */
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/usr/bin/which"];
  [task setArguments:@[@"sshfs"]];
  [task setStandardOutput:[NSPipe pipe]];
  [task setStandardError:[NSPipe pipe]];
  
  @try {
    [task launch];
    [task waitUntilExit];
    int status = [task terminationStatus];
    [task release];
    
    if (status == 0) {
      NSLog(@"NetworkVolumeManager: sshfs is available");
      return YES;
    } else {
      NSLog(@"NetworkVolumeManager: sshfs not found in PATH");
      return NO;
    }
  } @catch (NSException *exception) {
    NSLog(@"NetworkVolumeManager: Error checking for sshfs: %@", exception);
    [task release];
    return NO;
  }
}

- (void)showSshfsNotInstalledAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:NSLocalizedString(@"SSHFS Not Installed", @"")];
  [alert setInformativeText:NSLocalizedString(
    @"FUSE sshfs is required to mount SFTP network volumes but is not installed on your system.\n\n"
    @"To install it:\n"
    @"• On Debian/Ubuntu: sudo apt-get install sshfs\n"
    @"• On Fedora/RHEL: sudo dnf install fuse-sshfs\n"
    @"• On Arch: sudo pacman -S sshfs", @"")];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
  [alert runModal];
  [alert release];
}

- (BOOL)isSshpassAvailable
{
  /* Check if sshpass command exists in PATH */
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/usr/bin/which"];
  [task setArguments:@[@"sshpass"]];
  [task setStandardOutput:[NSPipe pipe]];
  [task setStandardError:[NSPipe pipe]];
  
  @try {
    [task launch];
    [task waitUntilExit];
    int status = [task terminationStatus];
    [task release];
    
    if (status == 0) {
      NSLog(@"NetworkVolumeManager: sshpass is available");
      return YES;
    } else {
      NSLog(@"NetworkVolumeManager: sshpass not found in PATH");
      return NO;
    }
  } @catch (NSException *exception) {
    NSLog(@"NetworkVolumeManager: Error checking for sshpass: %@", exception);
    [task release];
    return NO;
  }
}

- (void)showSshpassNotInstalledAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:NSLocalizedString(@"sshpass Not Installed", @"")];
  [alert setInformativeText:NSLocalizedString(
    @"sshpass is required for password-based SFTP authentication but is not installed on your system.\n\n"
    @"To install it:\n"
    @"• On Debian/Ubuntu: sudo apt-get install sshpass\n"
    @"• On Fedora/RHEL: sudo dnf install sshpass\n"
    @"• On Arch: sudo pacman -S sshpass\n\n"
    @"Alternatively, you can set up SSH key authentication to connect without a password.", @"")];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
  [alert runModal];
  [alert release];
}

- (NSString *)mountPointForService:(NetworkServiceItem *)serviceItem
{
  NSString *identifier = [serviceItem identifier];
  return [mountedVolumes objectForKey:identifier];
}

- (BOOL)isServiceMounted:(NetworkServiceItem *)serviceItem
{
  return [self mountPointForService:serviceItem] != nil;
}

- (NSString *)createMountPointForService:(NetworkServiceItem *)serviceItem
{
  /* Create mount point in user's home directory under ~/Network */
  NSString *homeDir = NSHomeDirectory();
  NSString *networkDir = [homeDir stringByAppendingPathComponent:@"Network"];
  
  /* Create ~/Network directory if it doesn't exist */
  BOOL isDir;
  if (![fm fileExistsAtPath:networkDir isDirectory:&isDir]) {
    NSError *error = nil;
    if (![fm createDirectoryAtPath:networkDir 
       withIntermediateDirectories:YES 
                        attributes:nil 
                             error:&error]) {
      NSLog(@"NetworkVolumeManager: Failed to create Network directory: %@", error);
      return nil;
    }
  } else if (!isDir) {
    NSLog(@"NetworkVolumeManager: ~/Network exists but is not a directory");
    return nil;
  }
  
  /* Create a unique mount point name based on the service */
  NSString *baseName = [serviceItem name];
  if (!baseName || [baseName length] == 0) {
    baseName = @"SFTP Server";
  }
  
  /* Sanitize the name for filesystem use */
  NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
  NSArray *components = [baseName componentsSeparatedByCharactersInSet:invalidChars];
  NSString *sanitizedName = [components componentsJoinedByString:@"-"];
  
  /* Find an unused mount point name */
  NSString *mountPoint = [networkDir stringByAppendingPathComponent:sanitizedName];
  int counter = 2;
  while ([fm fileExistsAtPath:mountPoint]) {
    mountPoint = [networkDir stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"%@-%d", sanitizedName, counter]];
    counter++;
  }
  
  /* Create the mount point directory */
  NSError *error = nil;
  if (![fm createDirectoryAtPath:mountPoint 
     withIntermediateDirectories:YES 
                      attributes:nil 
                           error:&error]) {
    NSLog(@"NetworkVolumeManager: Failed to create mount point %@: %@", mountPoint, error);
    return nil;
  }
  
  NSLog(@"NetworkVolumeManager: Created mount point at %@", mountPoint);
  return mountPoint;
}

- (NSString *)mountSFTPService:(NetworkServiceItem *)serviceItem
{
  /* Check if already mounted */
  NSString *existingMount = [self mountPointForService:serviceItem];
  if (existingMount) {
    NSLog(@"NetworkVolumeManager: Service %@ already mounted at %@", 
          [serviceItem name], existingMount);
    return existingMount;
  }
  
  /* Log TXT record data for debugging */
  NSLog(@"NetworkVolumeManager: === TXT Record Data for %@ ===", [serviceItem name]);
  NSNetService *netService = [serviceItem netService];
  if (netService) {
    NSData *txtData = [netService TXTRecordData];
    if (txtData && [txtData length] > 0) {
      NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData:txtData];
      if (txtDict) {
        NSLog(@"NetworkVolumeManager: TXT Record contains %lu keys:", (unsigned long)[txtDict count]);
        for (NSString *key in txtDict) {
          NSData *valueData = [txtDict objectForKey:key];
          NSString *valueString = [[[NSString alloc] initWithData:valueData 
                                                          encoding:NSUTF8StringEncoding] autorelease];
          NSLog(@"NetworkVolumeManager:   %@ = %@", key, valueString);
        }
      } else {
        NSLog(@"NetworkVolumeManager: Failed to parse TXT record dictionary");
      }
    } else {
      NSLog(@"NetworkVolumeManager: No TXT record data available");
    }
  } else {
    NSLog(@"NetworkVolumeManager: No netService available");
  }
  NSLog(@"NetworkVolumeManager: === End TXT Record Data ===");
  
  /* Check if sshfs is available */
  if (![self isSshfsAvailable]) {
    NSLog(@"NetworkVolumeManager: sshfs not available, showing alert");
    [self showSshfsNotInstalledAlert];
    return nil;
  }
  
  /* Get service details */
  NSString *hostName = [serviceItem hostName];
  int port = [serviceItem port];
  NSString *username = [serviceItem username];
  NSString *password = nil;
  
  if (!hostName || [hostName length] == 0) {
    NSLog(@"NetworkVolumeManager: Service has no hostname, cannot mount");
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Cannot Mount", @"")];
    [alert setInformativeText:NSLocalizedString(
      @"The network service does not have a valid hostname.", @"")];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
    [alert runModal];
    [alert release];
    return nil;
  }
  
  /* If no username in TXT record, prompt for it */
  if (!username || [username length] == 0) {
    NSLog(@"NetworkVolumeManager: No username in TXT record, prompting user");
    
    /* Create a custom panel for username/password input */
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 200)
                                                styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [panel setTitle:NSLocalizedString(@"Connect to SFTP Server", @"")];
    [panel center];
    
    /* Create main label */
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 140, 360, 40)];
    [label setStringValue:[NSString stringWithFormat:
      NSLocalizedString(@"Enter credentials for %@:", @""), hostName]];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [[panel contentView] addSubview:label];
    [label release];
    
    /* Create username label */
    NSTextField *usernameLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 110, 100, 17)];
    [usernameLabel setStringValue:NSLocalizedString(@"Username:", @"")];
    [usernameLabel setBezeled:NO];
    [usernameLabel setDrawsBackground:NO];
    [usernameLabel setEditable:NO];
    [usernameLabel setSelectable:NO];
    [usernameLabel setAlignment:NSRightTextAlignment];
    [[panel contentView] addSubview:usernameLabel];
    [usernameLabel release];
    
    /* Create username field */
    NSTextField *usernameField = [[NSTextField alloc] initWithFrame:NSMakeRect(130, 108, 250, 24)];
    [usernameField setStringValue:NSUserName()];
    [[panel contentView] addSubview:usernameField];
    [panel makeFirstResponder:usernameField];
    
    /* Create password label */
    NSTextField *passwordLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 75, 100, 17)];
    [passwordLabel setStringValue:NSLocalizedString(@"Password:", @"")];
    [passwordLabel setBezeled:NO];
    [passwordLabel setDrawsBackground:NO];
    [passwordLabel setEditable:NO];
    [passwordLabel setSelectable:NO];
    [passwordLabel setAlignment:NSRightTextAlignment];
    [[panel contentView] addSubview:passwordLabel];
    [passwordLabel release];
    
    /* Create password field */
    NSSecureTextField *passwordField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(130, 73, 250, 24)];
    [[panel contentView] addSubview:passwordField];
    
    /* Create buttons */
    NSButton *connectButton = [[NSButton alloc] initWithFrame:NSMakeRect(290, 20, 90, 24)];
    [connectButton setTitle:NSLocalizedString(@"Connect", @"")];
    [connectButton setTarget:NSApp];
    [connectButton setAction:@selector(stopModal)];
    [connectButton setKeyEquivalent:@"\\r"];
    [[panel contentView] addSubview:connectButton];
    [connectButton release];
    
    NSButton *cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(190, 20, 90, 24)];
    [cancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
    [cancelButton setTarget:NSApp];
    [cancelButton setAction:@selector(abortModal)];
    [cancelButton setKeyEquivalent:@"\\e"];
    [[panel contentView] addSubview:cancelButton];
    [cancelButton release];
    
    NSLog(@"NetworkVolumeManager: Showing username/password prompt dialog");
    NSInteger result = [NSApp runModalForWindow:panel];
    NSLog(@"NetworkVolumeManager: Dialog result: %ld", (long)result);
    
    if (result == NSRunStoppedResponse) {
      username = [[usernameField stringValue] retain];
      password = [[passwordField stringValue] retain];
      NSLog(@"NetworkVolumeManager: User entered username: %@", username);
    } else {
      NSLog(@"NetworkVolumeManager: User cancelled connection");
      [usernameField release];
      [passwordField release];
      [panel close];
      [panel release];
      return nil;
    }
    
    [usernameField release];
    [passwordField release];
    [panel close];
    [panel release];
    
    if (!username || [username length] == 0) {
      NSLog(@"NetworkVolumeManager: No username provided");
      [password release];
      return nil;
    }
    
    [username autorelease]; /* Balance the retain above */
    
    /* Keep password for sshfs (will autorelease later) */
    if (password && [password length] > 0) {
      [password autorelease];
    } else {
      [password release];
      password = nil;
    }
  } else {
    NSLog(@"NetworkVolumeManager: Using username from TXT record: %@", username);
  }
  
  /* Create mount point */
  NSString *mountPoint = [self createMountPointForService:serviceItem];
  if (!mountPoint) {
    NSLog(@"NetworkVolumeManager: Failed to create mount point");
    return nil;
  }
  
  NSLog(@"NetworkVolumeManager: Will use username: %@, hostname: %@, port: %d", 
        username, hostName, port);
  
  /* Use SFTPMount class to perform the mount */
  SFTPMount *mounter = [[SFTPMount alloc] init];
  SFTPMountResult *result = [mounter mountService:serviceItem 
                                         username:username 
                                         password:password 
                                        mountPath:mountPoint];
  [mounter release];
  
  if ([result success]) {
    /* Mount successful */
    NSString *identifier = [serviceItem identifier];
    [mountedVolumes setObject:mountPoint forKey:identifier];
    
    NSLog(@"NetworkVolumeManager: Successfully mounted %@ at %@", 
          [serviceItem name], mountPoint);
    
    /* Post notification that filesystem changed */
    [[NSNotificationCenter defaultCenter] 
      postNotificationName:@"GWFileSystemDidChangeNotification"
                    object:nil];
    
    return mountPoint;
  } else {
    /* Mount failed */
    NSString *errorMsg = [result errorMessage];
    NSLog(@"NetworkVolumeManager: Mount failed: %@", errorMsg);
    
    /* Remove the mount point directory on failure */
    [fm removeItemAtPath:mountPoint error:nil];
    
    /* Show error to user */
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:NSLocalizedString(@"Mount Failed", @"")];
    [alert setInformativeText:[NSString stringWithFormat:
      NSLocalizedString(@"Failed to mount SFTP volume:\n\n%@", @""), 
      errorMsg ? errorMsg : @"Unknown error"]];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
    [alert runModal];
    [alert release];
    
    return nil;
  }
}

- (BOOL)unmountService:(NetworkServiceItem *)serviceItem
{
  NSString *mountPoint = [self mountPointForService:serviceItem];
  if (!mountPoint) {
    NSLog(@"NetworkVolumeManager: Service %@ is not mounted", [serviceItem name]);
    return NO;
  }
  
  NSLog(@"NetworkVolumeManager: Unmounting %@ from %@", [serviceItem name], mountPoint);
  
  /* Execute fusermount -u to unmount */
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/usr/bin/fusermount"];
  [task setArguments:@[@"-u", mountPoint]];
  
  @try {
    [task launch];
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    [task release];
    
    if (status == 0) {
      /* Unmount successful */
      NSString *identifier = [serviceItem identifier];
      [mountedVolumes removeObjectForKey:identifier];
      
      /* Remove the mount point directory */
      [fm removeItemAtPath:mountPoint error:nil];
      
      NSLog(@"NetworkVolumeManager: Successfully unmounted %@", [serviceItem name]);
      
      /* Post notification that filesystem changed */
      [[NSNotificationCenter defaultCenter] 
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:nil];
      
      return YES;
    } else {
      NSLog(@"NetworkVolumeManager: fusermount failed with status %d", status);
      return NO;
    }
  } @catch (NSException *exception) {
    NSLog(@"NetworkVolumeManager: Exception while unmounting: %@", exception);
    [task release];
    return NO;
  }
}

- (void)unmountAll
{
  NSArray *identifiers = [mountedVolumes allKeys];
  
  for (NSString *identifier in identifiers) {
    NSString *mountPoint = [mountedVolumes objectForKey:identifier];
    
    NSLog(@"NetworkVolumeManager: Unmounting %@", mountPoint);
    
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/fusermount"];
    [task setArguments:@[@"-u", mountPoint]];
    
    @try {
      [task launch];
      [task waitUntilExit];
      [task release];
      
      /* Remove the mount point directory */
      [fm removeItemAtPath:mountPoint error:nil];
    } @catch (NSException *exception) {
      NSLog(@"NetworkVolumeManager: Exception while unmounting %@: %@", 
            mountPoint, exception);
      [task release];
    }
  }
  
  [mountedVolumes removeAllObjects];
}

@end
