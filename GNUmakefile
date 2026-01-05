ifeq ($(GNUSTEP_MAKEFILES),)
 GNUSTEP_MAKEFILES := $(shell gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null)
  ifeq ($(GNUSTEP_MAKEFILES),)
    $(warning )
    $(warning Unable to obtain GNUSTEP_MAKEFILES setting from gnustep-config!)
    $(warning Perhaps gnustep-make is not properly installed,)
    $(warning so gnustep-config is not in your PATH.)
    $(warning )
    $(warning Your PATH is currently $(PATH))
    $(warning )
  endif
endif

ifeq ($(GNUSTEP_MAKEFILES),)
  $(error You need to set GNUSTEP_MAKEFILES before compiling!)
endif

PACKAGE_NEEDS_CONFIGURE = YES

PACKAGE_NAME = gworkspace
export PACKAGE_NAME
include $(GNUSTEP_MAKEFILES)/common.make

# Default filesystem layout: assume self-contained GNUstep in /System
# This makes 'make install' place system files under /System (e.g., man pages)
ifndef GNUSTEP_FILESYSTEM_LAYOUT
GNUSTEP_FILESYSTEM_LAYOUT = gnustep
endif

ifndef GNUSTEP_SYSTEM_LIBRARY
GNUSTEP_SYSTEM_LIBRARY = /System/Library
endif

VERSION = 1.1.0
SVN_MODULE_NAME = gworkspace

BUILD_GWMETADATA = 0

#
# subprojects
#
SUBPROJECTS = DSStore \
	      FSNode \
	      DBKit \
	      Tools \
	      Inspector \
	      Operation \
	      Workspace

ifeq ($(BUILD_GWMETADATA),1)
SUBPROJECTS += GWMetadata
endif


-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

# After-install cleanup: remove any generated .desktop files from installed app bundles
after-install::
	@echo "Cleaning up .desktop files installed by this workspace..."
	@for dir in "$(GNUSTEP_APPS)" "/System/Applications" "$(GNUSTEP_SYSTEM_LIBRARY)/Applications"; do \
	  if [ -d "$$dir" ]; then \
	    for app in "$$dir"/*.app; do \
	      if [ -d "$$app/Resources" ]; then rm -f "$$app/Resources"/*.desktop 2>/dev/null || true; fi; \
	    done; \
	  fi; \
	done
	@# Also remove any accidental dsutil .desktop files from common locations
	@rm -f $(GNUSTEP_SYSTEM_LIBRARY)/Applications/dsutil.desktop 2>/dev/null || true
	@rm -f $(GNUSTEP_SYSTEM_LIBRARY)/Tools/dsutil.desktop 2>/dev/null || true
	@rm -f $(GNUSTEP_INSTALL_PREFIX)/share/applications/dsutil.desktop 2>/dev/null || true

include GNUmakefile.postamble

include $(GNUSTEP_MAKEFILES)/Master/nsis.make
