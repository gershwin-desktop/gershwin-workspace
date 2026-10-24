/* t_FSNListRowModel.m - the list view's rows with folders expanded inline,
 * and the horizontal geometry of a row.  Headless, no file system.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNListRowModel.h"

/* Items are plain path strings here: the model only needs a key per item. */
static NSString *const RootFolderKey = @"/root";

static NSArray *paths (NSString *parent, NSArray *names)
{
  NSMutableArray *result = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [names count]; i++)
    {
      [result addObject: [parent stringByAppendingPathComponent: [names objectAtIndex: i]]];
    }
  return result;
}

static NSString *rowsDescription (FSNListRowModel *model)
{
  NSMutableArray *parts = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [[model rows] count]; i++)
    {
      [parts addObject: [NSString stringWithFormat: @"%lu:%@",
                                  (unsigned long)[model depthOfRow: i],
                                  [[[model rows] objectAtIndex: i] lastPathComponent]]];
    }
  return [parts componentsJoinedByString: @" "];
}

int main (void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  FSNListRowModel *model;
  NSComparator byName = ^NSComparisonResult (id a, id b) {
    return [[a lastPathComponent] compare: [b lastPathComponent]];
  };
  NSComparator byNameDescending = ^NSComparisonResult (id a, id b) {
    return [[b lastPathComponent] compare: [a lastPathComponent]];
  };

  model = [[FSNListRowModel alloc] initWithKeyOfItem: ^NSString *(id item) {
      return item;
    }];
  [model resetWithRootKey: RootFolderKey keepExpanded: NO];

  /* --- flat list ------------------------------------------------------ */
  [model setChildren: paths (RootFolderKey, [NSArray arrayWithObjects: @"c", @"a", @"b", nil])
               ofKey: RootFolderKey];
  [model sortUsingComparator: byName];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 0:c",
              "RM-1 the shown folder's items are the rows at depth 0, sorted");

  /* --- expand inline -------------------------------------------------- */
  [model setChildren: paths (@"/root/b", [NSArray arrayWithObjects: @"y", @"x", nil])
               ofKey: @"/root/b"];
  [model sortUsingComparator: byName];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 0:c",
              "RM-2 a folder's loaded items stay hidden while it is collapsed");

  [model setExpanded: YES forKey: @"/root/b"];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 1:x 1:y 0:c",
              "RM-3 expanding a folder shows its items right under it, one level deeper");
  PASS ([model isExpanded: @"/root/b"] && ![model isExpanded: @"/root/a"],
        "RM-4 only the expanded folder reads as expanded");

  /* --- second level --------------------------------------------------- */
  [model setChildren: paths (@"/root/b/x", [NSArray arrayWithObjects: @"q", @"p", nil])
               ofKey: @"/root/b/x"];
  [model setExpanded: YES forKey: @"/root/b/x"];
  [model sortUsingComparator: byName];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 1:x 2:p 2:q 1:y 0:c",
              "RM-5 a folder inside an expanded folder expands two levels deep");
  PASS ([model rowOfKey: @"/root/b/x/q"] == 4 && [model rowOfKey: @"/root/zz"] == NSNotFound,
        "RM-6 rows are found by key, and an unknown key has none");
  PASS_EQUAL ([model parentKeyOfKey: @"/root/b/x/q"], @"/root/b/x",
              "RM-7 every item knows the folder it is listed in");

  /* --- sorting is per level ------------------------------------------- */
  [model sortUsingComparator: byNameDescending];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:c 0:b 1:y 1:x 2:q 2:p 0:a",
              "RM-8 sorting orders every level on its own; children stay under their folder");
  [model sortUsingComparator: byName];

  /* --- collapse and expand again -------------------------------------- */
  [model setExpanded: NO forKey: @"/root/b"];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 0:c",
              "RM-9 collapsing a folder hides everything below it");
  PASS ([model isExpanded: @"/root/b/x"],
        "RM-10 a folder inside keeps its expanded state while its parent is collapsed");
  {
    NSArray *visible = [model visibleExpandedKeys];
    PASS ([visible count] == 0, "RM-11 and no collapsed folder counts as visible (nothing to watch)");
  }
  [model setExpanded: YES forKey: @"/root/b"];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 1:x 2:p 2:q 1:y 0:c",
              "RM-12 expanding it again shows the inner folder still expanded");
  {
    NSArray *visible = [model visibleExpandedKeys];
    NSArray *want = [NSArray arrayWithObjects: @"/root/b", @"/root/b/x", nil];
    PASS_EQUAL (visible, want, "RM-13 the visible expanded folders, outer first");
  }

  /* --- watcher changes ------------------------------------------------ */
  [model addChild: @"/root/b/x/o" toKey: @"/root/b/x"];
  [model sortUsingComparator: byName];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 1:x 2:o 2:p 2:q 1:y 0:c",
              "RM-14 a file created in an expanded folder appears in it");
  [model addChild: @"/root/b/x/o" toKey: @"/root/b/x"];
  [model rebuildRows];
  PASS ([[model rows] count] == 8, "RM-15 adding an item that is listed already replaces it, no duplicate");

  PASS_EQUAL ([model removeItemWithKey: @"/root/b/x"], @"/root/b/x",
              "RM-16 removing an item hands it back");
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:a 0:b 1:y 0:c",
              "RM-17 removing an expanded folder removes its items with it");
  PASS (![model isExpanded: @"/root/b/x"] && [model childrenOfKey: @"/root/b/x"] == nil,
        "RM-18 and forgets its expanded state and its items");
  PASS ([model removeItemWithKey: @"/root/nothing"] == nil,
        "RM-19 removing an unknown key changes nothing");

  /* --- showing another folder or reloading the same one --------------- */
  [model resetWithRootKey: RootFolderKey keepExpanded: YES];
  PASS ([model isExpanded: @"/root/b"] && [[model rows] count] == 0
        && [model childrenOfKey: @"/root/b"] == nil,
        "RM-20 a reload of the same folder drops the items but keeps what was expanded");
  [model resetWithRootKey: @"/other" keepExpanded: NO];
  PASS (![model isExpanded: @"/root/b"], "RM-21 another folder starts with everything collapsed");

  /* --- an expanded folder whose items are not loaded shows none -------- */
  [model setChildren: paths (@"/other", [NSArray arrayWithObjects: @"f", nil]) ofKey: @"/other"];
  [model setExpanded: YES forKey: @"/other/f"];
  [model rebuildRows];
  PASS_EQUAL (rowsDescription (model), @"0:f",
              "RM-22 an expanded folder with nothing loaded yet adds no rows");
  {
    NSArray *want = [NSArray arrayWithObject: @"/other/f"];
    PASS_EQUAL ([model visibleExpandedKeys], want,
                "RM-23 but it is visible, so its items can be loaded and watched");
  }

  /* --- option-click: expand and collapse a whole tree -------------------- */
  {
    /* /t has a, b; a has a1 (folder) and af; a1 has deep; b has bf. */
    NSDictionary *tree = [NSDictionary dictionaryWithObjectsAndKeys:
      paths (@"/t", [NSArray arrayWithObjects: @"a", @"b", @"f", nil]), @"/t",
      paths (@"/t/a", [NSArray arrayWithObjects: @"a1", @"af", nil]), @"/t/a",
      paths (@"/t/a/a1", [NSArray arrayWithObjects: @"deep", nil]), @"/t/a/a1",
      paths (@"/t/b", [NSArray arrayWithObjects: @"bf", nil]), @"/t/b",
      [NSArray array], @"/t/a/a1/deep",
      nil];
    BOOL (^isFolder)(id) = ^BOOL (id item) {
      return [tree objectForKey: item] != nil;
    };
    __block NSUInteger loads = 0;
    NSArray *(^load)(NSString *) = ^NSArray *(NSString *key) {
      loads++;
      return [tree objectForKey: key];
    };
    BOOL complete;

    [model resetWithRootKey: @"/t" keepExpanded: NO];
    [model setChildren: [tree objectForKey: @"/t"] ofKey: @"/t"];
    complete = [model expandRecursivelyFromKey: @"/t/a" isExpandable: isFolder
                                   loadChildren: load maxRows: 1000];
    [model sortUsingComparator: byName];
    [model rebuildRows];
    PASS (complete, "RM-24 a small tree expands completely");
    PASS_EQUAL (rowsDescription (model), @"0:a 1:a1 2:deep 1:af 0:b 0:f",
                "RM-25 expanding recursively opens every folder below, but not the neighbours");
    PASS ([model isExpanded: @"/t/a/a1/deep"], "RM-26 down to the last level");

    [model collapseRecursivelyFromKey: @"/t/a"];
    [model rebuildRows];
    PASS_EQUAL (rowsDescription (model), @"0:a 0:b 0:f",
                "RM-27 collapsing recursively closes the folder");
    [model setExpanded: YES forKey: @"/t/a"];
    [model rebuildRows];
    PASS_EQUAL (rowsDescription (model), @"0:a 1:a1 1:af 0:b 0:f",
                "RM-28 and every folder below it, so a plain expand shows one level again");

    [model resetWithRootKey: @"/t" keepExpanded: NO];
    [model setChildren: [tree objectForKey: @"/t"] ofKey: @"/t"];
    loads = 0;
    complete = [model expandRecursivelyFromKey: @"/t/a" isExpandable: isFolder
                                   loadChildren: load maxRows: 1];
    [model sortUsingComparator: byName];
    [model rebuildRows];
    PASS (complete == NO && loads == 1,
          "RM-29 a tree bigger than the limit stops after the folder that crossed it");
    PASS_EQUAL (rowsDescription (model), @"0:a 1:a1 1:af 0:b 0:f",
                "RM-30 and shows what it loaded so far");
  }

  /* --- geometry --------------------------------------------------------- */
  PASS (FSNListIconXForDepth (0) == 26.0 && FSNListIconXForDepth (1) == 47.0
        && FSNListIconXForDepth (2) == 68.0,
        "RG-1 the icon sits 26 points in, plus 21 per level");
  {
    NSRect t0 = FSNListDisclosureRectForDepth (0, 19.0);
    NSRect t1 = FSNListDisclosureRectForDepth (1, 19.0);

    PASS (NSMinX (t0) == 8.0 && NSWidth (t0) == 9.0 && NSMinY (t0) == 4.0 && NSHeight (t0) == 9.0,
          "RG-2 the triangle is 9 points square, 8 in and 4 down in a 19 point row");
    PASS (NSMinX (t1) == 29.0 && NSMinY (t1) == 4.0,
          "RG-3 and moves 21 points per level");
    PASS (NSMinY (FSNListDisclosureRectForDepth (0, 39.0)) == 14.0,
          "RG-4 in a taller row it stays a point above the middle");
  }
  PASS (FSNListTextXForDepth (0, 16) == 49.0 && FSNListTextXForDepth (1, 16) == 70.0
        && FSNListTextXForDepth (0, 32) == 65.0,
        "RG-6 the name starts 7 points after the icon, at every level and icon size");
  {
    NSRect hit = FSNListDisclosureHitRectForDepth (1, 19.0);

    PASS (NSMinX (hit) == 21.0 && NSMaxX (hit) == 46.0 && NSHeight (hit) == 19.0,
          "RG-5 a click anywhere in the level's triangle column, up to the icon, toggles");
  }

  [model release];
  [arp release];
  return 0;
}
