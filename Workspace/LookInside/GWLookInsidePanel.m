/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#include <stdint.h>
#ifndef _WIN32
#include <X11/Xlib.h>
#endif
#include <GNUstepGUI/GSDisplayServer.h>

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWLookInsidePanel.h"
#import "GWLookInsideGeometry.h"
#import "GWLookInsideController.h"
#import "GWLookInsideKeys.h"
#import "GWLookInsidePreviewView.h"
#import "GWLookInsideOverviewView.h"

#import "FSNode.h"
#import "Workspace.h"                /* opening an item like a double-click */
#import "GWViewersManager.h"         /* birth-rect + icon-rect resolution */
#import "X11AppSupport.h"            /* GWX11WindowManager close animation */
#import "GWFunctions.h"              /* frameRectForScreenContentRect() */
#import "AppearanceMetrics.h"

#define LIString(key, comment) NSLocalizedStringFromTable(key, @"LookInside", comment)

/* Where the panel's size is remembered between openings (screen units, as
 * -frame gives them). */
static NSString * const kFrameSizeDefault = @"GWLookInsideFrameSize";

/* The control strip under the preview: one row of standard buttons with
 * METRICS_SPACE_8 above and below. */
static const CGFloat kStripHeight = METRICS_SPACE_8 + METRICS_BUTTON_HEIGHT + METRICS_SPACE_8;
static const CGFloat kArrowButtonWidth = 28.0;
static const CGFloat kCountFieldWidth = 80.0;

static unsigned long
LookInsideX11WindowID(NSWindow *window)
{
  GSDisplayServer *server = GSServerForWindow(window);

  if (server == nil)
    {
      return 0;
    }
  return (unsigned long)(uintptr_t)[server windowDevice: [window windowNumber]];
}

/* Real full screen is the window manager's: it takes the decorations
 * away, covers the menu bar and the Dock, and restores the frame
 * afterwards.  Moving the window to the screen frame at a higher level
 * leaves the title bar, menu bar and Dock on top (gnustep-media-playback). */
static BOOL
LookInsideRequestFullScreen(NSWindow *window, BOOL fullScreen)
{
#ifdef _WIN32
  /* No X window manager to ask on Windows; the caller keeps the panel
   * windowed. */
  return NO;
#else
  GSDisplayServer *server = GSServerForWindow(window);
  Display *dpy = (server != nil) ? (Display *)[server serverDevice] : NULL;
  unsigned long xwindow = LookInsideX11WindowID(window);
  XEvent event;

  if (dpy == NULL || xwindow == 0)
    {
      return NO;
    }

  memset(&event, 0, sizeof(event));
  event.xclient.type = ClientMessage;
  event.xclient.window = (Window)xwindow;
  event.xclient.message_type = XInternAtom(dpy, "_NET_WM_STATE", False);
  event.xclient.format = 32;
  event.xclient.data.l[0] = fullScreen ? 1 : 0;   /* _NET_WM_STATE_ADD / _REMOVE */
  event.xclient.data.l[1] = (long)XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", False);
  event.xclient.data.l[3] = 1;                    /* source: application */
  XSendEvent(dpy, DefaultRootWindow(dpy), False,
             SubstructureRedirectMask | SubstructureNotifyMask, &event);
  XFlush(dpy);
  return YES;
#endif
}

static NSButton *
MakeButton(NSString *title, SEL action, id target, unsigned int mask)
{
  NSButton *button = [[NSButton alloc] initWithFrame: NSZeroRect];

  [button setButtonType: NSMomentaryPushInButton];
  [button setBezelStyle: NSRoundedBezelStyle];
  [button setTitle: title];
  [button setTarget: target];
  [button setAction: action];
  [button setAutoresizingMask: mask];
  return button;
}

@implementation GWLookInsidePanel

- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow
{
  NSScreen *screen = nil;
  unsigned int style = NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask;

  if ([sourceWindow respondsToSelector: @selector(screen)])
    {
      screen = [sourceWindow screen];
    }
  if (screen == nil)
    {
      screen = [NSScreen mainScreen];
    }

  /* Constructed at NSZeroRect and resized right after, exactly like
   * GWViewerWindow's own -init: NSScreen's -visibleFrame is already in
   * device pixels here (gnustep-scale-factor-pitfalls), while
   * -initWithContentRect:.../-frameRectForContentRect: take their SIZE in
   * points and multiply it by GSScaleFactor - handing the pixel rect
   * straight to the initializer would double it at any scale other than
   * 1.0.  frameRectForScreenContentRect() (Workspace/GWFunctions.m) is the
   * same helper GWViewer.m uses to place a window from a pixel rect. */
  self = [super initWithContentRect: NSZeroRect
                          styleMask: style
                            backing: NSBackingStoreBuffered
                              defer: NO
                             screen: screen];
  if (self != nil)
    {
      NSRect visible = [screen visibleFrame];
      NSRect defaultFrame = frameRectForScreenContentRect(self,
        GWLookInsideFrameForVisibleFrame(visible));
      NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey: kFrameSizeDefault];
      NSSize savedSize = (saved != nil) ? NSSizeFromString(saved) : NSZeroSize;

      [self setFrame: GWLookInsideFrameForSavedSize(visible, savedSize, defaultFrame)
             display: NO];

      _sourceWindow = sourceWindow;
      [self setReleasedWhenClosed: NO];
      [self buildContent];
      [self showPaths: paths];
    }

  return self;
}

- (void)dealloc
{
  [_preview stopTasks];
  RELEASE(_paths);
  RELEASE(_preview);
  RELEASE(_overview);
  RELEASE(_previousButton);
  RELEASE(_nextButton);
  RELEASE(_countField);
  RELEASE(_overviewButton);
  RELEASE(_fullScreenButton);
  RELEASE(_openButton);
  [super dealloc];
}

- (void)buildContent
{
  NSView *content = [self contentView];
  NSRect bounds = [content bounds];
  NSRect area = NSMakeRect(0, kStripHeight, NSWidth(bounds), NSHeight(bounds) - kStripHeight);

  _preview = [[GWLookInsidePreviewView alloc] initWithFrame: area
                                                      style: GWLookInsidePreviewStyleFull];
  [_preview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [content addSubview: _preview];

  _overview = [[GWLookInsideOverviewView alloc] initWithFrame: area];
  [_overview setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [_overview setTarget: self];
  [_overview setAction: @selector(overviewPicked:)];

  _previousButton = MakeButton(LIString(@"Previous", @"Shows the previous item"),
                               @selector(showPrevious:), self, NSViewMaxXMargin);
  [_previousButton setImage: [NSImage imageNamed: @"common_ArrowLeft"]];
  [_previousButton setImagePosition: NSImageOnly];
  [content addSubview: _previousButton];

  _nextButton = MakeButton(LIString(@"Next", @"Shows the next item"),
                           @selector(showNext:), self, NSViewMaxXMargin);
  [_nextButton setImage: [NSImage imageNamed: @"common_ArrowRight"]];
  [_nextButton setImagePosition: NSImageOnly];
  [content addSubview: _nextButton];

  _countField = [[NSTextField alloc] initWithFrame: NSZeroRect];
  [_countField setEditable: NO];
  [_countField setSelectable: NO];
  [_countField setBezeled: NO];
  [_countField setDrawsBackground: NO];
  [_countField setFont: METRICS_FONT_SYSTEM_REGULAR_11];
  [_countField setAutoresizingMask: NSViewMaxXMargin];
  [content addSubview: _countField];

  _overviewButton = MakeButton(LIString(@"All Items", @"Shows all items side by side"),
                               @selector(toggleOverview:), self, NSViewMaxXMargin);
  /* Stays pressed while the overview is up, so the way back is obvious. */
  [_overviewButton setButtonType: NSPushOnPushOffButton];
  [content addSubview: _overviewButton];

  _openButton = MakeButton(@"", @selector(openCurrentItem:), self, NSViewMinXMargin);
  [content addSubview: _openButton];

  _fullScreenButton = MakeButton(LIString(@"Full Screen", @"Fills the screen with the preview"),
                                 @selector(toggleFullScreen:), self, NSViewMinXMargin);
  [content addSubview: _fullScreenButton];
}

static CGFloat
ButtonWidth(NSButton *button)
{
  [button sizeToFit];
  return MAX(ceil(NSWidth([button frame])) + METRICS_SPACE_16, METRICS_BUTTON_MIN_WIDTH);
}

/* Horizontal positions only change with what is shown; the vertical ones
 * and the anchoring come from the autoresizing masks. */
- (void)layoutStrip
{
  NSRect bounds = [[self contentView] bounds];
  BOOL several = ([_paths count] > 1);
  CGFloat y = METRICS_SPACE_8;
  CGFloat x = METRICS_CONTENT_SIDE_MARGIN;
  CGFloat right = NSMaxX(bounds) - METRICS_CONTENT_SIDE_MARGIN;
  CGFloat w;

  [_previousButton setHidden: !several];
  [_nextButton setHidden: !several];
  [_countField setHidden: !several];
  [_overviewButton setHidden: !several];

  if (several)
    {
      [_previousButton setFrame: NSMakeRect(x, y, kArrowButtonWidth, METRICS_BUTTON_HEIGHT)];
      /* -1: the two outlines coincide into one line (gershwin-ui-metrics). */
      x += kArrowButtonWidth - 1;
      [_nextButton setFrame: NSMakeRect(x, y, kArrowButtonWidth, METRICS_BUTTON_HEIGHT)];
      x += kArrowButtonWidth + METRICS_SPACE_8;
      [_countField setFrame: NSMakeRect(x, y + 2, kCountFieldWidth, METRICS_BUTTON_HEIGHT - 4)];
      x += kCountFieldWidth + METRICS_SPACE_8;
      w = ButtonWidth(_overviewButton);
      [_overviewButton setFrame: NSMakeRect(x, y, w, METRICS_BUTTON_HEIGHT)];
    }

  w = ButtonWidth(_openButton);
  right -= w;
  [_openButton setFrame: NSMakeRect(right, y, w, METRICS_BUTTON_HEIGHT)];
  w = ButtonWidth(_fullScreenButton);
  right -= METRICS_BUTTON_HORIZ_INTERSPACE + w;
  [_fullScreenButton setFrame: NSMakeRect(right, y, w, METRICS_BUTTON_HEIGHT)];
  [[self contentView] setNeedsDisplay: YES];
}

- (NSString *)currentPath
{
  return (_index < [_paths count]) ? [_paths objectAtIndex: _index] : nil;
}

- (NSString *)openButtonTitle
{
  NSString *path = [self currentPath];
  FSNode *node = (path != nil) ? [FSNode nodeWithPath: path] : nil;
  NSString *app = nil;
  NSString *type = nil;

  /* A folder opens in Workspace itself, which needs no naming. */
  if (node == nil || ([node isDirectory] && ![node isPackage]) || [node isApplication])
    {
      return LIString(@"Open", @"Opens the shown item");
    }
  [[NSWorkspace sharedWorkspace] getInfoForFile: path application: &app type: &type];
  if ([app length] == 0)
    {
      return LIString(@"Open", @"Opens the shown item");
    }
  return [NSString stringWithFormat: LIString(@"Open with %@", @"Opens the shown item with the named application"),
                   [[app lastPathComponent] stringByDeletingPathExtension]];
}

- (void)updateTitleAndControls
{
  NSUInteger count = [_paths count];
  NSString *path = [self currentPath];

  if (_overviewShown)
    {
      [self setTitle: [NSString stringWithFormat: LIString(@"%lu Items", @"Title of the overview of several items"),
                                (unsigned long)count]];
    }
  else
    {
      [self setTitle: (path != nil) ? [[FSNode nodeWithPath: path] name] : @""];
    }
  [_countField setStringValue: [NSString stringWithFormat:
    LIString(@"%lu of %lu", @"Which of several items is shown"),
    (unsigned long)(_index + 1), (unsigned long)count]];
  [_overviewButton setState: _overviewShown ? NSOnState : NSOffState];
  [_openButton setTitle: [self openButtonTitle]];
  [_fullScreenButton setTitle: _fullScreen
    ? LIString(@"Exit Full Screen", @"Leaves full screen")
    : LIString(@"Full Screen", @"Fills the screen with the preview")];
  [self layoutStrip];
}

- (void)showCurrentItem
{
  [_preview showPath: [self currentPath]];
  [self updateTitleAndControls];
}

- (void)showPaths:(NSArray *)paths
{
  ASSIGN(_paths, paths);
  _index = 0;
  if (_overviewShown)
    {
      [self setOverviewShown: NO];
    }
  [_overview setPaths: paths];
  [self showCurrentItem];
}

- (void)stepBy:(NSInteger)delta
{
  _index = GWLookInsideStepIndex(_index, [_paths count], delta);
  if (_overviewShown)
    {
      [_overview setHighlightedIndex: _index];
      [self updateTitleAndControls];
    }
  else
    {
      [self showCurrentItem];
    }
}

- (void)showNext:(id)sender
{
  [self stepBy: 1];
}

- (void)showPrevious:(id)sender
{
  [self stepBy: -1];
}

- (void)setOverviewShown:(BOOL)shown
{
  NSView *content = [self contentView];

  _overviewShown = shown;
  if (shown)
    {
      [_preview stopTasks];
      [_overview setFrame: [_preview frame]];
      [_overview setHighlightedIndex: _index];
      [content replaceSubview: _preview with: _overview];
    }
  else
    {
      [_preview setFrame: [_overview frame]];
      [content replaceSubview: _overview with: _preview];
    }
}

- (void)toggleOverview:(id)sender
{
  if ([_paths count] < 2)
    {
      return;
    }
  if (_overviewShown)
    {
      _index = [_overview highlightedIndex];
      [self setOverviewShown: NO];
      [self showCurrentItem];
    }
  else
    {
      [self setOverviewShown: YES];
      [self updateTitleAndControls];
    }
}

- (void)overviewPicked:(id)sender
{
  [self toggleOverview: sender];
}

- (void)toggleFullScreen:(id)sender
{
  if (LookInsideRequestFullScreen(self, !_fullScreen))
    {
      _fullScreen = !_fullScreen;
      [self updateTitleAndControls];
    }
}

- (void)openCurrentItem:(id)sender
{
  NSString *path = [self currentPath];

  if (path == nil)
    {
      return;
    }
  [[Workspace gworkspace] openSelectedPaths: [NSArray arrayWithObject: path] newViewer: NO];
  [[GWLookInsideController sharedController] close];
}

- (void)showAnimatedInFullScreen:(BOOL)fullScreen
{
  NSString *path = [self currentPath];
  FSNode *node = (path != nil) ? [FSNode nodeWithPath: path] : nil;
  NSRect target = [self frame];
  NSRect source = (node != nil)
    ? [[GWViewersManager viewersManager] resolveIconScreenRectForNode: node]
    : NSZeroRect;

  if (!NSIsEmptyRect(source) && !fullScreen)
    {
      /* X property the WindowManager reads to run the birth animation
       * when -makeKeyAndOrderFront: below maps the window - see
       * gershwin-windowmanager/ANIMATIONS.md. */
      [[GWViewersManager viewersManager] setWindowBirthRect: source
                                                  targetRect: target
                                               animationType: 0
                                                   forWindow: self];
    }

  [self makeKeyAndOrderFront: nil];
  if (fullScreen)
    {
      [self toggleFullScreen: nil];
    }
}

- (void)closeAnimated
{
  [_preview stopTasks];

  /* A full-screen frame is the screen's, not a size the user chose. */
  if (!_fullScreen)
    {
      [[NSUserDefaults standardUserDefaults] setObject: NSStringFromSize([self frame].size)
                                                forKey: kFrameSizeDefault];
    }

  if ([[GWX11WindowManager sharedManager] windowManagerSupportsWindowAnimation])
    {
      NSString *path = [self currentPath];
      FSNode *node = (path != nil) ? [FSNode nodeWithPath: path] : nil;
      NSRect target = (node != nil)
        ? [[GWViewersManager viewersManager] resolveIconScreenRectForNode: node]
        : NSZeroRect;
      unsigned long xwindow = LookInsideX11WindowID(self);

      /* Sent while still mapped; the WM shrinks/fades on the UnmapNotify
       * that -close (below) causes, or falls back to a plain fade when
       * the icon is no longer visible anywhere (NSZeroRect target). */
      if (xwindow != 0)
        {
          [[GWX11WindowManager sharedManager] animateWindowClose: xwindow
                                                       targetRect: target];
        }
    }

  [self close];
}

/* Route every close - including the titlebar [x] button - through the
 * controller, so its isOpen state (and the "second Space closes" rule)
 * stays correct no matter how the window was closed. */
- (void)performClose:(id)sender
{
  [[GWLookInsideController sharedController] close];
}

/* The folder window's own view (icon/list/browser) already knows how to
 * move its selection; handing it the arrow key is cheaper and more correct
 * than reimplementing selection here.  The new selection is read back
 * from whichever of the two selection accessors the source answers, since
 * the Desktop does not report its selection to Workspace. */
- (void)forwardToSourceWindow:(NSEvent *)theEvent
{
  id responder = nil;
  NSArray *selection = nil;
  id del;

  if ([_sourceWindow respondsToSelector: @selector(firstResponder)])
    {
      responder = [_sourceWindow firstResponder];
    }
  if (![responder respondsToSelector: @selector(keyDown:)])
    {
      return;
    }
  [responder keyDown: theEvent];

  del = [_sourceWindow respondsToSelector: @selector(delegate)] ? [_sourceWindow delegate] : nil;
  if ([responder respondsToSelector: @selector(selectedNodes)])
    {
      selection = [responder selectedNodes];
    }
  else if ([del respondsToSelector: @selector(lastSelection)])
    {
      selection = [del lastSelection];
    }
  selection = [GWLookInsideController selectionPathsOfNodes: selection
                                                   baseNode: [del respondsToSelector: @selector(baseNode)]
                                                             ? [del baseNode] : nil];
  if ([selection count] > 0)
    {
      [[GWLookInsideController sharedController] selectionDidChange: selection];
    }
}

/* Every key goes through the Look Inside key map before the first
 * responder sees it, so Space, Escape and the arrows work the same
 * whether the text of a preview or a button has the focus. */
- (void)sendEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSKeyDown && [[theEvent characters] length] > 0)
    {
      unsigned int flags = [theEvent modifierFlags];
      GWLookInsideKeyAction action =
        GWLookInsideActionForKey([[theEvent characters] characterAtIndex: 0],
                                 (flags & NSCommandKeyMask) != 0,
                                 (flags & NSAlternateKeyMask) != 0,
                                 [_paths count], _overviewShown);

      switch (action)
        {
        case GWLookInsideKeyActionClose:
          [[GWLookInsideController sharedController] close];
          return;
        case GWLookInsideKeyActionNext:
          [self showNext: nil];
          return;
        case GWLookInsideKeyActionPrevious:
          [self showPrevious: nil];
          return;
        case GWLookInsideKeyActionForwardToViewer:
          [self forwardToSourceWindow: theEvent];
          return;
        case GWLookInsideKeyActionToggleOverview:
          [self toggleOverview: nil];
          return;
        case GWLookInsideKeyActionToggleFullScreen:
          [self toggleFullScreen: nil];
          return;
        case GWLookInsideKeyActionOpen:
          [self openCurrentItem: nil];
          return;
        case GWLookInsideKeyActionNone:
        default:
          break;
        }
    }
  [super sendEvent: theEvent];
}

@end
