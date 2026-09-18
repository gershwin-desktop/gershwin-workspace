/* FSNIcon.h
 *  
 * Copyright (C) 2004-2022 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale <enrico@imago.ro>
 *          Riccardo Mottola <rm@gnu.org>
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

#ifndef FSN_ICON_H
#define FSN_ICON_H

#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>
#import "FSNodeRep.h"
#import "FSNIconLoader.h"
#import "FSNSpringLoader.h"

@class NSImage;
@class NSFont;
@class NSBezierPath;
@class NSTextField;
@class FSNode;
@class FSNTextCell;
@class FSNIconItemData;

@interface FSNIcon : NSView <FSNodeRep, FSNDecorationClient, FSNSpringFlashing>
{
  FSNode *node;
  NSString *hostname;
  NSArray *selection;
  NSString *selectionTitle;
  NSString *extInfoType;

  NSImage *icon;
  NSImage *selectedicon;
  NSImage *drawicon;
  /* The look a folder rested in when it started to flash before springing
     open; not retained, it is icon or selectedicon. */
  NSImage *springRestingIcon;
  int iconSize;
  NSRect icnBounds;
  NSPoint icnPoint;
  NSCellImagePosition icnPosition;

  NSRect brImgBounds;
    
  NSBezierPath *highlightPath;
  NSRect hlightRect;
  
  NSTrackingRectTag trectTag;
  
  FSNTextCell *label;
  NSRect labelRect;
  BOOL drawLabelBackground;
  NSColor *labelFrameColor;
  FSNTextCell *infolabel;
  NSRect infoRect;
  FSNInfoType showType;

  NSUInteger gridIndex;
  
  BOOL isSelected;
  BOOL selectable;
  BOOL suppressSelectionDrawing;
  
  BOOL isOpened;
  /* YES while the icon follows the pointer in a free-position move. */
  BOOL beingDragged;
  /* The ghost drawn while beingDragged, rendered once for the whole move. */
  NSImage *draggedLook;
  /* YES while a rubber band being dragged out would select the icon. */
  BOOL selectionPreview;
  
  BOOL nameEdited;
  BOOL isLeaf;
  BOOL isLocked;

  /* NO between initForNode: and -decorate (lazy icon loading). */
  BOOL decorated;
  
  NSTimeInterval editstamp;  

  BOOL dndSource;
  BOOL acceptDnd;
  BOOL slideBack;
  int dragdelay;
  BOOL isDragTarget;
  /* YES while a drag sits in this icon's frame but outside its image and
     name, i.e. on the view behind it, which then gets the drag messages. */
  BOOL dragProxied;
  BOOL forceCopy;
  NSDragOperation negotiatedDragOp;
  BOOL onApplication;
  BOOL onSelf;
  
  NSView <FSNodeRepContainer> *container;
  
  FSNodeRep *fsnodeRep;
  
  // DS_Store label color support
  NSColor *tagColor;        // Label/tag color from DS_Store (lclr)
  BOOL labelChecked;        // YES once metadata has been probed for a label
  NSString *spotlightComment;  // Spotlight comment from DS_Store (cmmt)

  // Git change-count badge: the number drawn as a red pill in the icon's
  // top-right corner (>= 48px icons only).  -1 while pending, >=0 once known.
  NSInteger gitBadgeCount;

  // Pixel placement data
  FSNIconItemData *_placementData;
}

@property (nonatomic, retain) FSNIconItemData *placementData;

+ (NSImage *)branchImage;

- (id)initForNode:(FSNode *)anode
     nodeInfoType:(FSNInfoType)type
     extendedType:(NSString *)exttype
         iconSize:(int)isize
     iconPosition:(NSUInteger)ipos
        labelFont:(NSFont *)lfont
        textColor:(NSColor *)tcolor
        gridIndex:(NSUInteger)gindex
        dndSource:(BOOL)dndsrc
        acceptDnd:(BOOL)dndaccept
        slideBack:(BOOL)slback;

- (void)setSelectable:(BOOL)value;

- (void)setSuppressSelectionDrawing:(BOOL)flag;

/* Load the icon image for the node (deferred from init so a large
 * directory fills lazily).  No-op when already decorated. */
- (void)decorate;

- (BOOL)isDecorated;

- (NSRect)iconBounds;

/* Image and name together: what the user sees of the node, and so what a
   rubber-band selection has to touch to catch it. */
- (NSRect)nodeBounds;

/* Whether the point (in this icon's own coordinates) is on what stands for
   the node - the image, or the name beside or below it.  The padding that
   fills the rest of the frame does not. */
- (BOOL)pointIsOnNode:(NSPoint)selfPoint;

/* Show the open-folder image while a drag that has not left the icon view
   hovers this icon, so the move into the folder is announced before the
   mouse is released. */
- (void)setDropHighlighted:(BOOL)flag;

/* Ghost this icon while it is being moved, so whatever it passes over - a
   folder opening up to take it - stays readable underneath. */
- (void)setBeingDragged:(BOOL)flag;

/* A picture of the icon as it looks at rest - full image, name, no
 * selection plate - to drag around. */
- (NSImage *)restingLookImage;

/* Draw the icon as selected without selecting it, while a rubber band that
   would select it is still being dragged out.  Only marks the icon for
   redisplay; the band's own loop does the drawing. */
- (void)setSelectionPreview:(BOOL)flag;

- (void)tile;

/* The width the label would need to draw its full (untruncated) title,
 * including the label margin.  Used by the container to give a wide label
 * a frame up to 2x the grid cell so the text is not clipped to one cell. */
- (float)labelTextWidth;

// DS_Store tag/label color support
- (void)setTagColor:(NSColor *)color;
- (NSColor *)tagColor;
- (void)setSpotlightComment:(NSString *)comment;
- (NSString *)spotlightComment;

@end


@interface FSNIcon (DraggingSource)

- (void)startExternalDragOnEvent:(NSEvent *)event
                 withMouseOffset:(NSSize)offset;

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag;

- (void)draggedImage:(NSImage *)anImage 
	     endedAt:(NSPoint)aPoint 
	   deposited:(BOOL)flag;

@end


@interface FSNIcon (DraggingDestination)

/* Whether a drag at this point is aimed at the node this icon shows.  The
   image and the name are; the padding around them is not - there the icon
   steps aside and the view behind it handles the drag.  Override to YES
   where the whole tile stands for the node, as in the Dock. */
- (BOOL)draggingPointIsOnNode:(id <NSDraggingInfo>)sender;

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;

- (void)draggingExited:(id <NSDraggingInfo>)sender;

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;

/* Carry out a drop on this icon: hand the paths to the application it stands
   for, or run the named file operation with its folder as the destination.
   Used by -concludeDragOperation: and by a drop that never left the icon
   view, which the drag machinery therefore never hears about. */
- (void)openDroppedPaths:(NSArray *)paths;

- (void)fileDroppedPaths:(NSArray *)paths operation:(NSString *)operation;

@end


@interface FSNIconNameEditor : NSTextField
{
  FSNode *node;
  NSView <FSNodeRepContainer> *container;
}  

- (void)setNode:(FSNode *)anode 
    stringValue:(NSString *)str;

- (FSNode *)node;


@end

#endif // FSN_ICON_H
