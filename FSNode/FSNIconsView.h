/* FSNIconsView.h
 *  
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
 * Date: March 2004
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


#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import <AppKit/NSTextField.h>
#import "FSNodeRep.h"
#import "FSNIconPlacement.h"

@class NSColor;
@class NSFont;
@class FSNode;
@class FSNIcon;
@class FSNIconNameEditor;
@class FSNIcon;
@class FSNIconNameEditor;
@class FSNIconItemData;

@interface FSNIconsView : NSView <NSTextFieldDelegate>
{
  FSNode *node;
  NSMutableArray *icons;
  FSNInfoType infoType;
  NSString *extInfoType;

  NSImage *verticalImage;
  NSImage *horizontalImage;

  FSNSelectionMask selectionMask;
  NSArray *lastSelection;

  FSNIconNameEditor *nameEditor;
  FSNIcon *editIcon;

  int iconSize;
  int labelTextSize;
  NSFont *labelFont;
  NSCellImagePosition iconPosition;

  NSSize gridSize;

  BOOL isDragTarget;
  BOOL forceCopy;
  NSDragOperation negotiatedDragOp;

  NSString *charBuffer;
  NSTimeInterval lastKeyPressedTime;

  NSColor *backColor;
  NSColor *textColor;
  NSColor *disabledTextColor;
  BOOL transparentSelection;

  // Cached grid cell dimensions (computed once, reused across tile calls + Clean Up)
  NSSize _cachedCellSize;
  CGFloat _cachedGapX;
  BOOL _gridCached;

  NSImage *backgroundImage;  // Background image for spatial views

  FSNodeRep *fsnodeRep;

  id <DesktopApplication> desktopApp;

  // Placement direction for Clean Up virtual grid enumeration
  FSNPlacementDirection _placementDirection;

  // DS_Store free positioning support for Mac interoperability
  NSMutableDictionary *customIconPositions; // filename -> NSValue(NSPoint) iloc top-left CENTER coords
  CGFloat dsStoreIconHeight;                // Icon height for coordinate conversion

  // Non-retained reference to the enclosing NSClipView being observed
  // for frame-change notifications.  Used to trigger tile on resize
  // even when NSClipView does not propagate resizeWithOldSuperviewSize.
  NSView *_observedClipView;

  // Content extent (max right/top edge of laid-out icons) reported by
  // -layoutIcons and consumed by -tile to size the document view.
  NSSize _contentExtent;
}

/* Layout policy: position every icon (setFrame:) and set _contentExtent to
 * the laid-out content's max right/top edge.  -tile owns the surrounding
 * mechanics (grid caching, document sizing, per-icon tile, scrolling) and
 * calls this.  One implementation serves every view: subclasses select a
 * policy through -isFlipped, -honorsSavedPositions, the iloc<->view mapping
 * and -gridOriginForLayout, not by overriding this method. */
- (void)layoutIcons;

/* Whether this view honors saved (.DS_Store/fdLocation) icon positions.
 * YES for position-honoring views (desktop, spatial); NO for the browser
 * icon view, which always auto-grids and reflows to the current width. */
- (BOOL)honorsSavedPositions;

/* Map an icon CENTER in this view's coordinates <-> a DS_Store iloc
 * (top-left) center.  The base view is bottom-left and flips about the
 * reference height; a flipped (spatial) view overrides both to the identity. */
- (NSPoint)ilocCenterForViewCenter:(NSPoint)center;
- (NSPoint)viewCenterForIlocCenter:(NSPoint)iloc;

/* Grid geometry in this view's own coordinates, flip-aware: rows grow
 * visually downward from gridOriginForLayout regardless of the coordinate
 * model.  Every operation that computes or assigns a grid position (layout,
 * Clean Up, first-free-cell, occupancy) goes through this pair so a layout
 * policy only has to define the coordinate model once. */
- (NSPoint)centerForGridCell:(FSNGridCell)cell
                    cellSize:(NSSize)cellSize
                        gapX:(CGFloat)gapX
                      origin:(NSPoint)gridOrigin;
- (FSNGridCell)gridCellForCenter:(NSPoint)center
                        cellSize:(NSSize)cellSize
                            gapX:(CGFloat)gapX
                          origin:(NSPoint)gridOrigin;

/* Placement direction access (used by Clean Up virtual grid) */
- (void)setPlacementDirection:(FSNPlacementDirection)direction;
- (FSNPlacementDirection)placementDirection;

/* Override point for subclasses to provide a custom grid origin.
 * Default: (X_MARGIN, viewHeight - Y_MARGIN).  The desktop subclass
 * overrides this to account for Dock position and menu bar. */
- (NSPoint)gridOriginForLayout;

/* Visible content width/height for layout, derived from the enclosing scroll
 * view (falls back to the window content view / own bounds).  Used by layout
 * policies to size the grid and canvas. */
- (CGFloat)windowContentWidthForLayout;
- (CGFloat)visibleContentHeightForLayout;

/* Cleanup and sort operations (Finder-compatible) */
- (void)cleanupIconPositions;

- (void)sortIcons;

- (void)calculateGridSize;

- (void)tile;

- (void)scrollIconToVisible:(FSNIcon *)icon;

- (NSString *)selectIconWithPrefix:(NSString *)prefix;

- (void)selectIconInPrevLine;

- (void)selectIconInNextLine;

- (void)selectPrevIcon;

- (void)selectNextIcon;

// DS_Store free positioning support for Mac interoperability
- (void)setCustomIconPositions:(NSDictionary *)positions;
- (NSDictionary *)customIconPositions;
- (NSArray *)icons;

/* Free-positioning icon repositioning */
- (void)repositionIcon:(FSNIcon *)icon toCenterPoint:(NSPoint)point;

/* Batch reposition — moves many icons at once, tiles once, persists once */
- (void)batchRepositionIcons:(NSArray *)icons toCenterPoints:(NSArray *)points;

/* Persist the auto-assigned positions of icons just added to an open window
 * (call after -tile).  Honor-gated and empty-safe; browser views no-op. */
- (void)persistStoredPositionsForIcons:(NSArray *)iconList;

// DS_Store tag colors and comments support
- (void)setTagColorsFromDictionary:(NSDictionary *)tagDict;
- (void)setCommentsFromDictionary:(NSDictionary *)commentsDict;

@end


@interface FSNIconsView (NodeRepContainer)

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
- (void)setIconSize:(int)size;
- (int)iconSize;
- (void)setLabelTextSize:(int)size;
- (int)labelTextSize;
- (void)setIconPosition:(NSCellImagePosition)pos;
- (NSCellImagePosition)iconPosition;
- (void)updateIcons;
- (id)repOfSubnode:(FSNode *)anode;
- (id)repOfSubnodePath:(NSString *)apath;
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
- (void)selectAll:(id)sender;
- (void)scrollSelectionToVisible;
- (NSArray *)reps;
- (NSArray *)selectedReps;
- (NSArray *)selectedNodes;
- (NSArray *)selectedPaths;
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
- (void)setBackgroundColor:(NSColor *)acolor;
- (NSColor *)backgroundColor;
- (void)setBackgroundImage:(NSImage *)image;
- (NSImage *)backgroundImage;
- (void)setTextColor:(NSColor *)acolor;
- (NSColor *)textColor;
- (NSColor *)disabledTextColor;

@end


@interface FSNIconsView (DraggingDestination)

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;

- (void)draggingExited:(id <NSDraggingInfo>)sender;

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;

@end


@interface FSNIconsView (IconNameEditing)

- (void)updateNameEditor;

- (void)setNameEditorForRep:(id)arep;

- (void)stopRepNameEditing;

- (BOOL)canStartRepNameEditing;

- (void)controlTextDidChange:(NSNotification *)aNotification;

- (void)controlTextDidEndEditing:(NSNotification *)aNotification;

@end
