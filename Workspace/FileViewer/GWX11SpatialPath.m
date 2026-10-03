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

#ifndef _WIN32

#include <X11/Xlib.h>

/* Forward declarations to avoid pulling in headers with type issues */
@class GWViewersManager;
@interface NSObject (GWX11SpatialPathDelegateMethods)
- (BOOL)isSpatial;
- (FSNode *)baseNode;
@end
#include <X11/Xatom.h>
#include <X11/Xutil.h>

/* Atom names */
#define GW_ATOM_SPATIAL_PATH     "_GW_SPATIAL_PATH"
#define GW_ATOM_SPATIAL_NAVIGATE "_GW_SPATIAL_NAVIGATE"

/* Polling interval for navigation requests (seconds) */
#define GW_NAVIGATE_POLL_INTERVAL 1.0

/* XSetErrorHandler is process-global: installing a handler here for the
 * whole run would also swallow errors on AppKit's own X connection and
 * defeat libs-back's XGErrorHandler (its BadMatch/SetInputFocus retry and
 * its exceptions for real protocol errors - see XGServerEvent.m).  Our own
 * window can legitimately vanish between us reading its id and the X
 * server acting on it (the WM tears it down on close), which is the one
 * error we need to swallow, and only around our own calls: save whatever
 * handler is currently installed, swap ours in, make the calls, then put
 * the previous handler straight back (the pattern libs-back itself uses
 * in xutil.c around XShmAttach). */
static XErrorHandler previousX11ErrorHandler = NULL;

static int gwX11ErrorHandler(Display *dpy, XErrorEvent *event)
{
  if (event->error_code == BadWindow) {
    return 0;
  }
  if (previousX11ErrorHandler != NULL) {
    return previousX11ErrorHandler(dpy, event);
  }
  return 0;
}

static void beginIgnoringBadWindow(void)
{
  previousX11ErrorHandler = XSetErrorHandler(gwX11ErrorHandler);
}

static void endIgnoringBadWindow(void)
{
  XSetErrorHandler(previousX11ErrorHandler);
  previousX11ErrorHandler = NULL;
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
  if (_dpy) {
    XCloseDisplay(_dpy);
    _dpy = NULL;
  }
}

#pragma mark - X11 Atom Operations

/* Get the X11 Window ID from the NSWindow.
 * On GNUstep's X11 backend, -windowRef returns the X11 Window. */
- (Window)x11Window
{
  if (!_window) return (Window)0;
  return (Window)[_window windowRef];
}

/* A persistent X connection for the atom operations.  Opening and closing an X
 * connection per operation (the previous behaviour) adds a handshake + sync
 * round-trip to every atom read/write; the poll tick ran one of each every
 * 0.5s on the main thread.  One connection is reused instead, closed in
 * invalidate/dealloc.  Only the main thread uses this object, so the
 * connection needs no locking. */
- (Display *)display
{
  if (_dpy == NULL) {
    _dpy = XOpenDisplay(NULL);
  }
  return _dpy;
}

/* Set _GW_SPATIAL_PATH to the given path string */
- (void)updateAtomWithPath:(NSString *)path
{
  Display *dpy = [self display];
  if (!dpy) {
    NSLog(@"GWX11SpatialPath: Cannot open display to set atom");
    return;
  }

  Window xid = [self x11Window];
  if (!xid) {
    return;
  }

  Atom atom = XInternAtom(dpy, GW_ATOM_SPATIAL_PATH, False);
  Atom utf8Atom = XInternAtom(dpy, "UTF8_STRING", False);
  const char *cpath = [path UTF8String];

  beginIgnoringBadWindow();
  XChangeProperty(dpy, xid, atom, utf8Atom, 8, PropModeReplace,
                  (unsigned char *)cpath, (int)strlen(cpath));
  XSync(dpy, False);
  endIgnoringBadWindow();
}

/* Delete _GW_SPATIAL_NAVIGATE to clear a stale request */
- (void)clearNavigateAtom
{
  Display *dpy = [self display];
  if (!dpy) return;

  Window xid = [self x11Window];
  if (!xid) {
    return;
  }

  Atom atom = XInternAtom(dpy, GW_ATOM_SPATIAL_NAVIGATE, False);
  beginIgnoringBadWindow();
  XDeleteProperty(dpy, xid, atom);
  XSync(dpy, False);
  endIgnoringBadWindow();
}

/* Poll for _GW_SPATIAL_NAVIGATE requests from the WM */
- (void)pollNavigateAtom:(NSTimer *)timer
{
  if (!_window) {
    [timer invalidate];
    return;
  }

  Display *dpy = [self display];
  if (!dpy) {
    /* Cannot reach the X server; stop polling rather than hammering it. */
    [timer invalidate];
    return;
  }

  Window xid = [self x11Window];
  if (!xid) {
    return;
  }

  Atom navAtom = XInternAtom(dpy, GW_ATOM_SPATIAL_NAVIGATE, False);
  Atom utf8Atom = XInternAtom(dpy, "UTF8_STRING", False);
  Atom actual_type;
  int actual_format;
  unsigned long nitems, bytes_after;
  unsigned char *data = NULL;
  NSString *targetPath = nil;

  beginIgnoringBadWindow();
  if (XGetWindowProperty(dpy, xid, navAtom, 0, 4096, True,
                         utf8Atom, &actual_type, &actual_format,
                         &nitems, &bytes_after, &data) == Success && data && nitems > 0) {
    targetPath = [[NSString alloc] initWithUTF8String:(const char *)data];
    XFree(data);
  }

  XSync(dpy, False);
  endIgnoringBadWindow();

  if (targetPath) {
    if ([targetPath length] > 0) {
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

#else /* _WIN32 */

/* Windows: no X11 atoms, so the spatial path object only keeps the path. */

@implementation GWX11SpatialPath

- (instancetype)initWithWindow:(NSWindow *)window path:(NSString *)path
{
  self = [super init];
  if (!self) return nil;

  _window = window;
  _currentPath = [path copy];
  _pollTimer = nil;
  _dpy = NULL;

  return self;
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
}

- (void)invalidate
{
  _window = nil;
}

@end

#endif /* _WIN32 */
