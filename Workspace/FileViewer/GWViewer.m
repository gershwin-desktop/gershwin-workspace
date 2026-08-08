/* GWViewer.m
 *  
 * Copyright (C) 2004-2015 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola
 * Date: July 2004
 *
 * This file is part of the GNUstep Workspace application
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
#include <sys/statvfs.h>
#include <string.h>

#import <AppKit/AppKit.h>
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "GWViewerBrowser.h"
#import "GWViewerBrowserPreview.h"
#import "GWViewerIconsView.h"
#import "GWViewerListView.h"
#import "GWViewerWindow.h"
#import "GWViewerScrollView.h"
#import "GWViewerSplit.h"
#import "GWViewerShelf.h"
#import "GWViewerSidebar.h"
#import "GWViewerIconsPath.h"
#import "Workspace.h"
#import "GWFunctions.h"
#include <GNUstepGUI/GSDisplayServer.h>
#import "X11AppSupport.h"
#import "FSNBrowser.h"
#import "FSNIconsView.h"
#import "FSNodeRep.h"
#import "FSNIcon.h"
#import "FSNFunctions.h"
#import "Thumbnailer/GWThumbnailer.h"
#import "NetworkServiceManager.h"
#import "NetworkFSNode.h"
#import "DSStoreInfo.h"
#import "GWViewSettingsManager.h"
#import "GSFileMetadata.h"
#import "GWViewerPrefs.h"

#define DEFAULT_INCR 150
#define MIN_WIN_H 300

#define MIN_SIDEBAR_WIDTH 120.0
#define DEFAULT_SIDEBAR_WIDTH 160.0
#define MAX_SIDEBAR_WIDTH 400.0

/* Node view area insets (must stay in sync with createSubviews). */
#define PREVIEW_XMARGIN 0
#define PREVIEW_YMARGIN 0
#define PREVIEW_PATHSCRH 46

/* Helper function to get volume information using statvfs */
static BOOL getVolumeInfo(const char *path, unsigned long long *total, 
                          unsigned long long *free_space, 
                          unsigned long long *available_space)
{
  struct statvfs buf;
  
  if (statvfs(path, &buf) == 0) {
    if (total) {
      *total = (unsigned long long)buf.f_blocks * (unsigned long long)buf.f_frsize;
    }
    if (free_space) {
      *free_space = (unsigned long long)buf.f_bfree * (unsigned long long)buf.f_frsize;
    }
    if (available_space) {
      *available_space = (unsigned long long)buf.f_bavail * (unsigned long long)buf.f_frsize;
    }
    return YES;
  }
  return NO;
}


@implementation GWViewer

/* Accessor for lastSelection used by GWViewerWindow quicklook guard */

- (void)dealloc
{
  [nc removeObserver: self];

  RELEASE (baseNode);
  RELEASE (baseNodeArray);
  RELEASE (lastSelection);
  RELEASE (defaultsKeyStr);
  RELEASE (watchedNodes);
  RELEASE (previewPane);
  RELEASE (vwrwin);
  RELEASE (viewerPrefs);
  RELEASE (history);
  
  [super dealloc];
}

- (id)initForNode:(FSNode *)node
         inWindow:(GWViewerWindow *)win
         showType:(GWViewType)stype
    showSelection:(BOOL)showsel
	  withKey:(NSString *)key
{
  self = [super init];
  
  if (self) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
    NSString *prefsname;
    id defEntry;
    NSRect r;
    NSString *viewTypeStr;
    
    /* For virtual nodes (like NetworkFSNode), keep the original node.
       For regular paths, create a fresh FSNode from the path. */
    if ([node isKindOfClass:NSClassFromString(@"NetworkFSNode")]) {
      ASSIGN(baseNode, node);
    } else {
      ASSIGN(baseNode, [FSNode nodeWithPath: [node path]]);
    }
    ASSIGN (baseNodeArray, [NSArray arrayWithObject: baseNode]);
    fsnodeRep = [FSNodeRep sharedInstance];
    lastSelection = nil;
    history = [NSMutableArray new];
    historyPosition = 0;
    watchedNodes = [NSMutableArray new];
    manager = [GWViewersManager viewersManager];
    gworkspace = [Workspace gworkspace];
    nc = [NSNotificationCenter defaultCenter];
    
    defEntry = [defaults objectForKey: @"browserColsWidth"];
    if (defEntry) {
      resizeIncrement = [defEntry intValue];
    } else {
      resizeIncrement = DEFAULT_INCR;
    }
    
    rootViewer = [[baseNode path] isEqual: path_separator()];
    firstRootViewer = (rootViewer && ([[manager viewersForBaseNode: baseNode] count] == 0));
    
    if (rootViewer == YES)
      {
	if (firstRootViewer)
	  {
	    prefsname = GWViewerPrefsKey([node path], NO, nil, YES);
	  }
	else
	  {
	    if (key == nil)
	      {
		NSNumber *rootViewerKey;

		rootViewerKey = [NSNumber numberWithUnsignedLong: (unsigned long)self];

		prefsname = GWViewerPrefsKey([node path], NO, rootViewerKey, NO);
	      }
	    else
	      {
		/* Non-owning like the sibling branches (which assign an
		 * autoreleased string); defaultsKeyStr takes the sole retain
		 * below.  A [key retain] here would leak — dealloc balances
		 * only defaultsKeyStr. */
		prefsname = key;
	      }
	  }
      }
    else
      {
	prefsname = GWViewerPrefsKey([node path], NO, nil, NO);
      }

    defaultsKeyStr = [prefsname retain];
    if (viewerPrefs == nil) {
      defEntry = [defaults dictionaryForKey: defaultsKeyStr];
      if (defEntry) {
        viewerPrefs = [defEntry copy];
      } else {
        viewerPrefs = [NSDictionary new];
      }
    }
    
    /* View settings come from .DS_Store (tiered via the settings manager,
     * the single store shared with the spatial viewer) as primary, with the
     * user-defaults viewerPrefs as fallback.  This matches -updateDefaults,
     * which already writes these settings to .DS_Store. */
    DSStoreInfo *dsInfo =
      [[GWViewSettingsManager managerForDirectoryPath: [baseNode path]] readSettings];
    if (dsInfo == nil) {
      dsInfo = [DSStoreInfo infoForDirectoryPath: [baseNode path]];
    }

    /* Precedence: an explicit caller-supplied type (stype != 0) wins; then the
     * folder's remembered .DS_Store style; then the user-defaults viewerPrefs;
     * else Icon.  (The enum starts at GWViewTypeBrowser = 1, so 0 means "no
     * preference".) */
    viewType = GWViewTypeIcon;
    if (stype != 0)
      {
        viewType = stype;
      }
    else
      {
        /* DS_Store style (decoded through the shared name helper) is primary,
         * viewerPrefs the fallback; both reduce to a canonical view-type name
         * decoded once below. */
        if (dsInfo.loaded && dsInfo.hasViewStyle)
          viewTypeStr = [DSStoreInfo viewTypeNameForViewStyle: dsInfo.viewStyle];
        else
          viewTypeStr = [viewerPrefs objectForKey: @"viewtype"];

        if ([viewTypeStr isEqual: @"Browser"])
          viewType = GWViewTypeBrowser;
        else if ([viewTypeStr isEqual: @"List"])
          viewType = GWViewTypeList;
        else if ([viewTypeStr isEqual: @"Icon"])
          viewType = GWViewTypeIcon;
      }

    /* The "Show Inspector" toggle and selected pane are remembered per view
     * type (Icon/List/Columns), so e.g. columns view can show the inspector
     * while icon view does not.  Keys are <key>_Icon / _List / _Browser. */
    {
      NSString *vtKey = [self _viewTypeKey];
      NSString *shownKey = [@"showInspector_" stringByAppendingString: vtKey];
      NSString *paneKey = [@"inspectorPane_" stringByAppendingString: vtKey];

      showInspector = [defaults boolForKey: shownKey];
      if ((defEntry = [viewerPrefs objectForKey: shownKey])) {
        showInspector = [defEntry boolValue];
      }
      inspectorPane = 0;
      if ((defEntry = [viewerPrefs objectForKey: paneKey])) {
        inspectorPane = [defEntry intValue];
      }
    }

    /* The sidebar toggle is remembered per view type, like the inspector. */
    showSidebar = YES;
    {
      NSString *vtKey = [self _viewTypeKey];
      NSString *sbKey = [@"showSidebar_" stringByAppendingString: vtKey];
      if ((defEntry = [viewerPrefs objectForKey: sbKey])) {
        showSidebar = [defEntry boolValue];
      }
    }

    if (dsInfo.loaded && dsInfo.hasSidebarWidth)
      {
        sidebarWidth = dsInfo.sidebarWidth;
      }
    else
      {
        defEntry = [viewerPrefs objectForKey: @"sidebarwidth"];
        sidebarWidth = defEntry ? [defEntry floatValue] : DEFAULT_SIDEBAR_WIDTH;
      }
    if (sidebarWidth < MIN_SIDEBAR_WIDTH) sidebarWidth = MIN_SIDEBAR_WIDTH;
    if (sidebarWidth > MAX_SIDEBAR_WIDTH) sidebarWidth = MAX_SIDEBAR_WIDTH;
       
    ASSIGN (vwrwin, win);
    [vwrwin setDelegate: self];

    // ================================================================
    // DS_Store Integration - window geometry (dsInfo loaded above)
    // ================================================================
    BOOL geometryApplied = NO;

    if (dsInfo.loaded && dsInfo.hasWindowFrame) {
      NSRect dsGeometry = [dsInfo gnustepWindowFrameForScreen:[NSScreen mainScreen]];
      
      if (dsGeometry.size.width > 0 && dsGeometry.size.height > 0) {
        
        /* dsGeometry is the CONTENT rect (DS_Store stores content area
         * excluding the title bar; gnustepWindowFrameForScreen: flips to
         * GNUstep bottom-left coords but stays content-sized).  Set the full
         * frame now, BEFORE the window is mapped: the WindowManager reads the
         * window geometry when it frames the window and plays the birth
         * animation, so mapping a placeholder would grow the animation toward
         * the wrong spot (bottom-left) and lay the content out for the wrong
         * size.  frameRectForContentRect: uses the cached decoration offsets,
         * which are exact once the compositor state has settled; activate
         * later re-applies the frame with the WM's live _NET_FRAME_EXTENTS
         * (exact), correcting any residual offset error mid-animation so it
         * never drifts on repeated open/close cycles. */
        pendingRestoreFrame = dsGeometry;
        hasPendingRestoreFrame = YES;
        [vwrwin setFrame: [vwrwin frameRectForContentRect: dsGeometry]
                 display: NO];
        geometryApplied = YES;
      }
    }
    
    if (!geometryApplied) {
      r = NSMakeRect(200, 200, resizeIncrement * 5, 600);
      NSRect content = rectForWindow([manager viewerWindows], r, YES);
      /* Route the default through the same exact restore path: activate:
       * reads the WM's live _NET_FRAME_EXTENTS and adds them to the content
       * rect, so the frame includes the title bar exactly.  A bare
       * frameRectForContentRect: cannot do this here - it relies on the
       * cached decoration offsets, which are not populated before the first
       * window of a session has been framed, so the first open would lack the
       * title while every reopen had it (a 22px frame-constant failure). */
      pendingRestoreFrame = content;
      hasPendingRestoreFrame = YES;
      [vwrwin setFrame: [vwrwin frameRectForContentRect: content]
               display: NO];
    }
    
    r = [vwrwin frame];
    
    if (r.size.height < MIN_WIN_H) {
      r.origin.y -= (MIN_WIN_H - r.size.height);
      r.size.height = MIN_WIN_H;
    
      if (r.origin.y < 0) {
        r.origin.y = 5;
      }
      
      [vwrwin setFrame: r display: NO];
    }

    [vwrwin setMinSize: NSMakeSize(resizeIncrement * 2, MIN_WIN_H)];    
    [vwrwin setResizeIncrements: NSMakeSize(resizeIncrement, 1)];

    if (firstRootViewer) {
      NSString *path = [baseNode path];
      if ([path isEqual: path_separator()]) {
        [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
      } else {
        [vwrwin setTitle: [baseNode name]];
      }
    } else {
      if (rootViewer) {
        NSString *path = [baseNode path];
        if ([path isEqual: path_separator()]) {
          [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
        } else {
          [vwrwin setTitle: [baseNode name]];
        }
      } else {
        NSString *path = [baseNode path];
        if ([path isEqual: path_separator()]) {
          [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
        } else {
          [vwrwin setTitle: [baseNode name]];
        }
      }
    }

    [self createSubviews];

    if (viewType == GWViewTypeIcon) {
      nodeView = [[GWViewerIconsView alloc] initForViewer: self];
      
      [pathsScroll setDelegate: pathsView];
      
    } else if (viewType == GWViewTypeList) { 
      NSRect r = [[nviewScroll contentView] bounds];
      
      nodeView = [[GWViewerListView alloc] initWithFrame: r forViewer: self];
       
      [pathsScroll setDelegate: pathsView];
       
    } else if (viewType == GWViewTypeBrowser ) {
      [nviewScroll setAutohidesScrollers: NO];
      [nviewScroll setHasHorizontalScroller: YES];
      [nviewScroll setHasVerticalScroller: YES];
      nodeView = [[GWViewerBrowser alloc] initWithBaseNode: baseNode
                                      inViewer: self
		                            visibleColumns: visibleCols
                                      scroller: [nviewScroll horizontalScroller]
                                    cellsIcons: NO
                                 editableCells: NO
                               selectionColumn: YES];
    }

    [nviewScroll setDocumentView: nodeView];
    RELEASE (nodeView);
    [self applyContentBackgroundColor];
    [nodeView showContentsOfNode: baseNode];

    if ([[NSUserDefaults standardUserDefaults] boolForKey: @"use_thumbnails"])
      {
        Thumbnailer *t = [Thumbnailer sharedThumbnailer];
        if (t) [t makeThumbnails: [baseNode path]];
      }
    
    if (showsel) {
      defEntry = [viewerPrefs objectForKey: @"lastselection"];
    
      if (defEntry) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *selection = [defEntry mutableCopy];
        int count = [selection count];
        int i;

        for (i = 0; i < count; i++) {
          NSString *s = [selection objectAtIndex: i];

          if ([fm fileExistsAtPath: s] == NO) {
            [selection removeObject: s];
            count--;
            i--;
          }
        }

        if ([selection count]) {
          if ([nodeView isSingleNode]) {
            NSString *base = [selection objectAtIndex: 0];
            FSNode *basenode = [FSNode nodeWithPath: base];
          
            if (([basenode isDirectory] == NO) || [basenode isPackage]) {
              base = [base stringByDeletingLastPathComponent];
              basenode = [FSNode nodeWithPath: base];
            }
            
            [nodeView showContentsOfNode: basenode];
            [nodeView selectRepsOfPaths: selection];
          
          } else {
            [nodeView selectRepsOfPaths: selection];
          }
        }

        RELEASE (selection);
      }
    }
        
    [nc addObserver: self 
           selector: @selector(columnsWidthChanged:) 
               name: @"GWBrowserColumnWidthChangedNotification"
             object: nil];

    /* If this viewer is showing the Network node, observe service changes */
    if ([baseNode isKindOfClass:[NetworkFSNode class]]) {
      [nc addObserver: self
             selector: @selector(networkServicesDidChange:)
                 name: NetworkServicesDidChangeNotification
               object: nil];
    }

    invalidated = NO;
    closing = NO;    
  }
  
  return self;
}

- (void)createSubviews
{
  NSRect r = [[vwrwin contentView] bounds];
  CGFloat w = r.size.width;
  CGFloat h = r.size.height;
  CGFloat d = 0.0;
  int xmargin = 0;
  int ymargin = 0;
  int pathscrh = 46;
  NSUInteger resizeMask;
  BOOL hasScroller;

  split = [[GWViewerSplit alloc] initWithFrame: r];
  [split setVertical: YES];
  [split setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];
  [split setDelegate: self];

  d = [split dividerThickness];

  if (sidebarWidth + d > w - MIN_SIDEBAR_WIDTH) {
    sidebarWidth = DEFAULT_SIDEBAR_WIDTH;
  }

  r = NSMakeRect(0, 0, sidebarWidth, h);
  sidebar = [[GWViewerSidebar alloc] initWithFrame: r forViewer: self];
  [sidebar setAutoresizingMask: NSViewHeightSizable];
  [split addSubview: sidebar];
  RELEASE (sidebar);

  r = NSMakeRect(sidebarWidth + d, 0, w - sidebarWidth - d, h);
  lowBox = [[NSView alloc] initWithFrame: r];
  resizeMask = NSViewWidthSizable | NSViewHeightSizable;
  [lowBox setAutoresizingMask: resizeMask];
  [lowBox setAutoresizesSubviews: YES];
  [split addSubview: lowBox];
  RELEASE (lowBox);

  r = [lowBox bounds];
  w = r.size.width;
  h = r.size.height;
  
  r = NSMakeRect(xmargin, 0, w - (xmargin * 2), pathscrh);
  pathsScroll = [[GWViewerPathsScroll alloc] initWithFrame: r];
  [pathsScroll setBorderType: NSBezelBorder];
  [pathsScroll setHasHorizontalScroller: YES];
  [pathsScroll setHasVerticalScroller: NO];
  [pathsScroll setDelegate: nil];
  [pathsScroll setBackgroundColor: [NSColor windowBackgroundColor]];
  [pathsScroll setDrawsBackground: YES];
  resizeMask = NSViewNotSizable | NSViewWidthSizable | NSViewMaxYMargin;
  [pathsScroll setAutoresizingMask: resizeMask];
  [lowBox addSubview: pathsScroll];
  RELEASE (pathsScroll);

  visibleCols = myrintf(r.size.width / [vwrwin resizeIncrements].width);

  r = [[pathsScroll contentView] bounds];
  pathsView = [[GWViewerIconsPath alloc] initWithFrame: r
                   visibleIcons: visibleCols forViewer: self
                   ownsScroller: (viewType != GWViewTypeBrowser)];
  resizeMask = NSViewNotSizable;
  [pathsView setAutoresizingMask: resizeMask];
  [pathsScroll setDocumentView: pathsView];
  /* Lion-style compact path bar: small icon directly to the left of the
     name, with a chevron drawn between path components. */
  [pathsView setCompactPathBarMode: YES iconSize: 20 labelFontSize: 12];
  RELEASE (pathsView);

  r = NSMakeRect(xmargin, pathscrh, w - (xmargin * 2), h - pathscrh - ymargin);
  nviewScroll = [[GWViewerScrollView alloc] initWithFrame: r inViewer: self];
  [nviewScroll setBorderType: NSBezelBorder];
  hasScroller = (viewType != GWViewTypeBrowser);
  [nviewScroll setHasHorizontalScroller: NO];
  [nviewScroll setHasVerticalScroller: hasScroller];
  resizeMask = NSViewNotSizable | NSViewWidthSizable | NSViewHeightSizable;
  [nviewScroll setAutoresizingMask: resizeMask];
  [lowBox addSubview: nviewScroll];
  RELEASE (nviewScroll);

  [self updatePreviewPaneForCurrentType];

  [vwrwin setContentView: split];
  RELEASE (split);
}

/* Adds or removes the rightmost "Contents" preview pane according to the
 * "Show Inspector" toggle, and resizes the node view accordingly.  When the
 * toggle is on, the fixed GW_PREVIEW_PANE_WIDTH on the right is reserved for
 * the pane in every view type; when off, the node view uses the full width.
 * Called both at setup and whenever the toggle or view type changes, so the
 * layout always stays consistent.
 *
 * While the inspector is shown, the node-view scroll view is NOT
 * width-sizable: GNUstep autoresizing would make it absorb the whole window
 * width change and grow over the pane.  Instead windowDidResize: lays it out
 * explicitly at width - GW_PREVIEW_PANE_WIDTH, then asks the browser to
 * re-tile its columns.  When the inspector is hidden the scroll view is
 * width-sizable again to fill the window. */
- (void)updatePreviewPaneForCurrentType
{
  NSRect low = [lowBox bounds];
  CGFloat w = low.size.width;
  CGFloat h = low.size.height;
  NSRect nr, pr;

  if (showInspector)
    {
      if (previewPane == nil)
        {
          pr = NSMakeRect(w - GW_PREVIEW_PANE_WIDTH, PREVIEW_PATHSCRH,
                          GW_PREVIEW_PANE_WIDTH, h - PREVIEW_PATHSCRH);
          previewPane = [[GWViewerBrowserPreview alloc] initWithFrame: pr];
          [previewPane setViewer: self];
          [previewPane setAutoresizingMask: NSViewHeightSizable | NSViewMinXMargin];
          [lowBox addSubview: previewPane];
        }
      /* Apply the remembered pane for the current view type (the pane may
       * persist across view-type switches). */
      [previewPane selectInspectorAtIndex: inspectorPane];
      nr = NSMakeRect(PREVIEW_XMARGIN, PREVIEW_PATHSCRH,
                      w - (PREVIEW_XMARGIN * 2) - GW_PREVIEW_PANE_WIDTH,
                      h - PREVIEW_PATHSCRH - PREVIEW_YMARGIN);
      [nviewScroll setAutoresizingMask: NSViewNotSizable | NSViewHeightSizable];
    }
  else
    {
      if (previewPane)
        {
          [previewPane removeFromSuperview];
          DESTROY (previewPane);
        }
      nr = NSMakeRect(PREVIEW_XMARGIN, PREVIEW_PATHSCRH,
                      w - (PREVIEW_XMARGIN * 2), h - PREVIEW_PATHSCRH - PREVIEW_YMARGIN);
      [nviewScroll setAutoresizingMask: NSViewNotSizable | NSViewWidthSizable | NSViewHeightSizable];
    }

  [nviewScroll setFrame: nr];
  [nviewScroll setNeedsDisplay: YES];
}


/* Canonical suffix for per-view-type inspector preferences. */
- (NSString *)_viewTypeKey
{
  switch (viewType)
    {
      case GWViewTypeList:    return @"List";
      case GWViewTypeBrowser: return @"Browser";
      case GWViewTypeIcon:
      default:                return @"Icon";
    }
}






- (FSNode *)baseNode
{
  return baseNode;
}

- (BOOL)isShowingNode:(FSNode *)anode
{
  NSArray *comps = [FSNode nodeComponentsFromNode: baseNode 
                                           toNode: [nodeView shownNode]];
  return [comps containsObject: anode];
}

- (BOOL)isShowingPath:(NSString *)apath
{
  FSNode *node = [FSNode nodeWithPath: apath];
  return [self isShowingNode: node];
}


- (void)reloadFromNode:(FSNode *)anode
{
  [nodeView reloadFromNode: anode];
  [self updeateInfoLabels];
}

- (void)unloadFromNode:(FSNode *)anode
{
  if ([baseNode isEqual: anode] || [baseNode isSubnodeOfNode: anode]) {
    [self deactivate];
  } else {
    [nodeView unloadFromNode: anode];
  }
}

- (void)updateShownSelection
{
  [pathsView updateLastIcon];
}

- (GWViewerWindow *)win
{
  return vwrwin;
}


- (id)shelf
{
  /* Browsing-mode viewers no longer have a shelf; the sidebar replaces it. */
  return nil;
}

- (GWViewType)viewType
{
  return viewType;
}

- (BOOL)isSpatial
{
  return NO;
}

- (int)vtype
{
  return BROWSING;
}

- (BOOL)isFirstRootViewer
{
  return firstRootViewer;
}

- (NSString *)defaultsKey
{
  return defaultsKeyStr;
}

- (void)activate
{
  if ([vwrwin isMiniaturized]) {
    [vwrwin deminiaturize: nil];
  }
  [vwrwin makeKeyAndOrderFront: nil];

  /* Re-apply the saved content rect through GNUstep's own setFrame: now that
   * the WM has framed the window and set _NET_FRAME_EXTENTS on it, GNUstep's
   * frame math (styleoffsets: reads _NET_FRAME_EXTENTS first) is exact.  The
   * frame set in init used the cached decoration offsets (correct position,
   * size within a px) so the window maps and animates at its real geometry;
   * this second pass corrects any residual offset error so the restore is
   * pixel-exact, and because it happens while the birth animation is still
   * playing the tiny correction is not visible.  setFrame: also keeps
   * GNUstep's internal frame in sync with the real X client - a raw X
   * placement would leave the two disagreeing.  The WM sets the extents
   * asynchronously after mapping, so retry briefly until they appear; if they
   * never do we hard-fail (report loudly) instead of placing at a guess. */
  if (hasPendingRestoreFrame) {
    Window xwin = 0;
    GSDisplayServer *gsrv = GSServerForWindow(vwrwin);
    if (!gsrv) gsrv = GSCurrentServer();
    if (gsrv) {
      void *winptr = [gsrv windowDevice:[vwrwin windowNumber]];
      xwin = (Window)(uintptr_t)winptr;
    }
    unsigned long l = 0, r = 0, t = 0, b = 0;
    int attempts = 0;
    while (xwin != 0 && attempts < 20
           && ![[GWX11WindowManager sharedManager] frameExtentsForWindow:xwin
                                                                 outLeft:&l
                                                                outRight:&r
                                                                 outTop:&t
                                                              outBottom:&b]) {
      [NSThread sleepForTimeInterval: 0.05];
      attempts++;
    }
    if (xwin != 0 && attempts < 20) {
      NSRect full = pendingRestoreFrame;
      full.origin.x -= (CGFloat)l;
      full.origin.y -= (CGFloat)b;
      full.size.width += (CGFloat)l + (CGFloat)r;
      full.size.height += (CGFloat)t + (CGFloat)b;
      [vwrwin setFrame: full display: YES];
    } else {
      /* Hard fail: never place the window at a guessed size.  The WM writes
       * _NET_FRAME_EXTENTS on the client when it frames the window; if it is
       * still missing after the retries the decoration state is unknown, so
       * leave the init geometry in place and report loudly instead of
       * silently drifting on every open/close cycle. */
      NSLog(@"ERROR: [GWViewer] frame extents missing for viewer window %@: "
            @"xwin=%lu attempts=%d - restore not placed exactly",
            vwrwin, (unsigned long)xwin, attempts);
    }
    hasPendingRestoreFrame = NO;
  }

  [self tileViews];
  [self scrollToBeginning];
}


- (void)tileViews
{
  NSRect r = [split bounds];
  CGFloat w = r.size.width;
  CGFloat h = r.size.height;
  CGFloat d = [split dividerThickness];

  if (!showSidebar)
    {
      /* Sidebar hidden: hide the pane and let the content box fill the
       * whole split.  The sidebar object stays alive so showing it again is
       * instant (no reload). */
      [sidebar setHidden: YES];
      [lowBox setFrame: r];
      return;
    }

  [sidebar setHidden: NO];

  if (sidebarWidth < MIN_SIDEBAR_WIDTH) sidebarWidth = MIN_SIDEBAR_WIDTH;
  if (sidebarWidth > MAX_SIDEBAR_WIDTH) sidebarWidth = MAX_SIDEBAR_WIDTH;
  if (sidebarWidth + d > w - MIN_SIDEBAR_WIDTH) {
    sidebarWidth = w - MIN_SIDEBAR_WIDTH - d;
    if (sidebarWidth < MIN_SIDEBAR_WIDTH) sidebarWidth = MIN_SIDEBAR_WIDTH;
  }

  [sidebar setFrame: NSMakeRect(0, 0, sidebarWidth, h)];
  [lowBox setFrame: NSMakeRect(sidebarWidth + d, 0, w - sidebarWidth - d, h)];
}

- (CGFloat)defaultSidebarWidth
{
  return DEFAULT_SIDEBAR_WIDTH;
}

- (void)setSidebarWidth:(CGFloat)w
{
  if (w < DEFAULT_SIDEBAR_WIDTH) w = DEFAULT_SIDEBAR_WIDTH;
  if (w > MAX_SIDEBAR_WIDTH) w = MAX_SIDEBAR_WIDTH;
  if (w == sidebarWidth) return;
  sidebarWidth = w;
  [self tileViews];
}

- (BOOL)isSidebarShown
{
  return showSidebar;
}

- (void)toggleSidebar:(id)sender
{
  [self setSidebarShown: !showSidebar];
}

- (void)setSidebarShown:(BOOL)shown
{
  if (showSidebar == shown) return;
  showSidebar = shown;
  [self tileViews];
  [vwrwin display];
  [self updateDefaults];
}

- (void)reloadSidebar
{
  [sidebar rebuildVolumesSection];
}

- (void)applyContentBackgroundColor
{
  NSColor *bg = [NSColor controlBackgroundColor];

  if (nviewScroll) {
    [nviewScroll setBackgroundColor: bg];
    [nviewScroll setDrawsBackground: YES];
  }

  if (nodeView && [nodeView respondsToSelector: @selector(setBackgroundColor:)]) {
    [(id)nodeView setBackgroundColor: bg];
  }
}


- (void)invalidate
{
  invalidated = YES;
}




- (void)unselectAllReps
{
  [nodeView unselectOtherReps: nil];
  [nodeView selectionDidChange];
}

- (void)selectionChanged:(NSArray *)newsel
{
  FSNode *node;
  NSArray *components;

  if (closing)
    return;

  [manager selectionChanged: newsel];

  if (lastSelection && [newsel isEqual: lastSelection]) {
    if ([[newsel objectAtIndex: 0] isEqual: [nodeView shownNode]] == NO) {
      return;
    }
  }

  ASSIGN (lastSelection, newsel);
  [self updeateInfoLabels]; 

  /* Show the Contents inspector for the newly selected file in the
   * rightmost browser preview pane.  Guarded: the inspector machinery must
   * never break selection or opening of files. */
  if (previewPane) {
    NS_DURING
      {
        [previewPane showSelection: newsel];
      }
    NS_HANDLER
      {
        NSLog(@"[GWViewer] preview showSelection exception: %@", localException);
      }
    NS_ENDHANDLER
  }

  node = [newsel objectAtIndex: 0];   
     
  if (([node isDirectory] == NO) || [node isPackage] || ([newsel count] > 1)) {
    if ([node isEqual: baseNode] == NO) { // if baseNode is a package 
      node = [FSNode nodeWithPath: [node parentPath]];
    }
  }
    
  components = [FSNode nodeComponentsFromNode: baseNode toNode: node];
  
  [pathsView showPathComponents: components selection: newsel];

  if ([node isDirectory] && ([newsel count] == 1)) {
    if ([nodeView isSingleNode] && ([node isEqual: [nodeView shownNode]] == NO)) {
      node = [FSNode nodeWithPath: [node parentPath]];
      components = [FSNode nodeComponentsFromNode: baseNode toNode: node];
    }
  }

  if ([components isEqual: watchedNodes] == NO) {
    NSUInteger count = [components count];
    unsigned pos = 0;
    NSUInteger i;
  
    for (i = 0; i < [watchedNodes count]; i++) { 
      FSNode *nd = [watchedNodes objectAtIndex: i];
      
      if (i < count) {
        FSNode *ndcomp = [components objectAtIndex: i];

        if ([nd isEqual: ndcomp] == NO) {
          [gworkspace removeWatcherForPath: [nd path]];
        } else {
          pos = i + 1;
        }

      } else {
        [gworkspace removeWatcherForPath: [nd path]];
      }
    }

    for (i = pos; i < count; i++) {   
      [gworkspace addWatcherForPath: [[components objectAtIndex: i] path]];
    }

    [watchedNodes removeAllObjects];
    [watchedNodes addObjectsFromArray: components];
  }  
  
  [manager addNode: node toHistoryOfViewer: self];
}

- (void)multipleNodeViewDidSelectSubNode:(FSNode *)node
{
}

- (void)pathsViewDidSelectIcon:(id)icon
{
  FSNode *node = [icon node];
  int index = [icon gridIndex];
  
  if ([node isDirectory] && (([node isPackage] == NO) || (index == 0))) {
    if ([nodeView isSingleNode]) {
      [nodeView showContentsOfNode: node];
      [self scrollToBeginning];
      [self selectionChanged: [NSArray arrayWithObject: node]];
      
    } else {
      [nodeView setLastShownNode: node];
    }
  }
}

- (void)shelfDidSelectIcon:(id)icon
{
  FSNode *node = [icon node];
  NSArray *selection = [icon selection];
  FSNode *nodetoshow;
  
  if (selection && ([selection count] > 1)) {
    nodetoshow = [FSNode nodeWithPath: [node parentPath]];
  } else {
    if ([node isDirectory] && ([node isPackage] == NO)) {
      nodetoshow = node;
      
      if (viewType != GWViewTypeBrowser) {
        selection = nil;
      } else {
        selection = [NSArray arrayWithObject: node];
      }
    
    } else {
      nodetoshow = [FSNode nodeWithPath: [node parentPath]];
      selection = [NSArray arrayWithObject: node];
    }
  }

  [nodeView showContentsOfNode: nodetoshow];
  
  if (selection) {
    [nodeView selectRepsOfSubnodes: selection];
  }

  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)]) {
    [nodeView scrollSelectionToVisible];
  }
}

- (void)setSelectableNodesRange:(NSRange)range
{
  visibleCols = range.length;
  [pathsView setSelectableIconsRange: range];
}

- (void)updeateInfoLabels
{
  FSNode *shownNode = [nodeView shownNode];
  const char *path = [[shownNode path] UTF8String];
  unsigned long long totalSize = 0;
  unsigned long long freeSize = 0;
  unsigned long long availableSize = 0;
  NSString *labelstr;
  
  /* Try to get volume information using statvfs */
  if (getVolumeInfo(path, &totalSize, &freeSize, &availableSize)) {
    NSUInteger systemType = [[NSProcessInfo processInfo] operatingSystem];
    
    /* Adjust for MACH systems if needed */
    if (systemType == NSMACHOperatingSystem) {
      totalSize = (totalSize >> 8);
      freeSize = (freeSize >> 8);
      availableSize = (availableSize >> 8);
    }
    
    /* Format the label with total, available, and free space */
    labelstr = [NSString stringWithFormat: @"%@ %@ | %@ %@ | %@ %@",
               sizeDescription(totalSize),
               NSLocalizedString(@"total", @""),
               sizeDescription(availableSize),
               NSLocalizedString(@"available", @""),
               sizeDescription(freeSize),
               NSLocalizedString(@"free", @"")];
  } else {
    /* Fallback to the old method if statvfs fails */
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attributes = [fm fileSystemAttributesAtPath: [shownNode path]];
    NSNumber *freefs = [attributes objectForKey: NSFileSystemFreeSize];
    
    if (freefs == nil) {
      labelstr = NSLocalizedString(@"unknown volume size", @"");
    } else {
      unsigned long long fallbackFreeSize = [freefs unsignedLongLongValue];
      NSUInteger systemType = [[NSProcessInfo processInfo] operatingSystem];
      
      if (systemType == NSMACHOperatingSystem) {
        fallbackFreeSize = (fallbackFreeSize >> 8);
      }
      labelstr = [NSString stringWithFormat: @"%@ %@",
                 sizeDescription(fallbackFreeSize),
                 NSLocalizedString(@"free", @"")];
    }
  }
  
  [split updateDiskSpaceInfo: labelstr];
}

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo
{
  FSNode *lastNode = [nodeView shownNode];
  NSArray *comps = [FSNode nodeComponentsFromNode: baseNode toNode: lastNode];
  int i;    

  for (i = 0; i < [comps count]; i++) {
    if ([[comps objectAtIndex: i] involvedByFileOperation: opinfo]) {
      return YES;
    }
  }

  return NO;
}


- (void)nodeContentsDidChange:(NSDictionary *)info
{
  NSString *operation = [info objectForKey: @"operation"];
  
  if ([nodeView isSingleNode]) {  
    NSString *source = [info objectForKey: @"source"];
    NSString *destination = [info objectForKey: @"destination"];
  
    if ([operation isEqual: @"WorkspaceRenameOperation"]) {
      destination = [destination stringByDeletingLastPathComponent]; 
    }

    if ([operation isEqual: NSWorkspaceMoveOperation]
          || [operation isEqual: NSWorkspaceCopyOperation]
          || [operation isEqual: NSWorkspaceLinkOperation]
          || [operation isEqual: NSWorkspaceDuplicateOperation]
          || [operation isEqual: @"WorkspaceCreateDirOperation"]
          || [operation isEqual: @"WorkspaceCreateFileOperation"]
          || [operation isEqual: NSWorkspaceRecycleOperation]
          || [operation isEqual: @"WorkspaceRenameOperation"]
			    || [operation isEqual: @"WorkspaceRecycleOutOperation"]) { 
      [nodeView reloadFromNode: [FSNode nodeWithPath: destination]];
    }

    if ([operation isEqual: NSWorkspaceMoveOperation]
          || [operation isEqual: NSWorkspaceDestroyOperation]
				  || [operation isEqual: NSWorkspaceRecycleOperation]
				  || [operation isEqual: @"WorkspaceRecycleOutOperation"]
				  || [operation isEqual: @"WorkspaceemptyTrashOperation"]) {
      [nodeView reloadFromNode: [FSNode nodeWithPath: source]];
    }
    
  } else {
    [nodeView nodeContentsDidChange: info];
  }
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  if (invalidated == NO) {
    if ([nodeView isSingleNode]) {
      NSString *path = [info objectForKey: @"path"];
      NSString *event = [info objectForKey: @"event"];
  
      if ([event isEqual: @"GWWatchedPathDeleted"]) {
        NSString *s = [path stringByDeletingLastPathComponent];

        if ([self isShowingPath: s]) {
          FSNode *node = [FSNode nodeWithPath: s];
          [nodeView reloadFromNode: node];
        }

      } else if ([nodeView isShowingPath: path]) {
        [nodeView watchedPathChanged: info];
      }
  
    } else {
      [nodeView watchedPathChanged: info];
    }
  }
}







- (void)columnsWidthChanged:(NSNotification *)notification
{
  NSRect r = [vwrwin frame];
  NSRange range;
    
  RETAIN (nodeView);  
  [nodeView removeFromSuperviewWithoutNeedingDisplay];
  [nviewScroll setDocumentView: nil];	

  RETAIN (pathsView);  
  [pathsView removeFromSuperviewWithoutNeedingDisplay];
  [pathsScroll setDocumentView: nil];	  

  resizeIncrement = [(NSNumber *)[notification object] intValue];
  /* When the Inspector toggle is on, it occupies a fixed width of window
   * space regardless of view type. */
  r.size.width = ((visibleCols * resizeIncrement)
                  + (showInspector ? GW_PREVIEW_PANE_WIDTH : 0));
  [vwrwin setFrame: r display: YES];  
  [vwrwin setMinSize: NSMakeSize(resizeIncrement * 2, MIN_WIN_H)];    
  [vwrwin setResizeIncrements: NSMakeSize(resizeIncrement, 1)];

  [pathsScroll setDocumentView: pathsView];	
  RELEASE (pathsView); 
  range = NSMakeRange([pathsView firstVisibleIcon], [pathsView lastVisibleIcon]);
  [pathsView setSelectableIconsRange: range];

  [nviewScroll setDocumentView: nodeView];
  RELEASE (nodeView);
  [self applyContentBackgroundColor];
  [nodeView resizeWithOldSuperviewSize: [nodeView bounds].size];

  [self windowDidResize: nil];
}

- (void)networkServicesDidChange:(NSNotification *)notification
{
  /* Refresh the network node's subnodes and reload the view */
  if ([baseNode isKindOfClass:[NetworkFSNode class]]) {
    [self reloadNodeContents];
  }
}

- (void)updateDefaults
{
  if ([baseNode isValid])
    {
      NSMutableDictionary *updatedprefs = [nodeView updateNodeInfo: NO];
      id defEntry;
      NSString *viewTypeStr;

      if (viewType == GWViewTypeIcon)
        viewTypeStr = @"Icon";
      else if (viewType == GWViewTypeList)
        viewTypeStr = @"List";
      else
        viewTypeStr = @"Browser";

    if (updatedprefs == nil) {
      updatedprefs = [NSMutableDictionary dictionary];
    }

    [updatedprefs setObject: [NSNumber numberWithBool: [nodeView isSingleNode]]
                     forKey: @"singlenode"];

    [updatedprefs setObject: viewTypeStr forKey: @"viewtype"];

    [updatedprefs setObject: [NSNumber numberWithFloat: sidebarWidth]
                     forKey: @"sidebarwidth"];

    /* Remember the inspector toggle and selected pane per view type. */
    {
      NSString *vtKey = [self _viewTypeKey];
      [updatedprefs setObject: [NSNumber numberWithBool: showInspector]
                       forKey: [@"showInspector_" stringByAppendingString: vtKey]];
      [updatedprefs setObject: [NSNumber numberWithBool: showSidebar]
                       forKey: [@"showSidebar_" stringByAppendingString: vtKey]];
      [updatedprefs setObject: [NSNumber numberWithInt: inspectorPane]
                       forKey: [@"inspectorPane_" stringByAppendingString: vtKey]];
    }

    defEntry = [nodeView selectedPaths];
    if (defEntry) {
      if ([defEntry count] == 0) {
        defEntry = [NSArray arrayWithObject: [[nodeView shownNode] path]];
      }
      [updatedprefs setObject: defEntry forKey: @"lastselection"];
    }
    
    /* Persist the window's CONTENT rect, not the full frame: .DS_Store
     * fwi0/bwsp stores the content area (excluding title bar/border), per
     * the MozillaWiki DS_Store format notes and Finder behavior.  Storing
     * stringWithSavedFrame (the full frame) would make restore add the
     * decoration height again, so the window would grow and drift upward on
     * every open/close cycle.  We measure the content rect from the ACTUAL
     * X geometry of the client window (EWMH §5.17), because GNUstep's
     * tracked frame can include a stale clientBorder and be a couple of px
     * wider/taller than the WM's real frame - using it would make the saved
     * rect grow on every cycle.  The content rect is in GNUstep screen
     * coords (bottom-left origin); the DS_Store coordinate conversion
     * happens in dsStoreWindowFrameForScreen:. */
    NSRect contentRect = NSZeroRect;
    {
      Window xwin = 0;
      GSDisplayServer *gsrv = GSServerForWindow(vwrwin);
      if (!gsrv) gsrv = GSCurrentServer();
      if (gsrv) {
        void *winptr = [gsrv windowDevice:[vwrwin windowNumber]];
        xwin = (Window)(uintptr_t)winptr;
      }
      if (xwin != 0
          && [[GWX11WindowManager sharedManager] contentRectFromXGeometry:xwin
                                                  screenHeight:[[NSScreen mainScreen] frame].size.height
                                                      outRect:&contentRect]) {
        /* Measured from the real client window - exact. */
      } else {
        /* No X geometry available: fall back to GNUstep's own conversion. */
        contentRect = [vwrwin contentRectForFrameRect: [vwrwin frame]];
      }
    }
    [updatedprefs setObject: NSStringFromRect(contentRect)
                     forKey: @"geometry"];

    // Save view settings to .DS_Store for Mac interoperability
    {
      GWViewSettingsManager *sm = [GWViewSettingsManager managerForDirectoryPath:[baseNode path]];
      /* Reload current settings first so the write reflects any icon
       * positions the position store persisted since the last load. */
      DSStoreInfo *dsInfo = [sm readSettings];
      if (dsInfo == nil) {
        dsInfo = [DSStoreInfo infoForDirectoryPath:[baseNode path] loadImmediately:NO];
      }
      [dsInfo takeValuesFromViewerPrefs:updatedprefs];
      /* Persist the LIVE layout: an icon-position-honoring view knows exactly
       * where every icon sits right now, so write that instead of whatever a
       * stale .DS_Store (possibly with foreign colliding positions) had. */
      if (viewType == GWViewTypeIcon
          && [nodeView respondsToSelector: @selector(liveIconPositions)]) {
        NSDictionary *live = [nodeView liveIconPositions];
        if (live && [live count] > 0)
          [dsInfo setLiveIconPositions: live];
      }
      [sm writeSettings:dsInfo];
    }

    [baseNode checkWritable];

    /* Window geometry lives in .DS_Store (interoperable), not in the
     * user-defaults viewerPrefs; the .DS_Store write above already used it. */
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      [updatedprefs removeObjectForKey: @"geometry"];
      [defaults setObject: updatedprefs forKey: defaultsKeyStr];
    }
    
    ASSIGN (viewerPrefs, [updatedprefs makeImmutableCopyOnFail: NO]);
  }
}


- (void)navigateToNode:(FSNode *)node
{
  if (node == nil || [node isValid] == NO)
    return;

  [nodeView showContentsOfNode: node];
  [self scrollToBeginning];
  [self selectionChanged: [NSArray arrayWithObject: node]];

  /* Update the window title to reflect the navigated location */
  NSString *path = [node path];
  if ([path isEqual: path_separator()]) {
    [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
  } else {
    [vwrwin setTitle: [node name]];
  }

  [manager addNode: node toHistoryOfViewer: self];
}

- (void)openNodeInPlace:(FSNode *)newBase
{
  if (newBase == nil) {
    return;
  }
  if ([baseNode isEqual: newBase]) {
    [self activate];
    return;
  }

  /* Tear down watchers for the old base */
  NSUInteger i;
  for (i = 0; i < [watchedNodes count]; i++) {
    [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: i] path]];
  }
  [watchedNodes removeAllObjects];
  DESTROY (lastSelection);

  /* Switch the base node. NetworkFSNode is virtual, keep it as-is. */
  if ([newBase isKindOfClass: [NetworkFSNode class]]) {
    ASSIGN (baseNode, newBase);
  } else {
    ASSIGN (baseNode, [FSNode nodeWithPath: [newBase path]]);
  }
  ASSIGN (baseNodeArray, [NSArray arrayWithObject: baseNode]);

  [history removeAllObjects];
  historyPosition = 0;

  /* Recreate the node view bound to the new base. Match the safe
     pattern used in setViewerType:: tearing the documentView down via
     setDocumentView:nil drops the only retain held by the scroller. */
  [nviewScroll setDocumentView: nil];
  nodeView = nil;

  if (viewType == GWViewTypeIcon) {
    nodeView = [[GWViewerIconsView alloc] initForViewer: self];
  } else if (viewType == GWViewTypeList) {
    NSRect r = [[nviewScroll contentView] bounds];
    nodeView = [[GWViewerListView alloc] initWithFrame: r forViewer: self];
  } else if (viewType == GWViewTypeBrowser) {
    nodeView = [[GWViewerBrowser alloc] initWithBaseNode: baseNode
                                                inViewer: self
                                          visibleColumns: visibleCols
                                                scroller: [pathsScroll horizontalScroller]
                                              cellsIcons: NO
                                           editableCells: NO
                                         selectionColumn: YES];
  }

  [nviewScroll setDocumentView: nodeView];
  RELEASE (nodeView);
  [self applyContentBackgroundColor];
  [nodeView showContentsOfNode: baseNode];

  /* Window title */
  {
    NSString *path = [baseNode path];
    if ([path isEqual: path_separator()]) {
      [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
    } else {
      [vwrwin setTitle: [baseNode name]];
    }
  }

  /* Reset the path bar to show only the new base */
  [pathsView showPathComponents: baseNodeArray selection: baseNodeArray];

  /* Network observer follows the current base */
  [nc removeObserver: self
                name: NetworkServicesDidChangeNotification
              object: nil];
  if ([baseNode isKindOfClass: [NetworkFSNode class]]) {
    [nc addObserver: self
           selector: @selector(networkServicesDidChange:)
               name: NetworkServicesDidChangeNotification
             object: nil];
  }

  [manager addNode: baseNode toHistoryOfViewer: self];
  [self scrollToBeginning];
  [self activate];
}

//
// splitView delegate methods
//
- (void)splitView:(NSSplitView *)sender 
                      resizeSubviewsWithOldSize:(NSSize)oldSize
{
  [self tileViews];
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification
{
	[self tileViews];
}

- (CGFloat)splitView:(NSSplitView *)sender
constrainSplitPosition:(CGFloat)proposedPosition
         ofSubviewAt:(NSInteger)offset
{
  CGFloat pos = proposedPosition;

  if (pos < MIN_SIDEBAR_WIDTH) {
    pos = MIN_SIDEBAR_WIDTH;
  } else if (pos > MAX_SIDEBAR_WIDTH) {
    pos = MAX_SIDEBAR_WIDTH;
  }

  sidebarWidth = pos;
  return pos;
}

- (CGFloat)splitView:(NSSplitView *)sender
constrainMaxCoordinate:(CGFloat)proposedMax
         ofSubviewAt:(NSInteger)offset
{
  if (proposedMax >= MAX_SIDEBAR_WIDTH) {
    return MAX_SIDEBAR_WIDTH;
  }
  return proposedMax;
}

- (CGFloat)splitView:(NSSplitView *)sender
constrainMinCoordinate:(CGFloat)proposedMin
         ofSubviewAt:(NSInteger)offset
{
  if (proposedMin <= MIN_SIDEBAR_WIDTH) {
    return MIN_SIDEBAR_WIDTH;
  }
  return proposedMin;
}

@end


//
// GWViewerWindow Delegate Methods
//
@implementation GWViewer (GWViewerWindowDelegateMethods)

- (void)windowDidExpose:(NSNotification *)aNotification
{
  [self updeateInfoLabels];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
  NSArray *selection = [nodeView selectedNodes];

  [manager updateDesktop];
  if ([selection count] == 0)
    {
      selection = [NSArray arrayWithObject: [nodeView shownNode]];
    }
  [self selectionChanged: selection];
  
  [manager changeHistoryOwner: self];
}

- (void)windowDidResize:(NSNotification *)aNotification
{
  if (nodeView) {
    [nodeView stopRepNameEditing];  
    [pathsView stopRepNameEditing];  

    /* Keep the rightmost preview pane sized to the new window width.  The
     * scroll view is not width-sizable while the inspector is shown (see
     * updatePreviewPaneForCurrentType), so resize it here and then let the
     * browser re-tile its columns against the new clip view width. */
    if (showInspector) {
      [self updatePreviewPaneForCurrentType];
      [nodeView resizeWithOldSuperviewSize: [nodeView bounds].size];
    }

    if ([nodeView isSingleNode]) {
      NSRect r = [[vwrwin contentView] bounds];
      int cols = myrintf(r.size.width / [vwrwin resizeIncrements].width);  

      if (cols != visibleCols) {
        [self setSelectableNodesRange: NSMakeRange(0, cols)];
      }
    }
  }
}


- (void)windowWillClose:(NSNotification *)aNotification
{
  if (invalidated == NO) {
    closing = YES;
    /* Resolve the folder's current icon position and tell the WindowManager
     * to shrink the window into it as it closes (or fade when the folder is
     * no longer visible). */
    [manager prepareCloseAnimationForViewer: self];
    [self updateDefaults];
    [vwrwin setDelegate: nil];
    [manager viewerWillClose: self];
  }
}


- (void)openSelectionInNewViewer:(BOOL)newv
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes]; 
    NSUInteger count = (selection ? [selection count] : 0);

    if (count) {
      if (count > MAX_FILES_TO_OPEN_DIALOG) {
        NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
        NSString *msg2 = NSLocalizedString(@"items?", @"");

        if (NSRunAlertPanel(nil,
                            [NSString stringWithFormat: @"%@ %lu %@", msg1, (unsigned long)count, msg2],
                    NSLocalizedString(@"Cancel", @""),
                    NSLocalizedString(@"Yes", @""),
                    nil)) {
          return;
        }
      }

      /* Single selected folder with no modifier: navigate in place (no new
       * window, no birth animation).  Works for single-node icon/list views
       * and the columns (browser) view, which shows the folder's contents in
       * the same window. */
      if ((count == 1) && (newv == NO)) {
        FSNode *node = [selection objectAtIndex: 0];
        if ([node isDirectory] && ([node isPackage] == NO)
            && [nodeView respondsToSelector: @selector(showContentsOfNode:)]) {
          [nodeView showContentsOfNode: node];
          [self scrollToBeginning];
          return;
        }
      }

      /* Everything else: let each item open itself (folders open a viewer
       * growing from the activated icon, other items launch their app). */
      NSUInteger i;
      for (i = 0; i < count; i++) {
        FSNode *node = [selection objectAtIndex: i];
        NS_DURING
          {
            [manager openNode: node fromViewer: self];
          }
        NS_HANDLER
          {
            NSRunAlertPanel(NSLocalizedString(@"error", @""),
                [NSString stringWithFormat: @"%@ %@!",
                          NSLocalizedString(@"Can't open ", @""), [node name]],
                                              NSLocalizedString(@"OK", @""),
                                              nil,
                                              nil);
          }
        NS_ENDHANDLER
      }
    } else if (newv) {
      [manager openAsFolderSelectionInViewer: self];
    }

  } else {
    NSRunAlertPanel(nil,
                  NSLocalizedString(@"You can't open a document that is in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""),
                  nil,
                  nil);
  }
}











- (void)setViewerBehaviour:(id)sender
{
  // For now, this is a placeholder for spatial/browsing mode selection
  // The actual implementation would switch between viewer types
}

- (void)setViewerType:(id)sender
{
  NSInteger tag = [sender tag];

  if (tag > 0)
    {
      NSArray *selection = [nodeView selectedNodes];
      NSUInteger i;
    
      [nodeView updateNodeInfo: YES];
      if ([nodeView isSingleNode] && ([selection count] == 0))
        selection = [NSArray arrayWithObject: [nodeView shownNode]];
 
      RETAIN (selection);
    
      if ([nodeView respondsToSelector: @selector(releaseScroller)])
        [nodeView releaseScroller];
      [nviewScroll setDocumentView: nil];	
    
      if (tag == GWViewTypeBrowser)
        {
          [pathsScroll setDelegate: nil];
          [pathsView setOwnsScroller: NO];

          [nviewScroll setAutohidesScrollers: NO];
          [nviewScroll setHasHorizontalScroller: YES];
          [nviewScroll setHasVerticalScroller: YES];

          nodeView = [[GWViewerBrowser alloc] initWithBaseNode: baseNode
                                                      inViewer: self
                                                visibleColumns: visibleCols
                                                      scroller: [nviewScroll horizontalScroller]
                                                    cellsIcons: NO
                                                 editableCells: NO
                                               selectionColumn: YES];
      
          viewType = GWViewTypeBrowser;
        }
      else if (tag == GWViewTypeIcon)
        {
          NSScroller *scroller = RETAIN ([pathsScroll horizontalScroller]);

          [pathsScroll setHasHorizontalScroller: NO];
          [pathsScroll setHorizontalScroller: scroller]; 
          [pathsScroll setHasHorizontalScroller: YES];
          RELEASE (scroller);
      
          [pathsView setOwnsScroller: YES];
          [pathsScroll setDelegate: pathsView];

          [nviewScroll setHasVerticalScroller: YES];
          [nviewScroll setHasHorizontalScroller: NO];

          nodeView = [[GWViewerIconsView alloc] initForViewer: self];
      
          viewType = GWViewTypeIcon;     
        }
      else if (tag == GWViewTypeList)
        {
          NSRect r = [[nviewScroll contentView] bounds];

          NSScroller *scroller = RETAIN ([pathsScroll horizontalScroller]);

          [pathsScroll setHasHorizontalScroller: NO];
          [pathsScroll setHorizontalScroller: scroller]; 
          [pathsScroll setHasHorizontalScroller: YES];
          RELEASE (scroller);
      
          [pathsView setOwnsScroller: YES];
          [pathsScroll setDelegate: pathsView];

          [nviewScroll setHasVerticalScroller: YES];
          [nviewScroll setHasHorizontalScroller: NO];

          nodeView = [[GWViewerListView alloc] initWithFrame: r forViewer: self];

          viewType = GWViewTypeList;
        }
    
      [nviewScroll setDocumentView: nodeView];
      RELEASE (nodeView);
      [self applyContentBackgroundColor];
      [nodeView showContentsOfNode: baseNode];
                    
      if ([selection count])
        {
          if ([nodeView isSingleNode])
            {
              FSNode *basend = [selection objectAtIndex: 0];
        
              if ([basend isEqual: baseNode] == NO)
                {
                  if (([selection count] > 1) || (([basend isDirectory] == NO) || ([basend isPackage])))
                    {
                      basend = [FSNode nodeWithPath: [basend parentPath]];
                    }
                }
              
              [nodeView showContentsOfNode: basend];
              [nodeView selectRepsOfSubnodes: selection];
              
            }
          else
            {
              [nodeView selectRepsOfSubnodes: selection];
            }
        }
      
      DESTROY (selection);
    
      [self scrollToBeginning];

      [vwrwin makeFirstResponder: nodeView]; 

      for (i = 0; i < [watchedNodes count]; i++)
        {  
          [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: i] path]];
        }
      [watchedNodes removeAllObjects];
      
      DESTROY (lastSelection);
      selection = [nodeView selectedNodes];
      
      if ([selection count] == 0)
        {
          selection = [NSArray arrayWithObject: [nodeView shownNode]];
        }
      
      [self selectionChanged: selection];
      
      [self updateDefaults];

      /* Re-read the per-view-type inspector preference for the new view
       * type, then ensure the rightmost preview pane matches it. */
      {
        NSString *vtKey = [self _viewTypeKey];
        NSString *shownKey = [@"showInspector_" stringByAppendingString: vtKey];
        NSString *paneKey = [@"inspectorPane_" stringByAppendingString: vtKey];
        id entry;

        showInspector = [[NSUserDefaults standardUserDefaults] boolForKey: shownKey];
        if ((entry = [viewerPrefs objectForKey: shownKey])) {
          showInspector = [entry boolValue];
        }
        inspectorPane = 0;
        if ((entry = [viewerPrefs objectForKey: paneKey])) {
          inspectorPane = [entry intValue];
        }
      }
      [self updatePreviewPaneForCurrentType];
      [nodeView resizeWithOldSuperviewSize: [nodeView bounds].size];
      [vwrwin display];
    }
}

- (void)setShownType:(id)sender
{
  NSString *title = [sender title];
  FSNInfoType type = FSNInfoNameType;

  if ([title isEqual: NSLocalizedString(@"Name", @"")]) {
    type = FSNInfoNameType;
  } else if ([title isEqual: NSLocalizedString(@"Type", @"")]) {
    type = FSNInfoKindType;
  } else if ([title isEqual: NSLocalizedString(@"Size", @"")]) {
    type = FSNInfoSizeType;
  } else if ([title isEqual: NSLocalizedString(@"Modification date", @"")]) {
    type = FSNInfoDateType;
  } else if ([title isEqual: NSLocalizedString(@"Owner", @"")]) {
    type = FSNInfoOwnerType;
  } else {
    type = FSNInfoNameType;
  } 

  [(id <FSNodeRepContainer>)nodeView setShowType: type]; 
  [self scrollToBeginning]; 
  [nodeView updateNodeInfo: YES];
}

- (void)setExtendedShownType:(id)sender
{
  [(id <FSNodeRepContainer>)nodeView setExtendedShowType: [sender title]];  
  [self scrollToBeginning];
  [nodeView updateNodeInfo: YES];
}




- (void)chooseLabelColor:(id)sender
{
  NSInteger tag = [sender tag];
  if (tag < 0 || tag > 7) return;

  DSStoreLabelColor labelColor = (DSStoreLabelColor)tag;

  NSArray *selection = [nodeView selectedNodes];
  if (!selection || [selection count] == 0)
    return;

  NSString *basePath = [baseNode path];
  if (![basePath hasSuffix: @"/"])
    {
      basePath = [basePath stringByAppendingString: @"/"];
    }

  /* Create a DSStoreInfo to hold the labels */
  DSStoreInfo *dsInfo = [DSStoreInfo infoForDirectoryPath: [baseNode path]
                                           loadImmediately: NO];
  NSMutableDictionary *tagColors = [NSMutableDictionary dictionary];

  for (FSNode *node in selection)
    {
      if ([node isEqual: baseNode]) continue;

      NSString *nodePath = [node path];
      NSString *filename = [node lastPathComponent];  /* on-disk name */

      if ([nodePath hasPrefix: basePath])
        {
          filename = [nodePath substringFromIndex: [basePath length]];
        }

      /* Also write the per-file FinderInfo label + _kMDItemUserTags tag, as
       * the canonical setLabelForNodes: path does. */
      {
        GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: nodePath];
        if (md == nil)
          {
            md = [[[GSFileMetadata alloc] init] autorelease];
          }
        [md setLabelNumber: (GSFileLabel)labelColor];
        [md writeToFileAtPath: nodePath error: NULL];
      }

      DSStoreIconInfo *info = [dsInfo iconInfoForFilename: filename];
      if (!info)
        {
          info = [DSStoreIconInfo infoForFilename: filename];
        }
      [info setLabelColor: labelColor];
      [info setHasLabelColor: YES];
      [dsInfo setIconInfo: info forFilename: filename];

      if (labelColor != DSStoreLabelColorNone)
        {
          NSColor *color = [DSStoreIconInfo colorForLabelColor: labelColor];
          if (color)
            {
              [tagColors setObject: color forKey: filename];
            }
        }
    }

  /* Visual feedback */
  if ([nodeView respondsToSelector: @selector(setTagColorsFromDictionary:)])
    {
      [(FSNIconsView *)nodeView setTagColorsFromDictionary: tagColors];
    }

  /* Persist via settings manager */
  GWViewSettingsManager *sm;
  sm = [GWViewSettingsManager managerForDirectoryPath: [baseNode path]];
  [sm writeSettings: dsInfo];
}

- (void)chooseBackColor:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setBackgroundColor:)]) {

  }
}

- (void)selectAllInViewer
{
  [nodeView selectAll];
}

- (void)showTerminal
{
  NSString *path;

  if ([nodeView isSingleNode])
    {
      path = [[nodeView shownNode] path];
    }
  else
    {
      NSArray *selection = [nodeView selectedNodes];

      if (selection)
	{
	  FSNode *node = [selection objectAtIndex: 0];

	  if ([selection count] > 1)
	    {
	      path = [node parentPath];
	    }
	  else
	    {
	      if ([node isDirectory] && ([node isPackage] == NO))
		{
		  path = [node path];
		}
	      else
		{
		  path = [node parentPath];
		}
	    }
	}
      else
	{
	  path = [[nodeView shownNode] path];
	}
    }

  [gworkspace startXTermOnDirectory: path];
}


- (BOOL)validateItem:(id)menuItem
{
  SEL action = [menuItem action];

  // Always enable view type/behaviour items regardless of key window
  if (sel_isEqual(action, @selector(setViewerType:)))
    {
      GWViewType vtype = [self viewType];
      [menuItem setState: ([menuItem tag] == vtype) ? NSOnState : NSOffState];
      return YES;
    }
  if (sel_isEqual(action, @selector(setViewerBehaviour:)))
    {
      int vt = [self vtype];
      [menuItem setState: ([menuItem tag] == vt) ? NSOnState : NSOffState];
      return YES;
    }

  if ([NSApp keyWindow] == vwrwin) {
    SEL action = [menuItem action];
    NSString *itemTitle = [menuItem title];
    NSString *menuTitle = [[menuItem menu] title];

    if ([menuTitle isEqual: NSLocalizedString(@"Icon Size", @"")]) {
      return [nodeView respondsToSelector: @selector(setIconSize:)];
    } else if ([menuTitle isEqual: NSLocalizedString(@"Icon Position", @"")]) {
      return [nodeView respondsToSelector: @selector(setIconPosition:)];
    } else if ([menuTitle isEqual: NSLocalizedString(@"Label Size", @"")]) {
      return [nodeView respondsToSelector: @selector(setLabelTextSize:)];
    } else if ([itemTitle isEqual: NSLocalizedString(@"Label Color...", @"")]) {
      return [nodeView respondsToSelector: @selector(setTextColor:)];
    } else if ([itemTitle isEqual: NSLocalizedString(@"Background Color...", @"")]) {
      return [nodeView respondsToSelector: @selector(setBackgroundColor:)];

    } else if (sel_isEqual(action, @selector(duplicateFiles:))
                    || sel_isEqual(action, @selector(recycleFiles:))
                        || sel_isEqual(action, @selector(deleteFiles:))) {
      if (lastSelection && [lastSelection count]
              && ([lastSelection isEqual: baseNodeArray] == NO)) {
        return ([[baseNode path] isEqual: [gworkspace trashPath]] == NO);
      }

      return NO;
    } else if (sel_isEqual(action, @selector(makeThumbnails:)) || sel_isEqual(action, @selector(removeThumbnails:)))
      {
        /* Make or Remove Thumbnails */
        return YES;
    } else if (sel_isEqual(action, @selector(openSelection:))) {
      if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
        if (lastSelection && [lastSelection count]
                && ([lastSelection isEqual: baseNodeArray] == NO)) {
          /* A single folder can be opened in place (navigate); anything else
           * opens in a new viewer/launches.  Multiple folders open several
           * viewers. */
          return YES;
        }
        return NO;
      }

      return NO;

    } else if (sel_isEqual(action, @selector(openSelectionAsFolder:))) {
      if (lastSelection && ([lastSelection count] == 1)) {  
        return [[lastSelection objectAtIndex: 0] isDirectory];
      }

      return NO;

    } else if (sel_isEqual(action, @selector(openWith:))) {
      BOOL canopen = YES;
      int i;

      if (lastSelection && [lastSelection count]
            && ([lastSelection isEqual: baseNodeArray] == NO)) {
        for (i = 0; i < [lastSelection count]; i++) {
          FSNode *node = [lastSelection objectAtIndex: i];

          if (([node isPlain] == NO) 
                && (([node isPackage] == NO) || [node isApplication])) {
            canopen = NO;
            break;
          }
        }
      } else {
        canopen = NO;
      }

      return canopen;

    } else if (sel_isEqual(action, @selector(newFolder:))
                                  || sel_isEqual(action, @selector(newFile:))) {
      if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
        return [[nodeView shownNode] isWritable];
      }

      return NO;

    } else if (sel_isEqual(action, @selector(setLabelForNodes:))) {
      // Label menu items are enabled when there's a valid selection
      if (lastSelection && [lastSelection count]
            && ([lastSelection isEqual: baseNodeArray] == NO)) {
        return YES;
      }
      return NO;
    } else if (sel_isEqual(action, @selector(showAttributesInspector:))) {
      // Get Info requires at least one selected item (not just the base)
      if (lastSelection && [lastSelection count]
            && ([lastSelection isEqual: baseNodeArray] == NO)) {
        return YES;
      }
      return NO;
    }

    return YES;
  } else {
    SEL action = [menuItem action];
    if (sel_isEqual(action, @selector(makeKeyAndOrderFront:))) {
      return YES;
    }
  }
  
  return NO;
}

- (void)makeThumbnails:(id)sender
{
  NSString *path;

  path = [[nodeView shownNode] path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t makeThumbnails:path];
      [t release];
    }
}

- (void)removeThumbnails:(id)sender
{
  NSString *path;

  path = [[nodeView shownNode] path];
  path = [path stringByResolvingSymlinksInPath];
  if (path)
    {
      Thumbnailer *t;
      
      t = [Thumbnailer sharedThumbnailer];
      [t removeThumbnails:path];
      [t release];
    }
}

@end
