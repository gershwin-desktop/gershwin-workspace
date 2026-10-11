# Standalone build of the two alias interop helpers (not part of the default
# build): gw-alias-writer links the built FSNode framework, gen_alias_for_mac
# compiles FSNAlias.m in-process.  Both use the built libGSMetadata, never
# compiled in as well, or the runtime would load GSFileMetadata twice.
#
# SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause

include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM

TOOL_NAME = gw-alias-writer gen_alias_for_mac

gw-alias-writer_OBJC_FILES = gw-alias-writer.m
gen_alias_for_mac_OBJC_FILES = gen_alias_for_mac.m

ADDITIONAL_INCLUDE_DIRS += -I../../FSNode -I../../GWMetadata
ADDITIONAL_OBJCFLAGS += -Wall
ADDITIONAL_TOOL_LIBS += -L../../GSMetadata/obj -lGSMetadata -lgnustep-gui

# gw-alias-writer uses the framework built in this tree, not an installed one.
gw-alias-writer_TOOL_LIBS += -L../../FSNode/FSNode.framework/Versions/Current -lFSNode
ADDITIONAL_LDFLAGS += -Wl,--disable-new-dtags \
                      -Wl,-rpath,$(CURDIR)/../../FSNode/FSNode.framework/Versions/Current \
                      -Wl,-rpath,$(CURDIR)/../../GSMetadata/obj

include $(GNUSTEP_MAKEFILES)/tool.make
