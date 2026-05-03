/* GWViewerSidebar.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import "GWViewerSidebar.h"
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "NetworkFSNode.h"

#define ROW_HEIGHT 20.0
#define HEADER_HEIGHT 18.0
#define ICON_SIZE 16
#define INDENT 0.0

/* Sidebar item kinds */
typedef enum {
  GWSidebarItemHeader = 0,
  GWSidebarItemPath,
  GWSidebarItemNetwork
} GWSidebarItemKind;

/* Outline view that forces a Snow-Leopard-style sidebar background.
   NSOutlineView/NSTableView's setBackgroundColor: isn't reliably honored
   in this GNUstep build, so we override the background paint directly. */
@interface GWSidebarOutlineView : NSOutlineView
@end

@implementation GWSidebarOutlineView
- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
  [[NSColor windowBackgroundColor] set];
  NSRectFill(clipRect);
}
@end

@interface GWSidebarItem : NSObject
{
  NSString *title;
  NSString *path;
  NSImage *icon;
  GWSidebarItemKind kind;
  NSMutableArray *children;
}
- (id)initHeaderWithTitle:(NSString *)aTitle;
- (id)initPathItemWithTitle:(NSString *)aTitle path:(NSString *)aPath;
- (id)initNetworkItemWithTitle:(NSString *)aTitle;
- (void)addChild:(GWSidebarItem *)child;
- (NSString *)title;
- (NSString *)path;
- (NSImage *)icon;
- (GWSidebarItemKind)kind;
- (NSArray *)children;
- (BOOL)isHeader;
@end

@implementation GWSidebarItem

- (id)initHeaderWithTitle:(NSString *)aTitle
{
  self = [super init];
  if (self) {
    title = [aTitle copy];
    kind = GWSidebarItemHeader;
    children = [[NSMutableArray alloc] init];
  }
  return self;
}

- (id)initPathItemWithTitle:(NSString *)aTitle path:(NSString *)aPath
{
  self = [super init];
  if (self) {
    title = [aTitle copy];
    path = [aPath copy];
    kind = GWSidebarItemPath;
    children = nil;
  }
  return self;
}

- (id)initNetworkItemWithTitle:(NSString *)aTitle
{
  self = [super init];
  if (self) {
    title = [aTitle copy];
    kind = GWSidebarItemNetwork;
    children = nil;
  }
  return self;
}

- (void)dealloc
{
  RELEASE (title);
  RELEASE (path);
  RELEASE (icon);
  RELEASE (children);
  [super dealloc];
}

- (void)addChild:(GWSidebarItem *)child
{
  if (children == nil) {
    children = [[NSMutableArray alloc] init];
  }
  [children addObject: child];
}

- (NSString *)title { return title; }
- (NSString *)path { return path; }
- (GWSidebarItemKind)kind { return kind; }
- (NSArray *)children { return children; }
- (BOOL)isHeader { return kind == GWSidebarItemHeader; }

- (NSImage *)icon
{
  if (icon != nil) {
    return icon;
  }

  if (kind == GWSidebarItemPath && path != nil) {
    FSNode *node = [FSNode nodeWithPath: path];
    if (node && [node isValid]) {
      NSImage *ic = [[FSNodeRep sharedInstance] iconOfSize: ICON_SIZE
                                                   forNode: node];
      if (ic) {
        ASSIGN (icon, ic);
        return icon;
      }
    }
    /* Fallback to a generic folder icon */
    NSImage *fallback = [NSImage imageNamed: @"Folder"];
    if (fallback) {
      [fallback setScalesWhenResized: YES];
      [fallback setSize: NSMakeSize(ICON_SIZE, ICON_SIZE)];
      ASSIGN (icon, fallback);
    }
    return icon;
  }

  if (kind == GWSidebarItemNetwork) {
    NSImage *ic = [NSImage imageNamed: @"Network"];
    if (ic == nil) {
      ic = [NSImage imageNamed: @"Computer"];
    }
    if (ic) {
      [ic setScalesWhenResized: YES];
      [ic setSize: NSMakeSize(ICON_SIZE, ICON_SIZE)];
      ASSIGN (icon, ic);
    }
    return icon;
  }

  return nil;
}

@end


@implementation GWViewerSidebar

- (void)dealloc
{
  if (outlineView) {
    [outlineView setDataSource: nil];
    [outlineView setDelegate: nil];
  }
  RELEASE (rootItems);
  RELEASE (scrollView);
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
          forViewer:(id)vwr
{
  self = [super initWithFrame: frameRect];
  if (self) {
    NSTableColumn *col;

    viewer = vwr;
    rootItems = [[NSMutableArray alloc] init];

    [self buildModel];

    scrollView = [[NSScrollView alloc] initWithFrame: [self bounds]];
    [scrollView setHasVerticalScroller: YES];
    [scrollView setHasHorizontalScroller: NO];
    [scrollView setBorderType: NSBezelBorder];
    [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [scrollView setBackgroundColor: [NSColor windowBackgroundColor]];
    [scrollView setDrawsBackground: YES];

    outlineView = [[GWSidebarOutlineView alloc] initWithFrame: [[scrollView contentView] bounds]];
    [outlineView setBackgroundColor: [NSColor windowBackgroundColor]];
    [outlineView setHeaderView: nil];
    [outlineView setRowHeight: ROW_HEIGHT];
    [outlineView setIndentationPerLevel: INDENT];
    [outlineView setIndentationMarkerFollowsCell: YES];
    [outlineView setAutoresizesOutlineColumn: NO];
    [outlineView setAllowsMultipleSelection: NO];
    [outlineView setAllowsEmptySelection: YES];
    [outlineView setAllowsColumnSelection: NO];

    col = [[NSTableColumn alloc] initWithIdentifier: @"item"];
    [col setWidth: frameRect.size.width - 4];
    [col setEditable: NO];
    [outlineView addTableColumn: col];
    [outlineView setOutlineTableColumn: col];
    RELEASE (col);

    [outlineView setDataSource: self];
    [outlineView setDelegate: self];
    [outlineView setTarget: self];
    [outlineView setAction: @selector(itemClicked:)];

    [scrollView setDocumentView: outlineView];
    RELEASE (outlineView);

    [self addSubview: scrollView];

    /* Expand all top-level groups */
    {
      NSUInteger i;
      for (i = 0; i < [rootItems count]; i++) {
        [outlineView expandItem: [rootItems objectAtIndex: i]];
      }
    }
  }

  return self;
}

- (void)buildModel
{
  GWSidebarItem *userDomain;
  GWSidebarItem *domain;
  NSString *home;
  NSFileManager *fm;
  NSArray *favs;
  NSUInteger i;

  fm = [NSFileManager defaultManager];
  home = NSHomeDirectory();

  userDomain = [[GWSidebarItem alloc] initHeaderWithTitle:
                  NSLocalizedString(@"User Domain", @"")];

  /* Applications: per-user ~/Applications under the User Domain group. */
  {
    NSString *appsPath = [home stringByAppendingPathComponent: @"Applications"];
    GWSidebarItem *it = [[GWSidebarItem alloc]
        initPathItemWithTitle: NSLocalizedString(@"Applications", @"")
                         path: appsPath];
    [userDomain addChild: it];
    RELEASE (it);
  }

  favs = [NSArray arrayWithObjects:
            [NSArray arrayWithObjects: NSLocalizedString(@"Documents", @""), @"Documents", nil],
            [NSArray arrayWithObjects: NSLocalizedString(@"Downloads", @""), @"Downloads", nil],
            [NSArray arrayWithObjects: NSLocalizedString(@"Music", @""), @"Music", nil],
            [NSArray arrayWithObjects: NSLocalizedString(@"Pictures", @""), @"Pictures", nil],
            [NSArray arrayWithObjects: NSLocalizedString(@"Videos", @""), @"Videos", nil],
            nil];

  for (i = 0; i < [favs count]; i++) {
    NSArray *pair = [favs objectAtIndex: i];
    NSString *title = [pair objectAtIndex: 0];
    NSString *folder = [pair objectAtIndex: 1];
    NSString *full = [home stringByAppendingPathComponent: folder];

    /* For Videos, also try Movies (Mac convention) if Videos doesn't exist */
    if ([folder isEqualToString: @"Videos"]
        && [fm fileExistsAtPath: full] == NO) {
      NSString *movies = [home stringByAppendingPathComponent: @"Movies"];
      if ([fm fileExistsAtPath: movies]) {
        full = movies;
      }
    }

    GWSidebarItem *it = [[GWSidebarItem alloc]
        initPathItemWithTitle: title path: full];
    [userDomain addChild: it];
    RELEASE (it);
  }

  [rootItems addObject: userDomain];
  RELEASE (userDomain);

  domain = [[GWSidebarItem alloc] initHeaderWithTitle:
              NSLocalizedString(@"Domains", @"")];

  {
    GWSidebarItem *local = [[GWSidebarItem alloc]
        initPathItemWithTitle: @"/Local" path: @"/Local"];
    [domain addChild: local];
    RELEASE (local);

    /* /Network keeps its virtual NetworkFSNode behavior so that
       mDNS service discovery still works when the user clicks it. */
    GWSidebarItem *net = [[GWSidebarItem alloc]
        initNetworkItemWithTitle: @"/Network"];
    [domain addChild: net];
    RELEASE (net);

    GWSidebarItem *system = [[GWSidebarItem alloc]
        initPathItemWithTitle: @"/System" path: @"/System"];
    [domain addChild: system];
    RELEASE (system);
  }

  [rootItems addObject: domain];
  RELEASE (domain);
}

- (void)reloadData
{
  [outlineView reloadData];
}

- (void)itemClicked:(id)sender
{
  NSInteger row = [outlineView clickedRow];
  if (row < 0) {
    row = [outlineView selectedRow];
  }
  if (row < 0) {
    return;
  }

  id item = [outlineView itemAtRow: row];
  if (item == nil || [item isHeader]) {
    return;
  }

  [self openItem: item];
}

- (void)openItem:(GWSidebarItem *)item
{
  FSNode *target = nil;

  if ([item kind] == GWSidebarItemNetwork) {
    target = [NetworkFSNode networkRootNode];
  } else if ([item kind] == GWSidebarItemPath) {
    NSString *p = [item path];
    if (p == nil || [p length] == 0) {
      return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath: p isDirectory: &isDir] == NO || isDir == NO) {
      NSBeep ();
      return;
    }

    target = [FSNode nodeWithPath: p];
    if (target == nil || [target isValid] == NO) {
      return;
    }
  }

  if (target == nil) {
    return;
  }

  /* Navigate the current viewer in place rather than opening a new
     window. */
  if (viewer && [viewer respondsToSelector: @selector(openNodeInPlace:)]) {
    [(id)viewer openNodeInPlace: target];
    return;
  }

  /* Fallback: hand off to the viewers manager */
  GWViewersManager *manager = [GWViewersManager viewersManager];
  [manager viewerForNode: target
                showType: GWViewTypeBrowser
           showSelection: NO
                forceNew: NO
                 withKey: nil];
}

/* ---------------- NSOutlineView data source ---------------- */

- (NSInteger)outlineView:(NSOutlineView *)ov
  numberOfChildrenOfItem:(id)item
{
  if (item == nil) {
    return [rootItems count];
  }
  return [[item children] count];
}

- (BOOL)outlineView:(NSOutlineView *)ov
   isItemExpandable:(id)item
{
  if (item == nil) {
    return YES;
  }
  return [item isHeader];
}

- (id)outlineView:(NSOutlineView *)ov
            child:(NSInteger)index
           ofItem:(id)item
{
  if (item == nil) {
    return [rootItems objectAtIndex: index];
  }
  return [[item children] objectAtIndex: index];
}

- (id)outlineView:(NSOutlineView *)ov
objectValueForTableColumn:(NSTableColumn *)tableColumn
           byItem:(id)item
{
  if (item == nil) {
    return @"";
  }
  return [item title];
}

/* ---------------- NSOutlineView delegate ---------------- */

- (BOOL)outlineView:(NSOutlineView *)ov
        shouldSelectItem:(id)item
{
  if (item == nil) {
    return NO;
  }
  return ([item isHeader] == NO);
}

- (BOOL)outlineView:(NSOutlineView *)ov
shouldCollapseItem:(id)item
{
  /* Keep top-level groups expanded */
  return NO;
}

- (NSCell *)outlineView:(NSOutlineView *)ov
 dataCellForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item
{
  if (item != nil && [item isHeader]) {
    NSTextFieldCell *cell = [[[NSTextFieldCell alloc] init] autorelease];
    [cell setFont: [NSFont boldSystemFontOfSize: 11]];
    [cell setTextColor: [NSColor controlShadowColor]];
    [cell setEditable: NO];
    [cell setSelectable: NO];
    return cell;
  }

  NSBrowserCell *cell = [[[NSBrowserCell alloc] init] autorelease];
  [cell setLeaf: YES];
  [cell setEditable: NO];
  [cell setFont: [NSFont systemFontOfSize: 11]];
  return cell;
}

- (void)outlineView:(NSOutlineView *)ov
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item
{
  if (item == nil) {
    return;
  }

  if ([item isHeader]) {
    if ([cell respondsToSelector: @selector(setStringValue:)]) {
      [cell setStringValue: [[item title] uppercaseString]];
    }
    return;
  }

  if ([cell respondsToSelector: @selector(setStringValue:)]) {
    [cell setStringValue: [item title]];
  }
  if ([cell respondsToSelector: @selector(setImage:)]) {
    [cell setImage: [item icon]];
  }
}

- (CGFloat)outlineView:(NSOutlineView *)ov
   heightOfRowByItem:(id)item
{
  if (item != nil && [item isHeader]) {
    return HEADER_HEIGHT;
  }
  return ROW_HEIGHT;
}

@end
