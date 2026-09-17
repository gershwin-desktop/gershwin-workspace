
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

BUNDLE_NAME = FModuleSize
BUNDLE_EXTENSION = .finder

FModuleSize_HAS_RESOURCE_BUNDLE = yes

OBJCFLAGS += -Wall

FModuleSize_OBJC_FILES = FModuleSize.m 

FModuleSize_PRINCIPAL_CLASS = FModuleSize

FModuleSize_RESOURCE_FILES = \
    Resources/Images/* \
    Resources/FModuleSize.gorm

include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/bundle.make

include GNUmakefile.postamble


