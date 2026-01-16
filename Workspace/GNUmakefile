
PACKAGE_NEEDS_CONFIGURE = YES

PACKAGE_NAME = gworkspace
GNUSTEP_INSTALLATION_DOMAIN = SYSTEM
include $(GNUSTEP_MAKEFILES)/common.make

VERSION = 1.1.0

# DBus support variables from configure
with_dbus = yes
DBUS_CFLAGS = -I/usr/include/dbus-1.0 -I/usr/lib/aarch64-linux-gnu/dbus-1.0/include 
DBUS_LIBS = -ldbus-1 

#
# subprojects
#
SUBPROJECTS = Finder/Modules \
	Thumbnailer

#
# MAIN APP
#
APP_NAME = Workspace
Workspace_PRINCIPAL_CLASS = Workspace
Workspace_APPLICATION_ICON=FileManager.tiff

Workspace_HAS_RESOURCE_BUNDLE = yes

#
# Additional libraries
#
ADDITIONAL_GUI_LIBS += -lFSNode
ADDITIONAL_GUI_LIBS += -lInspector
ADDITIONAL_GUI_LIBS += -lOperation
ADDITIONAL_GUI_LIBS += -lsquashfs

# Include path for DSStore headers (sibling subproject)
ADDITIONAL_INCLUDE_DIRS += -I../DSStore

Workspace_RESOURCE_FILES = \
  Resources/Icons/* \
  Resources/English.lproj \
  Resources/BrasilPortuguese.lproj \
  Resources/Dutch.lproj \
  Resources/Esperanto.lproj \
  Resources/French.lproj \
  Resources/German.lproj \
  Resources/Hungarian.lproj \
  Resources/Italian.lproj \
  Resources/Norvegian.lproj \
  Resources/Portuguese.lproj \
  Resources/Romanian.lproj \
  Resources/Spanish.lproj \
  Resources/Japanese.lproj \
  Resources/Polish.lproj \
  WorkspaceInfo.plist

Workspace_LANGUAGES = \
  Resources/English \
  Resources/BrasilPortuguese \
  Resources/Dutch \
  Resources/Esperanto \
  Resources/French \
  Resources/German \
  Resources/Hungarian \
  Resources/Italian \
  Resources/Norvegian \
  Resources/Portuguese \
  Resources/Romanian \
  Resources/Spanish \
  Resources/Japanese \
  Resources/Polish

# The Objective-C source files to be compiled
Workspace_OBJC_FILES = main.m \
GWFunctions.m \
AppImageIconProvider.m \
Workspace.m \
Workspace+UITesting.m \
X11AppSupport.m \
WorkspaceApplication.m \
GWApplicationLauncher.m \
GSGlobalShortcutsManager.m \
Desktop/GWDesktopManager.m \
Desktop/GWDesktopWindow.m \
Desktop/GWDesktopView.m \
Desktop/GWDesktopIcon.m \
Desktop/Dock/Dock.m \
Desktop/Dock/DockIcon.m \
FileViewer/GWViewersManager.m \
FileViewer/GWViewer.m \
FileViewer/GWSpatialViewer.m \
FileViewer/GWViewerWindow.m \
FileViewer/GWViewerBrowser.m \
FileViewer/GWViewerIconsView.m \
FileViewer/GWViewerListView.m \
FileViewer/GWViewerShelf.m \
FileViewer/GWViewerSplit.m \
FileViewer/GWViewerScrollView.m \
FileViewer/GWViewerIconsPath.m \
FileViewer/GWViewerPathsPopUp.m \
FileViewer/DSStoreInfo.m \
../DSStore/DSStore.m \
../DSStore/DSBuddyAllocator.m \
../DSStore/DSStoreEntry.m \
../DSStore/DSStoreCodecs.m \
../DSStore/SimpleColor.m \
Finder/Finder.m \
Finder/FindModuleView.m \
Finder/SearchPlacesBox.m \
Finder/SearchPlacesCell.m \
Finder/SearchResults/SearchResults.m \
Finder/SearchResults/ResultsTableView.m \
Finder/LiveSearch/LSFolder.m \
Finder/LiveSearch/LSFEditor.m \
Preferences/PrefController.m \
Preferences/DefEditorPref.m \
Preferences/XTermPref.m \
Preferences/DefSortOrderPref.m \
Preferences/IconsPref.m \
Preferences/HiddenFilesPref.m \
Preferences/HistoryPref.m \
Preferences/BrowserViewerPref.m \
Preferences/OperationPrefs.m \
Preferences/DesktopPref.m \
History/History.m \
Dialogs/Dialogs.m \
Dialogs/ExecuteController.m \
Dialogs/OpenWithController.m \
Dialogs/RunExternalController.m \
Dialogs/CompletionField.m \
Dialogs/StartAppWin.m \
Thumbnailer/GWThumbnailer.m \
Network/NetworkServiceItem.m \
Network/NetworkServiceManager.m \
Network/NetworkFSNode.m \
Network/NetworkVolumeManager.m \
Network/SFTPMount.m \
AVFSMount.m \
VolumeManager.m \
GWUnmountHelper.m \
ISOWrite/ISOWriteHandler.m \
ISOWrite/ISOWriteOperation.m \
ISOWrite/BlockDeviceInfo.m \
ISOWrite/ISOWriteConfirmation.m \
ISOWrite/ISOWriteProgressWindow.m \

# Conditionally add DBusConnection.m and FileManagerDBusInterface.m if DBus is available
ifeq ($(with_dbus), yes)
  Workspace_OBJC_FILES += DBusConnection.m
  Workspace_OBJC_FILES += FileManagerDBusInterface.m
endif

-include GNUmakefile.preamble

-include GNUmakefile.local

include $(GNUSTEP_MAKEFILES)/aggregate.make

include $(GNUSTEP_MAKEFILES)/application.make

-include GNUmakefile.postamble
