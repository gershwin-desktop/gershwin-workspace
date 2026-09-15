
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

FRAMEWORK_NAME = Operation
include Version

Operation_PRINCIPAL_CLASS = Operation
Operation_HAS_RESOURCE_BUNDLE = yes

Operation_RESOURCE_FILES = \
    Resources/Images/* \
    Resources/English.lproj \
    Resources/German.lproj

Operation_LANGUAGES = Resources/English Resources/German 

# The Objective-C source files to be compiled

Operation_OBJC_FILES = \
                 Operation.m \
                 FileOpInfo.m \
                 Functions.m 

Operation_HEADER_FILES = \
         Operation.h 

LIBRARIES_DEPEND_UPON += $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

# FileOpInfo's alias-record operation (WorkspaceCreateAliasOperation)
# reuses the wire-format code from the FSNode framework.
ADDITIONAL_INCLUDE_DIRS += -I../FSNode -I../../FSNode
# Link against the in-tree FSNode framework explicitly: in a from-source CI
# build FSNode is not installed, so gnustep-make's sibling-subproject path
# propagation (triggered by ADDITIONAL_GUI_LIBS, not LIBRARIES_DEPEND_UPON)
# does not add it here.  Mirror the Tools/* pattern that passes -L to the
# framework directory.
LIBRARIES_DEPEND_UPON += -L../FSNode/FSNode.framework -lFSNode

ifeq ($(findstring darwin, $(GNUSTEP_TARGET_OS)), darwin)
  ifeq ($(OBJC_RUNTIME_LIB), gnu)
    SHARED_LD_POSTFLAGS += -lgnustep-base -lgnustep-gui
  endif
endif

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/framework.make

-include GNUmakefile.postamble

