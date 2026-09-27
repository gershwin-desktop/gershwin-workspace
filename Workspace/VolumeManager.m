/* VolumeManager.m
 *
 * Implementation of disk image volume mounting
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <signal.h>
#import <errno.h>
#import <unistd.h>
#import "VolumeManager.h"
#import "AVFSMount.h"
#import "Workspace.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "Desktop/GWDesktopManager.h"
#import "Desktop/GWDesktopView.h"
#import "GWUnmountHelper.h"

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
    avfsVirtualPaths = [[NSMutableSet alloc] init];
    fm = [NSFileManager defaultManager];
  }
  return self;
}

- (void)dealloc
{
  [self unmountAll];
  [mountedVolumes release];
  [mountedVolumesPIDs release];
  [diskImageMountPoints release];
  [avfsVirtualPaths release];
  [super dealloc];
}

- (NSString *)findToolInPath:(NSString *)toolName alternativeNames:(NSArray *)altNames
{
  /* Build list of all names to try */
  NSMutableArray *allNames = [NSMutableArray arrayWithObject:toolName];
  if (altNames) {
    [allNames addObjectsFromArray:altNames];
  }
  
  /* Try each name using 'which' to search actual PATH */
  for (NSString *name in allNames) {
    @try {
      NSTask *whichTask = [[NSTask alloc] init];
      [whichTask setLaunchPath:@"/usr/bin/which"];
      [whichTask setArguments:@[name]];
      
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
        if ([result length] > 0 && [fm fileExistsAtPath:result]) {
          return result;
        }
      }
      [whichTask release];
    } @catch (NSException *e) {
    }
  }
  
  /* Fallback: try standard locations if which failed */
  NSArray *searchPaths = @[@"/usr/bin", @"/bin", @"/usr/local/bin", @"/opt/local/bin"];
  for (NSString *name in allNames) {
    for (NSString *path in searchPaths) {
      NSString *toolPath = [path stringByAppendingPathComponent:name];
      if ([fm fileExistsAtPath:toolPath]) {
        return toolPath;
      }
    }
  }
  
  return nil;
}

- (BOOL)isDarlingDmgAvailable
{
  return [self findToolInPath:@"darling-dmg" alternativeNames:nil] != nil;
}

- (BOOL)isApfsFuseAvailable
{
  return [self findToolInPath:@"apfs-fuse" alternativeNames:nil] != nil;
}

- (BOOL)isFuseisoAvailable
{
  return [self findToolInPath:@"fuseiso" alternativeNames:nil] != nil;
}

/* DMG mounting is provided by darling-dmg (HFS+/HFSX images) with apfs-fuse
 * (APFS images) as a fallback. If neither is present we have no way to mount
 * the file at all, so report both together rather than a tool-specific alert. */
- (void)showNoDmgToolInstalledAlert
{
  if (![NSThread isMainThread]) {
    /* A mount can now run from the async wrappers' background thread
     * (below); NSAlert's modal loop still has to be pumped from the main
     * thread, so hop back instead of assuming a caller already is there. */
    [self performSelectorOnMainThread:@selector(showNoDmgToolInstalledAlert)
                            withObject:nil
                         waitUntilDone:NO];
    return;
  }

  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"DMG Mount Tool Not Installed"];
  [alert setInformativeText:
    @"Mounting DMG files requires darling-dmg (HFS+) or apfs-fuse (APFS),\n"
    @"but neither is installed.\n\n"
    @"To install them, see:\n"
    @"https://github.com/darlinghq/darling-dmg\n"
    @"https://github.com/sgan81/apfs-fuse"];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

- (void)showFuseisoNotInstalledAlert
{
  if (![NSThread isMainThread]) {
    [self performSelectorOnMainThread:@selector(showFuseisoNotInstalledAlert)
                            withObject:nil
                         waitUntilDone:NO];
    return;
  }

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
  if (![NSThread isMainThread]) {
    [self performSelectorOnMainThread:@selector(showErrorAlert:)
                            withObject:errorMsg
                         waitUntilDone:NO];
    return;
  }

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
  /* mountedVolumes can now be written from the async wrappers' background
   * thread while this is read from the main thread (or vice versa). */
  @synchronized(self) {
    return [mountedVolumes objectForKey:imagePath];
  }
}

/* Returns the mount point already tracked for imagePath if it is still
 * genuinely mounted, evicting the entry and returning nil if it exists but
 * is stale - the exact case -isMountPointActive: was fixed to detect.
 * Shared by all three mount methods below instead of each repeating its
 * own check-and-evict. */
- (NSString *)activeExistingMountForImage:(NSString *)imagePath
{
  NSString *existingMount;
  @synchronized(self) {
    existingMount = [[mountedVolumes objectForKey:imagePath] copy];
  }
  if (existingMount && [self isMountPointActive:existingMount]) {
    return [existingMount autorelease];
  }
  if (existingMount) {
    @synchronized(self) {
      [mountedVolumes removeObjectForKey:imagePath];
      [mountedVolumesPIDs removeObjectForKey:imagePath];
    }
    [existingMount release];
  }
  return nil;
}

/* Records a completed mount so every mount type shares one synchronized
 * point of truth instead of repeating unguarded dictionary/set mutations -
 * load-bearing now that a mount can finish on a background thread while
 * another one is still in flight (see the async wrappers below). */
- (void)recordMount:(NSString *)mountPoint pid:(int)taskPid forImage:(NSString *)imagePath
{
  @synchronized(self) {
    [mountedVolumes setObject:mountPoint forKey:imagePath];
    [mountedVolumesPIDs setObject:[NSNumber numberWithInt:taskPid] forKey:imagePath];
    [diskImageMountPoints addObject:mountPoint];
  }
}

- (BOOL)isMountPointActive:(NSString *)mountPoint
{
  return VMPathIsActiveMountPoint(mountPoint);
}

/* Verify that the mount point has at least one entry and that the FUSE PID is running */
- (BOOL)verifyMountPoint:(NSString *)mountPoint pid:(int)pid error:(NSString **)errorOut
{
  /* Retry briefly to allow mounts that populate contents asynchronously to settle */
  const int maxRetries = 20; /* up to ~10 seconds with 500ms sleep */
  const useconds_t sleepUs = 500000; /* 0.5s */
  int attempt = 0;
  int lastErrno = 0;
  NSError *contentsError = nil;

  for (attempt = 0; attempt < maxRetries; attempt++) {
    /* Check pid if provided */
    if (pid > 0) {
      if (kill(pid, 0) != 0) {
        lastErrno = errno;
        if (lastErrno == ESRCH) {
          if (errorOut) {
            *errorOut = [NSString stringWithFormat:@"FUSE process %d is not running (ESRCH)", pid];
          }
          return NO;
        }
        /* For other errno values, continue and retry briefly */
      }
    }

    contentsError = nil;
    NSArray *contents = [fm contentsOfDirectoryAtPath:mountPoint error:&contentsError];
    if (!contentsError && contents && [contents count] > 0) {
      /* Success: PID is either valid or not required, and we have contents */
      return YES;
    }

    /* If there is a contents error like EACCES, abort early */
    if (contentsError) {
      lastErrno = errno;
      if (errorOut) {
        *errorOut = [NSString stringWithFormat:@"Mount point validation failed: %@", [contentsError localizedDescription]];
      }
      return NO;
    }

    /* Sleep a short while before retrying */
    usleep(sleepUs);
  }

  /* If the PID died during wait, prefer that message */
  if (pid > 0 && kill(pid, 0) != 0) {
    if (errorOut) {
      int kerr = errno;
      *errorOut = [NSString stringWithFormat:@"FUSE process %d is not running: %s", pid, strerror(kerr)];
    }
    return NO;
  }

  /* Final attempt: read directory one more time to capture state for diagnostics */
  NSError *finalErr = nil;
  NSArray *finalContents = [fm contentsOfDirectoryAtPath:mountPoint error:&finalErr];
  if (finalContents && [finalContents count] > 0) {
    /* Rare race: contents appeared right after retries; consider success */
    return YES;
  }

  /* Otherwise, report no files found after retries, include listing/error when available (do not mention wait duration) */
  if (errorOut) {
    NSString *detail = @"";
    if (finalErr) {
      detail = [NSString stringWithFormat:@" (%@)", [finalErr localizedDescription]];
    }
    *errorOut = [NSString stringWithFormat:@"Mount point validation failed: No files or directories found%@", detail];
  }
  return NO;
}

- (NSString *)createMountPointForDMG:(NSString *)dmgPath
{
  NSString *mediaDir = @"/Volumes";
  BOOL isDir;

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
    return nil;
  }
  
  return mountPoint;
}

- (NSString *)createMountPointForISO:(NSString *)isoPath
{
  NSString *mediaDir = @"/Volumes";
  BOOL isDir;

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
  if (![NSThread isMainThread]) {
    /* FSNode/FSNodeRep and the desktop view are AppKit-adjacent state that
     * must only be touched from the main thread; a mount can now finish on
     * a background thread (see the async wrappers below), so hop back
     * instead of assuming this call already started out there. */
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
      mountPoint, @"mountPoint",
      [NSNumber numberWithBool:isDiskImage], @"isDiskImage", nil];
    [self performSelectorOnMainThread:@selector(_registerVolumeWithDesktopArgs:)
                            withObject:args
                         waitUntilDone:NO];
    return;
  }

  /* Mark as mount point and register with desktop */
  @try {
    FSNode *vnode = [FSNode nodeWithPath:mountPoint];
    if (vnode) {
      [vnode setMountPoint:YES];
    }
    
    [[FSNodeRep sharedInstance] addVolumeAt:mountPoint isDiskImage:isDiskImage];
    
    /* Notify the desktop view directly (critical for volume to appear on desktop) */
    id gworkspace = [Workspace gworkspace];
    if (!gworkspace) {
    } else {
      id desktopManager = [gworkspace desktopManager];
      if (!desktopManager) {
      } else {
        id desktopView = [desktopManager desktopView];
        if (!desktopView) {
        } else if (![desktopView respondsToSelector:@selector(newVolumeMountedAtPath:)]) {
        } else {
          [desktopView newVolumeMountedAtPath: mountPoint];
        }
      }
    }
  } @catch (NSException *e) {
  }
}

/* performSelectorOnMainThread: target for the hop above - performSelector
 * only carries a single object argument, so the two real arguments travel
 * boxed in a dictionary. */
- (void)_registerVolumeWithDesktopArgs:(NSDictionary *)args
{
  [self registerVolumeWithDesktop:[args objectForKey:@"mountPoint"]
                       isDiskImage:[[args objectForKey:@"isDiskImage"] boolValue]];
}

/* Try to mount a DMG with one specific tool. Returns the mount point on
 * success, or nil (leaving *errorOut describing the failure). A per-tool
 * failure is recorded here so the caller can fall back to another tool and
 * only surface an alert once every candidate has failed. */
- (NSString *)mountDMGWithToolPath:(NSString *)toolPath
                            file:(NSString *)dmgPath
                       mountPoint:(NSString *)mountPoint
                            error:(NSString **)errorOut
{
  if (errorOut) {
    *errorOut = nil;
  }


  NSTask *dmgTask = [[NSTask alloc] init];
  [dmgTask setLaunchPath:toolPath];
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

    int taskPid = [dmgTask processIdentifier];
    NSString *verifyError = nil;

    if ([self isMountPointActive:mountPoint]) {
      if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
        [dmgTask terminate];
        sleep(1);
        if ([dmgTask isRunning]) {
          kill([dmgTask processIdentifier], SIGKILL);
        }
        [dmgTask release];
        [fm removeItemAtPath:mountPoint error:nil];
        if (errorOut) {
          *errorOut = verifyError;
        }
        return nil;
      }

      [self registerDmgMount:dmgPath mountPoint:mountPoint pid:taskPid];
      [dmgTask release];
      return mountPoint;
    }

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
      if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
        [dmgTask terminate];
        sleep(1);
        if ([dmgTask isRunning]) {
          kill([dmgTask processIdentifier], SIGKILL);
        }
        [dmgTask release];
        [fm removeItemAtPath:mountPoint error:nil];
        if (errorOut) {
          *errorOut = verifyError;
        }
        return nil;
      }

      [self registerDmgMount:dmgPath mountPoint:mountPoint pid:taskPid];
      [dmgTask release];
      return mountPoint;
    }

    [dmgTask terminate];
    sleep(1);
    if ([dmgTask isRunning]) {
      kill([dmgTask processIdentifier], SIGKILL);
    }
    [dmgTask release];
    [fm removeItemAtPath:mountPoint error:nil];

    if (errorOut) {
      *errorOut = allOutput;
    }
    return nil;
  }
  @catch (NSException *exception) {
    [dmgTask release];
    [fm removeItemAtPath:mountPoint error:nil];
    if (errorOut) {
      *errorOut = [exception reason];
    }
    return nil;
  }
}

/* Register a just-mounted DMG volume and notify observers. */
- (void)registerDmgMount:(NSString *)dmgPath mountPoint:(NSString *)mountPoint pid:(int)taskPid
{
  [self recordMount:mountPoint pid:taskPid forImage:dmgPath];

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
}

- (NSString *)mountDMGFile:(NSString *)dmgPath
{
  NSString *existingMount = [self activeExistingMountForImage:dmgPath];
  if (existingMount) {
    return existingMount;
  }

  if (![fm fileExistsAtPath:dmgPath]) {
    [self showErrorAlert:[NSString stringWithFormat:@"DMG file not found: %@", dmgPath]];
    return nil;
  }

  /* Collect every DMG-capable tool that is available. darling-dmg handles
   * HFS+/HFSX; apfs-fuse is the fallback for APFS images. We only give up
   * (with a single combined alert) once both have failed or neither exists. */
  NSMutableArray *toolPaths = [NSMutableArray array];
  NSString *darlingDmgPath = [self findToolInPath:@"darling-dmg" alternativeNames:nil];
  if (darlingDmgPath) {
    [toolPaths addObject:darlingDmgPath];
  }
  NSString *apfsFusePath = [self findToolInPath:@"apfs-fuse" alternativeNames:nil];
  if (apfsFusePath) {
    [toolPaths addObject:apfsFusePath];
  }

  if ([toolPaths count] == 0) {
    [self showNoDmgToolInstalledAlert];
    return nil;
  }

  NSString *mountPoint = nil;
  NSMutableArray *failures = [NSMutableArray array];

  for (NSString *toolPath in toolPaths) {
    mountPoint = [self createMountPointForDMG:dmgPath];
    if (!mountPoint) {
      [self showErrorAlert:@"Failed to create mount point"];
      return nil;
    }


    NSString *toolError = nil;
    NSString *result = [self mountDMGWithToolPath:toolPath file:dmgPath mountPoint:mountPoint error:&toolError];
    if (result) {
      return result;
    }

    NSString *toolName = [toolPath lastPathComponent];
    [failures addObject:[NSString stringWithFormat:@"%@: %@", toolName, (toolError ? toolError : @"unknown error")]];
  }

  [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount DMG with all available tools:\n%@",
                        [failures componentsJoinedByString:@"\n"]]];
  return nil;
}

- (NSString *)mountISOFile:(NSString *)isoPath
{
  NSString *existingMount = [self activeExistingMountForImage:isoPath];
  if (existingMount) {
    return existingMount;
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
    
    int taskPid = [isoTask processIdentifier];
    if ([self isMountPointActive:mountPoint]) {
      NSString *verifyError = nil;
      if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
        if ([isoTask isRunning]) {
          [isoTask terminate];
          sleep(1);
          if ([isoTask isRunning]) {
            kill([isoTask processIdentifier], SIGKILL);
          }
        }
        [isoTask release];
        [fm removeItemAtPath:mountPoint error:nil];
        [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount ISO:\n%@", verifyError]];
        return nil;
      }


      [self recordMount:mountPoint pid:taskPid forImage:isoPath];

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
        NSString *verifyError = nil;
        if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
          if ([isoTask isRunning]) {
            [isoTask terminate];
            sleep(1);
            if ([isoTask isRunning]) {
              kill([isoTask processIdentifier], SIGKILL);
            }
          }
          [isoTask release];
          [fm removeItemAtPath:mountPoint error:nil];
          [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount ISO:\n%@", verifyError]];
          return nil;
        }


        [self recordMount:mountPoint pid:taskPid forImage:isoPath];

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

  BOOL isSquashFS = ([extension isEqualToString:@"squashfs"] ||
                     [extension isEqualToString:@"sqsh"] ||
                     [extension isEqualToString:@"sfs"]);

  NSString *existingMount = [self activeExistingMountForImage:imagePath];
  if (existingMount) {
    return existingMount;
  }

  if (isSquashFS) {
    if (![self findToolInPath:@"squashfuse" alternativeNames:nil]) {
      [self showErrorAlert:@"squashfuse is not installed.\n\nInstall it with:\n  apt install squashfuse"];
      return nil;
    }
  } else {
    if (![self isFuseisoAvailable]) {
      [self showFuseisoNotInstalledAlert];
      return nil;
    }
  }

  NSString *mountPoint = [self createMountPointForISO:imagePath];
  if (!mountPoint) {
    [self showErrorAlert:@"Failed to create mount point"];
    return nil;
  }


  NSTask *fuseTask = [[NSTask alloc] init];
  NSString *toolPath = isSquashFS
    ? [self findToolInPath:@"squashfuse" alternativeNames:nil]
    : [self findToolInPath:@"fuseiso" alternativeNames:nil];
  if (!toolPath) {
    [fuseTask release];
    [self showErrorAlert:isSquashFS ? @"squashfuse not found" : @"fuseiso not found"];
    return nil;
  }

  [fuseTask setLaunchPath:toolPath];
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
    
    int taskPid = [fuseTask processIdentifier];
    if ([self isMountPointActive:mountPoint]) {
      NSString *verifyError = nil;
      if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
        if ([fuseTask isRunning]) {
          [fuseTask terminate];
          sleep(1);
          if ([fuseTask isRunning]) {
            kill([fuseTask processIdentifier], SIGKILL);
          }
        }
        [fuseTask release];
        [fm removeItemAtPath:mountPoint error:nil];
        [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount:\n%@", verifyError]];
        return nil;
      }


      [self recordMount:mountPoint pid:taskPid forImage:imagePath];

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
      NSString *verifyError = nil;
      if (![self verifyMountPoint:mountPoint pid:taskPid error:&verifyError]) {
        if ([fuseTask isRunning]) {
          [fuseTask terminate];
          sleep(1);
          if ([fuseTask isRunning]) {
            kill([fuseTask processIdentifier], SIGKILL);
          }
        }
        [fuseTask release];
        [fm removeItemAtPath:mountPoint error:nil];
        [self showErrorAlert:[NSString stringWithFormat:@"Failed to mount:\n%@", verifyError]];
        return nil;
      }


      [self recordMount:mountPoint pid:taskPid forImage:imagePath];

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

#pragma mark - Asynchronous mounting

/* Background-thread body for the async wrappers below: op picks which of
 * the synchronous mount methods above to run unchanged (launching the
 * helper tool and waiting for -verifyMountPoint:pid:error: to confirm it,
 * which alone can take up to ~10s) - only the thread it runs on changes,
 * so a caller on the main thread (typically reacting to a double-click)
 * is never blocked waiting for a disk image or ISO to attach. delayUsec
 * reproduces the fixed post-mount settle delay the caller used to sleep
 * through itself, now spent here instead, where it costs nothing.
 * result is delivered on the main thread via -_deliverAsyncMountResult:,
 * since that is the thread every AppKit-facing thing a caller does with
 * it (opening a viewer) has to run on. */
- (void)_asyncMountWorker:(NSDictionary *)info
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *op = [info objectForKey:@"op"];
  NSString *path = [info objectForKey:@"path"];
  useconds_t delayUsec = (useconds_t)[[info objectForKey:@"delayUsec"] unsignedIntValue];
  NSString *result = nil;

  if ([op isEqualToString:@"dmg"]) {
    result = [self mountDMGFile:path];
  } else if ([op isEqualToString:@"fuseiso"]) {
    result = [self mountFuseisoImage:path];
  }

  if (result && delayUsec > 0) {
    usleep(delayUsec);
  }

  NSMutableDictionary *delivery = [NSMutableDictionary dictionaryWithDictionary:info];
  [delivery setObject:(result ? (id)result : (id)[NSNull null]) forKey:@"result"];
  [self performSelectorOnMainThread:@selector(_deliverAsyncMountResult:)
                          withObject:delivery
                       waitUntilDone:NO];
  [arp release];
}

/* performSelector only carries a single object argument, and SEL is not
 * an object, so the target selector travels as its string name. */
- (void)_deliverAsyncMountResult:(NSDictionary *)delivery
{
  id target = [delivery objectForKey:@"target"];
  SEL selector = NSSelectorFromString([delivery objectForKey:@"selector"]);
  id result = [delivery objectForKey:@"result"];

  if ([result isKindOfClass:[NSNull class]]) {
    result = nil;
  }
  if (target && selector && [target respondsToSelector:selector]) {
    [target performSelector:selector withObject:result];
  }
}

/* Asynchronous variant of -mountDMGFile:: the mount itself runs on a
 * background thread; (target, selector) is invoked on the main thread
 * with the resulting mount point, or nil if mounting failed (a failure
 * alert has already been shown by then, exactly as -mountDMGFile: does
 * when called directly). */
- (void)mountDMGFile:(NSString *)dmgPath onMainThread:(id)target selector:(SEL)selector
{
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
    @"dmg", @"op",
    dmgPath, @"path",
    target, @"target",
    NSStringFromSelector(selector), @"selector",
    [NSNumber numberWithUnsignedInt:500000], @"delayUsec",
    nil];
  [NSThread detachNewThreadSelector:@selector(_asyncMountWorker:)
                            toTarget:self
                          withObject:info];
}

/* Asynchronous variant of -mountFuseisoImage:, covering ISO/BIN/NRG/IMG/
 * MDF and squashfs/sqsh/sfs the same way -mountDMGFile:onMainThread:
 * -selector: does for DMG. */
- (void)mountFuseisoImage:(NSString *)imagePath onMainThread:(id)target selector:(SEL)selector
{
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
    @"fuseiso", @"op",
    imagePath, @"path",
    target, @"target",
    NSStringFromSelector(selector), @"selector",
    [NSNumber numberWithUnsignedInt:500000], @"delayUsec",
    nil];
  [NSThread detachNewThreadSelector:@selector(_asyncMountWorker:)
                            toTarget:self
                          withObject:info];
}

- (BOOL)unmountImageFile:(NSString *)imagePath
{
  NSString *mountPoint = [self mountPointForImageFile:imagePath];
  if (!mountPoint) {
    return NO;
  }
  return [self unmountPath:mountPoint];
}

- (BOOL)unmountPath:(NSString *)mountPath
{
  
  if (!mountPath) {
    return NO;
  }
  
  
  /* Send will-unmount notification to grey out desktop icon */
  NSString *parent = [mountPath stringByDeletingLastPathComponent];
  NSString *name = [mountPath lastPathComponent];
  NSDictionary *unmountInfo = @{ @"NSDevicePath": mountPath };
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NSWorkspaceWillUnmountNotification
                  object:[NSWorkspace sharedWorkspace]
                userInfo:unmountInfo];
  
  
  /* Use GWUnmountHelper which properly handles sudo for unmounting */
  BOOL unmountSuccess = [GWUnmountHelper unmountPath:mountPath eject:NO];
  
  if (unmountSuccess) {
  } else {
  }
  
  /* Find the tracked volume for cleanup - the dictionaries can now also be
   * written by an async mount finishing on a background thread, so take a
   * consistent snapshot instead of iterating live state. */
  NSString *foundKey = nil;
  NSNumber *pidNumber = nil;
  @synchronized(self) {
    for (NSString *key in [mountedVolumes allKeys]) {
      if ([[mountedVolumes objectForKey:key] isEqualToString:mountPath]) {
        foundKey = [[key copy] autorelease];
        break;
      }
    }
    if (foundKey) {
      pidNumber = [mountedVolumesPIDs objectForKey:foundKey];
    }
  }

  /* Kill process as last resort if proper unmount failed */
  if (!unmountSuccess && foundKey) {
    if (pidNumber) {
      int pid = [pidNumber intValue];
      
      if (kill(pid, SIGKILL) == 0) {
        /* Brief wait for process to die, but non-blocking approach */
        int waitCount = 0;
        while (waitCount < 20 && kill(pid, 0) == 0) {
          usleep(100000); /* 0.1 seconds */
          waitCount++;
        }
        if (kill(pid, 0) != 0) {
          unmountSuccess = YES;
        } else {
        }
      } else {
        int killError = errno;
        if (killError == ESRCH) {
          unmountSuccess = YES;
        } else {
        }
      }
    } else {
    }
  } else if (!foundKey) {
  }
  
  if (!unmountSuccess) {
  }
  
  if (unmountSuccess) {
    /* Clean up tracking data */
    @synchronized(self) {
      if (foundKey) {
        [mountedVolumes removeObjectForKey:foundKey];
        [mountedVolumesPIDs removeObjectForKey:foundKey];
      }
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
    }
    
    /* Attempt to remove empty mount directory (non-recursively) */
    BOOL directoryRemoved = NO;
    @try {
      NSError *contentsErr = nil;
      NSArray *contents = [fm contentsOfDirectoryAtPath:mountPath error:&contentsErr];
      
      if (contentsErr) {
        /* Try to remove anyway - might be already unmounted */
        if (rmdir([mountPath fileSystemRepresentation]) == 0) {
          directoryRemoved = YES;
        }
      } else if (contents && [contents count] == 0) {
        if (rmdir([mountPath fileSystemRepresentation]) == 0) {
          directoryRemoved = YES;
        } else {
        }
      } else {
      }
    } @catch (NSException *e) {
    }
    
    /* Only remove desktop icon AFTER directory successfully removed */
    if (directoryRemoved) {
      
      /* Post NSWorkspaceDidUnmountNotification so other components can react */
      NSDictionary *unmountedInfo = @{ @"NSDevicePath": mountPath };
      [[NSNotificationCenter defaultCenter]
        postNotificationName:NSWorkspaceDidUnmountNotification
                      object:[NSWorkspace sharedWorkspace]
                    userInfo:unmountedInfo];
      
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
            } @catch (NSException *e) {
            }
          }
        }
      }
    } else {
    }
    
    if (directoryRemoved) {
      return YES;
    } else {
      return NO;
    }
  } else {
  }
  
  return NO;
}

#pragma mark - AVFS Support

- (BOOL)isAvfsAvailable
{
  return [[AVFSMount sharedInstance] isAvfsAvailable];
}

- (BOOL)isAvfsSupportedFile:(NSString *)path
{
  if (!path || [path length] == 0) {
    return NO;
  }
  return [[AVFSMount sharedInstance] canHandleFile:path];
}

- (NSArray *)avfsSupportedExtensions
{
  return [[AVFSMount sharedInstance] supportedExtensions];
}

- (NSString *)openAvfsArchive:(NSString *)archivePath
{
  if (!archivePath || [archivePath length] == 0) {
    return nil;
  }
  
  /* Check if file exists */
  if (![fm fileExistsAtPath:archivePath]) {
    [self showErrorAlert:[NSString stringWithFormat:@"File not found: %@", archivePath]];
    return nil;
  }
  
  AVFSMount *avfs = [AVFSMount sharedInstance];
  
  /* Check if AVFS can handle this file type */
  if (![avfs canHandleFile:archivePath]) {
    return nil;
  }
  
  /* Check if AVFS is available */
  if (![avfs isAvfsAvailable]) {
    [avfs showAvfsNotInstalledAlert];
    return nil;
  }
  
  
  /* Get the virtual path for the archive */
  AVFSMountResult *result = [avfs virtualPathForFile:archivePath];
  
  if (!result.success) {
    [self showErrorAlert:[NSString stringWithFormat:@"Failed to open archive:\n%@", result.errorMessage]];
    return nil;
  }
  
  NSString *virtualPath = result.virtualPath;
  
  /* Track this virtual path */
  @synchronized(self) {
    [avfsVirtualPaths addObject:virtualPath];
  }
  
  return virtualPath;
}

- (void)unmountAll
{
  NSArray *imagePaths = [[mountedVolumes allKeys] copy];
  for (NSString *imagePath in imagePaths) {
    [self unmountImageFile:imagePath];
  }
  [imagePaths release];
  
  /* Note: We don't stop AVFS daemon here as it may be used by other applications.
   * The daemon will be stopped when user logs out or explicitly unmounts ~/.avfs */
}

@end
