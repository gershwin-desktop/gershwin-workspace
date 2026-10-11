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
#include "../../Workspace/Finder/Modules/FModuleLabel/FModuleLabel.m"

static BOOL
check(NSInteger how, NSInteger color, NSString *path)
{
  NSDictionary *c = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInteger: how], @"how",
    [NSNumber numberWithInteger: color], @"what", nil];
  id m = [[FModuleLabel alloc] initWithSearchCriteria: c searchTool: nil];
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
                   [NSString stringWithFormat: @"t_FModuleLabel-%d", (int)getpid()]];
  NSString *red = [dir stringByAppendingPathComponent: @"red.txt"];
  NSString *plain = [dir stringByAppendingPathComponent: @"plain.txt"];
  GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createFileAtPath: red contents: [NSData data] attributes: nil];
  [fm createFileAtPath: plain contents: [NSData data] attributes: nil];
  [md setLabelNumber: GSFileLabelRed];
  PASS([md writeToFileAtPath: red error: NULL], "red label written");

  /* Finder colour 6 is red, whatever the menu order says */
  PASS(check(0, 6, red), "is red: red file matches");
  PASS(!check(0, 6, plain), "is red: plain file does not");
  PASS(!check(1, 6, red), "is not red: red file does not match");
  PASS(check(1, 6, plain), "is not red: plain file matches");
  PASS(check(0, 0, plain), "no label: plain file matches");
  PASS(!check(0, 1, red), "grey (1) is not red");

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

  /* the controls and their answer */
  {
    id m = [[FModuleLabel alloc] initInterface];
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
      [NSNumber numberWithInt: 1], @"how", [NSNumber numberWithInt: 6], @"what",
      nil]];
    c = [m searchCriteria];
    PASS([[c objectForKey: @"how"] intValue] == 1
         && [[c objectForKey: @"what"] intValue] == 6,
         "the state set is the criteria given back (Finder colour number)");
    [m release];
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
