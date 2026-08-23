PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

APP_NAME = ProgressTest

# Test helper app driven by UI tests, not a user-facing application; it
# installs next to the other system helpers where run_uitest finds it while
# keeping it out of /System/Applications.
ProgressTest_INSTALL_DIR = /System/Library/CoreServices/Applications

ProgressTest_OBJC_FILES = main.m

ProgressTest_RESOURCE_FILES = Resources/Info-gnustep.plist

-include GNUmakefile.preamble
-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/application.make

-include GNUmakefile.postamble
