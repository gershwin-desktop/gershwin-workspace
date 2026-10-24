/* t_DockDragRemoval.m - an item never leaves the Dock by being dragged.
 *
 * Dragging a Dock item out and letting go of it anywhere outside the Dock -
 * on the desktop, on nothing at all, however far out, or on a destination
 * that took the drop - puts it back where it was; the saved Dock contents
 * do not change.  Taking an item out of the Dock is the context menu's
 * "Remove from Dock" alone.  Moving an item along the Dock by dragging still
 * reorders it.
 *
 * Compiles Dock.m in-process, linked like t_DockInsertionRemoval (see
 * GNUmakefile.preamble), so the real -iconDragEnded:, -draggingUpdated:,
 * -iconMenuAction: and -saveDockConfiguration run.  The icons are the
 * stand-ins of Collab/DockDragStubs.m.  The Dock has no window here; the
 * test Dock answers the bar's place on the screen itself and does not lay
 * its icons out, which needs a screen and is not under test.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#include "../../Workspace/Desktop/Dock/Dock.m"
#import "Collab/DockDragStubs.h"

static NSString * const kAppA = @"/Applications/DockDragTestA.app";
static NSString * const kAppB = @"/Applications/DockDragTestB.app";
static NSString * const kFolder = @"/DockDragTest/Folder";

/* A bottom Dock 64 points high along the bottom of a 1000 point screen. */
@interface DragTestDock : Dock
- (void)addTestIcon:(DockIcon *)icon at:(CGFloat)x;
- (NSArray *)testIcons;
- (void)beginDragOf:(DockIcon *)icon;
@end

@implementation DragTestDock
- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self != nil)
    {
      /* What -initForManager: sets up: no drag in progress, at the bottom. */
      icons = [NSMutableArray new];
      targetIndex = -1;
      folderTargetIndex = -1;
      position = DockPositionBottom;
      baseCell = 64;
    }
  return self;
}
- (NSRect)barFrame
{
  return NSMakeRect(0, 0, 400, 64);
}
- (void)tile
{
}
- (void)addTestIcon:(DockIcon *)icon at:(CGFloat)x
{
  [icon setFrame: NSMakeRect(x, 0, 64, 64)];
  [icons addObject: icon];
  [self addSubview: icon];
}
- (NSArray *)testIcons
{
  return icons;
}
/* What DockIcon's -startExternalDragOnEvent:withMouseOffset: tells the Dock. */
- (void)beginDragOf:(DockIcon *)icon
{
  [icon setIsDndSourceIcon: YES];
  [self setDndSourceIcon: icon];
}
@end

/* Just enough of a drag in progress for -draggingUpdated:: who drags, and
 * where the pointer is in the Dock's (windowless) coordinates. */
@interface DragTestInfo : NSObject
{
  id source;
  NSPoint location;
}
- (id)initWithSource:(id)s location:(NSPoint)p;
@end

@implementation DragTestInfo
- (id)initWithSource:(id)s location:(NSPoint)p
{
  self = [super init];
  source = s;
  location = p;
  return self;
}
- (id)draggingSource { return source; }
- (NSPoint)draggingLocation { return location; }
- (NSPasteboard *)draggingPasteboard { return nil; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationMove; }
@end

static NSDictionary *
savedApplications(void)
{
  return [[NSUserDefaults standardUserDefaults] objectForKey: @"applications"];
}

static NSString *
savedPathAt(NSString *index)
{
  return [[savedApplications() objectForKey: index] objectForKey: @"path"];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *domain = [[NSProcessInfo processInfo] processName];
  DragTestDock *dock;
  DockIcon *a, *b, *folder;
  NSDictionary *before;

  /* The saved Dock contents go to this tool's own defaults domain; start
   * from nothing and leave nothing behind. */
  [defaults removePersistentDomainForName: domain];

  dock = [[DragTestDock alloc] initWithFrame: NSMakeRect(0, 0, 400, 64)];
  a = [[DockIcon alloc] initStandInWithPath: kAppA docked: YES];
  b = [[DockIcon alloc] initStandInWithPath: kAppB docked: YES];
  folder = [[DockIcon alloc] initStandInWithPath: kFolder docked: YES];
  [dock addTestIcon: a at: 0];
  [dock addTestIcon: b at: 64];
  [dock addTestIcon: folder at: 128];
  [dock saveDockConfiguration];
  before = [savedApplications() copy];
  NEED(PASS([before count] == 2 && [savedPathAt(@"0") isEqual: kAppA],
            "fixture: both applications are saved in the Dock"));

  /* --- dragged out and let go anywhere: it stays ---
   * DockIcon reports the end of every drag of it this way, wherever it was
   * let go: on the desktop, on the Trash, on another destination, on
   * nothing, however far out. */
  {
    [dock beginDragOf: a];
    [dock iconDragEnded: a];
    PASS([[dock testIcons] indexOfObjectIdenticalTo: a] == 0,
         "an application dragged out of the Dock stays in its place");
    PASS([a isDndSourceIconForTest] == NO,
         "it shows again once the drag is over");

    [dock beginDragOf: folder];
    [dock iconDragEnded: folder];
    PASS([[dock testIcons] indexOfObjectIdenticalTo: folder] == 2,
         "a kept folder dragged out of the Dock stays too");

    PASS([[dock testIcons] count] == 3
         && [savedApplications() isEqual: before]
         && [[defaults objectForKey: @"folders"] count] == 1,
         "no drag changed the saved Dock contents");
  }

  /* --- dragged along the Dock: it reorders --- */
  {
    DragTestInfo *info;
    int i;

    [dock beginDragOf: a];
    info = [[DragTestInfo alloc] initWithSource: a location: NSMakePoint(96, 32)];
    /* The Dock lets the first two updates of a drag pass before it acts. */
    for (i = 0; i < 3; i++)
      [dock draggingUpdated: (id <NSDraggingInfo>)info];
    [dock concludeDragOperation: (id <NSDraggingInfo>)info];
    [dock iconDragEnded: a];
    [info release];

    PASS([[dock testIcons] indexOfObjectIdenticalTo: a] == 1
         && [[dock testIcons] indexOfObjectIdenticalTo: b] == 0,
         "an application dragged onto the next one takes its place");
    PASS([savedPathAt(@"0") isEqual: kAppB] && [savedPathAt(@"1") isEqual: kAppA],
         "the new order is saved as soon as the drag ends");
  }

  /* --- the context menu takes it out, and that is saved --- */
  {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:
                          NSLocalizedString(@"Remove from Dock", @"")
                                                  action: @selector(iconMenuAction:)
                                           keyEquivalent: @""];

    [item setRepresentedObject: a];
    [dock iconMenuAction: item];
    [item release];

    PASS([[dock testIcons] indexOfObjectIdenticalTo: a] == NSNotFound,
         "Remove from Dock takes a docked application out of the Dock");
    PASS([savedApplications() count] == 1 && [savedPathAt(@"0") isEqual: kAppB],
         "and the saved Dock contents no longer hold it");

    item = [[NSMenuItem alloc] initWithTitle: NSLocalizedString(@"Remove from Dock", @"")
                                      action: @selector(iconMenuAction:)
                               keyEquivalent: @""];
    [item setRepresentedObject: folder];
    [dock iconMenuAction: item];
    [item release];
    PASS([[dock testIcons] indexOfObjectIdenticalTo: folder] == NSNotFound
         && [[defaults objectForKey: @"folders"] count] == 0,
         "Remove from Dock takes a kept folder out, and that is saved");
  }

  [before release];
  [a release];
  [b release];
  [folder release];
  [dock release];
  [defaults removePersistentDomainForName: domain];
  [arp release];
  return 0;
}
