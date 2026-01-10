/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BOOTLOADER_INSTALLER_H
#define BOOTLOADER_INSTALLER_H

#import <Foundation/Foundation.h>
#import "BootEnvironmentDetector.h"

@class BootloaderInstaller;

/**
 * Bootloader type
 */
typedef NS_ENUM(NSInteger, BootloaderType) {
  BootloaderTypeNone = 0,
  BootloaderTypeGRUB2,         // Linux GRUB2 (BIOS and UEFI)
  BootloaderTypeSystemdBoot,   // systemd-boot (UEFI only)
  BootloaderTypeFreeBSDLoader, // FreeBSD loader (BIOS and UEFI)
  BootloaderTypeRPiFirmware,   // Raspberry Pi boot firmware
  BootloaderTypeSyslinux,      // Syslinux (BIOS only)
  BootloaderTypeRefind         // rEFInd (UEFI only)
};

/**
 * Bootloader installation result
 */
@interface BootloaderInstallResult : NSObject
{
  BOOL _success;
  NSString *_errorMessage;
  BootloaderType _installedType;
  NSString *_bootloaderVersion;
  NSArray *_installedFiles;
  NSArray *_generatedConfigs;
}

@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BootloaderType installedType;
@property (nonatomic, copy) NSString *bootloaderVersion;
@property (nonatomic, copy) NSArray *installedFiles;
@property (nonatomic, copy) NSArray *generatedConfigs;

+ (instancetype)successWithType:(BootloaderType)type version:(NSString *)version;
+ (instancetype)failureWithError:(NSString *)error;

@end


/**
 * Delegate protocol for bootloader installation progress
 */
@protocol BootloaderInstallerDelegate <NSObject>

@optional
/**
 * Called when starting a bootloader installation phase
 */
- (void)installer:(BootloaderInstaller *)installer 
    didStartPhase:(NSString *)phaseName;

/**
 * Called when a phase completes
 */
- (void)installer:(BootloaderInstaller *)installer 
   didCompletePhase:(NSString *)phaseName 
            success:(BOOL)success;

/**
 * Called for status messages
 */
- (void)installer:(BootloaderInstaller *)installer 
    statusMessage:(NSString *)message;

/**
 * Called on error, allows abort/continue decision
 */
- (BOOL)installer:(BootloaderInstaller *)installer 
    shouldContinueAfterError:(NSString *)error;

/**
 * Called to run a command with root privileges (via sudo -A -E)
 * @param arguments Full command with arguments (first element is the command path)
 * @param output Receives stdout on success
 * @param error Receives stderr on failure
 * @return YES if command succeeded (exit code 0)
 */
- (BOOL)installer:(BootloaderInstaller *)installer 
runPrivilegedCommand:(NSArray *)arguments 
             output:(NSString **)output 
              error:(NSString **)error;

@end


/**
 * BootloaderInstaller handles installation and configuration of bootloaders
 * for various platforms and firmware types.
 *
 * Supported configurations:
 * - Linux + BIOS + GRUB2
 * - Linux + UEFI + GRUB2
 * - Linux + UEFI + systemd-boot
 * - FreeBSD + BIOS + MBR bootcode
 * - FreeBSD + BIOS + GPT gptboot
 * - FreeBSD + UEFI + loader.efi
 * - Raspberry Pi boot partition
 */
@interface BootloaderInstaller : NSObject
{
  NSFileManager *_fm;
  BootEnvironmentDetector *_detector;
  BootEnvironmentInfo *_environment;
  id<BootloaderInstallerDelegate> _delegate;
  
  NSString *_targetRootPath;
  NSString *_targetBootPath;
  NSString *_targetESPPath;
  NSString *_targetDisk;
  
  BootloaderType _preferredBootloader;
}

@property (nonatomic, assign) id<BootloaderInstallerDelegate> delegate;
@property (nonatomic, assign) BootloaderType preferredBootloader;
@property (nonatomic, copy) NSString *targetRootPath;
@property (nonatomic, copy) NSString *targetBootPath;
@property (nonatomic, copy) NSString *targetESPPath;
@property (nonatomic, copy) NSString *targetDisk;

#pragma mark - Initialization

/**
 * Create installer for detected environment
 */
+ (instancetype)installerForEnvironment:(BootEnvironmentInfo *)env;

- (instancetype)initWithEnvironment:(BootEnvironmentInfo *)env;

#pragma mark - Main Installation

/**
 * Perform full bootloader installation for the target system
 * This is the main entry point.
 *
 * @param targetRoot Mount point of target root filesystem
 * @param targetBoot Mount point of target boot partition (or nil if same as root)
 * @param targetESP Mount point of EFI System Partition (or nil if BIOS)
 * @param targetDisk Target disk device (e.g., /dev/sda)
 * @return Result object with success/failure
 */
- (BootloaderInstallResult *)installBootloaderToRoot:(NSString *)targetRoot
                                          bootMount:(NSString *)targetBoot
                                           espMount:(NSString *)targetESP
                                         targetDisk:(NSString *)targetDisk;

/**
 * Auto-detect and install appropriate bootloader
 */
- (BootloaderInstallResult *)autoInstallBootloader;

#pragma mark - Pre-Installation Checks

/**
 * Check if required bootloader tools are available
 */
- (BOOL)bootloaderToolsAvailable:(BootloaderType)type reason:(NSString **)reason;

/**
 * Verify target layout is suitable for bootloader installation
 */
- (BOOL)verifyTargetLayout:(NSString **)reason;

/**
 * Verify kernel and initramfs exist on source/target
 */
- (BOOL)verifyKernelExists:(NSString **)reason;

#pragma mark - Fstab Generation

/**
 * Generate fstab for target system
 *
 * @param targetRoot Target root mount point  
 * @param rootDevice Root partition device (e.g., /dev/sda2)
 * @param rootUUID UUID of root partition (preferred over device)
 * @param fsType Filesystem type (ext4, xfs, etc.)
 * @param bootDevice Boot partition device (or nil)
 * @param bootUUID Boot partition UUID (or nil)
 * @param espDevice ESP device (or nil)
 * @param espUUID ESP UUID (or nil)
 * @return YES on success
 */
- (BOOL)generateFstabAtPath:(NSString *)targetRoot
                 rootDevice:(NSString *)rootDevice
                   rootUUID:(NSString *)rootUUID
                 rootFSType:(NSString *)fsType
                 bootDevice:(NSString *)bootDevice
                   bootUUID:(NSString *)bootUUID
                  espDevice:(NSString *)espDevice
                    espUUID:(NSString *)espUUID
                      error:(NSError **)error;

/**
 * Get UUID for a device
 */
- (NSString *)uuidForDevice:(NSString *)device;

/**
 * Get PARTUUID for a device
 */
- (NSString *)partUUIDForDevice:(NSString *)device;

#pragma mark - GRUB Installation (Linux)

/**
 * Install GRUB2 for BIOS systems
 */
- (BOOL)installGrubBIOS:(NSString *)targetRoot
             targetDisk:(NSString *)disk
                  error:(NSError **)error;

/**
 * Install GRUB2 for UEFI systems
 */
- (BOOL)installGrubUEFI:(NSString *)targetRoot
               espMount:(NSString *)espMount
                  error:(NSError **)error;

/**
 * Generate GRUB configuration
 */
- (BOOL)generateGrubConfig:(NSString *)targetRoot
                     error:(NSError **)error;

/**
 * Update GRUB configuration in target
 */
- (BOOL)updateGrubConfig:(NSString *)targetRoot
                   error:(NSError **)error;

#pragma mark - systemd-boot Installation (Linux UEFI)

/**
 * Install systemd-boot
 */
- (BOOL)installSystemdBoot:(NSString *)espMount
                     error:(NSError **)error;

/**
 * Generate systemd-boot entries
 */
- (BOOL)generateSystemdBootEntries:(NSString *)espMount
                        targetRoot:(NSString *)targetRoot
                          rootUUID:(NSString *)rootUUID
                             error:(NSError **)error;

#pragma mark - FreeBSD Bootcode Installation

/**
 * Install FreeBSD MBR bootcode
 */
- (BOOL)installFreeBSDMBRBootcode:(NSString *)disk
                            error:(NSError **)error;

/**
 * Install FreeBSD GPT bootcode (pmbr + gptboot)
 */
- (BOOL)installFreeBSDGPTBootcode:(NSString *)disk
                    bootPartition:(NSString *)bootPart
                            error:(NSError **)error;

/**
 * Install FreeBSD UEFI loader
 */
- (BOOL)installFreeBSDUEFILoader:(NSString *)espMount
                           error:(NSError **)error;

/**
 * Configure FreeBSD loader.conf
 */
- (BOOL)configureFreeBSDLoader:(NSString *)targetRoot
                         error:(NSError **)error;

#pragma mark - Raspberry Pi Boot Configuration

/**
 * Configure Raspberry Pi boot partition
 */
- (BOOL)configureRPiBoot:(NSString *)bootMount
              targetRoot:(NSString *)targetRoot
                   error:(NSError **)error;

/**
 * Update config.txt for Raspberry Pi
 */
- (BOOL)updateRPiConfigTxt:(NSString *)bootMount
                targetRoot:(NSString *)targetRoot
                     error:(NSError **)error;

/**
 * Update cmdline.txt for Raspberry Pi (Linux)
 */
- (BOOL)updateRPiCmdlineTxt:(NSString *)bootMount
                   rootUUID:(NSString *)rootUUID
                      error:(NSError **)error;

/**
 * Copy kernel and initramfs to Raspberry Pi boot partition
 */
- (BOOL)copyRPiKernelFiles:(NSString *)bootMount
                fromSource:(NSString *)sourceRoot
                     error:(NSError **)error;

#pragma mark - Initramfs Generation

/**
 * Regenerate initramfs on target (Linux only)
 * Detects and uses: update-initramfs, dracut, or mkinitcpio
 */
- (BOOL)regenerateInitramfs:(NSString *)targetRoot
                      error:(NSError **)error;

/**
 * Detect initramfs tool available in target
 */
- (NSString *)detectInitramfsTool:(NSString *)targetRoot;

#pragma mark - Verification

/**
 * Verify bootloader was installed correctly
 */
- (BOOL)verifyBootloaderInstallation:(NSString *)targetRoot
                              reason:(NSString **)reason;

/**
 * Verify GRUB installation
 */
- (BOOL)verifyGrubInstallation:(NSString *)targetRoot
                       espPath:(NSString *)espPath
                        reason:(NSString **)reason;

/**
 * Verify FreeBSD bootcode
 */
- (BOOL)verifyFreeBSDBootcode:(NSString *)disk
                       reason:(NSString **)reason;

#pragma mark - Utility Methods

/**
 * Run a command in a chroot environment
 */
- (BOOL)runInChroot:(NSString *)chrootPath
            command:(NSString *)command
          arguments:(NSArray *)args
             output:(NSString **)output
              error:(NSError **)error;

/**
 * Mount virtual filesystems for chroot (proc, sys, dev, etc.)
 */
- (BOOL)mountChrootFilesystems:(NSString *)chrootPath
                         error:(NSError **)error;

/**
 * Unmount virtual filesystems from chroot
 */
- (BOOL)unmountChrootFilesystems:(NSString *)chrootPath
                           error:(NSError **)error;

/**
 * Get GRUB target platform string
 */
- (NSString *)grubTargetPlatform;

@end

#endif /* BOOTLOADER_INSTALLER_H */
