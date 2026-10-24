/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWNavigationHistory - the per-window Back/Forward history of a browsing
 * viewer.  Headless: the history only compares items with -isEqual: and asks
 * them -isValid, so plain strings and a tiny stand-in for a vanished folder
 * are enough. */

#import "Testing.h"
#import <Foundation/Foundation.h>

#include "../../Workspace/FileViewer/GWNavigationHistory.m"

/* A folder that may disappear while it is in the history. */
@interface TestItem : NSObject {
@public
  NSString *name;
  BOOL valid;
}
+ (TestItem *)itemNamed:(NSString *)n;
@end

@implementation TestItem
+ (TestItem *)itemNamed:(NSString *)n
{
  TestItem *it = [[TestItem new] autorelease];
  it->name = [n copy];
  it->valid = YES;
  return it;
}
- (void)dealloc
{
  [name release];
  [super dealloc];
}
- (BOOL)isValid
{
  return valid;
}
- (BOOL)isEqual:(id)other
{
  return [other isKindOfClass:[TestItem class]] && [name isEqual:((TestItem *)other)->name];
}
- (NSUInteger)hash
{
  return [name hash];
}
@end

static NSString *const kLongLiteral = @"navigation history test";

static GWNavigationHistory *historyWith(NSArray *names)
{
  GWNavigationHistory *h = [[GWNavigationHistory new] autorelease];
  NSUInteger i;

  for (i = 0; i < [names count]; i++)
    [h addItem:[names objectAtIndex:i] maxCount:50];
  return h;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("empty history");
  {
    GWNavigationHistory *h = [[GWNavigationHistory new] autorelease];
    PASS([h canGoBack] == NO, "a new window cannot go back");
    PASS([h canGoForward] == NO, "a new window cannot go forward");
    PASS([h positionAfterStep:-1] == NSNotFound, "no step back from nothing");
    PASS([h currentItem] == nil, "no current folder yet");
  }
  END_SET("empty history");

  START_SET("visiting folders");
  {
    GWNavigationHistory *h = historyWith(@[ @"/", @"/home", @"/home/u" ]);
    PASS([[h items] count] == 3, "three visited folders are kept");
    PASS([h position] == 2, "the last visited folder is current");
    PASS([h canGoBack], "after two moves Back is possible");
    PASS([h canGoForward] == NO, "Forward is not possible at the end");

    [h addItem:@"/home/u" maxCount:50];
    PASS([[h items] count] == 3, "showing the current folder again adds nothing");
  }
  END_SET("visiting folders");

  START_SET("back and forward");
  {
    GWNavigationHistory *h = historyWith(@[ @"/", @"/home", @"/home/u" ]);
    NSInteger p = [h positionAfterStep:-1];

    PASS(p == 1, "one step back lands on the previous folder");
    [h setPosition:p];
    PASS_EQUAL([h currentItem], @"/home", "the previous folder is current");
    PASS([h canGoBack] && [h canGoForward], "in the middle both ways are open");

    p = [h positionAfterStep:1];
    PASS(p == 2, "one step forward returns to the later folder");
    [h setPosition:0];
    PASS([h positionAfterStep:-1] == NSNotFound, "nothing before the first folder");
    PASS([h canGoBack] == NO, "Back is closed at the first folder");
  }
  END_SET("back and forward");

  START_SET("a new folder after going back drops the forward branch");
  {
    GWNavigationHistory *h = historyWith(@[ @"/a", @"/b", @"/c" ]);
    NSArray *want = @[ @"/a", @"/b", @"/d" ];

    [h setPosition:1];
    [h addItem:@"/d" maxCount:50];
    PASS_EQUAL([h items], want, "the forward folders are replaced by the new one");
    PASS([h position] == 2, "the new folder is current");
    PASS([h canGoForward] == NO, "Forward is closed after branching off");
  }
  END_SET("a new folder after going back drops the forward branch");

  START_SET("showing the next folder again keeps the forward branch");
  {
    GWNavigationHistory *h = historyWith(@[ @"/a", @"/b", @"/c" ]);
    NSArray *want = @[ @"/a", @"/b", @"/c" ];

    /* Opening the folder that Forward would show must behave like Forward,
     * not wipe what lies beyond it. */
    [h setPosition:0];
    [h addItem:@"/b" maxCount:50];
    PASS_EQUAL([h items], want, "the history is unchanged");
    PASS([h position] == 1, "the reopened folder is current");
    PASS([h canGoForward], "Forward still leads to the later folder");
  }
  END_SET("showing the next folder again keeps the forward branch");

  START_SET("the size limit drops the oldest folders");
  {
    GWNavigationHistory *h = [[GWNavigationHistory new] autorelease];
    NSArray *want = @[ @"/3", @"/4", @"/5" ];
    int i;

    for (i = 1; i <= 5; i++)
      [h addItem:[NSString stringWithFormat:@"/%d", i] maxCount:2];
    PASS_EQUAL([h items], want, "only the newest folders stay");
    PASS([h position] == 2, "the current folder stays current");
  }
  END_SET("the size limit drops the oldest folders");

  START_SET("vanished folders are skipped");
  {
    GWNavigationHistory *h = [[GWNavigationHistory new] autorelease];
    TestItem *a = [TestItem itemNamed:@"/a"];
    TestItem *b = [TestItem itemNamed:@"/b"];
    TestItem *c = [TestItem itemNamed:@"/c"];
    NSInteger p;

    [h addItem:a maxCount:50];
    [h addItem:b maxCount:50];
    [h addItem:c maxCount:50];
    b->valid = NO;

    p = [h positionAfterStep:-1];
    PASS([[h items] count] == 2, "the deleted folder leaves the history");
    PASS(p == 0, "Back skips the deleted folder");
    PASS_EQUAL([[h items] objectAtIndex:p], a, "Back shows the folder before it");
  }
  END_SET("vanished folders are skipped");

  START_SET("repeated pairs collapse");
  {
    GWNavigationHistory *h = [[GWNavigationHistory new] autorelease];
    NSArray *seq = @[ @"/a", @"/b", @"/a", @"/b", @"/c" ];
    NSArray *want = @[ @"/a", @"/b", @"/c" ];
    NSUInteger i;

    /* Going back and forth between two folders must not make Back step
     * through the same pair over and over. */
    for (i = 0; i < [seq count]; i++)
      [h addItem:[seq objectAtIndex:i] maxCount:50];
    PASS_EQUAL([h items], want, "the repeated pair is kept once");
    PASS([h position] == 2, "the last folder is current");
  }
  END_SET("repeated pairs collapse");

  START_SET("the stored limit");
  {
    /* A stored 0 left every window with one folder, so Back and Forward
     * never had anything to step to. */
    PASS(GWNavigationHistoryLimitFromDefault(nil) == GWNavigationHistoryDefaultLimit,
         "no stored value gives the default");
    PASS(GWNavigationHistoryLimitFromDefault([NSNumber numberWithInt:0])
             == GWNavigationHistoryDefaultLimit,
         "a stored 0 counts as not chosen");
    PASS(GWNavigationHistoryLimitFromDefault(@"2") == GWNavigationHistoryDefaultLimit,
         "a value below the preferences' minimum counts as not chosen");
    PASS(GWNavigationHistoryLimitFromDefault([NSNumber numberWithInt:50]) == 50,
         "a chosen value is kept");
    PASS(GWNavigationHistoryLimitFromDefault(@"4") == 4, "the minimum itself is kept");
  }
  END_SET("the stored limit");

  START_SET("clearing");
  {
    GWNavigationHistory *h = historyWith(@[ @"/a", @"/b" ]);
    [h removeAllItems];
    PASS([[h items] count] == 0 && [h position] == 0, "a re-based window starts over");
    PASS([kLongLiteral length] > 0, "constant string section present");
  }
  END_SET("clearing");

  [arp release];
  return 0;
}
