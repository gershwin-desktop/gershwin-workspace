/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The provider answers the label number as a scalar.  Asking for it through
 * performSelector: once made the icon treat that number as an object, which
 * crashed Workspace at launch; this checks the number arrives intact. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNIcon.h"
#import "FSNMetadataProvider.h"

@interface LabelProvider : NSObject <FSNMetadataProvider>
@end

@implementation LabelProvider
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSMakePoint(-1, -1); }
- (void)invalidateCaches { }
- (NSInteger)labelIndexForPath:(NSString *)path
{
  return 3;
}
@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  LabelProvider *provider = [LabelProvider new];
  FSNodeRep *rep = [FSNodeRep sharedInstance];
  NSString *path;
  FSNIcon *icon;

  if (getenv ("DISPLAY") == NULL)
    {
      printf ("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  path = [NSTemporaryDirectory () stringByAppendingPathComponent:
           [NSString stringWithFormat: @"t_FSNIconLabelIndex_%d", (int)getpid ()]];
  [@"x" writeToFile: path atomically: YES];
  [rep setMetadataProvider: provider];

  icon = [[FSNIcon alloc] initForNode: [FSNode nodeWithPath: path]
                         nodeInfoType: FSNInfoNameType
                         extendedType: nil
                             iconSize: 48
                         iconPosition: NSImageAbove
                            labelFont: [NSFont systemFontOfSize: 12]
                            textColor: [NSColor controlTextColor]
                            gridIndex: 0
                            dndSource: NO
                            acceptDnd: NO
                            slideBack: NO];

  PASS ([icon labelIndex] == 3,
        "MI-FSN-70 the icon takes the provider's scalar label number as is");

  [rep setMetadataProvider: nil];
  [icon release];
  [provider release];
  [fm removeFileAtPath: path handler: nil];
  [arp release];
  return 0;
}
