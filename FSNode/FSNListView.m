/* FSNListView.m
 *
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
 * Date: December 2004
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

#include <math.h>
#include <unistd.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNListView.h"
#import "FSNListRowModel.h"
#import "FSNTextCell.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"
#import "FSNLocationFile.h"
#import "FSNIconLoader.h"
#import "FSNDirEntry.h"
#import "FSNRenamePolicy.h"

#include <sys/stat.h>
#if !defined(_WIN32)
#include <dirent.h>
#endif
#include <limits.h>

#define HLIGHT_H_FACT (0.8125)

/* The reference list view shows 16 point icons in 19 point rows of 12 point
 * text, a point below the system font; anything bigger wastes a third of
 * the window on whitespace. */
#define DEFAULT_LIST_ICON_SIZE (16)
#define DEFAULT_LIST_TEXT_SIZE (12.0)
#define MIN_LIST_ICON_SIZE (16)
#define MAX_LIST_ICON_SIZE (128)
/* Space above and below the icon, and above and below the text line, that
 * the 28 point rows of the default 24 point icon have always had. */
#define ROW_ICON_MARGIN (4.0)
#define ROW_ICON_MARGIN_LARGE (7.0)
#define ROW_TEXT_MARGIN (7.0)
#define EMPTY_VALUE_STRING @"--"
/* Key of a rep's lazy label name (FSNListColumnTypeLabel holds its colour). */
#define LAZY_LABEL_NAME (FSNListColumnTypeLabel + 1000)

#define DOUBLE_CLICK_LIMIT 300
#define EDIT_CLICK_LIMIT 1000


NSString * const FSNListColumnIdName = @"name";
NSString * const FSNListColumnIdDateModified = @"dateModified";
NSString * const FSNListColumnIdDateCreated = @"dateCreated";
NSString * const FSNListColumnIdSize = @"size";
NSString * const FSNListColumnIdKind = @"kind";
NSString * const FSNListColumnIdLabel = @"label";
NSString * const FSNListColumnIdVersion = @"version";
NSString * const FSNListColumnIdComments = @"comments";
NSString * const FSNListColumnIdDateLastOpened = @"dateLastOpened";
NSString * const FSNListColumnIdOwner = @"owner";

NSString * const FSNListViewOptionsDidChangeNotification = @"FSNListViewOptionsDidChange";
NSString * const FSNListViewChangedOptionKey = @"option";
NSString * const FSNListViewOptionSort = @"sort";
NSString * const FSNListViewOptionColumnOrder = @"columnOrder";

/* The extra column types below FSNInfoType, as table identifiers. */
#define COLUMN_TYPE_IS_DATE(t) ((t) == FSNInfoDateType \
                                || (t) == FSNListColumnTypeDateCreated \
                                || (t) == FSNListColumnTypeDateLastOpened)

static NSBundle *
stringsBundle(void)
{
  return [NSBundle bundleForClass: [FSNode class]];
}

static NSString *
localized(NSString *key)
{
  return NSLocalizedStringFromTableInBundle(key, nil, stringsBundle(), @"");
}

/* Finder id <-> table identifier, in the order Finder lists the columns. */
static NSArray *
finderColumnIdList(void)
{
  static NSArray *ids = nil;

  if (ids == nil)
    {
      ids = [[NSArray alloc] initWithObjects:
                               FSNListColumnIdName,
                             FSNListColumnIdDateModified,
                             FSNListColumnIdDateCreated,
                             FSNListColumnIdSize,
                             FSNListColumnIdKind,
                             FSNListColumnIdLabel,
                             FSNListColumnIdVersion,
                             FSNListColumnIdComments,
                             FSNListColumnIdDateLastOpened,
                             nil];
    }
  return ids;
}

static NSDictionary *
columnTypeByColumnId(void)
{
  static NSDictionary *map = nil;

  if (map == nil)
    {
      map = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithInt: FSNInfoNameType], FSNListColumnIdName,
        [NSNumber numberWithInt: FSNInfoDateType], FSNListColumnIdDateModified,
        [NSNumber numberWithInt: FSNListColumnTypeDateCreated], FSNListColumnIdDateCreated,
        [NSNumber numberWithInt: FSNInfoSizeType], FSNListColumnIdSize,
        [NSNumber numberWithInt: FSNInfoKindType], FSNListColumnIdKind,
        [NSNumber numberWithInt: FSNListColumnTypeLabel], FSNListColumnIdLabel,
        [NSNumber numberWithInt: FSNListColumnTypeVersion], FSNListColumnIdVersion,
        [NSNumber numberWithInt: FSNListColumnTypeComments], FSNListColumnIdComments,
        [NSNumber numberWithInt: FSNListColumnTypeDateLastOpened], FSNListColumnIdDateLastOpened,
        [NSNumber numberWithInt: FSNInfoOwnerType], FSNListColumnIdOwner,
        nil];
    }
  return map;
}

@interface FSNListViewDataSource (FinderListOptionsPrivate) <FSNFolderSizeCalculatorDelegate>
- (BOOL)defaultAscendingForColumnType:(NSInteger)type;
- (BOOL)ascendingForColumnType:(NSInteger)type;
- (void)sortByColumnType:(NSInteger)type ascending:(NSNumber *)ascending;
- (NSDictionary *)defaultColumnInfoForType:(NSInteger)type;
- (FSNTextCell *)dataCellForColumnType:(NSInteger)type;
@end

@interface FSNListViewDataSource ()
- (void)syncRows;
- (void)updateNameHeaderInset;
@end

@interface FSNListViewDataSource (RowsPrivate)
- (FSNListViewNodeRep *)newRepForSubnode:(FSNode *)anode;
- (NSArray *)repsForSubnodes:(NSArray *)nodes;
@end

@interface FSNListViewDataSource (ExpansionPrivate)
- (void)loadExpandedFoldersReloadingUnder:(NSString *)prefix;
- (void)loadExpandedFolders:(BOOL)reloadAll;
- (void)watchExpandedFolders;
- (void)watchFolders:(NSSet *)paths;
- (NSFont *)effectiveFont;
- (void)updateSortIndicators;
- (void)resortPreservingSelection;
- (void)postOptionChange:(NSString *)option;
- (NSComparisonResult)compareRep:(FSNListViewNodeRep *)r1
                         withRep:(FSNListViewNodeRep *)r2
                      columnType:(NSInteger)type;
- (NSString *)descriptionOfDate:(NSDate *)date;
- (NSString *)sizeDescriptionOfRep:(FSNListViewNodeRep *)rep;
- (void)cancelSizeCalculation;
- (void)startSizeCalculation;
- (void)columnDidMove:(NSNotification *)notification;
@end

/* The sort direction arrow a column header shows, drawn here because the
 * table view of this GNUstep version has no indicator image support. */
@interface FSNListHeaderCell : NSTableHeaderCell
{
  int sortDirection;   /* 1 ascending, -1 descending, 0 not sorted by */
  CGFloat leadingInset;
  CGFloat trailingInset;
}
- (void)setSortDirection:(int)direction;
- (int)sortDirection;
/* Space before and after the title, so it lines up with the column's text. */
- (void)setLeadingInset:(CGFloat)leading trailingInset:(CGFloat)trailing;
@end

/* Horizontal padding of the list's text, measured on the reference list
 * view: text starts 15 points into a column and right aligned text ends 14
 * points before its end; the cell itself keeps 1 of those.  A column's
 * title starts a point before its text, ends 17 points before the column's
 * end, and the header cell draws its title 4 points into the frame it is
 * given. */
#define LIST_TEXT_INSET_LEFT (14.0)
#define LIST_TEXT_INSET_RIGHT (13.0)
#define LIST_HEADER_TITLE_PAD (4.0)
#define LIST_HEADER_INSET_LEFT (15.0 - 1.0 - LIST_HEADER_TITLE_PAD)
#define LIST_HEADER_INSET_RIGHT (15.0)
/* The reference's 1 point column separators in the header. */
#define LIST_HEADER_SEPARATOR_WHITE (184.0 / 255.0)
/* FSNTextCell draws the icon this far into its frame. */
#define TEXT_CELL_ICON_MARGIN (2.0)
/* Rows an option-click adds at most, so a huge tree cannot hang the list. */
#define MAX_RECURSIVE_EXPANSION_ROWS (1000)

/* A list cell: padding in every column, and in the name column the
 * disclosure triangle and the indent of the row's level. */
@interface FSNListCell : FSNTextCell
{
  BOOL nameCell;
  CGFloat leftInset;
  CGFloat rightInset;
  NSUInteger depth;
  int disclosure;   /* 0 none, 1 collapsed, 2 expanded */
}
- (void)setNameCell:(BOOL)flag;
- (void)setLeftInset:(CGFloat)left rightInset:(CGFloat)right;
- (void)setDepth:(NSUInteger)level disclosure:(int)state;
@end

#define SORT_ARROW_WIDTH (8.0)
#define SORT_ARROW_HEIGHT (5.0)
#define SORT_ARROW_MARGIN (6.0)

@implementation FSNListHeaderCell

- (void)setSortDirection:(int)direction
{
  sortDirection = direction;
}

- (int)sortDirection
{
  return sortDirection;
}

- (void)setLeadingInset:(CGFloat)leading trailingInset:(CGFloat)trailing
{
  leadingInset = leading;
  trailingInset = trailing;
}

/* The reference separates its column titles with a 1 point line at the
 * right end of each column, from below the header's top edge to its
 * bottom. */
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  [super drawWithFrame: cellFrame inView: controlView];
  [[NSColor colorWithCalibratedWhite: LIST_HEADER_SEPARATOR_WHITE alpha: 1.0] set];
  NSRectFill (NSMakeRect (NSMaxX (cellFrame) - 1.0, NSMinY (cellFrame) + 1.0,
                          1.0, NSHeight (cellFrame) - 1.0));
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  CGFloat reserved = SORT_ARROW_WIDTH + 2 * SORT_ARROW_MARGIN;
  NSRect padded = cellFrame;

  padded.origin.x += leadingInset;
  padded.size.width -= leadingInset + trailingInset;

  if (sortDirection == 0 || cellFrame.size.width <= reserved)
    {
      if (NSWidth (padded) > 0)
        {
          [super drawInteriorWithFrame: padded inView: controlView];
        }
      return;
    }

  /* The title gives way to the arrow instead of running under it. */
  {
    NSRect titleFrame = cellFrame;
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    CGFloat x = NSMaxX (cellFrame) - SORT_ARROW_MARGIN - SORT_ARROW_WIDTH;
    CGFloat top = NSMidY (cellFrame) - SORT_ARROW_HEIGHT / 2.0;
    CGFloat bottom = top + SORT_ARROW_HEIGHT;
    /* Header views are flipped in GNUstep; in an unflipped one the arrow
     * would point the wrong way. */
    BOOL up = ((sortDirection > 0) == [controlView isFlipped]);

    /* The arrow keeps the right end; the title its padding before it. */
    titleFrame.origin.x += leadingInset;
    titleFrame.size.width -= reserved + leadingInset;
    if (NSWidth (titleFrame) > 0)
      {
        [super drawInteriorWithFrame: titleFrame inView: controlView];
      }

    if (up)
      {
        [arrow moveToPoint: NSMakePoint (x, bottom)];
        [arrow lineToPoint: NSMakePoint (x + SORT_ARROW_WIDTH, bottom)];
        [arrow lineToPoint: NSMakePoint (x + SORT_ARROW_WIDTH / 2.0, top)];
      }
    else
      {
        [arrow moveToPoint: NSMakePoint (x, top)];
        [arrow lineToPoint: NSMakePoint (x + SORT_ARROW_WIDTH, top)];
        [arrow lineToPoint: NSMakePoint (x + SORT_ARROW_WIDTH / 2.0, bottom)];
      }
    [arrow closePath];
    [[NSColor controlShadowColor] set];
    [arrow fill];
  }
}

@end


@implementation FSNListCell

- (void)setNameCell:(BOOL)flag
{
  nameCell = flag;
}

- (void)setLeftInset:(CGFloat)left rightInset:(CGFloat)right
{
  leftInset = left;
  rightInset = right;
}

- (void)setDepth:(NSUInteger)level disclosure:(int)state
{
  depth = level;
  disclosure = state;
}

/* The reference's triangle: mid grey, pointing right when collapsed and
 * down when expanded.  On a row whose text is drawn light (an active
 * selection) it takes that colour. */
- (void)drawDisclosureInFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  NSRect box = FSNListDisclosureRectForDepth (depth, NSHeight (cellFrame));
  NSColor *text = [[self textColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
  BOOL light = (text != nil && [text brightnessComponent] > 0.5);
  NSBezierPath *path = [NSBezierPath bezierPath];
  CGFloat x = NSMinX (cellFrame) + NSMinX (box);
  CGFloat size = NSWidth (box);
  BOOL flipped = [controlView isFlipped];
  CGFloat y0 = flipped ? NSMinY (cellFrame) + NSMinY (box)
                       : NSMaxY (cellFrame) - NSMinY (box) - size;

  if (disclosure == 1)
    {
      [path moveToPoint: NSMakePoint (x + 1, y0)];
      [path lineToPoint: NSMakePoint (x + size, y0 + size / 2.0)];
      [path lineToPoint: NSMakePoint (x + 1, y0 + size)];
    }
  else
    {
      /* Pointing down it is a point less tall. */
      CGFloat yTop = flipped ? y0 : y0 + size;
      CGFloat yTip = flipped ? y0 + size - 1 : y0 + 1;

      [path moveToPoint: NSMakePoint (x, yTop)];
      [path lineToPoint: NSMakePoint (x + size, yTop)];
      [path lineToPoint: NSMakePoint (x + size / 2.0, yTip)];
    }
  [path closePath];
  [(light ? text : [NSColor colorWithCalibratedWhite: 141.0 / 255.0 alpha: 1.0]) set];
  [path fill];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  NSRect frame = cellFrame;

  if (nameCell)
    {
      CGFloat shift = FSNListIconXForDepth (depth) - TEXT_CELL_ICON_MARGIN;

      if (disclosure != 0)
        {
          [self drawDisclosureInFrame: cellFrame inView: controlView];
        }
      frame.origin.x += shift;
      frame.size.width -= shift;
    }
  else
    {
      frame.origin.x += leftInset;
      frame.size.width -= leftInset + rightInset;
    }
  if (NSWidth (frame) > 0)
    {
      [super drawInteriorWithFrame: frame inView: controlView];
    }
}

@end


@implementation FSNFolderSizeCalculator

- (id)initWithPaths:(NSArray *)folderPaths
           delegate:(id <FSNFolderSizeCalculatorDelegate>)aDelegate
{
  self = [super init];
  if (self)
    {
      paths = [folderPaths copy];
      delegate = aDelegate;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (paths);
  [super dealloc];
}

- (void)start
{
  /* The thread retains self until it ends, so a cancelled calculator that
   * nobody owns any more stays valid for as long as it needs. */
  [NSThread detachNewThreadSelector: @selector(work:)
                           toTarget: self
                         withObject: nil];
}

- (void)cancel
{
  /* Main thread only, like the delivery below: after this a result still
   * queued for the main thread finds no delegate. */
  __atomic_store_n (&cancelled, 1, __ATOMIC_SEQ_CST);
  delegate = nil;
}

- (BOOL)isFinished
{
  return finished;
}

- (void)work:(id)unused
{
  CREATE_AUTORELEASE_POOL (pool);
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      CREATE_AUTORELEASE_POOL (inner);
      NSString *path = [paths objectAtIndex: i];
      unsigned long long size;

      if (__atomic_load_n (&cancelled, __ATOMIC_SEQ_CST))
        {
          RELEASE (inner);
          break;
        }

      size = [FSNFolderSizeCalculator sizeOfTreeAtPath: path stop: &cancelled];

      if (__atomic_load_n (&cancelled, __ATOMIC_SEQ_CST) == 0)
        {
          [self performSelectorOnMainThread: @selector(deliver:)
                                 withObject: [NSArray arrayWithObjects:
                                                        path,
                                                      [NSNumber numberWithUnsignedLongLong: size],
                                                      nil]
                              waitUntilDone: NO];
        }
      RELEASE (inner);
    }

  [self performSelectorOnMainThread: @selector(deliverFinish)
                         withObject: nil
                      waitUntilDone: NO];
  RELEASE (pool);
}

- (void)deliver:(NSArray *)result
{
  [delegate sizeCalculator: self
            didComputeSize: [[result objectAtIndex: 1] unsignedLongLongValue]
                   forPath: [result objectAtIndex: 0]];
}

- (void)deliverFinish
{
  finished = YES;
  [delegate sizeCalculatorDidFinish: self];
}

/* Plain C on purpose: this runs off the main thread, and a walk through a
 * big tree must not build an object per entry. */
#if !defined(_WIN32)
static unsigned long long
treeSize(char *path, size_t length, dev_t device, const int *stop, int depth)
{
  unsigned long long total = 0;
  DIR *dir = opendir (path);
  struct dirent *entry;

  if (dir == NULL)
    {
      return 0;
    }

  while ((entry = readdir (dir)) != NULL)
    {
      size_t nameLength;
      struct stat st;

      if (__atomic_load_n (stop, __ATOMIC_SEQ_CST))
        {
          break;
        }
      if (strcmp (entry->d_name, ".") == 0 || strcmp (entry->d_name, "..") == 0)
        {
          continue;
        }

      nameLength = strlen (entry->d_name);
      if (length + 1 + nameLength >= PATH_MAX)
        {
          continue;
        }
      path[length] = '/';
      memcpy (path + length + 1, entry->d_name, nameLength + 1);

      if (lstat (path, &st) == 0)
        {
          if (!S_ISDIR (st.st_mode))
            {
              total += (unsigned long long)st.st_blocks * 512ULL;
            }
          /* A mount below the folder is another file system's business
           * (and /proc and friends are not files at all). */
          else if (st.st_dev == device && depth < 256)
            {
              total += treeSize (path, length + 1 + nameLength, device, stop, depth + 1);
            }
        }
      path[length] = '\0';
    }

  closedir (dir);
  return total;
}

+ (unsigned long long)sizeOfTreeAtPath:(NSString *)path stop:(const int *)stop
{
  char buffer[PATH_MAX];
  struct stat st;
  static const int never = 0;

  if (stop == NULL)
    {
      stop = &never;
    }
  if (![path getFileSystemRepresentation: buffer maxLength: sizeof (buffer)]
      || lstat (buffer, &st) != 0)
    {
      return 0;
    }
  if (!S_ISDIR (st.st_mode))
    {
      return (unsigned long long)st.st_blocks * 512ULL;
    }

  return treeSize (buffer, strlen (buffer), st.st_dev, stop, 0);
}
#else
+ (unsigned long long)sizeOfTreeAtPath:(NSString *)path stop:(const int *)stop
{
  /* Windows has no lstat/st_blocks and wide-character paths, so the walk
   * goes through NSFileManager and the shared on-disk size function. */
  static const int never = 0;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *e;
  NSString *sub;
  BOOL isDir = NO;
  unsigned long long total = 0;

  if (stop == NULL)
    {
      stop = &never;
    }
  if (![fm fileExistsAtPath: path isDirectory: &isDir])
    {
      return 0;
    }
  if (!isDir)
    {
      return FSNAllocatedSizeOfPath (path);
    }
  e = [fm enumeratorAtPath: path];
  while ((sub = [e nextObject]) != nil && *stop == 0)
    {
      if (![[[e fileAttributes] fileType] isEqual: NSFileTypeDirectory])
        {
          total += FSNAllocatedSizeOfPath ([path stringByAppendingPathComponent: sub]);
        }
    }
  return total;
}
#endif

@end


static NSString *defaultColumns = @"{ \
  <*I0> = { \
    position = <*I0>; \
    identifier = <*I0>; \
    width = <*R260>; \
    minwidth = <*R100>; \
  }; \
  <*I2> = { \
    position = <*I1>; \
    identifier = <*I2>; \
    width = <*R120>; \
    minwidth = <*R120>; \
  }; \
  <*I3> = { \
    position = <*I2>; \
    identifier = <*I3>; \
    width = <*R80>; \
    minwidth = <*R80>; \
  }; \
  <*I1> = { \
    position = <*I3>; \
    identifier = <*I1>; \
    width = <*R90>; \
    minwidth = <*R80>; \
  }; \
}";


@implementation FSNListViewDataSource

- (void)dealloc
{
  [[FSNIconLoader sharedLoader] cancelClient: self];

  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSUserDefaultsDidChangeNotification
                                                object: nil];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: @"GWFileWatcherFileDidChangeNotification"
                                                object: nil];
  [self detachFromListView];
  [self watchFolders: [NSSet set]];
  RELEASE (watchedFolders);
  RELEASE (rowModel);
  RELEASE (node);
  RELEASE (extInfoType);
  RELEASE (nodeReps);
  RELEASE (nameEditor);
  RELEASE (lastSelection);
  RELEASE (listFont);
  RELEASE (folderSizes);
  RELEASE (sizeCalculator);
  RELEASE (columnDirections);
  RELEASE (hiddenColumnWidths);

  [super dealloc];
}

/* Current contents generation for FSNIconLoader stale detection. */
- (NSInteger)fsnDecorationGeneration
{
  return generation;
}

/* FSNDecorationClient: load the decoration of one lazy rep. */
- (BOOL)fsnLoaderDecorateNode:(FSNode *)anode
{
  FSNListViewNodeRep *rep = [self repOfSubnode: anode];

  if (rep == nil || [rep isDecorated])
    {
      return NO;
    }

  [rep decorate];

  return YES;
}

/* Queue every still-undecorated rep for the loader (bulk priority: the
 * visible rows load synchronously in -willDisplayCell, this trickle just
 * prewarms the rows ahead of the scroll position). */
- (void)enqueueUndecoratedReps
{
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([rep isDecorated] == NO)
        {
          [[FSNIconLoader sharedLoader] enqueueNode: [rep node]
                                             client: self
                                             urgent: NO];
        }
    }
}

- (id)initForListView:(FSNListView *)aview
{
  self = [super init];

  if (self)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *appName = [defaults stringForKey: @"DesktopApplicationName"];
      NSString *selName = [defaults stringForKey: @"DesktopApplicationSelName"];
      id defentry;

      listView = aview;

      fsnodeRep = [FSNodeRep sharedInstance];

      if (appName && selName)
	{
	  Class desktopAppClass = [[NSBundle mainBundle] classNamed: appName];
	  SEL sel = NSSelectorFromString(selName);
	  desktopApp = [desktopAppClass performSelector: sel];
	}

      defentry = [defaults objectForKey: @"hligh_table_col"];
      hlighColId = defentry ? [defentry intValue] : FSNInfoNameType;
      sortAscending = [self defaultAscendingForColumnType: hlighColId];
      listIconSize = DEFAULT_LIST_ICON_SIZE;
      folderSizes = [NSMutableDictionary new];
      hiddenColumnWidths = [NSMutableDictionary new];
      columnDirections = [NSMutableDictionary new];

      ASSIGN (extInfoType, [fsnodeRep validExtendedInfoName:
                              [defaults objectForKey: FSNExtendedInfoTypeDefaultsKey]]);

      nodeReps = [NSMutableArray new];
      rowModel = [[FSNListRowModel alloc] initWithKeyOfItem: ^NSString *(id rep) {
          return [[rep node] path];
        }];
      watchedFolders = [NSMutableSet new];

      nameEditor = [FSNListViewNameEditor new];
      [nameEditor setDelegate: self];
      [nameEditor setEditable: NO];
      [nameEditor setSelectable: NO];
      [nameEditor setBezeled: NO];
      [nameEditor setAlignment: NSLeftTextAlignment];

      mouseFlags = 0;
      isDragTarget = NO;

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(defaultsChanged:)
               name: NSUserDefaultsDidChangeNotification
             object: nil];

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(columnDidMove:)
               name: NSTableViewColumnDidMoveNotification
             object: aview];

      /* The viewer watches the shown folder; the expanded ones are this
       * list's own, and Workspace posts what the watcher reports here. */
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(expandedFolderChanged:)
               name: @"GWFileWatcherFileDidChangeNotification"
             object: nil];
    }

  return self;
}

- (void)defaultsChanged:(NSNotification *)not
{
  [listView reloadData];
}

- (FSNode *)infoNode
{
  return node;
}

- (BOOL)keepsColumnsInfo
{
  return NO;
}

#pragma mark - DS_Store Support

- (void)setSortColumn:(FSNInfoType)sortType
{
  if (sortType != hlighColId)
    {
      [self sortByColumnType: sortType ascending: nil];
      [self resortPreservingSelection];
    }
}

- (FSNInfoType)sortColumn
{
  return hlighColId;
}

- (void)setColumnWidth:(float)width forIdentifier:(FSNInfoType)identifier
{
  NSTableColumn *column = [listView tableColumnWithIdentifier: [NSNumber numberWithInt: identifier]];
  if (column && width > 0) {
    [column setWidth: width];
  }
}

- (float)columnWidthForIdentifier:(FSNInfoType)identifier
{
  NSTableColumn *column = [listView tableColumnWithIdentifier: [NSNumber numberWithInt: identifier]];
  if (column) {
    return [column width];
  }
  return 0;
}

- (void)createColumns:(NSDictionary *)info
{
  NSArray *keys = [info keysSortedByValueUsingSelector: @selector(compareTableColumnInfo:)];
  NSTableColumn *column;
  NSUInteger i;

  for (i = 0; i < [keys count]; i++)
    {
      [self addColumn: [info objectForKey: [keys objectAtIndex: i]]];
    }

  column = [listView tableColumnWithIdentifier: [NSNumber numberWithInt: hlighColId]];
  if (column)
    {
      [listView setHighlightedTableColumn: column];
    }
}

- (void)addColumn:(NSDictionary *)info
{
  NSNumber *identifier = [info objectForKey: @"identifier"];
  NSInteger type = [identifier intValue];
  float width = [[info objectForKey: @"width"] floatValue];
  float minwidth = [[info objectForKey: @"minwidth"] floatValue];
  NSTableColumn *column = [(NSTableColumn *)[NSTableColumn alloc] initWithIdentifier: identifier];

  [column setHeaderCell: AUTORELEASE ([[FSNListHeaderCell alloc] init])];
  [column setDataCell: [self dataCellForColumnType: type]];
  [column setEditable: NO];
  [column setResizable: YES];
  [[column headerCell] setAlignment: (type == FSNInfoSizeType)
                                      ? NSRightTextAlignment : NSLeftTextAlignment];
  [(FSNListHeaderCell *)[column headerCell] setLeadingInset: LIST_HEADER_INSET_LEFT
                                              trailingInset: LIST_HEADER_INSET_RIGHT];
  [column setMinWidth: minwidth];
  [column setWidth: width];

  switch(type)
    {
    case FSNInfoNameType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Name", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoKindType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Type", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoDateType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Date Modified", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoSizeType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Size", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoOwnerType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Owner", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoParentType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Parent", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNInfoExtendedType:
      [[column headerCell] setStringValue: extInfoType]; /* should come Localized from the ExtInfo bundle */
      break;
    case FSNInfoDescriptionType:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Description", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    case FSNListColumnTypeDateCreated:
      [[column headerCell] setStringValue: localized (@"Date Created")];
      break;
    case FSNListColumnTypeDateLastOpened:
      [[column headerCell] setStringValue: localized (@"Date Last Opened")];
      break;
    case FSNListColumnTypeLabel:
      [[column headerCell] setStringValue: localized (@"Label")];
      break;
    case FSNListColumnTypeVersion:
      [[column headerCell] setStringValue: localized (@"Version")];
      break;
    case FSNListColumnTypeComments:
      [[column headerCell] setStringValue: localized (@"Comments")];
      break;
    default:
      [[column headerCell] setStringValue: NSLocalizedStringFromTableInBundle(@"Name", nil, [NSBundle bundleForClass:[FSNode class]], @"")];
      break;
    }

  [listView addTableColumn: column];
  RELEASE (column);
  [self updateNameHeaderInset];
  [self updateSortIndicators];
}

/* The name column's title stands over the names, not over the triangles
 * and icons, so it moves with the icon size. */
- (void)updateNameHeaderInset
{
  NSTableColumn *column = [listView tableColumnWithIdentifier:
                                      [NSNumber numberWithInt: FSNInfoNameType]];

  [(FSNListHeaderCell *)[column headerCell]
      setLeadingInset: FSNListTextXForDepth (0, listIconSize) - 1.0 - LIST_HEADER_TITLE_PAD
        trailingInset: LIST_HEADER_INSET_RIGHT];
}

- (void)addDescriptionColumn
{
  NSNumber *descId = [NSNumber numberWithInt: FSNInfoDescriptionType];
  if ([listView tableColumnWithIdentifier: descId] != nil)
    return;

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  [info setObject: descId forKey: @"identifier"];
  [info setObject: [NSNumber numberWithFloat: 200] forKey: @"width"];
  [info setObject: [NSNumber numberWithFloat: 50] forKey: @"minwidth"];
  [self addColumn: info];
}

- (void)removeColumnWithIdentifier:(NSNumber *)identifier
{
  if ([identifier intValue] != FSNInfoNameType)
    {
      NSTableColumn *column = [listView tableColumnWithIdentifier: identifier];

      if (column)
	{
	  [listView removeTableColumn: column];
	  /* Only the sorted-by column's removal changes the order. */
	  if ([identifier intValue] == hlighColId)
	    {
	      [self sortByColumnType: FSNInfoNameType ascending: nil];
	    }
	  [self sortNodeReps];
	  [listView reloadData];
	}
    }
}

- (NSDictionary *)columnsDescription
{
  NSArray *columns = [listView tableColumns];
  NSMutableDictionary *colsinfo = [NSMutableDictionary dictionary];

  if (columns)
    {
      NSUInteger i;

      for (i = 0; i < [columns count]; i++)
	{
	  NSTableColumn *column = [columns objectAtIndex: i];
	  NSNumber *identifier = [column identifier];
	  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

	  [dict setObject: [NSNumber numberWithInt: i]
		   forKey: @"position"];
	  [dict setObject: identifier
		   forKey: @"identifier"];
	  [dict setObject: [NSNumber numberWithFloat: [column width]]
		   forKey: @"width"];
	  [dict setObject: [NSNumber numberWithFloat: [column minWidth]]
		   forKey: @"minwidth"];

	  [colsinfo setObject: dict forKey: [identifier stringValue]];
	}
    }

  return colsinfo;
}

- (void)sortNodeReps
{
  NSInteger type = hlighColId;
  BOOL ascending = sortAscending;

  [rowModel sortUsingComparator: ^NSComparisonResult (id r1, id r2) {
      NSComparisonResult result = [self compareRep: r1 withRep: r2 columnType: type];

      if (result == NSOrderedSame)
        {
          /* Equal values keep a stable, readable order whatever the
           * direction. */
          return [[r1 node] compareAccordingToName: [r2 node]];
        }
      if (ascending == NO)
        {
          return (result == NSOrderedAscending) ? NSOrderedDescending : NSOrderedAscending;
        }
      return result;
    }];

  [self syncRows];
  [self updateSortIndicators];
}

/* nodeReps is what the table shows: the row model's order. */
- (void)syncRows
{
  [rowModel rebuildRows];
  [nodeReps setArray: [rowModel rows]];
}

- (void)setMouseFlags:(NSUInteger)flags
{
  mouseFlags = flags;
}

- (void)doubleClickOnListView:(id)sender
{
  [self openSelectionInNewViewer: NO];
}

- (void)selectRep:(id)aRep
{
  [self selectReps: [NSArray arrayWithObject: aRep]];
}

- (void)unselectRep:(id)aRep
{
  [listView deselectRow: [nodeReps indexOfObjectIdenticalTo: aRep]];
}

/* The flash before a folder springs open inverts the look its row rests
 * in - lit when it takes the drop, plain when not - and then restores it. */
- (void)setSpringHighlightVisible:(BOOL)visible
{
  BOOL lit;

  if (springRep == nil || [nodeReps containsObject: springRep] == NO)
    return;

  if (springFlashing == NO)
    {
      springRestingLit = (dndTarget == springRep);
      springFlashing = YES;
    }

  lit = visible ? springRestingLit : (springRestingLit == NO);
  if (visible)
    springFlashing = NO;

  if ([springRep selectIcon: lit])
    [self redisplayRep: springRep];
  [listView displayIfNeeded];
}

- (void)selectIconOfRep:(id)aRep
{
  if ([aRep selectIcon: YES])
    {
      [self redisplayRep: aRep];
      [self unSelectIconsOfRepsDifferentFrom: aRep];
    }
}

- (void)unSelectIconsOfRepsDifferentFrom:(id)aRep
{
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ((rep != aRep) && [rep selectIcon: NO]) {
	[self redisplayRep: rep];
      }
    }
}

- (void)redisplayRep:(id)aRep
{
  NSUInteger row = [nodeReps indexOfObjectIdenticalTo: aRep];
  NSRect rect = [listView rectOfRow: row];
  [listView setNeedsDisplayInRect: rect];
}

// On-screen rect of the given rep's icon, in screen coordinates.  Used for the
// window birth animation so a new window opens growing from the clicked icon.
// The icon sits at the left of the name column cell, so use that cell rect
// rather than the full row (which would centre the birth on the row).
- (NSRect)screenRectForRep:(FSNListViewNodeRep *)aRep
{
  NSUInteger row = [nodeReps indexOfObjectIdenticalTo: aRep];
  if (row == NSNotFound || listView == nil || [listView window] == nil) {
    return NSZeroRect;
  }
  NSRect cellRect = NSZeroRect;
  NSNumber *num = [NSNumber numberWithInt: FSNInfoNameType];
  unsigned col = [listView columnWithIdentifier: num];
  if (col != (unsigned)NSNotFound) {
    cellRect = [listView frameOfCellAtColumn: col row: row];
  }
  if (NSIsEmptyRect(cellRect)) {
    cellRect = [listView rectOfRow: row];
  }
  NSRect rectInWindow = [listView convertRect: cellRect toView: nil];
  return [[listView window] convertRectToScreen: rectInWindow];
}

- (id)desktopApp
{
  return desktopApp;
}

@end



@implementation FSNListViewDataSource (FinderListOptionsPrivate)

- (BOOL)defaultAscendingForColumnType:(NSInteger)type
{
  /* Newest and biggest first is what one looks for in these. */
  return !(COLUMN_TYPE_IS_DATE (type) || type == FSNInfoSizeType);
}

- (BOOL)ascendingForColumnType:(NSInteger)type
{
  NSNumber *kept;

  if (type == hlighColId)
    {
      return sortAscending;
    }
  kept = [columnDirections objectForKey: [NSNumber numberWithInteger: type]];
  return kept ? [kept boolValue] : [self defaultAscendingForColumnType: type];
}

/* Finder remembers a direction per column, so leaving the sort column must
 * not lose the direction it had. */
- (void)sortByColumnType:(NSInteger)type ascending:(NSNumber *)ascending
{
  [columnDirections setObject: [NSNumber numberWithBool: sortAscending]
                       forKey: [NSNumber numberWithInteger: hlighColId]];
  if (ascending == nil)
    {
      ascending = [NSNumber numberWithBool:
                     [self ascendingForColumnType: type]];
    }
  hlighColId = type;
  sortAscending = [ascending boolValue];
}

- (NSDictionary *)defaultColumnInfoForType:(NSInteger)type
{
  float width = 80.0, minwidth = 80.0;

  switch (type)
    {
    case FSNInfoNameType:
      width = 260.0;
      minwidth = 100.0;
      break;
    case FSNInfoDateType:
    case FSNListColumnTypeDateCreated:
    case FSNListColumnTypeDateLastOpened:
      width = 120.0;
      minwidth = 120.0;
      break;
    case FSNInfoKindType:
    case FSNInfoParentType:
    case FSNInfoExtendedType:
      width = 90.0;
      minwidth = 80.0;
      break;
    case FSNListColumnTypeLabel:
    case FSNListColumnTypeVersion:
      width = 90.0;
      minwidth = 60.0;
      break;
    case FSNListColumnTypeComments:
      width = 160.0;
      minwidth = 60.0;
      break;
    case FSNInfoDescriptionType:
      width = 200.0;
      minwidth = 50.0;
      break;
    default:
      break;
    }

  return [NSDictionary dictionaryWithObjectsAndKeys:
                         [NSNumber numberWithInteger: type], @"identifier",
                       [NSNumber numberWithFloat: width], @"width",
                       [NSNumber numberWithFloat: minwidth], @"minwidth",
                       nil];
}

/* The cells' own default font when no size was asked for. */
- (NSFont *)effectiveFont
{
  return listFont ? listFont : [NSFont systemFontOfSize: DEFAULT_LIST_TEXT_SIZE];
}

- (FSNTextCell *)dataCellForColumnType:(NSInteger)type
{
  FSNListCell *cell = AUTORELEASE ([[FSNListCell alloc] init]);

  [cell setFont: [self effectiveFont]];
  if (type == FSNInfoNameType)
    {
      [cell setNameCell: YES];
      /* The geometry says where the name starts; the cell counts its
       * spacing from its icon margin. */
      [cell setIconTextSpacing: FSNListTextXForDepth (0, 0) - FSNListIconXForDepth (0)
                                + TEXT_CELL_ICON_MARGIN];
    }
  else
    {
      [cell setLeftInset: LIST_TEXT_INSET_LEFT rightInset: LIST_TEXT_INSET_RIGHT];
      /* Sizes line up on their units, as in the reference. */
      if (type == FSNInfoSizeType)
        {
          [cell setAlignment: NSRightTextAlignment];
        }
    }
  return cell;
}

- (void)updateSortIndicators
{
  NSArray *columns = [listView tableColumns];
  NSTableColumn *sorted = nil;
  NSUInteger i;

  for (i = 0; i < [columns count]; i++)
    {
      NSTableColumn *column = [columns objectAtIndex: i];
      BOOL isSorted = ([[column identifier] intValue] == hlighColId);

      [(FSNListHeaderCell *)[column headerCell]
        setSortDirection: (isSorted ? (sortAscending ? 1 : -1) : 0)];
      if (isSorted)
        {
          sorted = column;
        }
    }

  if (sorted)
    {
      [listView setHighlightedTableColumn: sorted];
    }
  [[listView headerView] setNeedsDisplay: YES];
}

- (void)resortPreservingSelection
{
  NSArray *selected = [self selectedReps];

  [listView deselectAll: self];
  [self sortNodeReps];
  [listView reloadData];

  if ([selected count])
    {
      NSUInteger index = [nodeReps indexOfObjectIdenticalTo: [selected objectAtIndex: 0]];

      [self selectReps: selected];
      if (index != NSNotFound)
        {
          [listView scrollRowToVisible: index];
        }
    }
}

- (void)postOptionChange:(NSString *)option
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName: FSNListViewOptionsDidChangeNotification
                  object: listView
                userInfo: [NSDictionary dictionaryWithObject: option
                                                      forKey: FSNListViewChangedOptionKey]];
}

/* nil sorts before everything, so a missing value does not raise. */
static NSComparisonResult
compareOptional(id a, id b)
{
  if (a == nil || b == nil)
    {
      return (a == b) ? NSOrderedSame : (a == nil ? NSOrderedAscending : NSOrderedDescending);
    }
  return [a compare: b];
}

- (unsigned long long)sortSizeOfRep:(FSNListViewNodeRep *)rep
{
  FSNode *nd = [rep node];

  if ([nd isDirectory])
    {
      return [[folderSizes objectForKey: [nd path]] unsignedLongLongValue];
    }
  return FSNAllocatedSizeOfPath ([nd path]);
}

- (NSComparisonResult)compareRep:(FSNListViewNodeRep *)r1
                         withRep:(FSNListViewNodeRep *)r2
                      columnType:(NSInteger)type
{
  FSNode *n1 = [r1 node];
  FSNode *n2 = [r2 node];

  switch (type)
    {
    case FSNInfoKindType:
      return [n1 compareAccordingToKind: n2];
    case FSNInfoDateType:
      return compareOptional ([n1 modificationDate], [n2 modificationDate]);
    case FSNListColumnTypeDateCreated:
      return compareOptional ([n1 creationDate], [n2 creationDate]);
    case FSNListColumnTypeDateLastOpened:
      return compareOptional ([r1 lazyValueForColumnType: type],
                              [r2 lazyValueForColumnType: type]);
    case FSNInfoSizeType:
      {
        unsigned long long s1 = [self sortSizeOfRep: r1];
        unsigned long long s2 = [self sortSizeOfRep: r2];

        return (s1 == s2) ? NSOrderedSame : (s1 < s2 ? NSOrderedAscending : NSOrderedDescending);
      }
    case FSNInfoOwnerType:
      return [[n1 owner] caseInsensitiveCompare: [n2 owner]];
    case FSNInfoExtendedType:
      return [[r1 shownInfo] caseInsensitiveCompare: [r2 shownInfo]];
    case FSNListColumnTypeLabel:
      /* Finder: no label first, then by the (localized) label name; the
       * colour does not matter. */
      return compareOptional ([r1 lazyValueForColumnType: LAZY_LABEL_NAME],
                              [r2 lazyValueForColumnType: LAZY_LABEL_NAME]);
    case FSNListColumnTypeVersion:
      {
        NSString *v1 = [r1 lazyValueForColumnType: type];
        NSString *v2 = [r2 lazyValueForColumnType: type];

        if (v1 == nil || v2 == nil)
          {
            return compareOptional (v1, v2);
          }
        return [v1 compare: v2 options: NSNumericSearch | NSCaseInsensitiveSearch];
      }
    case FSNListColumnTypeComments:
      {
        NSString *c1 = [r1 lazyValueForColumnType: type];
        NSString *c2 = [r2 lazyValueForColumnType: type];

        if (c1 == nil || c2 == nil)
          {
            return compareOptional (c1, c2);
          }
        return [c1 caseInsensitiveCompare: c2];
      }
    default:
      return [n1 compareAccordingToName: n2];
    }
}

- (NSString *)descriptionOfDate:(NSDate *)date
{
  if (date == nil)
    {
      return EMPTY_VALUE_STRING;
    }
  return [[self class] descriptionOfDate: date
                              relativeTo: [NSDate date]
                           relativeNames: usesRelativeDates];
}

- (NSString *)sizeDescriptionOfRep:(FSNListViewNodeRep *)rep
{
  FSNode *nd = [rep node];

  if ([nd isDirectory] == NO)
    {
      return FSNFinderSizeDescription (FSNAllocatedSizeOfPath ([nd path]), nil);
    }
  /* A package is one thing to the user, so Finder sizes it without being
   * asked to size every folder. */
  if (calculatesAllSizes || [nd isPackage])
    {
      NSNumber *size = [folderSizes objectForKey: [nd path]];

      if (size)
        {
          return FSNFinderSizeDescription ([size unsignedLongLongValue], nil);
        }
    }
  return EMPTY_VALUE_STRING;
}

- (void)cancelSizeCalculation
{
  [sizeCalculator cancel];
  DESTROY (sizeCalculator);
}

- (void)startSizeCalculation
{
  NSMutableArray *paths;
  NSUInteger i;

  [self cancelSizeCalculation];

  paths = [NSMutableArray array];
  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNode *nd = [[nodeReps objectAtIndex: i] node];

      if ([nd isDirectory] && (calculatesAllSizes || [nd isPackage]))
        {
          [paths addObject: [nd path]];
        }
    }

  if ([paths count])
    {
      sizeCalculator = [[FSNFolderSizeCalculator alloc] initWithPaths: paths delegate: self];
      [sizeCalculator start];
    }
}

- (void)sizeCalculator:(FSNFolderSizeCalculator *)calculator
        didComputeSize:(unsigned long long)size
               forPath:(NSString *)path
{
  FSNListViewNodeRep *rep = [self repOfSubnodePath: path];

  [folderSizes setObject: [NSNumber numberWithUnsignedLongLong: size] forKey: path];

  if (rep)
    {
      NSUInteger row = [nodeReps indexOfObjectIdenticalTo: rep];

      if (row != NSNotFound)
        {
          [listView setNeedsDisplayInRect: [listView rectOfRow: row]];
        }
    }
}

- (void)sizeCalculatorDidFinish:(FSNFolderSizeCalculator *)calculator
{
  /* Rows are moved only now: a list that reshuffles under the pointer while
   * the numbers come in cannot be read. */
  if (hlighColId == FSNInfoSizeType)
    {
      [self resortPreservingSelection];
    }
}

- (void)columnDidMove:(NSNotification *)notification
{
  if (programmaticChanges)
    {
      return;
    }

  /* Many of these arrive during one drag; the order is only worth reporting
   * (and the name column worth putting back) once it settles. */
  [NSObject cancelPreviousPerformRequestsWithTarget: self
                                           selector: @selector(settleColumnOrder)
                                             object: nil];
  [self performSelector: @selector(settleColumnOrder)
             withObject: nil
             afterDelay: 0.0
                inModes: [NSArray arrayWithObjects: NSDefaultRunLoopMode,
                                  NSEventTrackingRunLoopMode, nil]];
}

- (void)settleColumnOrder
{
  NSInteger nameIndex = [listView columnWithIdentifier:
                                    [NSNumber numberWithInt: FSNInfoNameType]];

  /* Finder keeps the name column at the left edge. */
  if (nameIndex > 0)
    {
      programmaticChanges++;
      [listView moveColumn: nameIndex toColumn: 0];
      programmaticChanges--;
    }
  [self postOptionChange: FSNListViewOptionColumnOrder];
}

@end


@implementation FSNListViewDataSource (FinderListOptions)

+ (NSArray *)finderColumnIds
{
  return finderColumnIdList ();
}

+ (NSNumber *)tableIdentifierForColumnId:(NSString *)columnId
{
  return [columnTypeByColumnId () objectForKey: columnId];
}

+ (NSString *)columnIdForTableIdentifier:(NSNumber *)identifier
{
  return [[columnTypeByColumnId () allKeysForObject: identifier] lastObject];
}

+ (BOOL)defaultSortAscendingForColumnId:(NSString *)columnId
{
  NSNumber *ident = [self tableIdentifierForColumnId: columnId];

  return !(ident && (COLUMN_TYPE_IS_DATE ([ident intValue])
                     || [ident intValue] == FSNInfoSizeType));
}

+ (NSString *)descriptionOfDate:(NSDate *)date
                     relativeTo:(NSDate *)now
                  relativeNames:(BOOL)relative
{
  return [self descriptionOfDate: date
                      relativeTo: now
                   relativeNames: relative
                         strings: nil];
}

+ (NSString *)descriptionOfDate:(NSDate *)date
                     relativeTo:(NSDate *)now
                  relativeNames:(BOOL)relative
                        strings:(NSDictionary *)table
{
  return FSNFinderDateDescription (date, now, relative, table);
}

+ (CGFloat)rowHeightForTextSize:(CGFloat)points iconSize:(NSInteger)iconSize
{
  CGFloat text = (points > 0) ? points : DEFAULT_LIST_TEXT_SIZE;
  CGFloat icon = 0;

  /* Finder: a row is the text size plus 7, also with 16 point icons, and the
   * icon plus 7 with 32 point ones (E24).  Sizes in between, which Finder
   * does not offer, keep the 4 points around the icon the default 24 point
   * rows always had. */
  if (iconSize >= 32)
    {
      icon = iconSize + ROW_ICON_MARGIN_LARGE;
    }
  else if (iconSize > 16)
    {
      icon = iconSize + ROW_ICON_MARGIN;
    }

  return MAX (icon, text + ROW_TEXT_MARGIN);
}

+ (CGFloat)rowHeightForTextSize:(CGFloat)points
                        iconSize:(NSInteger)iconSize
                     scaleFactor:(CGFloat)scale
{
  CGFloat height = [self rowHeightForTextSize: points iconSize: iconSize];
  CGFloat pixels;

  NSAssert1 (scale > 0, @"no usable scale factor (%g)", (double)scale);
  /* The tolerance keeps a product such as 20 * 1.1 (22.000000000000004)
   * from being taken for a pixel and a hair, and growing by a whole pixel. */
  pixels = ceil (height * scale - 0.001);

  /* A row that ends between two device pixels is drawn one pixel taller or
   * shorter than its neighbours, so the stripes and the text baselines
   * wander from row to row; the next whole pixel keeps them on one grid. */
  return pixels / scale;
}

- (CGFloat)rowHeight
{
  /* The rows are aligned to the device pixels of the window they are drawn
   * in; with monitors of different scales that need not have the main
   * screen's factor, and rows aligned to another factor leave hairline
   * seams between the stripes. */
  NSWindow *win = [listView window];
  CGFloat scale = win ? [win userSpaceScaleFactor]
                      : [[NSScreen mainScreen] userSpaceScaleFactor];

  return [[self class] rowHeightForTextSize: [self textSize]
                                   iconSize: listIconSize
                                scaleFactor: scale];
}

- (BOOL)setSortColumnId:(NSString *)columnId ascending:(BOOL)ascending
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];

  if (ident == nil || [listView tableColumnWithIdentifier: ident] == nil)
    {
      return NO;
    }

  [self sortByColumnType: [ident intValue]
                ascending: [NSNumber numberWithBool: ascending]];
  [self resortPreservingSelection];
  return YES;
}

- (NSString *)sortColumnId
{
  return [[self class] columnIdForTableIdentifier: [NSNumber numberWithInt: hlighColId]];
}

- (void)setSortAscending:(BOOL)ascending
{
  if (ascending != sortAscending)
    {
      sortAscending = ascending;
      [self resortPreservingSelection];
    }
}

- (BOOL)sortAscendingForColumnId:(NSString *)columnId
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];

  return ident ? [self ascendingForColumnType: [ident intValue]] : YES;
}

- (BOOL)sortAscending
{
  return sortAscending;
}

- (BOOL)setColumn:(NSString *)columnId visible:(BOOL)visible
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];
  NSTableColumn *column;

  if (ident == nil)
    {
      return NO;
    }
  if ([ident intValue] == FSNInfoNameType)
    {
      return visible;
    }

  column = [listView tableColumnWithIdentifier: ident];
  if (visible == (column != nil))
    {
      return YES;
    }

  programmaticChanges++;
  if (visible)
    {
      NSMutableDictionary *info
        = [[[self defaultColumnInfoForType: [ident intValue]] mutableCopy] autorelease];
      NSNumber *remembered = [hiddenColumnWidths objectForKey: ident];

      if (remembered)
        {
          [info setObject: remembered forKey: @"width"];
        }
      [self addColumn: info];
      [listView reloadData];
    }
  else
    {
      [hiddenColumnWidths setObject: [NSNumber numberWithFloat: [column width]]
                             forKey: ident];
      [self removeColumnWithIdentifier: ident];
    }
  programmaticChanges--;

  return YES;
}

- (BOOL)isColumnVisible:(NSString *)columnId
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];

  return ident && ([listView tableColumnWithIdentifier: ident] != nil);
}

- (NSArray *)columnOrder
{
  NSArray *columns = [listView tableColumns];
  NSMutableArray *ids = [NSMutableArray arrayWithCapacity: [columns count]];
  NSUInteger i;

  for (i = 0; i < [columns count]; i++)
    {
      NSString *columnId
        = [[self class] columnIdForTableIdentifier: [[columns objectAtIndex: i] identifier]];

      if (columnId)
        {
          [ids addObject: columnId];
        }
    }
  return ids;
}

- (void)setColumnOrder:(NSArray *)columnIds
{
  NSMutableArray *target = [NSMutableArray arrayWithObject:
                                             [NSNumber numberWithInt: FSNInfoNameType]];
  NSUInteger i;

  for (i = 0; i < [columnIds count]; i++)
    {
      NSNumber *ident = [[self class] tableIdentifierForColumnId: [columnIds objectAtIndex: i]];

      if (ident && [target containsObject: ident] == NO
          && [listView tableColumnWithIdentifier: ident])
        {
          [target addObject: ident];
        }
    }

  programmaticChanges++;
  for (i = 0; i < [target count]; i++)
    {
      NSInteger index = [listView columnWithIdentifier: [target objectAtIndex: i]];

      if (index != (NSInteger)i)
        {
          [listView moveColumn: index toColumn: i];
        }
    }
  programmaticChanges--;
}

- (BOOL)setColumnWidth:(CGFloat)width forColumnId:(NSString *)columnId
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];

  if (ident == nil || width <= 0)
    {
      return NO;
    }

  if ([listView tableColumnWithIdentifier: ident])
    {
      programmaticChanges++;
      [self setColumnWidth: width forIdentifier: (FSNInfoType)[ident intValue]];
      programmaticChanges--;
    }
  else
    {
      /* Shown at this width when the column comes back. */
      [hiddenColumnWidths setObject: [NSNumber numberWithFloat: width] forKey: ident];
    }
  return YES;
}

- (CGFloat)columnWidthForColumnId:(NSString *)columnId
{
  NSNumber *ident = [[self class] tableIdentifierForColumnId: columnId];

  if (ident == nil)
    {
      return 0;
    }
  return [self columnWidthForIdentifier: (FSNInfoType)[ident intValue]];
}

- (void)setUsesRelativeDates:(BOOL)flag
{
  if (flag != usesRelativeDates)
    {
      usesRelativeDates = flag;
      [listView setNeedsDisplay: YES];
    }
}

- (BOOL)usesRelativeDates
{
  return usesRelativeDates;
}

- (void)setCalculatesAllSizes:(BOOL)flag
{
  if (flag == calculatesAllSizes)
    {
      return;
    }
  calculatesAllSizes = flag;

  if (flag)
    {
      [self startSizeCalculation];
    }
  else
    {
      [self cancelSizeCalculation];
      [folderSizes removeAllObjects];
      /* Packages keep their size. */
      [self startSizeCalculation];
    }

  if (hlighColId == FSNInfoSizeType)
    {
      [self resortPreservingSelection];
    }
  else
    {
      [listView setNeedsDisplay: YES];
    }
}

- (BOOL)calculatesAllSizes
{
  return calculatesAllSizes;
}

- (BOOL)isCalculatingSizes
{
  return sizeCalculator && ([sizeCalculator isFinished] == NO);
}

- (NSNumber *)calculatedSizeForPath:(NSString *)path
{
  return [folderSizes objectForKey: path];
}

- (void)applyRowMetrics
{
  NSArray *columns = [listView tableColumns];
  NSUInteger i;

  [listView setRowHeight: [self rowHeight]];
  [self updateNameHeaderInset];
  [[listView headerView] setNeedsDisplay: YES];

  for (i = 0; i < [columns count]; i++)
    {
      [[[columns objectAtIndex: i] dataCell] setFont: [self effectiveFont]];
    }
  for (i = 0; i < [nodeReps count]; i++)
    {
      [[nodeReps objectAtIndex: i] invalidateIcons];
    }

  [listView reloadData];
  [self enqueueUndecoratedReps];
}

- (void)setTextSize:(CGFloat)points
{
  NSFont *font = (points > 0) ? [NSFont systemFontOfSize: points] : nil;

  if (font == listFont || [font isEqual: listFont])
    {
      return;
    }
  ASSIGN (listFont, font);
  [self applyRowMetrics];
}

- (CGFloat)textSize
{
  return [[self effectiveFont] pointSize];
}

- (void)setListIconSize:(NSInteger)points
{
  points = MIN (MAX_LIST_ICON_SIZE, MAX (MIN_LIST_ICON_SIZE, points));
  if (points != listIconSize)
    {
      listIconSize = points;
      [self applyRowMetrics];
    }
}

- (NSInteger)listIconSize
{
  return listIconSize;
}

- (void)detachFromListView
{
  [self cancelSizeCalculation];
  [NSObject cancelPreviousPerformRequestsWithTarget: self];
  [[NSNotificationCenter defaultCenter] removeObserver: self
                                                  name: NSTableViewColumnDidMoveNotification
                                                object: nil];
}

@end


@implementation FSNListViewDataSource (Expansion)

- (BOOL)isRepExpandable:(FSNListViewNodeRep *)rep
{
  FSNode *nd = [rep node];

  /* An application or another package opens; it is not a folder to the
   * user. */
  return ([nd isDirectory] && [nd isPackage] == NO);
}

- (BOOL)isRepExpanded:(FSNListViewNodeRep *)rep
{
  return [rowModel isExpanded: [[rep node] path]];
}

- (NSUInteger)depthOfRep:(FSNListViewNodeRep *)rep
{
  NSUInteger row = [rowModel rowOfKey: [[rep node] path]];

  return (row == NSNotFound) ? 0 : [rowModel depthOfRow: row];
}

- (void)loadChildrenOfKey:(NSString *)key
{
  FSNode *folder = [FSNode nodeWithPath: key];

  if ([folder isValid] && [folder isDirectory])
    {
      [rowModel setChildren: [self repsForSubnodes: [folder lazySubNodes]]
                      ofKey: key];
    }
  else
    {
      [rowModel setExpanded: NO forKey: key];
    }
}

/* Loads the items of every expanded folder on the screen that has none
 * yet, and again those of the folders at or below prefix, which may have
 * changed while they were hidden and unwatched. */
- (void)loadExpandedFoldersReloadingUnder:(NSString *)prefix
{
  NSString *below = [prefix stringByAppendingString: @"/"];
  NSMutableSet *done = [NSMutableSet set];
  BOOL loaded = YES;

  /* Loading a folder can show expanded folders inside it. */
  while (loaded)
    {
      NSArray *keys = [rowModel visibleExpandedKeys];
      NSUInteger i;

      loaded = NO;
      for (i = 0; i < [keys count]; i++)
        {
          NSString *key = [keys objectAtIndex: i];
          BOOL stale = (prefix != nil
                        && ([key isEqual: prefix] || [key hasPrefix: below]));

          if ([done containsObject: key])
            {
              continue;
            }
          [done addObject: key];
          if (stale || [rowModel childrenOfKey: key] == nil)
            {
              [self loadChildrenOfKey: key];
              loaded = YES;
            }
        }
    }
}

- (void)loadExpandedFolders:(BOOL)reloadAll
{
  [self loadExpandedFoldersReloadingUnder: reloadAll ? [rowModel rootKey] : nil];
}

- (void)watchFolders:(NSSet *)paths
{
  NSEnumerator *e = [[[watchedFolders copy] autorelease] objectEnumerator];
  NSString *path;

  while ((path = [e nextObject]) != nil)
    {
      if ([paths containsObject: path] == NO)
        {
          [desktopApp removeWatcherForPath: path];
          [watchedFolders removeObject: path];
        }
    }
  e = [paths objectEnumerator];
  while ((path = [e nextObject]) != nil)
    {
      if ([watchedFolders containsObject: path] == NO)
        {
          [desktopApp addWatcherForPath: path];
          [watchedFolders addObject: path];
        }
    }
}

- (void)watchExpandedFolders
{
  [self watchFolders: [NSSet setWithArray: [rowModel visibleExpandedKeys]]];
}

/* Rows were added or removed around the selection: show the new rows and
 * keep selected what still is a row. */
- (void)reloadRowsKeepingSelection
{
  NSArray *selected = [self selectedReps];

  [self sortNodeReps];
  [listView deselectAll: self];
  [listView reloadData];
  [self selectReps: selected];
  [self enqueueUndecoratedReps];
}

- (void)setRep:(FSNListViewNodeRep *)rep expanded:(BOOL)flag
{
  [self setRep: rep expanded: flag recursively: NO];
}

- (void)setRep:(FSNListViewNodeRep *)rep
      expanded:(BOOL)flag
   recursively:(BOOL)recursively
{
  NSString *path = [[rep node] path];

  if ((recursively == NO && flag == [rowModel isExpanded: path])
      || (flag && [self isRepExpandable: rep] == NO))
    {
      return;
    }
  [self stopRepNameEditing];
  if (flag && recursively)
    {
      BOOL complete = [rowModel expandRecursivelyFromKey: path
        isExpandable: ^BOOL (id item) {
          return [self isRepExpandable: item];
        }
        loadChildren: ^NSArray *(NSString *key) {
          FSNode *folder = [FSNode nodeWithPath: key];

          return ([folder isValid] && [folder isDirectory])
            ? [self repsForSubnodes: [folder lazySubNodes]] : nil;
        }
        maxRows: MAX_RECURSIVE_EXPANSION_ROWS];

      if (complete == NO)
        {
          NSLog (@"List view: stopped expanding %@ after %d rows", path,
                 MAX_RECURSIVE_EXPANSION_ROWS);
        }
      /* Folders expanded earlier below a level the limit left out. */
      [self loadExpandedFoldersReloadingUnder: nil];
    }
  else if (flag)
    {
      [rowModel setExpanded: YES forKey: path];
      [self loadExpandedFoldersReloadingUnder: path];
    }
  else if (recursively)
    {
      [rowModel collapseRecursivelyFromKey: path];
    }
  else
    {
      [rowModel setExpanded: NO forKey: path];
    }
  [self reloadRowsKeepingSelection];
  [self watchExpandedFolders];
}

- (FSNListViewNodeRep *)parentRepOfRep:(FSNListViewNodeRep *)rep
{
  NSString *parentKey = [rowModel parentKeyOfKey: [[rep node] path]];

  if (parentKey == nil || [parentKey isEqual: [rowModel rootKey]])
    {
      return nil;
    }
  return [self repOfSubnodePath: parentKey];
}

- (void)moveIntoSelection:(BOOL)inward recursively:(BOOL)recursively
{
  NSArray *selected = [self selectedReps];
  FSNListViewNodeRep *rep;
  FSNListViewNodeRep *target = nil;
  NSUInteger i;

  /* Several rows: expand or collapse them all, move nowhere. */
  if ([selected count] != 1)
    {
      for (i = 0; i < [selected count]; i++)
        {
          [self setRep: [selected objectAtIndex: i]
              expanded: inward
           recursively: recursively];
        }
      return;
    }

  rep = [selected objectAtIndex: 0];
  if (inward)
    {
      if ([self isRepExpandable: rep] && [self isRepExpanded: rep] == NO)
        {
          [self setRep: rep expanded: YES recursively: recursively];
          return;
        }
      if ([self isRepExpanded: rep])
        {
          NSUInteger row = [nodeReps indexOfObjectIdenticalTo: rep];

          if (row + 1 < [nodeReps count]
              && [self depthOfRep: [nodeReps objectAtIndex: row + 1]] > [self depthOfRep: rep])
            {
              target = [nodeReps objectAtIndex: row + 1];
            }
        }
    }
  else
    {
      if ([self isRepExpanded: rep])
        {
          [self setRep: rep expanded: NO recursively: recursively];
          return;
        }
      target = [self parentRepOfRep: rep];
    }

  if (target)
    {
      [self selectReps: [NSArray arrayWithObject: target]];
      [listView scrollRowToVisible: [nodeReps indexOfObjectIdenticalTo: target]];
    }
}

- (void)expandedFolderChanged:(NSNotification *)notification
{
  NSDictionary *info = (NSDictionary *)[notification object];
  NSString *path = [info objectForKey: @"path"];
  NSString *event = [info objectForKey: @"event"];
  NSArray *files = [info objectForKey: @"files"];
  NSUInteger i;

  if (path == nil || [watchedFolders containsObject: path] == NO)
    {
      return;
    }

  if ([event isEqual: @"GWWatchedPathDeleted"])
    {
      [rowModel removeItemWithKey: path];
    }
  else if ([event isEqual: @"GWFileDeletedInWatchedDirectory"])
    {
      for (i = 0; i < [files count]; i++)
        {
          [rowModel removeItemWithKey:
                      [path stringByAppendingPathComponent: [files objectAtIndex: i]]];
        }
    }
  else if ([event isEqual: @"GWFileCreatedInWatchedDirectory"])
    {
      FSNode *folder = [FSNode nodeWithPath: path];

      for (i = 0; i < [files count]; i++)
        {
          FSNode *subnode = [FSNode nodeWithRelativePath: [files objectAtIndex: i]
                                                  parent: folder];
          FSNListViewNodeRep *rep;

          if (subnode == nil || [subnode isValid] == NO)
            {
              continue;
            }
          rep = [rowModel itemWithKey: [subnode path]];
          if (rep)
            {
              [rep setNode: subnode];
              continue;
            }
          rep = [self newRepForSubnode: subnode];
          if (rep)
            {
              [rowModel addChild: rep toKey: path];
              RELEASE (rep);
            }
        }
    }
  else
    {
      return;
    }

  [self reloadRowsKeepingSelection];
  [self watchExpandedFolders];
}

@end


@implementation FSNListViewDataSource (NSTableViewDataSource)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
  return [nodeReps count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
	    row:(NSInteger)rowIndex
{
  NSInteger ident = [[aTableColumn identifier] intValue];
  FSNListViewNodeRep *rep = [nodeReps objectAtIndex: rowIndex];
  FSNode *nd = [rep node];

  switch(ident)
    {
    case FSNInfoNameType:
      return [nd displayName];
      break;
    case FSNInfoKindType:
      return [nd typeDescription];
      break;
    case FSNInfoDateType:
      return [self descriptionOfDate: [nd modificationDate]];
      break;
    case FSNListColumnTypeDateCreated:
      return [self descriptionOfDate: [nd creationDate]];
      break;
    case FSNListColumnTypeDateLastOpened:
      return [self descriptionOfDate: [rep lazyValueForColumnType: ident]];
      break;
    case FSNInfoSizeType:
      return [self sizeDescriptionOfRep: rep];
      break;
    case FSNInfoOwnerType:
      return [nd owner];
      break;
    case FSNInfoParentType:
      return [nd parentName];
      break;
    case FSNInfoExtendedType:
      return [rep shownInfo];
      break;
    case FSNInfoDescriptionType:
      return GSDirectoryDescriptionForPath([nd path]);
      break;
    case FSNListColumnTypeVersion:
    case FSNListColumnTypeComments:
      {
        NSString *value = [rep lazyValueForColumnType: ident];

        return ([value length] > 0) ? value : EMPTY_VALUE_STRING;
      }
      break;
    case FSNListColumnTypeLabel:
      {
        NSString *value = [rep lazyValueForColumnType: LAZY_LABEL_NAME];

        return ([value length] > 0) ? value : EMPTY_VALUE_STRING;
      }
      break;
    default:
      return [nd name];
      break;
    }

  return [NSString string];
}

- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
	      row:(NSInteger)rowIndex
{
}

- (BOOL)tableView:(NSTableView *)aTableView
	writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [rows count]; i++)
    {
      NSInteger index = [[rows objectAtIndex: i] integerValue];
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: index];

      [paths addObject: [[rep node] path]];
    }

  [pboard declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
		 owner: nil];
  [pboard setPropertyList: paths forType: NSFilenamesPboardType];

  return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
  return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
  return NO;
}

//
// NSTableView delegate methods
//
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
  [self selectionDidChange];
}

- (BOOL)tableView:(NSTableView *)aTableView
  shouldSelectRow:(NSInteger)rowIndex
{
  return ((rowIndex != -1)
	  && ([[nodeReps objectAtIndex: rowIndex] isLocked] == NO));
}

- (void)tableView:(NSTableView *)aTableView
  willDisplayCell:(id)aCell
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
  NSInteger ident = [[aTableColumn identifier] intValue];
  FSNListViewNodeRep *rep = [nodeReps objectAtIndex: rowIndex];

  /* The row is on screen now: complete its lazy decoration (icon, tag
   * color) before the cell draws it. */
  [rep decorate];

  if (ident == FSNInfoNameType)
    {
      FSNTextCell *cell = (FSNTextCell *)aCell;

      if ([cell isKindOfClass: [FSNListCell class]])
        {
          int disclosure = 0;

          if ([self isRepExpandable: rep])
            {
              disclosure = [self isRepExpanded: rep] ? 2 : 1;
            }
          [(FSNListCell *)cell setDepth: [rowModel depthOfRow: rowIndex]
                             disclosure: disclosure];
        }

      if ([rep iconSelected])
	{
	  [cell setIcon: [rep openIcon]];
	}
      else if ([rep isLocked])
	{
	  [cell setIcon: [rep lockedIcon]];
	}
      else if ([rep isOpened])
	{
	  [cell setIcon: [rep spatialOpenIcon]];
	}
      else {
	[cell setIcon: [rep icon]];
      }

      /* Pass tag color (Finder label) and path from rep to cell */
      if ([rep respondsToSelector: @selector(tagColor)])
        [cell setTagColor: [rep tagColor]];
      if ([cell respondsToSelector: @selector(setNodePath:)])
        [cell setNodePath: [[rep node] path]];

      if ([rep isLocked])
	{
	  [cell setTextColor: [NSColor disabledControlTextColor]];
	}
      else
	{
	  [cell setTextColor: [NSColor controlTextColor]];
	}
    }
  else if (COLUMN_TYPE_IS_DATE (ident))
    {
      FSNTextCell *cell = (FSNTextCell *)aCell;
      [cell setDateCell: YES];
    }
}

/* A click, not the mouse going down: a header that is dragged to reorder
 * the columns must not also sort. */
- (void)tableView:(NSTableView *)tableView
didClickTableColumn:(NSTableColumn *)tableColumn
{
  NSInteger clicked = [[tableColumn identifier] intValue];

  if (clicked == hlighColId)
    {
      sortAscending = !sortAscending;
    }
  else
    {
      [self sortByColumnType: clicked ascending: nil];
    }

  [self resortPreservingSelection];
  [self postOptionChange: FSNListViewOptionSort];
}

- (NSImage *)tableView:(NSTableView *)tableView
      dragImageForRows:(NSArray *)dragRows
{
  if ([dragRows count] > 1)
    {
      return [[FSNodeRep sharedInstance] multipleSelectionIconOfSize: 24];
    }
  else
    {
      NSUInteger index = [[dragRows objectAtIndex: 0] unsignedIntegerValue];
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: index];

      /* A dragged row is on screen, so it is decorated already; keep the
       * guard for safety. */
      [rep decorate];

      return [rep icon];
    }

  return nil;
}

- (BOOL)tableView:(NSTableView *)aTableView
shouldEditTableColumn:(NSTableColumn *)aTableColumn
	      row:(NSInteger)rowIndex
{
  return NO;
}

@end


@implementation FSNListViewDataSource (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode
{
  NSDictionary *info = nil;
  NSDictionary *colsInfo = nil;
  NSDictionary *colsDescr;
  NSArray *nodes;
  BOOL keepinfo;

  BOOL sameNode = (node && [node isEqual: anode]);

  keepinfo = (node && ([self keepsColumnsInfo] || sameNode));

  /* Sizes belong to the folder that was shown; a reload of the same one
   * keeps showing them until the new ones are in. */
  [self cancelSizeCalculation];
  if (sameNode == NO)
    {
      [folderSizes removeAllObjects];
    }

  ASSIGN (node, anode);

  if (keepinfo == NO)
    {
      info = [self readNodeInfo];
      if (info)
	{
	  colsInfo = [info objectForKey: @"list_view_columns"];
	}

      if ((colsInfo == nil) || ([colsInfo count] == 0))
	{
	  colsInfo = [defaultColumns propertyList];
	}

      colsDescr = [self columnsDescription];

      if ([colsDescr count] == 0)
	{
      [self createColumns: colsInfo];
      [self addDescriptionColumn];

	}
      else if ([colsDescr isEqual: colsInfo] == NO)
	{
	  while ([listView numberOfColumns] > 0)
	    {
	      [listView removeTableColumn: [[listView tableColumns] objectAtIndex: 0]];
	    }

	  [self createColumns: colsInfo];
          [self addDescriptionColumn];
	}
    }

  [listView deselectAll: self];

  nodes = [anode lazySubNodes];
  [nodeReps removeAllObjects];
  generation++;   /* pending loader items for the old contents are stale */

  [rowModel resetWithRootKey: [anode path] keepExpanded: sameNode];
  [rowModel setChildren: [self repsForSubnodes: nodes] ofKey: [anode path]];
  [self loadExpandedFolders: NO];

  [self sortNodeReps];
  [self watchExpandedFolders];
  [listView reloadData];
  [self enqueueUndecoratedReps];
  [self startSizeCalculation];

  DESTROY (lastSelection);
  [self selectionDidChange];
}

- (NSDictionary *)readNodeInfo
{
  FSNode *infoNode = [self infoNode];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", [infoNode path]];
  NSDictionary *nodeDict = [defaults dictionaryForKey: prefsname];

  if (nodeDict)
    {
      id entry = [nodeDict objectForKey: @"hligh_table_col"];
      hlighColId = entry ? [entry intValue] : hlighColId;

      entry = [nodeDict objectForKey: @"hligh_table_asc"];
      sortAscending = entry ? [entry boolValue]
                            : [self defaultAscendingForColumnType: hlighColId];

      entry = [nodeDict objectForKey: @"ext_info_type"];

      if (entry)
	{
	  NSArray *availableTypes = [[FSNodeRep sharedInstance] availableExtendedInfoNames];

	  if ([availableTypes containsObject: entry]) {
	    ASSIGN (extInfoType, entry);
	  }
	}
    }

  return nodeDict;
}

- (NSMutableDictionary *)updateNodeInfo:(BOOL)ondisk
{
  CREATE_AUTORELEASE_POOL(arp);
  FSNode *infoNode = [self infoNode];
  NSMutableDictionary *updatedInfo = nil;

  if ([infoNode isValid])
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", [infoNode path]];

      NSDictionary *prefs = [defaults dictionaryForKey: prefsname];
      if (prefs)
        updatedInfo = [prefs mutableCopy];
      else
        updatedInfo = [NSMutableDictionary new];

      [updatedInfo setObject: [self columnsDescription]
		      forKey: @"list_view_columns"];

      [updatedInfo setObject: [NSNumber numberWithInt: hlighColId]
		      forKey: @"hligh_table_col"];

      [updatedInfo setObject: [NSNumber numberWithBool: sortAscending]
		      forKey: @"hligh_table_asc"];

      if (extInfoType)
	{
	  [updatedInfo setObject: extInfoType forKey: @"ext_info_type"];
	}

      if (ondisk)
        [defaults setObject: updatedInfo forKey: prefsname];
    }

  RELEASE (arp);

  return (AUTORELEASE (updatedInfo));
}

- (void)reloadContents
{
  CREATE_AUTORELEASE_POOL (pool);
  NSMutableArray *selection = [[self selectedNodes] mutableCopy];
  NSMutableArray *opennodes = [NSMutableArray array];
  NSUInteger i, count;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([rep isOpened])
	{
	  [opennodes addObject: [rep node]];
	}
    }

  RETAIN (opennodes);

  [self showContentsOfNode: node];

  count = [selection count];

  for (i = 0; i < count; i++)
    {
      FSNode *nd = [selection objectAtIndex: i];

      if ([nd isValid] == NO)
	{
	  [selection removeObjectAtIndex: i];
	  count--;
	  i--;
	}
    }

  for (i = 0; i < [opennodes count]; i++)
    {
      FSNode *nd = [opennodes objectAtIndex: i];

      if ([nd isValid])
	{
	  FSNListViewNodeRep *rep = [self repOfSubnode: nd];

	  if (rep) {
	    [rep setOpened: YES];
	  }
	}
    }

  RELEASE (opennodes);

  [self checkLockedReps];

  if ([selection count])
    {
      [self selectRepsOfSubnodes: selection];
    }

  RELEASE (selection);
  [self selectionDidChange];

  RELEASE (pool);
}

- (void)reloadFromNode:(FSNode *)anode
{
  if ([node isEqual: anode])
    {
      [self reloadContents];

    }
  else if ([node isSubnodeOfNode: anode])
    {
      NSArray *components = [FSNode nodeComponentsFromNode: anode toNode: node];
      NSUInteger i;

      for (i = 0; i < [components count]; i++)
	{
	  FSNode *component = [components objectAtIndex: i];

	  if ([component isValid] == NO)
	    {
	      component = [FSNode nodeWithPath: [component parentPath]];
	      [self showContentsOfNode: component];
	      break;
	    }
	}
    }
}

- (FSNode *)baseNode
{
  return node;
}

- (FSNode *)shownNode
{
  return node;
}

- (BOOL)isShowingNode:(FSNode *)anode
{
  return [node isEqual: anode];
}

- (BOOL)isShowingPath:(NSString *)path
{
  return [[node path] isEqual: path];
}

- (void)sortTypeChangedAtPath:(NSString *)path
{
  if ((path == nil) || [[node path] isEqual: path])
    {
      [self reloadContents];
    }
}

- (void)nodeContentsWillChange:(NSDictionary *)info
{
  [self checkLockedReps];
}

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  NSString *operation = [info objectForKey: @"operation"];
  NSString *source = [info objectForKey: @"source"];
  NSString *destination = [info objectForKey: @"destination"];
  NSArray *files = [info objectForKey: @"files"];
  NSString *ndpath = [node path];
  BOOL needsreload = NO;
  NSUInteger i;

  [self stopRepNameEditing];

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [source lastPathComponent]];
      source = [source stringByDeletingLastPathComponent];
    }

  if (([ndpath isEqual: source] == NO) && ([ndpath isEqual: destination] == NO))
    {
      [self reloadContents];
      return;
    }

  if ([ndpath isEqual: source])
    {
      if ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceDestroyOperation]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]) {

	if ([operation isEqual: NSWorkspaceRecycleOperation]) {
	  files = [info objectForKey: @"origfiles"];
	}

	for (i = 0; i < [files count]; i++)
	  {
	    NSString *fname = [files objectAtIndex: i];
	    FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];
	    [self removeRepOfSubnode: subnode];
	  }
	needsreload = YES;
      }
    }

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [destination lastPathComponent]];
      destination = [destination stringByDeletingLastPathComponent];
    }

  if ([ndpath isEqual: destination]
      && ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceCopyOperation]
	  || [operation isEqual: NSWorkspaceLinkOperation]
	  || [operation isEqual: NSWorkspaceDuplicateOperation]
	  || [operation isEqual: @"WorkspaceCreateDirOperation"]
	  || [operation isEqual: @"WorkspaceCreateFileOperation"]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]))
    {

      if ([operation isEqual: NSWorkspaceRecycleOperation])
	{
	  files = [info objectForKey: @"files"];
	}

      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];
	  FSNListViewNodeRep *rep = [self repOfSubnode: subnode];

	  if (rep)
	    {
	      [rep setNode: subnode];
	    }
	  else
	    {
	      [self addRepForSubnode: subnode];
	    }
	}
      needsreload = YES;
    }

  [self checkLockedReps];

  if (needsreload)
    {
      [self sortNodeReps];
      [listView reloadData];

      if ([[listView window] isKeyWindow])
	{
	  if ([operation isEqual: @"WorkspaceRenameOperation"]
	      || [operation isEqual: @"WorkspaceCreateDirOperation"]
	      || [operation isEqual: @"WorkspaceCreateFileOperation"])
	    {
	      NSString *fname = [files objectAtIndex: 0];
	      NSString *fpath = [destination stringByAppendingPathComponent: fname];
	      FSNListViewNodeRep *rep = [self repOfSubnodePath: fpath];

	      if (rep)
		{
		  NSUInteger index = [nodeReps indexOfObjectIdenticalTo: rep];

		  [self selectReps: [NSArray arrayWithObject: rep]];
		  [listView scrollRowToVisible: index];
		}
	    }
	}
    }

  [listView setNeedsDisplay: YES];
  [self selectionDidChange];
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  NSString *event = [info objectForKey: @"event"];
  NSArray *files = [info objectForKey: @"files"];
  NSString *ndpath = [node path];
  BOOL needsreload = NO;
  int i;

  if ([event isEqual: @"GWFileDeletedInWatchedDirectory"])
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  NSString *fpath = [ndpath stringByAppendingPathComponent: fname];
	  [self removeRepOfSubnodePath: fpath];
	}
      needsreload = YES;

    }
  else if ([event isEqual: @"GWFileCreatedInWatchedDirectory"])
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];

	  if (subnode && [subnode isValid])
	    {
	      FSNListViewNodeRep *rep = [self repOfSubnode: subnode];

	      if (rep)
		{
		  [rep setNode: subnode];
		}
	      else
		{
		  [self addRepForSubnode: subnode];
		}
	    }
	}

      needsreload = YES;
    }

  [self sortNodeReps];
  if (needsreload)
    {
      [listView deselectAll: self];
      [listView reloadData];
    }
  [listView setNeedsDisplay: YES];
  [self selectionDidChange];
}

//
// Attenzione! I due metodi che seguono sono usati solo per aggiungere
// o togliere colonne. Non hanno nessuna relazione con "hlighColId",
// come invece avviene per gli altri NodeRepContainer.
// "hlighColId" viene settato solo cliccando sulla headerCell
// di una colonna.
//

- (void)setShowType:(FSNInfoType)type
{
  NSNumber *num = [NSNumber numberWithInt: type];
  NSTableColumn *column = [listView tableColumnWithIdentifier: num];

  if (column == nil)
    {
      [self addColumn: [self defaultColumnInfoForType: type]];
    }
  else
    {
      [self removeColumnWithIdentifier: num];
    }
}

- (void)setExtendedShowType:(NSString *)type
{
  BOOL wasequal = (extInfoType && [extInfoType isEqual: type]);

  if (extInfoType)
    {
      NSNumber *num = [NSNumber numberWithInt: FSNInfoExtendedType];
      NSTableColumn *column = [listView tableColumnWithIdentifier: num];

      if (column)
	{
	  [self removeColumnWithIdentifier: num];
	}

      DESTROY (extInfoType);
    }

  if (wasequal == NO)
    {
      NSMutableDictionary *dict = [NSMutableDictionary dictionary];
      int i;

      [dict setObject: [NSNumber numberWithInt: FSNInfoExtendedType]
	       forKey: @"identifier"];
      [dict setObject: [NSNumber numberWithFloat: 90.0]
	       forKey: @"width"];
      [dict setObject: [NSNumber numberWithFloat: 80.0]
	       forKey: @"minwidth"];

      ASSIGN (extInfoType, type);

      for (i = 0; i < [nodeReps count]; i++)
	{
	  FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];
	  [rep setExtendedShowType: extInfoType];
	}

      [self addColumn: dict];
    }
}

- (FSNInfoType)showType
{
  return FSNInfoNameType;
}

- (id)repOfSubnode:(FSNode *)anode
{
  return [self repOfSubnodePath: [anode path]];
}

/* Only reps that are rows: the items of a collapsed folder are kept to
 * restore it, but are not on the screen. */
- (id)repOfSubnodePath:(NSString *)apath
{
  if (apath == nil || [rowModel rowOfKey: apath] == NSNotFound)
    {
      return nil;
    }
  return [rowModel itemWithKey: apath];
}

- (FSNListViewNodeRep *)newRepForSubnode:(FSNode *)anode
{
  FSNListViewNodeRep *rep;

  /* The listing leaves internal metadata out, but a file that appears
   * while the folder is shown (a .DS_Store written by the viewer itself)
   * arrives here from the watcher; the icon view refuses it the same way. */
  if ([FSNodeRep isInternalMetadataName: [anode name]])
    return nil;

  rep = [[FSNListViewNodeRep alloc] initForNode: anode dataSource: self];

  /* New rows (watcher events) decorate through the loader; visible rows
   * also decorate synchronously in -willDisplayCell. */
  [[FSNIconLoader sharedLoader] enqueueNode: anode client: self urgent: NO];

  return rep;
}

- (NSArray *)repsForSubnodes:(NSArray *)nodes
{
  NSMutableArray *reps = [NSMutableArray arrayWithCapacity: [nodes count]];
  NSUInteger i;

  for (i = 0; i < [nodes count]; i++)
    {
      FSNListViewNodeRep *rep = [self newRepForSubnode: [nodes objectAtIndex: i]];

      if (rep)
        {
          [reps addObject: rep];
          RELEASE (rep);
        }
    }
  return reps;
}

- (id)addRepForSubnode:(FSNode *)anode
{
  NSString *parentKey = [anode parentPath];
  FSNListViewNodeRep *rep;

  /* A file in a folder that is neither shown nor expanded has no row. */
  if ([parentKey isEqual: [rowModel rootKey]] == NO
      && [rowModel childrenOfKey: parentKey] == nil)
    {
      return nil;
    }
  rep = [self newRepForSubnode: anode];
  if (rep == nil)
    {
      return nil;
    }
  [rowModel addChild: rep toKey: parentKey];
  RELEASE (rep);
  [self syncRows];

  return rep;
}

- (void)removeRepOfSubnode:(FSNode *)anode
{
  [self removeRepOfSubnodePath: [anode path]];
}

- (void)removeRepOfSubnodePath:(NSString *)apath
{
  if ([rowModel removeItemWithKey: apath] != nil)
    {
      [self syncRows];
      [self watchExpandedFolders];
    }
}

- (void)unloadFromNode:(FSNode *)anode
{
  FSNode *parent = [FSNode nodeWithPath: [anode parentPath]];
  [self showContentsOfNode: parent];
}

- (void)unselectOtherReps:(id)arep
{
  if (arep == nil)
    {
      [listView deselectAll: self];
      [listView setNeedsDisplay: YES];
    }
}

- (void)selectReps:(NSArray *)reps
{
  NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
  NSUInteger i;

  for (i = 0; i < [reps count]; i++)
    {
      FSNListViewNodeRep *rep = [reps objectAtIndex: i];
      NSUInteger index = [nodeReps indexOfObjectIdenticalTo: rep];

      if (index != NSNotFound) {
	[set addIndex: index];
      }
    }

  if ([set count])
    {
      [listView deselectAll: self];
      [listView selectRowIndexes: set byExtendingSelection: NO];
      [listView setNeedsDisplay: YES];
    }
}

- (void)selectRepsOfSubnodes:(NSArray *)nodes
{
  NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([nodes containsObject: [rep node]])
        {
          [set addIndex: i];
        }
    }

  if ([set count])
    {
      [listView deselectAll: self];
      [listView selectRowIndexes: set byExtendingSelection: NO];
      [listView setNeedsDisplay: YES];
    }
}

- (void)selectRepsOfPaths:(NSArray *)paths
{
  NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([paths containsObject: [[rep node] path]])
	{
	  [set addIndex: i];
	}
    }

  if ([set count])
    {
      [listView deselectAll: self];
      [listView selectRowIndexes: set byExtendingSelection: NO];
      [listView setNeedsDisplay: YES];
    }
}

- (void)selectAll
{
  NSMutableIndexSet *set = [NSMutableIndexSet indexSet];
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([[rep node] isReserved] == NO)
	{
	  [set addIndex: i];
	}
    }

  if ([set count])
    {
      [listView deselectAll: self];
      [listView selectRowIndexes: set byExtendingSelection: NO];
      [listView setNeedsDisplay: YES];
    }
}

- (void)scrollSelectionToVisible
{
  NSArray *selected = [self selectedReps];

  if ([selected count]) {
    id rep = [selected objectAtIndex: 0];
    NSUInteger index = [nodeReps indexOfObjectIdenticalTo: rep];
    [listView scrollRowToVisible: index];
  } else if ([nodeReps count]) {
    [listView scrollRowToVisible: 0];
  }
}

- (NSArray *)reps
{
  return nodeReps;
}

- (NSArray *)selectedReps
{
  NSIndexSet *set = [listView selectedRowIndexes];
  NSMutableArray *selreps = [NSMutableArray array];

  NSUInteger i;
  for (i = [set firstIndex]; i != NSNotFound; i = [set indexGreaterThanIndex: i])
    {
      [selreps addObject: [nodeReps objectAtIndex: i]];
    }
  return [NSArray arrayWithArray: selreps];
}

- (NSArray *)selectedNodes
{
  NSMutableArray *selnodes = [NSMutableArray array];

  NSEnumerator *e = [[self selectedReps] objectEnumerator];
  id rep;
  while ((rep = [e nextObject]) != nil)
    {
      [selnodes addObject: [rep node]];
    }

  return [NSArray arrayWithArray: selnodes];
}

- (NSArray *)selectedPaths
{
  NSMutableArray *selpaths = [NSMutableArray array];

  NSEnumerator *e = [[self selectedNodes] objectEnumerator];
  id n;
  while ((n = [e nextObject]) != nil)
    {
      [selpaths addObject: [n path]];
    }

  return [NSArray arrayWithArray: selpaths];
}

/* The row's whole span covers every column (name, size, date, ...); only
   the name column - where the icon and the filename actually sit - is
   what the user would recognize this row's icon as, so that is what
   flies rather than the full-width row. */
- (NSArray *)flightSourcesForSelectedReps
{
  return [self flightSourcesForReps: [self selectedReps]];
}

/* An external caller asking for a flight is given paths, not a selection in
   the key window (Workspace -trashExternalPaths:), so the same sources have
   to be resolvable for an arbitrary set of rows.  Only rows this list is
   actually showing can fly: an item in another folder has no rect here. */
- (NSArray *)flightSourcesForPaths:(NSArray *)paths
{
  NSMutableArray *matched = [NSMutableArray arrayWithCapacity: [paths count]];
  NSUInteger i;

  if (paths == nil)
    return matched;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];
      NSString *path = [[rep node] path];

      if (path != nil && [paths containsObject: path])
        [matched addObject: rep];
    }

  return [self flightSourcesForReps: matched];
}

- (NSArray *)flightSourcesForReps:(NSArray *)reps
{
  NSMutableArray *sources = [NSMutableArray arrayWithCapacity: [reps count]];
  NSWindow *win = [listView window];
  NSTableColumn *nameColumn = [listView tableColumnWithIdentifier:
    [NSNumber numberWithInt: FSNInfoNameType]];
  NSInteger nameColIndex = nameColumn
    ? [listView columnWithIdentifier: [nameColumn identifier]] : -1;
  NSUInteger i;

  if (win == nil)
    return sources;

  for (i = 0; i < [reps count]; i++)
    {
      FSNListViewNodeRep *rep = [reps objectAtIndex: i];
      NSInteger row = [nodeReps indexOfObjectIdenticalTo: rep];
      NSRect rowRect, rect, rectInWindow, rectOnScreen;
      NSImage *image;
      NSString *path;

      if (row == NSNotFound)
        continue;

      rowRect = [listView rectOfRow: row];
      if (nameColIndex >= 0)
        rect = NSIntersectionRect(rowRect, [listView rectOfColumn: nameColIndex]);
      else
        rect = rowRect;

      rectInWindow = [listView convertRect: rect toView: nil];
      rectOnScreen = [win convertRectToScreen: rectInWindow];

      image = [rep icon];
      path = [[rep node] path];

      if (image == nil || path == nil)
        continue;

      [sources addObject: [NSDictionary dictionaryWithObjectsAndKeys:
        path, @"path",
        [NSValue valueWithRect: rectOnScreen], @"rect",
        image, @"image",
        nil]];
    }

  return sources;
}

- (void)selectionDidChange
{
  NSArray *selection = [self selectedNodes];

  if ([selection count] == 0)
    {
      selection = [NSArray arrayWithObject: node];
    }

  if ((lastSelection == nil) || ([selection isEqual: lastSelection] == NO))
    {
      ASSIGN (lastSelection, selection);
      [desktopApp selectionChanged: selection];
    }
}

- (void)checkLockedReps
{
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      [[nodeReps objectAtIndex: i] checkLocked];
    }
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  [desktopApp openSelectionInNewViewer: newv];
}

- (void)setLastShownNode:(FSNode *)anode
{
}

- (BOOL)needsDndProxy
{
  return YES;
}

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo
{
  return [node involvedByFileOperation: opinfo];
}

- (BOOL)validatePasteOfFilenames:(NSArray *)names
                       wasCut:(BOOL)cut
{
  NSString *nodePath = [node path];
  NSString *prePath = [NSString stringWithString: nodePath];
  NSString *basePath;

  if ([names count] == 0)
    {
      return NO;
    }

  if ([node isWritable] == NO)
    {
      return NO;
    }

  basePath = [[names objectAtIndex: 0] stringByDeletingLastPathComponent];
  if ([basePath isEqual: nodePath])
    {
      return NO;
    }

  if ([names containsObject: nodePath])
    {
      return NO;
    }

  while (1)
    {
      if ([names containsObject: prePath])
	{
	  return NO;
	}
      if ([prePath isEqual: path_separator()])
	{
	  break;
	}
      prePath = [prePath stringByDeletingLastPathComponent];
    }

  return YES;
}

- (void)stopRepNameEditing
{
  /* Whatever ends editing keeps the typed name, as in the reference; the
     controller comes back here once it has. */
  if ([[FSNRenameController sharedController] isEditingInHost: self])
    {
      [[FSNRenameController sharedController] commitActiveEditing];
      return;
    }

  if ([[listView subviews] containsObject: nameEditor])
    {
      [nameEditor abortEditing];
      [nameEditor setEditable: NO];
      [nameEditor setSelectable: NO];
      [nameEditor setNode: nil stringValue: @"" index: -1];
      [nameEditor removeFromSuperview];
      [listView setNeedsDisplayInRect: [nameEditor frame]];
    }
}

@end


@implementation FSNListViewDataSource (RepNameEditing)

- (void)setEditorAtRow:(int)row withMouseDownEvent: (NSEvent *)anEvent
{
  [self stopRepNameEditing];

  if ([[listView selectedRowIndexes] count] == 1)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: row];
      FSNode *nd = [rep node];
      BOOL canedit = (([rep isLocked] == NO) && ([nd isMountPoint] == NO)
		      && ([nd isNameLocked] == NO));

      if (canedit)
	{
	  NSNumber *num = [NSNumber numberWithInt: FSNInfoNameType];
	  unsigned col = [listView columnWithIdentifier: num];
	  NSRect r = [listView frameOfCellAtColumn: col row: row];
	  NSFont *edfont = [nameEditor font];
	  float fnheight = [fsnodeRep heightOfFont: edfont];

	  /* Over the name: past the row's indent and icon, as the cell
	   * draws them (FSNListCell, FSNTextCell). */
	  float xshift = FSNListIconXForDepth ([self depthOfRep: rep])
	    + [[rep icon] size].width + 2;

	  r.origin.y += ((r.size.height - fnheight) / 2);
	  r.size.height = fnheight;
	  r.origin.x += xshift;
	  r.size.width -= xshift;
	  r = NSIntegralRect(r);
	  [nameEditor setFrame: r];

	  [nameEditor setNode: nd stringValue: [nd name] index: 0];

	  [listView addSubview: nameEditor];

	  if (anEvent != nil)
	    {
	      [nameEditor mouseDown: anEvent];
	    }
	}
    }
}

- (NSTextField *)nameEditorForRenamingRep:(id)rep
{
  NSUInteger row = [nodeReps indexOfObjectIdenticalTo: rep];

  if (row == NSNotFound || [[listView selectedRowIndexes] count] != 1
      || [listView isRowSelected: row] == NO)
    return nil;

  [listView scrollRowToVisible: row];
  [self setEditorAtRow: row withMouseDownEvent: nil];
  if ([[listView subviews] containsObject: nameEditor] == NO)
    return nil;

  /* As tall as the row, for the field's bezel; it still starts after the
     row's indent and icon. */
  {
    NSRect r = [nameEditor frame];
    NSRect rowRect = [listView rectOfRow: row];

    r.origin.y = NSMinY(rowRect);
    r.size.height = NSHeight(rowRect);
    r.size.width = MIN(NSWidth(r), [[nameEditor font] widthOfString: [[rep node] name]] + 24);
    [nameEditor setFrame: NSIntegralRect(r)];
  }
  return nameEditor;
}

- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command
{
  return [[FSNRenameController sharedController] control: control
                                                textView: textView
                                     doCommandBySelector: command];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
  [[FSNRenameController sharedController] editorDidEndEditing: aNotification
                                                         node: [nameEditor node]
                                                         host: self];
}

@end


@implementation FSNListViewDataSource (DraggingDestination)

- (BOOL)checkDraggingLocation:(NSPoint)loc
{
  if (NSEqualRects(dndValidRect, NSZeroRect))
    {
      NSNumber *num = [NSNumber numberWithInt: FSNInfoNameType];
      unsigned col = [listView columnWithIdentifier: num];

      dndValidRect = [listView rectOfColumn: col];
    }

  return NSPointInRect(loc, dndValidRect);
}

/* What a drop on a row goes into: a file inside an expanded folder stands
 * for that folder, as the shown folder's files stand for it. */
- (FSNListViewNodeRep *)dropRepAtRow:(NSInteger)row
{
  FSNListViewNodeRep *rep = [nodeReps objectAtIndex: row];

  if ([self depthOfRep: rep] > 0 && [[rep node] isDirectory] == NO)
    {
      return [rowModel itemWithKey: [rowModel parentKeyOfKey: [[rep node] path]]];
    }
  return rep;
}

- (NSDragOperation)checkReturnValueForRep:(FSNListViewNodeRep *)arep
                         withDraggingInfo:(id <NSDraggingInfo>)sender
{
  if (dndTarget != arep)
    {
      dndTarget = arep;
    }

  dragOperation = [dndTarget repDraggingEntered: sender];

  if (dragOperation != NSDragOperationNone)
    {
      [self selectIconOfRep: dndTarget];
    }
  else
    {
      [self unSelectIconsOfRepsDifferentFrom: nil];
    }

  return dragOperation;
}

- (NSDragOperation)listViewDraggingEntered:(id <NSDraggingInfo>)sender
{
  NSPoint location;
  NSInteger row;

  isDragTarget = NO;
  dndTarget = nil;
  dragOperation = NSDragOperationNone;
  dndValidRect = NSZeroRect;

  location = [[listView window] mouseLocationOutsideOfEventStream];
  location = [listView convertPoint: location fromView: nil];
  row = [listView rowAtPoint: location];

  if (row != -1)
    {
      if ([self checkDraggingLocation: location])
	{
	  dndTarget = [self dropRepAtRow: row];
	  dragOperation = [dndTarget repDraggingEntered: sender];

	  if (dragOperation != NSDragOperationNone)
	    {
	      [self selectIconOfRep: dndTarget];
	    }
	  else
	    {
	      [self unSelectIconsOfRepsDifferentFrom: nil];
	    }
	}
      else
	{
	  [self unSelectIconsOfRepsDifferentFrom: nil];
	  dragOperation = NSDragOperationNone;
	}
    }

  if (dragOperation == NSDragOperationNone)
    {
      NSPasteboard *pb;
      NSDragOperation sourceDragMask;
      NSArray *sourcePaths;
      NSString *basePath;
      NSString *nodePath;
      NSString *prePath;
      NSUInteger count;

      dndTarget = nil;
      isDragTarget = NO;

      pb = [sender draggingPasteboard];

      /* A link dropped into the list becomes an Internet location file. */
      if ([FSNLocationFile URLForPasteboard: pb] != nil)
	{
	  if ([node isWritable] == NO)
	    {
	      return NSDragOperationNone;
	    }
	  isDragTarget = YES;
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}

      if (pb && [[pb types] containsObject: NSFilenamesPboardType])
	{
	  sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
	}
      else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
	{
	  NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
	  NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

	  sourcePaths = [pbDict objectForKey: @"paths"];
	}
      else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
	{
	  NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
	  NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

	  sourcePaths = [pbDict objectForKey: @"paths"];
	}
      else
	{
	  return NSDragOperationNone;
	}

      count = [sourcePaths count];
      if (count == 0) {
	return NSDragOperationNone;
      }

      if ([node isWritable] == NO)
	{
	  return NSDragOperationNone;
	}

      nodePath = [node path];

      basePath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
      if ([basePath isEqual: nodePath])
	{
	  return NSDragOperationNone;
	}

      if ([sourcePaths containsObject: nodePath])
	{
	  return NSDragOperationNone;
	}

      prePath = [NSString stringWithString: nodePath];

      while (1)
	{
	  if ([sourcePaths containsObject: prePath])
	    {
	      return NSDragOperationNone;
	    }
	  if ([prePath isEqual: path_separator()])
	    {
	      break;
	    }
	  prePath = [prePath stringByDeletingLastPathComponent];
	}

      if ([node isDirectory] && [node isParentOfPath: basePath])
	{
	  NSArray *subNodes = [node subNodes];
	  NSUInteger i;

	  for (i = 0; i < [subNodes count]; i++)
	    {
	      FSNode *nd = [subNodes objectAtIndex: i];

	      if ([nd isDirectory])
		{
		  NSUInteger j;

		  for (j = 0; j < count; j++)
		    {
		      NSString *fname = [[sourcePaths objectAtIndex: j] lastPathComponent];

		      if ([[nd name] isEqual: fname]) {
			return NSDragOperationNone;
		      }
		    }
		}
	    }
	}

      isDragTarget = YES;
      forceCopy = NO;

      sourceDragMask = dragOperationForCurrentModifierFlags();

      if (sourceDragMask & NSDragOperationMove)
	{
	  if ([[NSFileManager defaultManager] isWritableFileAtPath: basePath]
	      && pathsAreOnSameVolume(basePath, nodePath))
	    {
	      negotiatedDragOp = NSDragOperationMove;
	      return NSDragOperationMove;
	    }
	  forceCopy = YES;
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
      if (sourceDragMask & NSDragOperationCopy)
	{
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
      if (sourceDragMask & NSDragOperationLink)
	{
	  negotiatedDragOp = NSDragOperationLink;
	  return NSDragOperationLink;
	}
    }

  return dragOperation;
}

- (NSDragOperation)listViewDraggingUpdated:(id <NSDraggingInfo>)sender
{
  NSPoint location;
  NSInteger row;

  location = [[listView window] mouseLocationOutsideOfEventStream];
  location = [listView convertPoint: location fromView: nil];

  row = [listView rowAtPoint: location];

  if (row != -1)
    {
      if ([self checkDraggingLocation: location])
	{
	  FSNListViewNodeRep *rep = [self dropRepAtRow: row];

	  [self checkReturnValueForRep: rep withDraggingInfo: sender];

	  /* A folder the drag rests on springs open. */
	  if (rep != springRep)
	    springFlashing = NO;
	  springRep = rep;
	  [[FSNSpringLoader sharedLoader]
	    pointerRestsOnNode: [rep node]
			inView: listView
		       flasher: self
		  draggedPaths: [FSNSpringLoader draggedPathsOfDraggingInfo: sender]];
	}
      else
	{
	  [[FSNSpringLoader sharedLoader] pointerLeftView: listView];
	  springRep = nil;
	  [self unSelectIconsOfRepsDifferentFrom: nil];
	  dndTarget = nil;
	  dragOperation = NSDragOperationNone;
	}
    }
  else
    {
      [[FSNSpringLoader sharedLoader] pointerLeftView: listView];
      springRep = nil;
      dndTarget = nil;
      dragOperation = NSDragOperationNone;
    }

  if (dragOperation == NSDragOperationNone)
    {
      NSDragOperation sourceDragMask = dragOperationForCurrentModifierFlags();

      dndTarget = nil;

      if (isDragTarget == NO)
	{
	  return NSDragOperationNone;
	}

      if (sourceDragMask & NSDragOperationMove)
	{
	  negotiatedDragOp = forceCopy ? NSDragOperationCopy : NSDragOperationMove;
	  return negotiatedDragOp;
	}
      if (sourceDragMask & NSDragOperationCopy)
	{
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
      if (sourceDragMask & NSDragOperationLink)
	{
	  negotiatedDragOp = NSDragOperationLink;
	  return NSDragOperationLink;
	}
    }

  return dragOperation;
}

- (void)listViewDraggingExited:(id <NSDraggingInfo>)sender
{
  [[FSNSpringLoader sharedLoader] pointerLeftView: listView];
  springRep = nil;
  isDragTarget = NO;
  dndTarget = nil;
  dndValidRect = NSZeroRect;
  [self unSelectIconsOfRepsDifferentFrom: nil];
}

- (BOOL)listViewPrepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return ((dndTarget != nil) || isDragTarget);
}

- (BOOL)listViewPerformDragOperation:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb = [sender draggingPasteboard];

  if ((dndTarget != nil || isDragTarget)
      && [FSNLocationFile URLForPasteboard: pb] != nil)
    {
      /* Written here, not on conclude, so a failure refuses the drop. */
      return [FSNLocationFile
	       writeWeblocFromPasteboard: pb
			     inDirectory: [(dndTarget ? [dndTarget node] : node) path]]
	!= nil;
    }
  return ((dndTarget != nil) || isDragTarget);
}

- (void)listViewConcludeDragOperation:(id <NSDraggingInfo>)sender
{
  if ([FSNLocationFile URLForPasteboard: [sender draggingPasteboard]] != nil)
    {
      [self unSelectIconsOfRepsDifferentFrom: nil];
      isDragTarget = NO;
      dndTarget = nil;
      dndValidRect = NSZeroRect;
      return;
    }

  if (dndTarget)
    {
      [dndTarget repConcludeDragOperation: sender];
      [self unSelectIconsOfRepsDifferentFrom: nil];
    }
  else
    {
      NSPasteboard *pb;
      NSArray *sourcePaths;
      NSString *operation;
      NSString *source;
      NSMutableArray *files;
      NSMutableDictionary *opDict;
      NSString *trashPath;
      NSUInteger i;

      pb = [sender draggingPasteboard];
      operation = nil;

      if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
        {
          NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];

          [desktopApp concludeRemoteFilesDragOperation: pbData
                                           atLocalPath: [node path]];
          isDragTarget = NO;
          dndTarget = nil;
          dndValidRect = NSZeroRect;
          return;
        }
      if ([[pb types] containsObject: @"GWLSFolderPboardType"])
        {
          NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];

          [desktopApp lsfolderDragOperation: pbData
                            concludedAtPath: [node path]];
          isDragTarget = NO;
          dndTarget = nil;
          dndValidRect = NSZeroRect;
          return;
        }

      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

      if ([sourcePaths count] == 0)
        {
          isDragTarget = NO;
          dndTarget = nil;
          dndValidRect = NSZeroRect;
          return;
        }

      source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

      trashPath = [desktopApp trashPath];

      if ([source isEqual: trashPath])
        {
          operation = @"WorkspaceRecycleOutOperation";
        }

      else
        {
          switch (negotiatedDragOp)
            {
              case NSDragOperationMove:
                operation = NSWorkspaceMoveOperation;
                break;
              case NSDragOperationCopy:
                operation = NSWorkspaceCopyOperation;
                break;
              case NSDragOperationLink:
                operation = FSNLinkDropOperation();
                break;
              default:
                operation = NSWorkspaceCopyOperation;
                break;
            }
        }

      files = [NSMutableArray array];
      for (i = 0; i < [sourcePaths count]; i++)
        {
          [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
        }

      opDict = [NSMutableDictionary dictionary];
      [opDict setObject: operation forKey: @"operation"];
      [opDict setObject: source forKey: @"source"];
      [opDict setObject: [node path] forKey: @"destination"];
      [opDict setObject: files forKey: @"files"];

      [desktopApp performFileOperation: opDict];
    }

  isDragTarget = NO;
  dndTarget = nil;
  dndValidRect = NSZeroRect;
}

@end


@implementation FSNListViewNodeRep

- (void)dealloc
{
  RELEASE (icon);
  RELEASE (openicon);
  RELEASE (lockedicon);
  RELEASE (spopenicon);
  RELEASE (extInfoStr);
  RELEASE (tagColor);
  RELEASE (lazyValues);
  [super dealloc];
}

- (id)initForNode:(FSNode *)anode
       dataSource:(FSNListViewDataSource *)fsnds
{
  self = [super init];

  if (self)
    {
      dataSource = fsnds;
      fsnodeRep = [FSNodeRep sharedInstance];

      ASSIGN (node, anode);

      /* The icon image and tag color load later via -decorate
       * (FSNIconLoader): a large directory must not pay the icon pipeline
       * per row at fill time. */
      icon = nil;
      decorated = NO;
      lazyValues = [NSMutableDictionary new];

      openicon = nil;
      lockedicon = nil;
      spopenicon = nil;

      ASSIGN (extInfoStr, [NSString string]);

      isLocked = NO;
      iconSelected = NO;
      isOpened = NO;
      wasOpened = NO;
      nameEdited = NO;
    }

  return self;
}

- (void)decorate
{
  if (decorated || node == nil)
    {
      return;
    }

  ASSIGN (icon, [fsnodeRep iconOfSize: [dataSource listIconSize] forNode: node]);

  /* Load Finder label color from the metadata provider */
  ASSIGN (tagColor,
          [[fsnodeRep metadataProvider] labelColorForPath: [node path]]);

  decorated = YES;

  /* No redraw request here: rows going on screen decorate synchronously in
   * -willDisplayCell, and the loader trickle only prewarms rows that are
   * not displayed (the window may even be closed by then - the data source
   * is kept alive by its pending loader items, but the table view is not). */
}

- (BOOL)isDecorated
{
  return decorated;
}

- (void)invalidateIcons
{
  BOOL wasSelected = iconSelected;

  DESTROY (icon);
  DESTROY (openicon);
  DESTROY (lockedicon);
  DESTROY (spopenicon);
  decorated = NO;

  /* A selected row draws its open icon, which is only made when the row is
   * selected. */
  iconSelected = NO;
  if (wasSelected)
    {
      [self selectIcon: YES];
    }
}

- (id)loadLazyValueForColumnType:(NSInteger)type
{
  NSString *path = [node path];
  id provider = [fsnodeRep metadataProvider];

  switch (type)
    {
    case FSNListColumnTypeDateLastOpened:
      {
#if !defined(_WIN32)
        struct stat st;

        /* The access time is what a POSIX system has that comes closest. */
        if (stat ([path fileSystemRepresentation], &st) == 0)
          {
            return [NSDate dateWithTimeIntervalSince1970: (NSTimeInterval)st.st_atime];
          }
#endif
      }
      break;
    case FSNListColumnTypeVersion:
      if ([node isPackage])
        {
          NSDictionary *plist = [[NSBundle bundleWithPath: path] infoDictionary];
          NSString *version = [plist objectForKey: @"CFBundleShortVersionString"];

          if (version == nil)
            {
              version = [plist objectForKey: @"CFBundleVersion"];
            }
          if (version == nil)
            {
              version = [plist objectForKey: @"ApplicationRelease"];
            }
          return version;
        }
      break;
    case FSNListColumnTypeComments:
      if ([provider respondsToSelector: @selector(commentForPath:)])
        {
          return [provider commentForPath: path];
        }
      break;
    case FSNListColumnTypeLabel:
      return [provider labelColorForPath: path];
    case LAZY_LABEL_NAME:
      if ([provider respondsToSelector: @selector(labelNameForPath:)])
        {
          return [provider labelNameForPath: path];
        }
      break;
    }

  return nil;
}

- (id)lazyValueForColumnType:(NSInteger)type
{
  NSNumber *key = [NSNumber numberWithInteger: type];
  id value = [lazyValues objectForKey: key];

  if (value == nil)
    {
      value = [self loadLazyValueForColumnType: type];
      /* "Nothing" is remembered too, or every redraw of a row without a
       * comment would ask again. */
      [lazyValues setObject: (value ? value : (id)[NSNull null]) forKey: key];
    }

  return (value == [NSNull null]) ? nil : value;
}

- (NSImage *)icon
{
  return icon;
}

- (NSColor *)tagColor
{
  return tagColor;
}

// On-screen rect of this rep's icon, used as the birth-animation source when
// a new window is opened from a list view.
- (NSRect)screenRect
{
  if (dataSource && [dataSource respondsToSelector: @selector(screenRectForRep:)])
    {
      return [dataSource screenRectForRep: self];
    }
  return NSZeroRect;
}

- (NSImage *)openIcon
{
  return openicon;
}

- (NSImage *)lockedIcon
{
  return lockedicon;
}

- (NSImage *)spatialOpenIcon
{
  return spopenicon;
}

- (BOOL)selectIcon:(BOOL)value
{
  if ((iconSelected != value) || (isOpened != wasOpened))
    {
      iconSelected = value;

      if (iconSelected && ((openicon == nil) || (isOpened != wasOpened)))
	{
	  NSImage *opicn = [fsnodeRep openFolderIconOfSize: [dataSource listIconSize] forNode: node];

	  if (isOpened)
	    {
	      DESTROY (openicon);
	      openicon = [[NSImage alloc] initWithSize: [opicn size]];
	      [openicon lockFocus];
	      [opicn dissolveToPoint: NSZeroPoint fraction: 0.5];
	      [openicon unlockFocus];
	    }
	  else
	    {
	      ASSIGN (openicon, opicn);
	    }
	}
    }

  return YES;
}

- (BOOL)iconSelected
{
  return iconSelected;
}


//
// FSNodeRep protocol
//
- (void)setNode:(FSNode *)anode
{
  ASSIGN (node, anode);
  if (decorated)
    {
      ASSIGN (icon, [fsnodeRep iconOfSize: [dataSource listIconSize] forNode: node]);
    }
  DESTROY (tagColor);
  [lazyValues removeAllObjects];
  [self setLocked: [node isLocked]];
}

- (void)setNode:(FSNode *)anode
   nodeInfoType:(FSNInfoType)type
   extendedType:(NSString *)exttype
{
  [self setNode: anode];
}

- (FSNode *)node
{
  return node;
}

- (void)showSelection:(NSArray *)selnodes
{
}

- (BOOL)isShowingSelection
{
  return NO;
}

- (NSArray *)selection
{
  return nil;
}

- (NSArray *)pathsSelection
{
  return nil;
}

- (void)setFont:(NSFont *)fontObj
{
}

- (NSFont *)labelFont
{
  return nil;
}

- (void)setLabelTextColor:(NSColor *)acolor
{
}

- (NSColor *)labelTextColor
{
  return nil;
}

- (void)setIconSize:(int)isize
{
}

- (int)iconSize
{
  return [dataSource listIconSize];
}

- (void)setIconPosition:(NSCellImagePosition)ipos
{
}

- (NSCellImagePosition)iconPosition
{
  return NSImageLeft;
}

- (NSRect)labelRect
{
  return NSZeroRect;
}

- (void)setNodeInfoShowType:(FSNInfoType)type
{
}

- (BOOL)setExtendedShowType:(NSString *)type
{
  NSDictionary *info = [fsnodeRep extendedInfoOfType: type forNode: node];

  if (info)
    {
      ASSIGN (extInfoStr, [info objectForKey: @"labelstr"]);
    }

  return YES;
}

- (FSNInfoType)nodeInfoShowType
{
  return FSNInfoNameType;
}

- (NSString *)shownInfo
{
  // we returns allways extInfoStr because
  // the other info is got from the node by
  // FSNListViewDataSource
  return extInfoStr;
}

- (void)setNameEdited:(BOOL)value
{
  nameEdited = value;
}

- (void)setLeaf:(BOOL)flag
{
}

- (BOOL)isLeaf
{
  return YES;
}

- (void)select
{
  [dataSource selectRep: self];
}

- (void)unselect
{
  [dataSource unselectRep: self];
}

- (BOOL)isSelected
{
  return NO;
}

- (void)setOpened:(BOOL)value
{
  wasOpened = isOpened;

  if (isOpened != value)
    {
      isOpened = value;

      if (isOpened && (spopenicon == nil))
	{
	  spopenicon = [[NSImage alloc] initWithSize: [icon size]];
	  [spopenicon lockFocus];
	  [icon dissolveToPoint: NSZeroPoint fraction: 0.5];
	  [spopenicon unlockFocus];
	}

      [self selectIcon: iconSelected];
      [dataSource redisplayRep: self];
    }
}

- (BOOL)isOpened
{
  return isOpened;
}

- (void)setLocked:(BOOL)value
{
  if (isLocked != value)
    {
      isLocked = value;

      if (isLocked && (lockedicon == nil))
	{
	  lockedicon = [[NSImage alloc] initWithSize: [icon size]];
	  [lockedicon lockFocus];
	  [icon dissolveToPoint: NSZeroPoint fraction: 0.3];
	  [lockedicon unlockFocus];
	}

      [dataSource redisplayRep: self];
    }
}

- (BOOL)isLocked
{
  return isLocked;
}

- (void)checkLocked
{
  [self setLocked: [node isLocked]];
}

- (void)setGridIndex:(NSUInteger)index
{
}

- (NSUInteger)gridIndex
{
  return 0;
}

- (int)compareAccordingToName:(id)aObject
{
  return [node compareAccordingToName: [aObject node]];
}

- (int)compareAccordingToKind:(id)aObject;
{
  return [node compareAccordingToKind: [aObject node]];
}

- (int)compareAccordingToDate:(id)aObject
{
  return [node compareAccordingToDate: [aObject node]];
}

- (int)compareAccordingToSize:(id)aObject
{
  return [node compareAccordingToSize: [aObject node]];
}

- (int)compareAccordingToOwner:(id)aObject
{
  return [node compareAccordingToOwner: [aObject node]];
}

- (int)compareAccordingToGroup:(id)aObject
{
  return [node compareAccordingToGroup: [aObject node]];
}

- (int)compareAccordingToIndex:(id)aObject
{
  return NSOrderedSame;
}

@end


@implementation FSNListViewNodeRep (DraggingDestination)

- (NSDragOperation)repDraggingEntered:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSDragOperation sourceDragMask;
  NSArray *sourcePaths;
  NSString *fromPath;
  NSString *nodePath;
  NSString *prePath;
  int count;

  isDragTarget = NO;

  if (isLocked || ([node isDirectory] == NO)
      || [node isPackage] || ([node isWritable] == NO))
    {
      return NSDragOperationNone;
    }

  if ([node isDirectory])
    {
      id <DesktopApplication> desktopApp = [dataSource desktopApp];

      if ([node isSubnodeOfPath: [desktopApp trashPath]])
	{
	  return NSDragOperationNone;
	}
    }

  pb = [sender draggingPasteboard];

  if ([FSNLocationFile URLForPasteboard: pb] != nil)
    {
      isDragTarget = YES;
      return NSDragOperationCopy;
    }

  if ([[pb types] containsObject: NSFilenamesPboardType])
    {
      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

    }
  else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

      sourcePaths = [pbDict objectForKey: @"paths"];

    }
  else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

      sourcePaths = [pbDict objectForKey: @"paths"];

    }
  else
    {
      return NSDragOperationNone;
    }

  count = [sourcePaths count];
  if (count == 0)
    {
      return NSDragOperationNone;
    }

  nodePath = [node path];

  fromPath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  if ([nodePath isEqual: fromPath])
    {
      return NSDragOperationNone;
    }

  if ([sourcePaths containsObject: nodePath])
    {
      return NSDragOperationNone;
    }

  prePath = [NSString stringWithString: nodePath];

  while (1)
    {
      if ([sourcePaths containsObject: prePath])
	{
	  return NSDragOperationNone;
	}
      if ([prePath isEqual: path_separator()])
	{
	  break;
	}
      prePath = [prePath stringByDeletingLastPathComponent];
    }

  if ([node isDirectory] && [node isParentOfPath: fromPath])
    {
      NSArray *subNodes = [node subNodes];
      int i;

      for (i = 0; i < [subNodes count]; i++)
	{
	  FSNode *nd = [subNodes objectAtIndex: i];

	  if ([nd isDirectory]) {
	    int j;

	    for (j = 0; j < count; j++)
	      {
		NSString *fname = [[sourcePaths objectAtIndex: j] lastPathComponent];

		if ([[nd name] isEqual: fname])
		  {
		    return NSDragOperationNone;
		  }
	      }
	  }
	}
    }

  isDragTarget = YES;
  forceCopy = NO;

  sourceDragMask = dragOperationForCurrentModifierFlags();
  if (sourceDragMask & NSDragOperationMove)
    {
      if ([[NSFileManager defaultManager] isWritableFileAtPath: fromPath]
	  && pathsAreOnSameVolume(fromPath, nodePath))
	{
	  negotiatedDragOp = NSDragOperationMove;
	  return NSDragOperationMove;
	}
      forceCopy = YES;
      negotiatedDragOp = NSDragOperationCopy;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationCopy)
    {
      negotiatedDragOp = NSDragOperationCopy;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationLink)
    {
      negotiatedDragOp = NSDragOperationLink;
      return NSDragOperationLink;
    }

  return NSDragOperationNone;
}

- (void)repConcludeDragOperation:(id <NSDraggingInfo>)sender
{
  id <DesktopApplication> desktopApp = [dataSource desktopApp];
  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray *sourcePaths;
  NSString *operation, *source;
  NSMutableArray *files;
  NSMutableDictionary *opDict;
  NSString *trashPath;
  NSUInteger i;

  if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];

      [desktopApp concludeRemoteFilesDragOperation: pbData
				       atLocalPath: [node path]];
      return;

    }
  else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];

      [desktopApp lsfolderDragOperation: pbData
			concludedAtPath: [node path]];
      return;
    }

  sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

  source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  trashPath = [desktopApp trashPath];

  if ([source isEqual: trashPath])
    {
      operation = @"WorkspaceRecycleOutOperation";
    }
  else
    {
      switch (negotiatedDragOp)
	{
	  case NSDragOperationMove:
	    operation = NSWorkspaceMoveOperation;
	    break;
	  case NSDragOperationCopy:
	    operation = NSWorkspaceCopyOperation;
	    break;
	  case NSDragOperationLink:
	    operation = FSNLinkDropOperation();
	    break;
	  default:
	    operation = NSWorkspaceCopyOperation;
	    break;
	}
    }

  files = [NSMutableArray arrayWithCapacity: 1];
  for (i = 0; i < [sourcePaths count]; i++)
    {
      [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
    }

  opDict = [NSMutableDictionary dictionaryWithCapacity: 4];
  [opDict setObject: operation forKey: @"operation"];
  [opDict setObject: source forKey: @"source"];
  [opDict setObject: [node path] forKey: @"destination"];
  [opDict setObject: files forKey: @"files"];

  [desktopApp performFileOperation: opDict];
}

@end


@implementation FSNListViewNameEditor

NSComparisonResult sortSubviews(id view1, id view2, void *context)
{
  if ([view1 isMemberOfClass: [FSNListViewNameEditor class]]) {
    return NSOrderedAscending;
  }
  return NSOrderedDescending;
}

- (void)dealloc
{
  RELEASE (node);
  [super dealloc];
}

- (void)setNode:(FSNode *)anode
    stringValue:(NSString *)str
          index:(int)idx
{
  DESTROY (node);
  if (anode)
    {
      ASSIGN (node, anode);
    }
  [self setStringValue: str];
  index = idx;
}

- (FSNode *)node
{
  return node;
}

- (int)index
{
  return index;
}

- (void)mouseDown:(NSEvent *)theEvent
{
  NSView *view = [self superview];

  if ([self isEditable] == NO)
    {
      [self setSelectable: YES];
      [self setEditable: YES];
      [[self window] makeFirstResponder: self];
    }
  else
    {
      [super mouseDown: theEvent];
    }

  [view sortSubviewsUsingFunction: (NSComparisonResult (*)(id, id, void *))sortSubviews context: nil];
  [view setNeedsDisplayInRect: [self frame]];
}

@end


@implementation FSNListView

/* The row height depends on the window's scale factor (see -rowHeight):
 * it is applied again when the view gets a window and when that window
 * moves to a monitor of another scale. */
- (void)viewDidMoveToWindow
{
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  /* By name: libs-gui only posts it where windows have per-monitor scales. */
  NSString *name = @"NSWindowDidChangeBackingPropertiesNotification";

  [super viewDidMoveToWindow];
  [center removeObserver: self name: name object: nil];
  if ([self window] != nil)
    {
      [center addObserver: self
                 selector: @selector(windowScaleDidChange:)
                     name: name
                   object: [self window]];
      [self windowScaleDidChange: nil];
    }
}

- (void)windowScaleDidChange:(NSNotification *)notif
{
  if (fabs([dsource rowHeight] - [self rowHeight]) > 0.001)
    {
      [dsource applyRowMetrics];
    }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];

  /* Pending loader items keep the data source alive past this dealloc (the
   * window is going away, the loader is not), while its observers and its
   * unretained listView back-pointer die here.  Drop the items and the
   * defaults observer now so a late notification cannot reach the dead
   * table view through the surviving data source. */
  [dsource detachFromListView];
  [[FSNIconLoader sharedLoader] cancelClient: dsource];
  [[NSNotificationCenter defaultCenter] removeObserver: dsource
                                                  name: NSUserDefaultsDidChangeNotification
                                                object: nil];

  /* A rename waiting for the double-click interval must not start in a
   * view that is gone. */
  [[FSNRenameController sharedController] cancelScheduledRename];

  RELEASE (selectionModel);
  RELEASE (dsource);
  [super dealloc];
}

- (NSPoint)scrollPosition
{
  NSRect visible = [self visibleRect];
  NSRect all = [self bounds];

  return NSMakePoint(NSMinX(visible) - NSMinX(all),
                     [self isFlipped] ? NSMinY(visible) - NSMinY(all)
                                      : NSMaxY(all) - NSMaxY(visible));
}

- (void)applySavedScroll
{
  NSScrollView *scroll = [self enclosingScrollView];
  NSClipView *clip = [scroll contentView];
  NSRect all = [self bounds];
  NSSize visible = [clip bounds].size;
  CGFloat x, top, y;

  if (clip == nil)
    {
      return;
    }

  x = MIN (MAX (_savedScroll.x, 0), MAX (NSWidth (all) - visible.width, 0));
  top = MIN (MAX (_savedScroll.y, 0), MAX (NSHeight (all) - visible.height, 0));
  y = [self isFlipped] ? NSMinY (all) + top : NSMaxY (all) - top - visible.height;

  /* Not the user scrolling, so it must not end the hold on the position. */
  _applyingScroll = YES;
  [clip scrollToPoint: [clip constrainScrollPoint: NSMakePoint (NSMinX (all) + x, y)]];
  [scroll reflectScrolledClipView: clip];
  _applyingScroll = NO;
}

- (void)clipViewBoundsDidChange:(NSNotification *)notification
{
  if (_applyingScroll == NO)
    {
      _hasSavedScroll = NO;
    }
}

- (void)setScrollPosition:(NSPoint)position
{
  NSClipView *clip = [[self enclosingScrollView] contentView];

  if (clip != _observedClip)
    {
      NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

      [center removeObserver: self name: NSViewBoundsDidChangeNotification object: _observedClip];
      _observedClip = clip;
      [clip setPostsBoundsChangedNotifications: YES];
      [center addObserver: self
                 selector: @selector(clipViewBoundsDidChange:)
                     name: NSViewBoundsDidChangeNotification
                   object: clip];
    }

  _savedScroll = position;
  _hasSavedScroll = YES;
  [self applySavedScroll];
}

- (id)initWithFrame:(NSRect)frameRect
    dataSourceClass:(Class)dsclass
{
  self = [super initWithFrame: frameRect];

  if (self)
    {
      [self setDrawsGrid: NO];
      [self setAllowsColumnSelection: NO];
      [self setAllowsColumnReordering: YES];
      [self setAllowsColumnResizing: YES];
      [self setAllowsEmptySelection: YES];
      [self setAllowsMultipleSelection: YES];
      [self setIntercellSpacing: NSZeroSize];
      [self setUsesAlternatingRowBackgroundColors: YES];

      dsource = [[dsclass alloc] initForListView: self];
      [self setRowHeight: [dsource rowHeight]];

      [self setDataSource: dsource];
      [self setDelegate: dsource];
      [self setTarget: dsource];
      [self setDoubleAction: @selector(doubleClickOnListView:)];

      selectionModel = [[FSNSelectionModel alloc] initWithStyle: FSNSelectionStyleList];
      [selectionModel setDelegate: self];
      _bandRect = NSZeroRect;

      [self registerForDraggedTypes: [NSArray arrayWithObjects:
                                                NSFilenamesPboardType,
					      @"GWLSFolderPboardType",
					      @"GWRemoteFilenamesPboardType",
					      NSURLPboardType,
					      NSStringPboardType,
					      nil]];
    }

  return self;
}

- (void)checkSize
{
  id sview = [self superview];
  if (sview && ([self bounds].size.width < [sview bounds].size.width))
    {
      [self sizeLastColumnToFit];
    }
}

/* A click in front of a folder's icon expands or collapses it, and does
 * not touch the selection, as in the reference. */
- (BOOL)toggleDisclosureAtEvent:(NSEvent *)theEvent
{
  NSPoint p = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  NSInteger row = [self rowAtPoint: p];
  NSInteger col = [self columnAtPoint: p];
  FSNListViewNodeRep *rep;
  NSRect cell, hit;

  if (row < 0 || col < 0
      || [[[[self tableColumns] objectAtIndex: col] identifier] intValue] != FSNInfoNameType)
    {
      return NO;
    }
  rep = [[dsource reps] objectAtIndex: row];
  cell = [self frameOfCellAtColumn: col row: row];
  hit = FSNListDisclosureHitRectForDepth ([dsource depthOfRep: rep], NSHeight (cell));
  hit.origin.x += NSMinX (cell);
  hit.origin.y += NSMinY (cell);
  if (NSPointInRect (p, hit) == NO || [dsource isRepExpandable: rep] == NO)
    {
      return NO;
    }
  /* Option-click opens or closes the whole tree, as in the reference. */
  [dsource setRep: rep
         expanded: ([dsource isRepExpanded: rep] == NO)
      recursively: (([theEvent modifierFlags] & NSAlternateKeyMask) != 0)];
  return YES;
}

#pragma mark - Selection

- (NSString *)selectionModel:(FSNSelectionModel *)model nameOfItem:(id)item
{
  return [[(FSNListViewNodeRep *)item node] name];
}

- (void)syncSelectionModel
{
  [selectionModel setItems: [dsource reps]];
  [selectionModel setSelectedItems: [dsource selectedReps]];
}

- (void)applySelectionModel
{
  NSArray *reps = [dsource reps];
  NSArray *selected = [selectionModel selectedItems];
  NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
  NSUInteger i;
  id cursor = [selectionModel cursor];

  for (i = 0; i < [selected count]; i++)
    {
      NSUInteger row = [reps indexOfObjectIdenticalTo: [selected objectAtIndex: i]];

      if (row != NSNotFound)
        [rows addIndex: row];
    }
  if ([rows isEqualToIndexSet: [self selectedRowIndexes]] == NO)
    [self selectRowIndexes: rows byExtendingSelection: NO];

  if (cursor != nil && [selectionModel isItemSelected: cursor])
    [self scrollRowToVisible: [reps indexOfObjectIdenticalTo: cursor]];
}

/* Runs one keyboard decision of the selection model and shows its result. */
- (void)performSelectionKey:(BOOL (^)(FSNSelectionModel *model))step
{
  [self syncSelectionModel];
  if (step(selectionModel))
    {
      [dsource stopRepNameEditing];
      [self applySelectionModel];
    }
}

/* The icon and name of a row: a press there drags the item, a press
   anywhere else in the row starts a rubber band, as in the reference. */
- (BOOL)point:(NSPoint)p isOnNameOfRow:(NSInteger)row
{
  NSNumber *num = [NSNumber numberWithInt: FSNInfoNameType];
  NSInteger col = [self columnWithIdentifier: num];
  FSNListViewNodeRep *rep;
  NSTableColumn *column;
  NSFont *font;
  NSRect cell;
  CGFloat x, width;

  if (row < 0 || col < 0)
    return NO;

  rep = [[dsource reps] objectAtIndex: row];
  column = [[self tableColumns] objectAtIndex: col];
  font = [[column dataCell] font];
  cell = [self frameOfCellAtColumn: col row: row];
  x = NSMinX(cell) + FSNListIconXForDepth([dsource depthOfRep: rep]);
  width = [[rep icon] size].width + 2
    + ((font != nil) ? [font widthOfString: [[rep node] name]] : NSWidth(cell)) + 4;

  return (p.x >= x && p.x <= MIN(x + width, NSMaxX(cell)));
}

/* Starts dragging the selected rows, through the same data source and
   drag image NSTableView itself uses. */
- (BOOL)startRowDragWithEvent:(NSEvent *)theEvent
{
  NSIndexSet *rows = [self selectedRowIndexes];
  NSPasteboard *pboard = [NSPasteboard pasteboardWithName: NSDragPboard];
  NSPoint start = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  NSPoint offset = NSZeroPoint;
  id ds = [self dataSource];
  NSImage *image;
  NSSize size;
  BOOL written = NO;

  if ([rows count] == 0 || [self canDragRowsWithIndexes: rows atPoint: start] == NO)
    return NO;

  if ([ds respondsToSelector: @selector(tableView:writeRowsWithIndexes:toPasteboard:)])
    {
      written = [ds tableView: self writeRowsWithIndexes: rows toPasteboard: pboard];
    }
  else if ([ds respondsToSelector: @selector(tableView:writeRows:toPasteboard:)])
    {
      NSMutableArray *list = [NSMutableArray array];
      NSUInteger i = [rows firstIndex];

      while (i != NSNotFound)
        {
          [list addObject: [NSNumber numberWithUnsignedInteger: i]];
          i = [rows indexGreaterThanIndex: i];
        }
      written = [ds tableView: self writeRows: list toPasteboard: pboard];
    }
  if (written == NO)
    return NO;

  image = [self dragImageForRowsWithIndexes: rows
                               tableColumns: nil
                                      event: theEvent
                                     offset: &offset];
  size = [image size];
  /* The offset is where the image's center goes; the view is flipped. */
  start.x += offset.x - size.width / 2;
  start.y += offset.y + size.height / 2;
  [self dragImage: image
               at: start
           offset: NSZeroSize
            event: theEvent
       pasteboard: pboard
           source: self
        slideBack: YES];
  return YES;
}

/* The rows a band from "from" to "to" touches: every row its vertical
   extent crosses. */
- (NSArray *)repsInBandFrom:(NSPoint)from to:(NSPoint)to
{
  NSArray *reps = [dsource reps];
  NSMutableArray *touched = [NSMutableArray array];
  CGFloat top = MIN(from.y, to.y);
  CGFloat bottom = MAX(from.y, to.y);
  NSUInteger i;

  for (i = 0; i < [reps count]; i++)
    {
      NSRect r = [self rectOfRow: i];

      if (NSMaxY(r) > top && NSMinY(r) < bottom)
        [touched addObject: [reps objectAtIndex: i]];
    }
  return touched;
}

- (void)trackSelectionBandFromEvent:(NSEvent *)theEvent
{
  NSUInteger mask = NSLeftMouseUpMask | NSLeftMouseDraggedMask;
  NSPoint start = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  NSEvent *event = theEvent;

  [selectionModel beginBandWithModifiers:
                    FSNSelectionModifiersFromEventFlags([theEvent modifierFlags])];

  while ([event type] != NSLeftMouseUp)
    {
      CREATE_AUTORELEASE_POOL (arp);
      NSPoint p;

      event = [NSApp nextEventMatchingMask: mask
                                 untilDate: [NSDate distantFuture]
                                    inMode: NSEventTrackingRunLoopMode
                                   dequeue: YES];
      p = [self convertPoint: [event locationInWindow] fromView: nil];
      [self autoscroll: event];

      [self setNeedsDisplayInRect: NSInsetRect(_bandRect, -1, -1)];
      _bandRect = NSMakeRect(MIN(start.x, p.x), MIN(start.y, p.y),
                             MAX(1, fabs(p.x - start.x)), MAX(1, fabs(p.y - start.y)));
      [self setNeedsDisplayInRect: NSInsetRect(_bandRect, -1, -1)];

      [selectionModel updateBandWithItems: [self repsInBandFrom: start to: p]];
      [self applySelectionModel];
      [self displayIfNeeded];
      DESTROY (arp);
    }

  [selectionModel endBand];
  [self setNeedsDisplayInRect: NSInsetRect(_bandRect, -1, -1)];
  _bandRect = NSZeroRect;
  [self applySelectionModel];
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect: rect];

  if (NSIsEmptyRect(_bandRect) == NO && NSIntersectsRect(rect, _bandRect))
    {
      [[[NSColor selectedControlColor] colorWithAlphaComponent: 0.3] set];
      NSRectFillUsingOperation(_bandRect, NSCompositeSourceOver);
      [[NSColor darkGrayColor] set];
      NSFrameRect(_bandRect);
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
  NSPoint location = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  NSInteger row = [self rowAtPoint: location];
  unsigned modifiers = FSNSelectionModifiersFromEventFlags([theEvent modifierFlags]);
  FSNListViewNodeRep *rep;
  BOOL wasOnlySelected;
  NSEvent *next;

  /* A second press (the second click of a double click) opens rather
     than renames; any press ends editing a name. */
  [[FSNRenameController sharedController] cancelScheduledRename];
  /* A press beside the rows that ends renaming does only that; the renamed
     item stays selected, as in the reference. */
  if ([[FSNRenameController sharedController] commitActiveEditing]
      && [self rowAtPoint: [self convertPoint: [theEvent locationInWindow] fromView: nil]] < 0)
    return;

  if ([self toggleDisclosureAtEvent: theEvent])
    {
      return;
    }

  [dsource setMouseFlags: [theEvent modifierFlags]];

  /* The second click of a double click opens; NSTableView sends the
     double action for it. */
  if ([theEvent clickCount] > 1)
    {
      [super mouseDown: theEvent];
      return;
    }

  [dsource stopRepNameEditing];
  [[self window] makeFirstResponder: self];

  /* Control-click is the context menu, which a one-button mouse has no
     other way to ask for. */
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

  [self syncSelectionModel];

  if (row < 0)
    {
      [selectionModel mouseDownOnEmptySpaceWithModifiers: modifiers];
      [self applySelectionModel];
      next = FSNNextMouseUpOrDraggedEvent([self window]);
      if ([next type] == NSLeftMouseDragged)
        [self trackSelectionBandFromEvent: theEvent];
      return;
    }

  rep = [[dsource reps] objectAtIndex: row];
  wasOnlySelected = ([[self selectedRowIndexes] count] == 1 && [self isRowSelected: row]);

  if ([self point: location isOnNameOfRow: row] == NO)
    {
      /* Beside the name a press selects the row, and a drag from there
         is a rubber band. */
      [selectionModel mouseDownOnItem: rep modifiers: modifiers];
      [self applySelectionModel];
      next = FSNNextMouseUpOrDraggedEvent([self window]);
      if ([next type] == NSLeftMouseDragged)
        {
          [selectionModel mouseUpOnItem: rep dragged: YES];
          [self trackSelectionBandFromEvent: theEvent];
        }
      else
        {
          [selectionModel mouseUpOnItem: rep dragged: NO];
          [self applySelectionModel];
        }
      return;
    }

  [selectionModel mouseDownOnItem: rep modifiers: modifiers];
  [self applySelectionModel];

  /* A modifier click that deselected the row is done. */
  if ([selectionModel isItemSelected: rep] == NO)
    return;

  next = FSNNextMouseUpOrDraggedEvent([self window]);

  if ([next type] == NSLeftMouseDragged)
    {
      [selectionModel mouseUpOnItem: rep dragged: YES];
      [self startRowDragWithEvent: theEvent];
      return;
    }

  [selectionModel mouseUpOnItem: rep dragged: NO];
  [self applySelectionModel];

  /* A click on the name of the item that already was the only one
     selected starts renaming once it is clear no second click follows. */
  if ([FSNRenamePolicy clickStartsRenamingWithCount: 1
                                             onName: YES
                                    wasOnlySelected: wasOnlySelected
                                          modifiers: modifiers])
    {
      [[FSNRenameController sharedController] scheduleRenameOfRep: rep inHost: dsource];
    }
}

- (void)scrollToEdge:(BOOL)top
{
  NSRect b = [self bounds];
  BOOL atMaxY = (top != [self isFlipped]);

  [self scrollRectToVisible: NSMakeRect(NSMinX(b), atMaxY ? NSMaxY(b) - 1 : NSMinY(b), 1, 1)];
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];
  NSUInteger flags = [theEvent modifierFlags];
  BOOL extend = ((flags & NSShiftKeyMask) != 0);
  unichar character = 0;
  NSRect vRect, hiddRect;
  NSPoint p;
  float x, y, w, h;

  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
    }

  switch (character)
    {
    case NSPageUpFunctionKey:
      [dsource stopRepNameEditing];
      vRect = [self visibleRect];
      p = vRect.origin;
      x = p.x;
      y = p.y - vRect.size.height;
      w = vRect.size.width;
      h = vRect.size.height;
      hiddRect = NSMakeRect(x, y, w, h);
      [self scrollRectToVisible: hiddRect];
      return;

    case NSPageDownFunctionKey:
      [dsource stopRepNameEditing];
      vRect = [self visibleRect];
      p = vRect.origin;
      x = p.x;
      y = p.y + vRect.size.height;
      w = vRect.size.width;
      h = vRect.size.height;
      hiddRect = NSMakeRect(x, y, w, h);
      [self scrollRectToVisible: hiddRect];
      return;

    /* Home and End only scroll; the selection stays. */
    case NSHomeFunctionKey:
      [self scrollToEdge: YES];
      return;

    case NSEndFunctionKey:
      [self scrollToEdge: NO];
      return;

    case NSUpArrowFunctionKey:
    case NSDownArrowFunctionKey:
      /* Command-Up and Command-Down open things, further up. */
      if (flags & (NSCommandKeyMask | NSControlKeyMask))
        break;
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

    /* The reference expands the selected folders with the right arrow
     * and collapses them with the left one, the whole tree with option. */
    case NSRightArrowFunctionKey:
    case NSLeftArrowFunctionKey:
      [dsource stopRepNameEditing];
      [dsource moveIntoSelection: (character == NSRightArrowFunctionKey)
                     recursively: (([theEvent modifierFlags] & NSAlternateKeyMask) != 0)];
      return;

    case NSCarriageReturnCharacter:
    case NSEnterCharacter:
      {
	NSArray *selected = [dsource selectedReps];

	/* Return renames, as in the reference; opening is Command-Down and
	   Command-O. */
	if ([FSNRenamePolicy keyStartsRenaming: character
				     modifiers: FSNSelectionModifiersFromEventFlags(flags)
				selectionCount: [selected count]])
	  {
	    if ([[FSNRenameController sharedController]
		  beginRenameOfRep: [selected lastObject] inHost: dsource] == NO)
	      NSBeep();
	    return;
	  }
	if (flags & (NSAlternateKeyMask | NSControlKeyMask))
	  [dsource openSelectionInNewViewer: YES];
	return;
      }

    /* Tab walks the names instead of leaving the view, as in the
       reference, whose sidebar never takes the focus. */
    case NSTabCharacter:
    case NSBackTabCharacter:
      if (flags & (NSCommandKeyMask | NSControlKeyMask))
        break;
      [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
        return [model selectNextInNameOrder: (character == NSTabCharacter && extend == NO)];
      }];
      return;

    case 0x01B: // Escape
      [self performSelectionKey: ^BOOL(FSNSelectionModel *model) {
        [model resetTypeSelect];
        return [model deselectAllItems];
      }];
      return;

    default:
      break;
    }

  if (character >= 0x20 && character < 0xF700
      && (flags & (NSCommandKeyMask | NSControlKeyMask)) == 0)
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

- (void)setFrame:(NSRect)frameRect
{
  [super setFrame: frameRect];
  [self checkSize];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldFrameSize
{
  [super resizeWithOldSuperviewSize: oldFrameSize];
  [self checkSize];
}

/* Stripes by position rather than by row: the theme's version starts at
 * the row under the top of the clip rect, and below the last item there is
 * none, so an expose down there repaints the top rows instead and leaves
 * the exposed area plain. */
- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
  NSArray *colors;
  NSUInteger count;
  CGFloat height = [self rowHeight];
  NSInteger row, last;

  [[self backgroundColor] set];
  NSRectFill (clipRect);

  if ([self usesAlternatingRowBackgroundColors] == NO || height <= 0)
    {
      return;
    }
  colors = [NSColor controlAlternatingRowBackgroundColors];
  count = [colors count];
  if (count == 0)
    {
      return;
    }

  row = (NSInteger) floor (NSMinY (clipRect) / height);
  last = (NSInteger) ceil (NSMaxY (clipRect) / height);
  for (; row < last; row++)
    {
      NSRect band = NSMakeRect (NSMinX (clipRect), row * height,
                                NSWidth (clipRect), height);

      [(NSColor *)[colors objectAtIndex: row % count] set];
      NSRectFill (NSIntersectionRect (band, clipRect));
    }
}

- (NSImage *)dragImageForRows:(NSArray *)dragRows
			event:(NSEvent *)dragEvent
	      dragImageOffset:(NSPointPointer)dragImageOffset
{
  id deleg = [self delegate];

  if ([deleg respondsToSelector: @selector(tableView:dragImageForRows:)]) {
    NSImage *image = [deleg tableView: self dragImageForRows: dragRows];
    if (image) {
      /* Command+Alternate drags create Alias records - mark the drag
       * with the alias arrow. */
      if (FSNLinkDropCreatesAlias()) {
        image = FSNLinkBadgedImage(image);
      }
      return image;
    }
  }

  return [super dragImageForRows: dragRows
			   event: dragEvent
		 dragImageOffset: dragImageOffset];
}

@end


@implementation FSNListView (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode
{
  [dsource showContentsOfNode: anode];
  if (_hasSavedScroll)
    {
      [self applySavedScroll];
    }
}

- (NSDictionary *)readNodeInfo
{
  return [dsource readNodeInfo];
}

- (NSMutableDictionary *)updateNodeInfo:(BOOL)ondisk
{
  return [dsource updateNodeInfo: ondisk];
}

- (void)reloadContents
{
  [dsource reloadContents];
  if (_hasSavedScroll)
    {
      [self applySavedScroll];
    }
}

- (void)reloadFromNode:(FSNode *)anode
{
  [dsource reloadFromNode: anode];
  if (_hasSavedScroll)
    {
      [self applySavedScroll];
    }
}

- (FSNode *)baseNode
{
  return [dsource baseNode];
}

- (FSNode *)shownNode
{
  return [dsource shownNode];
}

- (BOOL)isSingleNode
{
  return YES;
}

- (BOOL)isShowingNode:(FSNode *)anode
{
  return [dsource isShowingNode: anode];
}

- (BOOL)isShowingPath:(NSString *)path
{
  return [dsource isShowingPath: path];
}

- (void)sortTypeChangedAtPath:(NSString *)path
{
  [dsource sortTypeChangedAtPath: path];
}

- (void)nodeContentsWillChange:(NSDictionary *)info
{
  [dsource nodeContentsWillChange: info];
}

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  [dsource nodeContentsDidChange: info];
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  [dsource watchedPathChanged: info];
}

- (void)setShowType:(FSNInfoType)type
{
  [dsource setShowType: type];
}

- (void)setExtendedShowType:(NSString *)type
{
  [(FSNListViewDataSource *)dsource setExtendedShowType: type];
}

- (FSNInfoType)showType
{
  return [dsource showType];
}

- (id)repOfSubnode:(FSNode *)anode
{
  return [dsource repOfSubnode: anode];
}

- (id)repOfSubnodePath:(NSString *)apath
{
  return [dsource repOfSubnodePath: apath];
}

- (id)addRepForSubnode:(FSNode *)anode
{
  return [dsource addRepForSubnode: anode];
}

- (void)removeRepOfSubnode:(FSNode *)anode
{
  [dsource removeRepOfSubnode: anode];
}

- (void)removeRepOfSubnodePath:(NSString *)apath
{
  [dsource removeRepOfSubnodePath: apath];
}

- (void)unloadFromNode:(FSNode *)anode
{
  [dsource unloadFromNode: anode];
}

- (void)unselectOtherReps:(id)arep
{
  [dsource unselectOtherReps: arep];
}

- (void)selectReps:(NSArray *)reps
{
  [dsource selectReps: reps];
}

- (void)selectRepsOfSubnodes:(NSArray *)nodes
{
  [dsource selectRepsOfSubnodes: nodes];
}

- (void)selectRepsOfPaths:(NSArray *)paths
{
  [dsource selectRepsOfPaths: paths];
}

- (void)selectAll
{
  [dsource selectAll];
}

- (void)scrollSelectionToVisible
{
  [dsource scrollSelectionToVisible];
}

- (NSArray *)reps
{
  return [dsource reps];
}

- (NSArray *)selectedReps
{
  return [dsource selectedReps];
}

- (NSArray *)selectedNodes
{
  return [dsource selectedNodes];
}

- (NSArray *)selectedPaths
{
  return [dsource selectedPaths];
}

- (NSArray *)flightSourcesForSelectedReps
{
  return [dsource flightSourcesForSelectedReps];
}

- (NSArray *)flightSourcesForPaths:(NSArray *)paths
{
  return [dsource flightSourcesForPaths: paths];
}

- (void)selectionDidChange
{
  [dsource selectionDidChange];
}

- (void)checkLockedReps
{
  [dsource checkLockedReps];
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  [dsource openSelectionInNewViewer: newv];
}

- (void)setLastShownNode:(FSNode *)anode
{
  [dsource setLastShownNode: anode];
}

- (BOOL)needsDndProxy
{
  return [dsource needsDndProxy];
}

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo
{
  return [dsource involvedByFileOperation: opinfo];
}

- (BOOL)validatePasteOfFilenames:(NSArray *)names
                       wasCut:(BOOL)cut
{
  return [dsource validatePasteOfFilenames: names wasCut: cut];
}

- (void)stopRepNameEditing
{
  [dsource stopRepNameEditing];
}

@end


@implementation FSNListView (DraggingDestination)

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag
{
  return NSDragOperationEvery;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  return [dsource listViewDraggingEntered: sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  return [dsource listViewDraggingUpdated: sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  [dsource listViewDraggingExited: sender];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return [dsource listViewPrepareForDragOperation: sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return [dsource listViewPerformDragOperation: sender];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  [dsource listViewConcludeDragOperation: sender];
}

@end


@implementation NSDictionary (TableColumnSort)

- (NSComparisonResult)compareTableColumnInfo:(NSDictionary *)info
{
  NSNumber *p1 = [self objectForKey: @"position"];
  NSNumber *p2 = [info objectForKey: @"position"];
  return [p1 compare: p2];
}

@end
