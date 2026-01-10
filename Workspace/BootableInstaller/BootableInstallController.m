/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BootableInstallController.h"
#import <unistd.h>
#import <sys/mount.h>

// Notification names
NSString * const BootableInstallDidStartNotification = @"BootableInstallDidStartNotification";
NSString * const BootableInstallProgressNotification = @"BootableInstallProgressNotification";
NSString * const BootableInstallDidCompleteNotification = @"BootableInstallDidCompleteNotification";
NSString * const BootableInstallDidFailNotification = @"BootableInstallDidFailNotification";
NSString * const BootableInstallDidCancelNotification = @"BootableInstallDidCancelNotification";

// Forward declaration for FSNode if not available
#ifndef FSNODE_DEFINED
@interface FSNode : NSObject
- (NSString *)path;
- (BOOL)isMountPoint;
- (BOOL)isDirectory;
@end
#define FSNODE_DEFINED
#endif


#pragma mark - BootableInstallLogEntry Implementation

@implementation BootableInstallLogEntry

@synthesize timestamp = _timestamp;
@synthesize level = _level;
@synthesize phase = _phase;
@synthesize message = _message;

+ (instancetype)infoWithPhase:(NSString *)phase message:(NSString *)msg
{
  BootableInstallLogEntry *entry = [[self alloc] init];
  entry.timestamp = [NSDate date];
  entry.level = @"INFO";
  entry.phase = phase;
  entry.message = msg;
  return [entry autorelease];
}

+ (instancetype)warningWithPhase:(NSString *)phase message:(NSString *)msg
{
  BootableInstallLogEntry *entry = [[self alloc] init];
  entry.timestamp = [NSDate date];
  entry.level = @"WARNING";
  entry.phase = phase;
  entry.message = msg;
  return [entry autorelease];
}

+ (instancetype)errorWithPhase:(NSString *)phase message:(NSString *)msg
{
  BootableInstallLogEntry *entry = [[self alloc] init];
  entry.timestamp = [NSDate date];
  entry.level = @"ERROR";
  entry.phase = phase;
  entry.message = msg;
  return [entry autorelease];
}

- (void)dealloc
{
  [_timestamp release];
  [_level release];
  [_phase release];
  [_message release];
  [super dealloc];
}

- (NSString *)formattedString
{
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
  NSString *timeStr = [formatter stringFromDate:_timestamp];
  [formatter release];
  
  return [NSString stringWithFormat:@"[%@] [%@] [%@] %@",
          timeStr, _level, _phase, _message];
}

@end


#pragma mark - BootableInstallResult Implementation

@implementation BootableInstallResult

@synthesize success = _success;
@synthesize errorMessage = _errorMessage;
@synthesize errorPhase = _errorPhase;
@synthesize logEntries = _logEntries;
@synthesize totalTime = _totalTime;
@synthesize installStats = _installStats;

+ (instancetype)success
{
  BootableInstallResult *result = [[self alloc] init];
  result.success = YES;
  return [result autorelease];
}

+ (instancetype)failureWithError:(NSString *)error phase:(NSString *)phase
{
  BootableInstallResult *result = [[self alloc] init];
  result.success = NO;
  result.errorMessage = error;
  result.errorPhase = phase;
  return [result autorelease];
}

- (void)dealloc
{
  [_errorMessage release];
  [_errorPhase release];
  [_logEntries release];
  [_installStats release];
  [super dealloc];
}

- (NSString *)fullLogAsString
{
  NSMutableString *log = [NSMutableString string];
  for (BootableInstallLogEntry *entry in _logEntries) {
    [log appendString:[entry formattedString]];
    [log appendString:@"\n"];
  }
  return log;
}

- (BOOL)writeLogToFile:(NSString *)path
{
  NSString *log = [self fullLogAsString];
  return [log writeToFile:path 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:nil];
}

@end


#pragma mark - BootableInstallController Implementation

@implementation BootableInstallController

static BootableInstallController *_sharedController = nil;

@synthesize state = _state;

- (BOOL)isRunning
{
  return _state != BootableInstallStateIdle && 
         _state != BootableInstallStateCompleted &&
         _state != BootableInstallStateFailed &&
         _state != BootableInstallStateCancelled;
}

#pragma mark - Singleton

+ (instancetype)sharedController
{
  if (_sharedController == nil) {
    _sharedController = [[BootableInstallController alloc] init];
  }
  return _sharedController;
}

#pragma mark - Initialization

- (instancetype)init
{
  self = [super init];
  if (self) {
    _fm = [[NSFileManager defaultManager] retain];
    _validator = [[BootPartitionValidator sharedValidator] retain];
    _detector = [[BootEnvironmentDetector sharedDetector] retain];
    _copier = nil;
    _bootloaderInstaller = nil;
    
    _state = BootableInstallStateIdle;
    _logEntries = [[NSMutableArray alloc] init];
    _mountedPaths = [[NSMutableArray alloc] init];
    
    _excludeHome = NO;
    _targetWasMounted = NO;
  }
  return self;
}

- (void)dealloc
{
  [_fm release];
  [_validator release];
  [_detector release];
  [_copier release];
  [_bootloaderInstaller release];
  [_environment release];
  [_sourceNode release];
  [_targetNode release];
  [_sourcePath release];
  [_targetPath release];
  [_targetDevice release];
  [_targetDisk release];
  [_espMountPoint release];
  [_bootMountPoint release];
  [_logEntries release];
  [_mountedPaths release];
  [_startTime release];
  [_progressWindow release];
  [super dealloc];
}

#pragma mark - Main Entry Point

- (BOOL)validateSudoAskPassAvailable
{
  // If running as root, no need for askpass
  if (getuid() == 0) {
    return YES;
  }
  
  char *askpass = getenv("SUDO_ASKPASS");
  if (askpass == NULL || strlen(askpass) == 0) {
    [self showErrorAlert:
      @"The SUDO_ASKPASS environment variable is not set.\n\n"
      @"This operation requires root privileges. Please set SUDO_ASKPASS to a "
      @"valid password dialog helper (e.g., SudoAskPass.app) and try again."
      title:@"SUDO_ASKPASS Not Set"];
    return NO;
  }
  
  NSString *askpassPath = [NSString stringWithUTF8String:askpass];
  NSFileManager *fm = [NSFileManager defaultManager];
  
  if (![fm isExecutableFileAtPath:askpassPath]) {
    [self showErrorAlert:
      [NSString stringWithFormat:
        @"The SUDO_ASKPASS path is not executable:\n%@\n\n"
        @"Please set SUDO_ASKPASS to a valid password dialog helper.", askpassPath]
      title:@"Invalid SUDO_ASKPASS"];
    return NO;
  }
  
  return YES;
}

- (BOOL)runCommandWithSudo:(NSArray *)arguments 
                    output:(NSString **)outputPtr 
                     error:(NSString **)errorPtr
{
  // If running as root, run directly without sudo
  BOOL needSudo = (getuid() != 0);
  
  NSTask *task = [[NSTask alloc] init];
  NSMutableArray *args = [NSMutableArray array];
  
  if (needSudo) {
    [task setLaunchPath:@"/usr/bin/sudo"];
    [args addObject:@"-A"];
    [args addObject:@"-E"];
    [args addObjectsFromArray:arguments];
  } else {
    [task setLaunchPath:[arguments objectAtIndex:0]];
    NSRange range = NSMakeRange(1, [arguments count] - 1);
    [args addObjectsFromArray:[arguments subarrayWithRange:range]];
  }
  
  [task setArguments:args];
  
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];
  [task setStandardOutput:outPipe];
  [task setStandardError:errPipe];
  
  @try {
    [task launch];
    [task waitUntilExit];
    
    NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];
    
    if (outputPtr) {
      *outputPtr = [[[NSString alloc] initWithData:outData 
                                          encoding:NSUTF8StringEncoding] autorelease];
    }
    if (errorPtr) {
      *errorPtr = [[[NSString alloc] initWithData:errData 
                                         encoding:NSUTF8StringEncoding] autorelease];
    }
    
    int status = [task terminationStatus];
    [task release];
    return (status == 0);
  }
  @catch (NSException *e) {
    if (errorPtr) {
      *errorPtr = [e reason];
    }
    [task release];
    return NO;
  }
}

- (void)performInstallFromSource:(FSNode *)sourceNode
                        toTarget:(FSNode *)targetNode
{
  if ([self isInstallationInProgress]) {
    [self showErrorAlert:@"An installation is already in progress." 
                   title:@"Installation In Progress"];
    return;
  }
  
  // Validate SUDO_ASKPASS before proceeding
  if (![self validateSudoAskPassAvailable]) {
    return;
  }
  
  // Store nodes
  [_sourceNode release];
  _sourceNode = [sourceNode retain];
  [_targetNode release];
  _targetNode = [targetNode retain];
  
  [_sourcePath release];
  _sourcePath = [[sourceNode path] retain];
  [_targetPath release];
  _targetPath = [[targetNode path] retain];
  
  [_startTime release];
  _startTime = [[NSDate date] retain];
  [_logEntries removeAllObjects];
  
  [self logInfo:@"Starting bootable installation"];
  [self logInfo:[NSString stringWithFormat:@"Source: %@", _sourcePath]];
  [self logInfo:[NSString stringWithFormat:@"Target: %@", _targetPath]];
  
  // Show experimental warning
  if (![self showExperimentalWarning]) {
    [self logInfo:@"Installation cancelled by user"];
    return;
  }
  
  // Detect environment
  [_environment release];
  _environment = [[_detector detectEnvironment] retain];
  [self logInfo:[NSString stringWithFormat:@"Detected environment: %@", _environment]];
  
  // Ask about home exclusion
  _excludeHome = [self askExcludeHome];
  [self logInfo:[NSString stringWithFormat:@"Exclude /home: %@", 
                 _excludeHome ? @"YES" : @"NO"]];
  
  // Post start notification
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:BootableInstallDidStartNotification
                  object:self
                userInfo:@{@"source": _sourcePath, @"target": _targetPath}];
  
  // Show progress window
  [self showProgressWindow];
  
  // Run installation phases
  [self transitionToState:BootableInstallStateValidating];
  
  // Run in background to not block UI
  [self performSelectorInBackground:@selector(runInstallationPhases) 
                         withObject:nil];
}

- (void)runInstallationPhases
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL success = YES;
  
  // Phase 1: Validate
  if (success) {
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Validating target..." 
                        waitUntilDone:YES];
    success = [self phaseValidate];
  }
  
  // Phase 2: Mount
  if (success) {
    [self transitionToState:BootableInstallStateMounting];
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Mounting filesystems..." 
                        waitUntilDone:YES];
    success = [self phaseMountTarget];
  }
  
  // Phase 3: Create layout
  if (success) {
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Creating directory layout..." 
                        waitUntilDone:YES];
    success = [self phaseCreateLayout];
  }
  
  // Phase 4: Copy filesystem
  if (success) {
    [self transitionToState:BootableInstallStateCopying];
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Copying filesystem..." 
                        waitUntilDone:YES];
    success = [self phaseCopyFilesystem];
  }
  
  // Phase 5: Configure system
  if (success) {
    [self transitionToState:BootableInstallStateConfiguring];
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Configuring system..." 
                        waitUntilDone:YES];
    success = [self phaseConfigureSystem];
  }
  
  // Phase 6: Install bootloader
  if (success) {
    [self transitionToState:BootableInstallStateBootloader];
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Installing bootloader..." 
                        waitUntilDone:YES];
    success = [self phaseInstallBootloader];
  }
  
  // Phase 7: Verify
  if (success) {
    [self transitionToState:BootableInstallStateVerifying];
    [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                           withObject:@"Verifying installation..." 
                        waitUntilDone:YES];
    success = [self phaseVerify];
  }
  
  // Phase 8: Cleanup
  [self transitionToState:BootableInstallStateUnmounting];
  [self performSelectorOnMainThread:@selector(updateProgressPhase:) 
                         withObject:@"Finishing up..." 
                      waitUntilDone:YES];
  [self phaseCleanup];
  
  // Finish
  if (success) {
    [self transitionToState:BootableInstallStateCompleted];
    [self performSelectorOnMainThread:@selector(installationCompleted) 
                           withObject:nil 
                        waitUntilDone:NO];
  }
  
  [pool release];
}

- (void)updateProgressPhase:(NSString *)phase
{
  [self updateProgressWithPhase:phase status:@"" progress:-1 currentFile:nil];
}

- (void)installationCompleted
{
  [self closeProgressWindow];
  
  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startTime];
  [self logInfo:[NSString stringWithFormat:@"Installation completed in %.1f seconds", 
                 elapsed]];
  
  NSDictionary *stats = _copier ? [_copier statistics] : @{};
  
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:BootableInstallDidCompleteNotification
                  object:self
                userInfo:@{@"stats": stats, @"time": @(elapsed)}];
  
  [self showSuccessDialog:stats];
}

- (BOOL)isInstallationInProgress
{
  return [self isRunning];
}

- (void)cancelInstallation
{
  if (_copier) {
    [_copier cancel];
  }
  
  [self transitionToState:BootableInstallStateCancelled];
  [self logInfo:@"Installation cancelled by user"];
  
  [self performFailureCleanup];
  [self closeProgressWindow];
  
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:BootableInstallDidCancelNotification
                  object:self
                userInfo:nil];
}

#pragma mark - Drag-and-Drop Support

- (BOOL)canAcceptDragOfSource:(FSNode *)sourceNode
                     toTarget:(FSNode *)targetNode
{
  return [_validator canAcceptDragForTarget:targetNode source:sourceNode];
}

- (NSString *)lastDragRefusalReason
{
  // This would be stored from the last validation
  return nil;
}

#pragma mark - User Confirmation Dialogs

- (BOOL)showExperimentalWarning
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Experimental Feature"];
  [alert setInformativeText:
    @"Creating a bootable installation is an experimental feature that may "
    @"result in DATA LOSS on the target partition.\n\n"
    @"The target partition will be COMPLETELY OVERWRITTEN.\n\n"
    @"Are you sure you want to continue?"];
  [alert setAlertStyle:NSCriticalAlertStyle];
  
  // Cancel is the default (first) button
  [alert addButtonWithTitle:@"Cancel"];
  [alert addButtonWithTitle:@"Continue at Own Risk"];
  
  NSModalResponse response = [alert runModal];
  [alert release];
  
  return response == NSAlertSecondButtonReturn;
}

- (BOOL)askExcludeHome
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Exclude /home Directory?"];
  [alert setInformativeText:
    @"Would you like to exclude the /home directory from the copy?\n\n"
    @"Excluding /home will:\n"
    @"• Make the copy faster and smaller\n"
    @"• Create a clean installation without user data\n\n"
    @"Including /home will:\n"
    @"• Copy all user files and settings\n"
    @"• Take longer and require more space"];
  [alert setAlertStyle:NSInformationalAlertStyle];
  
  [alert addButtonWithTitle:@"Exclude /home"];
  [alert addButtonWithTitle:@"Include /home"];
  
  NSModalResponse response = [alert runModal];
  [alert release];
  
  return response == NSAlertFirstButtonReturn;
}

- (void)showErrorAlert:(NSString *)message title:(NSString *)title
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:title];
  [alert setInformativeText:message];
  [alert setAlertStyle:NSCriticalAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

- (void)showSuccessDialog:(NSDictionary *)stats
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Installation Complete"];
  
  NSMutableString *info = [NSMutableString string];
  [info appendString:@"The bootable installation was created successfully.\n\n"];
  
  if (stats[@"bytesCopied"]) {
    unsigned long long bytes = [stats[@"bytesCopied"] unsignedLongLongValue];
    [info appendFormat:@"Data copied: %.2f GB\n", bytes / 1073741824.0];
  }
  if (stats[@"filesCopied"]) {
    [info appendFormat:@"Files copied: %@\n", stats[@"filesCopied"]];
  }
  
  [info appendString:@"\nYou can now boot from the target partition."];
  
  [alert setInformativeText:info];
  [alert setAlertStyle:NSInformationalAlertStyle];
  [alert addButtonWithTitle:@"OK"];
  [alert runModal];
  [alert release];
}

#pragma mark - Progress Window

- (void)showProgressWindow
{
  if (_progressWindow) {
    [_progressWindow makeKeyAndOrderFront:nil];
    return;
  }
  
  NSRect frame = NSMakeRect(0, 0, 450, 180);
  _progressWindow = [[NSWindow alloc] 
    initWithContentRect:frame
              styleMask:NSWindowStyleMaskTitled
                backing:NSBackingStoreBuffered
                  defer:NO];
  
  [_progressWindow setTitle:@"Creating Bootable Installation"];
  [_progressWindow center];
  
  NSView *contentView = [_progressWindow contentView];
  
  // Phase label
  _phaseField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 130, 410, 20)];
  [_phaseField setEditable:NO];
  [_phaseField setBordered:NO];
  [_phaseField setBackgroundColor:[NSColor clearColor]];
  [_phaseField setFont:[NSFont boldSystemFontOfSize:13]];
  [_phaseField setStringValue:@"Preparing..."];
  [contentView addSubview:_phaseField];
  [_phaseField release];
  
  // Status label
  _statusField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 105, 410, 18)];
  [_statusField setEditable:NO];
  [_statusField setBordered:NO];
  [_statusField setBackgroundColor:[NSColor clearColor]];
  [_statusField setFont:[NSFont systemFontOfSize:11]];
  [_statusField setTextColor:[NSColor secondaryLabelColor]];
  [_statusField setStringValue:@""];
  [contentView addSubview:_statusField];
  [_statusField release];
  
  // Progress indicator
  _progressIndicator = [[NSProgressIndicator alloc] 
    initWithFrame:NSMakeRect(20, 75, 410, 20)];
  [_progressIndicator setStyle:NSProgressIndicatorBarStyle];
  [_progressIndicator setIndeterminate:YES];
  [_progressIndicator startAnimation:nil];
  [contentView addSubview:_progressIndicator];
  [_progressIndicator release];
  
  // Current file label
  _fileField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 50, 410, 18)];
  [_fileField setEditable:NO];
  [_fileField setBordered:NO];
  [_fileField setBackgroundColor:[NSColor clearColor]];
  [_fileField setFont:[NSFont systemFontOfSize:10]];
  [_fileField setTextColor:[NSColor tertiaryLabelColor]];
  [_fileField setStringValue:@""];
  [contentView addSubview:_fileField];
  [_fileField release];
  
  // Cancel button
  _cancelButton = [[NSButton alloc] initWithFrame:NSMakeRect(350, 15, 80, 28)];
  [_cancelButton setTitle:@"Cancel"];
  [_cancelButton setBezelStyle:NSRoundedBezelStyle];
  [_cancelButton setTarget:self];
  [_cancelButton setAction:@selector(cancelInstallation)];
  [contentView addSubview:_cancelButton];
  [_cancelButton release];
  
  [_progressWindow makeKeyAndOrderFront:nil];
}

- (void)updateProgressWithPhase:(NSString *)phase
                         status:(NSString *)status
                       progress:(double)progress
                    currentFile:(NSString *)file
{
  if (!_progressWindow) return;
  
  if (phase) {
    [_phaseField setStringValue:phase];
  }
  if (status) {
    [_statusField setStringValue:status];
  }
  if (file) {
    // Truncate long paths
    if ([file length] > 60) {
      file = [NSString stringWithFormat:@"...%@", 
              [file substringFromIndex:[file length] - 57]];
    }
    [_fileField setStringValue:file];
  }
  
  if (progress >= 0) {
    [_progressIndicator setIndeterminate:NO];
    [_progressIndicator setDoubleValue:progress * 100];
  } else {
    [_progressIndicator setIndeterminate:YES];
    [_progressIndicator startAnimation:nil];
  }
  
  // Post progress notification
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:BootableInstallProgressNotification
                  object:self
                userInfo:@{@"phase": phase ?: @"", 
                          @"progress": @(progress),
                          @"status": status ?: @""}];
}

- (void)closeProgressWindow
{
  if (_progressWindow) {
    [_progressWindow close];
    [_progressWindow release];
    _progressWindow = nil;
  }
}

#pragma mark - Installation Phases

- (BOOL)phaseValidate
{
  [self logInfo:@"Phase: Validation"];
  
  BootPartitionValidationResult *result = 
    [_validator validateTargetNode:_targetNode forSourceNode:_sourceNode];
  
  if (!result.valid) {
    [self handleFatalError:result.failureReason inPhase:@"Validation"];
    return NO;
  }
  
  // Get device information
  [_targetDevice release];
  _targetDevice = [[_detector deviceForMountPoint:_targetPath] retain];
  
  [_targetDisk release];
  _targetDisk = [[_detector parentDiskForPartition:_targetDevice] retain];
  
  [self logInfo:[NSString stringWithFormat:@"Target device: %@", _targetDevice]];
  [self logInfo:[NSString stringWithFormat:@"Target disk: %@", _targetDisk]];
  
  // Find ESP and boot partitions
  if (_environment.firmwareType == BootFirmwareTypeUEFI) {
    NSString *espDev = nil, *espMount = nil;
    if ([_detector findESPDevice:&espDev mountPoint:&espMount]) {
      [_espMountPoint release];
      _espMountPoint = [espMount retain];
      [self logInfo:[NSString stringWithFormat:@"ESP mount: %@", _espMountPoint]];
    }
  }
  
  if (_environment.isRaspberryPi) {
    NSString *bootDev = nil, *bootMount = nil;
    if ([_detector findBootPartition:&bootDev mountPoint:&bootMount]) {
      [_bootMountPoint release];
      _bootMountPoint = [bootMount retain];
      [self logInfo:[NSString stringWithFormat:@"Boot mount: %@", _bootMountPoint]];
    }
  }
  
  return YES;
}

- (BOOL)phaseMountTarget
{
  [self logInfo:@"Phase: Mount Target"];
  
  // Check if target is already mounted
  NSString *existingMount = [_detector mountPointForDevice:_targetDevice];
  if (existingMount) {
    _targetWasMounted = YES;
    [_targetPath release];
    _targetPath = [existingMount retain];
    [self logInfo:[NSString stringWithFormat:@"Target already mounted at %@", _targetPath]];
  } else {
    // Mount the target
    _targetWasMounted = NO;
    
    // Create temporary mount point
    NSString *tempMount = [NSString stringWithFormat:@"/tmp/bootable_install_%d", 
                           (int)getpid()];
    [_fm createDirectoryAtPath:tempMount 
   withIntermediateDirectories:YES 
                    attributes:nil 
                         error:nil];
    
    NSError *error = nil;
    if (![self mountDevice:_targetDevice atPath:tempMount readOnly:NO error:&error]) {
      [self handleFatalError:[error localizedDescription] inPhase:@"Mount"];
      return NO;
    }
    
    [_targetPath release];
    _targetPath = [tempMount retain];
    [_mountedPaths addObject:tempMount];
  }
  
  return YES;
}

- (BOOL)phaseCreateLayout
{
  [self logInfo:@"Phase: Create Layout"];
  
  // This is handled by the copier, but we can do some prep here
  return YES;
}

- (BOOL)phaseCopyFilesystem
{
  [self logInfo:@"Phase: Copy Filesystem"];
  
  // Build rsync command with proper exclusions
  NSMutableArray *rsyncArgs = [NSMutableArray arrayWithObjects:
    @"/usr/bin/rsync",
    @"-aHAXx",           // archive, hardlinks, ACLs, xattrs, one-filesystem
    @"--info=progress2", // progress info
    @"--delete",         // delete extraneous files from destination
    nil];
  
  // Add exclusions for virtual/runtime directories
  NSArray *exclusions = @[
    @"/proc/*", @"/sys/*", @"/dev/*", @"/run/*", @"/tmp/*",
    @"/var/run/*", @"/var/lock/*", @"/var/tmp/*",
    @"/mnt/*", @"/media/*", @"/lost+found/*"
  ];
  
  for (NSString *exclusion in exclusions) {
    [rsyncArgs addObject:@"--exclude"];
    [rsyncArgs addObject:exclusion];
  }
  
  // Optionally exclude /home
  if (_excludeHome) {
    [rsyncArgs addObject:@"--exclude"];
    [rsyncArgs addObject:@"/home/*"];
  }
  
  // Add source (with trailing slash to copy contents) and destination
  [rsyncArgs addObject:[NSString stringWithFormat:@"%@/", _sourcePath]];
  [rsyncArgs addObject:[NSString stringWithFormat:@"%@/", _targetPath]];
  
  [self logInfo:[NSString stringWithFormat:@"Running rsync with sudo: %@", 
                 [rsyncArgs componentsJoinedByString:@" "]]];
  
  // Run rsync with sudo
  NSString *output = nil, *errorOutput = nil;
  BOOL success = [self runCommandWithSudo:rsyncArgs output:&output error:&errorOutput];
  
  if (!success) {
    NSString *errorMsg = errorOutput ?: @"rsync failed";
    [self handleFatalError:errorMsg inPhase:@"Copy"];
    return NO;
  }
  
  [self logInfo:@"Filesystem copy completed successfully"];
  if ([output length] > 0) {
    [self logInfo:output];
  }
  
  return YES;
}

- (BOOL)phaseConfigureSystem
{
  [self logInfo:@"Phase: Configure System"];
  
  // Generate fstab
  NSString *rootUUID = [[BootloaderInstaller new] uuidForDevice:_targetDevice];
  NSString *fsType = [_detector filesystemTypeForDevice:_targetDevice];
  
  BootloaderInstaller *installer = [[BootloaderInstaller alloc] 
                                     initWithEnvironment:_environment];
  
  NSError *error = nil;
  if (![installer generateFstabAtPath:_targetPath 
                           rootDevice:_targetDevice 
                             rootUUID:rootUUID 
                           rootFSType:fsType ?: @"ext4"
                           bootDevice:nil 
                             bootUUID:nil 
                            espDevice:nil 
                              espUUID:nil 
                                error:&error]) {
    [installer release];
    [self handleFatalError:[error localizedDescription] inPhase:@"Configure"];
    return NO;
  }
  
  [installer release];
  [self logInfo:@"Generated /etc/fstab"];
  
  return YES;
}

- (BOOL)phaseInstallBootloader
{
  [self logInfo:@"Phase: Install Bootloader"];
  
  [_bootloaderInstaller release];
  _bootloaderInstaller = [[BootloaderInstaller alloc] 
                           initWithEnvironment:_environment];
  _bootloaderInstaller.delegate = self;
  
  BootloaderInstallResult *result = 
    [_bootloaderInstaller installBootloaderToRoot:_targetPath 
                                        bootMount:_bootMountPoint 
                                         espMount:_espMountPoint 
                                       targetDisk:_targetDisk];
  
  if (!result.success) {
    [self handleFatalError:result.errorMessage inPhase:@"Bootloader"];
    return NO;
  }
  
  [self logInfo:[NSString stringWithFormat:@"Installed bootloader: %@", 
                 result.bootloaderVersion]];
  
  // Regenerate initramfs if needed
  NSError *error = nil;
  if (![_bootloaderInstaller regenerateInitramfs:_targetPath error:&error]) {
    [self logWarning:@"Could not regenerate initramfs - using existing"];
  }
  
  return YES;
}

- (BOOL)phaseVerify
{
  [self logInfo:@"Phase: Verify"];
  
  // Verify bootloader
  NSString *reason = nil;
  if (![_bootloaderInstaller verifyBootloaderInstallation:_targetPath 
                                                   reason:&reason]) {
    [self logWarning:[NSString stringWithFormat:@"Bootloader verification warning: %@", 
                      reason]];
  }
  
  // Verify file copy
  if (![_copier quickVerifyTarget:_targetPath withSource:_sourcePath reason:&reason]) {
    [self logWarning:[NSString stringWithFormat:@"Copy verification warning: %@", 
                      reason]];
  }
  
  return YES;
}

- (BOOL)phaseCleanup
{
  [self logInfo:@"Phase: Cleanup"];
  
  // Sync filesystems
  [self syncFilesystems];
  
  // Unmount everything we mounted
  [self unmountAllMounted];
  
  return YES;
}

#pragma mark - Mount Operations

- (BOOL)mountDevice:(NSString *)device
            atPath:(NSString *)mountPoint
          readOnly:(BOOL)ro
             error:(NSError **)error
{
  NSMutableArray *args = [NSMutableArray arrayWithObject:@"/bin/mount"];
  if (ro) {
    [args addObject:@"-r"];
  }
  [args addObject:device];
  [args addObject:mountPoint];
  
  NSString *output = nil, *errorOutput = nil;
  BOOL success = [self runCommandWithSudo:args output:&output error:&errorOutput];
  
  if (!success) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootableInstallController" 
                                   code:1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Failed to mount %@ at %@: %@", 
                                  device, mountPoint, errorOutput ?: @"unknown error"]}];
    }
    return NO;
  }
  
  return YES;
}

- (BOOL)unmountPath:(NSString *)path
              error:(NSError **)error
{
  NSString *output = nil, *errorOutput = nil;
  BOOL success = [self runCommandWithSudo:@[@"/bin/umount", path] 
                                   output:&output 
                                    error:&errorOutput];
  
  if (!success) {
    // Try lazy unmount
    success = [self runCommandWithSudo:@[@"/bin/umount", @"-l", path] 
                                output:&output 
                                 error:&errorOutput];
  }
  
  if (!success) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootableInstallController" 
                                   code:1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Failed to unmount %@: %@", 
                                  path, errorOutput ?: @"unknown error"]}];
    }
    return NO;
  }
  
  return YES;;
}

- (void)unmountAllMounted
{
  // Unmount in reverse order
  for (NSInteger i = [_mountedPaths count] - 1; i >= 0; i--) {
    NSString *path = [_mountedPaths objectAtIndex:i];
    [self unmountPath:path error:nil];
    
    // Remove temp directory if we created it
    if ([path hasPrefix:@"/tmp/bootable_install_"]) {
      [_fm removeItemAtPath:path error:nil];
    }
  }
  [_mountedPaths removeAllObjects];
}

- (void)syncFilesystems
{
  sync();
  [_detector runCommandStatus:@"/bin/sync" arguments:nil];
}

#pragma mark - Error Handling

- (void)handleFatalError:(NSString *)error inPhase:(NSString *)phase
{
  [self transitionToState:BootableInstallStateFailed];
  [self logError:[NSString stringWithFormat:@"%@: %@", phase, error]];
  
  [self performFailureCleanup];
  
  [self performSelectorOnMainThread:@selector(showFatalError:) 
                         withObject:@{@"error": error, @"phase": phase} 
                      waitUntilDone:NO];
  
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:BootableInstallDidFailNotification
                  object:self
                userInfo:@{@"error": error, @"phase": phase}];
}

- (void)showFatalError:(NSDictionary *)info
{
  [self closeProgressWindow];
  [self showErrorAlert:info[@"error"] 
                 title:[NSString stringWithFormat:@"Installation Failed (%@)", 
                        info[@"phase"]]];
}

- (void)performFailureCleanup
{
  [self syncFilesystems];
  [self unmountAllMounted];
}

#pragma mark - Logging

- (void)logInfo:(NSString *)message
{
  BootableInstallLogEntry *entry = 
    [BootableInstallLogEntry infoWithPhase:[self stateDescription] message:message];
  [_logEntries addObject:entry];
  NSLog(@"%@", [entry formattedString]);
}

- (void)logWarning:(NSString *)message
{
  BootableInstallLogEntry *entry = 
    [BootableInstallLogEntry warningWithPhase:[self stateDescription] message:message];
  [_logEntries addObject:entry];
  NSLog(@"%@", [entry formattedString]);
}

- (void)logError:(NSString *)message
{
  BootableInstallLogEntry *entry = 
    [BootableInstallLogEntry errorWithPhase:[self stateDescription] message:message];
  [_logEntries addObject:entry];
  NSLog(@"%@", [entry formattedString]);
}

- (NSArray *)logEntries
{
  return [[_logEntries copy] autorelease];
}

- (BOOL)saveLogToPath:(NSString *)path
{
  BootableInstallResult *result = [[BootableInstallResult alloc] init];
  result.logEntries = _logEntries;
  BOOL success = [result writeLogToFile:path];
  [result release];
  return success;
}

#pragma mark - State Machine

- (void)transitionToState:(BootableInstallState)newState
{
  _state = newState;
}

- (NSString *)stateDescription
{
  switch (_state) {
    case BootableInstallStateIdle: return @"Idle";
    case BootableInstallStateValidating: return @"Validating";
    case BootableInstallStateConfirming: return @"Confirming";
    case BootableInstallStateMounting: return @"Mounting";
    case BootableInstallStateCopying: return @"Copying";
    case BootableInstallStateConfiguring: return @"Configuring";
    case BootableInstallStateBootloader: return @"Bootloader";
    case BootableInstallStateVerifying: return @"Verifying";
    case BootableInstallStateUnmounting: return @"Unmounting";
    case BootableInstallStateCompleted: return @"Completed";
    case BootableInstallStateFailed: return @"Failed";
    case BootableInstallStateCancelled: return @"Cancelled";
    default: return @"Unknown";
  }
}

#pragma mark - BootableFileCopierDelegate

- (void)copier:(BootableFileCopier *)copier
    didProgress:(unsigned long long)bytesCompleted
        ofTotal:(unsigned long long)bytesTotal
          files:(unsigned long long)filesCompleted
    totalFiles:(unsigned long long)filesTotal
{
  double progress = (bytesTotal > 0) ? (double)bytesCompleted / bytesTotal : 0;
  
  NSString *status = [NSString stringWithFormat:@"%.2f GB of %.2f GB (%.0f%%)",
                      bytesCompleted / 1073741824.0,
                      bytesTotal / 1073741824.0,
                      progress * 100];
  
  [self performSelectorOnMainThread:@selector(updateCopyProgress:) 
                         withObject:@{@"progress": @(progress), 
                                      @"status": status,
                                      @"file": copier.currentPath ?: @""} 
                      waitUntilDone:NO];
}

- (void)updateCopyProgress:(NSDictionary *)info
{
  [self updateProgressWithPhase:@"Copying filesystem..." 
                         status:info[@"status"] 
                       progress:[info[@"progress"] doubleValue] 
                    currentFile:info[@"file"]];
}

- (void)copier:(BootableFileCopier *)copier willCopyPath:(NSString *)path
{
  // Optional - could update UI
}

- (void)copier:(BootableFileCopier *)copier didCopyPath:(NSString *)path
{
  // Optional - could update UI
}

- (BOOL)copier:(BootableFileCopier *)copier 
    shouldContinueAfterError:(NSString *)error 
                      atPath:(NSString *)path
{
  [self logWarning:[NSString stringWithFormat:@"Copy error at %@: %@", path, error]];
  
  // Continue on non-critical errors
  return YES;
}

- (void)copierWasCancelled:(BootableFileCopier *)copier
{
  [self logInfo:@"Copy operation was cancelled"];
}

#pragma mark - BootloaderInstallerDelegate

- (void)installer:(BootloaderInstaller *)installer 
    didStartPhase:(NSString *)phaseName
{
  [self logInfo:[NSString stringWithFormat:@"Bootloader phase: %@", phaseName]];
}

- (void)installer:(BootloaderInstaller *)installer 
   didCompletePhase:(NSString *)phaseName 
            success:(BOOL)success
{
  if (success) {
    [self logInfo:[NSString stringWithFormat:@"Completed: %@", phaseName]];
  } else {
    [self logWarning:[NSString stringWithFormat:@"Phase completed with issues: %@", 
                      phaseName]];
  }
}

- (void)installer:(BootloaderInstaller *)installer 
    statusMessage:(NSString *)message
{
  [self performSelectorOnMainThread:@selector(updateBootloaderStatus:) 
                         withObject:message 
                      waitUntilDone:NO];
}

- (void)updateBootloaderStatus:(NSString *)message
{
  [self updateProgressWithPhase:@"Installing bootloader..." 
                         status:message 
                       progress:-1 
                    currentFile:nil];
}

- (BOOL)installer:(BootloaderInstaller *)installer 
    shouldContinueAfterError:(NSString *)error
{
  [self logWarning:[NSString stringWithFormat:@"Bootloader error: %@", error]];
  return YES;  // Try to continue
}

- (BOOL)installer:(BootloaderInstaller *)installer 
runPrivilegedCommand:(NSArray *)arguments 
             output:(NSString **)output 
              error:(NSString **)error
{
  return [self runCommandWithSudo:arguments output:output error:error];
}

@end
