
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

# The application to be compiled
TOOL_NAME = uitest

# The Objective-C source files to be compiled
uitest_OBJC_FILES = uitest.m

# Link with AppKit and Foundation
uitest_LIBS_DEPEND_UPON += -lgnustep-gui -lgnustep-base

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/tool.make

-include GNUmakefile.postamble
