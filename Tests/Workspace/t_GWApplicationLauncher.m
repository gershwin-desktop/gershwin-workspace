/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_GWApplicationLauncher.m - the error alert for an application that quit
 * with an error must not freeze the screen: while the alert runs its modal
 * loop, the window display performer must still fire, otherwise its text
 * does not scroll and its buttons do not react visibly.
 * Headless: the alert is replaced by a stand-in that runs one modal pass. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWApplicationLauncher.m"

#include <unistd.h>

static NSArray *displayModes = nil;
static unsigned displayCount = 0;

/* Stands in for +[NSWindow _handleAutodisplay:], which requeues itself on
 * every pass in these modes, so it is always pending when an alert opens. */
@interface DisplayStandIn : NSObject
+ (void) queue;
@end

@implementation DisplayStandIn
+ (void) queue
{
  [[NSRunLoop currentRunLoop] performSelector: @selector(fire:)
                                       target: self
                                     argument: nil
                                        order: 600000
                                        modes: displayModes];
}

+ (void) fire: (id)ignored
{
  displayCount++;
  [self queue];
}

+ (void) tick: (NSTimer *)t
{
}
@end

static NSDictionary *alertInfo = nil;
static BOOL displayedDuringAlert = NO;

@interface TestLauncher : GWApplicationLauncher
@end

@implementation TestLauncher
/* NSAlert -runModal runs NSApp's modal loop in NSModalPanelRunLoopMode; one
 * pass of that mode is what decides whether windows get redrawn. */
+ (void)_showErrorAlert:(NSDictionary *)info
{
  unsigned before = displayCount;

  alertInfo = [info retain];
  [[NSRunLoop currentRunLoop]
    runMode: NSModalPanelRunLoopMode
 beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.2]];
  displayedDuringAlert = (displayCount > before);
}
@end

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSRunLoop *run = [NSRunLoop currentRunLoop];
  NSString *name = [NSString stringWithFormat: @"t_GWApplicationLauncher-%d.sh",
                                               (int)getpid()];
  NSString *script = [NSTemporaryDirectory()
                       stringByAppendingPathComponent: name];
  NSString *logPath = [[NSHomeDirectory()
                         stringByAppendingPathComponent: @"Library/Logs"]
                        stringByAppendingPathComponent:
                          [name stringByAppendingPathExtension: @"log"]];
  NSTimer *keepAlive;
  NSTask *task;
  NSDate *limit;

  displayModes = [[NSArray alloc] initWithObjects: NSDefaultRunLoopMode,
                                  NSModalPanelRunLoopMode, nil];

  /* A mode without timers or watchers returns at once; a far future timer
   * keeps both modes runnable. */
  keepAlive = [NSTimer timerWithTimeInterval: 1000.0
                                      target: [DisplayStandIn class]
                                    selector: @selector(tick:)
                                    userInfo: nil
                                     repeats: YES];
  [run addTimer: keepAlive forMode: NSDefaultRunLoopMode];
  [run addTimer: keepAlive forMode: NSModalPanelRunLoopMode];
  [DisplayStandIn queue];

  [fm removeFileAtPath: logPath handler: nil];
  [@"#!/bin/sh\necho 'fatal: something broke' >&2\nexit 3\n"
    writeToFile: script atomically: YES];
  [fm changeFileAttributes:
        [NSDictionary dictionaryWithObject: [NSNumber numberWithShort: 0755]
                                    forKey: NSFilePosixPermissions]
                    atPath: script];

  task = [[NSTask new] autorelease];
  [task setLaunchPath: script];
  PASS([TestLauncher launchAndMonitorTask: task],
       "a task is launched and monitored");

  limit = [NSDate dateWithTimeIntervalSinceNow: 5.0];
  while (alertInfo == nil && [limit timeIntervalSinceNow] > 0)
    {
      [run runMode: NSDefaultRunLoopMode
        beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
    }

  PASS(alertInfo != nil
       && [[alertInfo objectForKey: @"status"] intValue] == 3,
       "an application that exits with an error status gets the error alert");
  PASS([[alertInfo objectForKey: @"stderr"]
         rangeOfString: @"fatal: something broke"].location != NSNotFound,
       "the error alert shows what the application wrote to stderr");
  PASS(displayedDuringAlert,
       "windows are still redrawn while the error alert runs its modal loop");

  [keepAlive invalidate];
  [fm removeFileAtPath: script handler: nil];
  [fm removeFileAtPath: logPath handler: nil];
  [arp release];
  return 0;
}
