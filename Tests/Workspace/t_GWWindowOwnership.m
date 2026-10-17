/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWWindowOwnership.m - headless coverage for the one decision which
 * application a window belongs to (pid first, WM_CLASS next, never a title
 * alone, and a class naming another bundle never counts for this one). */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWWindowOwnership.m"

/* A made-up process tree: 100 started 101, which started 102. 900 is a
 * browser nobody here started. */
static BOOL
fakeAncestry(pid_t pid, pid_t ancestor)
{
  pid_t p = pid;

  while (p > 0)
    {
      pid_t parent = 0;

      if (p == 101)
        parent = 100;
      else if (p == 102)
        parent = 101;
      if (parent == ancestor)
        return YES;
      p = parent;
    }
  return NO;
}

static GWWindowOwnership *
app(NSString *name, NSString *path, pid_t pid, NSArray *hints, NSDictionary *map)
{
  return [[[GWWindowOwnership alloc] initWithName: name
                                             path: path
                                      launchedPID: pid
                                       classHints: hints
                                         classMap: map
                                         ancestry: fakeAncestry] autorelease];
}

static NSString * const claudePath = @"/home/u/Applications/Claude Desktop.app";

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSDictionary *apps = [NSDictionary dictionaryWithObjectsAndKeys:
    claudePath, @"Claude Desktop",
    @"/home/u/Applications/Brave Origin.app", @"Brave Origin",
    @"/Apps/VLC media player.app", @"VLC media player",
    @"/System/Applications/TextEdit.app", @"TextEdit",
    @"/Apps/XTerm.app", @"XTerm", nil];
  NSDictionary *hints = [NSDictionary dictionaryWithObject:
                           [NSArray arrayWithObject: @"vlc"]
                                                    forKey: @"/Apps/VLC media player.app"];
  NSDictionary *map = GWWindowOwnershipClassMap(apps, hints);
  GWWindowOwnership *o;
  GWWindowOwnershipReason r;

  /* The live case: Brave Origin shows a page about Claude Desktop while
   * Claude Desktop sits in the Dock, not running. */
  o = app(@"Claude Desktop", claudePath, 0, nil, map);
  r = [o reasonForWindowPID: 900
                   instance: @"brave-origin"
                windowClass: @"Brave-origin"
                      title: @"Claude Desktop on Linux - Brave Origin"];
  PASS(GWWindowOwnershipReasonIsOwned(r) == NO,
       "a browser window titled after a docked app is not that app's");
  PASS(r == GWWindowNotOwnedClassOfOtherBundle,
       "its class names Brave Origin, which claims it");

  /* The same window, with Claude Desktop running under a known pid. */
  o = app(@"Claude Desktop", claudePath, 100, nil, map);
  r = [o reasonForWindowPID: 900
                   instance: @"brave-origin"
                windowClass: @"Brave-origin"
                      title: @"Claude Desktop on Linux - Brave Origin"];
  PASS(r == GWWindowNotOwnedOtherProcess,
       "with the app's pid known, another process's window never counts");

  /* Pid and descendants. */
  r = [o reasonForWindowPID: 100 instance: @"claude" windowClass: @"Claude" title: @"x"];
  PASS(r == GWWindowOwnedLaunchedProcess, "the launched process's window belongs");
  r = [o reasonForWindowPID: 102 instance: @"electron" windowClass: @"Electron" title: @""];
  PASS(r == GWWindowOwnedDescendantProcess,
       "a window of a process the launched one started belongs (two levels down)");
  r = [o reasonForWindowPID: 100 instance: @"brave-origin" windowClass: @"Brave-origin"
                      title: @"y"];
  PASS(r == GWWindowOwnedLaunchedProcess,
       "the launched process itself belongs whatever class it shows");
  r = [o reasonForWindowPID: 101 instance: @"brave-origin" windowClass: @"Brave-origin"
                      title: @"z"];
  PASS(r == GWWindowNotOwnedClassOfOtherBundle,
       "a started process whose class names another bundle is that bundle's");
  r = [o reasonForWindowPID: 0 instance: @"claude" windowClass: @"Claude"
                      title: @"Claude Desktop"];
  PASS(r == GWWindowNotOwnedOtherProcess,
       "with the pid known, a window without a pid does not belong by its class");

  /* WM_CLASS without a known pid. */
  o = app(@"Brave Origin", @"/home/u/Applications/Brave Origin.app", 0, nil, map);
  r = [o reasonForWindowPID: 900 instance: @"brave-origin" windowClass: @"Brave-origin"
                      title: @"Home"];
  PASS(r == GWWindowOwnedClass,
       "a class equal to the bundle name, case and hyphens aside, belongs");
  o = app(@"XTerm", @"/Apps/XTerm.app", 0, nil, map);
  r = [o reasonForWindowPID: 300 instance: @"xterm" windowClass: @"XTerm" title: @"TextEdit"];
  PASS(r == GWWindowOwnedClass, "XTerm's own window belongs to it by class");

  /* The Info.plist class hint of a wrapper bundle. */
  o = app(@"VLC media player", @"/Apps/VLC media player.app", 0,
          [NSArray arrayWithObject: @"vlc"], map);
  r = [o reasonForWindowPID: 400 instance: @"vlc" windowClass: @"vlc"
                      title: @"movie.mkv"];
  PASS(r == GWWindowOwnedClass, "the GSX11WindowClass hint names the class");
  o = app(@"VLC media player", @"/Apps/VLC media player.app", 0, nil, map);
  r = [o reasonForWindowPID: 400 instance: @"vlc" windowClass: @"vlc"
                      title: @"movie.mkv"];
  PASS(r == GWWindowOwnedClass,
       "the hint is also known from the class map when not passed directly");

  /* Title only, no pid. */
  o = app(@"TextEdit", @"/System/Applications/TextEdit.app", 0, nil, map);
  r = [o reasonForWindowPID: 500 instance: @"mystery" windowClass: @"Mystery"
                      title: @"TextEdit on Linux"];
  PASS(r == GWWindowNotOwnedTitleOnly, "a title alone, without a pid, never belongs");
  r = [o reasonForWindowPID: 300 instance: @"xterm" windowClass: @"XTerm"
                      title: @"TextEdit on Linux"];
  PASS(GWWindowOwnershipReasonIsOwned(r) == NO,
       "an xterm titled after TextEdit is not TextEdit's");
  r = [o reasonForWindowPID: 600 instance: @"TextEdit" windowClass: @"GNUstep"
                      title: @"Untitled"];
  PASS(r == GWWindowOwnedClass,
       "a GNUstep window is known by its instance, the application's name");

  /* A class claimed by another bundle. */
  o = app(@"VLC media player", @"/Apps/VLC media player.app", 0, nil, map);
  r = [o reasonForWindowPID: 700 instance: @"xterm" windowClass: @"XTerm"
                      title: @"VLC media player"];
  PASS(r == GWWindowNotOwnedClassOfOtherBundle,
       "a class claimed by another bundle never counts for this one");

  /* The class map. */
  PASS_EQUAL([map objectForKey: @"braveorigin"], @"/home/u/Applications/Brave Origin.app",
             "bundle names are folded into the class map");
  PASS_EQUAL([map objectForKey: @"vlc"], @"/Apps/VLC media player.app",
             "hints are part of the class map");

  /* Info.plist hints: a string or an array of strings. */
  {
    NSDictionary *one = [NSDictionary dictionaryWithObject: @"vlc"
                                                    forKey: @"GSX11WindowClass"];
    NSDictionary *many = [NSDictionary dictionaryWithObject:
      [NSArray arrayWithObjects: @"soffice", @"libreoffice-writer", nil]
                                                     forKey: @"GSX11WindowClass"];
    NSArray *want = [NSArray arrayWithObjects: @"soffice", @"libreoffice-writer", nil];

    PASS_EQUAL(GWWindowOwnershipClassHintsInInfo(one), [NSArray arrayWithObject: @"vlc"],
               "a string hint is one class");
    PASS_EQUAL(GWWindowOwnershipClassHintsInInfo(many), want,
               "an array hint lists several classes");
    PASS([GWWindowOwnershipClassHintsInInfo([NSDictionary dictionary]) count] == 0,
         "no key, no hints");
  }

  /* The application list make_services writes maps "Name.app" to a path;
   * its other entries (extension maps) are no applications. */
  {
    NSDictionary *appList = [NSDictionary dictionaryWithObjectsAndKeys:
      @"/Apps/XTerm.app", @"XTerm.app",
      @"/Apps/Tool.debug", @"Tool.debug",
      [NSDictionary dictionary], @"GSExtensionsMap", nil];
    NSDictionary *named = GWWindowOwnershipApplicationsInAppList(appList);

    PASS([named count] == 1
         && [[named objectForKey: @"XTerm"] isEqual: @"/Apps/XTerm.app"],
         "the bundles are read by name from the application list");
  }

  [arp release];
  return 0;
}
