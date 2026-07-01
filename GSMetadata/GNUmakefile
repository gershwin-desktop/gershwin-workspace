# GNUmakefile for libGSMetadata
#
# The Finder-compatible file metadata stack (POSIX xattr wrapper, AppleDouble
# parser, and the GSFileMetadata model).  Built once here and linked by the
# consumers (Workspace) instead of being recompiled into each of them.  The
# sources live in ../GWMetadata; this library is their single build home.

PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_VAR  = GSMETADATA
LIBRARY_NAME = libGSMetadata

libGSMetadata_OBJC_FILES = \
    ../GWMetadata/GWMetaXattr.m \
    ../GWMetadata/GSAppleDouble.m \
    ../GWMetadata/GSFileMetadata.m

libGSMetadata_HEADER_FILES = \
    GWMetaXattr.h \
    GSAppleDouble.h \
    GSFileMetadata.h

libGSMetadata_HEADER_FILES_DIR = ../GWMetadata
libGSMetadata_HEADER_FILES_INSTALL_DIR = GWMetadata

ADDITIONAL_INCLUDE_DIRS += -I../GWMetadata

LIBRARIES_DEPEND_UPON += $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

ifeq ($(findstring darwin, $(GNUSTEP_TARGET_OS)), darwin)
  ifeq ($(OBJC_RUNTIME_LIB), gnu)
    SHARED_LD_POSTFLAGS += -lgnustep-base -lgnustep-gui
  endif
endif

include $(GNUSTEP_MAKEFILES)/library.make
include $(GNUSTEP_MAKEFILES)/aggregate.make

-include GNUmakefile.preamble
-include GNUmakefile.local
-include GNUmakefile.postamble
