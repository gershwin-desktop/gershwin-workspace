/* NetworkVolumeManager.m
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <signal.h>
#import <errno.h>
#import <unistd.h>
#import "NetworkVolumeManager.h"
#import "NetworkServiceItem.h"
#import "SFTPMount.h"
#import "../Workspace.h"
#import "../FSNode/FSNode.h"
#import "../FSNode/FSNodeRep.h"
#import "../Desktop/GWDesktopManager.h"
#import "../Desktop/GWDesktopView.h"

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
    mountedVolumesPIDs = [[NSMutableDictionary alloc] init];
    fm = [NSFileManager defaultManager];
    
    NSLog(@"NetworkVolumeManager: Initialized");
  }
  return self;
}

- (void)dealloc
{
  [self unmountAll];
  [mountedVolumes release];
  [mountedVolumesPIDs release];
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

- (NSString *)findExistingMountForHost:(NSString *)hostname username:(NSString *)username
{
  /* Check /proc/mounts to see if this server is already mounted */
  NSString *procMounts = @"/proc/mounts";
  NSError *readError = nil;
  NSString *mountsContent = [NSString stringWithContentsOfFile:procMounts 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:&readError];
  if (!mountsContent) {
    NSLog(@"NetworkVolumeManager: Could not read /proc/mounts: %@", readError);
    return nil;
  }
  
  /* Look for a line that matches: user@hostname:... on <mountpoint> type fuse.sshfs */
  NSArray *lines = [mountsContent componentsSeparatedByString:@"\n"];
  NSString *expectedPrefix = [NSString stringWithFormat:@"%@@%@:", username, hostname];
  
  for (NSString *line in lines) {
    if ([line length] == 0) continue;
    
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if ([parts count] < 3) continue;
    
    NSString *source = [parts objectAtIndex:0];  /* e.g., user@hostname:/path */
    NSString *target = [parts objectAtIndex:1];  /* mount point */
    NSString *fstype = [parts objectAtIndex:2];  /* filesystem type */
    
    /* Check if this is an sshfs mount to our target server */
    if ([fstype isEqual:@"fuse.sshfs"] && [source hasPrefix:expectedPrefix]) {
      NSLog(@"NetworkVolumeManager: Found existing mount of %@ at %@", source, target);
      return target;
    }
  }
  
  return nil;
}

- (NSString *)createMountPointForService:(NetworkServiceItem *)serviceItem
{
  /* Create mount point in /media/$USER directory */
  NSString *userName = NSUserName();
  NSString *networkDir = [@"/media" stringByAppendingPathComponent:userName];
  
  /* Create /media/$USER directory if it doesn't exist */
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
    NSLog(@"NetworkVolumeManager: /media/%@ exists but is not a directory", userName);
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
  return [self mountSFTPService:serviceItem username:nil password:nil];
}

- (NSString *)mountSFTPService:(NetworkServiceItem *)serviceItem
                      username:(NSString *)providedUsername
                      password:(NSString *)providedPassword
{
  /* Check if already mounted in our tracked mounts */
  NSString *existingMount = [self mountPointForService:serviceItem];
  if (existingMount) {
    NSLog(@"NetworkVolumeManager: Service %@ already mounted at %@ (tracked)", 
          [serviceItem name], existingMount);
    return existingMount;
  }
  
  /* Get details early to check for existing system mounts */
  NSString *hostName = [serviceItem hostName];
  int port = [serviceItem port];
  NSString *username = nil;
  
  /* First try to get username from TXT record */
  NSNetService *netService = [serviceItem netService];
  if (netService) {
    NSData *txtData = [netService TXTRecordData];
    if (txtData && [txtData length] > 0) {
      NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData:txtData];
      if (txtDict) {
        NSData *usernameData = [txtDict objectForKey:@"u"];
        if (usernameData) {
          username = [[[NSString alloc] initWithData:usernameData 
                                            encoding:NSUTF8StringEncoding] autorelease];
        }
      }
    }
  }
  
  /* For duplicate mount check, use username from TXT or current user as default */
  NSString *checkUsername = (username && [username length] > 0) ? username : NSUserName();
  
  /* Check if this server is already mounted in the system (from previous session/crash) */
  NSString *existingSystemMount = [self findExistingMountForHost:hostName username:checkUsername];
  if (existingSystemMount) {
    NSLog(@"NetworkVolumeManager: Found existing system mount of %@ at %@", 
          hostName, existingSystemMount);
    
    /* Verify the mount is still working */
    NSError *testError = nil;
    [fm contentsOfDirectoryAtPath:existingSystemMount error:&testError];
    
    if (!testError) {
      /* Mount is working - reuse it */
      NSLog(@"NetworkVolumeManager: Reusing existing working mount at %@", existingSystemMount);
      NSString *identifier = [serviceItem identifier];
      [mountedVolumes setObject:existingSystemMount forKey:identifier];
      /* Note: We don't store PID for existing mounts since we didn't start the process */

      /* Mark as volume in FSNodeRep for icon updates and notify parent directory */
      @try {
        FSNode *vnode = [FSNode nodeWithPath: existingSystemMount];
        if (vnode) {
          [vnode setMountPoint: YES];
        }
        [[FSNodeRep sharedInstance] addVolumeAt: existingSystemMount];
        NSLog(@"NetworkVolumeManager: FSNodeRep volumes now: %@", [[FSNodeRep sharedInstance] volumes]);
      } @catch (NSException *e) {
        NSLog(@"NetworkVolumeManager: Error marking existing mount: %@", e);
      }

      NSString *parent = [existingSystemMount stringByDeletingLastPathComponent];
      NSString *name = [existingSystemMount lastPathComponent];
      NSDictionary *opinfo = @{ @"operation": @"MountOperation",
                                @"source": parent,
                                @"destination": parent,
                                @"files": @[name] };

      [[NSNotificationCenter defaultCenter] 
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:opinfo];
      
      /* Also notify desktop manager directly so the volume appears on the desktop */
      NSLog(@"NetworkVolumeManager: Notifying desktop manager directly for existing mount %@", existingSystemMount);
      id gworkspace = [Workspace gworkspace];
      if (gworkspace) {
        id desktopManager = [gworkspace desktopManager];
        if (desktopManager && [[desktopManager desktopView] respondsToSelector:@selector(newVolumeMountedAtPath:)]) {
          [[desktopManager desktopView] newVolumeMountedAtPath: existingSystemMount];
        }
      }

      return existingSystemMount;
    } else {
      /* Mount exists but is not working - clean it up */
      NSLog(@"NetworkVolumeManager: Existing mount at %@ is stale, cleaning up", existingSystemMount);
      NSTask *umountTask = [[NSTask alloc] init];
      [umountTask setLaunchPath:@"/usr/bin/fusermount"];
      [umountTask setArguments:@[@"-u", existingSystemMount]];
      @try {
        [umountTask launch];
        [umountTask waitUntilExit];
        if ([umountTask terminationStatus] == 0) {
          NSLog(@"NetworkVolumeManager: Successfully unmounted stale mount");
          /* Also try to remove the directory */
          [fm removeItemAtPath:existingSystemMount error:nil];
        }
      } @catch (NSException *e) {
        NSLog(@"NetworkVolumeManager: Exception while cleaning up stale mount: %@", e);
      }
      [umountTask release];
      /* Wait a moment for cleanup to complete */
      [NSThread sleepForTimeInterval:0.5];
    }
  }
  
  /* Log TXT record data for debugging */
  NSLog(@"NetworkVolumeManager: === TXT Record Data for %@ ===", [serviceItem name]);
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
  
  /* Service details already obtained above */
  NSString *password = providedPassword;
  
  /* Use provided username if available, otherwise check TXT record */
  if (providedUsername && [providedUsername length] > 0) {
    username = providedUsername;
  }
  
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
  
  /* If no username provided AND no username in TXT record, prompt for it */
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
    
    /* Store the sshfs process ID for proper unmounting */
    int pid = [result pid];
    if (pid > 0) {
      [mountedVolumesPIDs setObject:[NSNumber numberWithInt:pid] forKey:identifier];
      NSLog(@"NetworkVolumeManager: Stored sshfs PID %d for service %@", pid, identifier);
    }

    NSLog(@"NetworkVolumeManager: Successfully mounted %@ at %@", 
          [serviceItem name], mountPoint);

    /* Mark the mount point in the FSNode cache so UI displays mountpoint icons */
    @try {
      FSNode *vnode = [FSNode nodeWithPath: mountPoint];
      if (vnode) {
        [vnode setMountPoint: YES];
      }
      [[FSNodeRep sharedInstance] addVolumeAt: mountPoint];
      NSLog(@"NetworkVolumeManager: FSNodeRep volumes now: %@", [[FSNodeRep sharedInstance] volumes]);
    } @catch (NSException *e) {
      NSLog(@"NetworkVolumeManager: Error marking volume: %@", e);
    }

    /* Notify parent directory that a new entry has appeared so viewers refresh */
    NSString *parent = [mountPoint stringByDeletingLastPathComponent];
    NSString *name = [mountPoint lastPathComponent];
    NSDictionary *opinfo = @{ @"operation": @"MountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name] };

    [[NSNotificationCenter defaultCenter]
      postNotificationName:@"GWFileSystemDidChangeNotification"
                    object:opinfo];
    
    /* Also notify desktop manager directly so the volume appears on the desktop */
    NSLog(@"NetworkVolumeManager: Notifying desktop manager directly for mount %@", mountPoint);
    id gworkspace = [Workspace gworkspace];
    if (gworkspace) {
      id desktopManager = [gworkspace desktopManager];
      if (desktopManager && [[desktopManager desktopView] respondsToSelector:@selector(newVolumeMountedAtPath:)]) {
        [[desktopManager desktopView] newVolumeMountedAtPath: mountPoint];
      }
    }

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
  return [self unmountPath:mountPoint];
}

- (BOOL)unmountPath:(NSString *)path
{
  if (!path) return NO;

  /* Find the service identifier for this path to get the PID */
  NSString *foundId = nil;
  for (NSString *ident in [mountedVolumes allKeys]) {
    NSString *mp = [mountedVolumes objectForKey:ident];
    if ([mp isEqualToString:path]) {
      foundId = ident;
      break;
    }
  }

  /* Remove filesystem watchers to prevent "target is busy" errors */
  id gworkspace = [Workspace gworkspace];
  if (gworkspace) {
    NSLog(@"NetworkVolumeManager: Removing filesystem watchers for %@", path);
    [gworkspace removeWatcherForPath:path];
    
    /* Also try to remove watchers for any subdirectories that might be watched */
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:path error:nil];
    if (contents) {
      for (NSString *item in contents) {
        NSString *itemPath = [path stringByAppendingPathComponent:item];
        BOOL isDirectory;
        if ([fileManager fileExistsAtPath:itemPath isDirectory:&isDirectory] && isDirectory) {
          [gworkspace removeWatcherForPath:itemPath];
        }
      }
    }
  }

  /* Notify viewers that an unmount is about to occur so they can close windows */
  NSString *parent = [path stringByDeletingLastPathComponent];
  NSString *name = [path lastPathComponent];
  NSDictionary *willInfo = @{ @"operation": @"UnmountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name] };

  [[NSNotificationCenter defaultCenter]
    postNotificationName:@"GWFileSystemWillChangeNotification"
                  object:willInfo];
  
  /* Notify viewers and desktop that an unmount is about to occur */

  /* Wait for viewers to close and watchers to be removed to prevent "target is busy" */
  NSLog(@"NetworkVolumeManager: Waiting for viewers and watchers to close...");
  [NSThread sleepForTimeInterval:2.0];

  BOOL unmountSuccess = NO;
  
  /* First try to kill the sshfs process if we have its PID */
  if (foundId) {
    NSNumber *pidNumber = [mountedVolumesPIDs objectForKey:foundId];
    if (pidNumber) {
      int pid = [pidNumber intValue];
      NSLog(@"NetworkVolumeManager: Killing sshfs process %d for %@", pid, path);
      
      /* Send SIGTERM first, then SIGKILL if needed */
      if (kill(pid, SIGTERM) == 0) {
        NSLog(@"NetworkVolumeManager: Sent SIGTERM to process %d", pid);
        /* Wait briefly for graceful shutdown */
        usleep(500000); /* 0.5 seconds */
        
        /* Check if process is still running */
        if (kill(pid, 0) == 0) {
          /* Process still exists, force kill */
          NSLog(@"NetworkVolumeManager: Process %d still running, sending SIGKILL", pid);
          if (kill(pid, SIGKILL) == 0) {
            NSLog(@"NetworkVolumeManager: Sent SIGKILL to process %d", pid);
          }
        } else {
          NSLog(@"NetworkVolumeManager: Process %d terminated after SIGTERM", pid);
        }
        
        /* Wait a bit more for the FUSE filesystem to clean up */
        usleep(1000000); /* 1 second */
        
        unmountSuccess = YES;
        NSLog(@"NetworkVolumeManager: Successfully killed sshfs process %d", pid);
      } else {
        NSLog(@"NetworkVolumeManager: Failed to kill process %d: %s", pid, strerror(errno));
        /* Process may already be dead or we don't have permission */
        if (errno == ESRCH) {
          NSLog(@"NetworkVolumeManager: Process %d no longer exists", pid);
          unmountSuccess = YES; /* Process is gone, that's what we wanted */
        }
      }
    }
  }
  
  /* Also try fusermount as fallback/cleanup */
  if (!unmountSuccess) {
    NSLog(@"NetworkVolumeManager: Trying fusermount -u as fallback");
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/bin/fusermount"];
    [task setArguments:@[@"-u", path]];

    @try {
      [task launch];
      [task waitUntilExit];

      int status = [task terminationStatus];
      [task release];

      if (status == 0) {
        NSLog(@"NetworkVolumeManager: fusermount succeeded");
        unmountSuccess = YES;
      } else {
        NSLog(@"NetworkVolumeManager: fusermount failed with status %d, trying alternative approaches", status);
        
        /* Try umount as alternative */
        NSTask *umountTask = [[NSTask alloc] init];
        [umountTask setLaunchPath:@"/usr/bin/umount"];
        [umountTask setArguments:@[path]];
        
        @try {
          [umountTask launch];
          [umountTask waitUntilExit];
          
          if ([umountTask terminationStatus] == 0) {
            NSLog(@"NetworkVolumeManager: umount succeeded");
            unmountSuccess = YES;
          } else {
            NSLog(@"NetworkVolumeManager: umount failed with status %d", [umountTask terminationStatus]);
          }
        } @catch (NSException *e) {
          NSLog(@"NetworkVolumeManager: umount exception: %@", e);
        }
        [umountTask release];
      }
    } @catch (NSException *exception) {
      NSLog(@"NetworkVolumeManager: Exception while running fusermount: %@", exception);
      [task release];
    }
  } else {
    NSLog(@"NetworkVolumeManager: Process kill succeeded, attempting cleanup with fusermount");
    /* Even if kill succeeded, try fusermount for cleanup */
    NSTask *cleanupTask = [[NSTask alloc] init];
    [cleanupTask setLaunchPath:@"/usr/bin/fusermount"];
    [cleanupTask setArguments:@[@"-u", path]];
    
    @try {
      [cleanupTask launch];
      [cleanupTask waitUntilExit];
      
      if ([cleanupTask terminationStatus] != 0) {
        NSLog(@"NetworkVolumeManager: Cleanup fusermount failed (but process kill succeeded)");
      }
    } @catch (NSException *e) {
      NSLog(@"NetworkVolumeManager: Cleanup fusermount exception: %@", e);
    }
    [cleanupTask release];
  }

  if (unmountSuccess) {
    /* Clean up our tracking data */
    if (foundId) {
      [mountedVolumes removeObjectForKey:foundId];
      [mountedVolumesPIDs removeObjectForKey:foundId];
    }

    /* Clear FSNode/FSNodeRep state */
    @try {
      FSNode *vnode = [FSNode nodeWithPath:path];
      if (vnode) {
        [vnode setMountPoint:NO];
      }
      [[FSNodeRep sharedInstance] removeVolumeAt:path];
    } @catch (NSException *e) {
      NSLog(@"NetworkVolumeManager: Error clearing volume info: %@", e);
    }

    /* Attempt to remove empty mountpoint directory */
    @try {
      NSError *contentsErr = nil;
      NSArray *contents = [fm contentsOfDirectoryAtPath:path error:&contentsErr];
      if (contents && ([contents count] == 0)) {
        if ([fm removeItemAtPath:path error:&contentsErr]) {
          NSLog(@"NetworkVolumeManager: Removed empty mount point %@", path);
        } else {
          NSLog(@"NetworkVolumeManager: Failed to remove mount point %@: %@", path, contentsErr);
        }
      } else if (contentsErr) {
        NSLog(@"NetworkVolumeManager: Could not read mount point contents %@: %@", path, contentsErr);
      } else {
        NSLog(@"NetworkVolumeManager: Mount point %@ not empty, leaving in place", path);
      }
    } @catch (NSException *e) {
      NSLog(@"NetworkVolumeManager: Exception checking/removing mount point %@: %@", path, e);
    }

    /* Notify viewers to close and refresh parent directory */
    NSDictionary *opinfo = @{ @"operation": @"UnmountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name],
                              @"unmounted": path };

    [[NSNotificationCenter defaultCenter]
      postNotificationName:@"GWFileSystemDidChangeNotification"
                    object:opinfo];
                    
    /* Also notify desktop manager directly so volume disappears from desktop */
    NSLog(@"NetworkVolumeManager: Notifying desktop manager directly for unmount %@", path);
    id gworkspace = [Workspace gworkspace];
    if (gworkspace) {
      id desktopManager = [gworkspace desktopManager];
      if (desktopManager && [[desktopManager desktopView] respondsToSelector:@selector(workspaceDidUnmountVolumeAtPath:)]) {
        [[desktopManager desktopView] workspaceDidUnmountVolumeAtPath: path];
      }
    }
                    
    NSLog(@"NetworkVolumeManager: Sent completion notification for unmount of %@", path);

    return YES;
  } else {
    NSLog(@"NetworkVolumeManager: All unmount attempts failed for %@", path);
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
