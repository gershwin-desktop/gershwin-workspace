/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>
#import "GWSmartFolder.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNTextCell.h"
#import "Finder.h"
#import <MDKit/GWSavedSearch.h>
#import <MDKit/GWSavedSearchRunner.h>
#import "AppearanceMetrics.h"

/* Space between the window edge, the labels and the list. */
#define MARGIN 12.0
#define LABEL_HEIGHT 17.0
#define ROW_HEIGHT 28.0
#define ICON_SIZE 24

static NSMutableDictionary *openFolders = nil;

@interface GWSmartFolder (Private)
- (id)initWithPath:(NSString *)path;
- (void)buildWindow;
- (void)layoutStatus;
- (NSArray *)selectedNodes;
- (BOOL)runSearch;
@end

@implementation GWSmartFolder

- (void)dealloc
{
  [runner stop];
  [runner release];
  [nodes release];
  [filePath release];
  [win release];
  [super dealloc];
}

+ (BOOL)openSavedSearchAtPath:(NSString *)path
{
  GWSmartFolder *folder;
  NSString *err = nil;

  if (openFolders == nil) {
    openFolders = [NSMutableDictionary new];
  }
  folder = [openFolders objectForKey: path];
  if (folder == nil) {
    GWSavedSearch *search = [GWSavedSearch savedSearchWithContentsOfFile: path
                                                                   error: &err];

    if (search == nil) {
      NSRunAlertPanel([path lastPathComponent],
                      NSLocalizedString(@"This smart folder cannot be read: %@", @""),
                      NSLocalizedString(@"OK", @""), nil, nil, err);
      return NO;
    }
    folder = [[[self alloc] initWithPath: path] autorelease];
    [openFolders setObject: folder forKey: path];
  } else if ([folder runSearch] == NO) {
    return NO;
  }
  [[folder window] makeKeyAndOrderFront: nil];
  return YES;
}

- (id)initWithPath:(NSString *)path
{
  self = [super init];
  filePath = [path copy];
  nodes = [NSMutableArray new];
  [self buildWindow];
  [self runSearch];
  return self;
}

/* Opening a smart folder again means asking the question again, and the
 * file may have been edited since the window was made. */
- (BOOL)runSearch
{
  NSString *err = nil;
  GWSavedSearch *search = [GWSavedSearch savedSearchWithContentsOfFile: filePath
                                                                 error: &err];

  if (search == nil) {
    NSRunAlertPanel([filePath lastPathComponent],
                    NSLocalizedString(@"This smart folder cannot be read: %@", @""),
                    NSLocalizedString(@"OK", @""), nil, nil, err);
    return NO;
  }
  [runner stop];
  [runner release];
  [nodes removeAllObjects];
  [table reloadData];
  runner = [[GWSavedSearchRunner alloc] initWithSavedSearch: search
                                                   delegate: self];
  /* An unsearchable file still gets its window, saying why. */
  [runner start];
  [self updateCount];
  [self layoutStatus];
  return YES;
}

- (NSWindow *)window
{
  return win;
}

- (NSTextField *)labelWithFrame:(NSRect)r
{
  NSTextField *f = [[[NSTextField alloc] initWithFrame: r] autorelease];

  [f setEditable: NO];
  [f setSelectable: NO];
  [f setBezeled: NO];
  [f setDrawsBackground: NO];
  [f setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  return f;
}

- (NSTableColumn *)columnWithIdentifier:(NSString *)ident
                                  title:(NSString *)title
                                  width:(CGFloat)w
{
  NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: ident]
                      autorelease];

  [c setDataCell: [[[FSNTextCell alloc] init] autorelease]];
  [c setEditable: NO];
  [c setResizable: YES];
  [[c headerCell] setStringValue: title];
  [c setMinWidth: 50];
  [c setWidth: w];
  return c;
}

- (void)buildWindow
{
  NSRect frame = NSMakeRect(100, 100, 640, 420);
  NSView *content;
  NSRect b;

  win = [[NSWindow alloc] initWithContentRect: frame
                                    styleMask: NSTitledWindowMask
                                              | NSClosableWindowMask
                                              | NSMiniaturizableWindowMask
                                              | NSResizableWindowMask
                                      backing: NSBackingStoreBuffered
                                        defer: NO];
  [win setReleasedWhenClosed: NO];
  [win setTitle: [[filePath lastPathComponent] stringByDeletingPathExtension]];
  [win setDelegate: self];
  [win setFrameAutosaveName: @"smart_folder"];
  content = [win contentView];
  b = [content bounds];

  countField = [self labelWithFrame:
                NSMakeRect(MARGIN, MARGIN, b.size.width - 2 * MARGIN,
                           LABEL_HEIGHT)];
  [countField setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
  [content addSubview: countField];

  statusField = [self labelWithFrame:
                 NSMakeRect(MARGIN, b.size.height - MARGIN - LABEL_HEIGHT,
                            b.size.width - 2 * MARGIN, LABEL_HEIGHT)];
  [statusField setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
  [content addSubview: statusField];

  scroll = [[[NSScrollView alloc] initWithFrame:
             NSMakeRect(MARGIN, 2 * MARGIN + LABEL_HEIGHT,
                        b.size.width - 2 * MARGIN,
                        b.size.height - 3 * MARGIN - LABEL_HEIGHT)]
            autorelease];
  [scroll setBorderType: NSBezelBorder];
  [scroll setHasVerticalScroller: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

  table = [[[NSTableView alloc] initWithFrame: [[scroll contentView] bounds]]
           autorelease];
  [table setAllowsMultipleSelection: YES];
  [table setAllowsEmptySelection: YES];
  [table setRowHeight: ROW_HEIGHT];
  [table setIntercellSpacing: NSZeroSize];
  [table setUsesAlternatingRowBackgroundColors: YES];
  [table addTableColumn: [self columnWithIdentifier: @"name"
                      title: NSLocalizedString(@"Name", @"") width: 200]];
  [table addTableColumn: [self columnWithIdentifier: @"parent"
                      title: NSLocalizedString(@"Parent", @"") width: 120]];
  [table addTableColumn: [self columnWithIdentifier: @"date"
                      title: NSLocalizedString(@"Date Modified", @"") width: 120]];
  [table addTableColumn: [self columnWithIdentifier: @"size"
                      title: NSLocalizedString(@"Size", @"") width: 70]];
  [table addTableColumn: [self columnWithIdentifier: @"kind"
                      title: NSLocalizedString(@"Type", @"") width: 100]];
  [table setDataSource: self];
  [table setDelegate: self];
  [table setTarget: self];
  [table setDoubleAction: @selector(openSelection:)];
  [scroll setDocumentView: table];
  [content addSubview: scroll];
}

/* The status line takes as many lines as the text needs; the list gives
 * way to it. */
- (void)layoutStatus
{
  NSString *text = [runner statusText];
  NSRect b = [[win contentView] bounds];
  CGFloat width = b.size.width - 2 * MARGIN;
  CGFloat h = 0;
  CGFloat top;

  if ([text length]) {
    NSRect r = [text boundingRectWithSize: NSMakeSize(width, 10000)
                                  options: NSStringDrawingUsesLineFragmentOrigin
                               attributes: [NSDictionary dictionaryWithObject:
                                            METRICS_FONT_SYSTEM_REGULAR_11
                                            forKey: NSFontAttributeName]];

    h = ceil(r.size.height) + 4;
  }
  [statusField setStringValue: text ? text : @""];
  top = b.size.height - MARGIN;
  [statusField setFrame: NSMakeRect(MARGIN, top - h, width, h)];
  [scroll setFrame: NSMakeRect(MARGIN, 2 * MARGIN + LABEL_HEIGHT, width,
                               top - h - (h > 0 ? MARGIN : 0)
                               - (2 * MARGIN + LABEL_HEIGHT))];
}

- (void)updateCount
{
  NSUInteger n = [nodes count];

  if ([runner statusText] != nil && [runner isRunning] == NO && n == 0
      && [[runner resultPaths] count] == 0) {
    [countField setStringValue: @""];
  } else {
    [countField setStringValue: [NSString stringWithFormat: @"%lu %@%@",
                                 (unsigned long)n,
                                 NSLocalizedString(@"elements", @""),
                                 [runner isRunning]
                                 ? NSLocalizedString(@" - searching...", @"")
                                 : @""]];
  }
}

- (void)savedSearchRunnerDidChangeResults:(GWSavedSearchRunner *)r
{
  NSArray *paths = [r resultPaths];
  NSUInteger i;

  /* Results only ever get added; appending keeps the selection. */
  for (i = [nodes count]; i < [paths count]; i++) {
    FSNode *n = [FSNode nodeWithPath: [paths objectAtIndex: i]];

    if (n != nil) {
      [nodes addObject: n];
    }
  }
  [table reloadData];
  [self updateCount];
}

- (void)savedSearchRunnerDidFinish:(GWSavedSearchRunner *)r
{
  [self updateCount];
}

- (NSArray *)selectedNodes
{
  NSMutableArray *sel = [NSMutableArray array];
  NSIndexSet *rows = [table selectedRowIndexes];
  NSUInteger i;

  for (i = [rows firstIndex]; i != NSNotFound; i = [rows indexGreaterThanIndex: i]) {
    [sel addObject: [nodes objectAtIndex: i]];
  }
  return sel;
}

- (void)openSelection:(id)sender
{
  [[Finder finder] openFoundSelection: [self selectedNodes]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
  return [nodes count];
}

- (id)tableView:(NSTableView *)aTableView
          objectValueForTableColumn:(NSTableColumn *)col
                                row:(NSInteger)row
{
  FSNode *node = [nodes objectAtIndex: row];
  NSString *ident = [col identifier];

  if ([ident isEqual: @"name"]) {
    return [node name];
  } else if ([ident isEqual: @"parent"]) {
    return [[node parentPath] lastPathComponent];
  } else if ([ident isEqual: @"date"]) {
    return [node modDateDescription];
  } else if ([ident isEqual: @"size"]) {
    return [node sizeDescription];
  }
  return [node typeDescription];
}

- (void)tableView:(NSTableView *)aTableView
  willDisplayCell:(id)aCell
   forTableColumn:(NSTableColumn *)col
              row:(NSInteger)row
{
  if ([[col identifier] isEqual: @"name"]) {
    [(FSNTextCell *)aCell setIcon: [[FSNodeRep sharedInstance]
                                    iconOfSize: ICON_SIZE
                                    forNode: [nodes objectAtIndex: row]]];
  } else if ([[col identifier] isEqual: @"date"]) {
    [(FSNTextCell *)aCell setDateCell: YES];
  }
}

- (BOOL)tableView:(NSTableView *)aTableView
        writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard
{
  NSMutableArray *paths = [NSMutableArray array];
  NSNumber *r;

  for (r in rows) {
    [paths addObject: [[nodes objectAtIndex: [r intValue]] path]];
  }
  [pboard declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
                 owner: nil];
  [pboard setPropertyList: paths forType: NSFilenamesPboardType];
  return YES;
}

- (void)windowDidResize:(NSNotification *)n
{
  [self layoutStatus];
}

- (void)windowWillClose:(NSNotification *)n
{
  [runner stop];
  [[self retain] autorelease];
  [openFolders removeObjectForKey: filePath];
}

@end
