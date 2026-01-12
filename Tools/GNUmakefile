PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

SUBPROJECTS = \
        dsutil \
        fswatcher \
        searchtool \
        lsfupdater \
        ddbd \
        wopen \
        uitest \
        isowrite-helper 

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

# Convenience target to install only dsutil (and its man page)
.PHONY: install-dsutil
install-dsutil:
	@echo "Installing dsutil to $(GNUSTEP_SYSTEM_LIBRARY)/Tools (manpages to $(GNUSTEP_SYSTEM_LIBRARY)/Documentation/man)"
	@$(MAKE) -C dsutil install TOOL_INSTALL_DIR=$(GNUSTEP_SYSTEM_LIBRARY)/Tools GNUSTEP_SYSTEM_LIBRARY=$(GNUSTEP_SYSTEM_LIBRARY) --no-print-directory

-include GNUmakefile.postamble

