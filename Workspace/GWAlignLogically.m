/* GWAlignLogically.m
 *
 * "View ▸ Align Logically" - semantic spatial arrangement.
 *
 * The algorithm follows the AlignLogically.md specification in four stages:
 *
 *   DISCOVER  - enumerate the visible icons
 *   UNDERSTAND - classify each icon's semantic role and importance
 *   COMPOSE   - pick an entry point and a primary subject, group into zones
 *   PLACE     - turn the composition into coordinates (last), then persist
 *
 * The spatial grammar is the classic one: entry material near the top, the
 * main object central, preparation (source/build) on the left, reference
 * (documentation/examples) on the right, secondary material lower down, and
 * technical machinery (dotfiles, CI) on the far periphery.  Every semantic
 * role is laid out on a SHARED grid: icons snap to the same row lines AND the
 * same column lines, so the whole composition reads as aligned in both axes;
 * each row is centred - an odd row sits on the centre column, an even row
 * straddles it with the centre column left empty - so every line is as
 * symmetric as the grid allows, and a long label reserves extra empty columns
 * instead of widening the pitch.  Layout is fully deterministic: the only
 * variation comes from a stable hash of the folder path and item name, so the
 * same directory always produces the same result.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "GWAlignLogically.h"
#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNode.h"
#import "GSFileMetadata.h"
#import "DSStoreInfo.h"
#import "GWViewSettingsManager.h"

/* Semantic roles.  Classification is intentionally probabilistic; an item's
 * role drives its importance and therefore its visual prominence. */
typedef NS_ENUM(NSInteger, GWAlignRole)
{
  GWAlignRoleEntryPoint = 0,
  GWAlignRoleEntryNote,         /* TODO, CHANGELOG, NEWS, ... near the README */
  GWAlignRolePrimaryArtifact,
  GWAlignRoleSource,
  GWAlignRoleDocumentation,
  GWAlignRoleExample,
  GWAlignRoleBuild,
  GWAlignRoleTest,
  GWAlignRoleProjectMetadata,
  GWAlignRoleDevInfrastructure,
  GWAlignRoleAsset,
  GWAlignRoleUtility,
  GWAlignRoleContainer,
  GWAlignRoleUnknown,
  GWAlignRoleCount
};

/* Spatial zones of the canvas. */
typedef NS_ENUM(NSInteger, GWAlignZone)
{
  GWAlignZoneEntry = 0,       /* upper region            */
  GWAlignZoneExamples,        /* just below the entry    */
  GWAlignZonePrimary,         /* central visual region   */
  GWAlignZonePreparation,     /* left-middle             */
  GWAlignZoneReference,       /* right-middle            */
  GWAlignZoneSecondary,       /* lower / peripheral      */
  GWAlignZoneTechnical,       /* farthest periphery      */
  GWAlignZoneCount
};

/* One discovered icon with its semantic profile. */
@interface GWAlignItem : NSObject
{
  FSNIcon *_icon;
  FSNode *_node;
  NSString *_name;
  GWAlignRole _role;
  GWAlignZone _zone;
  double _importance;
  double _userFacingness;
  NSPoint _center;
}

@property (nonatomic, assign) FSNIcon *icon;
@property (nonatomic, assign) FSNode *node;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) GWAlignRole role;
@property (nonatomic, assign) GWAlignZone zone;
@property (nonatomic, assign) double importance;
@property (nonatomic, assign) double userFacingness;
@property (nonatomic, assign) NSPoint center;

@end

@implementation GWAlignItem

@synthesize icon = _icon;
@synthesize node = _node;
@synthesize name = _name;
@synthesize role = _role;
@synthesize zone = _zone;
@synthesize importance = _importance;
@synthesize userFacingness = _userFacingness;
@synthesize center = _center;

@end

static double GWImportanceForRole(GWAlignRole role)
{
  switch (role)
    {
    case GWAlignRoleEntryPoint:       return 1.0;
    case GWAlignRoleEntryNote:        return 0.8;
    case GWAlignRolePrimaryArtifact:  return 1.0;
    case GWAlignRoleSource:           return 0.8;
    case GWAlignRoleDocumentation:    return 0.75;
    case GWAlignRoleExample:          return 0.6;
    case GWAlignRoleBuild:            return 0.5;
    case GWAlignRoleTest:             return 0.45;
    case GWAlignRoleProjectMetadata:  return 0.3;
    case GWAlignRoleDevInfrastructure:return 0.15;
    case GWAlignRoleAsset:            return 0.5;
    case GWAlignRoleUtility:          return 0.4;
    case GWAlignRoleContainer:        return 0.55;
    default:                          return 0.4;
    }
}

static double GWUserFacingnessForRole(GWAlignRole role)
{
  switch (role)
    {
    case GWAlignRoleEntryPoint:       return 1.0;
    case GWAlignRoleEntryNote:        return 0.95;
    case GWAlignRolePrimaryArtifact:  return 1.0;
    case GWAlignRoleSource:           return 0.5;
    case GWAlignRoleDocumentation:    return 0.9;
    case GWAlignRoleExample:          return 0.85;
    case GWAlignRoleBuild:            return 0.4;
    case GWAlignRoleTest:             return 0.3;
    case GWAlignRoleProjectMetadata:  return 0.55;
    case GWAlignRoleDevInfrastructure:return 0.05;
    case GWAlignRoleAsset:            return 0.6;
    case GWAlignRoleUtility:          return 0.4;
    case GWAlignRoleContainer:        return 0.6;
    default:                          return 0.5;
    }
}

static GWAlignZone GWZoneForRole(GWAlignRole role)
{
  switch (role)
    {
    case GWAlignRoleEntryPoint:
    case GWAlignRoleEntryNote:        return GWAlignZoneEntry;
    case GWAlignRoleExample:          return GWAlignZoneExamples;
    case GWAlignRolePrimaryArtifact:  return GWAlignZonePrimary;
    case GWAlignRoleSource:
    case GWAlignRoleBuild:            return GWAlignZonePreparation;
    case GWAlignRoleDocumentation:    return GWAlignZoneReference;
    case GWAlignRoleDevInfrastructure:return GWAlignZoneTechnical;
    default:                          return GWAlignZoneSecondary;
    }
}

static BOOL GWNameIs(NSString *name, NSArray *names)
{
  return [names containsObject: name];
}

@implementation GWAlignLogically

+ (instancetype)sharedAligner
{
  static GWAlignLogically *shared = nil;
  if (shared == nil)
    shared = [[self alloc] init];
  return shared;
}

/* ------------------------------------------------------------------ */
/* UNDERSTAND: classify a node into a semantic role.                   */
/* ------------------------------------------------------------------ */

- (GWAlignRole)roleForNode:(FSNode *)node
{
  NSString *name = [node lastPathComponent];
  if (!name) return GWAlignRoleUnknown;
  NSString *lowName = [name lowercaseString];
  NSString *base = [name stringByDeletingPathExtension];
  NSString *lowBase = [base lowercaseString];
  NSString *ext = [[name pathExtension] lowercaseString];

  if ([node isDirectory])
    {
      if (GWNameIs(lowName, @[@".github", @".git", @".svn", @".hg",
                              @".circleci", @".gitlab", @".idea", @".vscode"]))
        return GWAlignRoleDevInfrastructure;
      if (GWNameIs(lowName, @[@"src", @"source", @"sources", @"lib", @"libs",
                              @"include", @"includes", @"library", @"libraries",
                              @"code", @"impl", @"implementation"]))
        return GWAlignRoleSource;
      if (GWNameIs(lowName, @[@"docs", @"doc", @"documentation", @"manual",
                              @"manuals", @"guide", @"guides", @"reference",
                              @"ref", @"help", @"documents"]))
        return GWAlignRoleDocumentation;
      if (GWNameIs(lowName, @[@"example", @"examples", @"sample", @"samples",
                              @"demo", @"demos", @"tutorial", @"tutorials"]))
        return GWAlignRoleExample;
      if (GWNameIs(lowName, @[@"test", @"tests", @"spec", @"specs",
                              @"fixtures", @"snapshots", @"testing"]))
        return GWAlignRoleTest;
      if (GWNameIs(lowName, @[@"asset", @"assets", @"resources", @"images",
                              @"img", @"icons", @"icon", @"fonts", @"sounds",
                              @"audio", @"music", @"themes", @"theme",
                              @"templates", @"artwork", @"media"]))
        return GWAlignRoleAsset;
      if (GWNameIs(lowName, @[@"util", @"utils", @"utilities", @"tools",
                              @"bin", @"helpers", @"scripts", @"tool"]))
        return GWAlignRoleUtility;
      if (GWNameIs(lowName, @[@"extensions", @"plugins", @"plug-ins",
                              @"preferences", @"prefs", @"modules",
                              @"components", @"contrib", @"bundles"]))
        return GWAlignRoleContainer;
      return GWAlignRoleContainer;   /* folders are semantic landmarks */
    }

  /* Files */
  if ([node isApplication] || GWNameIs(ext, @[@"app", @"exe"]) ||
      GWNameIs(ext, @[@"dmg", @"pkg", @"installer"]))
    return GWAlignRolePrimaryArtifact;

  if (GWNameIs(lowBase, @[@"readme"]) || [lowBase hasPrefix: @"readme."] ||
      GWNameIs(lowBase, @[@"welcome", @"start", @"start-here", @"getting-started",
                          @"install", @"index", @"about"]) ||
      [lowBase hasPrefix: @"install-"])
    return GWAlignRoleEntryPoint;

  if (GWNameIs(lowBase, @[@"license", @"licence", @"copying", @"authors",
                          @"contributors", @"contributing", @"history",
                          @"notice", @"copyright"]))
    return GWAlignRoleProjectMetadata;
  /* Entry-adjacent notes belong around the README: TODO, CHANGELOG, NEWS,
   * FAQ and the like are human-facing status files, not reference docs. */
  if (GWNameIs(lowBase, @[@"todo", @"changelog", @"changes", @"news",
                          @"release-notes", @"faq", @"credits", @"thanks",
                          @"roadmap", @"known-issues"]))
    return GWAlignRoleEntryNote;

  /* GNUmakefile is the primary build artifact of a GNUstep project: it gets
   * the same central treatment as an application and a blue label. */
  if ([lowName isEqualToString: @"gnumakefile"])
    return GWAlignRolePrimaryArtifact;

  if (GWNameIs(lowName, @[@"makefile", @"cmakelists.txt",
                          @"package.json", @"cargo.toml", @"setup.py",
                          @"configure", @"configure.ac", @"setup", @"install.sh",
                          @"build.sh", @"build", @"cmake"]))
    return GWAlignRoleBuild;
  if (GWNameIs(ext, @[@"mk", @"cmake"]))
    return GWAlignRoleBuild;
  if ([ext isEqualToString: @"sh"] &&
      ([lowBase isEqualToString: @"build"] || [lowBase hasPrefix: @"build"] ||
       [lowBase isEqualToString: @"setup"] || [lowBase hasPrefix: @"setup"]))
    return GWAlignRoleBuild;

  if ([name hasPrefix: @"."])
    {
      /* User-relevant dotfiles stay visible; the rest is infrastructure. */
      if (GWNameIs(lowName, @[@".env.example", @".editorconfig", @".envrc",
                              @".gitmessage"]))
        return GWAlignRoleProjectMetadata;
      return GWAlignRoleDevInfrastructure;
    }

  if (GWNameIs(ext, @[@"c", @"h", @"m", @"mm", @"cpp", @"cc", @"cxx", @"hpp",
                      @"swift", @"py", @"rb", @"js", @"ts", @"tsx", @"jsx",
                      @"go", @"rs", @"java", @"kt", @"kts", @"scala", @"php",
                      @"pl", @"sh", @"s", @"asm", @"cs", @"m4", @"y", @"yy",
                      @"l", @"ll", @"xib", @"nib"]))
    return GWAlignRoleSource;

  if (GWNameIs(ext, @[@"md", @"markdown", @"txt", @"rtf", @"pdf", @"html",
                      @"htm", @"tex", @"rst", @"adoc", @"asciidoc", @"info",
                      @"man"]))
    return GWAlignRoleDocumentation;

  if ([lowName hasSuffix: @"_test"] || [lowName hasSuffix: @"-test"] ||
      [lowName hasSuffix: @".test"] || [ext isEqualToString: @"spec"])
    return GWAlignRoleTest;

  if (GWNameIs(ext, @[@"png", @"jpg", @"jpeg", @"gif", @"svg", @"ico", @"tiff",
                      @"bmp", @"webp", @"heic", @"wav", @"mp3", @"ogg", @"flac",
                      @"aiff", @"otf", @"ttf", @"woff", @"woff2", @"css",
                      @"scss", @"less", @"json", @"xml", @"yaml", @"yml",
                      @"plist"]))
    return GWAlignRoleAsset;

  return GWAlignRoleUnknown;
}

/* How user-facing an entry-point name is; higher is more prominent. */
- (double)entryPointRank:(NSString *)name
{
  NSString *base = [[name stringByDeletingPathExtension] lowercaseString];
  if ([base isEqualToString: @"readme"])
    {
      NSString *ext = [[name pathExtension] lowercaseString];
      if ([ext isEqualToString: @"md"] || [ext isEqualToString: @"markdown"])
        return 1.0;
      if ([ext length] == 0) return 0.9;
      if ([ext isEqualToString: @"txt"]) return 0.8;
      return 0.6;
    }
  if (GWNameIs(base, @[@"welcome", @"start", @"start-here",
                       @"getting-started", @"index"]))
    return 0.7;
  if ([base isEqualToString: @"about"] || [base isEqualToString: @"install"] ||
      [base hasPrefix: @"install"])
    return 0.5;
  return 0.0;
}

/* COMPOSE: keep the single best entry point; demote duplicate README-style
 * files so they do not all claim the top of the window. */
/* COMPOSE: keep the single best entry point; demote duplicate README-style
 * files so they do not all claim the top of the window.  Returns the chosen
 * entry item (nil when none exists). */
- (GWAlignItem *)selectEntryPointFromItems:(NSMutableArray *)items
{
  NSMutableArray *entries = [NSMutableArray array];
  for (GWAlignItem *item in items)
    if ([item role] == GWAlignRoleEntryPoint)
      [entries addObject: item];
  if ([entries count] == 0) return nil;

  if ([entries count] > 1)
    {
      [entries sortUsingComparator: ^(id a, id b)
        {
          double af = [self entryPointRank: [a name]];
          double bf = [self entryPointRank: [b name]];
          if (af < bf) return NSOrderedDescending;
          if (af > bf) return NSOrderedAscending;
          return [[a name] compare: [b name]];
        }];

      for (NSUInteger i = 1; i < [entries count]; i++)
        {
          GWAlignItem *it = [entries objectAtIndex: i];
          [it setRole: GWAlignRoleDocumentation];
          [it setImportance: GWImportanceForRole(GWAlignRoleDocumentation)];
          [it setUserFacingness: GWUserFacingnessForRole(GWAlignRoleDocumentation)];
        }
    }
  return [entries objectAtIndex: 0];
}

/* How strong a candidate is as the primary subject: applications and
 * installers outrank the GNUmakefile, which in turn outranks a plain
 * name-match. */
- (NSInteger)primaryPriorityForItem:(GWAlignItem *)item
{
  NSString *ext = [[item name] pathExtension];
  FSNode *node = [item node];
  if ((node && [node isApplication]) ||
      [ext isEqualToString: @"app"] || [ext isEqualToString: @"exe"] ||
      [ext isEqualToString: @"dmg"] || [ext isEqualToString: @"pkg"])
    return 3;
  if ([[[item name] lowercaseString] isEqualToString: @"gnumakefile"])
    return 2;
  return 1;
}

/* COMPOSE: pick the primary subject.  Prefers an application/artifact, then
 * the GNUmakefile (which is treated like an application and gets a blue
 * label), then an item whose name matches the folder name, then (in a pure
 * source repo) the most important source tree - never an arbitrary
 * tie-break between equally-scored candidates. */
- (GWAlignItem *)selectPrimaryFromItems:(NSArray *)items
                             folderPath:(NSString *)folderPath
{
  NSString *dirBase = [[[folderPath lastPathComponent]
                         stringByDeletingPathExtension] lowercaseString];
  NSMutableArray *candidates = [NSMutableArray array];

  for (GWAlignItem *item in items)
    {
      if ([item role] == GWAlignRolePrimaryArtifact)
        {
          [candidates addObject: item];
          continue;
        }
      NSString *base = [[[item name] stringByDeletingPathExtension]
                         lowercaseString];
      if ([base length] > 0 && [dirBase length] > 0 &&
          [base isEqualToString: dirBase])
        {
          [item setRole: GWAlignRolePrimaryArtifact];
          [item setImportance: 1.0];
          [item setUserFacingness: 1.0];
          [candidates addObject: item];
        }
    }

  if ([candidates count] > 0)
    {
      GWAlignItem *best = nil;
      NSInteger bestPriority = -1;
      double bestScore = -1.0;
      for (GWAlignItem *item in candidates)
        {
          NSInteger priority = [self primaryPriorityForItem: item];
          double score = [item importance];
          if (priority > bestPriority
              || (priority == bestPriority && score > bestScore))
            {
              bestPriority = priority;
              bestScore = score;
              best = item;
            }
        }
      return best;
    }

  GWAlignItem *subject = nil;
  double bestImp = -1.0;
  for (GWAlignItem *item in items)
    if ([item role] == GWAlignRoleSource && [item importance] > bestImp)
      {
        bestImp = [item importance];
        subject = item;
      }
  return subject;
}

/* ------------------------------------------------------------------ */
/* PLACE                                                               */
/* ------------------------------------------------------------------ */

/* The horizontal space an item needs: its icon plus its rendered label, with
 * a little gap so neighbouring labels never touch.  The label is measured
 * with the view's label font; when no font is available (e.g. the headless
 * test tool) a conservative per-character estimate is used instead. */
- (CGFloat)cellWidthForItem:(GWAlignItem *)item
                       base:(CGFloat)base
                  labelFont:(NSFont *)labelFont
{
  CGFloat w = 0;
  if (labelFont)
    {
      @try
        {
          w = [[item name] sizeWithAttributes:
                 [NSDictionary dictionaryWithObjectsAndKeys:
                   labelFont, NSFontAttributeName, nil]].width
              + 16.0;
        }
      @catch (NSException *e)
        {
          w = 0;
        }
    }
  if (w < 1.0)
    w = [[item name] length] * 8.0 + 24.0;
  return MAX(base, w + 8.0);
}

/* How many grid columns an item needs so its label never covers a neighbour.
 * The span is rounded UP and forced ODD: odd means the icon centre stays on a
 * grid line (an even span would centre the icon between two columns).  The
 * extra columns are left empty, so a long name overhangs into space. */
static NSUInteger GWColumnSpanForWidth(CGFloat w, CGFloat pitch)
{
  NSUInteger s = (NSUInteger)ceil(w / pitch);
  if (s < 1) s = 1;
  if ((s % 2) == 0) s += 1;
  return s;
}

/* Lay the items of one semantic role out on a SHARED grid: every icon snaps
 * to the same vertical grid lines (columns) AND the same horizontal grid
 * lines (rows), so the whole role reads as one aligned block.  Returns the
 * number of grid rows consumed.
 *
 * The grid has an ODD column count, centred on the canvas centreline, so the
 * README and the primary object land exactly on the centre.  Each row is then
 * centred on that centreline: a row whose items fill fewer columns than the
 * grid simply leaves the outer grid positions empty.  A row with an even
 * number of columns skips its CENTRE column so the two halves mirror each
 * other exactly - symmetry is bought by skipping grid positions, never by
 * nudging an icon off the grid.
 *
 * A label wider than the base column spans extra columns (odd count, so the
 * icon centre stays on a grid line) and those columns are left empty; the
 * long name overhangs into space instead of a neighbour.  Rows are packed
 * densely - filled up to the grid's column count - but stay homogeneous: a
 * row holds folders or files, never a mix.  Every item in a row shares the
 * SAME column span (the widest label in the row), so the spacing between all
 * items in a row is identical.  A label wider than the whole grid is clamped
 * to the grid width: the visible viewport is the upper limit for the width of
 * a line (layout is vertical-scrolling only).  Never more than one empty row. */
- (NSUInteger)placeItemsOnGrid:(NSArray *)items
                      startRow:(NSUInteger)startRow
                         slotW:(CGFloat)baseSlotW
                         slotH:(CGFloat)slotH
                        origin:(NSPoint)origin
                        bounds:(NSRect)bounds
                     labelFont:(NSFont *)labelFont
{
  NSUInteger n = [items count];
  if (n == 0) return 0;
  CGFloat margin = 14.0;
  CGFloat usableW = bounds.size.width - 2 * margin;

  /* One column pitch for the whole group: the base slot, so short names keep
   * the compact grid and every item in the role shares the same column lines.
   * A name wider than the pitch reserves extra columns instead of widening
   * the pitch. */
  CGFloat pitch = baseSlotW;

  /* ODD column count -> a true centre column on the canvas centreline. */
  NSUInteger cols = (NSUInteger)floor(usableW / pitch);
  if (cols < 1) cols = 1;
  if ((cols % 2) == 0) cols -= 1;
  NSUInteger centerCol = (cols - 1) / 2;
  CGFloat gridW = cols * pitch;
  CGFloat gridStartX = origin.x + (usableW - gridW) / 2.0;

  /* Each item's column span, precomputed so packing and placement agree.  A
   * span is capped at the grid width, and the label itself is capped there
   * too: the visible viewport width is the upper limit for the width of a
   * line (only vertical scrolling), so a name longer than the whole grid is
   * clamped and its box never overhangs the visible viewport. */
  NSUInteger *spans = calloc(n, sizeof(NSUInteger));
  NSUInteger si;
  for (si = 0; si < n; si++)
    {
      GWAlignItem *item = [items objectAtIndex: si];
      CGFloat w = [self cellWidthForItem: item base: baseSlotW
                              labelFont: labelFont];
      if (w > gridW) w = gridW;
      NSUInteger span = GWColumnSpanForWidth(w, pitch);
      if (span > cols) span = cols;
      spans[si] = span;
    }

  /* Reorder the items by kind, then by WIDEST span first.  A row keeps one
   * column span for every item (uniform spacing), so a wide label sets the
   * row's span; letting the widest items lead isolates them cleanly while
   * equal-width neighbours pack into full rows - the layout stays dense and
   * the spacing uniform.  Equal spans keep their importance order. */
  {
    NSMutableArray *bySpan = [NSMutableArray arrayWithCapacity: n];
    for (si = 0; si < n; si++)
      [bySpan addObject: [NSNumber numberWithUnsignedLong: si]];
    [bySpan sortUsingComparator: ^NSComparisonResult(id a, id b)
      {
        NSUInteger ia = [(NSNumber *)a unsignedLongValue];
        NSUInteger ib = [(NSNumber *)b unsignedLongValue];
        NSString *ka = [self kindKeyForItem: [items objectAtIndex: ia]];
        NSString *kb = [self kindKeyForItem: [items objectAtIndex: ib]];
        NSComparisonResult kr = [ka compare: kb];
        if (kr != NSOrderedSame) return kr;
        if (spans[ia] > spans[ib]) return NSOrderedAscending;
        if (spans[ia] < spans[ib]) return NSOrderedDescending;
        if (ia < ib) return NSOrderedAscending;
        if (ia > ib) return NSOrderedDescending;
        return NSOrderedSame;
      }];
    NSMutableArray *reordered = [NSMutableArray arrayWithCapacity: n];
    NSUInteger *spans2 = calloc(n, sizeof(NSUInteger));
    for (si = 0; si < n; si++)
      {
        NSUInteger from = [[bySpan objectAtIndex: si] unsignedLongValue];
        [reordered addObject: [items objectAtIndex: from]];
        spans2[si] = spans[from];
      }
    items = reordered;
    free(spans);
    spans = spans2;
  }

  NSUInteger idx = 0, r = 0;
  while (idx < n)
    {
      /* Pack the next row: only items of the SAME kind (folders or files,
       * never a mix - items are pre-sorted by kind so same-kind items are
       * contiguous).  Every item in a row shares ONE column span, the widest
       * in the row, so the spacing between all items in a row is identical;
       * a row only grows when the shared span still fits the grid. */
      NSString *rowKind = [self kindKeyForItem: [items objectAtIndex: idx]];
      NSMutableArray *rowItems = [NSMutableArray array];
      NSUInteger maxSpan = 0;
      NSUInteger probe = idx;
      while (probe < n
             && [[self kindKeyForItem: [items objectAtIndex: probe]]
                  isEqualToString: rowKind])
        {
          NSUInteger s = spans[probe];
          NSUInteger newMax = (s > maxSpan) ? s : maxSpan;
          if (([rowItems count] + 1) * newMax > cols) break;
          [rowItems addObject: [items objectAtIndex: probe]];
          maxSpan = newMax;
          probe++;
        }
      NSUInteger rowSpan = [rowItems count] * maxSpan;

      CGFloat y = origin.y + (startRow + r) * slotH + slotH / 2.0;

      if ((rowSpan % 2) == 1)
        {
          /* Odd row: a contiguous block with its middle column on the centre
           * column - no position is skipped.  Every item takes the shared
           * span, so the icons are evenly spaced. */
          NSUInteger col = centerCol - (rowSpan - 1) / 2;
          NSUInteger ri;
          for (ri = 0; ri < [rowItems count]; ri++)
            {
              GWAlignItem *item = [rowItems objectAtIndex: ri];
              NSUInteger first = col;
              NSUInteger last = col + maxSpan - 1;
              CGFloat x = gridStartX + ((first + last) / 2.0 + 0.5) * pitch;
              [item setCenter: NSMakePoint(x, y)];
              col += maxSpan;
            }
        }
      else
        {
          /* Even row: split the items into two halves on either side of the
           * centre column, which stays empty - exactly ONE grid position
           * skipped between the halves, never two.  The halves are equal when
           * the shared span is uniform, so the split is simply in the middle. */
          NSUInteger leftCount = [rowItems count] / 2;
          NSUInteger leftSpan = leftCount * maxSpan;

          /* The row occupies rowSpan + 1 columns (the halves plus one empty
           * column between them); centre that block on the centreline.  This
           * keeps every icon inside the grid: rowSpan <= cols, so the block
           * fits exactly within [0, cols-1] no matter where the split falls. */
          NSUInteger blockStart = centerCol - rowSpan / 2;
          NSUInteger col = blockStart;
          NSUInteger ri;
          for (ri = 0; ri < leftCount; ri++)
            {
              GWAlignItem *item = [rowItems objectAtIndex: ri];
              NSUInteger first = col;
              NSUInteger last = col + maxSpan - 1;
              CGFloat x = gridStartX + ((first + last) / 2.0 + 0.5) * pitch;
              [item setCenter: NSMakePoint(x, y)];
              col += maxSpan;
            }
          col = blockStart + leftSpan + 1;
          for (ri = leftCount; ri < [rowItems count]; ri++)
            {
              GWAlignItem *item = [rowItems objectAtIndex: ri];
              NSUInteger first = col;
              NSUInteger last = col + maxSpan - 1;
              CGFloat x = gridStartX + ((first + last) / 2.0 + 0.5) * pitch;
              [item setCenter: NSMakePoint(x, y)];
              col += maxSpan;
            }
        }
      idx = probe;
      r++;
    }
  free(spans);
  return r;
}

/* Sort a zone's items by descending importance so the most important ones
 * fill the earlier grid cells. */
/* The "kind" an item belongs to for row grouping: folders form one type,
 * every file another.  Rows then stay homogeneous - a row holds folders or
 * files, never a mix - which reads as tidy and hand-arranged. */
- (NSString *)kindKeyForItem:(GWAlignItem *)item
{
  FSNode *node = [item node];
  if (node && [node isDirectory])
    return @"folder";
  return @"file";
}

/* Sort a zone's items by kind (so every row holds folders or files, never a
 * mix), then by descending importance within a kind so the notable items
 * lead the group. */
- (NSArray *)sortZoneItems:(NSArray *)items
{
  return [items sortedArrayUsingComparator: ^(id a, id b)
    {
      NSString *ka = [self kindKeyForItem: a];
      NSString *kb = [self kindKeyForItem: b];
      NSComparisonResult kr = [ka compare: kb];
      if (kr != NSOrderedSame) return kr;
      double ia = [a importance];
      double ib = [b importance];
      if (ia > ib) return NSOrderedAscending;
      if (ia < ib) return NSOrderedDescending;
      return [[a name] compare: [b name]];
    }];
}

- (void)composePositionsForItems:(NSArray *)items
                          bounds:(NSRect)bounds
                        iconView:(FSNIconsView *)iconView
                      folderPath:(NSString *)folderPath
{
  int iconSize = 48;
  if ([iconView respondsToSelector: @selector(iconSize)])
    iconSize = [iconView iconSize];
  if (iconSize <= 0) iconSize = 48;

  /* Base cell: the icon glyph plus room for a typical label.  Rows that
   * contain longer labels widen their own pitch (see cellWidthForItem:), so
   * the base stays compact and only the affected rows use a wider grid. */
  CGFloat slotW = iconSize + 44;
  CGFloat slotH = iconSize + 28;

  /* The label font of the view, used to measure names so long labels get
   * extra empty grid columns.  Unavailable in a headless context, in which
   * case the estimate inside cellWidthForItem: is used. */
  NSFont *labelFont = nil;
  int labelTextSize = 13;
  if ([iconView respondsToSelector: @selector(labelTextSize)])
    labelTextSize = [iconView labelTextSize];
  if (labelTextSize <= 0) labelTextSize = 13;
  @try
    {
      labelFont = [NSFont systemFontOfSize: labelTextSize];
    }
  @catch (NSException *e)
    {
      labelFont = nil;
    }

  NSPoint origin = NSMakePoint(14.0, 14.0);

  NSMutableArray *zoneItems[GWAlignZoneCount];
  int zi;
  for (zi = 0; zi < GWAlignZoneCount; zi++)
    zoneItems[zi] = [NSMutableArray array];
  for (GWAlignItem *item in items)
    [zoneItems[[item zone]] addObject: item];

  NSUInteger row = 0;

  /* Entry band: the README alone on the top row, the entry-adjacent notes
   * (TODO, CHANGELOG, NEWS, ...) on the row right beneath it, and Examples
   * close to the top too - the human-facing start material.  One blank row
   * then separates the whole band from the rest of the composition. */
  NSMutableArray *entryPoints = [NSMutableArray array];
  NSMutableArray *entryNotes = [NSMutableArray array];
  for (GWAlignItem *item in zoneItems[GWAlignZoneEntry])
    {
      if ([item role] == GWAlignRoleEntryPoint)
        [entryPoints addObject: item];
      else
        [entryNotes addObject: item];
    }
  if ([entryPoints count] > 0)
    row += [self placeItemsOnGrid: entryPoints startRow: row
                         slotW: slotW slotH: slotH origin: origin bounds: bounds
                 labelFont: labelFont];
  if ([entryNotes count] > 0)
    {
      NSArray *sorted = [self sortZoneItems: entryNotes];
      row += [self placeItemsOnGrid: sorted startRow: row
                           slotW: slotW slotH: slotH origin: origin bounds: bounds
                 labelFont: labelFont];
    }
  if ([zoneItems[GWAlignZoneExamples] count] > 0)
    {
      NSArray *sorted = [self sortZoneItems: zoneItems[GWAlignZoneExamples]];
      row += [self placeItemsOnGrid: sorted startRow: row
                           slotW: slotW slotH: slotH origin: origin bounds: bounds
                 labelFont: labelFont];
    }
  if (row > 0)
    row += 1;

  /* Primary: centred, below the entry band. */
  if ([zoneItems[GWAlignZonePrimary] count] > 0)
    {
      NSArray *sorted = [self sortZoneItems: zoneItems[GWAlignZonePrimary]];
      row += [self placeItemsOnGrid: sorted startRow: row
                           slotW: slotW slotH: slotH origin: origin bounds: bounds
                 labelFont: labelFont];
    }

  /* Every remaining zone (preparation, reference, secondary, technical, in
   * that visual order) flows into ONE shared grid, packed densely - a row is
   * filled up to the grid's column count before advancing - so the bulk of
   * the layout never degenerates into rows holding only one or two icons.
   * Rows stay homogeneous (folders or files, never a mix) and every item in a
   * row shares one column span, so the spacing is uniform.  A strict left/
   * right split would waste half the canvas whenever one side dominates, so
   * the shared grid is centred across the whole width; the per-zone kind
   * grouping keeps the semantic layering within each kind. */
  static const GWAlignZone zoneOrder[] = {
    GWAlignZonePreparation, GWAlignZoneReference,
    GWAlignZoneSecondary, GWAlignZoneTechnical
  };
  NSUInteger zoneCount = sizeof(zoneOrder) / sizeof(zoneOrder[0]);
  NSMutableArray *allRemaining = [NSMutableArray array];
  NSUInteger zi2;
  for (zi2 = 0; zi2 < zoneCount; zi2++)
    {
      GWAlignZone zone = zoneOrder[zi2];
      if ([zoneItems[zone] count] == 0)
        continue;
      [allRemaining addObjectsFromArray: zoneItems[zone]];
    }
  if ([allRemaining count] > 0)
    {
      /* Sort the merged set by kind so folders form their own rows and files
       * theirs - never mixed - then by descending importance within a kind. */
      NSArray *sorted = [self sortZoneItems: allRemaining];
      row += [self placeItemsOnGrid: sorted startRow: row
                           slotW: slotW slotH: slotH origin: origin bounds: bounds
                 labelFont: labelFont];
    }
}

/* ------------------------------------------------------------------ */
/* Labels                                                              */
/* ------------------------------------------------------------------ */

/* Persist a label (FinderInfo xattr + .DS_Store lclr) for the item and paint
 * it on the icon.  Used to give a GNUmakefile a blue label (like an
 * application) and a README a green label.
 *
 * The label persistence classes (GSFileMetadata, DSStoreInfo,
 * GWViewSettingsManager) live in the Workspace/GWMetadata targets; they are
 * looked up by name so this file stays linkable in the standalone test tool
 * (same pattern as NSClassFromString elsewhere in Workspace). */
- (void)applyLabelToItem:(GWAlignItem *)item
             labelNumber:(NSInteger)labelNumber
            labelColor:(DSStoreLabelColor)labelColor
               colorRed:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue
{
  FSNode *node = [item node];
  if (!node) return;
  NSString *path = [node path];
  if (!path || [path length] == 0) return;

  id metaClass = NSClassFromString(@"GSFileMetadata");
  if (metaClass)
    {
      id md = [metaClass metadataForFileAtPath: path];
      if (!md) md = [[[metaClass alloc] init] autorelease];
      if (md)
        {
          [md setLabelNumber: labelNumber];
          NSError *err = nil;
          [md writeToFileAtPath: path error: &err];
        }
    }

  id dsInfoClass = NSClassFromString(@"DSStoreInfo");
  id iconInfoClass = NSClassFromString(@"DSStoreIconInfo");
  id settingsClass = NSClassFromString(@"GWViewSettingsManager");
  if (dsInfoClass && iconInfoClass && settingsClass)
    {
      NSString *parent = [path stringByDeletingLastPathComponent];
      NSString *filename = [path lastPathComponent];
      id dsInfo = [dsInfoClass infoForDirectoryPath: parent
                                    loadImmediately: NO];
      id iconInfo = [iconInfoClass infoForFilename: filename];
      [iconInfo setLabelColor: labelColor];
      [iconInfo setHasLabelColor: YES];
      [dsInfo setIconInfo: iconInfo forFilename: filename];
      id sm = [settingsClass managerForDirectoryPath: parent];
      [sm writeSettings: dsInfo];
    }

  [[item icon] setTagColor:
    [NSColor colorWithCalibratedRed: red green: green blue: blue alpha: 1.0]];
}

/* ------------------------------------------------------------------ */
/* Public entry point                                                  */
/* ------------------------------------------------------------------ */

- (BOOL)alignLogicallyInIconView:(FSNIconsView *)iconView
{
  if (!iconView) return NO;
  NSArray *icons = [iconView icons];
  NSUInteger count = [icons count];
  if (count == 0) return NO;

  NSRect bounds = [iconView bounds];
  if (bounds.size.width < 80 || bounds.size.height < 80) return NO;

  /* The layout is constrained to the VISIBLE viewport width: the enclosing
   * scroll view's content width (up to date after autoresize, already
   * accounting for sidebar/borders/scrollers).  The document view can be
   * wider than what is on screen, and a line must never exceed the visible
   * part - only vertical scrolling is wanted.  Height stays the document
   * height; rows simply stack downward from the origin. */
  if ([iconView respondsToSelector: @selector(windowContentWidthForLayout)])
    {
      CGFloat visibleW = [iconView windowContentWidthForLayout];
      if (visibleW >= 80)
        bounds.size.width = visibleW;
    }

  /* DISCOVER + UNDERSTAND */
  NSMutableArray *items = [NSMutableArray arrayWithCapacity: count];
  NSString *folderPath = nil;
  NSUInteger i;
  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNode *node = [icon node];
      GWAlignItem *item = [[GWAlignItem alloc] init];
      [item setIcon: icon];
      [item setNode: node];
      [item setName: (node ? [node lastPathComponent] : @"")];
      [item setRole: (node ? [self roleForNode: node] : GWAlignRoleUnknown)];
      [item setImportance: GWImportanceForRole([item role])];
      [item setUserFacingness: GWUserFacingnessForRole([item role])];
      if (node && folderPath == nil)
        folderPath = [[node path] stringByDeletingLastPathComponent];
      [items addObject: item];
      [item release];
    }
  if (folderPath == nil) folderPath = @"";

  /* COMPOSE: entry point + primary subject, then zone assignment. */
  GWAlignItem *entry = [self selectEntryPointFromItems: items];
  GWAlignItem *primary = [self selectPrimaryFromItems: items
                                           folderPath: folderPath];
  for (GWAlignItem *item in items)
    {
      GWAlignZone zone = GWZoneForRole([item role]);
      if (primary && item == primary) zone = GWAlignZonePrimary;
      [item setZone: zone];
    }

  /* A README gets a green label, the entry point of the directory; any
   * GNUmakefile gets a blue label, like an application - both persisted
   * before the positions so the two .DS_Store writes cooperate. */
  if (entry)
    [self applyLabelToItem: entry labelNumber: GSFileLabelGreen
               labelColor: DSStoreLabelColorGreen
                  colorRed: 0.3 green: 0.85 blue: 0.39];
  for (GWAlignItem *item in items)
    if ([[[item name] lowercaseString] isEqualToString: @"gnumakefile"])
      [self applyLabelToItem: item labelNumber: GSFileLabelBlue
                 labelColor: DSStoreLabelColorBlue
                    colorRed: 0.25 green: 0.61 blue: 0.98];

  /* PLACE + persist. */
  [self composePositionsForItems: items bounds: bounds
                       iconView: iconView folderPath: folderPath];

  NSMutableArray *centers = [NSMutableArray arrayWithCapacity: count];
  for (i = 0; i < count; i++)
    {
      GWAlignItem *item = [items objectAtIndex: i];
      [centers addObject: [NSValue valueWithPoint: [item center]]];
    }

  if ([iconView respondsToSelector: @selector(batchRepositionIcons:toCenterPoints:)])
    {
      [iconView batchRepositionIcons: icons toCenterPoints: centers];
      return YES;
    }
  return NO;
}

@end
