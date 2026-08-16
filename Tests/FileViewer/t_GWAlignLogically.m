/* t_GWAlignLogically.m — ObjectTesting coverage for the semantic classifier
 * behind "View ▸ Arrange Logically".
 *
 * The classifier is the heart of the feature: it decides which role every
 * icon plays (entry point, primary artifact, source, documentation, ...)
 * which drives where the icon ends up.  This exercises it against a typical
 * repository layout and verifies the roles the AlignLogically.md spec
 * requires.  GWAlignLogically.m is compiled in-process; the FSNode class
 * (needed to create the nodes) is linked from the FSNode framework.
 *
 * Runs headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>
#include <math.h>

#include "../../Workspace/GWAlignLogically.m"

@interface GWAlignLogically (Testing)
- (NSUInteger)roleForNode:(FSNode *)node;
- (GWAlignItem *)selectEntryPointFromItems:(NSMutableArray *)items;
- (GWAlignItem *)selectPrimaryFromItems:(NSArray *)items
                             folderPath:(NSString *)folderPath;
- (void)composePositionsForItems:(NSArray *)items
                          bounds:(NSRect)bounds
                        iconView:(FSNIconsView *)iconView
                      folderPath:(NSString *)folderPath;
- (CGFloat)cellWidthForItem:(GWAlignItem *)item
                       base:(CGFloat)base
                  labelFont:(NSFont *)labelFont;
@end

static BOOL
checkRole(NSString *dir, NSString *name, NSUInteger expected)
{
  FSNode *node = [FSNode nodeWithPath:
                   [dir stringByAppendingPathComponent: name]];
  NSUInteger role = [[GWAlignLogically sharedAligner] roleForNode: node];
  if (role != expected)
    NSLog (@"%s: %@ classified as role %lu, expected %lu",
           __PRETTY_FUNCTION__, name, (unsigned long)role,
           (unsigned long)expected);
  return role == expected;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_gwalign_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  NSArray *subdirs = @[@"src", @"docs", @"examples", @"tests", @".github",
                       @"images", @"bin"];
  NSArray *files = @[@"README.md", @"README.txt", @"LICENSE",
                     @"CONTRIBUTING.md", @"CHANGELOG.md", @"TODO",
                     @"Makefile", @"GNUmakefile", @"package.json", @".gitignore",
                     @".env.example", @"MyApp.app", @"Notes.txt", @"data.bin"];
  NSUInteger si;
  for (si = 0; si < [subdirs count]; si++)
    [fm createDirectoryAtPath:
          [dir stringByAppendingPathComponent: [subdirs objectAtIndex: si]]
        attributes: nil];
  NSUInteger fi;
  for (fi = 0; fi < [files count]; fi++)
    [fm createFileAtPath:
          [dir stringByAppendingPathComponent: [files objectAtIndex: fi]]
        contents: [NSData data] attributes: nil];

  PASS(checkRole(dir, @"README.md", GWAlignRoleEntryPoint),
       "README.md is ENTRY_POINT");
  PASS(checkRole(dir, @"MyApp.app", GWAlignRolePrimaryArtifact),
       "MyApp.app is PRIMARY_ARTIFACT");
  PASS(checkRole(dir, @"LICENSE", GWAlignRoleProjectMetadata),
       "LICENSE is PROJECT_METADATA");
  PASS(checkRole(dir, @"CONTRIBUTING.md", GWAlignRoleProjectMetadata),
       "CONTRIBUTING.md is PROJECT_METADATA");
  PASS(checkRole(dir, @"CHANGELOG.md", GWAlignRoleEntryNote),
       "CHANGELOG.md is ENTRY_NOTE");
  PASS(checkRole(dir, @"TODO", GWAlignRoleEntryNote),
       "TODO is ENTRY_NOTE");
  PASS(checkRole(dir, @"Makefile", GWAlignRoleBuild),
       "Makefile is BUILD");
  PASS(checkRole(dir, @"package.json", GWAlignRoleBuild),
       "package.json is BUILD");
  PASS(checkRole(dir, @"GNUmakefile", GWAlignRolePrimaryArtifact),
       "GNUmakefile is PRIMARY_ARTIFACT");  PASS(checkRole(dir, @"src", GWAlignRoleSource),
       "src/ is SOURCE");
  PASS(checkRole(dir, @"docs", GWAlignRoleDocumentation),
       "docs/ is DOCUMENTATION");
  PASS(checkRole(dir, @"examples", GWAlignRoleExample),
       "examples/ is EXAMPLE");
  PASS(checkRole(dir, @"tests", GWAlignRoleTest),
       "tests/ is TEST");
  PASS(checkRole(dir, @".github", GWAlignRoleDevInfrastructure),
       ".github/ is DEVELOPMENT_INFRASTRUCTURE");
  PASS(checkRole(dir, @".gitignore", GWAlignRoleDevInfrastructure),
       ".gitignore is DEVELOPMENT_INFRASTRUCTURE");
  PASS(checkRole(dir, @".env.example", GWAlignRoleProjectMetadata),
       ".env.example is PROJECT_METADATA");
  PASS(checkRole(dir, @"images", GWAlignRoleAsset),
       "images/ is ASSET");
  PASS(checkRole(dir, @"bin", GWAlignRoleUtility),
       "bin/ is UTILITY");
  PASS(checkRole(dir, @"Notes.txt", GWAlignRoleDocumentation),
       "Notes.txt is DOCUMENTATION");
  PASS(checkRole(dir, @"data.bin", GWAlignRoleUnknown),
       "data.bin is UNKNOWN");

  /* Duplicate entry files: README.md outranks README.txt as the entry point,
   * so only README.md keeps ENTRY_POINT. */
  {
    GWAlignLogically *aligner = [GWAlignLogically sharedAligner];
    NSMutableArray *items = [NSMutableArray array];
    NSArray *entryNames = @[@"README.md", @"README.txt"];
    NSUInteger ei;
    for (ei = 0; ei < [entryNames count]; ei++)
      {
        FSNode *node = [FSNode nodeWithPath:
                         [dir stringByAppendingPathComponent:
                           [entryNames objectAtIndex: ei]]];
        GWAlignItem *item = [[GWAlignItem alloc] init];
        [item setNode: node];
        [item setName: [node lastPathComponent]];
        [item setRole: [aligner roleForNode: node]];
        [item setImportance:
          GWImportanceForRole([item role])];
        [item setUserFacingness:
          GWUserFacingnessForRole([item role])];
        [items addObject: item];
        [item release];
      }
    [aligner selectEntryPointFromItems: items];
    GWAlignItem *best = [items objectAtIndex: 0];
    GWAlignItem *other = [items objectAtIndex: 1];
    PASS([best role] == GWAlignRoleEntryPoint
         && [other role] == GWAlignRoleDocumentation,
         "selectEntryPointFromItems keeps README.md and demotes README.txt");
  }

  /* --- placement: no two icons may ever overlap, even with many items ---- */
  {
    GWAlignLogically *aligner = [GWAlignLogically sharedAligner];
    NSMutableArray *items = [NSMutableArray array];
    NSArray *names = @[@"README.md", @"MyApp.app", @"src", @"docs",
                       @"examples", @"tests", @"Makefile", @"LICENSE",
                       @"CONTRIBUTING.md", @"CHANGELOG.md", @".github",
                       @".gitignore", @"Notes.txt", @"data.bin",
                       @"00000000-0000-0000-0000-000000000000.spice",
                       @"a.spice", @"b.spice", @"c.spice", @"d.spice",
                       @"e.spice", @"f.spice", @"g.spice", @"h.spice",
                       @"i.spice", @"j.spice", @"k.spice", @"l.spice",
                       @"m.spice", @"n.spice", @"o.spice", @"p.spice"];
    NSUInteger ni;
    for (ni = 0; ni < [names count]; ni++)
      {
        FSNode *node = [FSNode nodeWithPath:
                         [dir stringByAppendingPathComponent:
                           [names objectAtIndex: ni]]];
        GWAlignItem *item = [[GWAlignItem alloc] init];
        [item setIcon: nil];
        [item setNode: node];
        [item setName: [node lastPathComponent]];
        [item setRole: [aligner roleForNode: node]];
        [item setImportance: GWImportanceForRole([item role])];
        [item setUserFacingness: GWUserFacingnessForRole([item role])];
        [items addObject: item];
        [item release];
      }

    [aligner selectEntryPointFromItems: items];
    GWAlignItem *primary = [aligner selectPrimaryFromItems: items
                                                folderPath: dir];
    for (GWAlignItem *item in items)
      {
        GWAlignZone zone = GWZoneForRole([item role]);
        if (primary && item == primary) zone = GWAlignZonePrimary;
        [item setZone: zone];
      }

    NSRect bounds = NSMakeRect(0, 0, 1000, 1400);
    [aligner composePositionsForItems: items bounds: bounds
                            iconView: nil folderPath: dir];

    /* No two items may overlap, and every item must stay inside the canvas
     * width.  Because icons are nil here, each item's label width is measured
     * from its name (the same fallback the implementation uses), so the cell
     * width already includes room for the label - overlap here means the
     * placement itself is wrong. */
    BOOL onCanvas = YES;
    BOOL overlap = NO;
    NSMutableArray *rects = [NSMutableArray array];
    NSMutableArray *centers = [NSMutableArray array];
    /* The layout clamps a label wider than the whole grid to the grid width
     * (the viewport is the upper limit for the width of a line), so mirror
     * that cap here when building each icon's box. */
    CGFloat usableW = bounds.size.width - 2 * 14.0;
    NSUInteger cols = (NSUInteger)floor(usableW / 92.0);
    if (cols < 1) cols = 1;
    if ((cols % 2) == 0) cols -= 1;
    CGFloat gridW = cols * 92.0;
    for (GWAlignItem *item in items)
      {
        NSPoint c = [item center];
        [centers addObject: [NSValue valueWithPoint: c]];
        CGFloat w = [aligner cellWidthForItem: item base: 92.0 labelFont: nil];
        if (w > gridW) w = gridW;
        NSRect r = NSMakeRect(c.x - w / 2.0, c.y - 24.0, w, 48.0);
        if (r.origin.x < 0 ||
            (r.origin.x + r.size.width) > bounds.size.width)
          onCanvas = NO;
        for (NSValue *v in rects)
          if (NSIntersectsRect(r, [v rectValue]))
            overlap = YES;
        [rects addObject: [NSValue valueWithRect: r]];
      }
    PASS(onCanvas, "placement keeps every icon within the canvas width");
    PASS(!overlap, "labels never overlap - long names widen their own row");

    /* Every icon centre must fall on a shared grid line in BOTH axes: rows
     * share a y line, columns share an x line.  Each role is placed on one
     * grid whose columns are centred on the canvas centreline. */
    {
      CGFloat margin = 14.0;
      CGFloat usableW = bounds.size.width - 2 * margin;
      CGFloat pitch = 92.0;
      NSUInteger cols = (NSUInteger)floor(usableW / pitch);
      if (cols < 1) cols = 1;
      if ((cols % 2) == 0) cols -= 1;
      CGFloat gridW = cols * pitch;
      CGFloat gridStartX = margin + (usableW - gridW) / 2.0;

      BOOL onGridX = YES;
      for (NSValue *v in centers)
        {
          CGFloat x = [v pointValue].x;
          CGFloat colFloat = (x - gridStartX) / pitch - 0.5;
          long col = (long)llround(colFloat);
          if (col < 0 || col >= (long)cols
              || fabs(colFloat - col) > 0.01)
            onGridX = NO;
        }
      PASS(onGridX, "every icon centre falls on a shared vertical grid line");
    }

    /* The README, the entry point, must sit exactly on the horizontal centre
     * of the canvas. */
    {
      BOOL readmeCentered = NO;
      for (GWAlignItem *item in items)
        if ([[item name] isEqualToString: @"README.md"])
          readmeCentered = (fabs([item center].x - bounds.size.width / 2.0) < 1.0);
      PASS(readmeCentered, "README is centred horizontally");
    }

    /* A label wider than the whole grid is clamped to the grid width, so no
     * line ever exceeds the viewport width (vertical-only scrolling). */
    {
      CGFloat usableW2 = bounds.size.width - 2 * 14.0;
      NSUInteger cols2 = (NSUInteger)floor(usableW2 / 92.0);
      if (cols2 < 1) cols2 = 1;
      if ((cols2 % 2) == 0) cols2 -= 1;
      CGFloat gridW2 = cols2 * 92.0;

      FSNode *node = [FSNode nodeWithPath:
                       [dir stringByAppendingPathComponent:
                         @"a-name-far-too-long-to-ever-fit-inside-the-viewport-width-"
                         @"and-keeps-growing-and-growing-beyond-every-reasonable-"
                         @"column-count.txt"]];
      GWAlignItem *wide = [[GWAlignItem alloc] init];
      [wide setIcon: nil];
      [wide setNode: node];
      [wide setName: [node lastPathComponent]];
      [wide setRole: GWAlignRoleDocumentation];
      [wide setZone: GWAlignZoneReference];
      [aligner composePositionsForItems: @[wide] bounds: bounds
                              iconView: nil folderPath: dir];
      CGFloat rawW = [aligner cellWidthForItem: wide base: 92.0
                                     labelFont: nil];
      CGFloat w = (rawW > gridW2) ? gridW2 : rawW;
      CGFloat c = [wide center].x;
      BOOL fits = (c - w / 2.0 >= 0)
                  && (c + w / 2.0 <= bounds.size.width);
      PASS(rawW > gridW2 && fits,
           "labels wider than the grid are clamped to the viewport width");
      [wide release];
    }

    /* The bulk zones (preparation, reference, secondary, technical) share one
     * grid and pack to the column count, so after the entry band and the
     * primary at most one row may hold fewer than three items.  A layout full
     * of rows with only 1-2 icons is a failure. */
    {
      double slotH = 48.0 + 28.0;
      double baseY = 14.0 + slotH / 2.0;
      NSInteger maxRow = (NSInteger)(1400.0 / slotH) + 1;
      NSUInteger *rowCount = calloc(maxRow + 1, sizeof(NSUInteger));
      BOOL *isBulk = calloc(maxRow + 1, sizeof(BOOL));
      for (GWAlignItem *item in items)
        {
          long r = (long)llround(([item center].y - baseY) / slotH);
          if (r < 0 || r > maxRow) continue;
          rowCount[r]++;
          GWAlignZone z = [item zone];
          if (z != GWAlignZoneEntry && z != GWAlignZoneExamples
              && z != GWAlignZonePrimary)
            isBulk[r] = YES;
        }
      NSInteger sparse = 0;
      NSInteger r2;
      for (r2 = 0; r2 <= maxRow; r2++)
        if (isBulk[r2] && rowCount[r2] < 3)
          sparse++;
      PASS(sparse <= 1, "bulk rows are dense - at most one sparse row");
      free(rowCount);
      free(isBulk);
    }

    /* No more than one empty row: consecutive filled grid rows must not be
     * separated by more than one empty row (row indices differ by at most 2).
     * Rows are identified from the snapped y centres. */
    {
      double slotH = 48.0 + 28.0;
      double baseY = 14.0 + slotH / 2.0;
      NSMutableSet *rows = [NSMutableSet set];
      for (NSValue *v in centers)
        {
          long r = (long)llround(([v pointValue].y - baseY) / slotH);
          [rows addObject: [NSNumber numberWithLong: r]];
        }
      NSArray *sortedRows = [[rows allObjects]
                              sortedArrayUsingSelector: @selector(compare:)];
      BOOL compact = YES;
      NSUInteger ri;
      for (ri = 1; ri < [sortedRows count]; ri++)
        {
          long prev = [(NSNumber *)[sortedRows objectAtIndex: ri - 1] longValue];
          long cur = [(NSNumber *)[sortedRows objectAtIndex: ri] longValue];
          if (cur - prev > 2) compact = NO;
        }
      PASS(compact, "no more than one empty row in the layout");
    }
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp drain];
  return 0;
}
