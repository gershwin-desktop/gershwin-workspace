/* FSNBrowser.h
 *  
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola <rm@gnu.org>
 * Date: July 2004
 *
 * This file is part of the GNUstep Workspace application
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

#ifndef FSN_BROWSER_H
#define FSN_BROWSER_H

#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "FSNArrangement.h"
#import "FSNPreviewProvider.h"
#import "FSNColumnViewOptions.h"
#import "FSNRenameController.h"

@class FSNBrowserColumn;
@class FSNBrowserCell;
@class FSNCellNameEditor;
@class NSScroller;

@interface FSNBrowser : NSView <NSTextFieldDelegate>
{
  FSNode *baseNode;
  FSNInfoType infoType;
  NSString *extInfoType;
  
  NSArray *lastSelection;
  NSMutableArray *columns;
  FSNBrowserCell *cellPrototype;
  NSScroller *scroller;
  BOOL skipUpdateScroller;
  int updateViewsLock;

  FSNCellNameEditor *nameEditor;

  BOOL cellsIcon;
  /* Whether rows and columns take drops and start drags - separate from
     cellsIcon, which only picks tall icon rows over single-line ones. */
  BOOL acceptsDnd;
  BOOL selColumn;

  BOOL isLoaded;

  /* Last-seen filename-extension display mode: defaultsChanged: only needs
   * to relabel cells when it actually changes. */
  GSFilenameExtensionDisplayMode lastDisplayMode;
    
  NSInteger visibleColumns;
  NSInteger lastColumnLoaded;
  NSInteger firstVisibleColumn;
  NSInteger lastVisibleColumn;	
  int currentshift;

  NSSize columnSize;
  NSInteger fontSize;
  BOOL simulatingDoubleClick;
  /* Times out the simulated double-click above; invalidated in -dealloc so
   * a closed browser cannot have it fire into a freed instance. */
  NSTimer *doubleClickTimer;
  float mousePointX;
  float mousePointY;
  
  NSColor *backColor;
	
  id viewer;  
  id manager;
  id <DesktopApplication> desktopApp;
  FSNodeRep *fsnodeRep;
  id _observedClipView;

  /* Column view options (see the ViewOptions category). */
  FSNColumnViewOptions *options;
  BOOL showsPreviewColumn;
  FSNIconsArrangement arrangement;
  CGFloat defaultColumnWidth;
  NSMutableDictionary *columnWidths;
}

- (id)initWithBaseNode:(FSNode *)bsnode
		    visibleColumns:(int)vcols 
              scroller:(NSScroller *)scrl
            cellsIcons:(BOOL)cicns
            acceptsDnd:(BOOL)dnd
         editableCells:(BOOL)edcells
       selectionColumn:(BOOL)selcol;

- (void)setBaseNode:(FSNode *)node;

- (void)setUsesCellsIcons:(BOOL)cicns;
- (void)setUsesSelectionColumn:(BOOL)selcol;
- (void)setVisibleColumns:(NSInteger)vcols;
- (NSInteger)visibleColumns;

- (void)showSubnode:(FSNode *)node;
- (void)showSelection:(NSArray *)selection;
- (void)showPathsSelection:(NSArray *)selpaths;

- (void)loadColumnZero;
- (FSNBrowserColumn *)createEmptyColumn;
- (void)addAndLoadColumnForNode:(FSNode *)node;
- (void)addFillingColumn;
- (void)unloadFromColumn:(NSInteger)column;
- (void)reloadColumnWithNode:(FSNode *)anode;
- (void)reloadColumnWithPath:(NSString *)cpath;
- (void)reloadFromColumn:(FSNBrowserColumn *)col;
- (void)reloadFromColumnWithNode:(FSNode *)anode;
- (void)reloadFromColumnWithPath:(NSString *)cpath;
- (void)setLastColumn:(int)column;

- (void)selectRow:(NSInteger)row inColumn:(NSInteger)column;

- (void)tile;
- (void)releaseScroller;
- (void)scrollViaScroller:(NSScroller *)sender;
- (void)updateScroller;
- (void)scrollColumnsLeftBy:(int)shiftAmount;
- (void)scrollColumnsRightBy:(int)shiftAmount;
- (void)scrollColumnToVisible:(NSInteger)column;
- (void)moveLeft;
- (void)moveRight;
- (void)setShift:(int)s;

- (FSNode *)nodeOfLastColumn;
- (NSString *)pathToLastColumn;
- (NSArray *)selectionInColumnBeforeColumn:(FSNBrowserColumn *)col;
- (void)selectCellsWithNames:(NSArray *)names 
            inColumnWithPath:(NSString *)cpath
                  sendAction:(BOOL)act;
- (void)selectAllInLastColumn;
- (void)notifySelectionChange:(NSArray *)newsel;
- (void)synchronizeViewer;

- (void)addCellsWithNames:(NSArray *)names 
         inColumnWithPath:(NSString *)cpath;
- (void)removeCellsWithNames:(NSArray *)names 
            inColumnWithPath:(NSString *)cpath;

- (NSInteger)firstVisibleColumn;
- (NSInteger)lastColumnLoaded;
- (NSInteger)lastVisibleColumn;
- (FSNBrowserColumn *)selectedColumn;
- (FSNBrowserColumn *)lastLoadedColumn;
- (FSNBrowserColumn *)columnWithNode:(FSNode *)anode;
- (FSNBrowserColumn *)columnWithPath:(NSString *)cpath;
- (FSNBrowserColumn *)columnBeforeColumn:(FSNBrowserColumn *)col;
- (FSNBrowserColumn *)columnAfterColumn:(FSNBrowserColumn *)col;

- (void)clickInColumn:(FSNBrowserColumn *)col;
- (void)clickInMatrixOfColumn:(FSNBrowserColumn *)col;
- (void)doubleClickInMatrixOfColumn:(FSNBrowserColumn *)col;
- (void)doubleClikTimeOut:(id)sender;

@end


/* Finder's column view options.  They are the same for every column view
 * (E30): a browser starts with FSNColumnViewOptions and follows its
 * changes.  The setters here change this browser alone - what the global
 * options do through them, and what a plain drag of a column's resize
 * handle does for this window's session (E32). */
@interface FSNBrowser (ViewOptions)

/* The text size of the names, held to Finder's 10 to 16. */
+ (int)clampedLabelTextSize:(int)size;
- (void)setLabelTextSize:(int)size;

/* "Show icons": without, the rows show the names alone. */
- (void)setShowsIcons:(BOOL)flag;
- (BOOL)showsIcons;

/* "Show icon preview": an image file shows its own picture rather than the
 * icon of its type. */
- (void)setShowsIconPreview:(BOOL)flag;
- (BOOL)showsIconPreview;

/* "Show preview column": a single selected file is shown large, with what
 * it is, in the column after it. */
- (void)setShowsPreviewColumn:(BOOL)flag;
- (BOOL)showsPreviewColumn;

/* "Arrange by", in the orders of the icon view; None keeps the folder's own
 * sort order. */
- (void)setArrangement:(FSNIconsArrangement)value;
- (FSNIconsArrangement)arrangement;

/* The width of every column, in whole points, at least
 * FSNBrowserMinimumColumnWidth.  Setting it drops the widths of single
 * columns. */
- (void)setDefaultColumnWidth:(CGFloat)width;
- (CGFloat)defaultColumnWidth;

/* The width of one column (by its index from the left, 0 for the folder
 * the browser starts at); kept until the default width changes. */
- (void)setWidth:(CGFloat)width forColumnAtIndex:(NSInteger)index;
- (CGFloat)widthOfColumnAtIndex:(NSInteger)index;

/* What the preview column shows of a file comes from this provider (the
 * application's file rendering); without one it shows the file's icon.
 * Retained. */
+ (void)setPreviewProvider:(id<FSNPreviewProvider>)provider;
+ (id<FSNPreviewProvider>)previewProvider;

@end


@interface FSNBrowser (NodeRepContainer)

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
- (int)iconSize;
- (int)labelTextSize;
- (NSCellImagePosition)iconPosition;
- (void)updateIcons;
- (id)repOfSubnode:(FSNode *)anode;
- (id)repOfSubnodePath:(NSString *)apath;
- (NSRect)screenRectForCell:(FSNBrowserCell *)aCell;
- (id)addRepForSubnode:(FSNode *)anode;
- (id)addRepForSubnodePath:(NSString *)apath;
- (void)removeRepOfSubnode:(FSNode *)anode;
- (void)removeRepOfSubnodePath:(NSString *)apath;
- (void)removeRep:(id)arep;
- (void)unloadFromNode:(FSNode *)anode;
- (void)repSelected:(id)arep;
- (void)unselectOtherReps:(id)arep;
- (void)selectReps:(NSArray *)reps;
- (void)selectRepsOfSubnodes:(NSArray *)nodes;
- (void)selectRepsOfPaths:(NSArray *)paths;
- (void)selectAll;
- (NSArray *)reps;
- (NSArray *)selectedReps;
- (NSArray *)selectedNodes;
- (NSArray *)selectedPaths;

/* One NSDictionary per selected cell, each with @"path" (NSString),
   @"rect" (NSValue-wrapped NSRect, from -screenRectForCell:) and @"image"
   (NSImage, the cell's own icon) - used to fly the selection to the Trash
   the way a drag there would look (Workspace -moveToTrash).  A cell that
   cannot be resolved to a screen rect (unusual during any normal
   selection) is left out rather than reported with a zero rect. */
- (NSArray *)flightSourcesForSelectedReps;

/* The same sources for an arbitrary set of paths instead of the selection -
   what an external caller that was handed paths (Workspace
   -trashExternalPaths:) needs.  Every loaded column is searched, since one
   browser shows many folders at once; cells that are not on screen are left
   out. */
- (NSArray *)flightSourcesForPaths:(NSArray *)paths;

/* The implementation both of the above share: one NSDictionary per cell. */
- (NSArray *)flightSourcesForCells:(NSArray *)reps;

- (void)selectionDidChange;
- (void)checkLockedReps;
- (void)setSelectionMask:(FSNSelectionMask)mask;
- (FSNSelectionMask)selectionMask;
- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)restoreLastSelection;
- (void)setLastShownNode:(FSNode *)anode;
- (BOOL)needsDndProxy;
- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (BOOL)validatePasteOfFilenames:(NSArray *)names
                       wasCut:(BOOL)cut;
- (NSColor *)backgroundColor;
- (NSColor *)textColor;
- (NSColor *)disabledTextColor;

@end


@interface FSNBrowser (IconNameEditing) <FSNRenameHost>

- (void)setEditorForCell:(FSNBrowserCell *)cell 
                inColumn:(FSNBrowserColumn *)col;

/* FSNRenameHost: the editor over the name of a cell of any column. */
- (NSTextField *)nameEditorForRenamingRep:(id)rep;
                
- (void)stopCellEditing;                

- (void)stopRepNameEditing;                       
                
- (void)controlTextDidChange:(NSNotification *)aNotification;

- (void)controlTextDidEndEditing:(NSNotification *)aNotification;

@end

#endif // FSN_BROWSER_H
