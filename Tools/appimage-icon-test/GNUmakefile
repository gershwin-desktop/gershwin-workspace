PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

ifneq ($(with_squashfs),yes)
	$(warning libsquashfs not found; appimage-icon-test disabled)
	include $(GNUSTEP_MAKEFILES)/aggregate.make
else
	TOOL_NAME = appimage-icon-test

	appimage-icon-test_OBJC_FILES = main.m WorkspaceStub.m ../../Workspace/AppImageIconProvider.m \
		../../Workspace/GWThumbnailSpec.m ../../Workspace/GWThumbnailPNG.m \
		../../Workspace/GWThumbnailStore.m ../../Workspace/GWScaleFactor.m \
		../../Workspace/GWWorkerPool.m
	appimage-icon-test_OBJCFLAGS += -I../../Workspace
	appimage-icon-test_OBJCFLAGS += -I../../FSNode
	appimage-icon-test_OBJCFLAGS += $(SQUASHFS_CFLAGS)
	appimage-icon-test_LDFLAGS += $(SQUASHFS_LIBS) -ldispatch
	# The provider's icon disk cache writes its thumbnails through libpng.
	appimage-icon-test_OBJCFLAGS += $(shell pkg-config --cflags libpng)
	appimage-icon-test_LDFLAGS += $(shell pkg-config --libs libpng)
	appimage-icon-test_TOOL_LIBS += -lgnustep-gui
	# Ensure the linker can find our FSNode framework built in-tree
	appimage-icon-test_TOOL_LIBS += -L../../FSNode/FSNode.framework -lFSNode
	# libFSNode needs libGSMetadata, which is not installed yet in a from-source
	# build; naming it directly makes every linker resolve it from the tree.
	appimage-icon-test_TOOL_LIBS += -L../../GSMetadata/obj -lGSMetadata

	include $(GNUSTEP_MAKEFILES)/tool.make
endif

