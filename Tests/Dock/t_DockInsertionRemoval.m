/* t_DockInsertionRemoval.m - an item taken out of the Dock while it still
 * grows in must not be messaged again once it is freed.
 *
 * -growIn: remembers growing items without retaining them, and the 60 Hz
 * insertion tick, -missingLength and -presenceOf: read them back.  An icon or
 * miniature tile added and removed within DOCK_INSERTION_DURATION used to stay
 * in that bookkeeping, so the next tick sent -superview to a freed object
 * (Workspace SIGBUS in -[Dock(Insertion) insertionTick:] in CI).
 *
 * Compiles Dock.m in-process, linked like t_DockLaunchRefreshThread (see
 * GNUmakefile.preamble), so the real -growIn:, -insertionTick: and NSView's
 * own removal path run, and the tick fires from its own timer.  The item is owned only by the Dock, as icons and
 * tiles are in production, so removing it frees it.  A freed object is not
 * guaranteed to crash when messaged, so the tool re-execs itself with
 * NSZombieEnabled and fails on the zombie report instead.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#include <unistd.h>
#include "../../Workspace/Desktop/Dock/Dock.m"

/* -growIn: only animates while the Dock is on the screen; a real window
 * would need a display, and nothing else of it is used here. */
@interface InsertionShownWindow : NSObject
- (BOOL)isVisible;
@end

@implementation InsertionShownWindow
- (BOOL)isVisible
{
  return YES;
}
@end

/* Laying out and publishing icon geometry need the desktop manager and X;
 * they are not what is under test, only the bookkeeping around them. */
@interface InsertionTestDock : Dock
{
  InsertionShownWindow *shownWindow;
  BOOL growing;
}
- (BOOL)isTicking;
@end

@implementation InsertionTestDock
- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self != nil)
    {
      shownWindow = [InsertionShownWindow new];
      /* What -initForManager: sets up: no drag in progress, a 64 pt cell. */
      targetIndex = -1;
      folderTargetIndex = -1;
      baseCell = 64;
    }
  return self;
}
- (BOOL)isTicking
{
  return insertionTimer != nil;
}
/* Only -growIn: is shown the window: NSView's own coordinate code would
 * take the stand-in for a real one. */
- (void)growIn:(NSView *)item
{
  growing = YES;
  [super growIn: item];
  growing = NO;
}
- (NSWindow *)window
{
  return growing ? (NSWindow *)shownWindow : [super window];
}
- (void)layoutIcons
{
}
- (void)updateIconGeometries
{
}
@end

/* Runs block with stderr redirected to a file and returns what it wrote,
 * because GNUstep zombies report on stderr with fprintf. */
static NSString *
stderrOf(void (^block)(void))
{
  char path[] = "/tmp/t_DockInsertionRemoval.XXXXXX";
  int fd = mkstemp(path);
  int saved = dup(2);
  NSString *text;

  fflush(stderr);
  dup2(fd, 2);
  block();
  fflush(stderr);
  dup2(saved, 2);
  close(saved);
  close(fd);
  text = [NSString stringWithContentsOfFile: [NSString stringWithUTF8String: path]];
  unlink(path);
  return text != nil ? text : @"";
}

int
main(int argc, char **argv)
{
  NSAutoreleasePool *arp;
  InsertionTestDock *dock;
  __block NSView *item;
  __block CGFloat missing = -1;
  NSString *zombies;

  /* NSObject reads NSZombieEnabled before main runs. */
  if (getenv("NSZombieEnabled") == NULL)
    {
      setenv("NSZombieEnabled", "YES", 1);
      execv(argv[0], argv);
      perror("execv");
      return 1;
    }

  arp = [NSAutoreleasePool new];
  /* A user who asked for reduced motion would skip the animation, and with
   * it the bookkeeping under test. */
  [[NSUserDefaults standardUserDefaults]
    removeVolatileDomainForName: NSArgumentDomain];
  [[NSUserDefaults standardUserDefaults]
    setVolatileDomain: [NSDictionary dictionaryWithObject: @"NO"
                                                   forKey: @"GSReduceMotion"]
              forName: NSArgumentDomain];

  dock = [[InsertionTestDock alloc] initWithFrame: NSMakeRect(0, 0, 400, 64)];

  zombies = stderrOf(^{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];

    item = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 64, 64)];
    [dock addSubview: item];
    [item release];
    [dock growIn: item];
    [pool release];

    pool = [NSAutoreleasePool new];
    [item removeFromSuperview];
    missing = [dock missingLength];
    [pool release];

    /* The run loop drops NSView's pending redisplay, the last hold on the
     * item, and then fires the insertion timer -growIn: started, as in
     * Workspace. */
    [[NSRunLoop currentRunLoop] runUntilDate:
      [NSDate dateWithTimeIntervalSinceNow: 0.1]];
  });

  PASS([zombies rangeOfString: @"deallocated instance"].location == NSNotFound,
       "an item removed while it grows in is not messaged after it is freed");
  PASS(missing == 0,
       "a removed item no longer takes room from the Dock");
  PASS([dock isTicking] == NO,
       "the insertion tick stops once nothing grows in any more");

  [arp release];
  return 0;
}
