/* VolumeManager.m
 *
 * Implementation of disk image volume mounting
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <signal.h>
#import <errno.h>
#import <unistd.h>
#import <sys/statfs.h>
#import "VolumeManager.h"
#import "Workspace.h"
#import "FSNode/FSNode.h"
#import "FSNode/FSNodeRep.h"
#import "Desktop/GWDesktopManager.h"
#import "Desktop/GWDesktopView.h"

static VolumeManager *sharedInstance = nil;

@implementation VolumeMountResult

@synthesize success, mountPoint, errorMessage, processId;

+ (VolumeMountResult *)successWithPath:(NSString *)path pid:(int)pid
{
  VolumeMountResult *result = [[VolumeMountResult alloc] init];
  result.success = YES;
  result.mountPoint = path;
  result.processId = pid;
  return [result autorelease];
}

+ (VolumeMountResult *)failureWithError:(NSString *)error
{
  VolumeMountResult *result = [[VolumeMountResult alloc] init];
  result.success = NO;
  result.errorMessage = error;
  return [result autorelease];
}

- (void)dealloc
{
  [mountPoint release];
  [errorMessage release];
  [super dealloc];
}

@end

@implementation VolumeManager

+ (VolumeManager *)sharedManager
{
  if (sharedInstance == nil) {
    sharedInstance = [[VolumeManager alloc] init];
  }
  return sharedInstance;
}

+ (BOOL)isDiskImageMount:(NSString *)path
{
  if (!path) return NO;
  VolumeManager *manager = [VolumeManager sharedManager];
  @synchronized(manager) {
    return [manager->diskImageMountPoints containsObject:path];
  }
}

- (id)init
{
  self = [super init];
  if (self) {
    mountedVolumes = [[NSMutableDictionary alloc] init];
    mountedVolumesPIDs = [[NSMutableDictionary alloc] init];
    diskImageMountPoints = [[NSMutableSet alloc] init];
    fm = [NSFileManager defaultManager];
    NSLog(@"VolumeManager: Initialized");
  }
  return self;
}

- (void)dealloc
{
  [self unmountAll];
  [mountedVolumes release];
  [mountedVolumesPIDs release];
  [diskImageMountPoints release];
  [super dealloc];
}

- (NSString *)findToolInPath:(NSString *)toolName alternativeNames:(NSArray *)altNames
{
  /* First try the tool name directly in standard locations */
  NSArray *searchPaths = @[@"/usr/bin", @"/bin", @"/usr/local/bin", @"/opt/local/bin"];
  
  for (NSString *path in searchPaths) {
    NSString *toolPath = [path stringByAppendingPathComponent:toolName];
    if ([fm fileExistsAtPath:toolPath]) {
      NSLog(@"VolumeManager: Found %@ at %@", toolName, toolPath);
      return toolPath;
    }
  }
  
  /* Try alternative names */
  if (altNames) {
    for (NSString *altName in altNames) {
      for (NSString *path in searchPaths) {
        NSString *toolPath = [path stringByAppendingPathComponent:altName];
        if ([fm fileExistsAtPath:toolPath]) {
          NSLog(@"VolumeManager: Found %@ (alternative) at %@", altName, toolPath);
          return toolPath;
        }
      }
    }
  }
  
  /* Try to find via 'which' command */
  @try {
    NSTask *whichTask = [[NSTask alloc] init];
    [whichTask setLaunchPath:@"/usr/bin/which"];
    [whichTask setArguments:@[toolName]];
    
    NSPipe *outPipe = [NSPipe pipe];
    [whichTask setStandardOutput:outPipe];
    [whichTask setStandardError:[NSPipe pipe]];
    
    [whichTask launch];
    [whichTask waitUntilExit];
    
    if ([whichTask terminationStatus] == 0) {
      NSData *data = [[outPipe fileHandleForReading] availableData];
      NSString *result = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
      result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      [whichTask release];
      if ([result length] > 0) {
        NSLog(@"VolumeManager: Found %@ via which: %@", toolName, result);
        return result;
      }
    }
    [whichTask release];
  } @catch (NSException *e) {
    NSLog(@"VolumeManager: Exception in findToolInPath: %@", e);
  }
  
  NSLog(@"VolumeManager: Tool %@ not found", toolName);
  return nil;
}

- (BOOL)isDarlingDmgAvailable
{
  return [self findToolInPath:@"darling-dmg" alternativeNames:nil] != nil;
}

- (BOOL)isFuseisoAvailable
{
  return [self findToolInPath:@"fuseiso" alternativeNames:nil] != nil;
}

- (void)showDarlingDmgNotInstalledAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"darling-dmg Not Installed"];
  [alert setInformativeText:
    @"darling-dmg is required to mount DMG files but is not installed.\n\n"
    @"To install darling-dmg, see:\n"
    @"https://github.com/darlinghq/darling"];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

- (void)showFuseisoNotInstalledAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"fuseiso Not Installed"];
  [alert setInformativeText:
    @"fuseiso is required to mount ISO/BIN/NRG/IMG/MDF files.\n\n"
    @"To install it:\n"
    @"• Debian/Ubuntu: sudo apt-get install fuseiso\n"
    @"• Fedora: sudo dnf install fuseiso\n"
    @"• Arch: sudo pacman -S fuseiso"];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

- (void)showErrorAlert:(NSString *)errorMsg
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Mount Error"];
  [alert setInformativeText:errorMsg];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

- (NSString *)mountPointForImageFile:(NSString *)imagePath
{
  return [mountedVolumes objectForKey:imagePath];
}

- (BOOL)isMountPointActive:(NSString *)mountPoint
{
  struct statfs statbuf;
  if (statfs([mountPoint UTF8String], &statbuf) == 0) {
    return YES;
  }
  return NO;
}

- (NSString *)createMountPointForDMG:(NSString *)dmgPath
{
  NSString *userName = NSUserName();
  NSString *mediaDir = [@"/media" stringByAppendingPathComponent:userName];
  
  BOOL isDir;
  if (![fm fileExistsAtPath:mediaDir isDirectory:&isDir]) {
    NSError *error = nil;
    if (![fm createDirectoryAtPath:mediaDir 
       withIntermediateDirectories:YES 
                        attributes:nil 
                             error:&error]) {
      NSLog(@"VolumeManager: Failed to create media directory: %@", error);
      return nil;
    }
  }
  
  NSString *dmgName = [[dmgPath lastPathComponent] stringByDeletingPathExtension];
  NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
  NSArray *components = [dmgName componentsSeparatedByCharactersInSet:invalidChars];
  NSString *sanitizedName = [components componentsJoinedByString:@"-"];
  
  if ([sanitizedName length] == 0) {
    sanitizedName = @"DiskImage";
  }
  
  NSString *mountPoint = [mediaDir stringByAppendingPathComponent:sanitizedName];
  int counter = 2;
  
  while ([fm fileExistsAtPath:mountPoint]) {
    if ([fm fileExistsAtPath:mountPoint isDirectory:&isDir] && isDir) {
      NSError *contentsError = nil;
      NSArray *contents = [fm contentsOfDirectoryAtPath:mountPoint error:&contentsError];
      if (!contentsError && [contents count] == 0) {
        NSLog(@"VolumeManager: Reusing empty directory at %@", mountPoint);
        return mountPoint;
      }
    }
    
    mountPoint = [mediaDir stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"%@-%d", sanitizedName, counter]];
    counter++;
    
    if (counter > 100) {
      NSLog(@"VolumeManager: Too many mount point attempts");
      return nil;
    }
  }
  
  NSError *error = nil;
  if (![fm createDirectoryAtPath:mountPoint 
     withIntermediateDirectories:YES 
                      attributes:nil 
                           error:&error]) {
    NSLog(@"VolumeManager: Failed to create mount point: %@", error);
    return nil;
  }
  
  return mountPoint;
}

- (NSString *)createMountPointForISO:(NSString *)isoPath
{
  NSString *userName = NSUserName();
  NSString *mediaDir = [@"/media" stringByAppendingPathComponent:userName];
  
  BOOL isDir;
  if (![fm fileExistsAtPath:mediaDir isDirectory:&isDir]) {
    NSError *error = nil;
    if (![fm createDirectoryAtPath:mediaDir 
       withIntermediateDirectories:YES 
                        attributes:nil 
                             error:&error]) {
      NSLog(@"VolumeManager: Failed to create media directory: %@", error);
      return nil;
    }
  }
  
  NSString *isoName = [[isoPath lastPathComponent] stringByDeletingPathExtension];
  NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
  NSArray *components = [isoName componentsSeparatedByCharactersInSet:invalidChars];
  NSString *sanitizedName = [components componentsJoinedByString:@"-"];
  
  if ([sanitizedName length] == 0) {
    sanitizedName = @"ISOImage";
  }
  
  NSString *mountPoint = [mediaDir stringByAppendingPathComponent:sanitizedName];
  int counter = 2;
  
  while ([fm fileExistsAtPath:mountPoint]) {
    if ([fm fileExistsAtPath:mountPoint isDirectory:&isDir] && isDir) {
      NSError *contentsError = nil;
      NSArray *contents = [fm contentsOfDirectoryAtPath:mountPoint error:&contentsError];
      if (!contentsError && [contents count] == 0) {
        NSLog(@"VolumeManager: Reusing empty directory at %@", mountPoint);
        return mountPoint;
      }
    }
    
    mountPoint = [mediaDir stringByAppendingPathComponent:
                  [NSString stringWithFormat:@"%@-%d", sanitizedName, counter]];
    counter++;
    
    if (counter > 100) {
      return nil;
    }
  }
  
  NSError *error = nil;
  if (![fm createDirectoryAtPath:mountPoint 
     withIntermediateDirectories:YES 
                      attributes:nil 
                           error:&error]) {
    NSLog(@"VolumeManager: Failed to create mount point: %@", error);
    return nil;
  }
  
  return mountPoint;
}

- (void)registerVolumeWithDesktop:(NSString *)mountPoint
{
  [self registerVolumeWithDesktop:mountPoint isDiskImage:NO];
}

- (void)registerVolumeWithDesktop:(NSString *)mountPoint isDiskImage:(BOOL)isDiskImage
{
  /* Mark as mount point and register with desktop */
  @try {
    FSNode *vnode = [FSNode nodeWithPath:mountPoint];
    if (vnode) {
      [vnode setMountPoint:YES];
      NSLog(@"VolumeManager: Marked %@ as mount point", mountPoint);
    }
    
    [[FSNodeRep sharedInstance] addVolumeAt:mountPoint isDiskImage:isDiskImage];
    NSLog(@"VolumeManager: Registered volume with FSNodeRep (isDiskImage=%d)", isDiskImage);
    
    /* Notify the desktop view directly (critical for volume to appear on desktop) */
    id gworkspace = [Workspace gworkspace];
    if (!gworkspace) {
      NSLog(@"VolumeManager: WARNING - gworkspace is nil, cannot notify desktop");
    } else {
      id desktopManager = [gworkspace desktopManager];
      if (!desktopManager) {
        NSLog(@"VolumeManager: WARNING - desktopManager is nil, cannot notify desktop");
      } else {
        id desktopView = [desktopManager desktopView];
        if (!desktopView) {
          NSLog(@"VolumeManager: WARNING - desktopView is nil");
        } else if (![desktopView respondsToSelector:@selector(newVolumeMountedAtPath:)]) {
          NSLog(@"VolumeManager: WARNING - desktopView does not respond to newVolumeMountedAtPath:");
        } else {
          [desktopView newVolumeMountedAtPath: mountPoint];
          NSLog(@"VolumeManager: Notified desktop view to show mount at %@", mountPoint);
        }
      }
    }
  } @catch (NSException *e) {
    NSLog(@"VolumeManager: Error registering volume: %@", e);
  }
}

- (NSString *)mountDMGFile:(NSString *)dmgPath
{
  NSString *existingMount = [self mountPointForImageFile:dmgPath];
  if (existingMount) {
    if ([self isMountPointActive:existingMount]) {
      NSLog(@"VolumeManager: DMG already mounted at %@", existingMount);
      return existingMount;
    } else {
      [mountedVolumes removeObjectForKey:dmgPath];
      [mountedVolumesPIDs removeObjectForKey:dmgPath];
    }
  }
  
  if (![fm fileExistsAtPath:dmgPath]) {
    [self showErrorAlert:[NSString stringWithFormat:@"DMG file not found: %@", dmgPath]];
    return nil;
  }
  
  if (![self isDarlingDmgAvailable]) {
    [self showDarlingDmgNotInstalledAlert];
    return nil;
  }
  
  NSString *mountPoint = [self createMountPointForDMG:dmgPath];
  if (!mountPoint) {
    [self showErrorAlert:@"Failed to create mount point"];
    return nil;
  }
  
  NSLog(@"VolumeManager: Mounting DMG %@ at %@", dmgPath, mountPoint);
  
  NSTask *dmgTask = [[NSTask alloc] init];
  NSString *darlingDmgPath = [self findToolInPath:@"darling-dmg" alternativeNames:nil];
  if (!darlingDmgPath) {
    [dmgTask release];
    [self showErrorAlert:@"darling-dmg tool not found"];
    return nil;
  }
  
  [dmgTask setLaunchPath:darlingDmgPath];
  [dmgTask setArguments:@[dmgPath, mountPoint]];
  
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  [dmgTask setStandardOutput:outPipe];
  [dmgTask setStandardError:errPipe];
  
  @try {
    [dmgTask launch];
    
    int waitCount = 0;
    while (waitCount < 30 && ![self isMountPointActive:mountPoint]) {
      usleep(100000);
      waitCount++;
    }
    
    if ([self isMountPointActive:mountPoint]) {
      NSLog(@"VolumeManager: Successfully mounted DMG at %@", mountPoint);
      
      int taskPid = [dmgTask processIdentifier];
      [mountedVolumes setObject:mountPoint forKey:dmgPath];
      [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:dmgPath];
      [diskImageMountPoints addObject:mountPoint];
      
      /* Register with desktop to show on desktop and in viewers */
      [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
      
      /* Notify filesystem observers */
      NSString *parent = [mountPoint stringByDeletingLastPathComponent];
      NSString *name = [mountPoint lastPathComponent];
      [[NSNotificationCenter defaultCenter]
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:@{@"operation": @"MountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name]}];
      
      return mountPoint;
    } else {
      NSData *errData = [[errPipe fileHandleForReading] availableData];
      NSString *errString = @"";
      if (errData && [errData length] > 0) {
        errString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] autorelease];
      }
      
      NSData *outData = [[outPipe fileHandleForReading] availableData];
      NSString *outString = @"";
      if (outData && [outData length] > 0) {
        outString = [[[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] autorelease];
      }
      
      NSString *allOutput = [NSString stringWithFormat:@"%@ %@", outString, errString];
      
      if ([allOutput containsString:@"Everything looks OK, disk mounted"] || [self isMountPointActive:mountPoint]) {
        NSLog(@"VolumeManager: Successfully mounted DMG at %@ (verified)", mountPoint);
        
        int taskPid = [dmgTask processIdentifier];
        [mountedVolumes setObject:mountPoint forKey:dmgPath];
        [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:dmgPath];        [diskImageMountPoints addObject:mountPoint];        
        [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
        
        NSString *parent = [mountPoint stringByDeletingLastPathComponent];
        NSString *name = [mountPoint lastPathComponent];
        [[NSNotificationCenter defaultCenter]
          postNotificationName:@"GWFileSystemDidChangeNotification"
                        object:@{@"operation": @"MountOperation",
                                @"source": parent,
                                @"destination": parent,
                                @"files": @[name]}];
        
        [dmgTask release];
        return mountPoint;
      }
      
      NSLog(@"VolumeManager: Failed to mount DMG: %@", allOutput);
      
      if ([dmgTask isRunning]) {
        [dmgTask terminate];
        sleep(1);
        if ([dmgTask isRunning]) {
          kill([dmgTask processIdentifier], SIGKILL);
        }
      }
      
      [dmgTask release];
      [fm removeItemAtPath:mountPoint error:nil];
      [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount DMG:\n%@", allOutput]];
      return nil;
    }
  }
  @catch (NSException *exception) {
    NSLog(@"VolumeManager: Exception during mount: %@", exception);
    [dmgTask release];
    [fm removeItemAtPath:mountPoint error:nil];
    [self showErrorAlert:[NSString stringWithFormat:@"Exception: %@", [exception reason]]];
    return nil;
  }
}

- (NSString *)mountISOFile:(NSString *)isoPath
{
  NSString *existingMount = [self mountPointForImageFile:isoPath];
  if (existingMount) {
    if ([self isMountPointActive:existingMount]) {
      NSLog(@"VolumeManager: ISO already mounted at %@", existingMount);
      return existingMount;
    } else {
      [mountedVolumes removeObjectForKey:isoPath];
      [mountedVolumesPIDs removeObjectForKey:isoPath];
    }
  }
  
  if (![fm fileExistsAtPath:isoPath]) {
    [self showErrorAlert:[NSString stringWithFormat:@"ISO file not found: %@", isoPath]];
    return nil;
  }
  
  if (![self isFuseisoAvailable]) {
    [self showFuseisoNotInstalledAlert];
    return nil;
  }
  
  NSString *mountPoint = [self createMountPointForISO:isoPath];
  if (!mountPoint) {
    [self showErrorAlert:@"Failed to create mount point"];
    return nil;
  }
  
  NSLog(@"VolumeManager: Mounting ISO %@ at %@", isoPath, mountPoint);
  
  NSTask *isoTask = [[NSTask alloc] init];
  NSString *fuseisoPath = [self findToolInPath:@"fuseiso" alternativeNames:nil];
  if (!fuseisoPath) {
    [isoTask release];
    [self showErrorAlert:@"fuseiso tool not found"];
    return nil;
  }
  
  [isoTask setLaunchPath:fuseisoPath];
  [isoTask setArguments:@[isoPath, mountPoint]];
  
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  [isoTask setStandardOutput:outPipe];
  [isoTask setStandardError:errPipe];
  
  @try {
    [isoTask launch];
    
    int waitCount = 0;
    while (waitCount < 30 && ![self isMountPointActive:mountPoint]) {
      usleep(100000);
      waitCount++;
    }
    
    if ([self isMountPointActive:mountPoint]) {
      NSLog(@"VolumeManager: Successfully mounted ISO at %@", mountPoint);
      
      int taskPid = [isoTask processIdentifier];
      [mountedVolumes setObject:mountPoint forKey:isoPath];
      [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:isoPath];
      [diskImageMountPoints addObject:mountPoint];
      
      [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
      
      NSString *parent = [mountPoint stringByDeletingLastPathComponent];
      NSString *name = [mountPoint lastPathComponent];
      [[NSNotificationCenter defaultCenter]
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:@{@"operation": @"MountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name]}];
      
      return mountPoint;
    } else {
      NSData *errData = [[errPipe fileHandleForReading] availableData];
      NSString *errString = @"";
      if (errData) {
        errString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] autorelease];
      }
      
      if ([self isMountPointActive:mountPoint]) {
        NSLog(@"VolumeManager: Successfully mounted ISO at %@ (verified)", mountPoint);
        
        int taskPid = [isoTask processIdentifier];
        [mountedVolumes setObject:mountPoint forKey:isoPath];
        [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:isoPath];
        [diskImageMountPoints addObject:mountPoint];
        
        [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
        
        NSString *parent = [mountPoint stringByDeletingLastPathComponent];
        NSString *name = [mountPoint lastPathComponent];
        [[NSNotificationCenter defaultCenter]
          postNotificationName:@"GWFileSystemDidChangeNotification"
                        object:@{@"operation": @"MountOperation",
                                @"source": parent,
                                @"destination": parent,
                                @"files": @[name]}];
        
        [isoTask release];
        return mountPoint;
      }
      
      NSLog(@"VolumeManager: Failed to mount ISO: %@", errString);
      
      if ([isoTask isRunning]) {
        [isoTask terminate];
        sleep(1);
        if ([isoTask isRunning]) {
          kill([isoTask processIdentifier], SIGKILL);
        }
      }
      
      [isoTask release];
      [fm removeItemAtPath:mountPoint error:nil];
      [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount ISO:\n%@", errString]];
      return nil;
    }
  }
  @catch (NSException *exception) {
    NSLog(@"VolumeManager: Exception: %@", exception);
    [isoTask release];
    [fm removeItemAtPath:mountPoint error:nil];
    [self showErrorAlert:[NSString stringWithFormat:@"Exception: %@", [exception reason]]];
    return nil;
  }
}

- (NSString *)mountFuseisoImage:(NSString *)imagePath
{
  NSString *extension = [[imagePath pathExtension] lowercaseString];
  
  if ([extension isEqualToString:@"iso"]) {
    return [self mountISOFile:imagePath];
  }
  
  NSString *existingMount = [self mountPointForImageFile:imagePath];
  if (existingMount && [self isMountPointActive:existingMount]) {
    NSLog(@"VolumeManager: Image already mounted at %@", existingMount);
    return existingMount;
  }
  
  if (![self isFuseisoAvailable]) {
    [self showFuseisoNotInstalledAlert];
    return nil;
  }
  
  NSString *mountPoint = [self createMountPointForISO:imagePath];
  if (!mountPoint) {
    [self showErrorAlert:@"Failed to create mount point"];
    return nil;
  }
  
  NSLog(@"VolumeManager: Mounting %@ image at %@", extension, mountPoint);
  
  NSTask *fuseTask = [[NSTask alloc] init];
  NSString *fuseisoPath = [self findToolInPath:@"fuseiso" alternativeNames:nil];
  if (!fuseisoPath) {
    [fuseTask release];
    [self showErrorAlert:@"fuseiso tool not found"];
    return nil;
  }
  
  [fuseTask setLaunchPath:fuseisoPath];
  [fuseTask setArguments:@[imagePath, mountPoint]];
  
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  [fuseTask setStandardOutput:outPipe];
  [fuseTask setStandardError:errPipe];
  
  @try {
    [fuseTask launch];
    
    int waitCount = 0;
    while (waitCount < 30 && ![self isMountPointActive:mountPoint]) {
      usleep(100000);
      waitCount++;
    }
    
    if ([self isMountPointActive:mountPoint]) {
      NSLog(@"VolumeManager: Successfully mounted at %@", mountPoint);
      
      int taskPid = [fuseTask processIdentifier];
      [mountedVolumes setObject:mountPoint forKey:imagePath];
      [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:imagePath];
      [diskImageMountPoints addObject:mountPoint];
      
      [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
      
      NSString *parent = [mountPoint stringByDeletingLastPathComponent];
      NSString *name = [mountPoint lastPathComponent];
      [[NSNotificationCenter defaultCenter]
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:@{@"operation": @"MountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name]}];
      
      [fuseTask release];
      return mountPoint;
    }
    
    NSData *errData = [[errPipe fileHandleForReading] availableData];
    NSString *errString = @"";
    if (errData) {
      errString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] autorelease];
    }
    
    if ([self isMountPointActive:mountPoint]) {
      NSLog(@"VolumeManager: Mounted (verified)");
      
      int taskPid = [fuseTask processIdentifier];
      [mountedVolumes setObject:mountPoint forKey:imagePath];
      [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:imagePath];
      [diskImageMountPoints addObject:mountPoint];
      
      [self registerVolumeWithDesktop:mountPoint isDiskImage:YES];
      
      NSString *parent = [mountPoint stringByDeletingLastPathComponent];
      NSString *name = [mountPoint lastPathComponent];
      [[NSNotificationCenter defaultCenter]
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:@{@"operation": @"MountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name]}];
      
      [fuseTask release];
      return mountPoint;
    }
    
    if ([fuseTask isRunning]) {
      [fuseTask terminate];
      sleep(1);
      if ([fuseTask isRunning]) {
        kill([fuseTask processIdentifier], SIGKILL);
      }
    }
    
    [fuseTask release];
    [fm removeItemAtPath:mountPoint error:nil];
    [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount:\n%@", errString]];
    return nil;
  }
  @catch (NSException *exception) {
    [fuseTask release];
    [fm removeItemAtPath:mountPoint error:nil];
    [self showErrorAlert:[NSString stringWithFormat:@"Exception: %@", [exception reason]]];
    return nil;
  }
}

- (BOOL)unmountImageFile:(NSString *)imagePath
{
  NSString *mountPoint = [mountedVolumes objectForKey:imagePath];
  if (!mountPoint) {
    return NO;
  }
  return [self unmountPath:mountPoint];
}

- (BOOL)unmountPath:(NSString *)mountPath
{
  if (!mountPath) return NO;
  
  /* Send will-unmount notification to grey out desktop icon */
  NSString *parent = [mountPath stringByDeletingLastPathComponent];
  NSString *name = [mountPath lastPathComponent];
  NSDictionary *unmountInfo = @{ @"NSDevicePath": mountPath };
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NSWorkspaceWillUnmountNotification
                  object:[NSWorkspace sharedWorkspace]
                userInfo:unmountInfo];
  
  NSLog(@"VolumeManager: Sent will unmount notification for %@", mountPath);
  
  BOOL unmountSuccess = NO;
  
  /* Try to kill the FUSE process if we have its PID */
  NSString *foundKey = nil;
  for (NSString *key in [mountedVolumes allKeys]) {
    if ([[mountedVolumes objectForKey:key] isEqualToString:mountPath]) {
      foundKey = key;
      break;
    }
  }
  
  if (foundKey) {
    NSNumber *pidNumber = [mountedVolumesPIDs objectForKey:foundKey];
    if (pidNumber) {
      int pid = [pidNumber intValue];
      NSLog(@"VolumeManager: Killing FUSE process %d for %@", pid, mountPath);
      
      if (kill(pid, SIGTERM) == 0) {
        NSLog(@"VolumeManager: Sent SIGTERM to process %d", pid);
        usleep(500000); /* 0.5 seconds */
        
        if (kill(pid, 0) == 0) {
          NSLog(@"VolumeManager: Process %d still running, sending SIGKILL", pid);
          kill(pid, SIGKILL);
        }
        usleep(1000000); /* 1 second for cleanup */
        unmountSuccess = YES;
      } else if (errno == ESRCH) {
        NSLog(@"VolumeManager: Process %d no longer exists", pid);
        unmountSuccess = YES;
      }
    }
  }
  
  /* Try fusermount as fallback/cleanup */
  if (!unmountSuccess) {
    NSString *fusermountPath = [self findToolInPath:@"fusermount" alternativeNames:@[@"fusermount3"]];
    if (fusermountPath) {
      NSTask *unmountTask = [[NSTask alloc] init];
      [unmountTask setLaunchPath:fusermountPath];
      [unmountTask setArguments:@[@"-u", mountPath]];
      
      @try {
        [unmountTask launch];
        [unmountTask waitUntilExit];
        if ([unmountTask terminationStatus] == 0) {
          unmountSuccess = YES;
          NSLog(@"VolumeManager: fusermount succeeded");
        }
        [unmountTask release];
      } @catch (NSException *e) {
        NSLog(@"VolumeManager: fusermount exception: %@", e);
        [unmountTask release];
      }
    }
  }
  
  /* Try umount as final fallback */
  if (!unmountSuccess) {
    NSTask *umountTask = [[NSTask alloc] init];
    [umountTask setLaunchPath:@"/bin/umount"];
    [umountTask setArguments:@[mountPath]];
    
    @try {
      [umountTask launch];
      [umountTask waitUntilExit];
      if ([umountTask terminationStatus] == 0) {
        unmountSuccess = YES;
        NSLog(@"VolumeManager: umount succeeded");
      }
      [umountTask release];
    } @catch (NSException *e) {
      [umountTask release];
    }
  }
  
  if (unmountSuccess) {
    /* Clean up tracking data */
    if (foundKey) {
      [mountedVolumes removeObjectForKey:foundKey];
      [mountedVolumesPIDs removeObjectForKey:foundKey];
    }
    @synchronized(self) {
      [diskImageMountPoints removeObject:mountPath];
    }
    
    /* Clear FSNode/FSNodeRep state */
    @try {
      FSNode *vnode = [FSNode nodeWithPath:mountPath];
      if (vnode) {
        [vnode setMountPoint:NO];
      }
      [[FSNodeRep sharedInstance] removeVolumeAt:mountPath];
    } @catch (NSException *e) {
      NSLog(@"VolumeManager: Error clearing volume info: %@", e);
    }
    
    /* Attempt to remove empty mount directory (non-recursively) */
    BOOL directoryRemoved = NO;
    @try {
      NSError *contentsErr = nil;
      NSArray *contents = [fm contentsOfDirectoryAtPath:mountPath error:&contentsErr];
      if (contents && [contents count] == 0) {
        if (rmdir([mountPath fileSystemRepresentation]) == 0) {
          NSLog(@"VolumeManager: Removed empty mount point %@", mountPath);
          directoryRemoved = YES;
        } else {
          NSLog(@"VolumeManager: Failed to remove mount point %@ (rmdir): %s", mountPath, strerror(errno));
        }
      } else if (contentsErr) {
        NSLog(@"VolumeManager: Could not read mount point contents %@: %@", mountPath, contentsErr);
      } else {
        NSLog(@"VolumeManager: Mount point %@ not empty (%lu items), leaving in place",
              mountPath, (unsigned long)[contents count]);
      }
    } @catch (NSException *e) {
      NSLog(@"VolumeManager: Exception checking/removing mount point %@: %@", mountPath, e);
    }
    
    /* Only remove desktop icon AFTER directory successfully removed */
    if (directoryRemoved) {
      NSLog(@"VolumeManager: Directory removed successfully, notifying desktop to remove icon for %@", mountPath);
      
      NSDictionary *opinfo = @{ @"operation": @"UnmountOperation",
                                @"source": parent,
                                @"destination": parent,
                                @"files": @[name],
                                @"unmounted": mountPath };
      
      [[NSNotificationCenter defaultCenter]
        postNotificationName:@"GWFileSystemDidChangeNotification"
                      object:opinfo];
      
      id gworkspace = [Workspace gworkspace];
      if (gworkspace) {
        id desktopManager = [gworkspace desktopManager];
        if (desktopManager) {
          id desktopView = [desktopManager desktopView];
          if (desktopView && [desktopView respondsToSelector:@selector(workspaceDidUnmountVolumeAtPath:)]) {
            @try {
              [desktopView workspaceDidUnmountVolumeAtPath:mountPath];
              NSLog(@"VolumeManager: Notified desktop view to remove mount at %@", mountPath);
            } @catch (NSException *e) {
              NSLog(@"VolumeManager: Exception notifying desktop: %@", e);
            }
          }
        }
      }
    } else {
      NSLog(@"VolumeManager: Mount point not removed, keeping desktop icon for %@", mountPath);
    }
    
    return YES;
  }
  
  return NO;
}

- (void)unmountAll
{
  NSArray *imagePaths = [[mountedVolumes allKeys] copy];
  for (NSString *imagePath in imagePaths) {
    [self unmountImageFile:imagePath];
  }
  [imagePaths release];
}

@end
