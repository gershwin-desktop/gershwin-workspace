/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BootloaderInstaller.h"
#import <sys/stat.h>
#import <sys/mount.h>
#import <unistd.h>

#pragma mark - BootloaderInstallResult Implementation

@implementation BootloaderInstallResult

@synthesize success = _success;
@synthesize errorMessage = _errorMessage;
@synthesize installedType = _installedType;
@synthesize bootloaderVersion = _bootloaderVersion;
@synthesize installedFiles = _installedFiles;
@synthesize generatedConfigs = _generatedConfigs;

+ (instancetype)successWithType:(BootloaderType)type version:(NSString *)version
{
  BootloaderInstallResult *result = [[self alloc] init];
  result.success = YES;
  result.installedType = type;
  result.bootloaderVersion = version;
  return [result autorelease];
}

+ (instancetype)failureWithError:(NSString *)error
{
  BootloaderInstallResult *result = [[self alloc] init];
  result.success = NO;
  result.errorMessage = error;
  return [result autorelease];
}

- (void)dealloc
{
  [_errorMessage release];
  [_bootloaderVersion release];
  [_installedFiles release];
  [_generatedConfigs release];
  [super dealloc];
}

@end


#pragma mark - BootloaderInstaller Implementation

@implementation BootloaderInstaller

@synthesize delegate = _delegate;
@synthesize preferredBootloader = _preferredBootloader;
@synthesize targetRootPath = _targetRootPath;
@synthesize targetBootPath = _targetBootPath;
@synthesize targetESPPath = _targetESPPath;
@synthesize targetDisk = _targetDisk;

#pragma mark - Initialization

+ (instancetype)installerForEnvironment:(BootEnvironmentInfo *)env
{
  return [[[self alloc] initWithEnvironment:env] autorelease];
}

- (instancetype)initWithEnvironment:(BootEnvironmentInfo *)env
{
  self = [super init];
  if (self) {
    _fm = [[NSFileManager defaultManager] retain];
    _detector = [[BootEnvironmentDetector sharedDetector] retain];
    _environment = [env retain];
    _preferredBootloader = BootloaderTypeNone;
    
    // Auto-select bootloader based on environment
    if (env.osType == SourceOSTypeLinux) {
      if (env.firmwareType == BootFirmwareTypeUEFI) {
        if ([_detector systemdBootAvailable]) {
          _preferredBootloader = BootloaderTypeSystemdBoot;
        } else {
          _preferredBootloader = BootloaderTypeGRUB2;
        }
      } else if (env.firmwareType == BootFirmwareTypeRaspberryPi) {
        _preferredBootloader = BootloaderTypeRPiFirmware;
      } else {
        _preferredBootloader = BootloaderTypeGRUB2;
      }
    } else if (env.osType == SourceOSTypeFreeBSD) {
      _preferredBootloader = BootloaderTypeFreeBSDLoader;
    }
  }
  return self;
}

- (instancetype)init
{
  BootEnvironmentInfo *env = [[BootEnvironmentDetector sharedDetector] 
                               detectEnvironment];
  return [self initWithEnvironment:env];
}

- (void)dealloc
{
  [_fm release];
  [_detector release];
  [_environment release];
  [_targetRootPath release];
  [_targetBootPath release];
  [_targetESPPath release];
  [_targetDisk release];
  [super dealloc];
}

#pragma mark - Privileged Command Execution

/**
 * Run a command with root privileges using the delegate if available
 */
- (BOOL)runPrivilegedCommand:(NSString *)command 
                   arguments:(NSArray *)arguments 
                      output:(NSString **)output 
                       error:(NSString **)error
{
  // Build full command array with command path as first element
  NSMutableArray *fullArgs = [NSMutableArray arrayWithObject:command];
  if (arguments) {
    [fullArgs addObjectsFromArray:arguments];
  }
  
  // Try delegate first if available
  if (_delegate && 
      [_delegate respondsToSelector:@selector(installer:runPrivilegedCommand:output:error:)]) {
    return [_delegate installer:self 
           runPrivilegedCommand:fullArgs 
                         output:output 
                          error:error];
  }
  
  // Fallback: run directly without sudo (will fail if root required)
  int status = [_detector runCommandStatus:command arguments:arguments];
  if (status != 0 && error) {
    *error = [NSString stringWithFormat:@"%@ exited with status %d", command, status];
  }
  return (status == 0);
}

/**
 * Run a command and get its output using privileged execution
 */
- (NSString *)runPrivilegedCommandOutput:(NSString *)command 
                              arguments:(NSArray *)arguments
{
  NSString *output = nil;
  NSString *errorStr = nil;
  [self runPrivilegedCommand:command arguments:arguments output:&output error:&errorStr];
  return output;
}

#pragma mark - Main Installation

- (BootloaderInstallResult *)installBootloaderToRoot:(NSString *)targetRoot
                                          bootMount:(NSString *)targetBoot
                                           espMount:(NSString *)targetESP
                                         targetDisk:(NSString *)disk
{
  self.targetRootPath = targetRoot;
  self.targetBootPath = targetBoot ?: targetRoot;
  self.targetESPPath = targetESP;
  self.targetDisk = disk;
  
  // Validate inputs
  NSString *reason = nil;
  if (![self verifyTargetLayout:&reason]) {
    return [BootloaderInstallResult failureWithError:reason];
  }
  
  if (![self verifyKernelExists:&reason]) {
    return [BootloaderInstallResult failureWithError:reason];
  }
  
  if (![self bootloaderToolsAvailable:_preferredBootloader reason:&reason]) {
    return [BootloaderInstallResult failureWithError:reason];
  }
  
  // Notify delegate
  if (_delegate && [_delegate respondsToSelector:@selector(installer:didStartPhase:)]) {
    [_delegate installer:self didStartPhase:@"Bootloader Installation"];
  }
  
  BootloaderInstallResult *result = nil;
  NSError *error = nil;
  
  switch (_preferredBootloader) {
    case BootloaderTypeGRUB2:
      if (_environment.firmwareType == BootFirmwareTypeUEFI) {
        if (![self installGrubUEFI:targetRoot espMount:targetESP error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      } else {
        if (![self installGrubBIOS:targetRoot targetDisk:disk error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      }
      if (!result) {
        if (![self generateGrubConfig:targetRoot error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      }
      if (!result) {
        result = [BootloaderInstallResult successWithType:BootloaderTypeGRUB2 
                                                  version:[self grubVersion]];
      }
      break;
      
    case BootloaderTypeSystemdBoot:
      if (![self installSystemdBoot:targetESP error:&error]) {
        result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
      } else {
        NSString *rootUUID = [self uuidForDevice:[_detector deviceForMountPoint:targetRoot]];
        if (![self generateSystemdBootEntries:targetESP 
                                   targetRoot:targetRoot 
                                     rootUUID:rootUUID 
                                        error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        } else {
          result = [BootloaderInstallResult successWithType:BootloaderTypeSystemdBoot 
                                                    version:@"systemd-boot"];
        }
      }
      break;
      
    case BootloaderTypeFreeBSDLoader:
      if (_environment.firmwareType == BootFirmwareTypeUEFI) {
        if (![self installFreeBSDUEFILoader:targetESP error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      } else if (_environment.rootPartitionScheme == PartitionSchemeTypeGPT) {
        if (![self installFreeBSDGPTBootcode:disk bootPartition:nil error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      } else {
        if (![self installFreeBSDMBRBootcode:disk error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        }
      }
      if (!result) {
        if (![self configureFreeBSDLoader:targetRoot error:&error]) {
          result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
        } else {
          result = [BootloaderInstallResult successWithType:BootloaderTypeFreeBSDLoader 
                                                    version:@"FreeBSD loader"];
        }
      }
      break;
      
    case BootloaderTypeRPiFirmware:
      if (![self configureRPiBoot:targetBoot ?: @"/boot" 
                       targetRoot:targetRoot 
                            error:&error]) {
        result = [BootloaderInstallResult failureWithError:[error localizedDescription]];
      } else {
        result = [BootloaderInstallResult successWithType:BootloaderTypeRPiFirmware 
                                                  version:@"Raspberry Pi firmware"];
      }
      break;
      
    default:
      result = [BootloaderInstallResult failureWithError:@"No bootloader type configured"];
      break;
  }
  
  // Notify delegate
  if (_delegate && [_delegate respondsToSelector:@selector(installer:didCompletePhase:success:)]) {
    [_delegate installer:self 
        didCompletePhase:@"Bootloader Installation" 
                 success:result.success];
  }
  
  return result;
}

- (BootloaderInstallResult *)autoInstallBootloader
{
  if (!_targetRootPath) {
    return [BootloaderInstallResult failureWithError:@"Target root path not set"];
  }
  
  return [self installBootloaderToRoot:_targetRootPath 
                             bootMount:_targetBootPath 
                              espMount:_targetESPPath 
                            targetDisk:_targetDisk];
}

#pragma mark - Pre-Installation Checks

- (BOOL)bootloaderToolsAvailable:(BootloaderType)type reason:(NSString **)reason
{
  switch (type) {
    case BootloaderTypeGRUB2:
      if (![_detector grubAvailable]) {
        if (reason) *reason = @"GRUB installation tools not found (grub-install)";
        return NO;
      }
      break;
      
    case BootloaderTypeSystemdBoot:
      if (![_detector systemdBootAvailable]) {
        if (reason) *reason = @"systemd-boot tools not found (bootctl)";
        return NO;
      }
      break;
      
    case BootloaderTypeFreeBSDLoader:
      if (![_detector freebsdBootcodeAvailable]) {
        if (reason) *reason = @"FreeBSD bootcode tools not found";
        return NO;
      }
      break;
      
    case BootloaderTypeRPiFirmware:
      // No special tools needed
      break;
      
    default:
      if (reason) *reason = @"Unknown bootloader type";
      return NO;
  }
  
  return YES;
}

- (BOOL)verifyTargetLayout:(NSString **)reason
{
  if (!_targetRootPath) {
    if (reason) *reason = @"Target root path not specified";
    return NO;
  }
  
  BOOL isDir = NO;
  if (![_fm fileExistsAtPath:_targetRootPath isDirectory:&isDir] || !isDir) {
    if (reason) *reason = @"Target root path does not exist or is not a directory";
    return NO;
  }
  
  // Check for essential directories
  NSArray *requiredDirs = @[@"etc", @"boot", @"usr"];
  for (NSString *dir in requiredDirs) {
    NSString *path = [_targetRootPath stringByAppendingPathComponent:dir];
    if (![_fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
      if (reason) *reason = [NSString stringWithFormat:@"Required directory missing: /%@", dir];
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)verifyKernelExists:(NSString **)reason
{
  if (_environment.osType == SourceOSTypeLinux) {
    // Check for kernel in target
    NSArray *kernelPaths = @[
      @"boot/vmlinuz",
      @"boot/vmlinuz-linux",
      @"vmlinuz"
    ];
    
    BOOL found = NO;
    for (NSString *path in kernelPaths) {
      NSString *fullPath = [_targetRootPath stringByAppendingPathComponent:path];
      if ([_fm fileExistsAtPath:fullPath]) {
        found = YES;
        break;
      }
    }
    
    // Also check for versioned kernels
    if (!found) {
      NSString *bootPath = [_targetRootPath stringByAppendingPathComponent:@"boot"];
      NSArray *bootContents = [_fm contentsOfDirectoryAtPath:bootPath error:nil];
      for (NSString *file in bootContents) {
        if ([file hasPrefix:@"vmlinuz-"]) {
          found = YES;
          break;
        }
      }
    }
    
    if (!found) {
      if (reason) *reason = @"No Linux kernel found in target";
      return NO;
    }
  }
  
  if (_environment.osType == SourceOSTypeFreeBSD) {
    NSString *kernelPath = [_targetRootPath 
                             stringByAppendingPathComponent:@"boot/kernel/kernel"];
    if (![_fm fileExistsAtPath:kernelPath]) {
      if (reason) *reason = @"No FreeBSD kernel found in target";
      return NO;
    }
  }
  
  return YES;
}

#pragma mark - Fstab Generation

- (BOOL)generateFstabAtPath:(NSString *)targetRoot
                 rootDevice:(NSString *)rootDevice
                   rootUUID:(NSString *)rootUUID
                 rootFSType:(NSString *)fsType
                 bootDevice:(NSString *)bootDevice
                   bootUUID:(NSString *)bootUUID
                  espDevice:(NSString *)espDevice
                    espUUID:(NSString *)espUUID
                      error:(NSError **)error
{
  NSMutableString *fstab = [NSMutableString string];
  
  [fstab appendString:@"# /etc/fstab: static file system information.\n"];
  [fstab appendString:@"# Generated by Bootable Installer\n"];
  [fstab appendString:@"#\n"];
  [fstab appendString:@"# <file system> <mount point> <type> <options> <dump> <pass>\n\n"];
  
  // Root filesystem
  if (rootUUID) {
    [fstab appendFormat:@"UUID=%@\t/\t%@\tdefaults\t0\t1\n", rootUUID, fsType];
  } else {
    [fstab appendFormat:@"%@\t/\t%@\tdefaults\t0\t1\n", rootDevice, fsType];
  }
  
  // Boot partition if separate
  if (bootDevice && ![bootDevice isEqualToString:rootDevice]) {
    NSString *bootFSType = [_detector filesystemTypeForDevice:bootDevice];
    if (bootUUID) {
      [fstab appendFormat:@"UUID=%@\t/boot\t%@\tdefaults\t0\t2\n", 
       bootUUID, bootFSType ?: @"ext4"];
    } else {
      [fstab appendFormat:@"%@\t/boot\t%@\tdefaults\t0\t2\n", 
       bootDevice, bootFSType ?: @"ext4"];
    }
  }
  
  // ESP if present
  if (espDevice) {
    NSString *espMount = @"/boot/efi";
    if (_environment.isRaspberryPi) {
      espMount = @"/boot/firmware";
    }
    
    if (espUUID) {
      [fstab appendFormat:@"UUID=%@\t%@\tvfat\tumask=0077\t0\t1\n", espUUID, espMount];
    } else {
      [fstab appendFormat:@"%@\t%@\tvfat\tumask=0077\t0\t1\n", espDevice, espMount];
    }
  }
  
  // Virtual filesystems
  [fstab appendString:@"\n# Virtual filesystems\n"];
  [fstab appendString:@"proc\t/proc\tproc\tdefaults\t0\t0\n"];
  [fstab appendString:@"sysfs\t/sys\tsysfs\tdefaults\t0\t0\n"];
  [fstab appendString:@"devtmpfs\t/dev\tdevtmpfs\tmode=0755,nosuid\t0\t0\n"];
  [fstab appendString:@"tmpfs\t/tmp\ttmpfs\tdefaults,nosuid,nodev\t0\t0\n"];
  
  // Write fstab
  NSString *fstabPath = [targetRoot stringByAppendingPathComponent:@"etc/fstab"];
  
  if (![fstab writeToFile:fstabPath 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:error]) {
    return NO;
  }
  
  return YES;
}

- (NSString *)uuidForDevice:(NSString *)device
{
  if (!device) return nil;
  
  NSString *output = [_detector runCommand:@"/sbin/blkid" 
                                 arguments:@[@"-s", @"UUID", @"-o", @"value", device]];
  return [output stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)partUUIDForDevice:(NSString *)device
{
  if (!device) return nil;
  
  NSString *output = [_detector runCommand:@"/sbin/blkid" 
                                 arguments:@[@"-s", @"PARTUUID", @"-o", @"value", device]];
  return [output stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - GRUB Installation

- (BOOL)installGrubBIOS:(NSString *)targetRoot
             targetDisk:(NSString *)disk
                  error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing GRUB for BIOS..."];
  }
  
  // Mount necessary filesystems for chroot
  if (![self mountChrootFilesystems:targetRoot error:error]) {
    return NO;
  }
  
  NSString *grubInstall = [_detector pathForTool:@"grub-install"];
  if (!grubInstall) {
    grubInstall = [_detector pathForTool:@"grub2-install"];
  }
  
  NSString *output = nil;
  BOOL success = [self runInChroot:targetRoot 
                           command:grubInstall 
                         arguments:@[@"--target=i386-pc", 
                                    @"--recheck",
                                    @"--force",
                                    disk]
                            output:&output 
                             error:error];
  
  [self unmountChrootFilesystems:targetRoot error:nil];
  
  if (!success) {
    if (error && !*error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 output ?: @"GRUB installation failed"}];
    }
    return NO;
  }
  
  return YES;
}

- (BOOL)installGrubUEFI:(NSString *)targetRoot
               espMount:(NSString *)espMount
                  error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing GRUB for UEFI..."];
  }
  
  if (![self mountChrootFilesystems:targetRoot error:error]) {
    return NO;
  }
  
  NSString *grubInstall = [_detector pathForTool:@"grub-install"];
  if (!grubInstall) {
    grubInstall = [_detector pathForTool:@"grub2-install"];
  }
  
  NSString *target = [self grubTargetPlatform];
  NSString *efiDir = espMount ?: @"/boot/efi";
  
  NSString *output = nil;
  BOOL success = [self runInChroot:targetRoot 
                           command:grubInstall 
                         arguments:@[[NSString stringWithFormat:@"--target=%@", target],
                                    @"--efi-directory", efiDir,
                                    @"--bootloader-id=gershwin",
                                    @"--recheck"]
                            output:&output 
                             error:error];
  
  [self unmountChrootFilesystems:targetRoot error:nil];
  
  if (!success) {
    if (error && !*error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 output ?: @"GRUB UEFI installation failed"}];
    }
    return NO;
  }
  
  return YES;
}

- (BOOL)generateGrubConfig:(NSString *)targetRoot
                     error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Generating GRUB configuration..."];
  }
  
  if (![self mountChrootFilesystems:targetRoot error:error]) {
    return NO;
  }
  
  NSString *grubMkconfig = [_detector pathForTool:@"grub-mkconfig"];
  if (!grubMkconfig) {
    grubMkconfig = [_detector pathForTool:@"grub2-mkconfig"];
  }
  
  NSString *output = nil;
  BOOL success = [self runInChroot:targetRoot 
                           command:grubMkconfig 
                         arguments:@[@"-o", @"/boot/grub/grub.cfg"]
                            output:&output 
                             error:error];
  
  if (!success) {
    // Try grub2 path
    success = [self runInChroot:targetRoot 
                        command:grubMkconfig 
                      arguments:@[@"-o", @"/boot/grub2/grub.cfg"]
                         output:&output 
                          error:error];
  }
  
  [self unmountChrootFilesystems:targetRoot error:nil];
  
  return success;
}

- (BOOL)updateGrubConfig:(NSString *)targetRoot
                   error:(NSError **)error
{
  return [self generateGrubConfig:targetRoot error:error];
}

- (NSString *)grubVersion
{
  NSString *output = [_detector runCommand:@"/usr/sbin/grub-install" 
                                 arguments:@[@"--version"]];
  if (!output) {
    output = [_detector runCommand:@"/usr/sbin/grub2-install" 
                         arguments:@[@"--version"]];
  }
  return [output stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

#pragma mark - systemd-boot Installation

- (BOOL)installSystemdBoot:(NSString *)espMount
                     error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing systemd-boot..."];
  }
  
  NSString *bootctl = [_detector pathForTool:@"bootctl"];
  
  NSTask *task = [[NSTask alloc] init];
  NSPipe *outputPipe = [NSPipe pipe];
  NSPipe *errorPipe = [NSPipe pipe];
  
  @try {
    [task setLaunchPath:bootctl];
    [task setArguments:@[@"install", @"--esp-path", espMount]];
    [task setStandardOutput:outputPipe];
    [task setStandardError:errorPipe];
    [task launch];
    [task waitUntilExit];
    
    if ([task terminationStatus] != 0) {
      NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
      NSString *errorStr = [[NSString alloc] initWithData:errorData 
                                                 encoding:NSUTF8StringEncoding];
      if (error) {
        *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                     code:[task terminationStatus] 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   errorStr ?: @"bootctl install failed"}];
      }
      [errorStr release];
      [task release];
      return NO;
    }
  } @catch (NSException *e) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:-1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [e reason] ?: @"bootctl failed"}];
    }
    [task release];
    return NO;
  }
  
  [task release];
  return YES;
}

- (BOOL)generateSystemdBootEntries:(NSString *)espMount
                        targetRoot:(NSString *)targetRoot
                          rootUUID:(NSString *)rootUUID
                             error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Creating boot entries..."];
  }
  
  // Create loader directory
  NSString *loaderDir = [espMount stringByAppendingPathComponent:@"loader"];
  NSString *entriesDir = [loaderDir stringByAppendingPathComponent:@"entries"];
  
  [_fm createDirectoryAtPath:entriesDir 
 withIntermediateDirectories:YES 
                  attributes:nil 
                       error:nil];
  
  // Find kernel version
  NSString *kernelVersion = nil;
  NSString *bootPath = [targetRoot stringByAppendingPathComponent:@"boot"];
  NSArray *bootContents = [_fm contentsOfDirectoryAtPath:bootPath error:nil];
  for (NSString *file in bootContents) {
    if ([file hasPrefix:@"vmlinuz-"]) {
      kernelVersion = [file substringFromIndex:8];
      break;
    }
  }
  
  if (!kernelVersion) {
    kernelVersion = @"linux";
  }
  
  // Create loader.conf
  NSString *loaderConf = @"default gershwin.conf\ntimeout 3\neditor yes\n";
  NSString *loaderConfPath = [loaderDir stringByAppendingPathComponent:@"loader.conf"];
  [loaderConf writeToFile:loaderConfPath 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:nil];
  
  // Create boot entry
  NSMutableString *entry = [NSMutableString string];
  [entry appendString:@"title   Gershwin Linux\n"];
  [entry appendString:@"linux   /vmlinuz-"];
  [entry appendString:kernelVersion];
  [entry appendString:@"\n"];
  [entry appendString:@"initrd  /initramfs-"];
  [entry appendString:kernelVersion];
  [entry appendString:@".img\n"];
  [entry appendFormat:@"options root=UUID=%@ rw quiet\n", rootUUID];
  
  NSString *entryPath = [entriesDir stringByAppendingPathComponent:@"gershwin.conf"];
  if (![entry writeToFile:entryPath 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:error]) {
    return NO;
  }
  
  // Copy kernel and initramfs to ESP if needed
  NSString *espKernel = [espMount stringByAppendingPathComponent:
    [NSString stringWithFormat:@"vmlinuz-%@", kernelVersion]];
  NSString *sourceKernel = [bootPath stringByAppendingPathComponent:
    [NSString stringWithFormat:@"vmlinuz-%@", kernelVersion]];
  
  if (![_fm fileExistsAtPath:espKernel] && [_fm fileExistsAtPath:sourceKernel]) {
    [_fm copyItemAtPath:sourceKernel toPath:espKernel error:nil];
  }
  
  NSString *espInitrd = [espMount stringByAppendingPathComponent:
    [NSString stringWithFormat:@"initramfs-%@.img", kernelVersion]];
  NSString *sourceInitrd = [bootPath stringByAppendingPathComponent:
    [NSString stringWithFormat:@"initramfs-%@.img", kernelVersion]];
  
  if (![_fm fileExistsAtPath:espInitrd] && [_fm fileExistsAtPath:sourceInitrd]) {
    [_fm copyItemAtPath:sourceInitrd toPath:espInitrd error:nil];
  }
  
  return YES;
}

#pragma mark - FreeBSD Bootcode Installation

- (BOOL)installFreeBSDMBRBootcode:(NSString *)disk
                            error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing FreeBSD MBR bootcode..."];
  }
  
  // Install boot0 to MBR
  NSString *output = [_detector runCommand:@"/sbin/boot0cfg" 
                                 arguments:@[@"-B", disk]];
  
  int status = [_detector runCommandStatus:@"/sbin/boot0cfg" 
                                 arguments:@[@"-B", disk]];
  
  if (status != 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:status 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 output ?: @"boot0cfg failed"}];
    }
    return NO;
  }
  
  return YES;
}

- (BOOL)installFreeBSDGPTBootcode:(NSString *)disk
                    bootPartition:(NSString *)bootPart
                            error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing FreeBSD GPT bootcode..."];
  }
  
  // Install protective MBR
  int status = [_detector runCommandStatus:@"/sbin/gpart" 
                                 arguments:@[@"bootcode", @"-b", @"/boot/pmbr", disk]];
  if (status != 0) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:status 
                               userInfo:@{NSLocalizedDescriptionKey: @"Failed to install pmbr"}];
    }
    return NO;
  }
  
  // Find boot partition if not specified
  if (!bootPart) {
    // Find freebsd-boot partition
    NSString *output = [_detector runCommand:@"/sbin/gpart" 
                                   arguments:@[@"show", @"-p", disk]];
    if (output) {
      NSArray *lines = [output componentsSeparatedByString:@"\n"];
      for (NSString *line in lines) {
        if ([line containsString:@"freebsd-boot"]) {
          NSArray *parts = [line componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
          for (NSString *part in parts) {
            if ([part hasPrefix:disk]) {
              bootPart = part;
              break;
            }
          }
        }
      }
    }
  }
  
  if (bootPart) {
    // Install gptboot to boot partition
    status = [_detector runCommandStatus:@"/sbin/gpart" 
                               arguments:@[@"bootcode", @"-p", @"/boot/gptboot", 
                                          @"-i", [bootPart lastPathComponent], disk]];
    if (status != 0) {
      if (error) {
        *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                     code:status 
                                 userInfo:@{NSLocalizedDescriptionKey: @"Failed to install gptboot"}];
      }
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)installFreeBSDUEFILoader:(NSString *)espMount
                           error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Installing FreeBSD UEFI loader..."];
  }
  
  // Create EFI directory structure
  NSString *efiBootDir = [espMount stringByAppendingPathComponent:@"EFI/BOOT"];
  NSString *efiFreeBSDDir = [espMount stringByAppendingPathComponent:@"EFI/FreeBSD"];
  
  [_fm createDirectoryAtPath:efiBootDir 
 withIntermediateDirectories:YES 
                  attributes:nil 
                       error:nil];
  [_fm createDirectoryAtPath:efiFreeBSDDir 
 withIntermediateDirectories:YES 
                  attributes:nil 
                       error:nil];
  
  // Copy loader.efi
  NSString *loaderSrc = @"/boot/loader.efi";
  NSString *loaderDst = [efiFreeBSDDir stringByAppendingPathComponent:@"loader.efi"];
  
  if (![_fm copyItemAtPath:loaderSrc toPath:loaderDst error:error]) {
    return NO;
  }
  
  // Also copy as default boot file
  NSString *arch = _environment.cpuArchitecture;
  NSString *bootName = @"BOOTX64.EFI";
  if ([arch isEqualToString:@"aarch64"] || [arch isEqualToString:@"arm64"]) {
    bootName = @"BOOTAA64.EFI";
  }
  
  NSString *defaultBoot = [efiBootDir stringByAppendingPathComponent:bootName];
  [_fm copyItemAtPath:loaderSrc toPath:defaultBoot error:nil];
  
  return YES;
}

- (BOOL)configureFreeBSDLoader:(NSString *)targetRoot
                         error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Configuring FreeBSD loader..."];
  }
  
  NSString *loaderConf = [targetRoot stringByAppendingPathComponent:@"boot/loader.conf"];
  
  NSMutableString *config = [NSMutableString string];
  [config appendString:@"# loader.conf - Generated by Bootable Installer\n\n"];
  [config appendString:@"autoboot_delay=\"3\"\n"];
  [config appendString:@"kern.geom.label.disk_ident.enable=\"0\"\n"];
  [config appendString:@"kern.geom.label.gptid.enable=\"0\"\n"];
  
  if (![config writeToFile:loaderConf 
                atomically:YES 
                  encoding:NSUTF8StringEncoding 
                     error:error]) {
    return NO;
  }
  
  return YES;
}

#pragma mark - Raspberry Pi Boot Configuration

- (BOOL)configureRPiBoot:(NSString *)bootMount
              targetRoot:(NSString *)targetRoot
                   error:(NSError **)error
{
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Configuring Raspberry Pi boot..."];
  }
  
  // Update config.txt
  if (![self updateRPiConfigTxt:bootMount targetRoot:targetRoot error:error]) {
    return NO;
  }
  
  // Update cmdline.txt
  NSString *rootDevice = [_detector deviceForMountPoint:targetRoot];
  NSString *rootUUID = [self uuidForDevice:rootDevice];
  
  if (![self updateRPiCmdlineTxt:bootMount rootUUID:rootUUID error:error]) {
    return NO;
  }
  
  // Copy kernel files if needed
  if (![self copyRPiKernelFiles:bootMount fromSource:targetRoot error:error]) {
    return NO;
  }
  
  return YES;
}

- (BOOL)updateRPiConfigTxt:(NSString *)bootMount
                targetRoot:(NSString *)targetRoot
                     error:(NSError **)error
{
  NSString *configPath = [bootMount stringByAppendingPathComponent:@"config.txt"];
  
  NSMutableString *config = [NSMutableString string];
  
  // Read existing config if present
  NSString *existing = [NSString stringWithContentsOfFile:configPath 
                                                 encoding:NSUTF8StringEncoding 
                                                    error:nil];
  if (existing) {
    [config appendString:existing];
    if (![config hasSuffix:@"\n"]) {
      [config appendString:@"\n"];
    }
  }
  
  // Add our configuration
  if (![config containsString:@"[pi4]"]) {
    [config appendString:@"\n# Gershwin configuration\n"];
    [config appendString:@"[pi4]\n"];
    [config appendString:@"kernel=vmlinuz\n"];
    [config appendString:@"initramfs initrd.img followkernel\n"];
  }
  
  if (![config containsString:@"[all]"]) {
    [config appendString:@"\n[all]\n"];
    [config appendString:@"arm_64bit=1\n"];
  }
  
  if (![config writeToFile:configPath 
                atomically:YES 
                  encoding:NSUTF8StringEncoding 
                     error:error]) {
    return NO;
  }
  
  return YES;
}

- (BOOL)updateRPiCmdlineTxt:(NSString *)bootMount
                   rootUUID:(NSString *)rootUUID
                      error:(NSError **)error
{
  NSString *cmdlinePath = [bootMount stringByAppendingPathComponent:@"cmdline.txt"];
  
  NSMutableString *cmdline = [NSMutableString string];
  [cmdline appendString:@"console=serial0,115200 console=tty1 "];
  
  if (rootUUID) {
    [cmdline appendFormat:@"root=UUID=%@ ", rootUUID];
  } else {
    [cmdline appendString:@"root=/dev/mmcblk0p2 "];
  }
  
  [cmdline appendString:@"rootfstype=ext4 fsck.repair=yes rootwait quiet"];
  
  if (![cmdline writeToFile:cmdlinePath 
                 atomically:YES 
                   encoding:NSUTF8StringEncoding 
                      error:error]) {
    return NO;
  }
  
  return YES;
}

- (BOOL)copyRPiKernelFiles:(NSString *)bootMount
                fromSource:(NSString *)sourceRoot
                     error:(NSError **)error
{
  // Copy kernel
  NSString *sourceKernel = [sourceRoot stringByAppendingPathComponent:@"boot/vmlinuz"];
  NSString *destKernel = [bootMount stringByAppendingPathComponent:@"vmlinuz"];
  
  if ([_fm fileExistsAtPath:sourceKernel] && ![_fm fileExistsAtPath:destKernel]) {
    if (![_fm copyItemAtPath:sourceKernel toPath:destKernel error:error]) {
      return NO;
    }
  }
  
  // Copy initramfs
  NSString *sourceInitrd = [sourceRoot stringByAppendingPathComponent:@"boot/initrd.img"];
  NSString *destInitrd = [bootMount stringByAppendingPathComponent:@"initrd.img"];
  
  if ([_fm fileExistsAtPath:sourceInitrd] && ![_fm fileExistsAtPath:destInitrd]) {
    if (![_fm copyItemAtPath:sourceInitrd toPath:destInitrd error:error]) {
      return NO;
    }
  }
  
  // Copy DTB files
  NSString *sourceDtb = [sourceRoot stringByAppendingPathComponent:@"boot/dtbs"];
  NSString *destDtb = [bootMount stringByAppendingPathComponent:@"dtbs"];
  
  if ([_fm fileExistsAtPath:sourceDtb] && ![_fm fileExistsAtPath:destDtb]) {
    [_fm copyItemAtPath:sourceDtb toPath:destDtb error:nil];
  }
  
  return YES;
}

#pragma mark - Initramfs Generation

- (BOOL)regenerateInitramfs:(NSString *)targetRoot
                      error:(NSError **)error
{
  if (_environment.osType != SourceOSTypeLinux) {
    return YES;  // Not applicable
  }
  
  if (_delegate && [_delegate respondsToSelector:@selector(installer:statusMessage:)]) {
    [_delegate installer:self statusMessage:@"Regenerating initramfs..."];
  }
  
  NSString *tool = [self detectInitramfsTool:targetRoot];
  if (!tool) {
    // No initramfs tool found - this is OK, might be using a generic initramfs
    return YES;
  }
  
  if (![self mountChrootFilesystems:targetRoot error:error]) {
    return NO;
  }
  
  NSString *output = nil;
  BOOL success = NO;
  
  if ([tool isEqualToString:@"update-initramfs"]) {
    success = [self runInChroot:targetRoot 
                        command:@"/usr/sbin/update-initramfs" 
                      arguments:@[@"-u", @"-k", @"all"]
                         output:&output 
                          error:error];
  } else if ([tool isEqualToString:@"dracut"]) {
    success = [self runInChroot:targetRoot 
                        command:@"/usr/bin/dracut" 
                      arguments:@[@"--force", @"--regenerate-all"]
                         output:&output 
                          error:error];
  } else if ([tool isEqualToString:@"mkinitcpio"]) {
    success = [self runInChroot:targetRoot 
                        command:@"/usr/bin/mkinitcpio" 
                      arguments:@[@"-P"]
                         output:&output 
                          error:error];
  }
  
  [self unmountChrootFilesystems:targetRoot error:nil];
  
  return success;
}

- (NSString *)detectInitramfsTool:(NSString *)targetRoot
{
  // Check for various initramfs tools
  if ([_fm fileExistsAtPath:[targetRoot stringByAppendingPathComponent:
        @"usr/sbin/update-initramfs"]]) {
    return @"update-initramfs";
  }
  if ([_fm fileExistsAtPath:[targetRoot stringByAppendingPathComponent:
        @"usr/bin/dracut"]]) {
    return @"dracut";
  }
  if ([_fm fileExistsAtPath:[targetRoot stringByAppendingPathComponent:
        @"usr/bin/mkinitcpio"]]) {
    return @"mkinitcpio";
  }
  
  return nil;
}

#pragma mark - Verification

- (BOOL)verifyBootloaderInstallation:(NSString *)targetRoot
                              reason:(NSString **)reason
{
  switch (_preferredBootloader) {
    case BootloaderTypeGRUB2:
      return [self verifyGrubInstallation:targetRoot espPath:_targetESPPath reason:reason];
      
    case BootloaderTypeSystemdBoot:
      // Check for boot entries
      if (_targetESPPath) {
        NSString *entriesDir = [_targetESPPath 
                                 stringByAppendingPathComponent:@"loader/entries"];
        BOOL isDir = NO;
        if (![_fm fileExistsAtPath:entriesDir isDirectory:&isDir] || !isDir) {
          if (reason) *reason = @"systemd-boot entries directory not found";
          return NO;
        }
      }
      return YES;
      
    case BootloaderTypeFreeBSDLoader:
      return [self verifyFreeBSDBootcode:_targetDisk reason:reason];
      
    case BootloaderTypeRPiFirmware:
      // Check for essential files
      if (_targetBootPath) {
        if (![_fm fileExistsAtPath:[_targetBootPath 
              stringByAppendingPathComponent:@"config.txt"]]) {
          if (reason) *reason = @"config.txt not found on boot partition";
          return NO;
        }
      }
      return YES;
      
    default:
      if (reason) *reason = @"Unknown bootloader type";
      return NO;
  }
}

- (BOOL)verifyGrubInstallation:(NSString *)targetRoot
                       espPath:(NSString *)espPath
                        reason:(NSString **)reason
{
  // Check for grub.cfg
  NSString *grubCfg = [targetRoot stringByAppendingPathComponent:@"boot/grub/grub.cfg"];
  if (![_fm fileExistsAtPath:grubCfg]) {
    grubCfg = [targetRoot stringByAppendingPathComponent:@"boot/grub2/grub.cfg"];
    if (![_fm fileExistsAtPath:grubCfg]) {
      if (reason) *reason = @"GRUB configuration file not found";
      return NO;
    }
  }
  
  // Check for EFI bootloader if UEFI
  if (_environment.firmwareType == BootFirmwareTypeUEFI && espPath) {
    NSString *efiFile = [espPath stringByAppendingPathComponent:@"EFI/gershwin/grubx64.efi"];
    if (![_fm fileExistsAtPath:efiFile]) {
      efiFile = [espPath stringByAppendingPathComponent:@"EFI/gershwin/grubaa64.efi"];
      if (![_fm fileExistsAtPath:efiFile]) {
        if (reason) *reason = @"GRUB EFI bootloader not found";
        return NO;
      }
    }
  }
  
  return YES;
}

- (BOOL)verifyFreeBSDBootcode:(NSString *)disk
                       reason:(NSString **)reason
{
  // Verify bootcode is installed
  int status = [_detector runCommandStatus:@"/sbin/gpart" 
                                 arguments:@[@"show", disk]];
  if (status != 0) {
    if (reason) *reason = @"Cannot verify FreeBSD bootcode";
    return NO;
  }
  
  return YES;
}

#pragma mark - Utility Methods

- (BOOL)runInChroot:(NSString *)chrootPath
            command:(NSString *)command
          arguments:(NSArray *)args
             output:(NSString **)output
              error:(NSError **)error
{
  // Build chroot command: chroot <path> <command> [args...]
  NSMutableArray *fullArgs = [NSMutableArray arrayWithObjects:
    @"/usr/sbin/chroot", chrootPath, command, nil];
  if (args) {
    [fullArgs addObjectsFromArray:args];
  }
  
  // Use privileged execution via delegate if available
  if (_delegate && 
      [_delegate respondsToSelector:@selector(installer:runPrivilegedCommand:output:error:)]) {
    NSString *errorStr = nil;
    BOOL success = [_delegate installer:self 
                   runPrivilegedCommand:fullArgs 
                                 output:output 
                                  error:&errorStr];
    
    if (!success && error && !*error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 errorStr ?: @"chroot command failed"}];
    }
    return success;
  }
  
  // Fallback: run directly (will fail if root required)
  NSTask *task = [[NSTask alloc] init];
  NSPipe *outputPipe = [NSPipe pipe];
  NSPipe *errorPipe = [NSPipe pipe];
  
  @try {
    [task setLaunchPath:@"/usr/sbin/chroot"];
    [task setArguments:[fullArgs subarrayWithRange:NSMakeRange(1, [fullArgs count] - 1)]];
    [task setStandardOutput:outputPipe];
    [task setStandardError:errorPipe];
    [task launch];
    [task waitUntilExit];
    
    NSData *outputData = [[outputPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errorData = [[errorPipe fileHandleForReading] readDataToEndOfFile];
    
    NSString *outputStr = [[NSString alloc] initWithData:outputData 
                                                encoding:NSUTF8StringEncoding];
    NSString *errorStr = [[NSString alloc] initWithData:errorData 
                                               encoding:NSUTF8StringEncoding];
    
    if (output) {
      *output = [[outputStr stringByAppendingString:errorStr] retain];
    }
    
    [outputStr release];
    [errorStr release];
    
    if ([task terminationStatus] != 0) {
      if (error && !*error) {
        *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                     code:[task terminationStatus] 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   [NSString stringWithFormat:@"chroot command failed with status %d", 
                                    [task terminationStatus]]}];
      }
      [task release];
      return NO;
    }
  } @catch (NSException *e) {
    if (error) {
      *error = [NSError errorWithDomain:@"BootloaderInstaller" 
                                   code:-1 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [e reason] ?: @"chroot failed"}];
    }
    [task release];
    return NO;
  }
  
  [task release];
  return YES;
}

- (BOOL)mountChrootFilesystems:(NSString *)chrootPath
                         error:(NSError **)error
{
  // Mount proc
  NSString *procPath = [chrootPath stringByAppendingPathComponent:@"proc"];
  [self runPrivilegedCommand:@"/bin/mount" 
                   arguments:@[@"-t", @"proc", @"proc", procPath]
                      output:nil error:nil];
  
  // Mount sys
  NSString *sysPath = [chrootPath stringByAppendingPathComponent:@"sys"];
  [self runPrivilegedCommand:@"/bin/mount" 
                   arguments:@[@"--rbind", @"/sys", sysPath]
                      output:nil error:nil];
  
  // Mount dev
  NSString *devPath = [chrootPath stringByAppendingPathComponent:@"dev"];
  [self runPrivilegedCommand:@"/bin/mount" 
                   arguments:@[@"--rbind", @"/dev", devPath]
                      output:nil error:nil];
  
  // Mount dev/pts
  NSString *ptsPath = [chrootPath stringByAppendingPathComponent:@"dev/pts"];
  [self runPrivilegedCommand:@"/bin/mount" 
                   arguments:@[@"-t", @"devpts", @"devpts", ptsPath]
                      output:nil error:nil];
  
  // Mount run
  NSString *runPath = [chrootPath stringByAppendingPathComponent:@"run"];
  [self runPrivilegedCommand:@"/bin/mount" 
                   arguments:@[@"--rbind", @"/run", runPath]
                      output:nil error:nil];
  
  return YES;
}

- (BOOL)unmountChrootFilesystems:(NSString *)chrootPath
                           error:(NSError **)error
{
  // Unmount in reverse order
  NSArray *mounts = @[@"dev/pts", @"dev", @"sys", @"proc", @"run"];
  
  for (NSString *mount in mounts) {
    NSString *path = [chrootPath stringByAppendingPathComponent:mount];
    [self runPrivilegedCommand:@"/bin/umount" 
                     arguments:@[@"-l", path]  // Lazy unmount
                        output:nil error:nil];
  }
  
  return YES;
}

- (NSString *)grubTargetPlatform
{
  NSString *arch = _environment.cpuArchitecture;
  
  if ([arch isEqualToString:@"x86_64"] || [arch isEqualToString:@"amd64"]) {
    return @"x86_64-efi";
  }
  if ([arch isEqualToString:@"aarch64"] || [arch isEqualToString:@"arm64"]) {
    return @"arm64-efi";
  }
  if ([arch isEqualToString:@"i686"] || [arch isEqualToString:@"i386"]) {
    return @"i386-efi";
  }
  
  return @"x86_64-efi";  // Default
}

@end
