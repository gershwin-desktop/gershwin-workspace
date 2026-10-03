PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

SUBPROJECTS = \
        BadgeTest \
        ProgressTest \
        dsutil \
        fswatcher \
        searchtool \
        lsfupdater \
        wopen

# Unix-only tools: ddbd needs libdispatch, uitest needs X11, and the three
# helpers drive Unix mount/format/block-device machinery.
ifeq ($(findstring mingw,$(GNUSTEP_TARGET_OS)),mingw)
else
SUBPROJECTS += \
        ddbd \
        uitest \
        isowrite-helper \
        formatdisk-helper \
        gw-unmount
endif

ifeq ($(with_squashfs),yes)
SUBPROJECTS += appimage-icon-test
endif

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

# Convenience target to install only dsutil (and its man page)
.PHONY: install-dsutil
install-dsutil:
	@echo "Installing dsutil to $(GNUSTEP_SYSTEM_LIBRARY)/Tools (manpages to $(GNUSTEP_SYSTEM_LIBRARY)/Documentation/man)"
	@$(MAKE) -C dsutil install TOOL_INSTALL_DIR=$(GNUSTEP_SYSTEM_LIBRARY)/Tools GNUSTEP_SYSTEM_LIBRARY=$(GNUSTEP_SYSTEM_LIBRARY) --no-print-directory

-include GNUmakefile.postamble


