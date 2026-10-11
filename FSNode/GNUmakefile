
PACKAGE_NAME = gworkspace
include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM
include Version

FRAMEWORK_NAME = FSNode

FSNode_OBJC_FILES = \
         FSNode.m \
         FSNDirEntry.m \
         FSNIconLoader.m \
         FSNodeRep.m \
         FSNodeRepIcons.m \
         FSNFunctions.m \
         FSNTextCell.m \
         FSNBrowserCell.m \
         FSNBrowserScroll.m \
         FSNBrowserMatrix.m \
         FSNBrowserColumn.m \
         FSNBrowser.m \
         FSNIcon.m \
         FSNIconsView.m \
         FSNListView.m \
         FSNPathComponentsViewer.m \
         FSNPlacementEnumerator.m \
          FSNIconPlacement.m \
          FSNAlias.m \
          FSNAliasFile.m \
          FSNLocationFile.m \
          FSNSpringLoader.m \
          FSNIconDragSession.m \


FSNode_HEADER_FILES = \
         FSNode.h \
         FSNDirEntry.h \
         FSNIconLoader.h \
         FSNodeRep.h \
         FSNFunctions.h \
         FSNTextCell.h \
         FSNBrowserCell.h \
         FSNBrowserScroll.h \
         FSNBrowserMatrix.h \
         FSNBrowserColumn.h \
         FSNBrowser.h \
         FSNIcon.h \
         FSNIconsView.h \
         FSNListView.h \
         FSNPathComponentsViewer.h \
         FSNIconPlacement.h \
         FSNPlacementEnumerator.h \
         FSNMetadataProvider.h \
          FSNIconPositionStore.h \
          FSNAlias.h \
          FSNAliasFile.h \
          FSNLocationFile.h \
          FSNSpringLoader.h \
          FSNIconDragSession.h \


FSNode_HAS_RESOURCE_BUNDLE = yes                                          

FSNode_RESOURCE_FILES = \
    Resources/Images/* \
    Resources/*.lproj \
    Resources/WellKnownLocations.plist \

# Views reach Finder metadata and .DS_Store only through the
# FSNMetadataProvider / FSNIconPositionStore protocols; the one direct use of
# libGSMetadata is the alias and location file reader/writer (see below).

FSNode_LANGUAGES = \
	English \
	Italian \
	German \
	French \
	Spanish \

# Alias and location files read and write their forks through GSFileMetadata
# (built before this framework).
LIBRARIES_DEPEND_UPON += -L../GSMetadata/obj -lGSMetadata
LIBRARIES_DEPEND_UPON += $(GUI_LIBS) $(FND_LIBS) $(OBJC_LIBS) $(SYSTEM_LIBS)

ifeq ($(findstring darwin, $(GNUSTEP_TARGET_OS)), darwin)
  ifeq ($(OBJC_RUNTIME_LIB), gnu)
    SHARED_LD_POSTFLAGS += -lgnustep-base -lgnustep-gui
  endif
endif

SUBPROJECTS = ExtendedInfo 

-include GNUmakefile.preamble

include $(GNUSTEP_MAKEFILES)/framework.make

include $(GNUSTEP_MAKEFILES)/aggregate.make

-include GNUmakefile.postamble

