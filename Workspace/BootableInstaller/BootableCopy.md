# Bootable OS Installation Architecture

## Overview

This module provides the capability to create a bootable OS installation by dragging the root volume icon of the running system onto another suitable partition. The architecture follows GNUstep and Workspace patterns with clean separation of concerns.

## Warning

⚠️ **EXPERIMENTAL FEATURE** ⚠️

This feature is experimental and may result in data loss. Use with extreme caution.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     GWDesktopView                               │
│  (Drag-and-Drop Entry Point)                                    │
│  - Detects drag of root volume onto partition icon              │
│  - Calls BootPartitionValidator for quick validation            │
│  - Delegates to BootableInstallController on drop               │
└─────────────────────────┬───────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                 BootableInstallController                        │
│  (Main Orchestrator)                                             │
│  - Manages UI flow and user confirmations                        │
│  - Shows warning dialog with Cancel as default                   │
│  - Asks about /home exclusion                                    │
│  - Coordinates validation → copy → bootloader sequence           │
│  - Handles errors and cleanup                                    │
└────────┬────────────────┬────────────────┬──────────────────────┘
         │                │                │
         ▼                ▼                ▼
┌─────────────────┐ ┌──────────────────┐ ┌─────────────────────────┐
│BootPartition    │ │BootEnvironment   │ │BootableFileCopier       │
│Validator        │ │Detector          │ │                         │
│                 │ │                  │ │- Recursive copy with    │
│- 30+ validation │ │- OS detection    │ │  progress indicator     │
│  checks         │ │- CPU arch        │ │- Preserves permissions, │
│- Non-destructive│ │- Firmware type   │ │  ACLs, xattrs           │
│- Fast checks    │ │- Raspberry Pi    │ │- Hardlink/symlink       │
│  using statvfs  │ │- Partition scheme│ │  preservation           │
│                 │ │                  │ │- Exclusion support      │
└─────────────────┘ └──────────────────┘ └─────────────────────────┘
                                                     │
                                                     ▼
                          ┌─────────────────────────────────────────┐
                          │          BootloaderInstaller            │
                          │                                         │
                          │- GRUB installation (Linux BIOS/UEFI)    │
                          │- systemd-boot (UEFI)                    │
                          │- FreeBSD bootcode (MBR/GPT)             │
                          │- Raspberry Pi boot partition setup      │
                          │- fstab generation                       │
                          │- initramfs regeneration                 │
                          └─────────────────────────────────────────┘
```

## Class Responsibilities

### 1. BootPartitionValidator

**Purpose**: Validate target partition for bootable installation.

**Key Methods**:
- `-validateTargetNode:forSourceNode:` - Full validation with all 30+ checks
- `-canAcceptDragForTarget:source:` - Quick check for drag hover feedback

**Validation Checks** (all non-destructive, fast, reversible):
1. Target is a real block device partition
2. Target is not the current root filesystem
3. Target device is not read-only at block layer
4. Target is not mounted or can be safely remounted
5. Target has sufficient size for source rootfs
6. Target filesystem type is supported
7. Filesystem supports POSIX permissions, symlinks, device nodes
8. Filesystem is not corrupted (quick check)
9. Partition label/UUID is readable
10. Not marked as swap
11. Not encrypted or encryption is unlocked
12. Not part of active RAID/LVM
13. Uses supported partition scheme (GPT/MBR/BSD)
14. Sufficient free space with overhead (using statvfs)
15. Allows setting ownership and xattrs
16. Firmware can boot from target disk
17-18. UEFI-specific: ESP exists and is FAT formatted
18-19. Raspberry Pi: Boot partition exists and is FAT
20. Boot partition is accessible from target root
21. Bootloader is available in running system
22. Target disk is not non-bootable removable media
23. Source OS is compatible with target architecture
24. Source OS supports live copy
25. Kernel/initramfs are suitable for target
26. Filesystem supported by bootloader
27. FreeBSD-specific bootcode checks
28. User has sufficient privileges (root)
29. Target not protected by policy
30. Target not experiencing I/O errors
31. Target disk is not source disk

### 2. BootEnvironmentDetector

**Purpose**: Detect the running system's boot environment characteristics.

**Detection Capabilities**:
- Operating System: Linux, FreeBSD, NetBSD, OpenBSD, DragonFly BSD
- CPU Architecture: x86_64, aarch64, armv7l, i686, riscv64, etc.
- Firmware Type: BIOS, UEFI, Raspberry Pi firmware
- Raspberry Pi detection via `/proc/device-tree`, SoC model, FreeBSD FDT
- Partition scheme: GPT, MBR, BSD disklabel

**Key Methods**:
- `-detectRunningOS`
- `-detectCPUArchitecture`
- `-detectBootFirmware`
- `-detectRaspberryPi`
- `-partitionSchemeForDisk:`

### 3. BootableFileCopier

**Purpose**: Perform the actual filesystem copy with proper preservation of all attributes.

**Features**:
- Recursive directory copy with progress indicator
- Preserves: ownership, permissions, ACLs, xattrs, timestamps
- Handles hardlinks and symlinks correctly
- Excludes virtual/runtime directories: `/proc`, `/sys`, `/dev`, `/run`, `/tmp`
- Optional `/home` exclusion
- Verification of copy completion
- Progress reporting via delegate

**Key Methods**:
- `-copyRootFilesystemToTarget:excludingHome:delegate:`
- `-verifyTargetIntegrity:`

**Exclusion Lists**:
```
Always excluded:
  /proc, /sys, /dev, /run, /tmp, /var/run, /var/lock, /var/tmp
  /mnt, /media, /lost+found

Optional:
  /home (user choice)
```

### 4. BootloaderInstaller

**Purpose**: Install and configure bootloader for the target system.

**Supported Bootloaders**:
- **Linux BIOS**: GRUB2 (MBR)
- **Linux UEFI**: GRUB2 (ESP), systemd-boot
- **FreeBSD BIOS**: gptboot, boot0
- **FreeBSD UEFI**: loader.efi
- **Raspberry Pi**: config.txt, kernel, DTB files

**Key Methods**:
- `-installBootloaderForEnvironment:toTarget:`
- `-generateFstab:forTarget:`
- `-regenerateInitramfs:` (Linux only)
- `-installGrubToTarget:`
- `-installFreeBSDBootcode:`
- `-configureRaspberryPiBoot:`

### 5. BootableInstallController

**Purpose**: Main orchestrator managing UI flow and coordination.

**UI Flow**:
1. Receive drop event from GWDesktopView
2. Show experimental warning dialog (Cancel = default, "Continue at Own Risk")
3. Ask about /home exclusion
4. Show progress window
5. Handle errors with NSAlert
6. Report success/failure

**State Machine**:
```
IDLE → VALIDATING → CONFIRMING → COPYING → CONFIGURING → BOOTLOADER → VERIFYING → DONE
                                     ↓
                                  ERROR → CLEANUP → IDLE
```

**Key Methods**:
- `-performInstallFromSource:toTarget:`
- `-showExperimentalWarning:` (returns BOOL)
- `-askExcludeHome:` (returns BOOL)
- `-showProgressWindow`
- `-handleError:` (shows alert, cleanup)
- `-completeInstallation`

## Drag-and-Drop Integration

### Detection Logic (in GWDesktopView)

```objc
// In draggingEntered: / draggingUpdated:
if ([self isDragOfRootVolume:sender] && [self isTargetPartition:targetIcon]) {
    BootPartitionValidator *validator = [BootPartitionValidator sharedValidator];
    if ([validator canAcceptDragForTarget:targetNode source:sourceNode]) {
        return NSDragOperationCopy;  // Visual feedback: drag accepted
    }
    return NSDragOperationNone;  // Visual feedback: drag refused
}

// In performDragOperation:
if ([self isDragOfRootVolume:sender] && [self isTargetPartition:targetIcon]) {
    BootPartitionValidationResult *result = 
        [validator validateTargetNode:targetNode forSourceNode:sourceNode];
    if (result.valid) {
        [[BootableInstallController sharedController] 
            performInstallFromSource:sourceNode toTarget:targetNode];
    } else {
        [self showValidationFailure:result.failureReason];
    }
}
```

## Installation Sequence

1. **Privilege Check**: Verify running as root
2. **Environment Detection**: Detect OS, firmware, architecture
3. **Validation**: Run all 30+ checks
4. **User Confirmation**: Show warning dialog
5. **Home Exclusion Choice**: Ask user preference
6. **Mount Target**: Mount target partition R/W
7. **Mount Additional**: Mount ESP, boot partition as needed
8. **Create Layout**: Create required directory structure
9. **Check Existing**: Handle existing installation (overwrite/merge)
10. **Copy Filesystem**: Recursive copy with progress
11. **Verify Copy**: Confirm successful copy
12. **Configure fstab**: Adjust for new partition UUIDs
13. **Update Configs**: OS-specific configuration files
14. **Regenerate Initramfs**: Linux only, if required
15. **Generate Bootloader Config**: GRUB menu, loader.conf, etc.
16. **Install Bootloader**: Write to disk/ESP/boot partition
17. **Verify Bootloader**: Confirm installation succeeded
18. **Sync Buffers**: Ensure all data written
19. **Unmount**: Clean unmount of all filesystems
20. **Final Checks**: Verify target layout
21. **Log Results**: Record success/failure
22. **Report Status**: Show result to user

## Error Handling

All errors stop the current operation immediately and:
1. Close any progress windows
2. Show NSAlert with error message
3. Attempt cleanup (unmount, restore state)
4. Log detailed error information
5. Return to idle state

## File Layout

```
Workspace/BootableInstaller/
├── BootableCopy.md              # This architecture document
├── BootPartitionValidator.h     # Validation interface
├── BootPartitionValidator.m     # Validation implementation
├── BootEnvironmentDetector.h    # Environment detection interface
├── BootEnvironmentDetector.m    # Environment detection implementation
├── BootableFileCopier.h         # File copy interface
├── BootableFileCopier.m         # File copy implementation
├── BootloaderInstaller.h        # Bootloader interface
├── BootloaderInstaller.m        # Bootloader implementation
├── BootableInstallController.h  # Controller interface
└── BootableInstallController.m  # Controller implementation
```

## Dependencies

- NSFileManager (file operations)
- NSTask (external commands: mount, grub-install, etc.)
- statvfs (fast space checking)
- udev/devfs (device information on Linux/BSD)

## Security Considerations

1. Must run as root for privileged operations
2. All validation before any destructive action
3. No automatic operations on encrypted volumes
4. Protected paths (system EFI, other OS partitions) are refused
5. Explicit user confirmation with "Continue at Own Risk"

## Platform-Specific Notes

### Linux
- Uses `/proc/filesystems` for supported FS types
- Uses `/sys/firmware/efi` for UEFI detection
- Uses `/proc/device-tree` for Raspberry Pi detection
- Initramfs: update-initramfs, dracut, or mkinitcpio

### FreeBSD
- Uses `sysctl kern.ostype` for OS detection
- Uses `efibootmgr` for UEFI detection
- Uses FDT/sysctl for Raspberry Pi detection
- Bootcode: gptboot, boot0, loader.efi

## Testing Considerations

1. Test on QEMU/VirtualBox with multiple partition setups
2. Test BIOS and UEFI boot modes
3. Test GPT and MBR partition schemes
4. Test with insufficient space
5. Test with corrupted target filesystem
6. Test error recovery and cleanup
7. Test Raspberry Pi specific paths (if hardware available)
