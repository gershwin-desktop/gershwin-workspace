/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The Finder list view options of FSNListView: sort direction, column
 * visibility and order, relative dates, folder sizes, text and icon size. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNListView.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"
#import "FSNFunctions.h"

/* Counts the user-change notifications. */
@interface OptionsObserver : NSObject
{
@public
  NSMutableArray *options;
}
@end

@implementation OptionsObserver
- (id)init
{
  self = [super init];
  options = [NSMutableArray new];
  return self;
}
- (void)changed:(NSNotification *)n
{
  [options addObject: [[n userInfo] objectForKey: FSNListViewChangedOptionKey]];
}
@end

/* Answers what the metadata provider protocol of the list view asks. */
@interface StubProvider : NSObject <FSNMetadataProvider, FSNListViewMetadataProvider>
@end

@implementation StubProvider
- (NSColor *)labelColorForPath:(NSString *)path
{
  if ([path hasSuffix: @"/mid.dat"])
    return [NSColor blueColor];
  return [path hasSuffix: @"/big.bin"] ? [NSColor redColor] : nil;
}
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSZeroPoint; }
- (void)invalidateCaches {}
- (NSString *)commentForPath:(NSString *)path
{
  return [path hasSuffix: @"/small.txt"] ? @"hello" : nil;
}
- (NSString *)labelNameForPath:(NSString *)path
{
  if ([path hasSuffix: @"/mid.dat"])
    return @"Blue";
  return [path hasSuffix: @"/big.bin"] ? @"Red" : nil;
}
@end

static void
spin(NSTimeInterval seconds)
{
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSArray *
shownNames(FSNListViewDataSource *ds)
{
  NSMutableArray *names = [NSMutableArray array];
  NSArray *reps = [ds reps];
  NSUInteger i;

  for (i = 0; i < [reps count]; i++)
    {
      [names addObject: [[[reps objectAtIndex: i] node] name]];
    }
  return names;
}

#define NAMES(...) namesList (__VA_ARGS__, nil)

static NSArray *
namesList(NSString *first, ...)
{
  NSMutableArray *a = [NSMutableArray array];
  va_list ap;
  NSString *s;

  va_start (ap, first);
  for (s = first; s; s = va_arg (ap, NSString *))
    {
      [a addObject: s];
    }
  va_end (ap);
  return a;
}

static NSCalendarDate *
localDate(int y, int m, int d, int h, int min)
{
  return [NSCalendarDate dateWithYear: y month: m day: d hour: h minute: min second: 0
                             timeZone: [NSTimeZone localTimeZone]];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* The expected texts are English; the framework's strings follow the
   * language of whoever runs the suite.  Set before the first lookup. */
  [[NSUserDefaults standardUserDefaults]
    setObject: [NSArray arrayWithObject: @"English"] forKey: @"NSLanguages"];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [NSTemporaryDirectory () stringByAppendingPathComponent:
                                              [NSString stringWithFormat: @"fsnlist-%d", getpid ()]];
  NSString *folder = [root stringByAppendingPathComponent: @"sub"];
  Class DS = [FSNListViewDataSource class];
  FSNListView *view;
  FSNListViewDataSource *ds;
  OptionsObserver *observer = [OptionsObserver new];
  StubProvider *provider = [StubProvider new];
  NSArray *ids;
  NSUInteger i, columnCount;

  [NSApplication sharedApplication];

  /* --- pure functions ------------------------------------------------ */

  ids = [DS finderColumnIds];
  PASS ([ids isEqual: NAMES (@"name", @"dateModified", @"dateCreated", @"size", @"kind",
                             @"label", @"version", @"comments", @"dateLastOpened")],
        "MI-LST-1 the Finder lsvp column ids are the ones this list knows");
  {
    BOOL roundTrip = YES;

    for (i = 0; i < [ids count]; i++)
      {
        NSNumber *ident = [DS tableIdentifierForColumnId: [ids objectAtIndex: i]];

        roundTrip = roundTrip && ident
          && [[DS columnIdForTableIdentifier: ident] isEqual: [ids objectAtIndex: i]];
      }
    PASS (roundTrip, "MI-LST-2 every Finder column id maps to a table identifier and back");
  }
  PASS ([DS tableIdentifierForColumnId: @"bogus"] == nil,
        "MI-LST-3 an unknown column id has no table identifier");
  PASS ([[DS tableIdentifierForColumnId: @"name"] intValue] == FSNInfoNameType
        && [[DS tableIdentifierForColumnId: @"dateModified"] intValue] == FSNInfoDateType
        && [[DS tableIdentifierForColumnId: @"size"] intValue] == FSNInfoSizeType
        && [[DS tableIdentifierForColumnId: @"kind"] intValue] == FSNInfoKindType,
        "MI-LST-4 the columns the list always had keep their old identifiers");

  PASS ([DS defaultSortAscendingForColumnId: @"name"]
        && [DS defaultSortAscendingForColumnId: @"kind"]
        && ![DS defaultSortAscendingForColumnId: @"dateModified"]
        && ![DS defaultSortAscendingForColumnId: @"dateCreated"]
        && ![DS defaultSortAscendingForColumnId: @"dateLastOpened"]
        && ![DS defaultSortAscendingForColumnId: @"size"],
        "MI-LST-5 a first click sorts text A-Z and dates and sizes newest/biggest first");

  {
    NSDate *now = localDate (2026, 10, 11, 9, 30);
    NSString *today = [DS descriptionOfDate: localDate (2026, 10, 11, 0, 5)
                                 relativeTo: now relativeNames: YES];
    NSString *yesterday = [DS descriptionOfDate: localDate (2026, 10, 10, 23, 59)
                                     relativeTo: now relativeNames: YES];
    NSString *olderExpected = @"10/9/26 11:59 PM";
    NSString *futureExpected = @"10/12/26 12:01 AM";
    NSString *plainExpected = @"10/11/26 12:05 AM";
    NSString *older = [DS descriptionOfDate: localDate (2026, 10, 9, 23, 59)
                                 relativeTo: now relativeNames: YES];
    NSString *future = [DS descriptionOfDate: localDate (2026, 10, 12, 0, 1)
                                  relativeTo: now relativeNames: YES];
    NSString *plain = [DS descriptionOfDate: localDate (2026, 10, 11, 0, 5)
                                 relativeTo: now relativeNames: NO];

    PASS_EQUAL (today, @"Today 12:05 AM", "MI-LST-6 [O:2026-10-11 E22] a date of today reads the day word and the time");
    PASS_EQUAL (yesterday, @"Yesterday 11:59 PM",
                "MI-LST-7 [O:2026-10-11 E22] a date of the day before reads \"Yesterday\" and the time");
    PASS_EQUAL (older, olderExpected,
                "MI-LST-8 an older date keeps the plain form");
    PASS_EQUAL (future, futureExpected,
                "MI-LST-9 a date after today is not called Today or Yesterday");
    PASS_EQUAL (plain, plainExpected,
                "MI-LST-10 with relative dates off today is a plain date");

    /* German as the Mac mini shows it (E22): "Heute, 09:51", "Gestern,
     * 10:15" and everything else dd.mm.yyyy HH:MM. */
    {
      NSDictionary *de = [NSDictionary dictionaryWithContentsOfFile:
        @"../../FSNode/Resources/German.lproj/Localizable.strings"];

      PASS_EQUAL ([DS descriptionOfDate: localDate (2026, 10, 11, 9, 51)
                             relativeTo: now relativeNames: YES strings: de],
                  @"Heute, 09:51", "MI-LST-80 [O:2026-10-11 E22] German today");
      PASS_EQUAL ([DS descriptionOfDate: localDate (2026, 10, 10, 10, 15)
                             relativeTo: now relativeNames: YES strings: de],
                  @"Gestern, 10:15", "MI-LST-81 [O:2026-10-11 E22] German yesterday");
      PASS_EQUAL ([DS descriptionOfDate: localDate (2026, 10, 8, 9, 30)
                             relativeTo: now relativeNames: YES strings: de],
                  @"08.10.2026 09:30", "MI-LST-82 [O:2026-10-11 E22] German older date");
      PASS_EQUAL ([DS descriptionOfDate: localDate (2026, 10, 11, 9, 51)
                             relativeTo: now relativeNames: NO strings: de],
                  @"11.10.2026 09:51", "MI-LST-83 [O:2026-10-11 E22] German today with relative off");
    }
  }

  PASS ([DS rowHeightForTextSize: 0 iconSize: 24] == 28.0,
        "MI-LST-11 the default row height is the 28 points the list always had");
  PASS ([DS rowHeightForTextSize: 0 iconSize: 32] == 39.0
        && [DS rowHeightForTextSize: 0 iconSize: 16] < 28.0,
        "MI-LST-12 the row height follows the icon size");
  {
    BOOL small = YES, large = YES;
    int size;

    for (size = 10; size <= 16; size++)
      {
        small = small && [DS rowHeightForTextSize: size iconSize: 16] == size + 7;
        large = large && [DS rowHeightForTextSize: size iconSize: 32] == 39.0;
      }
    PASS (small, "MI-LST-104 [O:2026-10-11 E24] with 16 point icons a row is the text size plus 7 (10 -> 17 ... 16 -> 23)");
    PASS (large, "MI-LST-105 [O:2026-10-11 E24] with 32 point icons a row is 39 for every text size 10 to 16");
  }
  PASS ([DS rowHeightForTextSize: 40 iconSize: 16] > [DS rowHeightForTextSize: 0 iconSize: 16],
        "MI-LST-13 a big text makes rows taller than a small icon needs");

  /* --- folder size walk ---------------------------------------------- */

  [fm removeItemAtPath: root error: NULL];
  [fm createDirectoryAtPath: folder withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: [folder stringByAppendingPathComponent: @"deep"]
withIntermediateDirectories: YES attributes: nil error: NULL];
  [[NSData dataWithBytes: "0123456789" length: 10]
    writeToFile: [folder stringByAppendingPathComponent: @"a"] atomically: NO];
  [[NSMutableData dataWithLength: 1000]
    writeToFile: [folder stringByAppendingPathComponent: @"deep/b"] atomically: NO];
  symlink ("/etc/passwd", [[folder stringByAppendingPathComponent: @"link"] fileSystemRepresentation]);

  {
    /* Finder adds up the space the files take, not their lengths (E23). */
    unsigned long long below = FSNAllocatedSizeOfPath ([folder stringByAppendingPathComponent: @"a"])
      + FSNAllocatedSizeOfPath ([folder stringByAppendingPathComponent: @"deep/b"])
      + FSNAllocatedSizeOfPath ([folder stringByAppendingPathComponent: @"link"]);
    int stopped = 1;

    PASS ([FSNFolderSizeCalculator sizeOfTreeAtPath: folder stop: NULL] == below && below > 0,
          "MI-LST-14 [O:2026-10-11 E23] a folder's size is the sum of the space taken by what is below it, links not followed");
    PASS ([FSNFolderSizeCalculator sizeOfTreeAtPath: [folder stringByAppendingPathComponent: @"a"]
                                               stop: NULL]
          == FSNAllocatedSizeOfPath ([folder stringByAppendingPathComponent: @"a"]),
          "MI-LST-15 [O:2026-10-11 E23] the size of a plain file is the space it takes");
    PASS ([FSNFolderSizeCalculator sizeOfTreeAtPath: folder stop: &stopped] == 0,
          "MI-LST-16 a walk told to stop does not go on");
    PASS ([FSNFolderSizeCalculator sizeOfTreeAtPath: @"/nonexistent-fsn" stop: NULL] == 0,
          "MI-LST-17 a folder that is not there is 0 bytes");
  }

  /* --- the list view on a fixture folder ----------------------------- */

  [fm removeItemAtPath: root error: NULL];
  [fm createDirectoryAtPath: folder withIntermediateDirectories: YES attributes: nil error: NULL];
  [[NSMutableData dataWithLength: 5] writeToFile: [root stringByAppendingPathComponent: @"small.txt"]
                                      atomically: NO];
  [[NSMutableData dataWithLength: 20000] writeToFile: [root stringByAppendingPathComponent: @"big.bin"]
                                         atomically: NO];
  [[NSMutableData dataWithLength: 5000] writeToFile: [root stringByAppendingPathComponent: @"mid.dat"]
                                        atomically: NO];
  [[NSMutableData dataWithLength: 9000] writeToFile: [folder stringByAppendingPathComponent: @"inner"]
                                        atomically: NO];
  [fm setAttributes: [NSDictionary dictionaryWithObject: localDate (2026, 1, 2, 3, 4)
                                                 forKey: NSFileModificationDate]
       ofItemAtPath: [root stringByAppendingPathComponent: @"small.txt"] error: NULL];
  [fm setAttributes: [NSDictionary dictionaryWithObject: localDate (2026, 5, 6, 7, 8)
                                                 forKey: NSFileModificationDate]
       ofItemAtPath: [root stringByAppendingPathComponent: @"mid.dat"] error: NULL];
  [fm setAttributes: [NSDictionary dictionaryWithObject: localDate (2026, 9, 9, 9, 9)
                                                 forKey: NSFileModificationDate]
       ofItemAtPath: [root stringByAppendingPathComponent: @"big.bin"] error: NULL];

  [[FSNodeRep sharedInstance] setMetadataProvider: provider];

  view = [[FSNListView alloc] initWithFrame: NSMakeRect (0, 0, 800, 300)
                            dataSourceClass: [FSNListViewDataSource class]];
  ds = (FSNListViewDataSource *)[view dataSource];
  [view showContentsOfNode: [FSNode nodeWithPath: root]];

  [[NSNotificationCenter defaultCenter] addObserver: observer
                                           selector: @selector(changed:)
                                               name: FSNListViewOptionsDidChangeNotification
                                             object: view];

  PASS_EQUAL ([ds columnOrder], NAMES (@"name", @"dateModified", @"size", @"kind"),
              "MI-LST-18 the default columns are name, date modified, size, kind");
  PASS_EQUAL ([ds sortColumnId], @"name", "MI-LST-19 the list is sorted by name at first");
  PASS ([ds sortAscending], "MI-LST-20 and ascending");
  PASS_EQUAL (shownNames (ds), NAMES (@"big.bin", @"mid.dat", @"small.txt", @"sub"),
              "MI-LST-21 sorted by name ascending");

  PASS ([ds setSortColumnId: @"size" ascending: YES], "MI-LST-22 sorting by a shown column works");
  PASS_EQUAL ([shownNames (ds) objectAtIndex: [shownNames (ds) count] - 1], @"big.bin",
              "MI-LST-23 size ascending puts the biggest file last");
  [ds setSortAscending: NO];
  PASS_EQUAL ([shownNames (ds) objectAtIndex: 0], @"big.bin",
              "MI-LST-24 size descending puts the biggest file first");
  PASS ([ds sortAscending] == NO, "MI-LST-25 the direction is kept");

  [ds setSortColumnId: @"dateModified" ascending: YES];
  PASS_EQUAL ([shownNames (ds) subarrayWithRange: NSMakeRange (0, 3)],
              NAMES (@"small.txt", @"mid.dat", @"big.bin"),
              "MI-LST-26 date modified ascending is oldest first");
  [ds setSortAscending: NO];
  PASS_EQUAL ([shownNames (ds) subarrayWithRange: NSMakeRange (1, 3)],
              NAMES (@"big.bin", @"mid.dat", @"small.txt"),
              "MI-LST-27 date modified descending is newest first");

  PASS ([ds setSortColumnId: @"version" ascending: YES] == NO
        && [ds setSortColumnId: @"bogus" ascending: YES] == NO,
        "MI-LST-28 sorting by a hidden or unknown column is refused");
  PASS ([observer->options count] == 0,
        "MI-LST-29 the setters do not post the user-change notification");

  /* header clicks */
  [ds setSortColumnId: @"name" ascending: YES];
  [ds tableView: view didClickTableColumn: [view tableColumnWithIdentifier:
                                                   [NSNumber numberWithInt: FSNInfoNameType]]];
  PASS ([ds sortAscending] == NO && [[ds sortColumnId] isEqual: @"name"],
        "MI-LST-30 clicking the sorted column's header reverses the direction");
  PASS_EQUAL ([shownNames (ds) objectAtIndex: 0], @"sub", "MI-LST-31 and the rows follow");
  [ds tableView: view didClickTableColumn: [view tableColumnWithIdentifier:
                                                   [NSNumber numberWithInt: FSNInfoSizeType]]];
  PASS ([[ds sortColumnId] isEqual: @"size"] && [ds sortAscending] == NO,
        "MI-LST-32 clicking another header sorts by it in its default direction (size: biggest first)");
  [ds tableView: view didClickTableColumn: [view tableColumnWithIdentifier:
                                                   [NSNumber numberWithInt: FSNInfoKindType]]];
  PASS ([[ds sortColumnId] isEqual: @"kind"] && [ds sortAscending],
        "MI-LST-33 and text columns start ascending");
  PASS_EQUAL (observer->options, NAMES (FSNListViewOptionSort, FSNListViewOptionSort,
                                        FSNListViewOptionSort),
              "MI-LST-34 every header click is reported once as a sort change");
  [observer->options removeAllObjects];

  /* visibility and order */
  PASS ([ds setColumn: @"size" visible: NO] && ![ds isColumnVisible: @"size"],
        "MI-LST-35 a column can be hidden");
  PASS_EQUAL ([ds columnOrder], NAMES (@"name", @"dateModified", @"kind"),
              "MI-LST-36 the hidden column is gone from the order");
  PASS ([ds setColumn: @"name" visible: NO] == NO && [ds isColumnVisible: @"name"],
        "MI-LST-37 the name column cannot be hidden");
  PASS ([ds setColumn: @"bogus" visible: YES] == NO, "MI-LST-38 an unknown id is refused");
  [ds setSortColumnId: @"name" ascending: YES];
  [ds setSortColumnId: @"kind" ascending: NO];
  [ds setColumn: @"kind" visible: NO];
  PASS_EQUAL ([ds sortColumnId], @"name",
              "MI-LST-39 hiding the column the list is sorted by sorts by name instead");
  PASS ([ds sortAscending], "MI-LST-40 in the direction the name column had (A-Z here)");
  [ds setColumn: @"kind" visible: YES];
  [ds setSortColumnId: @"name" ascending: NO];
  [ds setSortColumnId: @"kind" ascending: YES];
  PASS ([ds sortAscendingForColumnId: @"name"] == NO
        && [ds sortAscendingForColumnId: @"kind"] == YES
        && [ds sortAscendingForColumnId: @"size"] == NO,
        "MI-LST-77 [O:2026-10-11 E20] every column keeps its own direction, its first-click one until changed");
  [ds setColumn: @"kind" visible: NO];
  PASS_EQUAL ([ds sortColumnId], @"name",
              "MI-LST-78 [O:2026-10-11 E20] hiding the sort column sorts by name");
  PASS (![ds sortAscending],
        "MI-LST-79 [O:2026-10-11 E20] in the direction the name column was last sorted in (Z-A here)");
  [ds setSortColumnId: @"name" ascending: YES];
  [ds setColumn: @"kind" visible: YES];

  [ds setColumnWidth: 222 forColumnId: @"size"];
  [ds setColumn: @"size" visible: YES];
  PASS ([ds isColumnVisible: @"size"] && [ds columnWidthForColumnId: @"size"] == 222,
        "MI-LST-41 a column set to a width while hidden comes back with it");
  [ds setColumn: @"kind" visible: YES];
  [ds setColumn: @"comments" visible: YES];
  [ds setColumn: @"label" visible: YES];
  PASS_EQUAL ([[ds columnOrder] lastObject], @"label", "MI-LST-42 a shown column is appended");

  [ds setColumnOrder: NAMES (@"label", @"kind", @"bogus", @"name", @"size")];
  PASS_EQUAL ([ds columnOrder],
              NAMES (@"name", @"label", @"kind", @"size", @"dateModified", @"comments"),
              "MI-LST-43 listed columns go left in that order, name first, the rest follow");
  PASS ([observer->options count] == 0, "MI-LST-44 setting the order does not post");

  /* a drag by the user */
  columnCount = [[view tableColumns] count];
  [view moveColumn: 3 toColumn: 1];
  spin (0.3);
  PASS_EQUAL ([ds columnOrder],
              NAMES (@"name", @"size", @"label", @"kind", @"dateModified", @"comments"),
              "MI-LST-45 a column dragged by the user stays where it was dropped");
  PASS_EQUAL (observer->options, NAMES (FSNListViewOptionColumnOrder),
              "MI-LST-46 and the new order is reported once");
  [observer->options removeAllObjects];
  [view moveColumn: 1 toColumn: 0];
  spin (0.3);
  PASS_EQUAL ([[ds columnOrder] objectAtIndex: 0], @"name",
              "MI-LST-47 the name column is put back at the left edge");
  PASS ([[view tableColumns] count] == columnCount, "MI-LST-48 and no column is lost");
  [observer->options removeAllObjects];

  /* values in the new columns */
  [ds setColumn: @"dateCreated" visible: YES];
  [ds setColumn: @"version" visible: YES];
  [ds setColumn: @"dateLastOpened" visible: YES];
  {
    NSInteger row = [shownNames (ds) indexOfObject: @"small.txt"];
    NSTableColumn *cmt = [view tableColumnWithIdentifier: [DS tableIdentifierForColumnId: @"comments"]];
    NSTableColumn *lbl = [view tableColumnWithIdentifier: [DS tableIdentifierForColumnId: @"label"]];
    NSTableColumn *ver = [view tableColumnWithIdentifier: [DS tableIdentifierForColumnId: @"version"]];
    NSTableColumn *opened = [view tableColumnWithIdentifier:
                                    [DS tableIdentifierForColumnId: @"dateLastOpened"]];

    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: cmt row: row], @"hello",
                "MI-LST-49 the comments column shows the provider's comment");
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: cmt row: 0], @"--",
                "MI-LST-50 an empty comment shows --");
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: ver row: row], @"--",
                "MI-LST-51 a plain file has no version");
    row = [shownNames (ds) indexOfObject: @"big.bin"];
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: lbl row: row], @"Red",
                "MI-LST-52 the label column shows the label name");
    PASS ([[ds tableView: view objectValueForTableColumn: opened row: row] length] > 5
          && ![[ds tableView: view objectValueForTableColumn: opened row: row] isEqual: @"--"],
        "MI-LST-53 the date last opened is a date");
  }
  [ds setSortColumnId: @"label" ascending: NO];
  PASS_EQUAL ([shownNames (ds) objectAtIndex: 0], @"big.bin",
              "MI-LST-54 [O:2026-10-11 E24] sorting by label puts labelled files before those without (descending)");
  [ds setSortColumnId: @"label" ascending: YES];
  {
    NSArray *names = shownNames (ds);

    PASS ([names indexOfObject: @"small.txt"] < [names indexOfObject: @"mid.dat"]
          && [names indexOfObject: @"sub"] < [names indexOfObject: @"mid.dat"],
          "MI-LST-101 [O:2026-10-11 E24] first click on Label: no label first");
    PASS ([names indexOfObject: @"mid.dat"] < [names indexOfObject: @"big.bin"],
          "MI-LST-102 [O:2026-10-11 E24] then alphabetical by the label name (Blue before Red), not by colour");
  }
  [ds setSortColumnId: @"label" ascending: NO];
  PASS_EQUAL ([shownNames (ds) objectAtIndex: 0], @"big.bin",
              "MI-LST-103 [O:2026-10-11 E24] the second click reverses it exactly");
  [ds setSortColumnId: @"name" ascending: YES];

  /* relative dates in the cell values */
  {
    NSInteger row = [shownNames (ds) indexOfObject: @"big.bin"];
    NSTableColumn *dm = [view tableColumnWithIdentifier: [NSNumber numberWithInt: FSNInfoDateType]];

    [fm setAttributes: [NSDictionary dictionaryWithObject: [NSDate date] forKey: NSFileModificationDate]
         ofItemAtPath: [root stringByAppendingPathComponent: @"mid.dat"] error: NULL];
    [view reloadContents];
    row = [shownNames (ds) indexOfObject: @"mid.dat"];
    PASS (![[ds tableView: view objectValueForTableColumn: dm row: row] hasPrefix: @"Today"],
          "MI-LST-55 dates are plain by default");
    [ds setUsesRelativeDates: YES];
    PASS ([[ds tableView: view objectValueForTableColumn: dm row: row] hasPrefix: @"Today "],
          "MI-LST-56 with relative dates on, today's file reads Today and the time");
    [ds setUsesRelativeDates: NO];
  }

  /* text and icon size */
  {
    CGFloat before = [view rowHeight];

    PASS (before == 28.0 && [ds listIconSize] == 24, "MI-LST-57 default row 28, icon 24");
    [ds setListIconSize: 32];
    PASS ([view rowHeight] == 39.0, "MI-LST-58 [O:2026-10-11 E24] a 32 point icon makes the rows 39 points");
    [ds setListIconSize: 1000];
    PASS ([ds listIconSize] == 128, "MI-LST-59 icon sizes are limited to 128");
    [ds setListIconSize: 1];
    PASS ([ds listIconSize] == 16, "MI-LST-60 and to 16 at the least");
    [ds setListIconSize: 24];
    PASS ([view rowHeight] == 28.0, "MI-LST-61 back to 24 points the rows are 28 again");
    [ds setTextSize: 30];
    PASS ([ds textSize] == 30 && [view rowHeight] > 28.0,
          "MI-LST-62 a 30 point text makes the rows taller");
    PASS ([[[[view tableColumns] objectAtIndex: 0] dataCell] font] != nil
          && [[[[[view tableColumns] objectAtIndex: 1] dataCell] font] pointSize] == 30,
          "MI-LST-63 and every column's cells use it");
    [ds setTextSize: 0];
    PASS ([view rowHeight] == 28.0, "MI-LST-64 text size 0 selects the default again");
  }

  /* the size of a file is the space it takes */
  {
    NSInteger row = [shownNames (ds) indexOfObject: @"small.txt"];
    NSTableColumn *sz = [view tableColumnWithIdentifier: [NSNumber numberWithInt: FSNInfoSizeType]];

    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: row],
                FSNFinderSizeDescription (FSNAllocatedSizeOfPath ([root stringByAppendingPathComponent: @"small.txt"]), nil),
                "MI-LST-98 [O:2026-10-11 E23] a 5 byte file shows the space it takes, like \"4 KB\"");
  }

  /* folder sizes */
  {
    NSInteger row = [shownNames (ds) indexOfObject: @"sub"];
    NSTableColumn *sz = [view tableColumnWithIdentifier: [NSNumber numberWithInt: FSNInfoSizeType]];

    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: row], @"--",
                "MI-LST-65 a folder's size is -- as long as sizes are not calculated");
    [ds setCalculatesAllSizes: YES];
    PASS ([ds isCalculatingSizes], "MI-LST-66 turning calculate all sizes on starts the walk");
    PASS ([ds calculatedSizeForPath: [root stringByAppendingPathComponent: @"sub"]] == nil,
          "MI-LST-67 the UI does not wait for it");
    for (i = 0; i < 40 && [ds isCalculatingSizes]; i++)
      {
        spin (0.05);
      }
    PASS ([ds isCalculatingSizes] == NO, "MI-LST-68 the walk ends");
    PASS ([[ds calculatedSizeForPath: [root stringByAppendingPathComponent: @"sub"]]
            unsignedLongLongValue]
          == FSNAllocatedSizeOfPath ([[root stringByAppendingPathComponent: @"sub"]
                                       stringByAppendingPathComponent: @"inner"]),
          "MI-LST-69 the folder's size is that of its contents");
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: row],
                FSNFinderSizeDescription (FSNAllocatedSizeOfPath ([[root stringByAppendingPathComponent: @"sub"]
                                            stringByAppendingPathComponent: @"inner"]), nil),
                "MI-LST-70 and the size column shows it");

    [ds setSortColumnId: @"size" ascending: NO];
    PASS_EQUAL ([shownNames (ds) objectAtIndex: 0], @"big.bin", "MI-LST-71 sizes sort with folders");
    PASS_EQUAL ([shownNames (ds) objectAtIndex: 1], @"sub", "MI-LST-72 folders sort by their calculated size");

    [ds setCalculatesAllSizes: NO];
    PASS ([ds calculatedSizeForPath: [root stringByAppendingPathComponent: @"sub"]] == nil,
          "MI-LST-73 turning it off forgets the sizes");
    row = [shownNames (ds) indexOfObject: @"sub"];
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: row], @"--",
                "MI-LST-74 and folders show -- again");
  }

  /* a walk cancelled by showing another folder delivers nothing */
  {
    FSNode *other = [FSNode nodeWithPath: folder];

    [ds setCalculatesAllSizes: YES];
    [view showContentsOfNode: other];
    spin (0.5);
    PASS ([ds calculatedSizeForPath: [root stringByAppendingPathComponent: @"sub"]] == nil,
          "MI-LST-75 sizes of a folder no longer shown are not kept or delivered");
    PASS ([ds isCalculatingSizes] == NO, "MI-LST-76 a folder without subfolders has nothing to walk");
    [ds setCalculatesAllSizes: NO];
  }

  /* a package shows its size without calculate all sizes (E23), a plain folder not */
  {
    NSString *pk = [root stringByAppendingPathComponent: @"Thing.app"];
    NSTableColumn *sz;
    NSInteger prow, frow;
    unsigned long long expected;

    [fm createDirectoryAtPath: [pk stringByAppendingPathComponent: @"Contents"]
  withIntermediateDirectories: YES attributes: nil error: NULL];
    [fm createDirectoryAtPath: [pk stringByAppendingPathComponent: @"Resources"]
  withIntermediateDirectories: YES attributes: nil error: NULL];
    [@"{}" writeToFile: [pk stringByAppendingPathComponent: @"Resources/Info.plist"]
            atomically: NO encoding: NSUTF8StringEncoding error: NULL];
    [[NSMutableData dataWithLength: 30000]
      writeToFile: [pk stringByAppendingPathComponent: @"Contents/blob"] atomically: NO];
    expected = FSNAllocatedSizeOfPath ([pk stringByAppendingPathComponent: @"Contents/blob"])
      + FSNAllocatedSizeOfPath ([pk stringByAppendingPathComponent: @"Resources/Info.plist"]);
    [view showContentsOfNode: [FSNode nodeWithPath: root]];
    sz = [view tableColumnWithIdentifier: [NSNumber numberWithInt: FSNInfoSizeType]];
    for (i = 0; i < 40 && [ds isCalculatingSizes]; i++)
      {
        spin (0.05);
      }
    prow = [shownNames (ds) indexOfObject: @"Thing.app"];
    frow = [shownNames (ds) indexOfObject: @"sub"];
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: prow],
                FSNFinderSizeDescription (expected, nil),
                "MI-LST-99 [O:2026-10-11 E23] a package shows its size although sizes are not calculated");
    PASS_EQUAL ([ds tableView: view objectValueForTableColumn: sz row: frow], @"--",
                "MI-LST-100 [O:2026-10-11 E23] a plain folder shows -- then");
  }

  /* scroll position, the same convention as the icon view (E11) */
  {
    NSString *many = [root stringByAppendingPathComponent: @"many"];
    NSScrollView *sc = [[[NSScrollView alloc] initWithFrame: NSMakeRect (0, 0, 400, 200)] autorelease];
    FSNListView *lv = [[FSNListView alloc] initWithFrame: NSMakeRect (0, 0, 400, 200)
                                         dataSourceClass: [FSNListViewDataSource class]];
    NSPoint got;

    [fm createDirectoryAtPath: many withIntermediateDirectories: YES attributes: nil error: NULL];
    for (i = 0; i < 80; i++)
      {
        [@"x" writeToFile: [many stringByAppendingPathComponent:
                                   [NSString stringWithFormat: @"f%03u.txt", (unsigned)i]]
               atomically: NO encoding: NSUTF8StringEncoding error: NULL];
      }
    [sc setDocumentView: lv];
    [lv showContentsOfNode: [FSNode nodeWithPath: many]];

    got = [lv scrollPosition];
    PASS (fabs (got.x) < 0.5 && fabs (got.y) < 0.5,
          "MI-LST-106 [O:2026-10-11 E11] a freshly shown folder is scrolled to its top left");
    [lv setScrollPosition: NSMakePoint (0, 120)];
    got = [lv scrollPosition];
    PASS (fabs (got.x) < 0.5 && fabs (got.y - 120) < 0.5
          && fabs (NSMinY ([lv visibleRect]) - 120) < 0.5,
          "MI-LST-107 [O:2026-10-11 E11] the position is points from the top left of the content to the visible corner");
    [lv reloadContents];
    got = [lv scrollPosition];
    PASS (fabs (got.y - 120) < 0.5,
          "MI-LST-108 [G] it survives a reload of the folder");
    [lv setScrollPosition: NSMakePoint (0, 100000)];
    got = [lv scrollPosition];
    PASS (got.y < 100000 && NSMaxY ([lv visibleRect]) <= NSMaxY ([lv bounds]) + 0.5,
          "MI-LST-109 [G] a position beyond the content is held inside it");
    [lv release];
  }

  [view release];
  [observer release];
  [fm removeItemAtPath: root error: NULL];
  [arp release];
  return 0;
}
