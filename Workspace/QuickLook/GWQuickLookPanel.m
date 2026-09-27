/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#include <stdint.h>
#include <GNUstepGUI/GSDisplayServer.h>

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWQuickLookPanel.h"
#import "GWQuickLookGeometry.h"
#import "GWQuickLookController.h"

#import "FSNode.h"
#import "Contents.h"                 /* TextViewer, GenericView fallbacks */
#import "ContentViewersProtocol.h"
#import "GWViewersManager.h"         /* birth-rect + icon-rect resolution */
#import "X11AppSupport.h"            /* GWX11WindowManager close animation */

/* Stands in for the real Inspector object the bundled ContentViewers (and
 * TextViewer) expect as their "inspector": checked against every class
 * under Inspector/ContentViewers, only -contentsReadyAt: is ever sent
 * back for a path-based display - the data-only viewers (NSTIFFViewer,
 * NSColorViewer, NSRTFViewer, IBViewViewer) never answer YES to
 * -canDisplayPath:, so they are never chosen here and never send
 * -dataContentsReadyForType:useIcon: back.  A no-op is enough: Quick Look
 * has no title/icon strip of its own for a viewer to refresh - the panel
 * sets its own window title directly from the path. */
@interface GWQuickLookViewerHost : NSObject
@end

@implementation GWQuickLookViewerHost
- (void)contentsReadyAt:(NSString *)path
{
}
- (void)dataContentsReadyForType:(NSString *)type useIcon:(NSImage *)icon
{
}
- (id)inspector
{
  return nil;
}
@end

/* Scans exactly the same Library/Bundles ".inspector" locations Inspector's
 * own Contents class scans, and instantiates every principal class that
 * conforms to ContentViewersProtocol.  Kept apart from Contents itself
 * because Contents requires loading its own nib and a live Inspector
 * window (win/titleField/iconView outlets) neither of which Quick Look
 * has any use for - reusing the viewer classes directly is the minimal
 * option (see the sprint brief on hosting a content viewer outside the
 * Inspector). */
static NSMutableArray *
QuickLookLoadContentViewers(void)
{
  NSMutableArray *loaded = [[NSMutableArray alloc] init];
  GWQuickLookViewerHost *host = [[GWQuickLookViewerHost new] autorelease];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *e = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                          NSAllDomainsMask, YES)
                      objectEnumerator];
  NSString *libDir;
  NSRect r = NSMakeRect(0, 0, 1, 1);

  while ((libDir = [e nextObject]) != nil)
    {
      NSString *bundlesDir = [libDir stringByAppendingPathComponent: @"Bundles"];
      NSArray *names = [fm directoryContentsAtPath: bundlesDir];
      NSUInteger i;

      for (i = 0; i < [names count]; i++)
        {
          NSString *name = [names objectAtIndex: i];

          if ([[name pathExtension] isEqual: @"inspector"])
            {
              NSString *path = [bundlesDir stringByAppendingPathComponent: name];
              NSBundle *bundle = [NSBundle bundleWithPath: path];
              Class principalClass = bundle ? [bundle principalClass] : Nil;

              if ([principalClass conformsToProtocol: @protocol(ContentViewersProtocol)])
                {
                  id vwr = [[principalClass alloc] initWithFrame: r inspector: host];

                  if (vwr != nil)
                    {
                      [loaded addObject: vwr];
                      RELEASE(vwr);
                    }
                }
            }
        }
    }

  return loaded;
}

/* Which principal class (if any, out of the cached prototypes) answers YES
 * to -canDisplayPath: for this path.  Only the discovery/capability check
 * uses the cached 1x1 prototypes - the actual displayed instance is always
 * built fresh, at the real content size, by the caller (see the note on
 * QuickLookFreshViewerForPath below on why).
 *
 * ImageViewer is skipped by name (the same string-comparison convention
 * Contents.m itself uses to special-case it) rather than loaded: it hands
 * the decoded image to a SEPARATE resizer process over Distributed Objects
 * and reads the result back asynchronously, sized from its own imageview's
 * bounds at the moment -displayPath: runs.  Built fresh at Quick Look's
 * much larger content size (instead of the Inspector's small, fixed box),
 * that path produced negative-size NSViews and crashed Workspace outright
 * - reproduced with more than one otherwise-valid PNG, so this is a real
 * defect in the bundle's own resize math at this scale, not a fixture
 * artifact.  ImageViewer.m is read-only reused code (Inspector/
 * ContentViewers), so QuickLookImageViewForPath below stands in with a
 * plain, synchronous NSImageView instead. */
static Class
QuickLookViewerClassForPath(NSString *path)
{
  static NSMutableArray *viewers = nil;
  NSUInteger i;

  if (viewers == nil)
    {
      viewers = QuickLookLoadContentViewers();
    }

  for (i = 0; i < [viewers count]; i++)
    {
      id vwr = [viewers objectAtIndex: i];

      if ([NSStringFromClass([vwr class]) isEqualToString: @"ImageViewer"])
        {
          continue;
        }

      if ([vwr canDisplayPath: path])
        {
          return [vwr class];
        }
    }

  return Nil;
}

/* A safe, synchronous stand-in for ImageViewer (see the note above): a
 * plain NSImageView showing the file's contents at its natural aspect
 * ratio, scaled down to fit if larger than the content area. */
static NSView *
QuickLookImageViewForPath(NSString *path, NSRect frame)
{
  NSImage *image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
  NSImageView *imageView = [[[NSImageView alloc] initWithFrame: frame] autorelease];

  [imageView setImage: image];
  [imageView setImageScaling: NSScaleProportionally];
  [imageView setImageFrameStyle: NSImageFrameNone];
  [imageView setEditable: NO];

  return imageView;
}

static BOOL
QuickLookPathIsImage(NSString *path)
{
  NSString *extension = [[path pathExtension] lowercaseString];

  return [[NSImage imageFileTypes] containsObject: extension];
}

/* A ContentViewers bundle class is designed to be built once, at the
 * Inspector's fixed Contents-pane size, and never resized again - some of
 * them (ImageViewer's own NSImageView, sized from [self bounds] at -init
 * and given no resizing mask at all) lay out their subviews only at
 * construction time and never again, so a cached instance built small and
 * stretched afterward stays visibly empty however large its own frame
 * grows.  Quick Look's frame is neither fixed nor Inspector's size, so
 * every display builds a fresh instance at the real, final content size
 * instead of reusing one built small. */
static id
QuickLookFreshViewerForPath(NSString *path, NSRect frame)
{
  Class cls = QuickLookViewerClassForPath(path);
  GWQuickLookViewerHost *host;
  id vwr;

  if (cls == Nil)
    {
      return nil;
    }

  host = [[GWQuickLookViewerHost new] autorelease];
  vwr = [[[cls alloc] initWithFrame: frame inspector: host] autorelease];
  return vwr;
}

static TextViewer *
QuickLookFreshTextViewer(NSRect frame)
{
  GWQuickLookViewerHost *host = [[GWQuickLookViewerHost new] autorelease];

  return [[[TextViewer alloc] initWithFrame: frame forInspector: host] autorelease];
}

static GenericView *
QuickLookFreshGenericView(NSRect frame)
{
  return [[[GenericView alloc] initWithFrame: frame] autorelease];
}

static NSView *
QuickLookMultipleSelectionView(NSUInteger count, NSRect frame)
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame: frame] autorelease];

  [label setStringValue: [NSString stringWithFormat: @"%lu %@",
                                    (unsigned long)count,
                                    NSLocalizedString(@"Items", @"")]];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];
  [label setAlignment: NSCenterTextAlignment];
  [label setFont: [NSFont systemFontOfSize: 18]];
  [label setTextColor: [NSColor grayColor]];

  return label;
}

/* The X11 window id GWViewersManager/X11AppSupport need for the close
 * animation message - the same lookup GWViewersManager.m itself uses for
 * a folder window's close, duplicated here rather than calling into that
 * class (which expects a full GWViewer/GWSpatialViewer "aviewer", not a
 * plain window). */
static unsigned long
QuickLookX11WindowID(NSWindow *window)
{
  GSDisplayServer *server = GSServerForWindow(window);
  void *winptr;

  if (server == nil)
    {
      server = GSCurrentServer();
    }
  if (server == nil)
    {
      return 0;
    }

  winptr = [server windowDevice: [window windowNumber]];
  return (unsigned long)(uintptr_t)winptr;
}

/* Two defensive fixups applied to every content viewer's view tree after
 * -displayPath:/-tryToDisplayPath:/-showInfoOfPath:, without touching the
 * (read-only, reused) viewer classes themselves:
 *
 * - Any NSScrollView is scrolled back to its origin.  A text-based viewer
 *   (TextViewer, RtfViewer, ...) is built and ordinarily used at the
 *   Inspector's small, fixed Contents-pane size; its NSTextView carries
 *   both a content-driven vertical size (-setVerticallyResizable:) and a
 *   plain Height|WidthSizable autoresizing mask, which do not agree once
 *   the view is stretched to Quick Look's much larger frame - the clip
 *   view can end up scrolled to a document position that shows no glyphs.
 *
 * - Any NSTextView left with a nil -textColor (built bare via
 *   -initWithFrame: outside of a nib, which does not seed one the way
 *   AppKit's own nib-loading path does) is given the standard text color
 *   explicitly, or its glyphs paint nothing at all despite the text
 *   genuinely being in its text storage. */
static void
QuickLookFixupContentView(NSView *view)
{
  if ([view isKindOfClass: [NSScrollView class]])
    {
      NSScrollView *scrollView = (NSScrollView *)view;
      NSClipView *clipView = [scrollView contentView];

      [scrollView tile];
      [clipView scrollToPoint: NSZeroPoint];
      [scrollView reflectScrolledClipView: clipView];
      [[scrollView documentView] setNeedsDisplay: YES];
      [scrollView setNeedsDisplay: YES];
    }
  else if ([view isKindOfClass: [NSTextView class]])
    {
      NSTextView *textView = (NSTextView *)view;

      if ([textView textColor] == nil)
        {
          [textView setTextColor: [NSColor textColor]];
        }
    }

  {
    NSEnumerator *e = [[view subviews] objectEnumerator];
    NSView *sub;

    while ((sub = [e nextObject]) != nil)
      {
        QuickLookFixupContentView(sub);
      }
  }
}

@implementation GWQuickLookPanel

- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow
{
  NSScreen *screen = nil;
  NSRect frame;
  unsigned int style = NSTitledWindowMask | NSClosableWindowMask;

  if ([sourceWindow respondsToSelector: @selector(screen)])
    {
      screen = [sourceWindow screen];
    }
  if (screen == nil)
    {
      screen = [NSScreen mainScreen];
    }

  frame = GWQuickLookFrameForVisibleFrame([screen visibleFrame]);

  self = [super initWithContentRect: frame
                           styleMask: style
                             backing: NSBackingStoreBuffered
                               defer: NO
                              screen: screen];
  if (self != nil)
    {
      _sourceWindow = sourceWindow;
      [self setReleasedWhenClosed: NO];
      [self showPaths: paths];
    }

  return self;
}

- (void)dealloc
{
  if ([_currentViewer respondsToSelector: @selector(stopTasks)])
    {
      [_currentViewer stopTasks];
    }
  RELEASE(_currentViewerView);
  RELEASE(_currentPaths);
  [super dealloc];
}

- (void)showPaths:(NSArray *)paths
{
  NSString *path = ([paths count] > 0) ? [paths objectAtIndex: 0] : nil;
  NSRect contentBounds = [[self contentView] bounds];
  NSView *newView;
  id viewer;

  if ([_currentViewer respondsToSelector: @selector(stopTasks)])
    {
      [_currentViewer stopTasks];
    }
  if (_currentViewerView != nil)
    {
      [_currentViewerView removeFromSuperview];
    }

  ASSIGN(_currentPaths, paths);
  _currentViewer = nil;

  if ([paths count] > 1)
    {
      newView = QuickLookMultipleSelectionView([paths count], contentBounds);
      [self setTitle: [NSString stringWithFormat: @"%lu %@",
                                 (unsigned long)[paths count],
                                 NSLocalizedString(@"Items", @"")]];
    }
  else if (path != nil)
    {
      /* Built fresh, at the real content size, every time - see
       * QuickLookFreshViewerForPath on why these classes cannot be built
       * small once and stretched later.  Images go through the plain,
       * synchronous stand-in instead of the bundle's ImageViewer - see
       * QuickLookViewerClassForPath on why. */
      if (QuickLookPathIsImage(path))
        {
          newView = QuickLookImageViewForPath(path, contentBounds);
        }
      else if ((viewer = QuickLookFreshViewerForPath(path, contentBounds)) != nil)
        {
          [viewer displayPath: path];
          newView = viewer;
        }
      else
        {
          TextViewer *textViewer = QuickLookFreshTextViewer(contentBounds);

          if ([textViewer tryToDisplayPath: path])
            {
              newView = textViewer;
            }
          else
            {
              GenericView *genericView = QuickLookFreshGenericView(contentBounds);

              [genericView showInfoOfPath: path];
              newView = genericView;
            }
        }

      _currentViewer = newView;
      [self setTitle: [[FSNode nodeWithPath: path] name]];
    }
  else
    {
      newView = [[[NSView alloc] initWithFrame: contentBounds] autorelease];
      [self setTitle: @""];
    }

  [newView setFrame: contentBounds];
  [newView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
  [[self contentView] addSubview: newView];
  ASSIGN(_currentViewerView, newView);
  QuickLookFixupContentView(newView);
}

- (void)showAnimated
{
  FSNode *node = ([_currentPaths count] == 1)
    ? [FSNode nodeWithPath: [_currentPaths objectAtIndex: 0]] : nil;
  NSRect target = [self frame];
  NSRect source = (node != nil)
    ? [[GWViewersManager viewersManager] resolveIconScreenRectForNode: node]
    : NSZeroRect;

  if (!NSIsEmptyRect(source))
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
}

- (void)closeAnimated
{
  if ([_currentViewer respondsToSelector: @selector(stopTasks)])
    {
      [_currentViewer stopTasks];
    }

  if ([[GWX11WindowManager sharedManager] windowManagerSupportsWindowAnimation])
    {
      FSNode *node = ([_currentPaths count] == 1)
        ? [FSNode nodeWithPath: [_currentPaths objectAtIndex: 0]] : nil;
      NSRect target = (node != nil)
        ? [[GWViewersManager viewersManager] resolveIconScreenRectForNode: node]
        : NSZeroRect;
      unsigned long xwindow = QuickLookX11WindowID(self);

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

/* Space and Escape close Quick Look - checked before the first responder
 * (mirroring how GWViewerWindow -performKeyEquivalent: catches the same
 * Space bar), so it works regardless of which subview inside the panel
 * currently has focus. */
- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];

  if ([characters length] > 0)
    {
      unichar character = [characters characterAtIndex: 0];

      if (character == ' ' || character == 0x1B)
        {
          [[GWQuickLookController sharedController] close];
          return YES;
        }
    }

  return [super performKeyEquivalent: theEvent];
}

/* Route every close - including the titlebar [x] button - through the
 * controller, so its isOpen state (and the "second Space closes" rule)
 * stays correct no matter how the window was closed. */
- (void)performClose:(id)sender
{
  [[GWQuickLookController sharedController] close];
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *characters = [theEvent characters];
  unichar character = ([characters length] > 0) ? [characters characterAtIndex: 0] : 0;

  if (character == NSUpArrowFunctionKey || character == NSDownArrowFunctionKey
      || character == NSLeftArrowFunctionKey || character == NSRightArrowFunctionKey)
    {
      /* The folder window's own view (icon/list/browser) already knows
       * how to move its selection; forwarding the raw event there is
       * cheaper and more correct than reimplementing arrow-key selection
       * here, and it is what makes the shown item follow the arrow keys
       * while Quick Look is open. */
      id responder = nil;

      if ([_sourceWindow respondsToSelector: @selector(firstResponder)])
        {
          responder = [_sourceWindow firstResponder];
        }

      if ([responder respondsToSelector: @selector(keyDown:)])
        {
          id del = nil;

          [responder keyDown: theEvent];

          if ([_sourceWindow respondsToSelector: @selector(delegate)])
            {
              del = [_sourceWindow delegate];
            }
          if ([del respondsToSelector: @selector(lastSelection)])
            {
              NSArray *selection = [del lastSelection];

              if ([selection count] > 0)
                {
                  [self showPaths: [selection valueForKey: @"path"]];
                }
            }
        }

      return;
    }

  [super keyDown: theEvent];
}

@end
