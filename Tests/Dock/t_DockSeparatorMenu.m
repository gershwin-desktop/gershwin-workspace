/* t_DockSeparatorMenu.m - headless coverage for the menu of the line
 * between the Dock's applications and its folders: which items it shows
 * for a given state of the Dock settings, their titles and checkmarks, and
 * which settings choosing an item leads to (DockSeparatorMenu.h).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockSeparatorMenu.h"

static DockSeparatorSettings
settings(BOOL magnification, DockPosition position)
{
  DockSeparatorSettings s;

  s.magnification = magnification;
  s.position = position;
  return s;
}

/* The tag of the Position submenu entry with the given title. */
static NSInteger
positionTag(NSArray *entries, NSString *title)
{
  NSEnumerator *e = [[[entries objectAtIndex: 1] submenu] objectEnumerator];
  DockSeparatorMenuEntry *entry;

  while ((entry = [e nextObject]) != nil)
    {
      if ([[entry title] isEqual: title])
        return [entry tag];
    }
  return -1;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("items for magnification on, Dock at the bottom")
    NSArray *entries = DockSeparatorMenuEntries(settings(YES, DockPositionBottom));
    NSArray *sub;
    NSArray *subTitles;
    NSArray *wantTitles = [NSArray arrayWithObjects:
                                     @"Left", @"Bottom", @"Right", nil];

    NEED(PASS([entries count] == 4,
              "magnification, position, a separator and the preferences"));
    PASS_EQUAL([[entries objectAtIndex: 0] title], @"Turn Magnification Off",
               "magnification on offers to turn it off");
    PASS([[entries objectAtIndex: 0] submenu] == nil,
         "the magnification item is a plain item");
    PASS_EQUAL([[entries objectAtIndex: 1] title], @"Position on Screen",
               "the second item is the position");
    PASS([[entries objectAtIndex: 2] isSeparator],
         "a separator comes before the preferences item");
    PASS_EQUAL([[entries objectAtIndex: 3] title], @"Dock Preferences...",
               "the last item opens the Dock preferences");
    PASS(DockSeparatorChoiceOpensPreferences([[entries objectAtIndex: 3] tag]),
         "the preferences item is recognised as such");

    sub = [[entries objectAtIndex: 1] submenu];
    subTitles = [sub valueForKey: @"title"];
    PASS_EQUAL(subTitles, wantTitles,
               "the positions are Left, Bottom and Right, in that order");
    PASS([[sub objectAtIndex: 1] isChecked]
         && ![[sub objectAtIndex: 0] isChecked]
         && ![[sub objectAtIndex: 2] isChecked],
         "only Bottom carries the checkmark");
  END_SET("items for magnification on, Dock at the bottom")

  START_SET("items for magnification off, Dock on the left")
    NSArray *entries = DockSeparatorMenuEntries(settings(NO, DockPositionLeft));
    NSArray *sub = [[entries objectAtIndex: 1] submenu];

    PASS_EQUAL([[entries objectAtIndex: 0] title], @"Turn Magnification On",
               "magnification off offers to turn it on");
    PASS([[sub objectAtIndex: 0] isChecked]
         && ![[sub objectAtIndex: 1] isChecked]
         && ![[sub objectAtIndex: 2] isChecked],
         "only Left carries the checkmark");
  END_SET("items for magnification off, Dock on the left")

  START_SET("only items for features the Dock has")
    NSArray *entries = DockSeparatorMenuEntries(settings(YES, DockPositionRight));
    NSString *all = [[entries valueForKey: @"title"]
                       componentsJoinedByString: @"|"];

    PASS([all rangeOfString: @"Hiding"].location == NSNotFound,
         "no hiding item: the Dock cannot hide itself automatically");
    PASS([all rangeOfString: @"Minimize"].location == NSNotFound,
         "no minimize effect item: there is only one effect");
    PASS([[[[entries objectAtIndex: 1] submenu] objectAtIndex: 2] isChecked],
         "Right is checked for a Dock on the right");
  END_SET("only items for features the Dock has")

  START_SET("choosing an item")
    DockSeparatorSettings before = settings(YES, DockPositionBottom);
    NSArray *entries = DockSeparatorMenuEntries(before);
    DockSeparatorSettings after;

    after = DockSeparatorSettingsAfterChoice(before,
                                             [[entries objectAtIndex: 0] tag]);
    PASS(after.magnification == NO && after.position == DockPositionBottom,
         "Turn Magnification Off turns it off and leaves the position");

    after = DockSeparatorSettingsAfterChoice(settings(NO, DockPositionLeft),
      [[DockSeparatorMenuEntries(settings(NO, DockPositionLeft))
          objectAtIndex: 0] tag]);
    PASS(after.magnification == YES && after.position == DockPositionLeft,
         "Turn Magnification On turns it on and leaves the position");

    after = DockSeparatorSettingsAfterChoice(before,
                                             positionTag(entries, @"Left"));
    PASS(after.position == DockPositionLeft && after.magnification == YES,
         "Left moves the Dock to the left and leaves magnification");

    after = DockSeparatorSettingsAfterChoice(before,
                                             positionTag(entries, @"Right"));
    PASS(after.position == DockPositionRight,
         "Right moves the Dock to the right");

    after = DockSeparatorSettingsAfterChoice(settings(YES, DockPositionLeft),
                                             positionTag(entries, @"Bottom"));
    PASS(after.position == DockPositionBottom,
         "Bottom moves the Dock to the bottom");

    after = DockSeparatorSettingsAfterChoice(before,
                                             [[entries objectAtIndex: 3] tag]);
    PASS(after.magnification == before.magnification
         && after.position == before.position,
         "the preferences item changes no setting");
    PASS(!DockSeparatorChoiceOpensPreferences([[entries objectAtIndex: 0] tag])
         && !DockSeparatorChoiceOpensPreferences(positionTag(entries, @"Left")),
         "only the preferences item opens the preferences");

    after = DockSeparatorSettingsAfterChoice(before, 0);
    PASS(after.magnification == before.magnification
         && after.position == before.position,
         "an unknown tag changes nothing");
  END_SET("choosing an item")

  [arp release];
  return 0;
}
