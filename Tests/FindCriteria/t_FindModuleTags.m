/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#include <unistd.h>
#import "GSFileMetadata.h"
#include "../../Workspace/Finder/Modules/FModuleTags/FModuleTags.m"

static BOOL
check(NSInteger how, NSString *text, NSString *path)
{
  NSDictionary *c = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInteger: how], @"how", text, @"what", nil];
  id m = [[FModuleTags alloc] initWithSearchCriteria: c searchTool: nil];
  BOOL r = [m checkPath: path withAttributes:
            [[NSFileManager defaultManager] fileAttributesAtPath: path
                                                    traverseLink: NO]];

  [m release];
  return r;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat: @"t_FModuleTags-%d", (int)getpid()]];
  NSString *tagged = [dir stringByAppendingPathComponent: @"tagged.txt"];
  NSString *plain = [dir stringByAppendingPathComponent: @"plain.txt"];
  GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createFileAtPath: tagged contents: [NSData data] attributes: nil];
  [fm createFileAtPath: plain contents: [NSData data] attributes: nil];
  [md setUserTags: [NSArray arrayWithObjects: @"Taxes 2025", @"Red\n6", nil]];
  PASS([md writeToFileAtPath: tagged error: NULL], "tags written");

  PASS(check(0, @"Taxes 2025", tagged), "is: whole tag matches");
  PASS(!check(0, @"Taxes", tagged), "is: part of a tag does not");
  PASS(check(1, @"axes", tagged), "contains: part of a tag matches");
  PASS(check(0, @"Red", tagged), "the colour suffix is not part of the name");
  PASS(!check(0, @"Taxes 2025", plain), "untagged file does not match");
  PASS(!check(1, @"", tagged), "an empty text matches nothing");

  /* The controls are AppKit views: they need the shared NSApplication, and
   * so a display; without one the model checks above still ran. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping the control checks\n");
      [fm removeFileAtPath: dir handler: nil];
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  {
    id m = [[FModuleTags alloc] initInterface];
    NSDictionary *c;

    PASS([m controls] != nil, "controls exist");
    /* Every row of the Find window lines up: the controls are 20 high and
     * flush with the bottom of the row, as in the modules from the nib. */
    {
      NSView *row = [m controls];
      NSEnumerator *en;
      NSView *v;

      [row setFrameSize: NSMakeSize(260, 34)];
      en = [[row subviews] objectEnumerator];
      while ((v = [en nextObject]) != nil)
        {
          PASS(NSMinY([v frame]) == 0 && NSHeight([v frame]) == 20,
               "control %s is 20 high at the bottom of the row",
               [NSStringFromClass([v class]) UTF8String]);
        }
    }
    [m setControlsState: [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 1], @"how", @"abc", @"what", nil]];
    c = [m searchCriteria];
    PASS([[c objectForKey: @"how"] intValue] == 1
         && [[c objectForKey: @"what"] isEqual: @"abc"],
         "the state set is the criteria given back");
    [m release];
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
