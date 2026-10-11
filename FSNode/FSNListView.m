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
#import "FSNTextCell.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"
#import "FSNLocationFile.h"
#import "FSNIconLoader.h"
#import "FSNDirEntry.h"

#include <sys/stat.h>
#if !defined(_WIN32)
#include <dirent.h>
#endif
#include <limits.h>

#define ICNSIZE (24)
#define CELLS_HEIGHT (28.0)
#define HLIGHT_H_FACT (0.8125)

#define DEFAULT_LIST_ICON_SIZE (ICNSIZE)
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
- (FSNTextCell *)freshDataCell;
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
}
- (void)setSortDirection:(int)direction;
- (int)sortDirection;
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

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
  CGFloat reserved = SORT_ARROW_WIDTH + 2 * SORT_ARROW_MARGIN;

  if (sortDirection == 0 || cellFrame.size.width <= reserved)
    {
      [super drawInteriorWithFrame: cellFrame inView: controlView];
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

    titleFrame.size.width -= reserved;
    [super drawInteriorWithFrame: titleFrame inView: controlView];

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
  [self detachFromListView];
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
  [column setDataCell: [self freshDataCell]];
  [column setEditable: NO];
  [column setResizable: YES];
  [[column headerCell] setAlignment: NSLeftTextAlignment];
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
  [self updateSortIndicators];
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

  [nodeReps sortUsingComparator: ^NSComparisonResult (id r1, id r2) {
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

  [self updateSortIndicators];
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

- (void)selectRepInPrevRow
{
  NSInteger row = [listView selectedRow];

  if ((row != -1) && (row > 0))
    {
      row--;
      [listView selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
	    byExtendingSelection: NO];
      [listView scrollRowToVisible: row];
    }
}

- (void)selectRepInNextRow
{
  NSInteger row = [listView selectedRow];

  if ((row != -1) && (row < ([nodeReps count] -1)))
    {
      row++;
      [listView selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
	    byExtendingSelection: NO];
      [listView scrollRowToVisible: row];
    }
}

- (NSString *)selectRepWithPrefix:(NSString *)prefix
{
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];
      NSString *name = [[rep node] name];

      if ([name rangeOfString: prefix options: NSCaseInsensitiveSearch].location == 0)
        {
          [listView deselectAll: self];
          [self selectReps: [NSArray arrayWithObject: rep]];
          [listView scrollRowToVisible: i];

          return name;
        }
    }

  return nil;
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
  return listFont ? listFont : [[self freshDataCell] font];
}

- (FSNTextCell *)freshDataCell
{
  FSNTextCell *cell = AUTORELEASE ([[FSNTextCell alloc] init]);

  if (listFont)
    {
      [cell setFont: listFont];
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
  CGFloat text = (points > 0)
    ? points
    : [[[[FSNTextCell alloc] init] autorelease] font].pointSize;
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

  [listView setRowHeight: [[self class] rowHeightForTextSize: [self textSize]
                                                    iconSize: listIconSize]];

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
  NSUInteger i;

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

  for (i = 0; i < [nodes count]; i++)
    {
      [self addRepForSubnode: [nodes objectAtIndex: i]];
    }

  [self sortNodeReps];
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
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([[rep node] isEqual: anode])
	{
	  return rep;
	}
    }

  return nil;
}

- (id)repOfSubnodePath:(NSString *)apath
{
  NSUInteger i;

  for (i = 0; i < [nodeReps count]; i++)
    {
      FSNListViewNodeRep *rep = [nodeReps objectAtIndex: i];

      if ([[[rep node] path] isEqual: apath])
	{
	  return rep;
	}
    }

  return nil;
}

- (id)addRepForSubnode:(FSNode *)anode
{
  /* The listing leaves internal metadata out, but a file that appears
   * while the folder is shown (a .DS_Store written by the viewer itself)
   * arrives here from the watcher; the icon view refuses it the same way. */
  if ([FSNodeRep isInternalMetadataName: [anode name]])
    return nil;

  FSNListViewNodeRep *rep = [[FSNListViewNodeRep alloc] initForNode: anode
                                                         dataSource: self];
  [nodeReps addObject: rep];
  RELEASE (rep);

  /* New rows (watcher events) decorate through the loader; visible rows
   * also decorate synchronously in -willDisplayCell. */
  [[FSNIconLoader sharedLoader] enqueueNode: anode client: self urgent: NO];

  return rep;
}

- (void)removeRepOfSubnode:(FSNode *)anode
{
  FSNListViewNodeRep *rep = [self repOfSubnode: anode];

  if (rep)
    {
      [nodeReps removeObject: rep];
    }
}

- (void)removeRepOfSubnodePath:(NSString *)apath
{
  FSNListViewNodeRep *rep = [self repOfSubnodePath: apath];

  if (rep)
    {
      [nodeReps removeObject: rep];
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

	  float xshift = [[rep icon] size].width + 4;

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

- (void)controlTextDidChange:(NSNotification *)aNotification
{
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
  FSNode *ednode = [nameEditor node];

#define CLEAREDITING				\
  [self stopRepNameEditing];			\
  return


  if ([ednode isParentWritable] == NO)
    {
      showAlertNoPermission([FSNode class], [ednode parentName]);
      CLEAREDITING;
    }
  else if ([ednode isSubnodeOfPath: [desktopApp trashPath]])
    {
      showAlertInRecycler([FSNode class]);
      CLEAREDITING;
    }
  else
    {
      NSString *userName = [nameEditor stringValue];
      NSString *origName = [ednode name];
      NSString *newname = GSRenamedFilename(userName, origName, GSCurrentExtensionDisplayMode());
      NSString *newpath;
      NSString *extension;
      NSCharacterSet *notAllowSet = [NSCharacterSet characterSetWithCharactersInString: @"/\\*:?\33"];
      NSRange range;
      NSArray *dirContents;
      NSMutableDictionary *opinfo;

      if (newname == nil)
	{
	  CLEAREDITING;
	}

      newpath = [[ednode parentPath] stringByAppendingPathComponent: newname];
      extension = [newpath pathExtension];
      range = [newname rangeOfCharacterFromSet: notAllowSet];
      dirContents = [ednode subNodeNamesOfParent];
      opinfo = [NSMutableDictionary dictionary];

      if (([newname length] == 0) || (range.length > 0))
	{
	  showAlertInvalidName([FSNode class]);
	  CLEAREDITING;
	}

      if (([extension length]
	   && ([ednode isDirectory] && ([ednode isPackage] == NO))))
        {
          if (showAlertExtensionChange([FSNode class], extension) == NSAlertDefaultReturn)
            {
              CLEAREDITING;
            }
        }

      if ([dirContents containsObject: newname])
	{
	  showAlertNameInUse([FSNode class], newname);
	  CLEAREDITING;
	}

      [opinfo setObject: @"WorkspaceRenameOperation" forKey: @"operation"];
      [opinfo setObject: [ednode path] forKey: @"source"];
      [opinfo setObject: newpath forKey: @"destination"];
      [opinfo setObject: [NSArray arrayWithObject: @""] forKey: @"files"];

      [self stopRepNameEditing];
      [desktopApp performFileOperation: opinfo];
    }

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
	  dndTarget = [nodeReps objectAtIndex: row];
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
	  FSNListViewNodeRep *rep = [nodeReps objectAtIndex: row];

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

  /* A pending single-click timer targets self with 0.5s repeats:NO; left
   * running past -dealloc it fires -singleClick: into a freed view. */
  if (clickTimer != nil)
    {
      [clickTimer invalidate];
      RELEASE (clickTimer);
      clickTimer = nil;
    }

  RELEASE (charBuffer);
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
      [self setRowHeight: CELLS_HEIGHT];
      [self setIntercellSpacing: NSZeroSize];
      [self setUsesAlternatingRowBackgroundColors: YES];

      dsource = [[dsclass alloc] initForListView: self];

      [self setDataSource: dsource];
      [self setDelegate: dsource];
      [self setTarget: dsource];
      [self setDoubleAction: @selector(doubleClickOnListView:)];

      lastKeyPressedTime = 0.0;
      charBuffer = nil;

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

- (void)singleClick: (NSTimer *)aTimer
{
  NSEvent *theEvent = [aTimer userInfo];
  NSPoint location;
  int row;

  location = [theEvent locationInWindow];
  location = [self convertPoint: location fromView: nil];
  row = [self rowAtPoint: location];

  if (row != -1)
    {
      [dsource setEditorAtRow: row withMouseDownEvent: theEvent];
    }

  [clickTimer release];
  clickTimer = nil;
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if (clickTimer != nil)
    {
      [clickTimer invalidate];
      [clickTimer release];
      clickTimer = nil;
    }

  if ([theEvent clickCount] == 1
      && (!([theEvent modifierFlags] & NSShiftKeyMask)))
    {
      NSPoint location;
      int row;

      location = [theEvent locationInWindow];
      location = [self convertPoint: location fromView: nil];
      row = [self rowAtPoint: location];

      if (row == [self selectedRow])
	{
	  // We clicked on an already-selected row.

	  ASSIGN(clickTimer, [NSTimer scheduledTimerWithTimeInterval: 0.5 // FIXME: use [NSEvent doubleClickInterval]
							      target: self
							    selector: @selector(singleClick:)
							    userInfo: theEvent
							     repeats: NO]);
	}
    }

  [dsource setMouseFlags: [theEvent modifierFlags]];
  [dsource stopRepNameEditing];

  [super mouseDown: theEvent];
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];
  unichar character = 0;
  NSString *characterStr = nil;
  NSRect vRect, hiddRect;
  NSPoint p;
  float x, y, w, h;

  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
      characterStr = [characters substringToIndex: 1];
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

    case NSUpArrowFunctionKey:
      [dsource stopRepNameEditing];
      [dsource selectRepInPrevRow];
      return;

    case NSDownArrowFunctionKey:
      [dsource stopRepNameEditing];
      [dsource selectRepInNextRow];
      return;

    case NSCarriageReturnCharacter:
      {
	unsigned flags = [theEvent modifierFlags];
	BOOL closesndr = ((flags == NSAlternateKeyMask)
			  || (flags == NSControlKeyMask));
	[dsource openSelectionInNewViewer: closesndr];
	DESTROY(charBuffer);
	return;
      }
    case 0x01B: // Escape
      DESTROY(charBuffer);
      return;
    default:
      break;
    }

  if (([characters length] > 0) && (character < 0xF700))
    {
      if (charBuffer != nil)
	{
	  if ([theEvent timestamp] - lastKeyPressedTime < 5.0) // seconds
	    {
	      NSString *appendBuffer = [charBuffer stringByAppendingString:characterStr];

	      // Try selecting
	      if ([dsource selectRepWithPrefix:appendBuffer])
		{
		  ASSIGN(charBuffer, appendBuffer);
		  return;
		}
	      // unable to select - fall-through and reinit as if typed is first char
	    }
	}

      ASSIGN(charBuffer, characterStr);
      lastKeyPressedTime = [theEvent timestamp];

      // Try selecting
      if ([dsource selectRepWithPrefix:charBuffer])
	{
	  return;
	}

      // Selection failed, reinitialize and use mismatching character as new buffer beginning
      DESTROY(charBuffer);
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
