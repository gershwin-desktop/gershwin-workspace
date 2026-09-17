
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

BUNDLE_NAME = FolderViewer
BUNDLE_EXTENSION = .inspector

FolderViewer_HAS_RESOURCE_BUNDLE = yes

OBJCFLAGS += -Wall

FolderViewer_OBJC_FILES = FolderViewer.m 

FolderViewer_PRINCIPAL_CLASS = FolderViewer

FolderViewer_RESOURCE_FILES = Resources/English.lproj \
InspectorInfo.plist 

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble


