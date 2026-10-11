/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The Finder column view options of FSNBrowser: text size, show icons, show
 * icon preview, arrange by, column widths and the preview column, and
 * that the browser follows the global FSNColumnViewOptions. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNBrowser.h"
#import "FSNBrowserColumn.h"
#import "FSNBrowserCell.h"
#import "FSNBrowserPreviewView.h"
#import "FSNPreviewProvider.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"
#import "FSNColumnViewOptions.h"

/* Labels as the Finder fixture of E25 has them. */
@interface StubMetadata : NSObject <FSNMetadataProvider>
@end

@implementation StubMetadata
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSZeroPoint; }
- (void)invalidateCaches {}
- (NSInteger)labelIndexForPath:(NSString *)path
{
  if ([path hasSuffix: @"/big.bin"]) return 7;    /* Orange */
  if ([path hasSuffix: @"/small.rtf"]) return 6;  /* Red */
  if ([path hasSuffix: @"/dir"]) return 4;        /* Blue */
  return 0;
}
- (NSString *)labelNameForPath:(NSString *)path
{
  if ([path hasSuffix: @"/big.bin"]) return @"Orange";
  if ([path hasSuffix: @"/small.rtf"]) return @"Red";
  if ([path hasSuffix: @"/dir"]) return @"Blue";
  return nil;
}
@end

/* Stands in for Workspace's Look Inside rendering. */
@interface StubPreviewProvider : NSObject <FSNPreviewProvider>
{
@public
  NSMutableArray *asked;
}
@end

@implementation StubPreviewProvider
- (id)init
{
  self = [super init];
  asked = [NSMutableArray new];
  return self;
}
- (NSView *)previewViewForPath:(NSString *)path frame:(NSRect)frame
{
  NSView *v;

  [asked addObject: path];
  if ([path hasSuffix: @".bin"])
    return nil;
  v = [[[NSView alloc] initWithFrame: frame] autorelease];
  return v;
}
@end

static void
writeFile(NSString *path, NSUInteger size, NSDate *date)
{
  NSMutableData *d = [NSMutableData dataWithLength: size];

  [d writeToFile: path atomically: NO];
  [[NSFileManager defaultManager]
    changeFileAttributes: [NSDictionary dictionaryWithObject: date forKey: NSFileModificationDate]
                  atPath: path];
}

static NSDate *
day(int y, int m, int d)
{
  return [NSCalendarDate dateWithYear: y month: m day: d hour: 12 minute: 0 second: 0
                             timeZone: [NSTimeZone localTimeZone]];
}

/* A 16 x 16 pure red PNG: its own picture is easy to tell from a type icon. */
static void
writeRedPNG(NSString *path, NSDate *date)
{
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL pixelsWide: 16 pixelsHigh: 16
               bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
              colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 64 bitsPerPixel: 32];
  unsigned char *p = [rep bitmapData];
  NSUInteger i;

  for (i = 0; i < 16 * 16; i++)
    {
      p[i * 4] = 255; p[i * 4 + 1] = 0; p[i * 4 + 2] = 0; p[i * 4 + 3] = 255;
    }
  [[rep representationUsingType: NSPNGFileType properties: nil] writeToFile: path atomically: NO];
  [rep release];
  [[NSFileManager defaultManager]
    changeFileAttributes: [NSDictionary dictionaryWithObject: date forKey: NSFileModificationDate]
                  atPath: path];
}

static BOOL
isRed(NSImage *image)
{
  NSEnumerator *e = [[image representations] objectEnumerator];
  NSImageRep *rep;

  while ((rep = [e nextObject]) != nil)
    {
      if ([rep isKindOfClass: [NSBitmapImageRep class]])
        {
          NSColor *c = [[(NSBitmapImageRep *)rep colorAtX: 8 y: 8]
                         colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
          return [c redComponent] > 0.9 && [c greenComponent] < 0.1 && [c blueComponent] < 0.1;
        }
    }
  return NO;
}

static NSArray *
cellsOf(FSNBrowserColumn *col)
{
  NSArray *cells = [[col cmatrix] cells];
  NSUInteger i;

  /* Decoration normally waits for the rows to come on screen. */
  for (i = 0; i < [cells count]; i++)
    {
      if ([[cells objectAtIndex: i] isDecorated] == NO)
        [[cells objectAtIndex: i] decorate];
    }
  return cells;
}

static NSArray *
namesOf(FSNBrowserColumn *col)
{
  NSMutableArray *names = [NSMutableArray array];
  NSArray *cells = [[col cmatrix] cells];
  NSUInteger i;

  for (i = 0; i < [cells count]; i++)
    [names addObject: [[[cells objectAtIndex: i] node] name]];
  return names;
}

static FSNBrowserCell *
cellNamed(FSNBrowserColumn *col, NSString *name)
{
  NSArray *cells = cellsOf (col);
  NSUInteger i;

  for (i = 0; i < [cells count]; i++)
    {
      if ([[[[cells objectAtIndex: i] node] name] isEqual: name])
        return [cells objectAtIndex: i];
    }
  return nil;
}

#define NAMES(...) [NSArray arrayWithObjects: __VA_ARGS__, nil]

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [NSTemporaryDirectory () stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"fsnbrowser-%d", getpid ()]];
  FSNodeRep *rep;
  StubMetadata *metadata = [StubMetadata new];
  StubPreviewProvider *previews = [StubPreviewProvider new];
  FSNColumnViewOptions *options;
  FSNBrowser *browser;
  FSNBrowserColumn *col0;
  NSArray *before;
  id savedProvider;

  if (getenv ("DISPLAY") == NULL)
    {
      printf ("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }

  [[NSUserDefaults standardUserDefaults]
    setObject: [NSArray arrayWithObject: @"English"] forKey: @"NSLanguages"];
  [NSApplication sharedApplication];

  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];
  writeFile ([root stringByAppendingPathComponent: @"big.bin"], 100000, day (2020, 1, 1));
  writeFile ([root stringByAppendingPathComponent: @"mid.txt"], 10000, day (2026, 10, 10));
  writeFile ([root stringByAppendingPathComponent: @"small.rtf"], 1000, day (2023, 1, 1));
  writeRedPNG ([root stringByAppendingPathComponent: @"pic.png"], day (2019, 1, 1));
  [fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"dir"] attributes: nil];
  writeFile ([[root stringByAppendingPathComponent: @"dir"] stringByAppendingPathComponent: @"inner"],
             10, day (2021, 1, 1));
  [fm changeFileAttributes: [NSDictionary dictionaryWithObject: day (2021, 1, 1)
                                                        forKey: NSFileModificationDate]
                    atPath: [root stringByAppendingPathComponent: @"dir"]];

  rep = [FSNodeRep sharedInstance];
  savedProvider = [rep metadataProvider];
  [rep setMetadataProvider: metadata];

  /* The global options start out as Finder's defaults (this tool's own
   * defaults domain; its NSFontSize hides the user's). */
  {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSArray *keys = [NSArray arrayWithObjects: FSNColumnViewTextSizeKey, FSNColumnViewShowsIconsKey,
                             FSNColumnViewShowsIconPreviewKey, FSNColumnViewShowsPreviewColumnKey,
                             FSNColumnViewArrangeByKey, FSNColumnViewColumnWidthKey, nil];
    NSUInteger k;

    for (k = 0; k < [keys count]; k++)
      [defs removeObjectForKey: [keys objectAtIndex: k]];
    [defs setInteger: 12 forKey: @"NSFontSize"];
  }
  options = [FSNColumnViewOptions sharedOptions];

  browser = [[FSNBrowser alloc] initWithBaseNode: [FSNode nodeWithPath: root]
                                  visibleColumns: 3
                                        scroller: nil
                                      cellsIcons: NO
                                      acceptsDnd: NO
                                   editableCells: NO
                                 selectionColumn: NO];
  [browser setFrame: NSMakeRect (0, 0, 602, 300)];
  [browser loadColumnZero];
  col0 = [browser columnWithPath: root];

  /* --- defaults --------------------------------------------------------- */
  PASS ([browser showsIcons], "MI-CLM-30 icons are shown by default");
  PASS ([browser showsIconPreview], "MI-CLM-31 icon previews are shown by default");
  PASS ([browser showsPreviewColumn], "MI-CLM-32 the preview column is shown by default");
  PASS ([browser arrangement] == FSNIconsArrangeName, "MI-CLM-33 arranged by name by default");
  PASS ([browser defaultColumnWidth] == 205 && [browser labelTextSize] == 12,
        "MI-CLM-34 by default columns are 205 points wide, names 12 points");

  /* --- text size ------------------------------------------------------- */
  PASS ([FSNBrowser clampedLabelTextSize: 20] == 16 && [FSNBrowser clampedLabelTextSize: 4] == 10,
        "MI-CLM-35 text sizes are held to Finder's 10 to 16");
  [browser setLabelTextSize: 10];
  col0 = [browser columnWithPath: root];
  {
    CGFloat small = [[col0 cmatrix] cellSize].height;
    FSNBrowserCell *cell;

    PASS ([browser labelTextSize] == 10, "MI-CLM-36 the text size set is the one reported");
    [browser setLabelTextSize: 16];
    col0 = [browser columnWithPath: root];
    cell = [[[col0 cmatrix] cells] objectAtIndex: 0];
    PASS ([[cell font] pointSize] == 16, "MI-CLM-37 the names are drawn at the new size");
    PASS ([[col0 cmatrix] cellSize].height > small, "MI-CLM-38 a larger text size makes the rows taller");
    PASS ([[col0 cmatrix] numberOfRows] == 5, "MI-CLM-39 the folder is still shown after the change");
    [browser setLabelTextSize: 12];
    col0 = [browser columnWithPath: root];
  }

  /* --- show icons, icon preview ---------------------------------------- */
  PASS ([cellNamed (col0, @"mid.txt") icon] != nil, "MI-CLM-40 a row has its icon");
  PASS (isRed ([cellNamed (col0, @"pic.png") icon]),
        "MI-CLM-41 with icon preview an image shows its own picture");
  [browser setShowsIconPreview: NO];
  PASS (!isRed ([cellNamed (col0, @"pic.png") icon]) && [cellNamed (col0, @"pic.png") icon] != nil,
        "MI-CLM-42 without icon preview an image shows the icon of its type");
  [browser setShowsIconPreview: YES];
  PASS (isRed ([cellNamed (col0, @"pic.png") icon]), "MI-CLM-43 and the picture comes back");
  [browser setShowsIcons: NO];
  PASS ([cellNamed (col0, @"mid.txt") icon] == nil && [cellNamed (col0, @"pic.png") icon] == nil,
        "MI-CLM-44 without icons the rows show the names alone");
  [browser selectCellsWithNames: NAMES (@"dir") inColumnWithPath: root sendAction: YES];
  PASS ([[[browser columnWithPath: [root stringByAppendingPathComponent: @"dir"]] cmatrix] numberOfRows] == 1
        && [cellNamed ([browser columnWithPath: [root stringByAppendingPathComponent: @"dir"]], @"inner") icon] == nil,
        "MI-CLM-45 a column opened later has no icons either");
  [browser setShowsIcons: YES];
  PASS ([cellNamed (col0, @"mid.txt") icon] != nil, "MI-CLM-46 turning icons on shows them again");
  [browser selectCellsWithNames: [NSArray array] inColumnWithPath: root sendAction: YES];

  /* --- arrange by (orders of E25) --------------------------------------- */
  [browser setArrangement: FSNIconsArrangeNone];
  before = namesOf (col0);
  [browser setArrangement: FSNIconsArrangeName];
  PASS_EQUAL (namesOf (col0), NAMES (@"big.bin", @"dir", @"mid.txt", @"pic.png", @"small.rtf"),
              "MI-CLM-47 by name: A to Z, folders not first");
  [browser setArrangement: FSNIconsArrangeSize];
  PASS_EQUAL (namesOf (col0), NAMES (@"dir", @"pic.png", @"small.rtf", @"mid.txt", @"big.bin"),
              "MI-CLM-48 by size: folders first, then smallest first");
  [browser setArrangement: FSNIconsArrangeDateModified];
  PASS_EQUAL (namesOf (col0), NAMES (@"mid.txt", @"small.rtf", @"dir", @"big.bin", @"pic.png"),
              "MI-CLM-49 by date modified: newest first");
  [browser setArrangement: FSNIconsArrangeLabel];
  PASS_EQUAL (namesOf (col0), NAMES (@"mid.txt", @"pic.png", @"dir", @"big.bin", @"small.rtf"),
              "MI-CLM-50 by label: unlabelled first, then by label name");
  [browser setArrangement: FSNIconsArrangeKind];
  {
    NSArray *cells = [[col0 cmatrix] cells];
    BOOL sorted = YES;
    NSUInteger i;

    for (i = 1; i < [cells count]; i++)
      {
        NSString *a = [[[cells objectAtIndex: i - 1] node] typeDescription];
        NSString *b = [[[cells objectAtIndex: i] node] typeDescription];
        if ([a caseInsensitiveCompare: b] == NSOrderedDescending)
          sorted = NO;
      }
    PASS (sorted, "MI-CLM-51 by kind: alphabetical by the kind string");
  }
  [browser setArrangement: FSNIconsArrangeSize];
  [fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"aaa"] attributes: nil];
  [browser addCellsWithNames: NAMES (@"aaa") inColumnWithPath: root];
  PASS_EQUAL ([namesOf (col0) subarrayWithRange: NSMakeRange (0, 3)], NAMES (@"aaa", @"dir", @"pic.png"),
              "MI-CLM-52 an item that appears takes its place in the arrangement");
  [fm removeFileAtPath: [root stringByAppendingPathComponent: @"aaa"] handler: nil];
  [browser removeCellsWithNames: NAMES (@"aaa") inColumnWithPath: root];
  [browser setArrangement: FSNIconsArrangeNone];
  PASS_EQUAL (namesOf (col0), before, "MI-CLM-53 not arranged: the folder's own sort order again");

  /* --- column widths ------------------------------------------------------ */
  [browser tile];
  PASS ([browser widthOfColumnAtIndex: 0] == 205 && NSWidth ([col0 frame]) == 205,
        "MI-CLM-54 a column is 205 points wide");
  PASS (NSMinX ([[browser columnAfterColumn: col0] frame]) == 206,
        "MI-CLM-63 the next column starts after it, not stretched to fill the view");
  [browser setDefaultColumnWidth: 250];
  PASS ([browser defaultColumnWidth] == 250 && NSWidth ([col0 frame]) == 250,
        "MI-CLM-55 a default width is the width of every column");
  [browser setWidth: 300 forColumnAtIndex: 1];
  {
    NSView *c1 = [browser columnAfterColumn: col0];
    PASS ([browser widthOfColumnAtIndex: 1] == 300 && NSWidth ([c1 frame]) == 300
          && NSMinX ([c1 frame]) == 251,
          "MI-CLM-56 one column can be wider than the others");
  }
  PASS ([browser widthOfColumnAtIndex: 0] == 250 && [browser widthOfColumnAtIndex: 2] == 250,
        "MI-CLM-57 the other columns keep the default width");
  [browser setWidth: 10 forColumnAtIndex: 1];
  PASS ([browser widthOfColumnAtIndex: 1] == 100, "MI-CLM-58 a column is never narrower than 100 points");
  [browser setDefaultColumnWidth: 180];
  PASS ([browser widthOfColumnAtIndex: 1] == 180 && [browser widthOfColumnAtIndex: 0] == 180,
        "MI-CLM-59 setting the width of all columns replaces single column widths");

  /* --- the global options reach the browser ------------------------------ */
  [browser setWidth: 300 forColumnAtIndex: 1];
  [options setColumnWidth: 230];
  PASS ([browser defaultColumnWidth] == 230 && [browser widthOfColumnAtIndex: 1] == 230,
        "MI-CLM-60 the global column width (Option-drag) is every column's width");
  [options setShowsIcons: NO];
  PASS ([browser showsIcons] == NO && [cellNamed (col0, @"mid.txt") icon] == nil,
        "MI-CLM-61 a global option is applied to an open browser at once");
  [options setShowsIcons: YES];
  [options setArrangement: FSNIconsArrangeSize];
  PASS_EQUAL ([namesOf (col0) objectAtIndex: 0], @"dir", "MI-CLM-62 and so is the arrangement");
  [options setArrangement: FSNIconsArrangeName];

  /* --- preview column -------------------------------------------------- */
  [FSNBrowser setPreviewProvider: previews];
  [browser selectCellsWithNames: NAMES (@"mid.txt") inColumnWithPath: root sendAction: YES];
  {
    FSNBrowserColumn *pc = [browser columnAfterColumn: col0];
    FSNBrowserPreviewView *pv = [pc previewView];

    PASS ([browser lastColumnLoaded] == 1 && [[[pc previewNode] name] isEqual: @"mid.txt"],
          "MI-CLM-64 a selected file is previewed in the column after it");
    PASS ([previews->asked containsObject: [root stringByAppendingPathComponent: @"mid.txt"]]
          && [pv providedView] != nil && [[pv providedView] isDescendantOf: pv],
          "MI-CLM-65 the preview is the one the provider draws");
  }
  [browser selectCellsWithNames: NAMES (@"big.bin") inColumnWithPath: root sendAction: YES];
  {
    FSNBrowserPreviewView *pv = [[browser columnAfterColumn: col0] previewView];

    PASS ([pv providedView] == nil && [pv iconImage] != nil,
          "MI-CLM-66 without a preview from the provider the file's large icon is shown");
  }
  {
    NSArray *rows = [FSNBrowserPreviewView infoRowsForNode:
                       [FSNode nodeWithPath: [root stringByAppendingPathComponent: @"big.bin"]]];
    NSMutableArray *labels = [NSMutableArray array];
    NSUInteger i;

    for (i = 0; i < [rows count]; i++)
      [labels addObject: [[rows objectAtIndex: i] objectAtIndex: 0]];

    PASS_EQUAL ([[rows objectAtIndex: 0] lastObject], @"big.bin", "MI-CLM-67 the info starts with the name");
    PASS_EQUAL (labels, NAMES (@"Name:", @"Kind:", @"Size:", @"Created:", @"Modified:"),
                "MI-CLM-68 then kind, size, created and modified");
  }
  [browser selectCellsWithNames: NAMES (@"dir") inColumnWithPath: root sendAction: YES];
  PASS ([[browser lastLoadedColumn] previewNode] == nil
        && [[[browser lastLoadedColumn] shownNode] isEqual: [FSNode nodeWithPath: [root stringByAppendingPathComponent: @"dir"]]],
        "MI-CLM-69 a selected folder shows its contents, not a preview");
  [browser selectCellsWithNames: NAMES (@"mid.txt") inColumnWithPath: root sendAction: YES];
  [browser setShowsPreviewColumn: NO];
  PASS ([browser lastColumnLoaded] == 0 && [[browser columnAfterColumn: col0] previewNode] == nil,
        "MI-CLM-70 turning the preview column off removes it");
  [browser selectCellsWithNames: NAMES (@"small.rtf") inColumnWithPath: root sendAction: YES];
  PASS ([browser lastColumnLoaded] == 0, "MI-CLM-71 and no file selected later gets one");
  [browser setShowsPreviewColumn: YES];
  PASS ([browser lastColumnLoaded] == 1 && [[[[browser columnAfterColumn: col0] previewNode] name] isEqual: @"small.rtf"],
        "MI-CLM-72 turning it on previews the file selected");
  [browser selectCellsWithNames: NAMES (@"mid.txt", @"big.bin") inColumnWithPath: root sendAction: YES];
  PASS ([[browser columnAfterColumn: col0] previewNode] == nil, "MI-CLM-73 several selected files have no preview");

  /* --- deep paths: the last column is scrolled into view ------------- */
  {
    NSString *deep = [root stringByAppendingPathComponent: @"x/a/b/c"];
    FSNBrowser *b2;
    NSView *third;

    [fm createDirectoryAtPath: deep withIntermediateDirectories: YES attributes: nil error: NULL];
    b2 = [[FSNBrowser alloc] initWithBaseNode: [FSNode nodeWithPath: [root stringByAppendingPathComponent: @"x"]]
                               visibleColumns: 3
                                     scroller: nil
                                   cellsIcons: NO
                                   acceptsDnd: NO
                                editableCells: NO
                              selectionColumn: NO];
    [b2 setFrame: NSMakeRect (0, 0, 602, 300)];
    [b2 setDefaultColumnWidth: 205];
    [b2 loadColumnZero];
    [b2 tile];
    third = [b2 columnAfterColumn: [b2 columnAfterColumn: [b2 columnWithPath: [root stringByAppendingPathComponent: @"x"]]]];
    PASS (third != nil && NSMinX ([third frame]) == 412 && NSWidth ([third frame]) == 205,
          "MI-CLM-75 empty columns fill the view; the one at the edge is cut off");
    [b2 showSelection: [NSArray arrayWithObject: [FSNode nodeWithPath: deep]]];
    PASS ([b2 lastColumnLoaded] == 3 && [b2 lastVisibleColumn] == 3 && [b2 firstVisibleColumn] == 2,
          "MI-CLM-76 the deepest column is shown whole at the right, with the one before it");
    [b2 release];
  }

  [FSNBrowser setPreviewProvider: nil];
  [options setColumnWidth: 205];
  {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs removeObjectForKey: FSNColumnViewColumnWidthKey];
    [defs removeObjectForKey: FSNColumnViewArrangeByKey];
    [defs removeObjectForKey: FSNColumnViewShowsIconsKey];
    [defs removeObjectForKey: @"NSFontSize"];
  }
  [browser release];
  [rep setMetadataProvider: savedProvider];
  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
