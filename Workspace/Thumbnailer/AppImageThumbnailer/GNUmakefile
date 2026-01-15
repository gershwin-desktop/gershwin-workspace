PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = AppImageThumbnailer
BUNDLE_EXTENSION = .thumb

OBJCFLAGS += -Wall

AppImageThumbnailer_OBJC_FILES = AppImageThumbnailer.m
AppImageThumbnailer_PRINCIPAL_CLASS = AppImageThumbnailer
AppImageThumbnailer_LDFLAGS = -lsquashfs

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble
