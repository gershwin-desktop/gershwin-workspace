/* FSNListView.h
 *
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
 *
 * Date: December 2004
 *
 * This file is part of the GNUstep FSNode framework
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#ifndef FSN_LIST_VIEW_H
#define FSN_LIST_VIEW_H

#import <Foundation/Foundation.h>
#import <AppKit/NSTableView.h>
#import <AppKit/NSTextField.h>
#import "FSNodeRep.h"

@class NSTableColumn;
@class FSNListView;
@class FSNListViewNodeRep;
@class FSNListViewNameEditor;
@class FSNFolderSizeCalculator;
@class FSNListRowModel;

/* Column identifiers as Finder writes them in the "columns" array of the
 * lsvp record.  A table column itself is identified by an NSNumber (an
 * FSNInfoType, or one of the FSNListColumnType values below) so that the
 * per-folder column descriptions already stored by older versions keep
 * working; use the class methods of FSNListViewDataSource (FinderListOptions)
 * to translate. */
extern NSString * const FSNListColumnIdName;
extern NSString * const FSNListColumnIdDateModified;
extern NSString * const FSNListColumnIdDateCreated;
extern NSString * const FSNListColumnIdSize;
extern NSString * const FSNListColumnIdKind;
extern NSString * const FSNListColumnIdLabel;
extern NSString * const FSNListColumnIdVersion;
extern NSString * const FSNListColumnIdComments;
extern NSString * const FSNListColumnIdDateLastOpened;
/* Not a Finder column; the owner column this list view has always had. */
extern NSString * const FSNListColumnIdOwner;

/* Table column identifiers for the columns FSNInfoType has no value for.
 * Kept well apart from FSNInfoType so that it can grow. */
enum {
  FSNListColumnTypeDateCreated = 100,
  FSNListColumnTypeDateLastOpened = 101,
  FSNListColumnTypeLabel = 102,
  FSNListColumnTypeVersion = 103,
  FSNListColumnTypeComments = 104
};

/* Posted (object: the FSNListView) when the USER changed a list option by
 * hand - a click on a column header, a column dragged to a new place.  The
 * option is in the userInfo under FSNListViewChangedOptionKey.  Changes made
 * through the setters below never post it, so that applying stored settings
 * does not write them straight back. */
extern NSString * const FSNListViewOptionsDidChangeNotification;
extern NSString * const FSNListViewChangedOptionKey;
/* Values of FSNListViewChangedOptionKey. */
extern NSString * const FSNListViewOptionSort;        /* column and/or direction */
extern NSString * const FSNListViewOptionColumnOrder;

/* Optional per-file metadata the list view asks the metadata provider
 * (FSNodeRep -metadataProvider) for; a column whose provider method is
 * missing shows "--". */
@protocol FSNListViewMetadataProvider <NSObject>
@optional
- (NSString *)commentForPath:(NSString *)path;
- (NSString *)labelNameForPath:(NSString *)path;
@end

#import "FSNIconLoader.h"
#import "FSNSpringLoader.h"

/* Sums the sizes of the files below paths on a thread of its own, one
 * folder at a time.  Delegate messages arrive on the main thread, and none
 * after -cancel returned. */
@protocol FSNFolderSizeCalculatorDelegate <NSObject>
- (void)sizeCalculator:(FSNFolderSizeCalculator *)calculator
        didComputeSize:(unsigned long long)size
               forPath:(NSString *)path;
- (void)sizeCalculatorDidFinish:(FSNFolderSizeCalculator *)calculator;
@end

@interface FSNListViewDataSource : NSObject <NSTextFieldDelegate, FSNDecorationClient, FSNSpringFlashing>
{
  FSNListView *listView;

  FSNode *node;
  NSMutableArray *nodeReps;
  FSNInfoType hlighColId;
  NSString *extInfoType;

  /* Bumped on every contents change; pending FSNIconLoader items carrying
   * an older generation are dropped. */
  NSInteger generation;

  NSArray *lastSelection;

  NSUInteger mouseFlags;
  BOOL isDragTarget;
  BOOL forceCopy;
  NSDragOperation negotiatedDragOp;
  FSNListViewNodeRep *dndTarget;
  /* The row a drag rests on, for the flash before it springs open; not
     retained, it is one of nodeReps. */
  FSNListViewNodeRep *springRep;
  BOOL springFlashing;
  BOOL springRestingLit;
  unsigned int dragOperation;
  NSRect dndValidRect;

  FSNListViewNameEditor *nameEditor;

  FSNodeRep *fsnodeRep;

  id <DesktopApplication> desktopApp;

  /* Finder list options (see FinderListOptions below). */
  BOOL sortAscending;
  BOOL usesRelativeDates;
  BOOL calculatesAllSizes;
  NSFont *listFont;          /* nil: the cells' own default */
  NSInteger listIconSize;
  NSMutableDictionary *folderSizes;   /* path -> NSNumber, from the calculator */
  FSNFolderSizeCalculator *sizeCalculator;
  NSMutableDictionary *columnDirections;   /* identifier -> BOOL ascending of the columns left */
  NSMutableDictionary *hiddenColumnWidths;  /* identifier -> width, to restore */
  NSUInteger programmaticChanges;

  /* The rows with folders expanded inline; nodeReps is its flat row order. */
  FSNListRowModel *rowModel;
  NSMutableSet *watchedFolders;   /* paths of the expanded folders shown */
}

- (id)initForListView:(FSNListView *)aview;

- (FSNode *)infoNode;

- (BOOL)keepsColumnsInfo;

// DS_Store support - set sort column and column widths
- (void)setSortColumn:(FSNInfoType)sortType;
- (FSNInfoType)sortColumn;
- (void)setColumnWidth:(float)width forIdentifier:(FSNInfoType)identifier;
- (float)columnWidthForIdentifier:(FSNInfoType)identifier;

- (void)createColumns:(NSDictionary *)info;

- (void)addColumn:(NSDictionary *)info;

- (void)removeColumnWithIdentifier:(NSNumber *)identifier;

- (NSDictionary *)columnsDescription;

- (void)sortNodeReps;

- (void)setMouseFlags:(NSUInteger)flags;

- (void)doubleClickOnListView:(id)sender;

- (void)selectRep:(id)aRep;

- (void)unselectRep:(id)aRep;

- (void)selectIconOfRep:(id)aRep;

- (void)unSelectIconsOfRepsDifferentFrom:(id)aRep;

- (void)selectRepInPrevRow;

- (void)selectRepInNextRow;

- (NSString *)selectRepWithPrefix:(NSString *)prefix;

- (void)redisplayRep:(id)aRep;

- (id)desktopApp;

@end


/* What Finder's list view options need.  Column ids are the Finder names
 * (FSNListColumnId...). */
@interface FSNListViewDataSource (FinderListOptions)

+ (NSArray *)finderColumnIds;

/* nil for an id this list view has no column for. */
+ (NSNumber *)tableIdentifierForColumnId:(NSString *)columnId;

/* nil for a column without a Finder name (extended info, description...). */
+ (NSString *)columnIdForTableIdentifier:(NSNumber *)identifier;

/* The direction a column sorts in when it is clicked for the first time:
 * ascending for text columns, descending (newest, biggest first) for dates
 * and sizes. */
+ (BOOL)defaultSortAscendingForColumnId:(NSString *)columnId;

/* "Today 2:05 PM" / "Heute, 14:05" when relative is YES and date is on
 * today's or yesterday's calendar day (local time zone) relative to now,
 * otherwise the short date and time of the language ("08.10.2026 09:30"),
 * as the Finder of that language shows them. */
+ (NSString *)descriptionOfDate:(NSDate *)date
                     relativeTo:(NSDate *)now
                  relativeNames:(BOOL)relative;

/* The same with the words and formats taken from a strings table (a
 * Localizable.strings of one language) instead of the framework's bundle. */
+ (NSString *)descriptionOfDate:(NSDate *)date
                     relativeTo:(NSDate *)now
                  relativeNames:(BOOL)relative
                        strings:(NSDictionary *)table;

/* Row height for a text size (points; 0 for the default) and icon size. */
+ (CGFloat)rowHeightForTextSize:(CGFloat)textSize iconSize:(NSInteger)iconSize;
/* The same rounded up to whole device pixels at a scale factor. */
+ (CGFloat)rowHeightForTextSize:(CGFloat)textSize
                        iconSize:(NSInteger)iconSize
                     scaleFactor:(CGFloat)scale;
/* The row height for the current text and icon size on this screen. */
- (CGFloat)rowHeight;

/* Sorting.  Unknown or hidden ids are refused (NO). Ascending means the
 * values in their natural order: A to Z, oldest first, smallest first. */
- (BOOL)setSortColumnId:(NSString *)columnId ascending:(BOOL)ascending;
- (NSString *)sortColumnId;
/* Every column keeps the direction it was last sorted in (its first-click
 * one before that), also while it is not the sort column. */
- (BOOL)sortAscendingForColumnId:(NSString *)columnId;
- (void)setSortAscending:(BOOL)ascending;
- (BOOL)sortAscending;

/* Columns.  The name column is always shown and always first.  Hiding a
 * column the list is sorted by sorts by name instead. */
- (BOOL)setColumn:(NSString *)columnId visible:(BOOL)visible;
- (BOOL)isColumnVisible:(NSString *)columnId;

/* Finder ids of the shown columns, left to right (columns without a Finder
 * id are left out). */
- (NSArray *)columnOrder;

/* Moves the listed shown columns to the left, in that order, name first;
 * ids that are unknown or hidden are skipped, other shown columns follow. */
- (void)setColumnOrder:(NSArray *)columnIds;

- (BOOL)setColumnWidth:(CGFloat)width forColumnId:(NSString *)columnId;
- (CGFloat)columnWidthForColumnId:(NSString *)columnId;

/* Dates of the date columns as "Today at ..." / "Yesterday at ...". */
- (void)setUsesRelativeDates:(BOOL)flag;
- (BOOL)usesRelativeDates;

/* Folder sizes in the size column, computed on a background thread; started
 * by this call and by every (re)load of the shown folder, cancelled when
 * another folder is shown, when this is turned off and when the view goes
 * away.  Without it folders show "--" like Finder's. */
- (void)setCalculatesAllSizes:(BOOL)flag;
- (BOOL)calculatesAllSizes;
- (BOOL)isCalculatingSizes;
/* The computed size of a shown folder, nil as long as not known. */
- (NSNumber *)calculatedSizeForPath:(NSString *)path;

/* Text size of all cells in points; 0 selects the default. */
- (void)setTextSize:(CGFloat)points;
- (CGFloat)textSize;

/* Size of the icons in the name column in points, 16 to 128. */
- (void)setListIconSize:(NSInteger)points;
- (NSInteger)listIconSize;

/* Stops background work; for a list view that is going away. */
- (void)detachFromListView;

@end


@interface FSNListViewDataSource (Expansion)

/* Folders expand inline: their items follow them one level deeper.  A
 * reload of the same folder keeps what was expanded. */
- (BOOL)isRepExpandable:(FSNListViewNodeRep *)rep;
- (BOOL)isRepExpanded:(FSNListViewNodeRep *)rep;
- (void)setRep:(FSNListViewNodeRep *)rep expanded:(BOOL)flag;
- (NSUInteger)depthOfRep:(FSNListViewNodeRep *)rep;
/* A change the file watcher reports in one of the expanded folders. */
- (void)expandedFolderChanged:(NSNotification *)notification;

@end


@interface FSNListViewDataSource (NSTableViewDataSource)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;

- (id)tableView:(NSTableView *)aTableView
          objectValueForTableColumn:(NSTableColumn *)aTableColumn
                                row:(NSInteger)rowIndex;

- (void)tableView:(NSTableView *)aTableView
            setObjectValue:(id)anObject
            forTableColumn:(NSTableColumn *)aTableColumn
                       row:(NSInteger)rowIndex;

- (BOOL)tableView:(NSTableView *)aTableView
	      writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard;

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation;

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation;

//
// NSTableView delegate methods
//
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification;

- (BOOL)tableView:(NSTableView *)aTableView
  shouldSelectRow:(NSInteger)rowIndex;

- (void)tableView:(NSTableView *)aTableView
  willDisplayCell:(id)aCell
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex;

- (void)tableView:(NSTableView *)tableView
            didClickTableColumn:(NSTableColumn *)tableColumn;

- (NSImage *)tableView:(NSTableView *)tableView
      dragImageForRows:(NSArray *)dragRows;

- (BOOL)tableView:(NSTableView *)aTableView
            shouldEditTableColumn:(NSTableColumn *)aTableColumn
                              row:(NSInteger)rowIndex;

@end


@interface FSNListViewDataSource (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode;
- (NSDictionary *)readNodeInfo;
- (NSMutableDictionary *)updateNodeInfo:(BOOL)ondisk;
- (void)reloadContents;
- (void)reloadFromNode:(FSNode *)anode;
- (FSNode *)baseNode;
- (FSNode *)shownNode;
- (BOOL)isShowingNode:(FSNode *)anode;
- (BOOL)isShowingPath:(NSString *)path;
- (void)sortTypeChangedAtPath:(NSString *)path;
- (void)nodeContentsWillChange:(NSDictionary *)info;
- (void)nodeContentsDidChange:(NSDictionary *)info;
- (void)watchedPathChanged:(NSDictionary *)info;
- (void)setShowType:(FSNInfoType)type;
- (void)setExtendedShowType:(NSString *)type;
- (FSNInfoType)showType;
- (id)repOfSubnode:(FSNode *)anode;
- (id)repOfSubnodePath:(NSString *)apath;
- (id)addRepForSubnode:(FSNode *)anode;
- (void)removeRepOfSubnode:(FSNode *)anode;
- (void)removeRepOfSubnodePath:(NSString *)apath;
- (void)unloadFromNode:(FSNode *)anode;
- (void)unselectOtherReps:(id)arep;
- (void)selectReps:(NSArray *)reps;
- (void)selectRepsOfSubnodes:(NSArray *)nodes;
- (void)selectRepsOfPaths:(NSArray *)paths;
- (void)selectAll;
- (void)scrollSelectionToVisible;
- (NSArray *)reps;
- (NSArray *)selectedReps;
- (NSArray *)selectedNodes;
- (NSArray *)selectedPaths;
- (void)selectionDidChange;
- (void)checkLockedReps;
- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)setLastShownNode:(FSNode *)anode;
- (BOOL)needsDndProxy;
- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (BOOL)validatePasteOfFilenames:(NSArray *)names
                          wasCut:(BOOL)cut;
- (void)stopRepNameEditing;

/* One NSDictionary per selected row, each with @"path" (NSString),
   @"rect" (NSValue-wrapped NSRect, the row's name column converted to
   screen coordinates) and @"image" (NSImage, its icon) - used to fly the
   selection to the Trash the way a drag there would look (Workspace
   -moveToTrash).  A row that cannot be resolved to a table row (unusual
   during any normal selection) is left out rather than reported with a
   zero rect. */
- (NSArray *)flightSourcesForSelectedReps;

/* The same sources for an arbitrary set of paths instead of the selection -
   what an external caller that was handed paths (Workspace
   -trashExternalPaths:) needs.  Only rows this list is currently showing
   are returned. */
- (NSArray *)flightSourcesForPaths:(NSArray *)paths;

/* The implementation both of the above share: one NSDictionary per rep. */
- (NSArray *)flightSourcesForReps:(NSArray *)reps;

@end


@interface FSNListViewDataSource (RepNameEditing)

- (void)setEditorAtRow:(int)row withMouseDownEvent: (NSEvent *)anEvent;

- (void)controlTextDidChange:(NSNotification *)aNotification;

- (void)controlTextDidEndEditing:(NSNotification *)aNotification;

@end


@interface FSNListViewDataSource (DraggingDestination)

- (BOOL)checkDraggingLocation:(NSPoint)loc;

- (NSDragOperation)checkReturnValueForRep:(FSNListViewNodeRep *)arep
                         withDraggingInfo:(id <NSDraggingInfo>)sender;

- (NSDragOperation)listViewDraggingEntered:(id <NSDraggingInfo>)sender;

- (NSDragOperation)listViewDraggingUpdated:(id <NSDraggingInfo>)sender;

- (void)listViewDraggingExited:(id <NSDraggingInfo>)sender;

- (BOOL)listViewPrepareForDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)listViewPerformDragOperation:(id <NSDraggingInfo>)sender;

- (void)listViewConcludeDragOperation:(id <NSDraggingInfo>)sender;

@end


@interface FSNFolderSizeCalculator : NSObject
{
  NSArray *paths;
  id <FSNFolderSizeCalculatorDelegate> delegate;   /* not retained */
  int cancelled;                                   /* read by the worker */
  BOOL finished;
}

- (id)initWithPaths:(NSArray *)folderPaths
           delegate:(id <FSNFolderSizeCalculatorDelegate>)aDelegate;

- (void)start;
- (void)cancel;
- (BOOL)isFinished;

/* The logical size of everything below path (symbolic links not followed,
 * other file systems not entered), stopping early when *stop becomes
 * nonzero.  Safe to call from any thread. */
+ (unsigned long long)sizeOfTreeAtPath:(NSString *)path stop:(const int *)stop;

@end


@interface FSNListViewNodeRep : NSObject <FSNodeRep>
{
  FSNode *node;
  NSImage *icon;
  NSImage *openicon;
  NSImage *lockedicon;
  NSImage *spopenicon;
  NSString *extInfoStr;
  NSColor *tagColor;

  BOOL isLocked;
  BOOL iconSelected;
  BOOL isOpened;
  BOOL wasOpened;
  BOOL nameEdited;
  BOOL isDragTarget;
  BOOL forceCopy;
  NSDragOperation negotiatedDragOp;

  /* NO between initForNode: and -decorate (lazy icon loading). */
  BOOL decorated;

  /* Values of the columns that need a stat, a bundle or the metadata
   * provider, read when first asked for; NSNull for "none". */
  NSMutableDictionary *lazyValues;

  FSNListViewDataSource *dataSource;
  FSNodeRep *fsnodeRep;
}

- (id)initForNode:(FSNode *)anode
       dataSource:(FSNListViewDataSource *)fsnds;

- (NSImage *)icon;

/* Load the icon image and tag color for the node (deferred from init so a
 * large directory fills lazily).  No-op when already decorated. */
- (void)decorate;

- (BOOL)isDecorated;

/* Forget the icons so that -decorate loads them again, at the size the data
 * source has by now. */
- (void)invalidateIcons;

/* The value behind a date last opened, version, comment or label column
 * (an NSDate, NSString or, for FSNListColumnTypeLabel, NSColor); nil when
 * there is none. */
- (id)lazyValueForColumnType:(NSInteger)type;

- (NSImage *)openIcon;

- (NSImage *)lockedIcon;

- (NSImage *)spatialOpenIcon;

- (BOOL)selectIcon:(BOOL)value;

- (BOOL)iconSelected;

- (NSColor *)tagColor;

- (NSRect)screenRect;

@end


@interface FSNListViewNodeRep (DraggingDestination)

- (NSDragOperation)repDraggingEntered:(id <NSDraggingInfo>)sender;

- (void)repConcludeDragOperation:(id <NSDraggingInfo>)sender;

@end


@interface FSNListViewNameEditor : NSTextField
{
  FSNode *node;
  int index;
}

- (void)setNode:(FSNode *)anode
    stringValue:(NSString *)str
          index:(int)idx;

- (FSNode *)node;

- (int)index;

@end


@interface FSNListView : NSTableView
{
  id dsource;
  NSString *charBuffer;
  NSTimeInterval lastKeyPressedTime;

  NSTimer *clickTimer;

  /* Scroll position asked for by the owner, held until the user scrolls */
  NSPoint _savedScroll;
  BOOL _hasSavedScroll;
  BOOL _applyingScroll;
  NSClipView *_observedClip;   /* not retained */
}

/* The scrolled position as Finder keeps it per folder (lsvp scrollPositionX/Y,
 * the same convention as the icon view): points from the left and from the top
 * edge of the content to the corner of the visible part.  Setting it works
 * before the rows are there too: it is applied again after every (re)load until
 * the user scrolls. */
- (NSPoint)scrollPosition;
- (void)setScrollPosition:(NSPoint)position;

- (id)initWithFrame:(NSRect)frameRect
    dataSourceClass:(Class)dsclass;

- (void)checkSize;

@end


@interface NSObject (FSNListViewDelegateMethods)

- (NSImage *)tableView:(NSTableView *)tableView
      dragImageForRows:(NSArray *)dragRows;

@end


@interface FSNListView (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode;
- (NSDictionary *)readNodeInfo;
- (NSMutableDictionary *)updateNodeInfo:(BOOL)ondisk;
- (void)reloadContents;
- (void)reloadFromNode:(FSNode *)anode;
- (FSNode *)baseNode;
- (FSNode *)shownNode;
- (BOOL)isSingleNode;
- (BOOL)isShowingNode:(FSNode *)anode;
- (BOOL)isShowingPath:(NSString *)path;
- (void)sortTypeChangedAtPath:(NSString *)path;
- (void)nodeContentsWillChange:(NSDictionary *)info;
- (void)nodeContentsDidChange:(NSDictionary *)info;
- (void)watchedPathChanged:(NSDictionary *)info;
- (void)setShowType:(FSNInfoType)type;
- (void)setExtendedShowType:(NSString *)type;
- (FSNInfoType)showType;
- (id)repOfSubnode:(FSNode *)anode;
- (id)repOfSubnodePath:(NSString *)apath;
- (id)addRepForSubnode:(FSNode *)anode;
- (void)removeRepOfSubnode:(FSNode *)anode;
- (void)removeRepOfSubnodePath:(NSString *)apath;
- (void)unloadFromNode:(FSNode *)anode;
- (void)unselectOtherReps:(id)arep;
- (void)selectReps:(NSArray *)reps;
- (void)selectRepsOfSubnodes:(NSArray *)nodes;
- (void)selectRepsOfPaths:(NSArray *)paths;
- (void)selectAll;
- (void)scrollSelectionToVisible;
- (NSArray *)reps;
- (NSArray *)selectedReps;
- (NSArray *)selectedNodes;
- (NSArray *)selectedPaths;
- (void)selectionDidChange;
- (void)checkLockedReps;
- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)setLastShownNode:(FSNode *)anode;
- (BOOL)needsDndProxy;
- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (BOOL)validatePasteOfFilenames:(NSArray *)names
                          wasCut:(BOOL)cut;
- (void)stopRepNameEditing;

/* Forwards to the data source's own -flightSourcesForSelectedReps (see
   FSNListViewDataSource (NodeRepContainer) above). */
- (NSArray *)flightSourcesForSelectedReps;

/* Forwards to the data source's own -flightSourcesForPaths: (see
   FSNListViewDataSource (NodeRepContainer) above). */
- (NSArray *)flightSourcesForPaths:(NSArray *)paths;

@end


@interface FSNListView (DraggingDestination)

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;

- (void)draggingExited:(id <NSDraggingInfo>)sender;

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;

@end


@interface NSDictionary (TableColumnSort)

- (NSComparisonResult)compareTableColumnInfo:(NSDictionary *)info;

@end

#endif // FSN_LIST_VIEW_H
