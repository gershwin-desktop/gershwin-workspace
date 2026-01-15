PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

TOOL_NAME = appimage-thumbnailer-tests

appimage-thumbnailer-tests_OBJC_FILES = main.m ../AppImageThumbnailer.m
appimage-thumbnailer-tests_OBJCFLAGS += -I.. -I../.. -Wall
appimage-thumbnailer-tests_LDFLAGS += -lsquashfs
appimage-thumbnailer-tests_TOOL_LIBS += -lgnustep-gui

include $(GNUSTEP_MAKEFILES)/tool.make
