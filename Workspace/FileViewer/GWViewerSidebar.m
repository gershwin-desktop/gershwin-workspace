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
#import "Workspace.h"

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

#define EJECT_ICON_SIZE 12.0
#define EJECT_ICON_RIGHT_PADDING 6.0
#define EJECT_ICON_LEFT_PADDING 10.0

/* Outline view that forces a Snow-Leopard-style sidebar background.
   NSOutlineView/NSTableView's setBackgroundColor: isn't reliably honored
   in this GNUstep build, so we override the background paint directly. */
@interface GWSidebarOutlineView : NSOutlineView
- (NSRect)ejectRectForRow:(NSInteger)row;
- (void)drawEjectGlyphInRect:(NSRect)r;
@end

@implementation GWSidebarOutlineView
- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
  [[NSColor windowBackgroundColor] set];
  NSRectFill(clipRect);
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  NSPoint p = [self convertPoint: [theEvent locationInWindow] fromView: nil];
  NSInteger row = [self rowAtPoint: p];
  if (row < 0) return nil;
  id item = [self itemAtRow: row];
  id ds = [self dataSource];
  if ([ds respondsToSelector: @selector(menuForSidebarItem:)]) {
    return [ds performSelector: @selector(menuForSidebarItem:) withObject: item];
  }
  return nil;
}

- (NSRect)ejectRectForRow:(NSInteger)row
{
  NSRect rowRect = [self rectOfRow: row];
  CGFloat x = NSMaxX(rowRect) - EJECT_ICON_RIGHT_PADDING - EJECT_ICON_SIZE;
  CGFloat y = NSMidY(rowRect) - (EJECT_ICON_SIZE / 2.0);
  return NSMakeRect(x, y, EJECT_ICON_SIZE, EJECT_ICON_SIZE);
}

- (void)drawEjectGlyphInRect:(NSRect)r
{
  CGFloat triH = r.size.height * 0.55;
  CGFloat barH = 1.5;
  CGFloat gap = 1.5;
  CGFloat triBaseY = NSMinY(r) + barH + gap;
  CGFloat triTipY = triBaseY + triH;
  CGFloat midX = NSMidX(r);
  CGFloat triHalfW = r.size.width / 2.0;

  [[NSColor darkGrayColor] set];

  NSBezierPath *tri = [NSBezierPath bezierPath];
  [tri moveToPoint: NSMakePoint(midX - triHalfW, triBaseY)];
  [tri lineToPoint: NSMakePoint(midX + triHalfW, triBaseY)];
  [tri lineToPoint: NSMakePoint(midX, triTipY)];
  [tri closePath];
  [tri fill];

  NSRect bar = NSMakeRect(NSMinX(r), NSMinY(r), r.size.width, barH);
  NSRectFill(bar);
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect: rect];

  id ds = [self dataSource];
  if (![ds respondsToSelector: @selector(itemAtRowIsVolume:)]) return;

  NSRange visible = [self rowsInRect: rect];
  NSUInteger end = visible.location + visible.length;
  NSUInteger i;
  for (i = visible.location; i < end; i++) {
    NSNumber *isVol = [ds performSelector: @selector(itemAtRowIsVolume:)
                              withObject: [NSNumber numberWithInteger: (NSInteger)i]];
    if ([isVol boolValue]) {
      [self drawEjectGlyphInRect: [self ejectRectForRow: (NSInteger)i]];
    }
  }
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSInteger row = [self rowAtPoint: p];
  id ds = [self dataSource];

  if (row >= 0
      && [ds respondsToSelector: @selector(itemAtRowIsVolume:)]
      && [ds respondsToSelector: @selector(ejectVolumeAtRow:)]) {
    NSNumber *isVol = [ds performSelector: @selector(itemAtRowIsVolume:)
                              withObject: [NSNumber numberWithInteger: row]];
    if ([isVol boolValue]
        && NSPointInRect(p, [self ejectRectForRow: row])) {
      [ds performSelector: @selector(ejectVolumeAtRow:)
              withObject: [NSNumber numberWithInteger: row]];
      return;
    }
  }

  [super mouseDown: event];
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
- (BOOL)isVolume
{
  return (kind == GWSidebarItemPath)
      && path != nil
      && [path hasPrefix: @"/Volumes/"];
}

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
  Workspace *gw = [Workspace gworkspace];
  if (gw) {
    [gw removeWatcherForPath: @"/Volumes"];
  }
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  if (outlineView) {
    [outlineView setDataSource: nil];
    [outlineView setDelegate: nil];
  }
  RELEASE (rootItems);
  RELEASE (collapsedGroupTitles);
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
    collapsedGroupTitles = [[NSMutableSet alloc] init];

    [self buildModel];

    scrollView = [[NSScrollView alloc] initWithFrame: [self bounds]];
    [scrollView setHasVerticalScroller: NO];
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

    [self expandGroupsRespectingCollapsedSet];

    [self applySidebarWidthIfNeeded];

    /* Watch /Volumes via the workspace fswatcher proxy so the Volumes
       section auto-refreshes on external mounts/unmounts as well. */
    {
      Workspace *gw = [Workspace gworkspace];
      if (gw) {
        [gw addWatcherForPath: @"/Volumes"];
      }
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(volumesWatcherNotification:)
                 name: @"GWFileWatcherFileDidChangeNotification"
               object: nil];
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(groupDidExpand:)
                 name: NSOutlineViewItemDidExpandNotification
               object: outlineView];
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(groupDidCollapse:)
                 name: NSOutlineViewItemDidCollapseNotification
               object: outlineView];
    }
  }

  return self;
}

- (void)buildModel
{
  GWSidebarItem *userDomain;
  GWSidebarItem *domain;
  GWSidebarItem *volumesGroup;
  NSString *home;
  NSFileManager *fm;
  NSArray *favs;
  NSUInteger i;

  [rootItems removeAllObjects];

  fm = [NSFileManager defaultManager];
  home = NSHomeDirectory();

  {
    NSString *headerTitle;
    if ([home hasPrefix: @"/Network/"] || [home isEqualToString: @"/Network"]) {
      headerTitle = NSLocalizedString(@"Network User", @"");
    } else {
      headerTitle = NSLocalizedString(@"Local User", @"");
    }
    userDomain = [[GWSidebarItem alloc] initHeaderWithTitle: headerTitle];
  }

  {
    GWSidebarItem *it = [[GWSidebarItem alloc]
        initPathItemWithTitle: NSUserName()
                         path: home];
    [userDomain addChild: it];
    RELEASE (it);
  }

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
        initPathItemWithTitle: NSLocalizedString(@"Local", @"")
                         path: @"/Local"];
    [domain addChild: local];
    RELEASE (local);

    /* /Network keeps its virtual NetworkFSNode behavior so that
       mDNS service discovery still works when the user clicks it. */
    GWSidebarItem *net = [[GWSidebarItem alloc]
        initNetworkItemWithTitle: NSLocalizedString(@"Network", @"")];
    [domain addChild: net];
    RELEASE (net);

    GWSidebarItem *system = [[GWSidebarItem alloc]
        initPathItemWithTitle: NSLocalizedString(@"System", @"")
                         path: @"/System"];
    [domain addChild: system];
    RELEASE (system);
  }

  [rootItems addObject: domain];
  RELEASE (domain);

  volumesGroup = [[GWSidebarItem alloc] initHeaderWithTitle:
                    NSLocalizedString(@"Volumes", @"")];
  {
    NSError *err = nil;
    NSArray *entries = [fm contentsOfDirectoryAtPath: @"/Volumes" error: &err];
    NSArray *sorted = [entries sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)];
    for (i = 0; i < [sorted count]; i++) {
      NSString *name = [sorted objectAtIndex: i];
      if ([name hasPrefix: @"."]) continue;
      NSString *full = [@"/Volumes" stringByAppendingPathComponent: name];
      BOOL isDir = NO;
      if (![fm fileExistsAtPath: full isDirectory: &isDir] || !isDir) continue;

      GWSidebarItem *it = [[GWSidebarItem alloc]
          initPathItemWithTitle: name path: full];
      [volumesGroup addChild: it];
      RELEASE (it);
    }
  }
  [rootItems addObject: volumesGroup];
  RELEASE (volumesGroup);
}

- (void)reloadData
{
  [outlineView reloadData];
}

- (void)volumesWatcherNotification:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  NSString *path = [info objectForKey: @"path"];
  if ([path isEqualToString: @"/Volumes"]) {
    [self rebuildModelPreservingExpansion];
  }
}

- (void)rebuildModelPreservingExpansion
{
  [self buildModel];
  [outlineView reloadData];
  [self expandGroupsRespectingCollapsedSet];
  [self applySidebarWidthIfNeeded];
}

- (void)expandGroupsRespectingCollapsedSet
{
  NSUInteger i;
  for (i = 0; i < [rootItems count]; i++) {
    GWSidebarItem *group = [rootItems objectAtIndex: i];
    NSString *t = [group title];
    if (t && [collapsedGroupTitles containsObject: t]) {
      continue;
    }
    [outlineView expandItem: group];
  }
}

- (void)groupDidCollapse:(NSNotification *)notif
{
  id item = [[notif userInfo] objectForKey: @"NSObject"];
  if ([item respondsToSelector: @selector(isHeader)] && [item isHeader]) {
    NSString *t = [item title];
    if (t) [collapsedGroupTitles addObject: t];
  }
}

- (void)groupDidExpand:(NSNotification *)notif
{
  id item = [[notif userInfo] objectForKey: @"NSObject"];
  if ([item respondsToSelector: @selector(isHeader)] && [item isHeader]) {
    NSString *t = [item title];
    if (t) [collapsedGroupTitles removeObject: t];
  }
}

- (NSMenu *)menuForSidebarItem:(id)item
{
  if (item == nil || ![item respondsToSelector: @selector(isVolume)]) {
    return nil;
  }
  if (![item isVolume]) {
    return nil;
  }
  NSMenu *menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
  NSMenuItem *eject = [[[NSMenuItem alloc]
      initWithTitle: NSLocalizedString(@"Eject", @"")
             action: @selector(ejectVolumeMenuAction:)
      keyEquivalent: @""] autorelease];
  [eject setTarget: self];
  [eject setRepresentedObject: [item path]];
  [menu addItem: eject];
  return menu;
}

- (void)ejectVolumeMenuAction:(id)sender
{
  NSString *path = [sender representedObject];
  [self ejectPath: path];
}

- (NSNumber *)itemAtRowIsVolume:(NSNumber *)rowNum
{
  NSInteger row = [rowNum integerValue];
  if (row < 0) return [NSNumber numberWithBool: NO];
  id item = [outlineView itemAtRow: row];
  BOOL v = (item && [item respondsToSelector: @selector(isVolume)]
            && [item isVolume]);
  return [NSNumber numberWithBool: v];
}

- (void)ejectVolumeAtRow:(NSNumber *)rowNum
{
  NSInteger row = [rowNum integerValue];
  if (row < 0) return;
  id item = [outlineView itemAtRow: row];
  if (item && [item respondsToSelector: @selector(isVolume)] && [item isVolume]) {
    [self ejectPath: [item path]];
  }
}

- (void)ejectPath:(NSString *)path
{
  if ([path length] == 0) return;
  Workspace *gw = [Workspace gworkspace];
  if (gw && [gw respondsToSelector: @selector(unmountVolumeAtPath:)]) {
    [gw unmountVolumeAtPath: path];
  }
}

- (CGFloat)requiredSidebarWidth
{
  CGFloat fixedOverhead = 19.0
      + ICON_SIZE
      + 5.0
      + EJECT_ICON_LEFT_PADDING
      + EJECT_ICON_SIZE
      + EJECT_ICON_RIGHT_PADDING
      + 8.0;
  CGFloat headerOverhead = 19.0 + 8.0;

  NSFont *itemFont = [NSFont systemFontOfSize: 11];
  NSFont *headerFont = [NSFont boldSystemFontOfSize: 11];
  NSDictionary *itemAttrs = [NSDictionary dictionaryWithObject: itemFont
                                                        forKey: NSFontAttributeName];
  NSDictionary *headerAttrs = [NSDictionary dictionaryWithObject: headerFont
                                                          forKey: NSFontAttributeName];

  CGFloat maxW = 0.0;
  NSUInteger gi, ci;
  for (gi = 0; gi < [rootItems count]; gi++) {
    GWSidebarItem *group = [rootItems objectAtIndex: gi];
    NSString *headerText = [[group title] uppercaseString];
    if (headerText) {
      CGFloat w = headerOverhead
          + ceil([headerText sizeWithAttributes: headerAttrs].width);
      if (w > maxW) maxW = w;
    }
    NSArray *kids = [group children];
    for (ci = 0; ci < [kids count]; ci++) {
      GWSidebarItem *child = [kids objectAtIndex: ci];
      NSString *t = [child title];
      if (t == nil) continue;
      CGFloat w = ceil([t sizeWithAttributes: itemAttrs].width);
      w += fixedOverhead;
      if (w > maxW) maxW = w;
    }
  }

  /* Add the scrollbar/bezel slack so content isn't clipped. */
  return maxW + 12.0;
}

- (void)applySidebarWidthIfNeeded
{
  if (viewer == nil
      || ![viewer respondsToSelector: @selector(setSidebarWidth:)]
      || ![viewer respondsToSelector: @selector(defaultSidebarWidth)]) {
    return;
  }
  CGFloat defaultW = [(id)viewer defaultSidebarWidth];
  CGFloat needed = [self requiredSidebarWidth];
  CGFloat target = (needed > defaultW) ? needed : defaultW;
  [(id)viewer setSidebarWidth: target];
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
