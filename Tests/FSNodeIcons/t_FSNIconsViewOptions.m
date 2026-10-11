/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The icon view options Finder offers per folder (text size, show item info,
 * show icon preview, arrange by, snap to grid, scroll position), driven on a
 * real FSNIconsView in a scroll view over a real folder. */

#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import "Testing.h"
#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"

/* A view that keeps saved positions, like the spatial one. */
@interface PositionedIconsView : FSNIconsView
@end

@implementation PositionedIconsView
- (BOOL) honorsSavedPositions
{
  return YES;
}

/* Top-left coordinates, so saved positions mean the same at any view size. */
- (BOOL) isFlipped
{
  return YES;
}
@end

static NSString *dir;
static NSFileManager *fm;

static void
makeFile(NSString *name, NSUInteger size, NSTimeInterval age)
{
  NSString *path = [dir stringByAppendingPathComponent: name];
  NSMutableData *d = [NSMutableData dataWithLength: size];

  [d writeToFile: path atomically: YES];
  [fm changeFileAttributes:
        [NSDictionary dictionaryWithObject:
                        [NSDate dateWithTimeIntervalSinceNow: -age]
                                    forKey: NSFileModificationDate]
                    atPath: path];
}

static void
makePNG(NSString *name, NSInteger w, NSInteger h)
{
  NSBitmapImageRep *rep;
  NSInteger x, y;
  unsigned char *p;

  rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                pixelsWide: w
                                                pixelsHigh: h
                                             bitsPerSample: 8
                                           samplesPerPixel: 4
                                                  hasAlpha: YES
                                                  isPlanar: NO
                                            colorSpaceName: NSDeviceRGBColorSpace
                                               bytesPerRow: 0
                                              bitsPerPixel: 0];
  p = [rep bitmapData];
  for (y = 0; y < h; y++)
    for (x = 0; x < w; x++)
      {
        unsigned char *px = p + y * [rep bytesPerRow] + x * 4;

        px[0] = 255; px[1] = 0; px[2] = 0; px[3] = 255;
      }
  [[rep representationUsingType: NSPNGFileType properties: nil]
    writeToFile: [dir stringByAppendingPathComponent: name] atomically: YES];
  [rep release];
}

static NSString *
leaf(FSNIcon *icon)
{
  return [[icon node] lastPathComponent];
}

/* The names of the three plain text files, in the order the view lists
 * them; the other entries of the folder sort by rules of their own. */
static NSArray *
textOrder(FSNIconsView *view)
{
  NSMutableArray *names = [NSMutableArray array];
  NSArray *icons = [view icons];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      NSString *n = leaf([icons objectAtIndex: i]);

      if ([n hasSuffix: @".txt"])
        [names addObject: n];
    }
  return names;
}

static FSNIcon *
iconNamed(FSNIconsView *view, NSString *name)
{
  return [view repOfSubnodePath: [dir stringByAppendingPathComponent: name]];
}

static void
decorateAll(FSNIconsView *view)
{
  NSArray *icons = [view icons];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    [[icons objectAtIndex: i] decorate];
}

static NSScrollView *
hostedView(FSNIconsView *view, NSRect frame)
{
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame: frame] autorelease];

  [scroll setHasVerticalScroller: YES];
  [scroll setDocumentView: view];
  return scroll;
}

static NSColor *
centerColor(NSImage *image)
{
  NSBitmapImageRep *rep;

  rep = [NSBitmapImageRep imageRepWithData: [image TIFFRepresentation]];
  return [rep colorAtX: [rep pixelsWide] / 2 y: [rep pixelsHigh] / 2];
}

/* Label names and numbers for the arrange by label test. */
@interface LabelProvider : NSObject <FSNMetadataProvider>
@end

@implementation LabelProvider
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSZeroPoint; }
- (void)invalidateCaches {}
- (NSInteger)labelIndexForPath:(NSString *)path
{
  return [path hasSuffix: @"/b.txt"] ? 2 : ([path hasSuffix: @"/c.txt"] ? 1 : 0);
}
- (NSString *)labelNameForPath:(NSString *)path
{
  return [path hasSuffix: @"/b.txt"] ? @"Blue" : ([path hasSuffix: @"/c.txt"] ? @"Red" : nil);
}
@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* The expected texts are English; the framework's strings follow the
   * language of whoever runs the suite.  Set before the first lookup. */
  [[NSUserDefaults standardUserDefaults]
    setObject: [NSArray arrayWithObject: @"English"] forKey: @"NSLanguages"];
  FSNIconsView *view;
  NSArray *want;

  /* Views need a display server before AppKit will make any of them. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  fm = [NSFileManager defaultManager];
  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_FSNIconsViewOptions_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  makeFile(@"a.txt", 1, 100);
  makeFile(@"b.txt", 3000, 10);
  makeFile(@"c.txt", 200, 500);
  makePNG(@"d.png", 20, 10);
  [fm createDirectoryAtPath: [dir stringByAppendingPathComponent: @"Folder"]
                 attributes: nil];
  makeFile(@"Folder/x", 1, 1);
  makeFile(@"Folder/y", 1, 1);

  /* -init (not -initWithFrame:) assigns the fsnodeRep ivar. */
  view = [[FSNIconsView alloc] init];
  (void)hostedView(view, NSMakeRect(0, 0, 600, 400));
  [view showContentsOfNode: [FSNode nodeWithPath: dir]];
  decorateAll(view);

  /* --- label text size --- */
  {
    NSSize cell16, cell10;
    FSNIcon *a = iconNamed(view, @"a.txt");

    [view setLabelTextSize: 16];
    cell16 = [view gridCellSize];
    PASS([view labelTextSize] == 16, "MI-ICN-11 the label text size is the one set");
    PASS((int)[[a labelFont] pointSize] == 16,
         "MI-ICN-12 every icon draws its name at the new text size");
    [view setLabelTextSize: 10];
    cell10 = [view gridCellSize];
    PASS((int)[[a labelFont] pointSize] == 10,
         "MI-ICN-13 the smallest Finder text size is 10 points");
    PASS(cell16.height > cell10.height,
         "MI-ICN-14 a larger text size makes the grid cell taller so names fit");
    PASS(cell16.width > cell10.width,
         "MI-ICN-15 a larger text size makes the grid cell wider so names fit");
    PASS([FSNIconsView clampedLabelTextSize: 8] == 10
         && [FSNIconsView clampedLabelTextSize: 20] == 16
         && [FSNIconsView clampedLabelTextSize: 13] == 13,
         "MI-ICN-16 Finder's text sizes run from 10 to 16 points");
    [view setLabelTextSize: 12];
  }

  /* --- show item info --- */
  {
    NSSize without, with;

    PASS([view showsItemInfo] == NO, "MI-ICN-17 item info is off by default");
    without = [view gridCellSize];
    [view setShowsItemInfo: YES];
    with = [view gridCellSize];
    decorateAll(view);
    PASS([view showsItemInfo] == YES, "MI-ICN-18 item info can be turned on");
    PASS_EQUAL([iconNamed(view, @"Folder") itemInfo], @"2 items",
               "MI-ICN-19 a folder shows its item count under the name");
    PASS_EQUAL([iconNamed(view, @"a.txt") itemInfo], @"",
               "MI-ICN-20 [O:2026-10-11 E23] a plain file shows nothing under the name");
    PASS_EQUAL([iconNamed(view, @"d.png") itemInfo], @"20 \u00D7 10",
               "MI-ICN-21 an image shows its pixel size under the name");
    PASS(with.height > without.height,
         "MI-ICN-22 the grid cell grows by the info line");
    PASS([[iconNamed(view, @"Folder") itemInfo] length] > 0,
         "MI-ICN-23 every folder has an info line while the option is on");
    [view setShowsItemInfo: NO];
    PASS([[iconNamed(view, @"Folder") itemInfo] length] == 0,
         "MI-ICN-24 turning item info off takes the line away again");
    PASS([view gridCellSize].height == without.height,
         "MI-ICN-25 and gives the grid cell its old height back");
  }

  /* --- show icon preview --- */
  {
    NSImage *pngOn, *pngOff, *txtOn, *txtOff;
    NSColor *c;

    [view setIconSize: 64];
    [view setShowsIconPreview: YES];
    decorateAll(view);
    PASS([view showsIconPreview], "MI-ICN-26 [O:2026-10-11 E26] icon preview can be turned on");
    pngOn = [iconNamed(view, @"d.png") iconImage];
    txtOn = [iconNamed(view, @"a.txt") iconImage];
    c = [centerColor(pngOn) colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    PASS(pngOn != nil && [c redComponent] > 0.8 && [c greenComponent] < 0.2,
         "MI-ICN-27 an image file shows a thumbnail of its own pixels");

    [view setShowsIconPreview: NO];
    decorateAll(view);
    pngOff = [iconNamed(view, @"d.png") iconImage];
    txtOff = [iconNamed(view, @"a.txt") iconImage];
    c = [centerColor(pngOff) colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    PASS(pngOff != nil && !([c redComponent] > 0.8 && [c greenComponent] < 0.2
                            && [c blueComponent] < 0.2),
         "MI-ICN-28 [O:2026-10-11 E26] with preview off an image file shows the document type icon of the system, not a thumbnail");
    PASS(txtOn == txtOff,
         "MI-ICN-29 files that are not images look the same either way");
    [view setShowsIconPreview: YES];
  }

  /* --- arrange by --- */
  {
    PASS([view arrangement] == FSNIconsArrangeNone,
         "MI-ICN-30 icons are not arranged by default");

    [view setArrangement: FSNIconsArrangeName];
    want = [NSArray arrayWithObjects: @"a.txt", @"b.txt", @"c.txt", nil];
    PASS_EQUAL(textOrder(view), want, "MI-ICN-31 [O:2026-10-11 E25] arrange by name sorts A to Z, folders not first");

    [view setArrangement: FSNIconsArrangeSize];
    want = [NSArray arrayWithObjects: @"a.txt", @"c.txt", @"b.txt", nil];
    PASS_EQUAL(textOrder(view), want,
               "MI-ICN-32 [O:2026-10-11 E25] arrange by size puts the smallest first");
    PASS_EQUAL(leaf([[view icons] objectAtIndex: 0]), @"Folder",
               "MI-ICN-54 [O:2026-10-11 E25] and folders before files");

    [view setArrangement: FSNIconsArrangeDateModified];
    want = [NSArray arrayWithObjects: @"b.txt", @"a.txt", @"c.txt", nil];
    PASS_EQUAL(textOrder(view), want,
               "MI-ICN-33 [O:2026-10-11 E25] arrange by date modified puts the newest first");

    [[FSNodeRep sharedInstance] setMetadataProvider: [[LabelProvider new] autorelease]];
    [iconNamed(view, @"b.txt") setLabelIndex: 2];
    [iconNamed(view, @"c.txt") setLabelIndex: 1];
    [view setArrangement: FSNIconsArrangeLabel];
    want = [NSArray arrayWithObjects: @"a.txt", @"b.txt", @"c.txt", nil];
    PASS_EQUAL(textOrder(view), want,
               "MI-ICN-34 [O:2026-10-11 E25] arrange by label: unlabelled first, then by the label name (Blue of b before Red of c, whatever the numbers)");

    [view setArrangement: FSNIconsArrangeKind];
    {
      NSArray *kinds = [[view icons] valueForKeyPath: @"node.typeDescription"];
      NSArray *sorted = [kinds sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];

      PASS_EQUAL(kinds, sorted,
                 "MI-ICN-35 [O:2026-10-11 E25] arrange by kind is alphabetical by the kind string, folders have no precedence");
    }
    want = [NSArray arrayWithObjects: @"a.txt", @"b.txt", @"c.txt", nil];
    PASS_EQUAL(textOrder(view), want,
               "MI-ICN-36 items of one kind are ordered by name");

    [view setArrangement: FSNIconsArrangeNone];
    PASS([view arrangement] == FSNIconsArrangeNone,
         "MI-ICN-37 arranging can be switched off again");
  }

  /* Reading order of the icons in the grid follows the arrangement. */
  {
    FSNIcon *first, *second;

    [view setArrangement: FSNIconsArrangeSize];
    [view tile];
    first = iconNamed(view, @"b.txt");
    second = iconNamed(view, @"c.txt");
    PASS(NSMinX([first frame]) < NSMinX([second frame])
         || NSMaxY([first frame]) > NSMaxY([second frame]),
         "MI-ICN-38 the arranged order is the reading order of the grid");
    [view setArrangement: FSNIconsArrangeNone];
  }

  [view release];

  /* --- snap to grid --- */
  {
    PositionedIconsView *pv = [[PositionedIconsView alloc] init];
    NSScrollView *ps = hostedView(pv, NSMakeRect(0, 0, 600, 500));
    NSPoint origin;
    NSSize cell;
    CGFloat gap;
    NSDictionary *pos;
    NSRect fa, fb, arrangedFrame;
    NSPoint ca, cb, off, wantA;
    NSPoint back;

    (void)ps;
    [pv showContentsOfNode: [FSNode nodeWithPath: dir]];
    decorateAll(pv);
    [pv tile];
    origin = [pv gridOriginForLayout];
    cell = [pv gridCellSize];
    gap = [pv gridColumnGap];

    /* A spot a few points off the center of the cell in column 2, row 1,
     * and another off the same cell the other way. */
    wantA = [pv centerForGridCell: FSNGridCellMake(2, 1)
                         cellSize: cell gapX: gap origin: origin];
    off = NSMakePoint(wantA.x + 9, wantA.y + 7);
    pos = [NSDictionary dictionaryWithObjectsAndKeys:
             [NSValue valueWithPoint: [pv ilocCenterForViewCenter: off]], @"a.txt",
             [NSValue valueWithPoint: [pv ilocCenterForViewCenter:
                 NSMakePoint(wantA.x - 4, wantA.y - 2)]], @"b.txt",
             [NSValue valueWithPoint: [pv ilocCenterForViewCenter:
                 [pv centerForGridCell: FSNGridCellMake(6, 3)
                              cellSize: cell gapX: gap origin: origin]]], @"c.txt",
             [NSValue valueWithPoint: [pv ilocCenterForViewCenter:
                 [pv centerForGridCell: FSNGridCellMake(7, 3)
                              cellSize: cell gapX: gap origin: origin]]], @"d.png",
             [NSValue valueWithPoint: [pv ilocCenterForViewCenter:
                 [pv centerForGridCell: FSNGridCellMake(8, 3)
                              cellSize: cell gapX: gap origin: origin]]], @"Folder",
             nil];
    [pv setCustomIconPositions: pos];
    [pv tile];
    fa = [iconNamed(pv, @"a.txt") frame];
    ca = NSMakePoint(NSMidX(fa), NSMidY(fa));
    PASS(fabs(ca.x - off.x) < 0.5 && fabs(ca.y - off.y) < 0.5,
         "MI-ICN-39 without snap an icon stays exactly where it was put");

    [pv setSnapsToGrid: YES];
    [pv tile];
    fa = [iconNamed(pv, @"a.txt") frame];
    fb = [iconNamed(pv, @"b.txt") frame];
    ca = NSMakePoint(NSMidX(fa), NSMidY(fa));
    cb = NSMakePoint(NSMidX(fb), NSMidY(fb));
    PASS([pv snapsToGrid], "MI-ICN-40 snap to grid can be turned on");
    PASS(fabs(ca.x - wantA.x) < 0.5 && fabs(ca.y - wantA.y) < 0.5,
         "MI-ICN-41 with snap an icon moves to the center of the nearest cell");

    back = [pv centerForGridCell: [pv gridCellForCenter: cb cellSize: cell
                                                   gapX: gap origin: origin]
                        cellSize: cell gapX: gap origin: origin];
    PASS(fabs(back.x - cb.x) < 0.5 && fabs(back.y - cb.y) < 0.5,
         "MI-ICN-42 a snapped icon sits exactly on a grid cell center");
    PASS(fabs(cb.x - ca.x) < 0.5 && fabs(cb.y - ca.y) < 0.5,
         "MI-ICN-43 [O:2026-10-11 E25] two icons that want one cell both take it, there is no collision handling");

    [pv setArrangement: FSNIconsArrangeName];
    [pv tile];
    fa = [iconNamed(pv, @"a.txt") frame];
    PASS([pv snapsToGrid] && [pv arrangement] == FSNIconsArrangeName
         && (fabs(NSMidX(fa) - wantA.x) > 1.0 || fabs(NSMidY(fa) - wantA.y) > 1.0),
         "MI-ICN-44 an arrangement ignores saved positions, snap stays a separate switch");

    arrangedFrame = fa;
    [pv setArrangement: FSNIconsArrangeNone];
    [pv tile];
    fa = [iconNamed(pv, @"a.txt") frame];
    PASS(NSEqualRects(fa, arrangedFrame),
         "MI-ICN-45 icons stay where the arrangement put them when it is switched off");
    [pv release];
  }

  /* --- scroll position --- */
  {
    NSScrollView *ss;
    FSNIconsView *sv;
    NSPoint got;
    NSString *big = [dir stringByAppendingPathComponent: @"many"];
    NSUInteger i;

    [fm createDirectoryAtPath: big attributes: nil];
    for (i = 0; i < 80; i++)
      [@"x" writeToFile: [big stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"f%03u.txt", (unsigned)i]]
             atomically: YES];

    sv = [[FSNIconsView alloc] init];
    ss = hostedView(sv, NSMakeRect(0, 0, 300, 200));
    [sv showContentsOfNode: [FSNode nodeWithPath: big]];
    [sv tile];

    got = [sv scrollPosition];
    PASS(fabs(got.x) < 0.5 && fabs(got.y) < 0.5,
         "MI-ICN-46 a freshly shown folder is scrolled to its top left");

    [sv setScrollPosition: NSMakePoint(0, 120)];
    [sv tile];
    got = [sv scrollPosition];
    PASS(fabs(got.x) < 0.5 && fabs(got.y - 120) < 0.5,
         "MI-ICN-47 the scroll position set is the one reported, measured from the top");
    PASS(fabs(NSMaxY([sv visibleRect]) - (NSMaxY([sv bounds]) - 120)) < 0.5,
         "MI-ICN-48 y counts down from the top edge of the content");

    [sv setScrollPosition: NSMakePoint(0, 100000)];
    [sv tile];
    got = [sv scrollPosition];
    PASS(got.y < 100000 && NSMinY([sv visibleRect]) >= -0.5,
         "MI-ICN-49 a position beyond the content is held inside it");
    [sv release];
    (void)ss;
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
