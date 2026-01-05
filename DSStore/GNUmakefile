# GNUmakefile for libDSStore
#
# A library for .DS_Store interoperability - reading and writing .DS_Store files.
# Integrated as a subproject of gworkspace following GNUstep conventions.
# The dsutil command-line tool is in the Tools/dsutil subproject.

PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

LIBRARY_VAR  = DSSTORE
LIBRARY_NAME = libDSStore

libDSStore_OBJC_FILES = \
    DSStore.m \
    DSBuddyAllocator.m \
    DSStoreEntry.m \
    DSStoreCodecs.m \
    SimpleColor.m

libDSStore_HEADER_FILES = \
    DSStore.h \
    DSBuddyAllocator.h \
    DSStoreEntry.h \
    DSStoreCodecs.h \
    SimpleColor.h

libDSStore_HEADER_FILES_DIR = .
libDSStore_HEADER_FILES_INSTALL_DIR = DSStore

LIBRARIES_DEPEND_UPON += $(FND_LIBS) $(GUI_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

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
