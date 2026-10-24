
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
         FSNKindNames.m \
         FSNTextCell.m \
         FSNBrowserCell.m \
         FSNBrowserScroll.m \
         FSNBrowserMatrix.m \
         FSNBrowserColumn.m \
         FSNBrowser.m \
         FSNBrowserLayout.m \
         FSNColumnViewOptions.m \
         FSNBrowserPreviewView.m \
         FSNBrowserResizeHandle.m \
         FSNArrangement.m \
         FSNIconPreview.m \
         FSNIcon.m \
         FSNIconsView.m \
         FSNListView.m \
         FSNListRowModel.m \
         FSNSelectionModel.m \
         FSNRenamePolicy.m \
         FSNRenameController.m \
         FSNPathComponentsViewer.m \
         FSNPlacementEnumerator.m \
          FSNIconPlacement.m \
          FSNAlias.m \
          FSNAliasFile.m \
          FSNAliasIcon.m \
          FSNLocationFile.m \
          FSNSpringLoader.m \
          FSNIconDragSession.m \
          GWThumbnailFormat.m \
          GWThumbnailPNG.m \
          GWThumbnailImage.m \
          GWThumbnailStore.m \
          GWWorkerPool.m \


FSNode_HEADER_FILES = \
         FSNode.h \
         FSNDirEntry.h \
         FSNIconLoader.h \
         FSNodeRep.h \
         FSNFunctions.h \
         FSNKindNames.h \
         FSNTextCell.h \
         FSNBrowserCell.h \
         FSNBrowserScroll.h \
         FSNBrowserMatrix.h \
         FSNBrowserColumn.h \
         FSNBrowser.h \
         FSNBrowserLayout.h \
         FSNColumnViewOptions.h \
         FSNBrowserPreviewView.h \
         FSNBrowserResizeHandle.h \
         FSNArrangement.h \
         FSNIconPreview.h \
         FSNPreviewProvider.h \
         FSNIcon.h \
         FSNIconsView.h \
         FSNListView.h \
         FSNListRowModel.h \
         FSNSelectionModel.h \
         FSNRenamePolicy.h \
         FSNRenameController.h \
         FSNPathComponentsViewer.h \
         FSNIconPlacement.h \
         FSNPlacementEnumerator.h \
         FSNMetadataProvider.h \
          FSNIconPositionStore.h \
          FSNAlias.h \
          FSNAliasFile.h \
          FSNAliasIcon.h \
          FSNLocationFile.h \
          FSNSpringLoader.h \
          FSNIconDragSession.h \
          GWThumbnailFormat.h \
          GWThumbnailPNG.h \
          GWThumbnailImage.h \
          GWThumbnailStore.h \
          GWWorkerPool.h \


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

# The thumbnail store writes its PNGs, with their text chunks, through
# libpng, which libs-gui already depends on; without it the build stops
# here rather than at the link.
PNG_CFLAGS := $(shell pkg-config --cflags libpng 2>/dev/null)
PNG_LIBS := $(shell pkg-config --libs libpng 2>/dev/null)
ifeq ($(PNG_LIBS),)
  $(error libpng (pkg-config libpng) is required for the thumbnail store)
endif
ADDITIONAL_CPPFLAGS += $(PNG_CFLAGS)
LIBRARIES_DEPEND_UPON += $(PNG_LIBS)

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

