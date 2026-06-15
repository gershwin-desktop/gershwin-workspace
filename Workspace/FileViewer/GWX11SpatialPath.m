/* GWX11SpatialPath.m
 *
 * Implementation of X11 atom-based spatial path communication.
 *
 * On GNUstep's X11 backend, [NSWindow windowRef] returns the native
 * X11 Window ID.  We open our own Display connection to set/read
 * atoms so we don't interfere with the AppKit event loop.
 */

#import "GWX11SpatialPath.h"
#import "FSNode.h"
#import "GWViewerWindow.h"

#include <X11/Xlib.h>

/* Forward declarations to avoid pulling in headers with type issues */
@class GWViewersManager;
#include <X11/Xatom.h>
#include <X11/Xutil.h>

/* Atom names */
#define GW_ATOM_SPATIAL_PATH     "_GW_SPATIAL_PATH"
#define GW_ATOM_SPATIAL_NAVIGATE "_GW_SPATIAL_NAVIGATE"

/* Polling interval for navigation requests (seconds) */
#define GW_NAVIGATE_POLL_INTERVAL 0.5

/* Custom X error handler to prevent crashes from BadWindow */
static int gwX11ErrorHandler(Display *dpy, XErrorEvent *event)
{
  char errorText[256];
  XGetErrorText(dpy, event->error_code, errorText, sizeof(errorText));
  NSDebugLLog(@"gwspace", @"GWX11SpatialPath X11 error: %s (request %d, error %d)",
        errorText, event->request_code, event->error_code);
  return 0;
}

static BOOL x11HandlerInstalled = NO;

static void ensureErrorHandler(void)
{
  if (!x11HandlerInstalled) {
    XSetErrorHandler(gwX11ErrorHandler);
    x11HandlerInstalled = YES;
  }
}

@interface GWX11SpatialPath (Private)
- (void)navigateToPath:(NSString *)targetPath;
@end

@implementation GWX11SpatialPath

- (instancetype)initWithWindow:(NSWindow *)window path:(NSString *)path
{
  self = [super init];
  if (!self) return nil;

  _window = window;
  _currentPath = [path copy];

  /* Set the initial atom value after a short delay to ensure
   * the window is fully mapped and windowRef is valid. */
  [self performSelector:@selector(setInitialAtom)
             withObject:nil
             afterDelay:0.1];

  return self;
}

- (void)setInitialAtom
{
  if (!_window || !_currentPath)
    return;

  ensureErrorHandler();

  [self updateAtomWithPath:_currentPath];
  [self clearNavigateAtom];

  /* Start polling for navigation requests */
  _pollTimer = [NSTimer scheduledTimerWithTimeInterval:GW_NAVIGATE_POLL_INTERVAL
                                                target:self
                                              selector:@selector(pollNavigateAtom:)
                                              userInfo:nil
                                               repeats:YES];
}

- (void)dealloc
{
  [self invalidate];
  RELEASE(_currentPath);
  [super dealloc];
}

- (void)setPath:(NSString *)path
{
  if (path == nil || [_currentPath isEqual:path])
    return;

  RELEASE(_currentPath);
  _currentPath = [path copy];
  [self updateAtomWithPath:_currentPath];
}

- (void)invalidate
{
  if (_pollTimer) {
    [_pollTimer invalidate];
    _pollTimer = nil;
  }
  _window = nil;
}

#pragma mark - X11 Atom Operations

/* Get the X11 Window ID from the NSWindow.
 * On GNUstep's X11 backend, -windowRef returns the X11 Window. */
- (Window)x11Window
{
  if (!_window) return (Window)0;
  return (Window)[_window windowRef];
}

/* Open a temporary display connection for X11 operations */
- (Display *)openDisplay
{
  ensureErrorHandler();
  return XOpenDisplay(NULL);
}

/* Set _GW_SPATIAL_PATH to the given path string */
- (void)updateAtomWithPath:(NSString *)path
{
  Display *dpy = [self openDisplay];
  if (!dpy) {
    NSLog(@"GWX11SpatialPath: Cannot open display to set atom");
    return;
  }

  Window xid = [self x11Window];
  if (!xid) {
    XCloseDisplay(dpy);
    return;
  }

  Atom atom = XInternAtom(dpy, GW_ATOM_SPATIAL_PATH, False);
  Atom utf8Atom = XInternAtom(dpy, "UTF8_STRING", False);
  const char *cpath = [path UTF8String];

  XChangeProperty(dpy, xid, atom, utf8Atom, 8, PropModeReplace,
                  (unsigned char *)cpath, (int)strlen(cpath));
  XSync(dpy, False);

  NSDebugLLog(@"gwspace", @"GWX11SpatialPath: Set %s on window 0x%lx to '%@'",
              GW_ATOM_SPATIAL_PATH, (unsigned long)xid, path);

  XCloseDisplay(dpy);
}

/* Delete _GW_SPATIAL_NAVIGATE to clear a stale request */
- (void)clearNavigateAtom
{
  Display *dpy = [self openDisplay];
  if (!dpy) return;

  Window xid = [self x11Window];
  if (!xid) {
    XCloseDisplay(dpy);
    return;
  }

  Atom atom = XInternAtom(dpy, GW_ATOM_SPATIAL_NAVIGATE, False);
  XDeleteProperty(dpy, xid, atom);
  XSync(dpy, False);

  XCloseDisplay(dpy);
}

/* Poll for _GW_SPATIAL_NAVIGATE requests from the WM */
- (void)pollNavigateAtom:(NSTimer *)timer
{
  if (!_window) {
    [timer invalidate];
    return;
  }

  Display *dpy = [self openDisplay];
  if (!dpy) return;

  Window xid = [self x11Window];
  if (!xid) {
    XCloseDisplay(dpy);
    return;
  }

  Atom navAtom = XInternAtom(dpy, GW_ATOM_SPATIAL_NAVIGATE, False);
  Atom utf8Atom = XInternAtom(dpy, "UTF8_STRING", False);
  Atom actual_type;
  int actual_format;
  unsigned long nitems, bytes_after;
  unsigned char *data = NULL;
  NSString *targetPath = nil;

  if (XGetWindowProperty(dpy, xid, navAtom, 0, 4096, True,
                         utf8Atom, &actual_type, &actual_format,
                         &nitems, &bytes_after, &data) == Success && data && nitems > 0) {
    targetPath = [[NSString alloc] initWithUTF8String:(const char *)data];
    XFree(data);
  }

  XSync(dpy, False);
  XCloseDisplay(dpy);

  if (targetPath) {
    if ([targetPath length] > 0) {
      NSDebugLLog(@"gwspace", @"GWX11SpatialPath: Navigate request to '%@'", targetPath);
      [self navigateToPath:targetPath];
    }
    RELEASE(targetPath);
  }
}

/* Navigate to the requested path using the viewers manager */
- (void)navigateToPath:(NSString *)targetPath
{
  if (!targetPath || !_window) return;

  /* The (True) flag in XGetWindowProperty already deleted the property,
   * so we won't process the same request twice. */

  /* Find the viewer delegate and check it's spatial */
  id delegate = [(GWViewerWindow *)_window delegate];

  if (!delegate || ![delegate respondsToSelector:@selector(isSpatial)])
    return;

  if (![delegate isSpatial])
    return;

  FSNode *currentBase = nil;
  if ([delegate respondsToSelector:@selector(baseNode)]) {
    currentBase = [delegate baseNode];
  }
  NSString *currentPath = [currentBase path];

  if ([targetPath isEqualToString:currentPath])
    return;

  FSNode *targetNode = [FSNode nodeWithPath:targetPath];
  if (!targetNode || ![targetNode isValid])
    return;

  /* Use runtime lookup to reach GWViewersManager without importing its header.
   * The method viewerOfType:showType:forNode:showSelection:closeOldViewer:forceNew:
   * takes: (unsigned vtype, NSString *stype, FSNode *node, BOOL showsel, id oldvwr, BOOL force) */
  Class mgrClass = NSClassFromString(@"GWViewersManager");
  if (!mgrClass) return;

  id manager = nil;
  SEL sharedSel = NSSelectorFromString(@"viewersManager");
  if ([mgrClass respondsToSelector:sharedSel]) {
    manager = [mgrClass performSelector:sharedSel];
  }
  if (!manager) return;

  SEL actionSel = NSSelectorFromString(@"viewerOfType:showType:forNode:showSelection:closeOldViewer:forceNew:");
  if (![manager respondsToSelector:actionSel]) return;

  NSMethodSignature *sig = [manager methodSignatureForSelector:actionSel];
  if (!sig) return;

  NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
  [inv setSelector:actionSel];
  [inv setTarget:manager];

  unsigned vtypeVal = 1;  /* SPATIAL = 1 */
  id nilStr = nil;        /* showType:nil */
  BOOL noVal = NO;

  [inv setArgument:&vtypeVal atIndex:2];
  [inv setArgument:&nilStr atIndex:3];
  [inv setArgument:&targetNode atIndex:4];
  [inv setArgument:&noVal atIndex:5];
  [inv setArgument:&delegate atIndex:6];
  [inv setArgument:&noVal atIndex:7];

  [inv invoke];
}

@end
