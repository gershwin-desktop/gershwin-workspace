
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

# Command-line utility for .DS_Store file manipulation
TOOL_NAME = dsutil

dsutil_OBJC_FILES = dsutil.m \
	../../DSStore/DSStore.m \
	../../DSStore/DSBuddyAllocator.m \
	../../DSStore/DSStoreEntry.m \
	../../DSStore/DSStoreCodecs.m \
	../../DSStore/SimpleColor.m

# Man pages
MAN1_PAGES = dsutil.1

# Include path for DSStore headers (sibling subproject)
dsutil_INCLUDE_DIRS += -I../../DSStore

# Compiler flags
ADDITIONAL_OBJCFLAGS += -Wall

include $(GNUSTEP_MAKEFILES)/tool.make

# Custom man page installation
after-install::
	@echo "Installing man pages..."
	@$(MKDIRS) $(GNUSTEP_SYSTEM_LIBRARY)/Documentation/man/man1
	@for manpage in $(MAN1_PAGES); do \
	  $(INSTALL_DATA) $$manpage $(GNUSTEP_SYSTEM_LIBRARY)/Documentation/man/man1/$$manpage; \
	done
	@echo "Ensuring no .desktop files are installed for dsutil..."
	@# Remove any accidental .desktop files that could be created by generic rules
	@rm -f $(GNUSTEP_SYSTEM_LIBRARY)/Applications/dsutil.desktop 2>/dev/null || true
	@rm -f $(GNUSTEP_APPS)/dsutil.app/Resources/dsutil.desktop 2>/dev/null || true
	@rm -f $(GNUSTEP_INSTALL_PREFIX)/share/applications/dsutil.desktop 2>/dev/null || true

-include GNUmakefile.preamble
-include GNUmakefile.local
-include GNUmakefile.postamble
