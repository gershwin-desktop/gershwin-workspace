/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* A link dropped into an icon view, or on a folder icon in it, becomes an
 * Internet location file in that folder; anything else that is not a file
 * list is refused. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNode.h"

@interface FakePB : NSObject
{
  NSDictionary *items;
}
- (id)initWithItems:(NSDictionary *)i;
@end

@implementation FakePB
- (id)initWithItems:(NSDictionary *)i
{
  items = [i retain];
  return self;
}
- (NSArray *)types { return [items allKeys]; }
- (id)propertyListForType:(NSString *)t { return [items objectForKey: t]; }
- (NSString *)stringForType:(NSString *)t { return [items objectForKey: t]; }
@end

/* The views ask their desktop application where the trash is. */
@interface FakeDesktop : NSObject
+ (id)sharedFake;
- (NSString *)trashPath;
- (void)selectionChanged:(NSArray *)newsel;
@end

@implementation FakeDesktop
+ (id)sharedFake { static id shared; return shared ? shared : (shared = [self new]); }
- (NSString *)trashPath { return @"/nonexistent/trash"; }
- (void)selectionChanged:(NSArray *)newsel { }
@end

/* Just enough of NSDraggingInfo for the destination methods under test. */
@interface FakeDrag : NSObject
{
  FakePB *pb;
@public
  NSPoint location;
}
- (id)initWithItems:(NSDictionary *)i;
@end

@implementation FakeDrag
- (id)initWithItems:(NSDictionary *)i
{
  pb = [[FakePB alloc] initWithItems: i];
  return self;
}
- (NSPasteboard *)draggingPasteboard { return (NSPasteboard *)pb; }
- (NSPoint)draggingLocation { return location; }
- (NSDragOperation)draggingSourceOperationMask { return NSDragOperationEvery; }
@end

static FakeDrag *
dragOf(NSString *type, id value)
{
  return [[[FakeDrag alloc] initWithItems:
	     [NSDictionary dictionaryWithObject: value forKey: type]]
	   autorelease];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir, *sub;
  FSNIconsView *view;
  FSNIcon *folder;

  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [[NSUserDefaults standardUserDefaults] setObject: @"FakeDesktop"
					    forKey: @"DesktopApplicationName"];
  [[NSUserDefaults standardUserDefaults] setObject: @"sharedFake"
					    forKey: @"DesktopApplicationSelName"];
  [NSApplication sharedApplication];

  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
	  [NSString stringWithFormat: @"t_FSNIconsViewURLDrop_%d", (int)getpid()]];
  sub = [dir stringByAppendingPathComponent: @"Folder"];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createDirectoryAtPath: sub attributes: nil];

  view = [[FSNIconsView alloc] init];
  [view showContentsOfNode: [FSNode nodeWithPath: dir]];

  {
    FakeDrag *url = dragOf(NSURLPboardType, @"https://example.org/a");
    FakeDrag *text = dragOf(NSStringPboardType, @"just some text");

    PASS([view draggingEntered: text] == NSDragOperationNone,
	 "MI-LNK-20 plain text dropped into the view is refused");
    PASS([view draggingEntered: url] == NSDragOperationCopy,
	 "MI-LNK-21 a link dropped into the view is accepted as a copy");
    PASS([view prepareForDragOperation: url], "MI-LNK-22 and may be prepared");
    PASS([view performDragOperation: url], "MI-LNK-23 and performed");
    PASS([fm fileExistsAtPath:
	    [dir stringByAppendingPathComponent: @"example.org.webloc"]],
	 "MI-LNK-24 the location file lands in the viewed folder");
    [view concludeDragOperation: url];
    PASS([[fm directoryContentsAtPath: dir] count] == 2,
	 "MI-LNK-25 concluding the drop adds nothing else");
  }

  folder = [view repOfSubnodePath: sub];
  PASS(folder != nil, "folder icon present");
  if (folder != nil)
    {
      FakeDrag *url = dragOf(NSURLPboardType, @"https://example.org/b");

      /* The drop point has to be on the folder, else the icon hands the drag
       * to its view. */
      NSRect b = [folder bounds];

      url->location = [folder convertPoint:
			 NSMakePoint(NSMidX(b), NSMidY(b)) toView: nil];
      PASS([folder draggingEntered: url] == NSDragOperationCopy,
	   "MI-LNK-26 a link dropped on a folder icon is accepted");
      PASS([folder performDragOperation: url], "MI-LNK-27 and performed");
      PASS([fm fileExistsAtPath:
	      [sub stringByAppendingPathComponent: @"example.org.webloc"]],
	   "MI-LNK-28 the location file lands inside that folder");
    }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
