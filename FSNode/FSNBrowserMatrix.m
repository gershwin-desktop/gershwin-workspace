/* FSNBrowserMatrix.m
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

#include <math.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "FSNBrowserMatrix.h"
#import "FSNBrowserCell.h"
#import "FSNBrowserColumn.h"
#import "FSNIcon.h"
#import "FSNFunctions.h"
#import "FSNBrowser.h"
#import "FSNRenamePolicy.h"
#import "FSNRenameController.h"

/* Forward declarations for methods on Workspace resolved at runtime
 * via NSClassFromString to avoid circular library dependencies. */
@interface NSObject (FSNBrowserMatrixWorkspaceMethods)
- (NSMenu *)contextMenuForNodes:(NSArray *)nodes
                     openTarget:(id)openTarget
                  openWithTarget:(id)openWithTarget
                     infoTarget:(id)infoTarget
                duplicateTarget:(id)duplicateTarget
                    aliasTarget:(id)aliasTarget
                  recycleTarget:(id)recycleTarget
                    ejectTarget:(id)ejectTarget
                     openAction:(SEL)openAction
                duplicateAction:(SEL)duplicateAction
                   aliasAction:(SEL)aliasAction
                  recycleAction:(SEL)recycleAction
                    ejectAction:(SEL)ejectAction
               includeOpenWith:(BOOL)includeOpenWith;
- (NSMenu *)emptySpaceContextMenuForViewer:(id)viewer;
@end


@implementation FSNBrowserMatrix

- (void)dealloc
{
  RELEASE (selectionModel);
  [super dealloc];
}

- (id)initInColumn:(FSNBrowserColumn *)col
         withFrame:(NSRect)frameRect
              mode:(NSMatrixMode)aMode
         prototype:(FSNBrowserCell *)aCell
      numberOfRows:(NSInteger)numRows
   numberOfColumns:(NSInteger)numColumns
         acceptDnd:(BOOL)dnd
{
  self = [super initWithFrame: frameRect mode: aMode prototype: aCell
		 numberOfRows: numRows numberOfColumns: numColumns];

  if (self)
    {
      column = col;
      mouseFlags = 0;
      dndTarget = nil;
      acceptDnd = dnd;
      if (acceptDnd)
	{
	  [self registerForDraggedTypes: [NSArray arrayWithObjects:
						    NSFilenamesPboardType,
						  @"GWLSFolderPboardType",
						  @"GWRemoteFilenamesPboardType",
						  nil]];
	}
      selectionModel = [[FSNSelectionModel alloc] initWithStyle: FSNSelectionStyleList];
      [selectionModel setDelegate: self];
    }

  return self;
}

#pragma mark - Selection

- (NSString *)selectionModel:(FSNSelectionModel *)model nameOfItem:(id)item
{
  return [[(FSNBrowserCell *)item node] name];
}

- (void)syncSelectionModel
{
  [selectionModel setItems: [self cells]];
  [selectionModel setSelectedItems: [self selectedCells]];
}

/* Selects the cells the model chose; YES when that changed anything. */
- (BOOL)applySelectionModel
{
  NSArray *want = [selectionModel selectedItems];
  NSArray *have = [self selectedCells];
  BOOL same = ([want count] == [have count]);
  NSUInteger i;
  id cursor;

  for (i = 0; same && i < [want count]; i++)
    same = ([have indexOfObjectIdenticalTo: [want objectAtIndex: i]] != NSNotFound);

  if (same == NO)
    {
      [self deselectAllCells];
      for (i = 0; i < [want count]; i++)
        [self selectCell: [want objectAtIndex: i]];
    }

  cursor = [selectionModel cursor];
  if (cursor != nil && [selectionModel isItemSelected: cursor])
    {
      NSInteger row, col;

      if ([self getRow: &row column: &col ofCell: cursor])
        [self scrollCellToVisibleAtRow: row column: col];
    }
  return (same == NO);
}

/* Runs one keyboard decision of the selection model; the browser then
   shows the column of what is selected, as after a click. */
- (void)performSelectionKey:(BOOL (^)(FSNSelectionModel *model))step
{
  [self syncSelectionModel];
  if (step(selectionModel))
    {
      [column stopCellEditing];
      if ([self applySelectionModel])
        [self sendAction];
    }
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];
  NSUInteger flags = [theEvent modifierFlags];
  BOOL extend = ((flags & NSShiftKeyMask) != 0);
  unichar character = ([characters length] > 0) ? [characters characterAtIndex: 0] : 0;

  if (acceptDnd == NO)
    {
      [super keyDown: theEvent];
      return;
    }

  if (flags & (NSCommandKeyMask | NSControlKeyMask))
    {
      /* Command-arrows open and go up; NSMatrix would only move the
	 selection with them, so they go straight to the browser. */
      if (character >= NSUpArrowFunctionKey && character <= NSRightArrowFunctionKey)
        [[self nextResponder] keyDown: theEvent];
      else
        [super keyDown: theEvent];
      return;
    }

  switch (character)
    {
    case NSUpArrowFunctionKey:
    case NSDownArrowFunctionKey:
      if (flags & NSAlternateKeyMask)
        {
          [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
            return (character == NSUpArrowFunctionKey) ? [model selectFirstItem]
                                                       : [model selectLastItem];
          }];
          return;
        }
      [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
        return [model moveInDirection: (character == NSUpArrowFunctionKey)
                                       ? FSNSelectionDirectionUp : FSNSelectionDirectionDown
                               extend: extend];
      }];
      return;

    /* Home and End only scroll; the selection stays. */
    case NSHomeFunctionKey:
    case NSEndFunctionKey:
      {
        NSRect b = [self bounds];
        BOOL atMaxY = ((character == NSHomeFunctionKey) != [self isFlipped]);

        [self scrollRectToVisible: NSMakeRect(NSMinX(b), atMaxY ? NSMaxY(b) - 1 : NSMinY(b), 1, 1)];
      }
      return;

    /* Return renames and Option-Return opens; the browser decides for
       every column (NSMatrix would only start editing a cell). */
    case NSCarriageReturnCharacter:
    case NSEnterCharacter:
      [[column browser] keyDown: theEvent];
      return;

    /* Tab walks the names of this column instead of leaving it. */
    case NSTabCharacter:
    case NSBackTabCharacter:
      [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
        return [model selectNextInNameOrder: (character == NSTabCharacter && extend == NO)];
      }];
      return;

    default:
      break;
    }

  /* Typing selects in the column that has the focus. Space belongs to the
     window (it looks inside the selection). */
  if (character > 0x20 && character < 0xF700)
    {
      NSString *typed = characters;
      NSTimeInterval when = [theEvent timestamp];

      [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
        return [model typeSelect: typed atTime: when];
      }];
      return;
    }

  [super keyDown: theEvent];
}

- (void)visibleCellsNodes:(NSArray **)nodes
          scrollTuneSpace:(float *)tspace
{
  NSArray *cells = [self cells];

  if (cells && [cells count])
    {
      NSRect vr = [self visibleRect];
      float ylim = vr.origin.y + vr.size.height - [self cellSize].height;
      NSMutableArray *vnodes = [NSMutableArray array];
      BOOL found = NO;
      NSUInteger i;

      for (i = 0; i < [cells count]; i++)
	{
	  NSRect cr = [self cellFrameAtRow: i column: 0];

	  if ((cr.origin.y >= vr.origin.y) && (cr.origin.y <= ylim))
	    {
	      if (found == NO) {
		*tspace = cr.origin.y - vr.origin.y;
		found = YES;
	      }
	      [vnodes addObject: [[cells objectAtIndex: i] node]];
	    }
	}

      if ([vnodes count])
	{
	  *nodes = vnodes;
	}
    }
}

- (NSRange)visibleRowRange
{
  NSRange range = NSMakeRange(0, 0);
  /* -cells copies every cell into a fresh NSArray, which is disproportionate
   * just to learn the row count; -numberOfRows reads the same ivar -cells
   * would have counted, without the O(rows) allocation. This method is now
   * on the drawRect: hot path (see -[FSNBrowserMatrix drawRect:]), so that
   * allocation would otherwise run on every single-row redraw. */
  NSInteger rows = [self numberOfRows];

  if (rows > 0)
    {
      NSRect vr = [self visibleRect];
      float rowh = [self cellSize].height;
      NSUInteger count = (NSUInteger)rows;
      NSUInteger first, last, i;

      if (rowh <= 0)
        {
          return range;
        }

      first = (NSUInteger)(vr.origin.y / rowh);
      last = (NSUInteger)((vr.origin.y + vr.size.height) / rowh);

      if (first >= count)
        {
          return range;
        }

      if (last >= count)
        {
          last = count - 1;
        }

      /* Include rows partially sticking out of the visible rect. */
      for (i = first; i > 0; i--)
        {
          NSRect fr = [self cellFrameAtRow: i column: 0];
          if (NSMaxY(fr) <= vr.origin.y)
            {
              break;
            }
          first = i - 1;
        }

      for (i = ((last + 1 < count) ? last + 1 : last); i < count; i++)
        {
          NSRect fr = [self cellFrameAtRow: i column: 0];
          if (fr.origin.y >= NSMaxY(vr))
            {
              break;
            }
          last = i;
        }

      range = NSMakeRange(first, last - first + 1);
    }

  return range;
}

- (void)scrollToFirstPositionCell:(id)aCell withScrollTune:(float)vtune
{
  NSRect vr, cr;
  NSInteger row, col;

  vr = [self visibleRect];

  [self getRow: &row column: &col ofCell: aCell];
  cr = [self cellFrameAtRow: row column: col];
  cr.size.height = vr.size.height - vtune;

  [self scrollRectToVisible: cr];
}

- (void)selectIconOfCell:(id)aCell
{
  FSNBrowserCell *cell = (FSNBrowserCell *)aCell;

  if ([cell selectIcon])
    {
      NSRect cellFrame;
      NSInteger row, col;

      [self getRow: &row column: &col ofCell: aCell];
      cellFrame = [self cellFrameAtRow: row column: col];
      [self setNeedsDisplayInRect: cellFrame];
    }

  [self unSelectIconsOfCellsDifferentFrom: cell];
}

- (void)unSelectIconsOfCellsDifferentFrom:(id)aCell
{
  NSArray *cells = [self cells];
  NSUInteger i = 0;

  for (i = 0; i < [cells count]; i++)
    {
      FSNBrowserCell *c = [cells objectAtIndex: i];

      if (c != aCell)
	{
	  if ([c unselectIcon])
	    {
	      NSRect cellFrame;
	      NSInteger row, col;

	      [self getRow: &row column: &col ofCell: c];
	      cellFrame = [self cellFrameAtRow: row column: col];
	      [self setNeedsDisplayInRect: cellFrame];
	    }
	}
    }
}

- (NSUInteger)mouseFlags
{
  return mouseFlags;
}

- (void)setMouseFlags:(NSUInteger)flags
{
  mouseFlags = flags;
}

- (void)mouseDown:(NSEvent*)theEvent
{
  NSPoint lastLocation;
  NSInteger row, col;
  FSNBrowserCell *cell;
  unsigned modifiers;
  BOOL wasOnlySelected;
  BOOL onIcon;
  NSRect rect;
  NSEvent *nextEvent;

  mouseFlags = [theEvent modifierFlags];

  if (acceptDnd == NO)
    {
      [super mouseDown: theEvent];
      return;
    }

  if (([self numberOfRows] == 0) || ([self numberOfColumns] == 0))
    {
      [super mouseDown: theEvent];
      return;
    }

  /* A second press (the second click of a double click) opens rather
     than renames; any press ends editing a name. */
  [[FSNRenameController sharedController] cancelScheduledRename];
  [[FSNRenameController sharedController] commitActiveEditing];

  if ([theEvent clickCount] >= 2)
    {
      [self sendDoubleAction];
      return;
    }

  lastLocation = [self convertPoint: [theEvent locationInWindow] fromView: nil];

  if ([self getRow: &row column: &col forPoint: lastLocation] == NO)
    {
      [super mouseDown: theEvent];
      return;
    }

  cell = [[self cells] objectAtIndex: row];
  if ([cell isEnabled] == NO)
    return;

  modifiers = FSNSelectionModifiersFromEventFlags([theEvent modifierFlags]);

  /* Control-click is the context menu, which a one-button mouse has no
     other way to ask for; like a right click it leaves the selection. */
  if (modifiers & FSNSelectionModifierControl)
    {
      NSEvent *menuEvent = [NSEvent mouseEventWithType: NSRightMouseDown
                                              location: [theEvent locationInWindow]
                                         modifierFlags: [theEvent modifierFlags]
                                             timestamp: [theEvent timestamp]
                                          windowNumber: [theEvent windowNumber]
                                               context: [theEvent context]
                                           eventNumber: [theEvent eventNumber]
                                            clickCount: 1
                                              pressure: [theEvent pressure]];
      NSMenu *menu = [self menuForEvent: menuEvent];

      if (menu != nil)
        [NSMenu popUpContextMenu: menu withEvent: menuEvent forView: self];
      return;
    }

  wasOnlySelected = ([[self selectedCells] count] == 1
                     && [[self selectedCells] indexOfObjectIdenticalTo: cell] != NSNotFound);

  [[self window] makeFirstResponder: self];
  [self syncSelectionModel];
  [selectionModel mouseDownOnItem: cell modifiers: modifiers];
  [self applySelectionModel];
  [self sendAction];

  /* A modifier click that deselected the cell is done. */
  if ([selectionModel isItemSelected: cell] == NO)
    return;

  rect = [self cellFrameAtRow: row column: col];
  rect.size.width = [cell iconSize];
  rect.size.height = [cell iconSize];
  onIcon = NSPointInRect(lastLocation, rect);

  nextEvent = FSNNextMouseUpOrDraggedEvent([self window]);

  if ([nextEvent type] == NSLeftMouseDragged)
    {
      [selectionModel mouseUpOnItem: cell dragged: YES];
      [self startExternalDragOnEvent: theEvent];
      return;
    }

  [selectionModel mouseUpOnItem: cell dragged: NO];
  if ([self applySelectionModel])
    [self sendAction];

  /* A click on the name of the only selected cell starts renaming once
     it is clear no second click follows. */
  if ([FSNRenamePolicy clickStartsRenamingWithCount: 1
                                             onName: (onIcon == NO)
                                    wasOnlySelected: wasOnlySelected
                                          modifiers: modifiers])
    {
      [[FSNRenameController sharedController] scheduleRenameOfRep: cell
                                                           inHost: [column browser]];
    }
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)drawRect:(NSRect)rect
{
  NSInteger rows = [self numberOfRows];

  if (rows > 0)
    {
      NSColor *evenColor = [NSColor colorWithCalibratedWhite: 0.92 alpha: 1.0];
      NSRange visRows = [self visibleRowRange];
      NSInteger first = (NSInteger)visRows.location;
      NSInteger count = (NSInteger)visRows.length;

      /* A big directory decorates one row at a time as its icons load, each
       * invalidating only that row's rect; walking every row of the whole
       * matrix to find which ones fall in it turned that into an O(rows)
       * scan per redraw, O(rows^2) overall. Only the rows the clip view can
       * actually show need to be walked at all. */
      if (count > 0)
        {
          NSInteger last = first + count;
          NSInteger i;

          if (first % 2 != 0)
            {
              first--;
            }

          for (i = first; i < last; i += 2)
            {
              NSRect cellFrame;

              if (i < 0 || i >= rows)
                {
                  continue;
                }

              cellFrame = [self cellFrameAtRow: i column: 0];

              if (NSIntersectsRect(cellFrame, rect))
                {
                  [evenColor set];
                  NSRectFill(cellFrame);
                }
            }
        }
    }

  [super drawRect: rect];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown)
    {
      NSPoint location = [theEvent locationInWindow];
      NSPoint localPoint = [self convertPoint: location fromView: nil];
      NSInteger row, col;

      if ([self getRow: &row column: &col forPoint: localPoint])
        {
          NSArray *cells = [self cells];

          if (row >= 0 && row < (NSInteger)[cells count])
            {
              FSNBrowserCell *cell = [cells objectAtIndex: row];
              FSNode *clickedNode = [cell node];
              NSArray *selcells = [self selectedCells];
              NSMutableArray *selnodes = [NSMutableArray array];
              NSUInteger i;

              for (i = 0; i < [selcells count]; i++)
                {
                  FSNode *node = [[selcells objectAtIndex: i] node];
                  if (node && [node isValid])
                    {
                      [selnodes addObject: node];
                    }
                }

              // If the clicked node is in the selection, use the full selection.
              // Otherwise, use just the clicked node.
              if (clickedNode && [clickedNode isValid])
                {
                  NSArray *menunodes = nil;

                  if ([selnodes containsObject: clickedNode])
                    {
                      menunodes = selnodes;
                    }
                  else
                    {
                      menunodes = [NSArray arrayWithObject: clickedNode];
                    }

                {
                  /* Resolve Workspace at runtime to avoid circular link dependency. */
                  Class wsClass = NSClassFromString(@"Workspace");
                  id gw = (wsClass && [wsClass respondsToSelector: @selector(gworkspace)])
                         ? [wsClass performSelector: @selector(gworkspace)] : nil;
                  if (gw)
                    return [gw contextMenuForNodes: menunodes
                                       openTarget: [self window]
                                    openWithTarget: gw
                                       infoTarget: gw
                                  duplicateTarget: [self window]
                                    aliasTarget: [self window]
                                      recycleTarget: [self window]
                                      ejectTarget: [self window]
                                       openAction: @selector(openSelection:)
                                  duplicateAction: @selector(duplicateFiles:)
                                    aliasAction: @selector(makeAliasFiles:)
                                    recycleAction: @selector(recycleFiles:)
                                      ejectAction: @selector(ejectVolumes:)
                                 includeOpenWith: YES];
                  else
                    return [super menuForEvent: theEvent];
                }
                }
            }
        }
      else
        {
          // Right-clicked on empty space
          {
            Class wsClass = NSClassFromString(@"Workspace");
            id gw = (wsClass && [wsClass respondsToSelector: @selector(gworkspace)])
                   ? [wsClass performSelector: @selector(gworkspace)] : nil;
            if (gw)
              return [gw emptySpaceContextMenuForViewer: [self window]];
          }
        }
    }

  return [super menuForEvent: theEvent];
}

@end


@implementation FSNBrowserMatrix (DraggingSource)

- (void)startExternalDragOnEvent:(NSEvent *)event
{
  NSArray *selectedCells = [self selectedCells];
  unsigned count = [selectedCells count];

  if (count) {
    NSPoint dragPoint = [event locationInWindow];
    NSPasteboard *pb = [NSPasteboard pasteboardWithName: NSDragPboard];
    int iconSize = [[self prototype] iconSize];
    NSImage *dragIcon;

    [self declareAndSetShapeOnPasteboard: pb];

    if (count > 1)
      {
	dragIcon = [[FSNodeRep sharedInstance] multipleSelectionIconOfSize: iconSize];
      }
    else
      {
	FSNBrowserCell *cell = [selectedCells objectAtIndex: 0];
	FSNode *node = [cell node];

	if (node && [node isValid])
	  {
	    dragIcon = [[FSNodeRep sharedInstance] iconOfSize: iconSize forNode: node];
	  }
	else
	  {
	    return;
	  }
      }

    /* Command+Alternate drags create Alias records - mark the drag with
     * the alias arrow so the user can tell it from a copy or symlink. */
    if (FSNLinkDropCreatesAlias())
      {
	dragIcon = FSNLinkBadgedImage(dragIcon);
      }

    dragPoint = [self convertPoint: dragPoint fromView: nil];
    dragPoint.x -= (iconSize / 2);
    dragPoint.y += (iconSize / 2);

    [self dragImage: dragIcon
                 at: dragPoint
             offset: NSZeroSize
              event: event
         pasteboard: pb
             source: self
          slideBack: YES];
  }
}

- (void)draggedImage:(NSImage *)anImage
	     endedAt:(NSPoint)aPoint
	   deposited:(BOOL)flag
{
}

- (void)declareAndSetShapeOnPasteboard:(NSPasteboard *)pb
{
  NSArray *selectedCells = [self selectedCells];
  NSMutableArray *selection = [NSMutableArray array];
  NSArray *dndtypes;
  int i;

  for (i = 0; i < [selectedCells count]; i++)
    {
      FSNBrowserCell *cell = [selectedCells objectAtIndex: i];
      FSNode *node = [cell node];

      if (node && [node isValid])
	{
	  [selection addObject: [node path]];
	}
    }

  if ([selection count])
    {
      dndtypes = [NSArray arrayWithObject: NSFilenamesPboardType];
      [pb declareTypes: dndtypes owner: nil];

      if ([pb setPropertyList: selection forType: NSFilenamesPboardType] == NO)
	{
	  return;
	}
    }
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag
{
  return NSDragOperationEvery;
}

@end


@implementation FSNBrowserMatrix (DraggingDestination)

- (NSDragOperation)checkReturnValueForCell:(FSNBrowserCell *)acell
                          withDraggingInfo:(id <NSDraggingInfo>)sender
{
  if (dndTarget != acell) {
    dndTarget = acell;
  }

  dragOperation = [column draggingEntered: sender inMatrixCell: dndTarget];

  if (dragOperation != NSDragOperationNone)
    {
      [self selectIconOfCell: dndTarget];
    }
  else
    {
      [self unSelectIconsOfCellsDifferentFrom: nil];
    }

  return dragOperation;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPoint location;
  NSInteger row, col;

  location = [[self window] mouseLocationOutsideOfEventStream];
  location = [self convertPoint: location fromView: nil];

  dndTarget = nil;

  if ([self getRow: &row column: &col forPoint: location])
    {
      dndTarget = [[self cells] objectAtIndex: row];
      dragOperation = [column draggingEntered: sender inMatrixCell: dndTarget];

      if (dragOperation != NSDragOperationNone)
	{
	  [self selectIconOfCell: dndTarget];
	}
      else
	{
	  [self unSelectIconsOfCellsDifferentFrom: nil];
	}

      if (dragOperation == NSDragOperationNone) {
	dndTarget = nil;
	return [column draggingEntered: sender];
      }

      return dragOperation;
    }

  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSPoint location;
  NSInteger row, col;

  location = [[self window] mouseLocationOutsideOfEventStream];
  location = [self convertPoint: location fromView: nil];

  if ([self getRow: &row column: &col forPoint: location])
    {
      FSNBrowserCell *cell = [[self cells] objectAtIndex: row];

      [self checkReturnValueForCell: cell withDraggingInfo: sender];

      [self dragRestsOnCell: cell draggingInfo: sender];

      if (dragOperation == NSDragOperationNone)
	{
	  dndTarget = nil;
	  return [column draggingUpdated: sender];
	}

      return dragOperation;
    }

  [self dragLeftCells];
  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  [self dragLeftCells];
  [self unSelectIconsOfCellsDifferentFrom: nil];
  dndTarget = nil;
}

/* A folder the drag rests on springs open: the browser then shows its
 * contents in the next column.  Reported by the matrix when its cells take
 * drops, and by its column when only the column as a whole does. */
- (void)dragRestsOnCell:(FSNBrowserCell *)cell
           draggingInfo:(id <NSDraggingInfo>)sender
{
  if (cell != springCell)
    springFlashing = NO;
  springCell = cell;

  [[FSNSpringLoader sharedLoader]
    pointerRestsOnNode: [cell node]
		inView: self
	       flasher: self
	  draggedPaths: [FSNSpringLoader draggedPathsOfDraggingInfo: sender]];
}

- (void)dragLeftCells
{
  [[FSNSpringLoader sharedLoader] pointerLeftView: self];
  springCell = nil;
  springFlashing = NO;
}

/* The flash before a folder springs open inverts the look its cell rests
 * in - lit when it takes the drop, plain when not - and then restores it. */
- (void)setSpringHighlightVisible:(BOOL)visible
{
  NSInteger row, col;
  BOOL lit;

  if (springCell == nil || [[self cells] containsObject: springCell] == NO)
    return;

  if (springFlashing == NO)
    {
      springRestingLit = (dndTarget == springCell);
      springFlashing = YES;
    }

  lit = visible ? springRestingLit : (springRestingLit == NO);
  if (visible)
    springFlashing = NO;

  if (lit)
    [springCell selectIcon];
  else
    [springCell unselectIcon];

  [self getRow: &row column: &col ofCell: springCell];
  [self setNeedsDisplayInRect: [self cellFrameAtRow: row column: col]];
  [self displayIfNeeded];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  if (dndTarget)
    {
      [column concludeDragOperation: sender inMatrixCell: dndTarget];
      [self unSelectIconsOfCellsDifferentFrom: nil];
    }
  else
    {
      [column concludeDragOperation: sender];
    }
}

@end
















