PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make

ifneq ($(with_squashfs),yes)
	$(warning libsquashfs not found; appimage-icon-test disabled)
	include $(GNUSTEP_MAKEFILES)/aggregate.make
else
	TOOL_NAME = appimage-icon-test

	appimage-icon-test_OBJC_FILES = main.m WorkspaceStub.m ../../Workspace/AppImageIconProvider.m
	appimage-icon-test_OBJCFLAGS += -I../../Workspace
	appimage-icon-test_OBJCFLAGS += -I../../FSNode
	appimage-icon-test_OBJCFLAGS += $(SQUASHFS_CFLAGS)
	appimage-icon-test_LDFLAGS += $(SQUASHFS_LIBS) -ldispatch
	appimage-icon-test_TOOL_LIBS += -lgnustep-gui
	# Ensure the linker can find our FSNode framework built in-tree
	appimage-icon-test_TOOL_LIBS += -L../../FSNode/FSNode.framework -lFSNode

	include $(GNUSTEP_MAKEFILES)/tool.make
endif
