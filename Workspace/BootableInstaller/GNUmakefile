#
# GNUmakefile for BootableInstaller module
#
# Copyright (C) 2025-2026 Free Software Foundation, Inc.
#
# This file is part of the GNUstep Workspace application
#

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECT_NAME = BootableInstaller

BootableInstaller_OBJC_FILES = \
	BootEnvironmentDetector.m \
	BootPartitionValidator.m \
	BootableFileCopier.m \
	BootloaderInstaller.m \
	BootableInstallController.m

BootableInstaller_HEADER_FILES = \
	BootEnvironmentDetector.h \
	BootPartitionValidator.h \
	BootableFileCopier.h \
	BootloaderInstaller.h \
	BootableInstallController.h

BootableInstaller_OBJCFLAGS = -Wall -Wno-import

# Include paths
BootableInstaller_INCLUDE_DIRS = -I..

-include GNUmakefile.preamble
include $(GNUSTEP_MAKEFILES)/subproject.make
-include GNUmakefile.postamble
