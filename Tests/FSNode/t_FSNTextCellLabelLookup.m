/* t_FSNTextCellLabelLookup.m - coverage for FSNTextCell's label-colour cache.
 *
 * -drawInteriorWithFrame:inView: asked the metadata provider for the Finder
 * label on every draw of a cell whose tagColor was nil, because "no label"
 * and "not looked up yet" were the same value.  Most files carry no label,
 * so every redraw of every list row repeated the lookup.  The provider must
 * be asked at most once per nodePath.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"
#include "../../FSNode/FSNTextCell.m"

/* Counts calls instead of just answering, so the test can tell "asked once"
 * from "asked on every draw". */
@interface CountingLabelProvider : NSObject <FSNMetadataProvider>
{
@public
  NSUInteger lookupCount;
}
@end

@implementation CountingLabelProvider

- (NSColor *)labelColorForPath:(NSString *)path
{
  lookupCount++;
  /* The common case this bug hits: an unlabeled file. */
  return nil;
}

- (BOOL)isInvisibleAtPath:(NSString *)path
{
  return NO;
}

- (NSImage *)customIconForPath:(NSString *)path
{
  return nil;
}

- (NSPoint)iconPositionForPath:(NSString *)path
{
  return NSMakePoint(-1, -1);
}

- (void)invalidateCaches
{
}

@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  CountingLabelProvider *provider;
  FSNTextCell *cell;
  NSImage *icon;
  NSImage *canvas;
  NSView *view;
  NSRect frame = NSMakeRect(0, 0, 200, 20);

  /* NSTextFieldCell drawing needs a graphics context, and gnustep-back only
   * ever gets one through a real display connection, even for an off-screen
   * bitmap - so this test is skipped without one rather than hanging. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  provider = [[CountingLabelProvider alloc] init];
  [[FSNodeRep sharedInstance] setMetadataProvider: provider];

  cell = [[FSNTextCell alloc] init];
  [cell setStringValue: @"unlabeled-file.txt"];
  icon = [[NSImage alloc] initWithSize: NSMakeSize(16, 16)];
  [cell setIcon: icon];
  [cell setNodePath: @"/tmp/fsnode-label-lookup-test-file"];

  view = [[NSView alloc] initWithFrame: frame];
  canvas = [[NSImage alloc] initWithSize: frame.size];

  [canvas lockFocus];
  [cell drawInteriorWithFrame: frame inView: view];
  [cell drawInteriorWithFrame: frame inView: view];
  [cell drawInteriorWithFrame: frame inView: view];
  [canvas unlockFocus];

  PASS(provider->lookupCount == 1,
       "an unlabeled file's metadata is looked up once, not on every redraw");

  [canvas release];
  [view release];
  [icon release];
  [cell release];
  [[FSNodeRep sharedInstance] setMetadataProvider: nil];
  [provider release];

  [arp release];
  return 0;
}
