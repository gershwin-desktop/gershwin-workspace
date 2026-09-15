
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

BUNDLE_NAME = NSTIFFViewer
BUNDLE_EXTENSION = .inspector

NSTIFFViewer_HAS_RESOURCE_BUNDLE = yes

OBJCFLAGS += -Wall

#
# We are creating a bundle
#
NSTIFFViewer_OBJC_FILES = NSTIFFViewer.m

NSTIFFViewer_PRINCIPAL_CLASS = NSTIFFViewer

NSTIFFViewer_RESOURCE_FILES = Resources/English.lproj \
InspectorInfo.plist 

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

-include GNUmakefile.postamble


