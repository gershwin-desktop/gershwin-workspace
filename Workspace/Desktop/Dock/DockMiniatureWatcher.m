/* DockMiniatureWatcher.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "DockMiniatureWatcher.h"

#ifndef _WIN32
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <math.h>
#endif

@interface DockMiniatureWatcher () <RunLoopEvents>
@end

@implementation DockMiniatureWatcher
{
  id<DockMiniatureWatcherDelegate> delegate;
#ifndef _WIN32
  Display *display;
  Window root;
  Atom listAtom;
  Atom answerAtom;
  Atom geometryAtom;
#endif
  int fd;
  /* What was last written per window (NSValue of NSRect), and so which
   * windows have been answered. */
  NSMutableDictionary *placed;
}

- (id)initWithDelegate:(id<DockMiniatureWatcherDelegate>)aDelegate
{
#ifdef _WIN32
  RELEASE (self);
  return nil;
#else
  self = [super init];
  if (self == nil)
    return nil;

  /* A connection of its own: the backend's reads every event of its own
   * connection, so the root's property changes have to arrive here. */
  display = XOpenDisplay(NULL);
  if (display == NULL)
    {
      RELEASE (self);
      return nil;
    }
  delegate = aDelegate;
  placed = [NSMutableDictionary new];
  root = DefaultRootWindow(display);
  listAtom = XInternAtom(display, "_WINDOW_LIVE_MINIATURES", False);
  answerAtom = XInternAtom(display, "_WINDOW_LIVE_MINIATURE", False);
  geometryAtom = XInternAtom(display, "_NET_WM_ICON_GEOMETRY", False);
  XSelectInput(display, root, PropertyChangeMask);
  XFlush(display);

  /* The run loop wakes when the connection has something to read, instead
   * of the Dock asking on a timer. */
  fd = ConnectionNumber(display);
  [[NSRunLoop currentRunLoop] addEvent: (void *)(intptr_t)fd
                                  type: ET_RDESC
                               watcher: self
                               forMode: NSDefaultRunLoopMode];
  return self;
#endif
}

- (void)dealloc
{
  [self stop];
  RELEASE (placed);
  [super dealloc];
}

- (void)stop
{
#ifndef _WIN32
  if (display != NULL)
    {
      [[NSRunLoop currentRunLoop] removeEvent: (void *)(intptr_t)fd
                                         type: ET_RDESC
                                      forMode: NSDefaultRunLoopMode
                                          all: YES];
      XCloseDisplay(display);
      display = NULL;
    }
#endif
}

- (void)receivedEvent:(void *)data
                 type:(RunLoopEventType)type
                extra:(void *)extra
              forMode:(NSString *)mode
{
#ifndef _WIN32
  BOOL changed = NO;

  while (display != NULL && XPending(display) > 0)
    {
      XEvent event;

      XNextEvent(display, &event);
      if (event.type == PropertyNotify
          && event.xproperty.window == root
          && event.xproperty.atom == listAtom)
        changed = YES;
    }
  if (changed)
    [delegate miniatureWatcherListChanged: self];
#endif
}

- (NSArray *)listedWindows
{
  NSMutableArray *windows = [NSMutableArray array];
#ifndef _WIN32
  Atom type;
  int format;
  unsigned long count, after;
  unsigned char *data = NULL;

  if (display == NULL)
    return windows;
  if (XGetWindowProperty(display, root, listAtom, 0, 1024, False, XA_WINDOW,
                         &type, &format, &count, &after, &data) == Success
      && data != NULL)
    {
      if (type == XA_WINDOW && format == 32)
        {
          unsigned long *ids = (unsigned long *)data;
          unsigned long i;

          for (i = 0; i < count; i++)
            [windows addObject: [NSNumber numberWithUnsignedLong: ids[i]]];
        }
      XFree(data);
    }
#endif
  return windows;
}

- (void)placeTile:(NSRect)rect
        forWindow:(unsigned long)window
       dockWindow:(unsigned long)dockWindow
{
#ifndef _WIN32
  NSNumber *key = [NSNumber numberWithUnsignedLong: window];
  NSValue *last = [placed objectForKey: key];
  long geometry[4];

  if (display == NULL || NSIsEmptyRect(rect))
    return;
  if (last != nil && NSEqualRects([last rectValue], rect))
    return;

  geometry[0] = (long)llround(NSMinX(rect));
  geometry[1] = (long)llround(NSMinY(rect));
  geometry[2] = (long)llround(NSWidth(rect));
  geometry[3] = (long)llround(NSHeight(rect));
  XChangeProperty(display, window, geometryAtom, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)geometry, 4);
  /* The answer goes after the rect, so the window manager never takes a
   * window for answered while it still holds its application's icon rect. */
  if (last == nil)
    {
      long dock = (long)dockWindow;

      XChangeProperty(display, window, answerAtom, XA_WINDOW, 32,
                      PropModeReplace, (unsigned char *)&dock, 1);
    }
  XFlush(display);
  [placed setObject: [NSValue valueWithRect: rect] forKey: key];
#endif
}

- (NSString *)titleOfWindow:(unsigned long)window
{
  NSString *title = nil;
#ifndef _WIN32
  Atom type;
  int format;
  unsigned long count, after;
  unsigned char *data = NULL;

  if (display == NULL)
    return nil;
  if (XGetWindowProperty(display, window,
                         XInternAtom(display, "_NET_WM_NAME", False),
                         0, 1024, False,
                         XInternAtom(display, "UTF8_STRING", False),
                         &type, &format, &count, &after, &data) == Success
      && data != NULL)
    {
      if (format == 8 && count > 0)
        title = AUTORELEASE ([[NSString alloc] initWithBytes: data
                                                      length: count
                                                    encoding: NSUTF8StringEncoding]);
      XFree(data);
    }
#endif
  return title;
}

- (void)forgetWindow:(unsigned long)window
{
  [placed removeObjectForKey: [NSNumber numberWithUnsignedLong: window]];
}

@end
