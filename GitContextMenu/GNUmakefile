# GNUmakefile for GitContextMenu
#
# A GWorkspace extension bundle (.gwext).  It is loaded at runtime by
# Workspace's GWExtensionsManager and adds a "Git" context-menu submenu plus a
# badge overlay on git-repository folders.  It is intentionally a separate
# bundle, not part of Workspace or FSNode.

PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

BUNDLE_NAME = GitContextMenu
GitContextMenu_PRINCIPAL_CLASS = GitContextMenu
GitContextMenu_OBJC_FILES = GitContextMenu.m
GitContextMenu_RESOURCE_FILES =

# FSNode types/headers (sibling subproject) and the generic extension protocol
# header shipped in Workspace/.  Pass -L to the in-tree FSNode framework: in a
# from-source CI build FSNode is not installed, and gnustep-make does not add
# the sibling framework path for bundles (only for the main app), so the
# explicit -L is required (matches the Tools/* and Operation patterns).
ADDITIONAL_GUI_LIBS += -L../FSNode/FSNode.framework -lFSNode
ADDITIONAL_INCLUDE_DIRS += -I../Workspace
ADDITIONAL_INCLUDE_DIRS += -I../FSNode

BUNDLE_EXTENSION = .gwext
BUNDLE_INSTALL_DIR = $(GNUSTEP_SYSTEM_LIBRARY)/Bundles

-include GNUmakefile.preamble
-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/bundle.make
