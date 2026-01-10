/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

//
// BootableInstallerTypes.h
// Bootable Installer - Common Type Definitions
//

#ifndef BOOTABLE_INSTALLER_TYPES_H
#define BOOTABLE_INSTALLER_TYPES_H

#import <Foundation/Foundation.h>

/**
 * Boot firmware type detected on the system
 */
typedef NS_ENUM(NSInteger, BootFirmwareType) {
  BootFirmwareTypeUnknown = 0,
  BootFirmwareTypeBIOS,
  BootFirmwareTypeUEFI,
  BootFirmwareTypeRaspberryPi,
  BootFirmwareTypeFreeBSDLoader
};

/**
 * Operating system type
 */
typedef NS_ENUM(NSInteger, SourceOSType) {
  SourceOSTypeUnknown = 0,
  SourceOSTypeLinux,
  SourceOSTypeFreeBSD,
  SourceOSTypeNetBSD,
  SourceOSTypeOpenBSD,
  SourceOSTypeDragonFly
};

/**
 * Partition scheme type
 */
typedef NS_ENUM(NSInteger, PartitionSchemeType) {
  PartitionSchemeTypeUnknown = 0,
  PartitionSchemeTypeGPT,
  PartitionSchemeTypeMBR,
  PartitionSchemeTypeBSD
};

#endif // BOOTABLE_INSTALLER_TYPES_H
