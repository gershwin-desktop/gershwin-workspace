PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = appimage-icon-test

appimage-icon-test_OBJC_FILES = main.m ../../Workspace/AppImageIconProvider.m
appimage-icon-test_OBJCFLAGS += -I../../Workspace
appimage-icon-test_LDFLAGS += -lsquashfs
appimage-icon-test_TOOL_LIBS += -lgnustep-gui

include $(GNUSTEP_MAKEFILES)/tool.make
