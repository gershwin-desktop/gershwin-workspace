
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

BUNDLE_NAME = ArchiveViewer
BUNDLE_EXTENSION = .inspector

ArchiveViewer_HAS_RESOURCE_BUNDLE = yes

OBJCFLAGS += -Wall

ArchiveViewer_OBJC_FILES = ArchiveViewer.m

ArchiveViewer_PRINCIPAL_CLASS = ArchiveViewer

ArchiveViewer_RESOURCE_FILES = Resources/English.lproj \
InspectorInfo.plist

ArchiveViewer_LDFLAGS += $(shell pkg-config --libs libarchive)

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble