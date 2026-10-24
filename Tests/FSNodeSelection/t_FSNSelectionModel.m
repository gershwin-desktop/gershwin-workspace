/* t_FSNSelectionModel.m - the selection rules every file view shares,
 * one assertion per row of the measured reference matrix. Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../FSNode/FSNSelectionModel.m"

/* Items are distinct string objects; their text is their name. A grid
 * delegate lays them out row by row, "columns" wide, like an icon view. */
@interface TSelDelegate : NSObject <FSNSelectionModelDelegate>
{
@public
  NSArray *items;
  NSUInteger columns;
}
@end

/* A list has no geometry: arrows walk the row order. */
@interface TListDelegate : NSObject <FSNSelectionModelDelegate>
@end

@implementation TListDelegate
- (NSString *)selectionModel:(FSNSelectionModel *)model nameOfItem:(id)item
{
  return item;
}
@end

@implementation TSelDelegate
- (NSString *)selectionModel:(FSNSelectionModel *)model nameOfItem:(id)item
{
  return item;
}
- (id)selectionModel:(FSNSelectionModel *)model
            itemFrom:(id)item
         inDirection:(FSNSelectionDirection)direction
{
  NSUInteger count = [items count];
  NSRect *rects = malloc(sizeof(NSRect) * count);
  NSUInteger i, found;

  for (i = 0; i < count; i++)
    rects[i] = NSMakeRect((i % columns) * 100.0, (i / columns) * 80.0, 90.0, 70.0);
  found = [FSNSelectionModel indexOfNeighborOfRect: [items indexOfObjectIdenticalTo: item]
                                           inRects: rects
                                             count: count
                                         direction: direction
                                           flipped: YES];
  free(rects);
  return (found == NSNotFound) ? nil : [items objectAtIndex: found];
}
@end

static NSArray *names(NSArray *sel)
{
  return [sel valueForKey: @"description"];
}

static NSString *joined(FSNSelectionModel *m)
{
  return [names([m selectedItems]) componentsJoinedByString: @","];
}

static NSArray *makeItems(NSString *spec)
{
  NSMutableArray *a = [NSMutableArray array];
  NSEnumerator *e = [[spec componentsSeparatedByString: @","] objectEnumerator];
  NSString *s;

  /* Copies, so identity and equality differ like for real reps. */
  while ((s = [e nextObject]) != nil)
    [a addObject: [NSMutableString stringWithString: s]];
  return a;
}

static id item(NSArray *items, NSString *name)
{
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    if ([[items objectAtIndex: i] isEqualToString: name])
      return [items objectAtIndex: i];
  return nil;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* The order of the reference's test folder, sorted by name like its
   * views; "Charlie" sorts between "bravo" and "delta" ignoring case. */
  NSArray *items = makeItems(@"alpha,alpine,beta,bravo,Charlie,delta,echo,"
                             @"foxtrot,golf,hotel,india,juliet,sub,sub.one,sub.two");
  TSelDelegate *grid = [TSelDelegate new];
  TListDelegate *list = [TListDelegate new];
  FSNSelectionModel *m;

  grid->items = items;
  grid->columns = 3;

  START_SET("icon style: mouse")
  m = [[FSNSelectionModel alloc] initWithStyle: FSNSelectionStyleIcon];
  [m setDelegate: grid];
  [m setItems: items];

  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"beta") dragged: NO];
  PASS_EQUAL(joined(m), @"beta", "a click selects only the item");

  [m mouseDownOnItem: item(items, @"delta") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"beta,delta", "Shift-click adds a single item, no range");
  [m mouseDownOnItem: item(items, @"beta") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"delta", "Shift-click on a selected item removes it");

  [m mouseDownOnItem: item(items, @"echo") modifiers: FSNSelectionModifierCommand];
  PASS_EQUAL(joined(m), @"delta,echo", "Command-click adds");
  [m mouseDownOnItem: item(items, @"echo") modifiers: FSNSelectionModifierCommand];
  PASS_EQUAL(joined(m), @"delta", "Command-click on a selected item removes it");

  [m mouseDownOnItem: item(items, @"golf") modifiers: FSNSelectionModifierCommand];
  [m mouseDownOnItem: item(items, @"delta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"delta") dragged: NO];
  PASS_EQUAL(joined(m), @"delta,golf",
             "a click on an item of a multiple selection keeps the selection");

  [m mouseDownOnItem: item(items, @"juliet") modifiers: FSNSelectionModifierOption];
  PASS_EQUAL(joined(m), @"juliet", "Option-click is a plain click");

  [m mouseDownOnItem: item(items, @"alpha") modifiers: FSNSelectionModifierControl];
  PASS_EQUAL(joined(m), @"juliet", "Control-click leaves the selection alone");

  [m mouseDownOnEmptySpaceWithModifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"juliet", "Shift on empty space keeps the selection for a band");
  [m mouseDownOnEmptySpaceWithModifiers: 0];
  PASS([[m selectedItems] count] == 0, "a click on empty space deselects everything");
  END_SET("icon style: mouse")

  START_SET("icon style: band")
  NSArray *band = [NSArray arrayWithObjects: item(items, @"hotel"), item(items, @"india"),
                                             item(items, @"sub"), nil];
  [m selectOnly: item(items, @"alpha")];
  [m beginBandWithModifiers: 0];
  [m updateBandWithItems: band];
  [m endBand];
  PASS_EQUAL(joined(m), @"hotel,india,sub", "a plain band replaces the selection");

  [m selectOnly: item(items, @"alpha")];
  [m mouseDownOnItem: item(items, @"sub") modifiers: FSNSelectionModifierCommand];
  [m beginBandWithModifiers: FSNSelectionModifierShift];
  [m updateBandWithItems: band];
  [m endBand];
  PASS_EQUAL(joined(m), @"alpha,hotel,india", "a Shift band toggles what it touches");

  [m selectOnly: item(items, @"alpha")];
  [m mouseDownOnItem: item(items, @"sub") modifiers: FSNSelectionModifierCommand];
  [m beginBandWithModifiers: FSNSelectionModifierCommand];
  [m updateBandWithItems: band];
  PASS_EQUAL(joined(m), @"alpha,hotel,india", "a Command band toggles too, while it is dragged");
  [m updateBandWithItems: [NSArray array]];
  PASS_EQUAL(joined(m), @"alpha,sub", "shrinking the band gives back what it toggled");
  [m endBand];
  END_SET("icon style: band")

  START_SET("icon style: keys")
  [m deselectAllItems];
  [m moveInDirection: FSNSelectionDirectionDown extend: NO];
  PASS_EQUAL(joined(m), @"alpha", "Down with nothing selected selects the first item");
  [m deselectAllItems];
  [m moveInDirection: FSNSelectionDirectionUp extend: NO];
  PASS_EQUAL(joined(m), @"sub.two", "Up with nothing selected selects the last item");
  [m deselectAllItems];
  [m moveInDirection: FSNSelectionDirectionRight extend: NO];
  PASS_EQUAL(joined(m), @"sub.two", "Right with nothing selected selects the last item");

  [m selectOnly: item(items, @"alpha")];
  [m moveInDirection: FSNSelectionDirectionRight extend: NO];
  PASS_EQUAL(joined(m), @"alpine", "Right moves to the neighbor in the row");
  [m moveInDirection: FSNSelectionDirectionDown extend: NO];
  PASS_EQUAL(joined(m), @"Charlie", "Down moves to the neighbor in the column");
  [m moveInDirection: FSNSelectionDirectionRight extend: NO];
  [m moveInDirection: FSNSelectionDirectionRight extend: NO];
  PASS_EQUAL(joined(m), @"delta", "Right at the end of a row stays (no wrap)");
  [m moveInDirection: FSNSelectionDirectionLeft extend: NO];
  [m moveInDirection: FSNSelectionDirectionLeft extend: NO];
  [m moveInDirection: FSNSelectionDirectionLeft extend: NO];
  PASS_EQUAL(joined(m), @"bravo", "Left stops at the start of the row");

  [m selectOnly: item(items, @"echo")];
  [m moveInDirection: FSNSelectionDirectionRight extend: YES];
  PASS_EQUAL(joined(m), @"echo,foxtrot", "Shift-Right adds the neighbor");
  [m moveInDirection: FSNSelectionDirectionDown extend: YES];
  PASS_EQUAL(joined(m), @"echo,foxtrot,india", "Shift-Down adds the item below the cursor");
  [m moveInDirection: FSNSelectionDirectionUp extend: YES];
  PASS_EQUAL(joined(m), @"echo,foxtrot,india",
             "Shift moving back over a selected item never shrinks");

  [m selectOnly: item(items, @"echo")];
  [m mouseDownOnItem: item(items, @"hotel") modifiers: FSNSelectionModifierCommand];
  [m moveInDirection: FSNSelectionDirectionRight extend: NO];
  PASS_EQUAL(joined(m), @"india", "arrows move from the item clicked last");

  PASS([m selectAllItems] && [[m selectedItems] count] == [items count], "select all");
  PASS([m deselectAllItems] && [[m selectedItems] count] == 0, "Escape deselects");
  END_SET("icon style: keys")

  START_SET("type select and Tab")
  [m resetTypeSelect];
  [m typeSelect: @"b" atTime: 100.0];
  PASS_EQUAL(joined(m), @"beta", "a typed letter selects the first match");
  [m typeSelect: @"r" atTime: 100.9];
  PASS_EQUAL(joined(m), @"bravo", "a key within the timeout extends the prefix");
  [m typeSelect: @"r" atTime: 102.0];
  PASS_EQUAL(joined(m), @"sub", "after the timeout a key starts over; no match selects the next name");
  [m typeSelect: @"c" atTime: 104.0];
  PASS_EQUAL(joined(m), @"Charlie", "type select ignores case");
  [m typeSelect: @"ALPI" atTime: 106.0];
  PASS_EQUAL(joined(m), @"alpine", "several characters at once");
  [m typeSelect: @"zz" atTime: 108.0];
  PASS_EQUAL(joined(m), @"sub.two", "past the last name the last item is selected");

  [m selectOnly: item(items, @"beta")];
  [m selectNextInNameOrder: YES];
  PASS_EQUAL(joined(m), @"bravo", "Tab selects the next name");
  [m selectNextInNameOrder: YES];
  PASS_EQUAL(joined(m), @"Charlie", "Tab orders names ignoring case");
  [m selectNextInNameOrder: NO];
  [m selectNextInNameOrder: NO];
  PASS_EQUAL(joined(m), @"beta", "Shift-Tab goes back");
  [m deselectAllItems];
  [m selectNextInNameOrder: YES];
  PASS_EQUAL(joined(m), @"alpha", "Tab with nothing selected selects the first name");
  [m deselectAllItems];
  [m selectNextInNameOrder: NO];
  PASS_EQUAL(joined(m), @"sub.two", "Shift-Tab with nothing selected selects the last name");
  [m selectOnly: item(items, @"beta")];
  [m mouseDownOnItem: item(items, @"foxtrot") modifiers: FSNSelectionModifierCommand];
  [m selectNextInNameOrder: YES];
  PASS_EQUAL(joined(m), @"golf", "Tab moves on from the item clicked last");
  [m release];
  END_SET("type select and Tab")

  START_SET("list style: mouse")
  m = [[FSNSelectionModel alloc] initWithStyle: FSNSelectionStyleList];
  [m setDelegate: list];
  [m setItems: items];

  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"beta") dragged: NO];
  [m mouseDownOnItem: item(items, @"delta") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"beta,bravo,Charlie,delta", "Shift-click selects a range from the anchor");
  [m mouseDownOnItem: item(items, @"alpha") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta", "a second Shift-click replaces the range");
  [m mouseDownOnItem: item(items, @"golf") modifiers: FSNSelectionModifierCommand];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,golf", "Command-click adds");
  [m mouseDownOnItem: item(items, @"india") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,golf,hotel,india",
             "Command-click moves the anchor; the next range keeps the rest");
  [m setItems: [NSArray arrayWithArray: items]];
  [m setSelectedItems: [m selectedItems]];
  [m mouseDownOnItem: item(items, @"hotel") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,golf,hotel",
             "a range can shrink, also after the view handed the same items and selection back");
  [m mouseDownOnItem: item(items, @"golf") modifiers: FSNSelectionModifierCommand];
  [m mouseDownOnItem: item(items, @"echo") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,echo,foxtrot,golf,hotel",
             "a Command-click that deselects still becomes the anchor");

  [m mouseDownOnItem: item(items, @"delta") modifiers: FSNSelectionModifierOption];
  [m mouseUpOnItem: item(items, @"delta") dragged: NO];
  PASS_EQUAL(joined(m), @"delta", "Option-click is a plain click");

  [m mouseDownOnEmptySpaceWithModifiers: 0];
  [m mouseDownOnItem: item(items, @"delta") modifiers: FSNSelectionModifierShift];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,bravo,Charlie,delta",
             "Shift-click with no anchor starts the range at the first item");

  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,bravo,Charlie,delta",
             "pressing on a selected item keeps the selection for a drag");
  [m mouseUpOnItem: item(items, @"beta") dragged: YES];
  PASS_EQUAL(joined(m), @"alpha,alpine,beta,bravo,Charlie,delta", "a drag keeps it");
  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"beta") dragged: NO];
  PASS_EQUAL(joined(m), @"beta", "a click without a drag reduces it to that item");

  [m mouseDownOnItem: item(items, @"juliet") modifiers: FSNSelectionModifierControl];
  PASS_EQUAL(joined(m), @"beta", "Control-click leaves the selection alone");
  END_SET("list style: mouse")

  START_SET("list style: band")
  NSArray *rows = [NSArray arrayWithObjects: item(items, @"foxtrot"), item(items, @"golf"), nil];
  [m selectOnly: item(items, @"beta")];
  [m mouseDownOnItem: item(items, @"golf") modifiers: FSNSelectionModifierCommand];
  [m beginBandWithModifiers: FSNSelectionModifierCommand];
  [m updateBandWithItems: rows];
  [m endBand];
  PASS_EQUAL(joined(m), @"beta,foxtrot,golf", "a Command band adds in a list");
  [m beginBandWithModifiers: 0];
  [m updateBandWithItems: rows];
  [m endBand];
  PASS_EQUAL(joined(m), @"foxtrot,golf", "a plain band replaces");
  END_SET("list style: band")

  START_SET("list style: keys")
  [m deselectAllItems];
  [m moveInDirection: FSNSelectionDirectionDown extend: NO];
  PASS_EQUAL(joined(m), @"alpha", "Down with nothing selected selects the first row");
  [m deselectAllItems];
  [m moveInDirection: FSNSelectionDirectionUp extend: NO];
  PASS_EQUAL(joined(m), @"sub.two", "Up with nothing selected selects the last row");
  [m moveInDirection: FSNSelectionDirectionDown extend: NO];
  PASS_EQUAL(joined(m), @"sub.two", "Down on the last row stays");
  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"beta") dragged: NO];
  [m moveInDirection: FSNSelectionDirectionDown extend: YES];
  [m moveInDirection: FSNSelectionDirectionDown extend: YES];
  PASS_EQUAL(joined(m), @"beta,bravo,Charlie", "Shift-Down extends the range");
  [m moveInDirection: FSNSelectionDirectionUp extend: YES];
  [m moveInDirection: FSNSelectionDirectionUp extend: YES];
  [m moveInDirection: FSNSelectionDirectionUp extend: YES];
  PASS_EQUAL(joined(m), @"alpine,beta", "Shift-Up shrinks it and grows it past the anchor");
  [m moveInDirection: FSNSelectionDirectionDown extend: NO];
  PASS_EQUAL(joined(m), @"beta", "a plain arrow moves on from the cursor");
  PASS([m selectLastItem] && [joined(m) isEqual: @"sub.two"], "Option-Down selects the last row");
  PASS([m selectFirstItem] && [joined(m) isEqual: @"alpha"], "Option-Up selects the first row");
  END_SET("list style: keys")

  START_SET("items change")
  NSMutableArray *fewer = [NSMutableArray arrayWithArray: items];
  [m selectOnly: item(items, @"beta")];
  [m mouseDownOnItem: item(items, @"golf") modifiers: FSNSelectionModifierCommand];
  [fewer removeObjectIdenticalTo: item(items, @"golf")];
  [m setItems: fewer];
  PASS_EQUAL(joined(m), @"beta", "an item that goes away leaves the selection");
  PASS([m cursor] == nil, "and is no longer the cursor");
  [m setItems: items];
  [m mouseDownOnItem: item(items, @"beta") modifiers: 0];
  [m mouseUpOnItem: item(items, @"beta") dragged: NO];
  [m setSelectedItems: [NSArray arrayWithObject: item(items, @"delta")]];
  PASS_EQUAL(joined(m), @"delta", "a selection made by the view is taken over");
  PASS([m anchor] == item(items, @"beta"), "the anchor survives it");
  [m release];
  END_SET("items change")

  START_SET("neighbor geometry")
  /* Freely placed icons, y grows downward (flipped): A B on one row, C
   * below A, D diagonally below-right of B but not under it. */
  NSRect r[4];
  r[0] = NSMakeRect(0, 0, 80, 60);
  r[1] = NSMakeRect(120, 5, 80, 60);
  r[2] = NSMakeRect(10, 100, 80, 60);
  r[3] = NSMakeRect(260, 120, 80, 60);
  PASS([FSNSelectionModel indexOfNeighborOfRect: 0 inRects: r count: 4
                                      direction: FSNSelectionDirectionRight flipped: YES] == 1,
       "Right finds the item in the same row");
  PASS([FSNSelectionModel indexOfNeighborOfRect: 0 inRects: r count: 4
                                      direction: FSNSelectionDirectionDown flipped: YES] == 2,
       "Down finds the item in the same column");
  PASS([FSNSelectionModel indexOfNeighborOfRect: 1 inRects: r count: 4
                                      direction: FSNSelectionDirectionDown flipped: YES] == NSNotFound,
       "Down does not jump diagonally");
  PASS([FSNSelectionModel indexOfNeighborOfRect: 2 inRects: r count: 4
                                      direction: FSNSelectionDirectionUp flipped: YES] == 0,
       "Up in a flipped view");
  PASS([FSNSelectionModel indexOfNeighborOfRect: 2 inRects: r count: 4
                                      direction: FSNSelectionDirectionUp flipped: NO] == NSNotFound,
       "in an unflipped view up is toward larger y");
  PASS([FSNSelectionModel indexOfNeighborOfRect: 0 inRects: r count: 4
                                      direction: FSNSelectionDirectionUp flipped: NO] == 2,
       "Up in an unflipped view");
  END_SET("neighbor geometry")

  [grid release];
  [list release];
  [arp release];
  return 0;
}
