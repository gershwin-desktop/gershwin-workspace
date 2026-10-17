/* t_DockAdoption.m - headless coverage for which already running
 * applications the Dock adopts when Workspace starts: from the windows of
 * this session and the known application bundles to the icons to add.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockAdoption.h"
#import "GWWindowOwnership.h"

static NSDictionary *
win(int pid, NSString *instance, NSString *cls, NSString *title,
    BOOL hidden, BOOL skips)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: pid], DockAdoptionPIDKey,
    instance, DockAdoptionInstanceKey,
    cls, DockAdoptionClassKey,
    title, DockAdoptionTitleKey,
    [NSNumber numberWithBool: hidden], DockAdoptionHiddenKey,
    [NSNumber numberWithBool: skips], DockAdoptionSkipsTaskbarKey, nil];
}

static NSString *
pathsOf(NSArray *plan)
{
  return [[plan valueForKey: DockAdoptionPathKey] componentsJoinedByString: @","];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSDictionary *apps = [NSDictionary dictionaryWithObjectsAndKeys:
    @"/home/u/Applications/Brave Origin.app", @"Brave Origin",
    @"/Apps/XTerm.app", @"XTerm",
    @"/Apps/VLC media player.app", @"VLC media player",
    @"/System/Applications/Terminal.app", @"Terminal",
    @"/Apps/Go.app", @"Go",
    @"/Apps/Claude.app", @"Claude", nil];
  /* The VLC wrapper declares its program's class in its Info.plist. */
  NSDictionary *hints = [NSDictionary dictionaryWithObject:
                           [NSArray arrayWithObject: @"vlc"]
                                                    forKey: @"/Apps/VLC media player.app"];
  NSDictionary *map = GWWindowOwnershipClassMap(apps, hints);
  NSDictionary *mapWithoutHints = GWWindowOwnershipClassMap(apps, nil);
  NSSet *none = [NSSet set];
  NSArray *plan;

  /* The live case: Brave Origin, started from its wrapper bundle before
   * Workspace restarted, all of its windows minimized. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(6036, @"brave-origin", @"Brave-origin", @"Home / X - Brave Origin", YES, NO),
      win(6036, @"brave-origin", @"Brave-origin", @"Notifications - Brave Origin", YES, NO),
      nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 1, "a running X11 application gets one icon");
    PASS_EQUAL([[plan lastObject] objectForKey: DockAdoptionPathKey],
               @"/home/u/Applications/Brave Origin.app",
               "WM_CLASS brave-origin maps to the bundle Brave Origin");
    PASS_EQUAL([[plan lastObject] objectForKey: DockAdoptionNameKey],
               @"Brave Origin", "the icon carries the bundle's name");
    PASS([[[plan lastObject] objectForKey: DockAdoptionPIDKey] intValue] == 6036,
         "the icon tracks the process that owns the windows");
    PASS([[[plan lastObject] objectForKey: DockAdoptionHiddenKey] boolValue],
         "an application whose every window is minimized shows as hidden");
  }

  /* One window still on screen: the application is not hidden. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(6036, @"brave-origin", @"Brave-origin", @"a - Brave Origin", YES, NO),
      win(6036, @"brave-origin", @"Brave-origin", @"b - Brave Origin", NO, NO),
      nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 1
         && [[[plan lastObject] objectForKey: DockAdoptionHiddenKey] boolValue] == NO,
         "an application with a window on screen is not hidden");
  }

  /* Several applications keep the order of the client list, so the icons
   * come out the same way every time Workspace starts. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(300, @"xterm", @"XTerm", @"admin@host: ~", NO, NO),
      win(6036, @"brave-origin", @"Brave-origin", @"x - Brave Origin", NO, NO),
      win(300, @"xterm", @"XTerm", @"second", NO, NO),
      nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS_EQUAL(pathsOf(plan),
               @"/Apps/XTerm.app,/home/u/Applications/Brave Origin.app",
               "icons follow the client list, one per application");
  }

  /* A wrapper whose program's class differs from the bundle's name is
   * found through the class it declares, never through the title. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(400, @"vlc", @"vlc", @"movie.mkv - VLC media player", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS_EQUAL(pathsOf(plan), @"/Apps/VLC media player.app",
               "the GSX11WindowClass hint maps the class to its bundle");
    plan = DockAdoptionPlan(clients, apps, mapWithoutHints, none);
    PASS([plan count] == 0,
         "a title naming a bundle does not adopt the window for it");
  }

  /* The live case on the user's desktop: a browser page about a docked
   * application is the browser's, not that application's. */
  {
    NSDictionary *more = [NSDictionary dictionaryWithObjectsAndKeys:
      @"/home/u/Applications/Brave Origin.app", @"Brave Origin",
      @"/home/u/Applications/Claude Desktop.app", @"Claude Desktop", nil];
    NSArray *clients = [NSArray arrayWithObjects:
      win(6036, @"brave-origin", @"Brave-origin",
          @"Claude Desktop on Linux - Brave Origin", NO, NO), nil];

    plan = DockAdoptionPlan(clients, more, GWWindowOwnershipClassMap(more, nil), none);
    PASS_EQUAL(pathsOf(plan), @"/home/u/Applications/Brave Origin.app",
               "Brave Origin is adopted, and Claude Desktop is not");
  }

  /* A name only counts as a whole word: "Go" is not "Google". */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(500, @"google-earth", @"Google-earth", @"Google Earth", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 0, "a bundle name inside a longer word does not match");
  }

  /* Two bundles fit the same window equally: no guessing. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(600, @"mplayer", @"MPlayer", @"Terminal - VLC media player", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 0, "an ambiguous window is left out");
  }

  /* The class decides before the title: an xterm whose title names another
   * bundle is still XTerm. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(700, @"xterm", @"XTerm", @"Terminal", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS_EQUAL(pathsOf(plan), @"/Apps/XTerm.app",
               "WM_CLASS wins over a title naming another bundle");
  }

  /* Nothing maps: nothing is added. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(800, @"xclock", @"XClock", @"xclock", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 0, "a window that maps to no bundle is skipped");
  }

  /* GNUstep applications come from the launched-applications registry; their
   * windows must not be adopted a second time by name. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(900, @"Terminal", @"GNUstep", @"Terminal", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 0, "GNUstep windows are left to the registry");
  }

  /* A window that skips the taskbar (a tooltip, a floating helper) does not
   * name an application, nor does it decide whether the app is hidden. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(1000, @"xterm", @"XTerm", @"tip", NO, YES), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 0, "only taskbar windows adopt an application");

    clients = [NSArray arrayWithObjects:
      win(1000, @"xterm", @"XTerm", @"tip", NO, YES),
      win(1000, @"xterm", @"XTerm", @"main", YES, NO), nil];
    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 1
         && [[[plan lastObject] objectForKey: DockAdoptionHiddenKey] boolValue],
         "a skip-taskbar window does not keep the application from hiding");
  }

  /* An application Workspace already tracks as running is not added again;
   * a docked one that is not tracked yet still is (it gets its dot). */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(1100, @"xterm", @"XTerm", @"x", NO, NO),
      win(1200, @"claude", @"Claude", @"Claude", NO, NO), nil];
    NSSet *tracked = [NSSet setWithObject: @"/Apps/XTerm.app"];

    plan = DockAdoptionPlan(clients, apps, map, tracked);
    PASS_EQUAL(pathsOf(plan), @"/Apps/Claude.app",
               "already tracked applications are skipped");
  }

  /* Two processes of one application give one icon, for the first. */
  {
    NSArray *clients = [NSArray arrayWithObjects:
      win(1300, @"xterm", @"XTerm", @"one", NO, NO),
      win(1301, @"xterm", @"XTerm", @"two", NO, NO), nil];

    plan = DockAdoptionPlan(clients, apps, map, none);
    PASS([plan count] == 1
         && [[[plan lastObject] objectForKey: DockAdoptionPIDKey] intValue] == 1300,
         "one icon per application, tracking its first process");
  }

  [arp release];
  return 0;
}
