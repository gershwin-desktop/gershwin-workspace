/* X11AppSupport.m
 *
 * Author: Gershwin Team
 * Date: December 2025
 */

#import "X11AppSupport.h"
#import "GWProcessOwnership.h"
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSDisplayServer.h>

#ifndef _WIN32

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <stddef.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#pragma mark - X11 Error Handler

/* Custom X error handler to prevent crashes from BadWindow/BadMatch errors.
 * These can occur when windows are destroyed between discovery and operation. */
static int gwX11ErrorHandler(Display *dpy, XErrorEvent *event)
{
    char errorText[256];
    XGetErrorText(dpy, event->error_code, errorText, sizeof(errorText));
    /* Return 0 to continue; the error is logged but doesn't crash */
    return 0;
}

static BOOL x11ErrorHandlerInstalled = NO;

static void ensureX11ErrorHandler(void)
{
    if (!x11ErrorHandlerInstalled) {
        XSetErrorHandler(gwX11ErrorHandler);
        x11ErrorHandlerInstalled = YES;
    }
}

#pragma mark - X11 I/O Error Logger

/* Xlib's default I/O error handler only prints "X connection to ... broken"
 * and exits.  That cannot tell a server-side kill apart from a descriptor
 * clobbered inside this process, and Workspace keeps several connections of
 * its own besides AppKit's.  So log which connection failed, the errno and
 * what its descriptor refers to now, then hand over to the previous handler
 * so the process still exits exactly as before. */
static XIOErrorHandler gwPreviousIOErrorHandler = NULL;

static NSString *gwDescribeDescriptor(int fd)
{
    struct sockaddr_un addr;
    socklen_t len = sizeof(addr);

    if (fcntl(fd, F_GETFD) == -1) {
        return [NSString stringWithFormat:@"fd %d not open (%s)", fd, strerror(errno)];
    }
    memset(&addr, 0, sizeof(addr));
    if (getpeername(fd, (struct sockaddr *)&addr, &len) != 0) {
        return [NSString stringWithFormat:@"fd %d open, no peer (%s)", fd, strerror(errno)];
    }
    if (addr.sun_family != AF_UNIX) {
        return [NSString stringWithFormat:@"fd %d peer address family %d", fd, (int)addr.sun_family];
    }
    /* Linux X servers also listen on an abstract socket, whose name starts
     * with a NUL byte. */
    if (addr.sun_path[0] == '\0' && len > offsetof(struct sockaddr_un, sun_path) + 1) {
        return [NSString stringWithFormat:@"fd %d peer @%s", fd, addr.sun_path + 1];
    }
    return [NSString stringWithFormat:@"fd %d peer %s", fd, addr.sun_path];
}

static int gwX11IOErrorLogger(Display *dpy)
{
    int savedErrno = errno;
    Display *appDisplay = (Display *)[GSCurrentServer() serverDevice];
    /* strerror() may return a shared buffer that gwDescribeDescriptor()
     * overwrites, so capture the text before calling it. */
    NSString *errnoText = [NSString stringWithUTF8String: strerror(savedErrno)];

    NSLog(@"X11 I/O error on %@ connection %p (%s): errno %d (%@), %@, %@ thread\n%@",
          (dpy == appDisplay) ? @"AppKit" : @"secondary",
          dpy, DisplayString(dpy), savedErrno, errnoText,
          gwDescribeDescriptor(ConnectionNumber(dpy)),
          [NSThread isMainThread] ? @"main" : @"background",
          [NSThread callStackSymbols]);
    errno = savedErrno;
    return (gwPreviousIOErrorHandler != NULL) ? gwPreviousIOErrorHandler(dpy) : 0;
}

void GWInstallX11IOErrorLogger(void)
{
    gwPreviousIOErrorHandler = XSetIOErrorHandler(gwX11IOErrorLogger);
}

#endif /* !_WIN32 */

#pragma mark - GWX11WindowInfo Implementation

@implementation GWX11WindowInfo

@synthesize windowID;
@synthesize windowName;
@synthesize windowClass;
@synthesize ownerPID;
@synthesize isHidden;
@synthesize isIconified;

+ (instancetype)infoWithWindowID:(unsigned long)wid
{
    GWX11WindowInfo *info = [[GWX11WindowInfo alloc] init];
    info.windowID = wid;
    return AUTORELEASE(info);
}

- (void)dealloc
{
    RELEASE(windowName);
    RELEASE(windowClass);
    [super dealloc];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<GWX11WindowInfo: 0x%lx name='%@' class='%@' pid=%d>",
            windowID, windowName, windowClass, (int)ownerPID];
}

@end

#ifndef _WIN32

#pragma mark - GWX11WindowManager Implementation

@implementation GWX11WindowManager

static GWX11WindowManager *sharedWindowManager = nil;

+ (instancetype)sharedManager
{
    @synchronized(self) {
        if (sharedWindowManager == nil) {
            sharedWindowManager = [[GWX11WindowManager alloc] init];
        }
    }
    return sharedWindowManager;
}

- (id)init
{
    self = [super init];
    return self;
}

#pragma mark Private Helpers

/* Key under which a thread keeps the connection it works with. */
static NSString * const GWX11ThreadDisplayKey = @"GWX11WindowManagerDisplay";

/* A connection costs a socket, the authentication handshake and a round trip
 * to open, and a single window scan asks several questions in a row, so the
 * connection is kept for as long as the thread that opened it runs. Each
 * thread gets its own, which is what makes the scans off the main thread safe
 * without any locking. */
- (Display *)openDisplay
{
    NSMutableDictionary *threadInfo = [[NSThread currentThread] threadDictionary];
    NSValue *cached = [threadInfo objectForKey:GWX11ThreadDisplayKey];

    if (cached != nil) {
        return (Display *)[cached pointerValue];
    }

    ensureX11ErrorHandler();
    Display *dpy = XOpenDisplay(NULL);
    if (dpy == NULL) {
        return NULL;
    }

    /* Sync to catch any pending errors before returning */
    XSync(dpy, False);
    [threadInfo setObject:[NSValue valueWithPointer:dpy]
                   forKey:GWX11ThreadDisplayKey];
    return dpy;
}

/* Counterpart of openDisplay. The connection stays open, but whatever the
 * caller queued still has to reach the server, which closing the connection
 * used to take care of. */
- (void)releaseDisplay:(Display *)dpy
{
    if (dpy != NULL) {
        XFlush(dpy);
    }
}

/* A worker thread must drop its connection before it ends, or the server
 * keeps a client for every scan that ever ran. */
- (void)closeThreadDisplay
{
    NSMutableDictionary *threadInfo = [[NSThread currentThread] threadDictionary];
    NSValue *cached = [threadInfo objectForKey:GWX11ThreadDisplayKey];

    if (cached == nil) {
        return;
    }

    XCloseDisplay((Display *)[cached pointerValue]);
    [threadInfo removeObjectForKey:GWX11ThreadDisplayKey];
}

- (Window *)getClientList:(Display *)dpy count:(unsigned long *)count
{
    if (!dpy || !count) return NULL;
    
    Atom net_client_list = XInternAtom(dpy, "_NET_CLIENT_LIST", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    
    Window root = DefaultRootWindow(dpy);
    
    if (XGetWindowProperty(dpy, root, net_client_list, 0, LONG_MAX, False,
                           XA_WINDOW, &actual_type, &actual_format,
                           &nitems, &bytes_after, &data) == Success && data) {
        *count = nitems;
        return (Window *)data;
    }
    
    *count = 0;
    return NULL;
}

- (pid_t)getPIDForWindow:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return 0;
    
    Atom net_wm_pid = XInternAtom(dpy, "_NET_WM_PID", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    pid_t pid = 0;
    
    if (XGetWindowProperty(dpy, win, net_wm_pid, 0, 1, False, XA_CARDINAL,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data) {
        if (nitems >= 1) {
            pid = (pid_t)(*(unsigned long *)data);
        }
        XFree(data);
    }
    
    return pid;
}

- (NSString *)getWindowName:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return nil;
    
    Atom net_wm_name = XInternAtom(dpy, "_NET_WM_NAME", False);
    Atom utf8_string = XInternAtom(dpy, "UTF8_STRING", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    NSString *name = nil;
    
    /* Try _NET_WM_NAME (UTF-8) first */
    if (XGetWindowProperty(dpy, win, net_wm_name, 0, 1024, False, utf8_string,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data && nitems > 0) {
        name = [NSString stringWithUTF8String:(const char *)data];
        XFree(data);
        if (name) return name;
    }
    if (data) { XFree(data); data = NULL; }
    
    /* Fallback to WM_NAME */
    if (XGetWindowProperty(dpy, win, XA_WM_NAME, 0, 1024, False, AnyPropertyType,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data && nitems > 0) {
        name = [NSString stringWithCString:(const char *)data encoding:NSUTF8StringEncoding];
        if (!name) {
            name = [NSString stringWithCString:(const char *)data encoding:NSISOLatin1StringEncoding];
        }
        XFree(data);
    }
    
    return name;
}

- (NSString *)getWindowClass:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return nil;
    
    XClassHint classHint;
    NSString *className = nil;
    
    if (XGetClassHint(dpy, win, &classHint)) {
        if (classHint.res_class) {
            className = [NSString stringWithCString:classHint.res_class encoding:NSUTF8StringEncoding];
            XFree(classHint.res_class);
        }
        if (classHint.res_name) {
            XFree(classHint.res_name);
        }
    }
    
    return className;
}

- (BOOL)isWindowHidden:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return NO;
    
    Atom net_wm_state = XInternAtom(dpy, "_NET_WM_STATE", False);
    Atom net_wm_state_hidden = XInternAtom(dpy, "_NET_WM_STATE_HIDDEN", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    BOOL hidden = NO;
    
    if (XGetWindowProperty(dpy, win, net_wm_state, 0, LONG_MAX, False, XA_ATOM,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data) {
        Atom *states = (Atom *)data;
        for (unsigned long i = 0; i < nitems; i++) {
            if (states[i] == net_wm_state_hidden) {
                hidden = YES;
                break;
            }
        }
        XFree(data);
    }
    
    return hidden;
}

- (BOOL)hasNetWmStateSkipTaskbar:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return NO;
    
    Atom net_wm_state = XInternAtom(dpy, "_NET_WM_STATE", False);
    Atom skip_taskbar = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    BOOL hasSkip = NO;
    
    if (XGetWindowProperty(dpy, win, net_wm_state, 0, LONG_MAX, False, XA_ATOM,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data) {
        Atom *states = (Atom *)data;
        for (unsigned long i = 0; i < nitems; i++) {
            if (states[i] == skip_taskbar) {
                hasSkip = YES;
                break;
            }
        }
        XFree(data);
    }
    
    return hasSkip;
}

- (BOOL)checkWindowIconified:(Display *)dpy window:(Window)win
{
    if (!dpy || !win) return NO;
    
    Atom wm_state = XInternAtom(dpy, "WM_STATE", False);
    Atom actual_type;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;
    BOOL iconified = NO;
    
    if (XGetWindowProperty(dpy, win, wm_state, 0, 2, False, wm_state,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data) {
        if (nitems >= 1) {
            long state = *(long *)data;
            iconified = (state == IconicState);
        }
        XFree(data);
    }
    
    return iconified;
}

- (GWX11WindowInfo *)infoForWindow:(Display *)dpy window:(Window)win
{
    GWX11WindowInfo *info = [GWX11WindowInfo infoWithWindowID:win];
    info.windowName = [self getWindowName:dpy window:win];
    info.windowClass = [self getWindowClass:dpy window:win];
    info.ownerPID = [self getPIDForWindow:dpy window:win];
    info.isHidden = [self isWindowHidden:dpy window:win];
    info.isIconified = [self checkWindowIconified:dpy window:win];
    return info;
}

#pragma mark Window Discovery

- (NSArray *)allClientWindows
{
    NSMutableArray *windows = [NSMutableArray array];
    Display *dpy = [self openDisplay];
    if (!dpy) return windows;
    
    @try {
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];
        
        if (clients) {
            for (unsigned long i = 0; i < count; i++) {
                /* Skip windows with no PID (WM root/decoration windows) or
                 * _NET_WM_STATE_SKIP_TASKBAR (dock panels, desktop, etc.). */
                pid_t winPID = [self getPIDForWindow:dpy window:clients[i]];
                if (winPID <= 0) {
                    continue;
                }
                if ([self hasNetWmStateSkipTaskbar:dpy window:clients[i]]) {
                    continue;
                }
                GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                [windows addObject:info];
            }
            XFree(clients);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return windows;
}

- (NSArray *)windowsForPID:(pid_t)pid
{
    NSMutableArray *windows = [NSMutableArray array];
    if (pid <= 0) return windows;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return windows;
    
    @try {
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];
        
        if (clients) {
            for (unsigned long i = 0; i < count; i++) {
                pid_t winPID = [self getPIDForWindow:dpy window:clients[i]];
                if (winPID == pid) {
                    /* Skip windows with _NET_WM_STATE_SKIP_TASKBAR */
                    if (![self hasNetWmStateSkipTaskbar:dpy window:clients[i]]) {
                        GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                        [windows addObject:info];
                    }
                }
            }
            XFree(clients);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return windows;
}

/*
 * Returns YES if 'word' appears as a whole word in 'str'
 * (case-insensitive).  A whole word means it is either at the start of str
 * or preceded by a non-alphanumeric character, and either at the end of str
 * or followed by a non-alphanumeric character.  This prevents matching the
 * app name embedded inside a longer word (e.g. "CreateLiveMediaAssistant"
 * inside "CreateLiveMediaAssistantBuild").
 */
static BOOL stringStartsOrEndsWith(NSString *str, NSString *word)
{
    if ([str length] < [word length])
        return NO;
    // Match at start (case-insensitive)
    if ([[str substringToIndex: [word length]] caseInsensitiveCompare: word] == NSOrderedSame)
        return YES;
    // Match at end (case-insensitive)
    if ([[str substringFromIndex: [str length] - [word length]] caseInsensitiveCompare: word] == NSOrderedSame)
        return YES;
    return NO;
}

- (NSArray *)windowsMatchingName:(NSString *)name
{
    NSMutableArray *windows = [NSMutableArray array];
    if (!name || [name length] == 0) return windows;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return windows;
    
    @try {
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];
        
        if (clients) {
            pid_t myPID = getpid();

            for (unsigned long i = 0; i < count; i++) {
                pid_t winPID = [self getPIDForWindow:dpy window:clients[i]];

                /* Skip windows with no PID (WM root/decoration windows) */
                if (winPID <= 0) {
                    continue;
                }

                /* Skip our own windows — the Workspace file viewer titles
                 * can match app names (e.g., a viewer browsing "xpdf" volume
                 * would falsely match an app named "xpdf").
                 * Check both _NET_WM_PID and WM_CLASS since GNUstep apps
                 * may not set _NET_WM_PID. */
                if (winPID == myPID) {
                    continue;
                }

                NSString *winName = [self getWindowName:dpy window:clients[i]];
                NSString *winClass = [self getWindowClass:dpy window:clients[i]];

                /* Skip windows belonging to Workspace (by WM_CLASS).
                 * GNUstep apps have res_class="GNUstep". Workspace's own
                 * windows use specific res_name values like "Workspace",
                 * "FileViewer", "Window", etc. Check both parts to avoid
                 * filtering out other GNUstep applications' windows. */
                if (winClass && [winClass isEqualToString:@"GNUstep"]) {
                    XClassHint classHint;
                    if (XGetClassHint(dpy, clients[i], &classHint)) {
                        BOOL isWorkspace = NO;
                        if (classHint.res_name) {
                            NSString *resName = [NSString stringWithCString:classHint.res_name encoding:NSUTF8StringEncoding];
                            if ([resName isEqualToString:@"Workspace"] ||
                                [resName isEqualToString:@"FileViewer"] ||
                                [resName isEqualToString:@"Window"] ||
                                [resName isEqualToString:@"Finder"]) {
                                isWorkspace = YES;
                            }
                            XFree(classHint.res_name);
                        }
                        if (classHint.res_class) {
                            XFree(classHint.res_class);
                        }
                        if (isWorkspace) {
                            continue;
                        }
                    }
                }

                /* Skip windows with _NET_WM_STATE_SKIP_TASKBAR (e.g. app icon
                 * windows, desktop windows, dock panels). */
                if ([self hasNetWmStateSkipTaskbar:dpy window:clients[i]]) {
                    continue;
                }

                BOOL matches = NO;
                if (winName && stringStartsOrEndsWith(winName, name)) {
                    matches = YES;
                } else if (winClass && stringStartsOrEndsWith(winClass, name)) {
                    matches = YES;
                }

                /* Other users' windows on this display are not this
                 * session's applications. */
                if (matches && [GWProcessOwnership isProcessOwnedByCurrentUser: winPID]) {
                    GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                    [windows addObject:info];
                }
            }
            XFree(clients);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return windows;
}

- (unsigned long)findWindowByName:(NSString *)name
{
    NSArray *windows = [self windowsMatchingName:name];
    if ([windows count] > 0) {
        return [[windows objectAtIndex:0] windowID];
    }
    return 0;
}

- (unsigned long)findWindowByPID:(pid_t)pid
{
    NSArray *windows = [self windowsForPID:pid];
    if ([windows count] > 0) {
        return [[windows objectAtIndex:0] windowID];
    }
    return 0;
}

#pragma mark Window Activation

- (BOOL)activateWindow:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL success = NO;
    
    @try {
        Window root = DefaultRootWindow(dpy);
        Atom net_active_window = XInternAtom(dpy, "_NET_ACTIVE_WINDOW", False);
        
        /* First, restore if iconified */
        if ([self checkWindowIconified:dpy window:(Window)windowID]) {
            XMapRaised(dpy, (Window)windowID);
        }
        
        /* Send _NET_ACTIVE_WINDOW client message */
        XEvent event;
        memset(&event, 0, sizeof(event));
        event.xclient.type = ClientMessage;
        event.xclient.window = (Window)windowID;
        event.xclient.message_type = net_active_window;
        event.xclient.format = 32;
        event.xclient.data.l[0] = 1; /* Source: application */
        event.xclient.data.l[1] = CurrentTime;
        event.xclient.data.l[2] = 0;
        
        XSendEvent(dpy, root, False,
                   SubstructureRedirectMask | SubstructureNotifyMask,
                   &event);
        
        /* Also raise the window */
        XRaiseWindow(dpy, (Window)windowID);
        XFlush(dpy);
        success = YES;
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return success;
}

- (BOOL)activateWindowsForPID:(pid_t)pid
{
    NSArray *windows = [self windowsForPID:pid];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self activateWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)activateWindowsMatchingName:(NSString *)name
{
    NSArray *windows = [self windowsMatchingName:name];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self activateWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

#pragma mark Window Hide/Show

- (BOOL)iconifyWindow:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL success = NO;
    
    @try {
        int screen = DefaultScreen(dpy);
        success = (XIconifyWindow(dpy, (Window)windowID, screen) != 0);
        XFlush(dpy);
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return success;
}

- (BOOL)iconifyWindowsForPID:(pid_t)pid
{
    NSArray *windows = [self windowsForPID:pid];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self iconifyWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)iconifyWindowsMatchingName:(NSString *)name
{
    NSArray *windows = [self windowsMatchingName:name];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self iconifyWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)isGNUstepWindow:(Display *)dpy window:(Window)win
{
    /* libs-back puts this property on every window it creates; WM_CLASS
     * cannot tell, it carries the application's own name. */
    Atom attr = XInternAtom(dpy, "_GNUSTEP_WM_ATTR", False);
    Atom actual_type = None;
    int actual_format;
    unsigned long nitems, bytes_after;
    unsigned char *data = NULL;

    if (XGetWindowProperty(dpy, win, attr, 0, 1, False, AnyPropertyType,
                           &actual_type, &actual_format, &nitems,
                           &bytes_after, &data) == Success && data) {
        XFree(data);
    }
    return (actual_type != None);
}

- (BOOL)iconifyNonGNUstepWindowsExceptPID:(pid_t)pid
{
    Display *dpy = [self openDisplay];
    BOOL success = NO;

    if (!dpy) return NO;

    @try {
        int screen = DefaultScreen(dpy);
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];

        for (unsigned long i = 0; i < count; i++) {
            Window win = clients[i];

            /* GNUstep applications hide themselves on Hide Others;
             * iconifying their windows here as well would take them out
             * of the hidden state the application itself keeps. */
            if ([self isGNUstepWindow:dpy window:win]) continue;
            if ([self hasNetWmStateSkipTaskbar:dpy window:win]) continue;
            if ([self checkWindowIconified:dpy window:win]) continue;
            if (pid > 0 && [self getPIDForWindow:dpy window:win] == pid) continue;
            if (XIconifyWindow(dpy, win, screen) != 0) {
                success = YES;
            }
        }
        if (clients) XFree(clients);
        XFlush(dpy);
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return success;
}

- (BOOL)restoreIconifiedWindows
{
    Display *dpy = [self openDisplay];
    BOOL success = NO;

    if (!dpy) return NO;

    @try {
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];

        for (unsigned long i = 0; i < count; i++) {
            Window win = clients[i];

            if ([self hasNetWmStateSkipTaskbar:dpy window:win]) continue;
            if ([self checkWindowIconified:dpy window:win] == NO) continue;
            XMapRaised(dpy, win);
            success = YES;
        }
        if (clients) XFree(clients);
        XFlush(dpy);
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return success;
}

- (BOOL)restoreWindow:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL success = NO;
    
    @try {
        XMapRaised(dpy, (Window)windowID);
        XFlush(dpy);
        success = YES;
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return success;
}

- (BOOL)restoreWindowsForPID:(pid_t)pid
{
    NSArray *windows = [self windowsForPID:pid];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self restoreWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)restoreWindowsMatchingName:(NSString *)name
{
    NSArray *windows = [self windowsMatchingName:name];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self restoreWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

- (BOOL)setIconGeometry:(NSRect)rect forPID:(pid_t)pid
{
    if (pid <= 0) return NO;

    Display *dpy = [self openDisplay];
    if (!dpy) return NO;

    BOOL success = NO;

    @try {
        Atom iconGeometry = XInternAtom(dpy, "_NET_WM_ICON_GEOMETRY", False);
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];

        if (clients) {
            for (unsigned long i = 0; i < count; i++) {
                pid_t winPID = [self getPIDForWindow:dpy window:clients[i]];
                if (winPID != pid) {
                    continue;
                }

                long data[4];
                data[0] = (long)llround(rect.origin.x);
                data[1] = (long)llround(rect.origin.y);
                data[2] = (long)llround(rect.size.width);
                data[3] = (long)llround(rect.size.height);

                XChangeProperty(dpy, clients[i], iconGeometry, XA_CARDINAL, 32,
                                PropModeReplace, (unsigned char *)data, 4);
                success = YES;
            }
            XFree(clients);
        }

        XFlush(dpy);
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return success;
}

- (BOOL)setIconGeometry:(NSRect)rect forName:(NSString *)name
{
    if (!name || [name length] == 0) return NO;

    Display *dpy = [self openDisplay];
    if (!dpy) return NO;

    BOOL success = NO;

    @try {
        Atom iconGeometry = XInternAtom(dpy, "_NET_WM_ICON_GEOMETRY", False);
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];

        if (clients) {
            for (unsigned long i = 0; i < count; i++) {
                NSString *winName = [self getWindowName:dpy window:clients[i]];
                NSString *winClass = [self getWindowClass:dpy window:clients[i]];

                BOOL matches = NO;
                if (winName && [winName rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    matches = YES;
                } else if (winClass && [winClass rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    matches = YES;
                }

                if (!matches) {
                    continue;
                }

                long data[4];
                data[0] = (long)llround(rect.origin.x);
                data[1] = (long)llround(rect.origin.y);
                data[2] = (long)llround(rect.size.width);
                data[3] = (long)llround(rect.size.height);

                XChangeProperty(dpy, clients[i], iconGeometry, XA_CARDINAL, 32,
                                PropModeReplace, (unsigned char *)data, 4);
                success = YES;
            }
            XFree(clients);
        }

        XFlush(dpy);
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return success;
}

#pragma mark Window State Queries

- (BOOL)isWindowIconified:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL iconified = NO;
    
    @try {
        iconified = [self checkWindowIconified:dpy window:(Window)windowID];
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return iconified;
}

- (BOOL)isWindowVisible:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL visible = NO;
    
    @try {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(dpy, (Window)windowID, &attrs)) {
            visible = (attrs.map_state == IsViewable);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return visible;
}

- (BOOL)hasWindowsForPID:(pid_t)pid
{
    if (pid <= 0) return NO;

    Display *dpy = [self openDisplay];
    if (!dpy) return NO;

    BOOL hasVisible = NO;

    @try {
        unsigned long count = 0;
        Window *clients = [self getClientList:dpy count:&count];

        if (clients) {
            for (unsigned long i = 0; i < count && !hasVisible; i++) {
                pid_t winPID = [self getPIDForWindow:dpy window:clients[i]];
                if (winPID == pid) {
                    if ([self hasNetWmStateSkipTaskbar:dpy window:clients[i]])
                        continue;
                    XWindowAttributes attrs;
                    if (XGetWindowAttributes(dpy, clients[i], &attrs)) {
                        if (attrs.map_state == IsViewable) {
                            hasVisible = YES;
                        }
                    }
                }
            }
            XFree(clients);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return hasVisible;
}

- (BOOL)hasWindowsMatchingName:(NSString *)name
{
    return [[self windowsMatchingName:name] count] > 0;
}

#pragma mark Window Closing

- (BOOL)closeWindow:(unsigned long)windowID
{
    if (windowID == 0) return NO;
    
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    
    BOOL success = NO;
    
    @try {
        Atom wm_delete_window = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
        Atom wm_protocols = XInternAtom(dpy, "WM_PROTOCOLS", False);
        
        /* Check if window supports WM_DELETE_WINDOW */
        Atom *protocols = NULL;
        int protocol_count = 0;
        BOOL supports_delete = NO;
        
        if (XGetWMProtocols(dpy, (Window)windowID, &protocols, &protocol_count)) {
            for (int i = 0; i < protocol_count; i++) {
                if (protocols[i] == wm_delete_window) {
                    supports_delete = YES;
                    break;
                }
            }
            if (protocols) XFree(protocols);
        }
        
        if (supports_delete) {
            XEvent event;
            memset(&event, 0, sizeof(event));
            event.xclient.type = ClientMessage;
            event.xclient.window = (Window)windowID;
            event.xclient.message_type = wm_protocols;
            event.xclient.format = 32;
            event.xclient.data.l[0] = wm_delete_window;
            event.xclient.data.l[1] = CurrentTime;
            
            XSendEvent(dpy, (Window)windowID, False, NoEventMask, &event);
            XFlush(dpy);
            success = YES;
        } else {
            /* Fallback: use _NET_CLOSE_WINDOW */
            Window root = DefaultRootWindow(dpy);
            Atom net_close_window = XInternAtom(dpy, "_NET_CLOSE_WINDOW", False);
            
            XEvent event;
            memset(&event, 0, sizeof(event));
            event.xclient.type = ClientMessage;
            event.xclient.window = (Window)windowID;
            event.xclient.message_type = net_close_window;
            event.xclient.format = 32;
            event.xclient.data.l[0] = CurrentTime;
            event.xclient.data.l[1] = 1; /* Source: application */
            
            XSendEvent(dpy, root, False,
                       SubstructureRedirectMask | SubstructureNotifyMask,
                       &event);
            XFlush(dpy);
            success = YES;
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    
    return success;
}

- (BOOL)closeWindowsForPID:(pid_t)pid
{
    NSArray *windows = [self windowsForPID:pid];
    BOOL success = NO;
    
    for (GWX11WindowInfo *info in windows) {
        if ([self closeWindow:info.windowID]) {
            success = YES;
        }
    }
    
    return success;
}

/* Ask the WindowManager to play the close animation for @p windowID: a
 * shrink+fade toward the folder icon's current position, or a plain fade
 * when no target is available.  Sends a _WINDOW_CLOSE_ANIMATION client
 * message to the WM while the window is still mapped; the WM unmaps the
 * window itself when the animation completes, so the app's later orderOut is
 * a harmless no-op.  The message name is vendor-neutral (like the
 * _WINDOW_BIRTH_ANIMATION atoms) so the protocol could be standardized. */
- (BOOL)animateWindowClose:(unsigned long)windowID
               targetRect:(NSRect)targetRect
{
    if (windowID == 0) return NO;

    Display *dpy = [self openDisplay];
    if (!dpy) return NO;

    BOOL success = NO;

    @try {
        Window root = DefaultRootWindow(dpy);
        Atom closeAnimAtom = XInternAtom(dpy, "_WINDOW_CLOSE_ANIMATION", False);
        if (closeAnimAtom == None) {
            return NO;
        }

        /* Convert the target rect from Cocoa (bottom-left origin) to X11 root
         * coordinates (top-left origin), matching the birth protocol. */
        long tx = 0, ty = 0, tw = 0, th = 0;
        if (!NSEqualRects(targetRect, NSZeroRect)) {
            NSScreen *screen = [NSScreen mainScreen];
            NSRect screenFrame = [screen frame];
            tx = (long)llround(targetRect.origin.x);
            ty = (long)llround(screenFrame.size.height - targetRect.origin.y - targetRect.size.height);
            tw = (long)llround(targetRect.size.width);
            th = (long)llround(targetRect.size.height);
        }

        XEvent event;
        memset(&event, 0, sizeof(event));
        event.xclient.type = ClientMessage;
        event.xclient.window = (Window)windowID;
        event.xclient.message_type = closeAnimAtom;
        event.xclient.format = 32;
        /* data32: [0]=animationType (0=shrink-to-icon, 2=fade), [1..4]=x,y,w,h */
        event.xclient.data.l[0] = NSEqualRects(targetRect, NSZeroRect) ? 2 : 0;
        event.xclient.data.l[1] = tx;
        event.xclient.data.l[2] = ty;
        event.xclient.data.l[3] = tw;
        event.xclient.data.l[4] = th;

        /* Send to the root window with SubstructureRedirect|Notify so the WM
         * receives it as a ClientMessage on the client window. */
        XSendEvent(dpy, root, False,
                   SubstructureRedirectMask | SubstructureNotifyMask,
                   &event);
        XFlush(dpy);
        success = YES;
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return success;
}

/* Check whether the running WindowManager advertises the window-animation
 * protocol in its _NET_SUPPORTED root-window property.  Workspace only sets
 * _WINDOW_BIRTH_ANIMATION / sends _WINDOW_CLOSE_ANIMATION when the WM does; otherwise
 * the window closes with a plain fade and no stale atoms are left behind. */
- (BOOL)windowManagerSupportsWindowAnimation
{
    BOOL supported = NO;
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;

    @try {
        Window root = DefaultRootWindow(dpy);
        Atom netSupported = XInternAtom(dpy, "_NET_SUPPORTED", False);
        Atom birth = XInternAtom(dpy, "_WINDOW_BIRTH_ANIMATION", False);
        Atom closeAnim = XInternAtom(dpy, "_WINDOW_CLOSE_ANIMATION", False);

        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *data = NULL;

        if (XGetWindowProperty(dpy, root, netSupported, 0, LONG_MAX, False,
                               XA_ATOM, &actual_type, &actual_format,
                               &nitems, &bytes_after, &data) == Success && data) {
            Atom *atoms = (Atom *)data;
            BOOL hasBirth = NO, hasCloseAnim = NO;
            for (unsigned long i = 0; i < nitems; i++) {
                if (atoms[i] == birth) hasBirth = YES;
                if (atoms[i] == closeAnim) hasCloseAnim = YES;
            }
            supported = hasBirth && hasCloseAnim;
            XFree(data);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }

    return supported;
}

/* Return the CONTENT rect of a window in GNUstep screen coords (bottom-left
 * origin), measured from the ACTUAL X geometry of the client window - not
 * GNUstep's tracked frame, which can include a stale clientBorder and be a
 * few px off from the WM's real frame.  The client window is the content
 * area (the WM wraps it in a frame), so its geometry is the content rect.
 * Returns NO if geometry cannot be obtained. */
- (BOOL)contentRectFromXGeometry:(Window)xwindow
                         screenHeight:(CGFloat)screenHeight
                             outRect:(NSRect *)outRect
{
    if (xwindow == 0 || !outRect) return NO;
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    BOOL ok = NO;
    @try {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(dpy, xwindow, &attrs)) {
            int root_x = 0, root_y = 0;
            Window child;
            XTranslateCoordinates(dpy, xwindow, DefaultRootWindow(dpy),
                                  0, 0, &root_x, &root_y, &child);
            /* The client window IS the content area: its root position and
             * size.  GNUstep screen coords are bottom-left. */
            NSRect content;
            content.origin.x = root_x;
            content.origin.y = screenHeight - root_y - attrs.height;
            content.size.width = attrs.width;
            content.size.height = attrs.height;
            *outRect = content;
            ok = (attrs.width > 0 && attrs.height > 0);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    return ok;
}

/* Read the WM's real _NET_FRAME_EXTENTS for a client window.  The WM writes
 * this property on the client when it frames the window (XCBFrame
 * decorateClientWindow / EWMHService updateNetFrameExtentsForWindow); before
 * that the property is absent.  Returns NO if the extents are not readable
 * (window not yet framed). */
- (BOOL)frameExtentsForWindow:(Window)xwindow
                      outLeft:(unsigned long *)l
                     outRight:(unsigned long *)r
                      outTop:(unsigned long *)t
                   outBottom:(unsigned long *)b
{
    if (xwindow == 0) return NO;
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    BOOL ok = NO;
    @try {
        Atom ext = XInternAtom(dpy, "_NET_FRAME_EXTENTS", False);
        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *data = NULL;
        if (XGetWindowProperty(dpy, xwindow, ext, 0, 4, False, XA_CARDINAL,
                               &actual_type, &actual_format, &nitems,
                               &bytes_after, &data) == Success
            && data && nitems >= 4) {
            unsigned long *vals = (unsigned long *)data;
            /* A real frame has a positive top (the titlebar).  All-zero
             * extents mean the WM has not framed the window yet (it sets the
             * property before applying the decoration offsets); returning YES
             * with zeros would make a caller snap to a title-bar-less frame.
             */
            if (nitems >= 4 && vals[2] > 0) {
                if (l) *l = vals[0];
                if (r) *r = vals[1];
                if (t) *t = vals[2];
                if (b) *b = vals[3];
                ok = YES;
            }
        }
        if (data) XFree(data);
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    return ok;
}

/* Return YES only when the client window is mapped (IsViewable) AND framed by
 * the WM (positive _NET_FRAME_EXTENTS top).  An unmapped window - e.g. a ghost
 * that never got a place on screen - still answers XGetWindowAttributes, and a
 * window caught mid-framing has no extents yet; persisting geometry from
 * either would save a transient/bogus position into the .DS_Store and poison
 * every later open of the folder.  See windowWillClose save paths. */
- (BOOL)windowIsMappedAndFramed:(Window)xwindow
{
    if (xwindow == 0) return NO;
    Display *dpy = [self openDisplay];
    if (!dpy) return NO;
    BOOL mapped = NO;
    @try {
        XWindowAttributes attrs;
        if (XGetWindowAttributes(dpy, xwindow, &attrs)) {
            mapped = (attrs.map_state == IsViewable);
        }
    }
    @finally {
        [self releaseDisplay:dpy];
    }
    if (!mapped) return NO;
    /* Positive top extents mean the WM has framed the window; frameExtents
     * for windows opens its own connection, so only call it once the cheap
     * map-state check passed. */
    return [self frameExtentsForWindow:xwindow
                               outLeft:NULL outRight:NULL
                                outTop:NULL outBottom:NULL];
}

@end

#pragma mark - X11 Application Info

@interface GWX11AppInfo : NSObject
{
    NSString *appName;
    NSString *appPath;
    NSString *windowSearchString;
    pid_t pid;
    BOOL hasWindowAppeared;
    NSUInteger windowScanCount;
    NSTimeInterval nextWindowScan;
}
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy) NSString *windowSearchString;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) BOOL hasWindowAppeared;
/* How often the windows of this app have been looked for, and when to look
 * again; see -shouldScanWindowsAt:. */
@property (nonatomic, assign) NSUInteger windowScanCount;
@property (nonatomic, assign) NSTimeInterval nextWindowScan;
@end

@implementation GWX11AppInfo
@synthesize appName, appPath, windowSearchString, pid, hasWindowAppeared;
@synthesize windowScanCount, nextWindowScan;

/* Looking for the windows of an app costs a round trip to the X server per
 * window, and it only serves to notice the first window of an app that has
 * just been started. An app that shows one does so within seconds, so the
 * first attempts come quickly and then ever more slowly, down to once every
 * ten seconds for an app whose windows never turn up at all (a program
 * without a window, or one whose windows carry nothing to recognise them
 * by). Nothing is given up: the app is still noticed, just later. */
- (BOOL)shouldScanWindowsAt:(NSTimeInterval)now
{
    if (hasWindowAppeared) {
        return NO;
    }
    if (nextWindowScan > 0 && now < nextWindowScan) {
        return NO;
    }

    NSTimeInterval delay = 0.5 * (NSTimeInterval)(1 << MIN(windowScanCount, (NSUInteger)5));
    nextWindowScan = now + MIN(delay, (NSTimeInterval)10.0);
    windowScanCount++;
    return YES;
}

- (void)dealloc
{
    RELEASE(appName);
    RELEASE(appPath);
    RELEASE(windowSearchString);
    [super dealloc];
}
@end

#pragma mark - GWX11AppManager Implementation

@implementation GWX11AppManager

@synthesize delegate;

static GWX11AppManager *sharedX11AppManager = nil;

+ (instancetype)sharedManager
{
    @synchronized(self) {
        if (sharedX11AppManager == nil) {
            sharedX11AppManager = [[GWX11AppManager alloc] init];
        }
    }
    return sharedX11AppManager;
}

- (id)init
{
    self = [super init];
    if (self) {
        x11Apps = [[NSMutableDictionary alloc] init];
        monitorTimer = nil;
        delegate = nil;
    }
    return self;
}

- (void)dealloc
{
    [monitorTimer invalidate];
    RELEASE(x11Apps);
    [super dealloc];
}

- (BOOL)processExists:(pid_t)pid
{
    if (pid <= 0) return NO;
    int result = kill(pid, 0);
    if (result == 0) return YES;
    return (errno == EPERM);
}

- (void)startMonitorTimer
{
    if (monitorTimer == nil && [x11Apps count] > 0) {
        /* Poll for launched-app windows.  The window scans themselves run on a
         * worker thread (see monitorTimerFired), so the 0.5s cadence is about
         * detection latency, not main-thread load. */
        monitorTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                        target:self
                                                      selector:@selector(monitorTimerFired:)
                                                      userInfo:nil
                                                       repeats:YES];
    }
}

- (void)stopMonitorTimer
{
    if (monitorTimer && [x11Apps count] == 0) {
        [monitorTimer invalidate];
        monitorTimer = nil;
    }
}

- (void)monitorTimerFired:(NSTimer *)timer
{
    /* Snapshot the registered apps on the main thread, then run the window
     * scans on a worker thread.  windowsForPID:/windowsMatchingName: open X
     * connections and issue synchronous round-trips per window; done on the
     * main thread they can wedge the app under window churn (X11
     * self-deadlock, the same class of bug as the DockIcon refresh). */
    NSMutableArray *snapshot = [NSMutableArray array];
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    for (NSString *appName in [x11Apps allKeys]) {
        GWX11AppInfo *info = [x11Apps objectForKey:appName];
        if (info == nil) continue;
        /* Decided here, on the main thread, so the worker only reads the
         * snapshot: the liveness probe runs every time, the window scan as
         * often as the app's own backoff allows. */
        BOOL scanWindows = [info shouldScanWindowsAt: now];
        [snapshot addObject: [NSDictionary dictionaryWithObjectsAndKeys:
            info.appName ?: @"", @"name",
            info.appPath ?: @"", @"path",
            info.windowSearchString ?: @"", @"search",
            [NSNumber numberWithInt: (int)info.pid], @"pid",
            [NSNumber numberWithBool: info.hasWindowAppeared], @"appeared",
            [NSNumber numberWithBool: scanWindows], @"scanwindows", nil]];
    }
    if ([snapshot count] == 0) {
        [self stopMonitorTimer];
        return;
    }

    /* A tick only needs a thread when an X window scan is due: the scans are
     * synchronous round-trips that must not run on the main thread.  Once
     * every registered app has shown its window there is nothing left but a
     * kill() probe per app, which costs nothing and is done right here -
     * otherwise this timer would detach a thread with an eight megabyte
     * stack and its own X connection twice a second for the whole session. */
    BOOL scanDue = NO;
    for (NSDictionary *snap in snapshot) {
        if (![[snap objectForKey: @"appeared"] boolValue]
            && [[snap objectForKey: @"scanwindows"] boolValue]) {
            scanDue = YES;
            break;
        }
    }

    if (!scanDue) {
        [self applyMonitorResults: [self monitorResultsFor: snapshot
                                             scanningWindows: NO]];
        return;
    }

    [NSThread detachNewThreadSelector: @selector(monitorScanWorker:)
                             toTarget: self
                           withObject: snapshot];
}

/* Worker thread: check process liveness and run the X window scans for a
 * snapshot of the registered apps.  Only immutable snapshot data is read, and
 * GWX11WindowManager gives every thread its own X connection, so this is safe
 * off the main thread.  Results are applied back on the main thread. */
- (void)monitorScanWorker:(NSArray *)appSnapshots
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *results = [self monitorResultsFor: appSnapshots
                                     scanningWindows: YES];

    [self performSelectorOnMainThread: @selector(applyMonitorResults:)
                           withObject: results waitUntilDone: NO];
    [[GWX11WindowManager sharedManager] closeThreadDisplay];
    [pool drain];
}

/* Which of the registered apps have gone, and which have shown a window.
 * With scanningWindows NO this only probes the processes, touches no X
 * connection and is safe to call on the main thread; with YES it runs the
 * window scans as well and therefore belongs on a worker thread. */
- (NSDictionary *)monitorResultsFor:(NSArray *)appSnapshots
                    scanningWindows:(BOOL)mayScan
{
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    NSMutableArray *appeared = [NSMutableArray array];
    NSMutableArray *terminated = [NSMutableArray array];

    for (NSDictionary *snap in appSnapshots) {
        NSString *appName = [snap objectForKey: @"name"];
        NSString *appPath = [snap objectForKey: @"path"];
        pid_t pid = (pid_t)[[snap objectForKey: @"pid"] intValue];
        BOOL alreadyAppeared = [[snap objectForKey: @"appeared"] boolValue];

        /* Check if the process still exists (cheap kill() probe). */
        if (![self processExists:pid]) {
            [terminated addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                appName ?: @"", @"name", appPath ?: @"", @"path", nil]];
            continue;
        }

        /* Check if windows have appeared for this app. */
        if (mayScan && !alreadyAppeared
            && [[snap objectForKey: @"scanwindows"] boolValue]) {
            NSArray *windows = [wm windowsForPID:pid];
            if ([windows count] == 0) {
                NSString *search = [snap objectForKey: @"search"];
                if ([search length] > 0) {
                    windows = [wm windowsMatchingName:search];
                }
            }
            if ([windows count] > 0) {
                [appeared addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                    appName ?: @"", @"name", appPath ?: @"", @"path", nil]];
            }
        }
    }

    return [NSDictionary dictionaryWithObjectsAndKeys:
        appeared, @"appeared", terminated, @"terminated", nil];
}

/* Main thread: apply the worker's results. */
- (void)applyMonitorResults:(NSDictionary *)results
{
    for (NSDictionary *app in [results objectForKey: @"appeared"]) {
        NSString *appName = [app objectForKey: @"name"];
        GWX11AppInfo *info = [x11Apps objectForKey:appName];
        /* A concurrent worker may already have handled this app. */
        if (info == nil || info.hasWindowAppeared) continue;
        info.hasWindowAppeared = YES;
        if (delegate && [delegate respondsToSelector:@selector(x11AppWindowsDidAppear:path:)]) {
            [delegate x11AppWindowsDidAppear:appName path:[app objectForKey: @"path"]];
        }
    }
    for (NSDictionary *app in [results objectForKey: @"terminated"]) {
        NSString *appName = [app objectForKey: @"name"];
        NSString *appPath = [app objectForKey: @"path"];
        [x11Apps removeObjectForKey:appName];
        if (delegate && [delegate respondsToSelector:@selector(x11AppDidTerminate:path:)]) {
            [delegate x11AppDidTerminate:appName path:appPath];
        }
    }
    [self stopMonitorTimer];
}

- (void)registerX11App:(NSString *)appName
                  path:(NSString *)appPath
                   pid:(pid_t)pid
    windowSearchString:(NSString *)searchString
{
    if (!appName || !appPath || pid <= 0) return;
    /* Workspace turns up in its own launch notifications. Watching for our
     * own windows would keep the scan running for the life of the session
     * and tell us nothing we do not already know. */
    if (pid == getpid()) return;
    
    GWX11AppInfo *info = [[GWX11AppInfo alloc] init];
    info.appName = appName;
    info.appPath = appPath;
    info.pid = pid;
    info.windowSearchString = searchString ? searchString : appName;
    info.hasWindowAppeared = NO;
    
    [x11Apps setObject:info forKey:appName];
    RELEASE(info);
    
    [self startMonitorTimer];
    
    if (delegate && [delegate respondsToSelector:@selector(x11AppDidLaunch:path:pid:)]) {
        [delegate x11AppDidLaunch:appName path:appPath pid:pid];
    }
}

- (void)unregisterX11App:(NSString *)appName
{
    if (!appName) return;
    [x11Apps removeObjectForKey:appName];
    [self stopMonitorTimer];
}

- (BOOL)isX11App:(NSString *)appName
{
    return appName && [x11Apps objectForKey:appName] != nil;
}

- (BOOL)activateX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    /* Priority 1: _NET_WM_PID (most reliable) */
    if (info.pid > 0 && [wm activateWindowsForPID:info.pid]) {
        return YES;
    }
    
    /* Priority 2: name/class matching (fallback) */
    return [wm activateWindowsMatchingName:info.windowSearchString];
}

- (BOOL)hideX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    if (info.pid > 0 && [wm iconifyWindowsForPID:info.pid]) {
        return YES;
    }
    
    return [wm iconifyWindowsMatchingName:info.windowSearchString];
}

- (BOOL)unhideX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    if (info.pid > 0 && [wm restoreWindowsForPID:info.pid]) {
        return YES;
    }
    
    return [wm restoreWindowsMatchingName:info.windowSearchString];
}

- (BOOL)x11AppHasVisibleWindows:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    NSArray *windows = nil;
    
    /* Priority 1: _NET_WM_PID */
    if (info.pid > 0) {
        windows = [wm windowsForPID:info.pid];
    }
    
    /* Priority 2: name/class matching */
    if ([windows count] == 0 && info.windowSearchString) {
        windows = [wm windowsMatchingName:info.windowSearchString];
    }
    
    for (GWX11WindowInfo *winInfo in windows) {
        if (!winInfo.isIconified && !winInfo.isHidden) {
            return YES;
        }
    }
    
    return NO;
}

- (pid_t)pidForX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    return info ? info.pid : 0;
}

- (BOOL)quitX11App:(NSString *)appName timeout:(NSTimeInterval)timeout
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    /* First try to close windows gracefully */
    [wm closeWindowsForPID:info.pid];
    
    /* Wait for process to exit */
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if (![self processExists:info.pid]) {
            return YES;
        }
        usleep(100000); /* 100ms */
    }
    
    /* Still running - send SIGTERM */
    kill(info.pid, SIGTERM);
    
    /* Wait a bit more */
    deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        if (![self processExists:info.pid]) {
            return YES;
        }
        usleep(100000);
    }
    
    /* Force kill if still running */
    if ([self processExists:info.pid]) {
        kill(info.pid, SIGKILL);
    }
    
    return YES;
}

@end

#pragma mark - Window under the pointer

/* The X windows of ours that the pointer passes through, such as the icons
   an icon move carries along under it.  libs-back does not give
   -setIgnoresMouseEvents: any effect on X11, so it is honoured here. */
static NSHashTable *pointerTransparentWindows(Display *dpy)
{
    NSHashTable *result = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality];

    for (NSWindow *w in [NSApp windows]) {
        if ([w isVisible] && [w ignoresMouseEvents]) {
            GSDisplayServer *server = GSServerForWindow(w);
            if ((Display *)[server serverDevice] == dpy) {
                [result addObject:(void *)[server windowDevice:[w windowNumber]]];
            }
        }
    }
    return result;
}

BOOL GWForeignWindowIsUnderPointer(void)
{
    Display *dpy = (Display *)[GSCurrentServer() serverDevice];
    Window root, rootRet = None, child = None, under = None;
    Window unusedRoot = None, unusedParent = None, *topLevel = NULL;
    unsigned int nTopLevel = 0;
    int rx = 0, ry = 0, wx = 0, wy = 0;
    unsigned int mask = 0;
    pid_t pid = 0;
    NSHashTable *transparent;

    if (dpy == NULL)
        return NO;

    ensureX11ErrorHandler();

    root = DefaultRootWindow(dpy);

    /* The pointer itself rather than a stored event location: this is asked
       while the button is down, and the answer has to match where the cursor
       is now. */
    if (!XQueryPointer(dpy, root, &rootRet, &child, &rx, &ry, &wx, &wy, &mask))
        return NO;   /* pointer on another screen */
    if (child == None)
        return NO;   /* bare root: nothing there to drop on */

    /* XQueryPointer names only the topmost child of the root, which may be
       one of ours the pointer passes through; then the window below it is
       the one that counts.  The root's children come bottom to top. */
    transparent = pointerTransparentWindows(dpy);
    if (!XQueryTree(dpy, root, &unusedRoot, &unusedParent, &topLevel, &nTopLevel))
        return NO;
    while (nTopLevel-- > 0 && under == None) {
        Window candidate = topLevel[nTopLevel];
        XWindowAttributes attr;
        int tx = 0, ty = 0;
        Window unusedChild = None;

        if ([transparent containsObject:(void *)candidate])
            continue;
        if (XGetWindowAttributes(dpy, candidate, &attr)
            && attr.map_state == IsViewable
            && XTranslateCoordinates(dpy, root, candidate, rx, ry, &tx, &ty, &unusedChild)
            && tx >= 0 && tx < attr.width && ty >= 0 && ty < attr.height) {
            under = candidate;
        }
    }
    if (topLevel != NULL)
        XFree(topLevel);
    if (under == None)
        return NO;

    /* A top-level window of a managed application is the frame the window
       manager reparented it into.  Descend to the window really under the
       pointer, then climb back up to whoever claims ownership: _NET_WM_PID
       sits on the client window, which is somewhere between the two. */
    for (;;) {
        Window next = None;
        int tx = 0, ty = 0;

        if (!XTranslateCoordinates(dpy, root, under, rx, ry, &tx, &ty, &next))
            break;
        if (next == None)
            break;
        under = next;
    }

    for (;;) {
        Window wroot = None, parent = None, *children = NULL;
        unsigned int nchildren = 0;

        pid = [[GWX11WindowManager sharedManager] getPIDForWindow: dpy
                                                           window: under];
        if (pid != 0 || under == root)
            break;
        if (!XQueryTree(dpy, under, &wroot, &parent, &children, &nchildren))
            break;
        if (children != NULL)
            XFree(children);
        if (parent == None || parent == under)
            break;
        under = parent;
    }

    if (pid == getpid())
        return NO;

    /* Nobody claims the window.  It is not ours as far as anyone can tell,
       but say foreign only when the owner is actually known: an application
       that sets no _NET_WM_PID must not make icon moves end at random, and
       neither must our own windows should this GNUstep stop setting it. */
    return (pid != 0);
}

#else /* _WIN32 */

#import "GWWin32Process.h"

/* Windows: there is no X11 server to query, so window management for
 * non-GNUstep applications is unavailable.  Every query answers "no windows"
 * and every operation reports failure; process liveness uses Win32. */

#pragma mark - GWX11WindowManager Implementation (Windows stub)

@implementation GWX11WindowManager

static GWX11WindowManager *sharedWindowManager = nil;

+ (instancetype)sharedManager
{
    if (sharedWindowManager == nil) {
        sharedWindowManager = [[GWX11WindowManager alloc] init];
    }
    return sharedWindowManager;
}

- (void)closeThreadDisplay
{
}

- (NSArray *)allClientWindows
{
    return [NSArray array];
}

- (NSArray *)windowsForPID:(pid_t)pid
{
    return [NSArray array];
}

- (NSArray *)windowsMatchingName:(NSString *)name
{
    return [NSArray array];
}

- (unsigned long)findWindowByName:(NSString *)name
{
    return 0;
}

- (unsigned long)findWindowByPID:(pid_t)pid
{
    return 0;
}

- (BOOL)activateWindow:(unsigned long)windowID
{
    return NO;
}

- (BOOL)activateWindowsForPID:(pid_t)pid
{
    return NO;
}

- (BOOL)activateWindowsMatchingName:(NSString *)name
{
    return NO;
}

- (BOOL)iconifyWindow:(unsigned long)windowID
{
    return NO;
}

- (BOOL)iconifyWindowsForPID:(pid_t)pid
{
    return NO;
}

- (BOOL)iconifyWindowsMatchingName:(NSString *)name
{
    return NO;
}

- (BOOL)iconifyNonGNUstepWindowsExceptPID:(pid_t)pid
{
    return NO;
}

- (BOOL)restoreIconifiedWindows
{
    return NO;
}

- (BOOL)restoreWindow:(unsigned long)windowID
{
    return NO;
}

- (BOOL)restoreWindowsForPID:(pid_t)pid
{
    return NO;
}

- (BOOL)restoreWindowsMatchingName:(NSString *)name
{
    return NO;
}

- (BOOL)setIconGeometry:(NSRect)rect forPID:(pid_t)pid
{
    return NO;
}

- (BOOL)setIconGeometry:(NSRect)rect forName:(NSString *)name
{
    return NO;
}

- (BOOL)isWindowIconified:(unsigned long)windowID
{
    return NO;
}

- (BOOL)isWindowVisible:(unsigned long)windowID
{
    return NO;
}

- (BOOL)hasWindowsForPID:(pid_t)pid
{
    return NO;
}

- (BOOL)hasWindowsMatchingName:(NSString *)name
{
    return NO;
}

- (BOOL)closeWindow:(unsigned long)windowID
{
    return NO;
}

- (BOOL)closeWindowsForPID:(pid_t)pid
{
    return NO;
}

- (BOOL)animateWindowClose:(unsigned long)windowID
               targetRect:(NSRect)targetRect
{
    return NO;
}

- (BOOL)windowManagerSupportsWindowAnimation
{
    return NO;
}

- (BOOL)contentRectFromXGeometry:(GWNativeWindowID)xwindow
                    screenHeight:(CGFloat)screenHeight
                        outRect:(NSRect *)outRect
{
    return NO;
}

- (BOOL)frameExtentsForWindow:(GWNativeWindowID)xwindow
                      outLeft:(unsigned long *)l
                     outRight:(unsigned long *)r
                      outTop:(unsigned long *)t
                   outBottom:(unsigned long *)b
{
    return NO;
}

- (BOOL)windowIsMappedAndFramed:(GWNativeWindowID)xwindow
{
    return NO;
}

@end

#pragma mark - GWX11AppManager Implementation (Windows stub)

@implementation GWX11AppManager

@synthesize delegate;

static GWX11AppManager *sharedX11AppManager = nil;

+ (instancetype)sharedManager
{
    if (sharedX11AppManager == nil) {
        sharedX11AppManager = [[GWX11AppManager alloc] init];
    }
    return sharedX11AppManager;
}

- (id)init
{
    self = [super init];
    if (self) {
        x11Apps = [[NSMutableDictionary alloc] init];
        monitorTimer = nil;
        delegate = nil;
    }
    return self;
}

- (void)dealloc
{
    [monitorTimer invalidate];
    RELEASE(x11Apps);
    [super dealloc];
}

- (BOOL)processExists:(pid_t)pid
{
    return GWWin32ProcessIsAlive(pid);
}

- (void)registerX11App:(NSString *)appName
                  path:(NSString *)appPath
                   pid:(pid_t)pid
    windowSearchString:(NSString *)windowSearchString
{
    static BOOL warned = NO;

    if (!warned) {
        warned = YES;
        NSLog(@"GWX11AppManager: non-GNUstep application windows are not managed on Windows");
    }
    if (appName != nil) {
        [x11Apps setObject: [NSNumber numberWithInt: (int)pid] forKey: appName];
    }
}

- (void)unregisterX11App:(NSString *)appName
{
    if (appName != nil) {
        [x11Apps removeObjectForKey: appName];
    }
}

- (BOOL)isX11App:(NSString *)appName
{
    return (appName != nil && [x11Apps objectForKey: appName] != nil);
}

- (BOOL)activateX11App:(NSString *)appName
{
    return NO;
}

- (BOOL)hideX11App:(NSString *)appName
{
    return NO;
}

- (BOOL)unhideX11App:(NSString *)appName
{
    return NO;
}

- (BOOL)x11AppHasVisibleWindows:(NSString *)appName
{
    return NO;
}

- (pid_t)pidForX11App:(NSString *)appName
{
    NSNumber *pid = (appName != nil) ? [x11Apps objectForKey: appName] : nil;

    return (pid != nil) ? (pid_t)[pid intValue] : 0;
}

- (BOOL)quitX11App:(NSString *)appName timeout:(NSTimeInterval)timeout
{
    pid_t pid = [self pidForX11App: appName];

    if (pid <= 0) {
        return NO;
    }
    if (GWWin32TerminateProcess(pid)) {
        [self unregisterX11App: appName];
        return YES;
    }
    return NO;
}

@end

#pragma mark - Windows stubs for the C entry points

void GWInstallX11IOErrorLogger(void)
{
}

BOOL GWForeignWindowIsUnderPointer(void)
{
    return NO;
}

#endif /* _WIN32 */
