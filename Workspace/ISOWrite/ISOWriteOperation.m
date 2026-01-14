/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ISOWriteOperation.h"
#import "BlockDeviceInfo.h"
#import "ISOWriteConfirmation.h"
#import "ISOWriteProgressWindow.h"
#import "../GWUnmountHelper.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import <sys/stat.h>
#import <sys/ioctl.h>
#import <sys/select.h>
#import <sys/time.h>
#import <linux/fs.h>
#import <fcntl.h>
#ifndef O_DIRECT
#define O_DIRECT 0
#endif
#import <unistd.h>
#import <errno.h>
#import <signal.h>

/* Buffer size for copying: 1MB for optimal throughput */
#define ISO_WRITE_BUFFER_SIZE (1024 * 1024)

/* Progress update interval in seconds */
#define PROGRESS_UPDATE_INTERVAL 0.25

@implementation ISOWriteOperation

@synthesize isoPath = _isoPath;
@synthesize devicePath = _devicePath;
@synthesize deviceInfo = _deviceInfo;
@synthesize state = _state;
@synthesize bytesWritten = _bytesWritten;
@synthesize isoSize = _isoSize;
@synthesize verifyAfterWrite = _verifyAfterWrite;
@synthesize delegate = _delegate;

#pragma mark - Class Methods

+ (NSString *)validateISOPath:(NSString *)isoPath
              forMountPoint:(NSString *)mountPoint
{
  NSFileManager *fm = [NSFileManager defaultManager];
  
  /* Check ISO file exists and is readable */
  if (![fm fileExistsAtPath:isoPath]) {
    return @"The ISO file does not exist.";
  }
  
  if (![fm isReadableFileAtPath:isoPath]) {
    return @"The ISO file is not readable.";
  }
  
  /* Get ISO file size */
  NSDictionary *attrs = [fm fileAttributesAtPath:isoPath traverseLink:YES];
  if (!attrs) {
    return @"Cannot read ISO file attributes.";
  }
  unsigned long long isoSize = [attrs fileSize];
  
  if (isoSize == 0) {
    return @"The ISO file is empty.";
  }
  
  /* Check if mount point corresponds to a physical device */
  if (![self isPhysicalDeviceMountPoint:mountPoint]) {
    return @"The target is not a physical device mount point.";
  }
  
  /* Get device info */
  BlockDeviceInfo *info = [BlockDeviceInfo infoForMountPoint:mountPoint];
  if (!info || !info.isValid) {
    return @"Cannot determine device information for the target.";
  }
  
  /* Check ISO fits on device (with 1% tolerance for alignment) */
  unsigned long long minDeviceSize = (unsigned long long)(isoSize * 0.99);
  if (info.size < minDeviceSize) {
    return [NSString stringWithFormat:
            @"The ISO file (%@) is larger than the target device (%@).",
            [self sizeDescription:isoSize], info.sizeDescription];
  }
  
  /* Check device safety */
  NSString *safetyError = [info safetyCheckForWriting];
  if (safetyError) {
    return safetyError;
  }
  
  return nil; /* Valid */
}

+ (BOOL)isPhysicalDeviceMountPoint:(NSString *)mountPoint
{
  NSString *devicePath = [BlockDeviceInfo devicePathForMountPoint:mountPoint];
  if (!devicePath) {
    return NO;
  }
  
  /* Check it's a block device */
  struct stat st;
  if (stat([devicePath UTF8String], &st) != 0) {
    return NO;
  }
  
  if (!S_ISBLK(st.st_mode)) {
    return NO;
  }
  
  /* It should be a partition on a physical device */
  NSString *parentDevice = [BlockDeviceInfo parentDeviceForPartition:devicePath];
  if (!parentDevice) {
    /* It's already a raw device - even better */
    return YES;
  }
  
  return YES;
}

+ (NSString *)devicePathForMountPoint:(NSString *)mountPoint
{
  NSString *partitionPath = [BlockDeviceInfo devicePathForMountPoint:mountPoint];
  if (!partitionPath) {
    return nil;
  }
  
  /* Get the parent raw device */
  NSString *rawDevice = [BlockDeviceInfo parentDeviceForPartition:partitionPath];
  return rawDevice ? rawDevice : partitionPath;
}

+ (NSString *)sizeDescription:(unsigned long long)size
{
  if (size >= 1000000000000ULL) {
    return [NSString stringWithFormat:@"%.1f TB", (double)size / 1000000000000.0];
  } else if (size >= 1000000000ULL) {
    return [NSString stringWithFormat:@"%.1f GB", (double)size / 1000000000.0];
  } else if (size >= 1000000ULL) {
    return [NSString stringWithFormat:@"%.1f MB", (double)size / 1000000.0];
  } else if (size >= 1000ULL) {
    return [NSString stringWithFormat:@"%.1f KB", (double)size / 1000.0];
  }
  return [NSString stringWithFormat:@"%llu bytes", size];
}

#pragma mark - Initialization

- (id)initWithISOPath:(NSString *)isoPath
         targetDevice:(NSString *)devicePath
{
  self = [super init];
  if (self) {
    _isoPath = [isoPath copy];
    _devicePath = [devicePath copy];
    _state = ISOWriteStateIdle;
    _cancelled = NO;
    _verifyAfterWrite = YES;
    _bytesWritten = 0;
    
    /* Create progress window */
    _progressWindow = [[ISOWriteProgressWindow alloc] init];
    [_progressWindow setDelegate:self];
  }
  return self;
}

- (void)dealloc
{
  [_progressTimer invalidate];
  RELEASE(_progressTimer);
  
  RELEASE(_isoPath);
  RELEASE(_devicePath);
  RELEASE(_deviceInfo);
  RELEASE(_startTime);
  RELEASE(_progressWindow);
  
  [super dealloc];
}

#pragma mark - Public Methods

- (void)startWithConfirmation
{
  NSLog(@"ISOWriteOperation: Starting write operation for ISO: %@", _isoPath);
  NSLog(@"ISOWriteOperation: Target device: %@", _devicePath);
  
  _state = ISOWriteStateValidating;
  
  /* Validate ISO file */
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *attrs = [fm fileAttributesAtPath:_isoPath traverseLink:YES];
  if (!attrs) {
    NSLog(@"ISOWriteOperation: ERROR - Cannot read ISO file attributes");
    [self failWithError:@"Cannot read ISO file."];
    return;
  }
  _isoSize = [attrs fileSize];
  NSLog(@"ISOWriteOperation: ISO size: %llu bytes (%@)", _isoSize, [[self class] sizeDescription:_isoSize]);
  
  /* Get device info */
  _deviceInfo = [[BlockDeviceInfo infoForDevicePath:_devicePath] retain];
  if (!_deviceInfo || !_deviceInfo.isValid) {
    NSLog(@"ISOWriteOperation: ERROR - Cannot determine device information");
    [self failWithError:@"Cannot determine device information."];
    return;
  }
  NSLog(@"ISOWriteOperation: Device info - size: %@, partitions: %lu", 
        [_deviceInfo sizeDescription], (unsigned long)[[_deviceInfo mountedPartitions] count]);
  
  /* Check ISO fits */
  if (_isoSize > _deviceInfo.size) {
    NSLog(@"ISOWriteOperation: ERROR - ISO too large for device (%llu > %llu)", _isoSize, _deviceInfo.size);
    [self failWithError:[NSString stringWithFormat:
                         @"The ISO file (%@) is larger than the target device (%@).",
                         [[self class] sizeDescription:_isoSize],
                         [_deviceInfo sizeDescription]]];
    return;
  }
  
  /* Safety check */
  NSString *safetyError = [_deviceInfo safetyCheckForWriting];
  if (safetyError) {
    NSLog(@"ISOWriteOperation: ERROR - Safety check failed: %@", safetyError);
    [self failWithError:safetyError];
    return;
  }
  NSLog(@"ISOWriteOperation: Safety checks passed");
  
  _state = ISOWriteStateConfirming;
  
  /* Show confirmation dialog */
  NSLog(@"ISOWriteOperation: Showing confirmation dialog to user");
  ISOWriteConfirmation *confirmation = [[ISOWriteConfirmation alloc]
                                        initWithISOPath:_isoPath
                                        deviceInfo:_deviceInfo
                                        isoSize:_isoSize];
  
  NSInteger result = [confirmation runModal];
  RELEASE(confirmation);
  
  if (result != NSModalResponseOK) {
    NSLog(@"ISOWriteOperation: User cancelled at confirmation dialog");
    _state = ISOWriteStateCancelled;
    if ([_delegate respondsToSelector:@selector(isoWriteOperationWasCancelled:)]) {
      [_delegate isoWriteOperationWasCancelled:self];
    }
    return;
  }
  
  NSLog(@"ISOWriteOperation: User confirmed - proceeding with unmount and write");
  /* User confirmed - proceed with unmount and write */
  [self performUnmountAndWrite];
}

- (IBAction)cancel:(id)sender
{
  if (_state == ISOWriteStateWriting || _state == ISOWriteStateVerifying) {
    _cancelled = YES;
    _state = ISOWriteStateCancelled;
    
    NSInteger result = NSRunAlertPanel(
      NSLocalizedString(@"Write Cancelled", @""),
      NSLocalizedString(@"The write operation was cancelled. The target device may be in an inconsistent state and should be reformatted before use.", @""),
      NSLocalizedString(@"OK", @""),
      nil, nil);
    (void)result;
  }
}

- (void)showProgressWindow
{
  if (_progressWindow) {
    [_progressWindow show];
  }
}

- (NSString *)stateDescription
{
  switch (_state) {
    case ISOWriteStateIdle:
      return @"Idle";
    case ISOWriteStateValidating:
      return @"Validating";
    case ISOWriteStateConfirming:
      return @"Waiting for confirmation";
    case ISOWriteStateUnmounting:
      return @"Unmounting partitions";
    case ISOWriteStateWriting:
      return @"Writing image";
    case ISOWriteStateVerifying:
      return @"Verifying";
    case ISOWriteStateCompleted:
      return @"Completed";
    case ISOWriteStateFailed:
      return @"Failed";
    case ISOWriteStateCancelled:
      return @"Cancelled";
    default:
      return @"Unknown";
  }
}

#pragma mark - Private Methods

- (void)failWithError:(NSString *)error
{
  /* Ensure we're on main thread for UI operations */
  if (![NSThread isMainThread]) {
    [self performSelectorOnMainThread:@selector(failWithError:)
                           withObject:error
                        waitUntilDone:NO];
    return;
  }
  
  _state = ISOWriteStateFailed;
  
  /* Close progress window FIRST before showing error */
  if (_progressWindow) {
    @try {
      [_progressWindow close];
      DESTROY(_progressWindow);
    } @catch (NSException *e) {
      NSLog(@"ISOWriteOperation: Exception closing progress window: %@", e);
    }
  }
  
  @try {
    NSRunAlertPanel(
      NSLocalizedString(@"ISO Write Error", @""),
      @"%@",
      NSLocalizedString(@"OK", @""),
      nil, nil, error ? error : @"Unknown error");
  } @catch (NSException *e) {
    NSLog(@"ISOWriteOperation: Exception showing alert: %@", e);
  }
  
  if ([_delegate respondsToSelector:@selector(isoWriteOperation:didFailWithError:)]) {
    @try {
      [_delegate isoWriteOperation:self didFailWithError:error];
    } @catch (NSException *e) {
      NSLog(@"ISOWriteOperation: Exception calling delegate: %@", e);
    }
  }
}

- (void)performUnmountAndWrite
{
  NSLog(@"ISOWriteOperation: Beginning unmount and write sequence");
  _state = ISOWriteStateUnmounting;
  
  /* Update status */
  [_progressWindow setStatus:NSLocalizedString(@"Unmounting partitions...", @"")];
  [_progressWindow setSourcePath:_isoPath];
  [_progressWindow setDestinationPath:_devicePath];
  [_progressWindow setIndeterminate:YES];
  [self showProgressWindow];
  
  /* Unmount all partitions on the device */
  NSLog(@"ISOWriteOperation: Unmounting all partitions on device");
  BOOL unmountSuccess = [self unmountAllPartitions];
  
  if (!unmountSuccess) {
    NSLog(@"ISOWriteOperation: ERROR - Failed to unmount partitions");
    [self failWithError:@"Failed to unmount all partitions on the device. Some may be in use."];
    return;
  }
  NSLog(@"ISOWriteOperation: All partitions successfully unmounted");
  
  /* Start writing in background thread */
  NSLog(@"ISOWriteOperation: Starting write thread");
  [NSThread detachNewThreadSelector:@selector(writeThread)
                           toTarget:self
                         withObject:nil];
}

- (BOOL)unmountAllPartitions
{
  NSArray *mountedParts = [_deviceInfo mountedPartitions];
  
  /* IMPORTANT: Use unmount-only (eject:NO) so device stays accessible for writing.
   * For future CDROM burning support:
   * 1. Unmount any data partitions (here)
   * 2. Keep device open (no eject)
   * 3. Write/burn to raw device (writeThread or future burnThread)
   * 4. Eject only after burn completes (in writeDidFinish or burnDidFinish)
   */
  for (PartitionInfo *part in mountedParts) {
    BOOL unmounted = [GWUnmountHelper unmountPath:part.mountPoint 
                                        devicePath:part.devicePath
                                             eject:NO];  /* NO eject - keep device accessible */
    if (!unmounted) {
      return NO;
    }
  }
  
  return YES;
}

- (void)writeThread
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSLog(@"ISOWriteOperation: Write thread started");
  _state = ISOWriteStateWriting;
  _bytesWritten = 0;
  _startTime = [[NSDate date] retain];
  
  /* Update UI on main thread */
  [self performSelectorOnMainThread:@selector(writeDidStart)
                         withObject:nil
                      waitUntilDone:NO];
  
  /* Start progress timer - don't wait to avoid deadlock if main thread is busy */
  [self performSelectorOnMainThread:@selector(startProgressTimer)
                         withObject:nil
                      waitUntilDone:NO];
  
  /* Use helper tool with sudo -A -E for privileged device access */
  NSString *helperPath = [[NSBundle mainBundle] pathForResource:@"isowrite-helper" 
                                                         ofType:nil
                                                    inDirectory:@"../Tools"];
  if (!helperPath) {
    /* Try GNUstep Tools directory (installed location) */
    helperPath = @"/System/Library/Tools/isowrite-helper";
    if (![[NSFileManager defaultManager] fileExistsAtPath:helperPath]) {
      /* Try system location */
      helperPath = @"/usr/local/bin/isowrite-helper";
      if (![[NSFileManager defaultManager] fileExistsAtPath:helperPath]) {
        helperPath = [[NSString stringWithFormat:@"%@/Tools/isowrite-helper", 
                       NSHomeDirectory()] stringByExpandingTildeInPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:helperPath]) {
          NSLog(@"ISOWriteOperation: ERROR - isowrite-helper not found in any expected location");
          NSString *errorMsg = @"Could not find isowrite-helper tool. Please reinstall Workspace.";
          [self performSelectorOnMainThread:@selector(writeDidFailWithError:)
                                 withObject:errorMsg
                              waitUntilDone:NO];
          DESTROY(pool);
          return;
        }
      }
    }
  }
  
  if (!helperPath) {
    NSLog(@"ISOWriteOperation: ERROR - helperPath is nil after search");
    NSString *errorMsg = @"Internal error: helper path is nil";
    [self performSelectorOnMainThread:@selector(writeDidFailWithError:)
                           withObject:errorMsg
                        waitUntilDone:NO];
    DESTROY(pool);
    return;
  }
  
  NSLog(@"ISOWriteOperation: Using helper tool at: %@", helperPath);
  
  /* Find sudo (may be in different locations on different OS) */
  NSString *sudoPath = [GWUnmountHelper findSudoPath];
  NSLog(@"ISOWriteOperation: Launching helper tool with %@ -A -E", sudoPath);
  
  /* sudo strips LD_LIBRARY_PATH for security, so we need to wrap the helper
   * invocation to preserve the library path. Use bash -c to set it. */
  NSString *ldPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"LD_LIBRARY_PATH"];
  if (!ldPath || [ldPath length] == 0) {
    ldPath = @"/System/Library/Libraries";
  }
  
  /* Build command with proper shell quoting: LD_LIBRARY_PATH=<path> <helper> '<iso>' '<device>' */
  NSString *helperCommand = [NSString stringWithFormat:@"LD_LIBRARY_PATH=%@ '%@' '%@' '%@'",
                             ldPath, helperPath, _isoPath, _devicePath];
  
  NSLog(@"ISOWriteOperation: Helper command: %@", helperCommand);
  
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:sudoPath];
  [task setArguments:@[@"-A", @"-E", @"/bin/bash", @"-c", helperCommand]];
  
  /* Set up pipes for monitoring output - explicitly retain to prevent premature deallocation */
  NSPipe *outputPipe = [[NSPipe pipe] retain];
  NSPipe *errorPipe = [[NSPipe pipe] retain];
  
  if (!outputPipe || !errorPipe) {
    NSLog(@"ISOWriteOperation: ERROR - Failed to create pipes");
    NSString *errorMsg = @"Failed to create communication pipes for write operation";
    [self performSelectorOnMainThread:@selector(writeDidFailWithError:)
                           withObject:errorMsg
                        waitUntilDone:NO];
    DESTROY(outputPipe);
    DESTROY(errorPipe);
    DESTROY(task);
    DESTROY(pool);
    return;
  }
  
  [task setStandardOutput:outputPipe];
  [task setStandardError:errorPipe];
  
  NSFileHandle *errorHandle = [[errorPipe fileHandleForReading] retain];
  
  if (!errorHandle) {
    NSLog(@"ISOWriteOperation: ERROR - Failed to get error pipe handle");
    NSString *errorMsg = @"Failed to create pipe for monitoring write progress";
    [self performSelectorOnMainThread:@selector(writeDidFailWithError:)
                           withObject:errorMsg
                        waitUntilDone:NO];
    DESTROY(outputPipe);
    DESTROY(errorPipe);
    DESTROY(task);
    DESTROY(pool);
    return;
  }
  
  BOOL success = YES;
  NSString *errorMessage = nil;
  volatile BOOL taskLaunched = NO;
  
  @try {
    NSLog(@"ISOWriteOperation: About to launch task...");
    
    /* Get the file descriptor BEFORE launching task */
    int fd = [errorHandle fileDescriptor];
    NSLog(@"ISOWriteOperation: Will monitor file descriptor %d", fd);
    
    [task launch];
    taskLaunched = YES;
    NSLog(@"ISOWriteOperation: Task launched successfully");
    
    /* DO NOT ACCESS TASK OBJECT AGAIN - it can cause crashes */
    /* Just monitor the pipe until it closes */
    
    /* Monitor stderr for progress - loop until pipe closes or we're cancelled */
    int loopCount = 0;
    int consecutiveEmptyReads = 0;
    while (!_cancelled) {
      NSData *data = nil;
      
      /* Drain autorelease pool periodically */
      if (++loopCount % 50 == 0) {
        DESTROY(pool);
        pool = [[NSAutoreleasePool alloc] init];
      }
      
      /* Use select() to check if data is available with timeout */
      fd_set readfds;
      struct timeval timeout;
      FD_ZERO(&readfds);
      FD_SET(fd, &readfds);
      timeout.tv_sec = 0;
      timeout.tv_usec = 100000; /* 100ms */
      
      int selectResult = select(fd + 1, &readfds, NULL, NULL, &timeout);
      
      if (selectResult < 0) {
        if (errno == EINTR) continue; /* Interrupted, retry */
        NSLog(@"ISOWriteOperation: select() error: %s", strerror(errno));
        break;
      }
      
      if (selectResult == 0) {
        /* Timeout - just continue waiting */
        continue;
      }
      
      /* Data is available - read it safely */
      @try {
        data = [errorHandle availableData];
        if (!data || [data length] == 0) {
          /* Empty read might mean EOF - wait a bit to confirm */
          if (++consecutiveEmptyReads > 3) {
            NSLog(@"ISOWriteOperation: Pipe closed (EOF detected)");
            break;
          }
          usleep(50000); /* Wait 50ms */
          continue;
        }
        consecutiveEmptyReads = 0; /* Reset on successful read */
      } @catch (NSException *readEx) {
        NSLog(@"ISOWriteOperation: Exception reading from pipe: %@", readEx);
        break;
      }
      
      if ([data length] > 0) {
        NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray *lines = [output componentsSeparatedByString:@"\n"];
        
        for (NSString *line in lines) {
          if ([line length] == 0) continue;
          
          NSLog(@"isowrite-helper: %@", line);
          
          /* Parse progress updates: "PROGRESS: 45.2% (1234567 / 2700000 bytes)" */
          if ([line hasPrefix:@"PROGRESS:"]) {
            NSScanner *scanner = [NSScanner scannerWithString:line];
            [scanner scanString:@"PROGRESS:" intoString:NULL];
            double percent;
            long long bytes;
            if ([scanner scanDouble:&percent] && 
                [scanner scanString:@"%" intoString:NULL] &&
                [scanner scanString:@"(" intoString:NULL] &&
                [scanner scanLongLong:&bytes]) {
              _bytesWritten = (unsigned long long)bytes;
            }
          }
          else if ([line hasPrefix:@"ERROR:"]) {
            if (!errorMessage) {
              errorMessage = [[line substringFromIndex:7] retain];
            }
          }
        }
        [output release];
      }
      
      usleep(100000); /* Check every 100ms */
    }
    
    NSLog(@"ISOWriteOperation: Pipe monitoring loop exited");
    
    /* DO NOT access task object - causes crashes. Just wait a moment for process to finish */
    if (taskLaunched) {
      NSLog(@"ISOWriteOperation: Waiting for task process to complete...");
      /* Give the process time to exit cleanly */
      int waitCount = 0;
      while (waitCount < 50) { /* Wait up to 5 seconds */
        usleep(100000); /* 100ms */
        waitCount++;
        
        /* Check if we got an error message - if so, stop waiting */
        if (errorMessage) break;
      }
      NSLog(@"ISOWriteOperation: Wait period complete");
    }
    
    if (_cancelled) {
      NSLog(@"ISOWriteOperation: Write was cancelled");
      success = NO;
    } else if (errorMessage) {
      NSLog(@"ISOWriteOperation: Error detected: %@", errorMessage);
      success = NO;
    } else {
      /* No error message means success */
      _bytesWritten = _isoSize; /* Ensure we show 100% */
      NSLog(@"ISOWriteOperation: Write appears successful");
    }
    
    /* Read any remaining output - pipe might still have buffered data */
    @try {
      NSData *remainingData = [errorHandle readDataToEndOfFile];
      if ([remainingData length] > 0) {
        NSString *output = [[NSString alloc] initWithData:remainingData 
                                                  encoding:NSUTF8StringEncoding];
        if (output) {
          NSLog(@"isowrite-helper final output: %@", output);
          [output release];
        }
      }
    } @catch (NSException *readException) {
      NSLog(@"ISOWriteOperation: Exception reading final output: %@", readException);
    }
  }
  @catch (NSException *exception) {
    NSLog(@"ISOWriteOperation: Exception launching helper: %@", exception);
    success = NO;
    if (!errorMessage) {
      errorMessage = [[NSString stringWithFormat:@"Failed to launch helper tool: %@", 
                      [exception reason]] retain];
    }
  }
  @finally {
    /* Clean up retained objects to prevent leaks */
    NSLog(@"ISOWriteOperation: Cleaning up task resources...");
    
    DESTROY(errorHandle);
    DESTROY(errorPipe);
    DESTROY(outputPipe);
    
    /* Just release task - don't access it at all to avoid crashes */
    if (task) {
      NSLog(@"ISOWriteOperation: Releasing task object");
      DESTROY(task);
    }
    
    NSLog(@"ISOWriteOperation: Resource cleanup complete");
  }
  
  NSLog(@"ISOWriteOperation: Write operation completed. Success: %@", success ? @"YES" : @"NO");
  
  /* Stop progress timer */
  [self performSelectorOnMainThread:@selector(stopProgressTimer)
                         withObject:nil
                      waitUntilDone:YES];
  
  if (_cancelled) {
    NSLog(@"ISOWriteOperation: Write was cancelled by user");
    _state = ISOWriteStateCancelled;
    [self performSelectorOnMainThread:@selector(writeWasCancelled)
                           withObject:nil
                        waitUntilDone:NO];
  } else if (!success) {
    NSLog(@"ISOWriteOperation: Write failed");
    NSString *errorMsg = errorMessage ? errorMessage : @"Error writing to device.";
    [self performSelectorOnMainThread:@selector(failWithError:)
                           withObject:errorMsg
                        waitUntilDone:NO];
    DESTROY(errorMessage);
  } else {
    /* Trigger partition table rescan before verification/completion */
    NSLog(@"ISOWriteOperation: Triggering partition table rescan");
    [self rescanPartitionTable];
    
    /* Optionally verify */
    if (_verifyAfterWrite) {
      NSLog(@"ISOWriteOperation: Starting verification");
      [self performVerification];
    } else {
      _state = ISOWriteStateCompleted;
      NSLog(@"ISOWriteOperation: Write completed successfully");
      [self performSelectorOnMainThread:@selector(writeDidComplete)
                             withObject:nil
                          waitUntilDone:NO];
    }
  }
  
  DESTROY(pool);
}

- (void)rescanPartitionTable
{
  /* Force kernel to re-read partition table so automounter can detect new volumes */
  /* ARCHITECTURE NOTE: For CDROM burning, this rescan would trigger automount of
   * the burned disc. The burning workflow would be:
   * 1. Unmount existing partitions (unmountAllPartitions with eject:NO)
   * 2. Burn ISO to device (similar to writeThread, but using cdrecord/wodim)
   * 3. Rescan partition table (this method)
   * 4. Wait for automount (same as ISO write completion)
   * 5. Eject disc after successful burn (optional)
   */
  NSLog(@"ISOWriteOperation: Executing blockdev --rereadpt %@", _devicePath);
  
  NSString *sudoPath = [GWUnmountHelper findSudoPath];
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:sudoPath];
  [task setArguments:@[@"-A", @"-E", @"/sbin/blockdev", @"--rereadpt", _devicePath]];
  [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  
  @try {
    [task launch];
    [task waitUntilExit];
    int status = [task terminationStatus];
    if (status == 0) {
      NSLog(@"ISOWriteOperation: Partition table rescan successful");
    } else {
      NSLog(@"ISOWriteOperation: Partition table rescan returned status %d (may be normal)", status);
    }
  } @catch (NSException *e) {
    NSLog(@"ISOWriteOperation: Partition rescan failed: %@", e);
  } @finally {
    DESTROY(task);
  }
  
  /* Give udev/systemd time to process the new partition table */
  NSLog(@"ISOWriteOperation: Waiting for udev to process new partition table...");
  usleep(1000000); /* Wait 1 second */
}

- (void)performVerification
{
  NSLog(@"ISOWriteOperation: Beginning verification");
  _state = ISOWriteStateVerifying;
  
  [self performSelectorOnMainThread:@selector(verifyDidStart)
                         withObject:nil
                      waitUntilDone:YES];
  
  /* Verify by reading first 10MB, middle 10MB, and last 10MB for balance of speed vs thoroughness */
  NSLog(@"ISOWriteOperation: Opening files for verification");
  NSFileHandle *isoHandle = [NSFileHandle fileHandleForReadingAtPath:_isoPath];
  int devFd = open([_devicePath UTF8String], O_RDONLY | O_DIRECT);
  
  if (!isoHandle || devFd < 0) {
    if (devFd < 0 && errno == EINVAL) {
      /* O_DIRECT not supported, try without it */
      NSLog(@"ISOWriteOperation: O_DIRECT not supported, retrying without it");
      devFd = open([_devicePath UTF8String], O_RDONLY);
    }
    
    if (!isoHandle || devFd < 0) {
      NSLog(@"ISOWriteOperation: WARNING - Cannot open files for verification (isoHandle=%p, devFd=%d, errno=%d)", 
            isoHandle, devFd, errno);
      _state = ISOWriteStateCompleted;
      [self performSelectorOnMainThread:@selector(writeDidComplete)
                             withObject:nil
                          waitUntilDone:NO];
      if (devFd >= 0) close(devFd);
      return;
    }
  }
  NSLog(@"ISOWriteOperation: Files opened for verification");
  
  /* Allocate aligned buffer for direct I/O */
  size_t verifyChunkSize = 10 * 1024 * 1024;  /* 10 MB chunks */
  void *devBuffer = NULL;
  posix_memalign(&devBuffer, 4096, verifyChunkSize);
  if (!devBuffer) {
    NSLog(@"ISOWriteOperation: ERROR - Failed to allocate verification buffer");
    close(devFd);
    [isoHandle closeFile];
    [self performSelectorOnMainThread:@selector(failWithError:)
                           withObject:@"Memory allocation failed during verification"
                        waitUntilDone:NO];
    return;
  }
  
  BOOL allMatch = YES;
  NSString *failureLocation = nil;
  
  /* Verify first 10MB */
  [self updateVerificationProgress:10.0 status:@"Verifying beginning of image..."];
  NSLog(@"ISOWriteOperation: Verifying first 10MB");
  NSData *isoFirst = [isoHandle readDataOfLength:verifyChunkSize];
  ssize_t readBytes = read(devFd, devBuffer, verifyChunkSize);
  NSData *devFirst = [NSData dataWithBytes:devBuffer length:readBytes];
  
  if (![isoFirst isEqualToData:devFirst]) {
    allMatch = NO;
    failureLocation = @"beginning";
    NSLog(@"ISOWriteOperation: First 10MB verification: MISMATCH");
  } else {
    NSLog(@"ISOWriteOperation: First 10MB verification: MATCH");
  }
  
  /* Verify middle 10MB */
  if (allMatch && _isoSize > verifyChunkSize * 2) {
    [self updateVerificationProgress:50.0 status:@"Verifying middle of image..."];
    unsigned long long middleOffset = (_isoSize / 2) - (verifyChunkSize / 2);
    NSLog(@"ISOWriteOperation: Verifying middle 10MB at offset %llu", middleOffset);
    
    [isoHandle seekToFileOffset:middleOffset];
    NSData *isoMiddle = [isoHandle readDataOfLength:verifyChunkSize];
    
    lseek(devFd, middleOffset, SEEK_SET);
    readBytes = read(devFd, devBuffer, verifyChunkSize);
    NSData *devMiddle = [NSData dataWithBytes:devBuffer length:readBytes];
    
    if (![isoMiddle isEqualToData:devMiddle]) {
      allMatch = NO;
      failureLocation = @"middle";
      NSLog(@"ISOWriteOperation: Middle 10MB verification: MISMATCH");
    } else {
      NSLog(@"ISOWriteOperation: Middle 10MB verification: MATCH");
    }
  }
  
  /* Verify last 10MB */
  if (allMatch) {
    [self updateVerificationProgress:90.0 status:@"Verifying end of image..."];
    unsigned long long lastOffset = (_isoSize > verifyChunkSize) ? (_isoSize - verifyChunkSize) : 0;
    NSLog(@"ISOWriteOperation: Verifying last 10MB at offset %llu", lastOffset);
    
    [isoHandle seekToFileOffset:lastOffset];
    NSData *isoLast = [isoHandle readDataToEndOfFile];
    
    lseek(devFd, lastOffset, SEEK_SET);
    readBytes = read(devFd, devBuffer, [isoLast length]);
    NSData *devLast = [NSData dataWithBytes:devBuffer length:readBytes];
    
    if (![isoLast isEqualToData:devLast]) {
      allMatch = NO;
      failureLocation = @"end";
      NSLog(@"ISOWriteOperation: Last 10MB verification: MISMATCH");
    } else {
      NSLog(@"ISOWriteOperation: Last 10MB verification: MATCH");
    }
  }
  
  free(devBuffer);
  close(devFd);
  [isoHandle closeFile];
  
  if (!allMatch) {
    NSLog(@"ISOWriteOperation: ERROR - Verification failed at %@!", failureLocation);
    NSString *errorMsg = [NSString stringWithFormat:
                          @"Verification failed at %@ of image!\n\nThe written data does not match the ISO file. The device may be defective.",
                          failureLocation];
    [self performSelectorOnMainThread:@selector(failWithError:)
                           withObject:errorMsg
                        waitUntilDone:NO];
    return;
  }
  
  NSLog(@"ISOWriteOperation: Verification successful");
  _state = ISOWriteStateCompleted;
  [self performSelectorOnMainThread:@selector(writeDidComplete)
                         withObject:nil
                      waitUntilDone:NO];
}

#pragma mark - UI Updates (Main Thread)

- (void)writeDidStart
{
  if ([_delegate respondsToSelector:@selector(isoWriteOperationDidStart:)]) {
    [_delegate isoWriteOperationDidStart:self];
  }
  
  [_progressWindow setStatus:NSLocalizedString(@"Writing image to device...", @"")];
  [_progressWindow setSourcePath:_isoPath];
  [_progressWindow setDestinationPath:_devicePath];
  [_progressWindow setIndeterminate:NO];
  [_progressWindow setProgress:0.0];
}

- (void)verifyDidStart
{
  [_progressWindow setStatus:NSLocalizedString(@"Verifying...", @"")];
  [_progressWindow setIndeterminate:NO];
  [_progressWindow setProgress:0.0];
}

- (void)updateVerificationProgress:(double)progress status:(NSString *)status
{
  [_progressWindow performSelectorOnMainThread:@selector(setProgress:)
                                    withObject:[NSNumber numberWithDouble:progress]
                                 waitUntilDone:NO];
  if (status) {
    [_progressWindow performSelectorOnMainThread:@selector(setStatus:)
                                      withObject:status
                                   waitUntilDone:NO];
  }
}

- (void)writeDidComplete
{
  NSLog(@"ISOWriteOperation: Write operation completed successfully");
  [_progressWindow close];
  
  if ([_delegate respondsToSelector:@selector(isoWriteOperationDidComplete:)]) {
    [_delegate isoWriteOperationDidComplete:self];
  }
  
  NSRunAlertPanel(
    NSLocalizedString(@"Write Complete", @""),
    NSLocalizedString(@"The ISO image has been successfully written to the device.\n\nThe new volume should appear on your desktop when you plug the device in.", @""),
    NSLocalizedString(@"OK", @""),
    nil, nil);
}

- (void)writeWasCancelled
{
  [_progressWindow close];
  
  if ([_delegate respondsToSelector:@selector(isoWriteOperationWasCancelled:)]) {
    [_delegate isoWriteOperationWasCancelled:self];
  }
}

- (void)startProgressTimer
{
  _progressTimer = [[NSTimer scheduledTimerWithTimeInterval:PROGRESS_UPDATE_INTERVAL
                                                    target:self
                                                  selector:@selector(updateProgress:)
                                                  userInfo:nil
                                                   repeats:YES] retain];
}

- (void)stopProgressTimer
{
  [_progressTimer invalidate];
  RELEASE(_progressTimer);
  _progressTimer = nil;
}

- (void)updateProgress:(NSTimer *)timer
{
  if (_state != ISOWriteStateWriting) {
    return;
  }
  
  double progress = (_isoSize > 0) ? ((double)_bytesWritten / (double)_isoSize * 100.0) : 0;
  
  /* Calculate speed and ETA */
  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startTime];
  double bytesPerSecond = (elapsed > 0) ? ((double)_bytesWritten / elapsed) : 0;
  
  unsigned long long remaining = _isoSize - _bytesWritten;
  NSTimeInterval eta = (bytesPerSecond > 0) ? ((double)remaining / bytesPerSecond) : 0;
  
  [_progressWindow setProgress:progress
                  bytesWritten:_bytesWritten
                    totalBytes:_isoSize
                  transferRate:bytesPerSecond
                           eta:eta];
  
  if ([_delegate respondsToSelector:@selector(isoWriteOperation:didUpdateProgress:bytesWritten:totalBytes:transferRate:)]) {
    [_delegate isoWriteOperation:self
              didUpdateProgress:progress
                   bytesWritten:_bytesWritten
                     totalBytes:_isoSize
                   transferRate:bytesPerSecond];
  }
}

#pragma mark - ISOWriteProgressDelegate

- (void)progressWindowDidRequestCancel:(id)sender
{
  [self cancel:sender];
}

@end
