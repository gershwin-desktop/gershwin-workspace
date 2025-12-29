/* X11AppSupport.m
 *
 * Author: Gershwin Team
 * Date: December 2025
 */

#import "X11AppSupport.h"
#import <AppKit/AppKit.h>

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>

#include <sys/types.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#pragma mark - X11 Error Handler

/* Custom X error handler to prevent crashes from BadWindow/BadMatch errors.
 * These can occur when windows are destroyed between discovery and operation. */
static int gwX11ErrorHandler(Display *dpy, XErrorEvent *event)
{
    char errorText[256];
    XGetErrorText(dpy, event->error_code, errorText, sizeof(errorText));
    NSLog(@"GWorkspace X11 error: %s (request %d, error %d)",
          errorText, event->request_code, event->error_code);
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
            windowID, windowName, windowClass, ownerPID];
}

@end

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

- (Display *)openDisplay
{
    ensureX11ErrorHandler();
    Display *dpy = XOpenDisplay(NULL);
    if (dpy) {
        /* Sync to catch any pending errors before returning */
        XSync(dpy, False);
    }
    return dpy;
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
                GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                [windows addObject:info];
            }
            XFree(clients);
        }
    }
    @finally {
        XCloseDisplay(dpy);
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
                    GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                    [windows addObject:info];
                }
            }
            XFree(clients);
        }
    }
    @finally {
        XCloseDisplay(dpy);
    }
    
    return windows;
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
            for (unsigned long i = 0; i < count; i++) {
                NSString *winName = [self getWindowName:dpy window:clients[i]];
                NSString *winClass = [self getWindowClass:dpy window:clients[i]];
                
                BOOL matches = NO;
                if (winName && [winName rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    matches = YES;
                } else if (winClass && [winClass rangeOfString:name options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    matches = YES;
                }
                
                if (matches) {
                    GWX11WindowInfo *info = [self infoForWindow:dpy window:clients[i]];
                    [windows addObject:info];
                }
            }
            XFree(clients);
        }
    }
    @finally {
        XCloseDisplay(dpy);
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
        XCloseDisplay(dpy);
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
        XCloseDisplay(dpy);
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
        XCloseDisplay(dpy);
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
        XCloseDisplay(dpy);
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
        XCloseDisplay(dpy);
    }
    
    return visible;
}

- (BOOL)hasWindowsForPID:(pid_t)pid
{
    return [[self windowsForPID:pid] count] > 0;
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
        XCloseDisplay(dpy);
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

@end

#pragma mark - X11 Application Info

@interface GWX11AppInfo : NSObject
{
    NSString *appName;
    NSString *appPath;
    NSString *windowSearchString;
    pid_t pid;
    BOOL hasWindowAppeared;
}
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, copy) NSString *appPath;
@property (nonatomic, copy) NSString *windowSearchString;
@property (nonatomic, assign) pid_t pid;
@property (nonatomic, assign) BOOL hasWindowAppeared;
@end

@implementation GWX11AppInfo
@synthesize appName, appPath, windowSearchString, pid, hasWindowAppeared;

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
        /* Use faster initial polling (100ms) for quicker window detection */
        monitorTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
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
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    NSMutableArray *terminatedApps = [NSMutableArray array];
    BOOL allAppsHaveWindows = YES;
    
    for (NSString *appName in [x11Apps allKeys]) {
        GWX11AppInfo *info = [x11Apps objectForKey:appName];
        if (info == nil) continue;
        
        /* Check if process still exists */
        if (![self processExists:info.pid]) {
            [terminatedApps addObject:appName];
            continue;
        }
        
        /* Check if windows have appeared for this app */
        if (!info.hasWindowAppeared) {
            allAppsHaveWindows = NO;
            
            /* Priority 1: Try to find windows by PID (most reliable) */
            NSArray *windows = [wm windowsForPID:info.pid];
            
            /* Priority 2: Fall back to name matching if PID fails */
            if ([windows count] == 0 && info.windowSearchString) {
                windows = [wm windowsMatchingName:info.windowSearchString];
            }
            
            if ([windows count] > 0) {
                info.hasWindowAppeared = YES;
                
                if (delegate && [delegate respondsToSelector:@selector(x11AppWindowsDidAppear:path:)]) {
                    [delegate x11AppWindowsDidAppear:info.appName path:info.appPath];
                }
            }
        }
    }
    
    /* Handle terminated apps */
    for (NSString *appName in terminatedApps) {
        GWX11AppInfo *info = [x11Apps objectForKey:appName];
        if (info == nil) continue;
        NSString *appPath = [[info.appPath retain] autorelease];
        
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
    
    if ([wm activateWindowsMatchingName:info.windowSearchString]) {
        return YES;
    }
    
    return [wm activateWindowsForPID:info.pid];
}

- (BOOL)hideX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    if ([wm iconifyWindowsMatchingName:info.windowSearchString]) {
        return YES;
    }
    
    return [wm iconifyWindowsForPID:info.pid];
}

- (BOOL)unhideX11App:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    if ([wm restoreWindowsMatchingName:info.windowSearchString]) {
        return YES;
    }
    
    return [wm restoreWindowsForPID:info.pid];
}

- (BOOL)x11AppHasVisibleWindows:(NSString *)appName
{
    GWX11AppInfo *info = [x11Apps objectForKey:appName];
    if (!info) return NO;
    
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    NSArray *windows = [wm windowsMatchingName:info.windowSearchString];
    if ([windows count] == 0) {
        windows = [wm windowsForPID:info.pid];
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
