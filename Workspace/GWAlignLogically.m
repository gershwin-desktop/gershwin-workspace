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
 * technical machinery (dotfiles, CI) on the far periphery.  Layout is fully
 * deterministic: the only variation comes from a stable hash of the folder
 * path and item name, so the same directory always produces the same result.
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

/* Lay the items out in centred rows, packing each row with as many items as
 * fit across the canvas and assigning every centre to the item's own grid
 * column.  Returns the number of grid rows consumed.
 *
 * A row holds a single file type (folders together, files by extension).  The
 * column pitch is the item's own width (icon + label), so long names get
 * extra room instead of overhanging their neighbour: a row with long labels
 * simply uses a wider pitch, i.e. a different grid, and never lets two labels
 * touch.  Rows are filled left-to-right before advancing, so the layout stays
 * dense - there is never more than one empty row - and every row is centred
 * so the whole composition stays symmetrical. */
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
  NSUInteger idx = 0, r = 0;

  while (idx < n)
    {
      /* Pack the next row: one file type, up to the canvas width. */
      NSMutableArray *rowItems = [NSMutableArray array];
      NSString *rowKind = nil;
      CGFloat rowW = 0;
      while (idx < n)
        {
          GWAlignItem *item = [items objectAtIndex: idx];
          NSString *kind = [self kindKeyForItem: item];
          if (rowKind && ![kind isEqualToString: rowKind]) break;
          CGFloat w = [self cellWidthForItem: item base: baseSlotW
                                  labelFont: labelFont];
          if ([rowItems count] > 0 && rowW + w > usableW) break;
          [rowItems addObject: item];
          rowKind = kind;
          rowW += w;
          idx++;
        }

      /* Centre the row, then place each item at its own pitch. */
      CGFloat startX = origin.x + (usableW - rowW) / 2.0;
      CGFloat y = origin.y + (startRow + r) * slotH + slotH / 2.0;
      CGFloat x = startX;
      NSUInteger ri;
      for (ri = 0; ri < [rowItems count]; ri++)
        {
          GWAlignItem *item = [rowItems objectAtIndex: ri];
          CGFloat w = [self cellWidthForItem: item base: baseSlotW
                                  labelFont: labelFont];
          [item setCenter: NSMakePoint(x + w / 2.0, y)];
          x += w;
        }
      r++;
    }
  return r;
}

/* Sort a zone's items by descending importance so the most important ones
 * fill the earlier grid cells. */
/* The "kind" a file belongs to for row grouping: folders form one type, files
 * are grouped by extension.  Rows then stay homogeneous - one file type per
 * row - which reads as tidy and hand-arranged. */
- (NSString *)kindKeyForItem:(GWAlignItem *)item
{
  FSNode *node = [item node];
  if (node && [node isDirectory])
    return @"folder";
  NSString *ext = [[item name] pathExtension];
  if ([ext length] > 0)
    return [ext lowercaseString];
  return @"file";
}

/* Sort a zone's items by kind (so every row holds one file type), then by
 * descending importance within a kind so the notable items lead the group.
 * When a kind's tail does not fill a row it shares the row with the next
 * kind - the space-saving exception to the one-type-per-row rule. */
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
   * their own row pitch.  Unavailable in a headless context, in which case
   * the estimate inside cellWidthForItem: is used. */
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

  /* Every remaining zone becomes a full-width band of rows (preparation,
   * reference, secondary, technical, in that visual order).  A strict
   * left/right split would waste half the canvas whenever one side dominates,
   * so each band is centred across the whole width; the one-type-per-row
   * grouping and the band order keep the semantic layering. */
  static const GWAlignZone zoneOrder[] = {
    GWAlignZonePreparation, GWAlignZoneReference,
    GWAlignZoneSecondary, GWAlignZoneTechnical
  };
  NSUInteger zoneCount = sizeof(zoneOrder) / sizeof(zoneOrder[0]);
  NSUInteger zi2;
  for (zi2 = 0; zi2 < zoneCount; zi2++)
    {
      GWAlignZone zone = zoneOrder[zi2];
      if ([zoneItems[zone] count] == 0)
        continue;
      NSArray *sorted = [self sortZoneItems: zoneItems[zone]];
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
