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
#import <sys/stat.h>
#import <sys/types.h>
#import "GWViewerSidebar.h"
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "NetworkFSNode.h"
#import "NetworkServiceManager.h"
#import "NetworkServiceItem.h"
#import "NetworkVolumeManager.h"
#import "Workspace.h"

#define ROW_HEIGHT 20.0
#define HEADER_HEIGHT 20.0
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

static BOOL GWSidebarPathIsUnderVolumeRoot(NSString *path)
{
  if (path == nil) return NO;
  NSArray *roots = [Workspace volumeMountRoots];
  for (NSString *root in roots) {
    NSString *prefix = [root stringByAppendingString: @"/"];
    if ([path hasPrefix: prefix] && [path length] > [prefix length]) {
      return YES;
    }
  }
  return NO;
}

/* Outline view that forces a Snow-Leopard-style sidebar background.
   NSOutlineView/NSTableView's setBackgroundColor: isn't reliably honored
   in this GNUstep build, so we override the background paint directly. */
@interface GWSidebarOutlineView : NSOutlineView
{
  NSInteger dragHighlightRow;
}
- (NSRect)ejectRectForRow:(NSInteger)row;
- (void)drawEjectGlyphInRect:(NSRect)r;
@end

@implementation GWSidebarOutlineView

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame: frameRect];
  if (self) {
    dragHighlightRow = -1;
  }
  return self;
}

- (void)drawBackgroundInClipRect:(NSRect)clipRect
{
  [[NSColor windowBackgroundColor] set];
  NSRectFill(clipRect);
}

- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row
{
  NSRect frame = [super frameOfOutlineCellAtRow: row];
  if (NSIsEmptyRect(frame) == NO) {
    // Shift the disclosure triangle down by 2px so it centers better
    // relative to the NSBrowserCell text positioning.
    frame.origin.y += 2.0;
  }
  return frame;
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

  /* Draw drag highlight for the row being hovered */
  if (dragHighlightRow >= 0) {
    NSRange visibleRows = [self rowsInRect: rect];
    if ((NSUInteger)dragHighlightRow >= visibleRows.location
        && (NSUInteger)dragHighlightRow < visibleRows.location + visibleRows.length) {
      NSRect rowRect = [self rectOfRow: dragHighlightRow];
      [[NSColor selectedControlColor] set];
      NSRectFill(rowRect);
      /* Re-draw the cell content on top so text/icons aren't obscured */
      [self drawRow: dragHighlightRow clipRect: rowRect];
    }
  }

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

/* Forward category so the dragging destination methods below can call
   GWSidebarItem methods without compiler warnings. */
@interface NSObject (GWSidebarItemMethods)
- (BOOL)isHeader;
- (GWSidebarItemKind)itemKind;
- (NSString *)path;
- (NSString *)title;
- (NSImage *)icon;
- (BOOL)isVolume;
- (BOOL)isMountedNetworkService;
- (NSArray *)children;
- (id)userInfo;
- (void)setUserInfo:(id)obj;
@end


@implementation GWSidebarOutlineView (DraggingDestination)

- (void)setDragHighlightRow:(NSInteger)row
{
  if (dragHighlightRow != row) {
    NSInteger oldRow = dragHighlightRow;
    dragHighlightRow = row;
    if (oldRow >= 0) {
      [self setNeedsDisplayInRect: [self rectOfRow: oldRow]];
    }
    if (row >= 0) {
      [self setNeedsDisplayInRect: [self rectOfRow: row]];
    }
  }
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSInteger row = [self rowAtPoint: [self convertPoint: [sender draggingLocation]
                                               fromView: nil]];
  if (row < 0) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  id item = [self itemAtRow: row];
  if (item == nil || [item isHeader]) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  NSString *targetPath = nil;
  if ([item itemKind] == GWSidebarItemNetwork) {
    /* Resolve network service to its mount point */
    id svc = [item userInfo];
    if (svc && [svc isKindOfClass: [NetworkServiceItem class]]) {
      targetPath = [[NetworkVolumeManager sharedManager] mountPointForService: svc];
    }
    if (targetPath == nil) {
      [self setDragHighlightRow: -1];
      return NSDragOperationNone;
    }
  } else {
    targetPath = [item path];
  }

  if (targetPath == nil || [targetPath length] == 0) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  FSNode *targetNode = [FSNode nodeWithPath: targetPath];
  if (targetNode == nil || [targetNode isValid] == NO
      || [targetNode isDirectory] == NO || [targetNode isPackage]) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  Workspace *gw = [Workspace gworkspace];
  if ([targetNode isSubnodeOfPath: [gw trashPath]]) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  NSPasteboard *pb = [sender draggingPasteboard];
  NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
  NSArray *sourcePaths = nil;

  if ([[pb types] containsObject: NSFilenamesPboardType]) {
    sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
  } else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"]) {
    if ([targetNode isWritable] == NO) {
      [self setDragHighlightRow: -1];
      return NSDragOperationNone;
    }
    [self setDragHighlightRow: row];
    return NSDragOperationCopy;
  } else if ([[pb types] containsObject: @"GWLSFolderPboardType"]) {
    if ([targetNode isWritable] == NO) {
      [self setDragHighlightRow: -1];
      return NSDragOperationNone;
    }
    [self setDragHighlightRow: row];
    return NSDragOperationCopy;
  }

  if (sourcePaths == nil || [sourcePaths count] == 0) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  NSString *fromPath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  if ([targetPath isEqual: fromPath]) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }
  if ([sourcePaths containsObject: targetPath]) {
    [self setDragHighlightRow: -1];
    return NSDragOperationNone;
  }

  /* Check that target is not a subdirectory of a source path */
  NSString *prePath = targetPath;
  while (1) {
    if ([sourcePaths containsObject: prePath]) {
      [self setDragHighlightRow: -1];
      return NSDragOperationNone;
    }
    if ([prePath isEqual: @"/"]) {
      break;
    }
    prePath = [prePath stringByDeletingLastPathComponent];
  }

  NSDragOperation result = NSDragOperationNone;
  if (sourceDragMask & NSDragOperationMove) {
    if ([[NSFileManager defaultManager] isWritableFileAtPath: fromPath]) {
      result = NSDragOperationMove;
    } else {
      result = NSDragOperationCopy;
    }
  } else if (sourceDragMask & NSDragOperationCopy) {
    result = NSDragOperationCopy;
  } else if (sourceDragMask & NSDragOperationLink) {
    result = NSDragOperationLink;
  }

  if (result != NSDragOperationNone) {
    [self setDragHighlightRow: row];
  } else {
    [self setDragHighlightRow: -1];
  }
  return result;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSDragOperation op = [self draggingEntered: sender];
  if (op != NSDragOperationNone) {
    NSInteger row = [self rowAtPoint: [self convertPoint: [sender draggingLocation]
                                                 fromView: nil]];
    [self setDragHighlightRow: row];
  } else {
    [self setDragHighlightRow: -1];
  }
  return op;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  [self setDragHighlightRow: -1];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  [self setDragHighlightRow: -1];

  NSInteger row = [self rowAtPoint: [self convertPoint: [sender draggingLocation]
                                               fromView: nil]];
  if (row < 0) {
    return;
  }

  id item = [self itemAtRow: row];
  if (item == nil || [item isHeader]) {
    return;
  }

  NSString *targetPath = nil;
  if ([item itemKind] == GWSidebarItemNetwork) {
    id svc = [item userInfo];
    if (svc && [svc isKindOfClass: [NetworkServiceItem class]]) {
      targetPath = [[NetworkVolumeManager sharedManager] mountPointForService: svc];
    }
    if (targetPath == nil) {
      return;
    }
  } else {
    targetPath = [item path];
  }

  if (targetPath == nil || [targetPath length] == 0) {
    return;
  }

  FSNode *targetNode = [FSNode nodeWithPath: targetPath];
  if (targetNode == nil || [targetNode isValid] == NO
      || [targetNode isDirectory] == NO) {
    return;
  }

  NSPasteboard *pb = [sender draggingPasteboard];
  NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];

  if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"]) {
    NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
    [[Workspace gworkspace] concludeRemoteFilesDragOperation: pbData
                                                 atLocalPath: targetPath];
    return;
  }

  if ([[pb types] containsObject: @"GWLSFolderPboardType"]) {
    NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
    [[Workspace gworkspace] lsfolderDragOperation: pbData
                                  concludedAtPath: targetPath];
    return;
  }

  NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
  if (sourcePaths == nil || [sourcePaths count] == 0) {
    return;
  }

  NSString *source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
  NSString *operation = nil;
  Workspace *gw = [Workspace gworkspace];
  NSString *trashPath = [gw trashPath];

  if ([source isEqual: trashPath]) {
    operation = @"WorkspaceRecycleOutOperation";
  } else {
    if (sourceDragMask & NSDragOperationMove) {
      if ([[NSFileManager defaultManager] isWritableFileAtPath: source]) {
        operation = NSWorkspaceMoveOperation;
      } else {
        operation = NSWorkspaceCopyOperation;
      }
    } else if (sourceDragMask & NSDragOperationCopy) {
      operation = NSWorkspaceCopyOperation;
    } else if (sourceDragMask & NSDragOperationLink) {
      operation = NSWorkspaceLinkOperation;
    }
  }

  if (operation == nil) {
    return;
  }

  NSMutableArray *files = [NSMutableArray arrayWithCapacity: [sourcePaths count]];
  NSUInteger i;
  for (i = 0; i < [sourcePaths count]; i++) {
    [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
  }

  NSMutableDictionary *opDict = [NSMutableDictionary dictionaryWithCapacity: 4];
  [opDict setObject: operation forKey: @"operation"];
  [opDict setObject: source forKey: @"source"];
  [opDict setObject: targetPath forKey: @"destination"];
  [opDict setObject: files forKey: @"files"];

  [gw performFileOperation: opDict];
}

@end


@interface GWSidebarItem : NSObject
{
  NSString *title;
  NSString *path;
  NSImage *icon;
  GWSidebarItemKind kind;
  NSMutableArray *children;
  id userInfo;
}
- (id)initHeaderWithTitle:(NSString *)aTitle;
- (id)initPathItemWithTitle:(NSString *)aTitle path:(NSString *)aPath;
- (id)initNetworkItemWithTitle:(NSString *)aTitle;
- (void)addChild:(GWSidebarItem *)child;
- (NSString *)title;
- (NSString *)path;
- (NSImage *)icon;
- (GWSidebarItemKind)itemKind;
- (NSArray *)children;
- (BOOL)isHeader;
- (id)userInfo;
- (void)setUserInfo:(id)obj;
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
  RELEASE (userInfo);
  [super dealloc];
}

- (id)userInfo
{
  return userInfo;
}

- (void)setUserInfo:(id)obj
{
  ASSIGN (userInfo, obj);
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
- (GWSidebarItemKind)itemKind { return kind; }
- (NSArray *)children { return children; }
- (BOOL)isHeader { return kind == GWSidebarItemHeader; }
- (BOOL)isVolume
{
  return (kind == GWSidebarItemPath)
      && GWSidebarPathIsUnderVolumeRoot(path);
}

- (BOOL)isMountedNetworkService
{
  if (kind != GWSidebarItemNetwork) return NO;
  if (userInfo == nil || ![userInfo isKindOfClass: [NetworkServiceItem class]]) return NO;

  /* First check what NetworkVolumeManager says (its internal dictionary). */
  NetworkVolumeManager *nvm = [NetworkVolumeManager sharedManager];
  NSString *mountPoint = nil;

  if ([nvm isServiceMounted: userInfo]) {
    mountPoint = [nvm mountPointForService: userInfo];
  }

  /* If NetworkVolumeManager doesn't know about this mount, check /proc/mounts
     directly — the volume may have been mounted externally (e.g. via sshfs
     command or the umount(1) CLI tool's mount remount).  We look for a line
     containing the service's hostname in the mount table. */
  if (mountPoint == nil) {
    NSString *hostname = [userInfo hostName];
    if (hostname) {
      NSString *procContent = [NSString stringWithContentsOfFile: @"/proc/mounts"
                                                        encoding: NSUTF8StringEncoding
                                                           error: NULL];
      if (procContent) {
        if ([procContent rangeOfString: hostname].location != NSNotFound) {
          /* The service's hostname appears in a mount — try to extract path */
          NSArray *lines = [procContent componentsSeparatedByString: @"\n"];
          for (NSString *line in lines) {
            if ([line rangeOfString: hostname].location != NSNotFound) {
              NSArray *parts = [line componentsSeparatedByString: @" "];
              if ([parts count] >= 2) {
                mountPoint = [parts objectAtIndex: 1];
                break;
              }
            }
          }
        }
      }
    }
  }

  if (mountPoint == nil) return NO;

  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if (![fm fileExistsAtPath: mountPoint isDirectory: &isDir]) return NO;
  if (!isDir) return NO;

  return YES;
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
        /* Copy the icon so we don't mutate the shared FSNodeRep cache,
         * which would affect desktop icons and other views. */
        ASSIGN (icon, [[ic copy] autorelease]);
        return icon;
      }
    }
    /* Fallback to a generic folder icon */
    NSImage *fallback = [NSImage imageNamed: @"Folder"];
    if (fallback) {
      NSImage *copy = [[fallback copy] autorelease];
      [copy setScalesWhenResized: YES];
      [copy setSize: NSMakeSize(ICON_SIZE, ICON_SIZE)];
      ASSIGN (icon, copy);
    }
    return icon;
  }

  if (kind == GWSidebarItemNetwork) {
    NSImage *ic = [NSImage imageNamed: @"Network"];
    if (ic == nil) {
      ic = [NSImage imageNamed: @"Computer"];
    }
    if (ic) {
      NSImage *copy = [[ic copy] autorelease];
      [copy setScalesWhenResized: YES];
      [copy setSize: NSMakeSize(ICON_SIZE, ICON_SIZE)];
      ASSIGN (icon, copy);
    }
    return icon;
  }

  return nil;
}

@end


@implementation GWViewerSidebar

- (void)dealloc
{
  /* Volume mount roots are watched by GWDesktopManager's MPointWatcher
     for the desktop's lifetime; the sidebar just listens to the
     broadcast GWFileWatcherFileDidChangeNotification, so there is
     nothing to unregister with fswatcher here. */
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
    [outlineView setUsesAlternatingRowBackgroundColors: YES];

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
    [outlineView registerForDraggedTypes:
        [NSArray arrayWithObjects:
            NSFilenamesPboardType,
            @"GWLSFolderPboardType",
            @"GWRemoteFilenamesPboardType",
            nil]];

    [scrollView setDocumentView: outlineView];
    RELEASE (outlineView);

    [self addSubview: scrollView];

    [self expandGroupsRespectingCollapsedSet];

    [self applySidebarWidthIfNeeded];

    /* Volume mount roots are already watched by GWDesktopManager's
       MPointWatcher; just subscribe to the broadcast notification so
       the Volumes section refreshes on real mount/unmount events. */
    {
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(volumesWatcherNotification:)
                 name: @"GWFileWatcherFileDidChangeNotification"
               object: nil];
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(rebuildVolumesSection)
                 name: @"GWFileSystemDidChangeNotification"
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
      [[NSNotificationCenter defaultCenter]
          addObserver: self
             selector: @selector(networkServicesDidChange:)
                 name: NetworkServicesDidChangeNotification
               object: nil];
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
    BOOL isDir = NO;
    if ([fm fileExistsAtPath: appsPath isDirectory: &isDir] && isDir) {
      GWSidebarItem *it = [[GWSidebarItem alloc]
          initPathItemWithTitle: NSLocalizedString(@"Applications", @"")
                           path: appsPath];
      [userDomain addChild: it];
      RELEASE (it);
    }
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

    BOOL isDir = NO;
    if ([fm fileExistsAtPath: full isDirectory: &isDir] && isDir) {
      GWSidebarItem *it = [[GWSidebarItem alloc]
          initPathItemWithTitle: title path: full];
      [userDomain addChild: it];
      RELEASE (it);
    }
  }

  [rootItems addObject: userDomain];
  RELEASE (userDomain);

  domain = [[GWSidebarItem alloc] initHeaderWithTitle:
              NSLocalizedString(@"Domains", @"")];

  {
    BOOL isDir = NO;

    if ([fm fileExistsAtPath: @"/Local" isDirectory: &isDir] && isDir) {
      GWSidebarItem *local = [[GWSidebarItem alloc]
          initPathItemWithTitle: NSLocalizedString(@"Local", @"")
                           path: @"/Local"];
      [domain addChild: local];
      RELEASE (local);
    }

    if ([fm fileExistsAtPath: @"/Network" isDirectory: &isDir] && isDir) {
      GWSidebarItem *net = [[GWSidebarItem alloc]
          initPathItemWithTitle: NSLocalizedString(@"Network", @"")
                           path: @"/Network"];
      [domain addChild: net];
      RELEASE (net);
    }

    if ([fm fileExistsAtPath: @"/System" isDirectory: &isDir] && isDir) {
      GWSidebarItem *system = [[GWSidebarItem alloc]
          initPathItemWithTitle: NSLocalizedString(@"System", @"")
                           path: @"/System"];
      [domain addChild: system];
      RELEASE (system);
    }
  }

  /* Only add the Domains section if at least one domain directory exists */
  if ([[domain children] count] > 0) {
    [rootItems addObject: domain];
  }
  RELEASE (domain);

  volumesGroup = [[GWSidebarItem alloc] initHeaderWithTitle:
                    NSLocalizedString(@"Volumes", @"")];
  {
    NetworkVolumeManager *nvm = [NetworkVolumeManager sharedManager];
    NSSet *networkMountPaths = [nvm allMountedPaths];
    NSArray *roots = [Workspace volumeMountRoots];
    NSMutableSet *seen = [NSMutableSet set];
    NSMutableArray *vols = [NSMutableArray array];

    for (NSString *root in roots) {
      struct stat parentSt;
      const char *rootC = [root fileSystemRepresentation];
      if (lstat(rootC, &parentSt) != 0) continue;
      if (!S_ISDIR(parentSt.st_mode)) continue;

      NSArray *entries = [fm contentsOfDirectoryAtPath: root error: NULL];
      for (NSString *name in entries) {
        if ([name hasPrefix: @"."]) continue;

        NSString *full = [root stringByAppendingPathComponent: name];
        if ([seen containsObject: full]) continue;

        /* Skip paths that are network volume mount points (shown under Network) */
        if ([networkMountPaths containsObject: full]) continue;

        struct stat childSt;
        if (lstat([full fileSystemRepresentation], &childSt) != 0) continue;
        if (!S_ISDIR(childSt.st_mode)) continue;
        /* Same device as parent = directory exists but nothing is
           mounted there; skip so we don't list stale stub dirs. */
        if (childSt.st_dev == parentSt.st_dev) continue;

        [seen addObject: full];
        [vols addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                          name, @"name", full, @"path", nil]];
      }
    }

    [vols sortUsingDescriptors:
        [NSArray arrayWithObject:
            [[[NSSortDescriptor alloc] initWithKey: @"name"
                                          ascending: YES
                                          selector: @selector(caseInsensitiveCompare:)]
                autorelease]]];

    for (NSDictionary *vol in vols) {
      GWSidebarItem *it = [[GWSidebarItem alloc]
          initPathItemWithTitle: [vol objectForKey: @"name"]
                           path: [vol objectForKey: @"path"]];
      [volumesGroup addChild: it];
      RELEASE (it);
    }
  }
  [rootItems addObject: volumesGroup];
  RELEASE (volumesGroup);

  /* Network section: discovered services from mDNS */
  {
    GWSidebarItem *networkGroup = [[GWSidebarItem alloc]
        initHeaderWithTitle: NSLocalizedString(@"Network", @"")];

    /* Collect all services: from discovery + mounted volumes without discovery.
       Wrap in @try/@catch to guard against crashes when NSNetServiceBrowser
       class exists but the mDNS daemon (Avahi/mDNSResponder) is not running.
       See: https://github.com/gershwin-desktop/gershwin-workspace/issues/93 */
    @try {
      NetworkServiceManager *mgr = [NetworkServiceManager sharedManager];
      NSMutableArray *allServices = [NSMutableArray array];
      NSMutableSet *seenIdentifiers = [NSMutableSet set];

      if ([mgr isMDNSAvailable]) {
        /* Auto-start mDNS browsing so network services always appear
           in the sidebar without the user having to go to Go To → Network.
           Defer the actual browsing to the next run loop iteration so that
           the viewer window is fully constructed first — this avoids the
           sidebar init blocking on mDNS discovery and ensures that a crash
           in the underlying DNS-SD library does not prevent the viewer
           from appearing at all. */
        if (![mgr isBrowsing]) {
          [mgr performSelector:@selector(startBrowsing)
                    withObject:nil
                    afterDelay:0];
        }
        NSArray *discovered = [mgr allServices];
        for (NetworkServiceItem *svc in discovered) {
          NSString *ident = [svc identifier];
          if (![seenIdentifiers containsObject: ident]) {
            [seenIdentifiers addObject: ident];
            [allServices addObject: svc];
          }
        }
      }

      /* Deduplicate display names */
      NSMutableDictionary *nameCounts = [NSMutableDictionary dictionaryWithCapacity:[allServices count]];
      for (NetworkServiceItem *svc in allServices) {
        NSString *baseName = [svc name];
        NSNumber *count = [nameCounts objectForKey: baseName];
        NSString *uniqueName = nil;
        if (!count) {
          [nameCounts setObject: @1 forKey: baseName];
          uniqueName = baseName;
        } else {
          NSUInteger newCount = [count unsignedIntegerValue] + 1;
          [nameCounts setObject: [NSNumber numberWithUnsignedInteger: newCount]
                         forKey: baseName];
          uniqueName = [NSString stringWithFormat: @"%@-%lu",
                                 baseName, (unsigned long)newCount];
        }

        GWSidebarItem *it = [[GWSidebarItem alloc]
            initNetworkItemWithTitle: uniqueName];
        [it setUserInfo: svc];
        [networkGroup addChild: it];
        RELEASE (it);
      }
    } @catch (NSException *exception) {
      NSWarnMLog(@"GWViewerSidebar: Failed to build network section: %@", exception);
    }
    [rootItems addObject: networkGroup];
    RELEASE (networkGroup);
  }
}

- (void)reloadData
{
  [outlineView reloadData];
}

- (void)volumesWatcherNotification:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  NSString *path = [info objectForKey: @"path"];
  if (path == nil) return;

  /* Rebuild the Volumes section whenever something changes inside
     any mount root directory (e.g. /media, /Volumes).  The file
     watcher reports the exact path that changed (e.g.
     /media/devuan/Asterisk), which is a *child* of the mount root,
     not the root itself.  We therefore check if the changed path
     has any mount root as a prefix. */
  NSArray *roots = [Workspace volumeMountRoots];
  for (NSString *root in roots) {
    NSString *rootSlash = [root stringByAppendingString: @"/"];
    if ([path isEqualToString: root] || [path hasPrefix: rootSlash]) {
      [self rebuildModelPreservingExpansion];
      return;
    }
  }
}

- (void)networkServicesDidChange:(NSNotification *)notif
{
  [self rebuildModelPreservingExpansion];
}

- (void)rebuildVolumesSection
{
  [self rebuildModelPreservingExpansion];
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
  if (item == nil) {
    return nil;
  }

  NSString *ejectPath = nil;

  if ([item respondsToSelector: @selector(isVolume)] && [item isVolume]) {
    ejectPath = [item path];
  } else if ([item respondsToSelector: @selector(isMountedNetworkService)]
             && [item isMountedNetworkService]) {
    id svc = [item userInfo];
    if (svc && [svc isKindOfClass: [NetworkServiceItem class]]) {
      ejectPath = [[NetworkVolumeManager sharedManager] mountPointForService: svc];
    }
  }

  if (ejectPath == nil) {
    return nil;
  }

  NSMenu *menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
  NSMenuItem *eject = [[[NSMenuItem alloc]
      initWithTitle: NSLocalizedString(@"Eject", @"")
             action: @selector(ejectVolumeMenuAction:)
      keyEquivalent: @""] autorelease];
  [eject setTarget: self];
  [eject setRepresentedObject: ejectPath];
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
  BOOL v = (item
            && [item respondsToSelector: @selector(isVolume)]
            && [item isVolume]);
  if (!v) {
    v = (item
         && [item respondsToSelector: @selector(isMountedNetworkService)]
         && [item isMountedNetworkService]);
  }
  return [NSNumber numberWithBool: v];
}

- (void)ejectVolumeAtRow:(NSNumber *)rowNum
{
  NSInteger row = [rowNum integerValue];
  if (row < 0) return;
  id item = [outlineView itemAtRow: row];
  if (item == nil) return;

  if ([item respondsToSelector: @selector(isVolume)] && [item isVolume]) {
    [self ejectPath: [item path]];
  } else if ([item respondsToSelector: @selector(isMountedNetworkService)]
             && [item isMountedNetworkService]) {
    id svc = [item userInfo];
    if (svc && [svc isKindOfClass: [NetworkServiceItem class]]) {
      [[NetworkVolumeManager sharedManager] unmountService: svc];
    }
  }
}

- (void)ejectPath:(NSString *)path
{
  if ([path length] == 0) return;

  /* Check if this is a network mount point */
  NSSet *netPaths = [[NetworkVolumeManager sharedManager] allMountedPaths];
  if ([netPaths containsObject: path]) {
    [[NetworkVolumeManager sharedManager] unmountPath: path];
    return;
  }

  /* Regular volume (disk image, USB, etc.) */
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

  if ([item itemKind] == GWSidebarItemNetwork) {
    id svc = [item userInfo];
    if (svc && [svc isKindOfClass: [NetworkServiceItem class]]) {
      NetworkFSNode *netNode = [NetworkFSNode nodeWithServiceItem: svc];
      NSString *mountPoint = [netNode openNetworkService];
      if (mountPoint) {
        target = [FSNode nodeWithPath: mountPoint];
        if (target == nil || [target isValid] == NO) {
          return;
        }
        /* Mount succeeded — navigate in-place.  Defer slightly so any
           mount-side notifications (GWFileSystemDidChangeNotification
           etc.) settle before the view is rebuilt, preventing the
           viewer window from closing. */
        if (viewer && [viewer respondsToSelector: @selector(openNodeInPlace:)]) {
          [self performSelector: @selector(performOpenNodeInPlace:)
                     withObject: target
                     afterDelay: 0.05];
        }
        return;
      } else {
        NSBeep ();
        return;
      }
    } else {
      target = [NetworkFSNode networkRootNode];
    }
  } else if ([item itemKind] == GWSidebarItemPath) {
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

/**
 * Deferred in-place navigation, called via performSelector:afterDelay:
 * so mount notifications settle before the view is rebuilt.
 * Checks that the viewer is still valid — mount-side handlers may have
 * invalidated it in the meantime.
 */
- (void)performOpenNodeInPlace:(FSNode *)target
{
  if (viewer == nil) return;
  if ([viewer respondsToSelector: @selector(invalidated)]
      && [viewer invalidated]) return;
  if ([viewer respondsToSelector: @selector(openNodeInPlace:)]) {
    [(id)viewer openNodeInPlace: target];
  }
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
  NSBrowserCell *cell = [[[NSBrowserCell alloc] init] autorelease];
  [cell setLeaf: YES];
  [cell setEditable: NO];

  if (item != nil && [item isHeader]) {
    [cell setFont: [NSFont boldSystemFontOfSize: 11]];
  } else {
    [cell setFont: [NSFont systemFontOfSize: 11]];
  }
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
    if ([cell respondsToSelector: @selector(setTextColor:)]) {
      [cell setTextColor: [NSColor controlShadowColor]];
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
