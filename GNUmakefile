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

VERSION = 1.1.0
SVN_MODULE_NAME = gworkspace

BUILD_GWMETADATA = 0

# libsquashfs support (AppImage icons) - autodetect via pkg-config or link test
SQUASHFS_CFLAGS ?= $(shell pkg-config --cflags libsquashfs 2>/dev/null)
SQUASHFS_LIBS ?= $(shell pkg-config --libs libsquashfs 2>/dev/null)

ifeq ($(SQUASHFS_LIBS),)
  SQUASHFS_CFLAGS := $(shell pkg-config --cflags squashfs 2>/dev/null)
  SQUASHFS_LIBS := $(shell pkg-config --libs squashfs 2>/dev/null)
endif

ifeq ($(SQUASHFS_LIBS),)
  ifneq ($(shell TMP=$$(mktemp -t sqfstest.XXXXXX 2>/dev/null) && \
    printf 'int main(void){return 0;}\n' | $(CC) -x c - -lsquashfs -o $$TMP >/dev/null 2>&1 && \
    rm -f $$TMP && echo yes),)
    SQUASHFS_LIBS := -lsquashfs
  endif
endif

ifneq ($(SQUASHFS_LIBS),)
  with_squashfs = yes
else
  with_squashfs = no
endif

export with_squashfs SQUASHFS_CFLAGS SQUASHFS_LIBS

#
# subprojects
#
SUBPROJECTS = FSNode \
	      DBKit \
	      DSStore \
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

include GNUmakefile.postamble

include $(GNUSTEP_MAKEFILES)/Master/nsis.make
