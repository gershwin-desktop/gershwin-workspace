/* t_FSNBrowserMatrixDrawRectRowScan.m - coverage for FSNBrowserMatrix's
 * bounded zebra-stripe redraw.
 *
 * -drawRect: painted its zebra stripes by walking every other row of the
 * WHOLE matrix and testing each against the dirty rect, even though a big
 * directory decorates one row at a time as its icons load - each such
 * decoration invalidates only that row, so the walk over every row of the
 * matrix repeated on every single-row redraw, turning a directory of N
 * entries into an O(N) scan per redraw and O(N^2) overall while it loads.
 * The walk must be bounded by what the clip view can actually show
 * (-visibleRowRange), not by the matrix's total row count.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNBrowserMatrix.h"
#import "FSNBrowserCell.h"

#define TOTAL_ROWS 10000
#define ROW_HEIGHT 20.0

/* Counts how many times the matrix computes a row's frame, so a redraw's
 * cost can be measured without touching private state. */
@interface CountingBrowserMatrix : FSNBrowserMatrix
{
@public
  NSUInteger frameCalls;
}
@end

@implementation CountingBrowserMatrix

- (NSRect)cellFrameAtRow:(NSInteger)row column:(NSInteger)column
{
  frameCalls++;
  return [super cellFrameAtRow: row column: column];
}

@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  FSNBrowserCell *prototype;
  CountingBrowserMatrix *matrix;
  NSScrollView *scroll;
  NSImage *canvas;
  NSRange oneRowRange;
  NSRange fullViewRange;
  NSRect middleRowRect;
  NSUInteger callsForOneRowRedraw;

  /* NSMatrix/NSScrollView geometry and NSRectFill both want a graphics
   * context, which gnustep-back only hands out through a real display
   * connection - so this is skipped, not hung, without one. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  prototype = [[FSNBrowserCell alloc] init];

  scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, ROW_HEIGHT)];
  [scroll setHasVerticalScroller: YES];

  matrix = [[CountingBrowserMatrix alloc] initInColumn: nil
                                              withFrame: [scroll bounds]
                                                   mode: NSListModeMatrix
                                              prototype: prototype
                                           numberOfRows: TOTAL_ROWS
                                        numberOfColumns: 1
                                              acceptDnd: NO];
  [matrix setIntercellSpacing: NSMakeSize(0, 0)];
  [matrix setCellSize: NSMakeSize(300, ROW_HEIGHT)];
  [scroll setDocumentView: matrix];
  [matrix release];
  [scroll tile];

  /* A viewport exactly one row tall: -visibleRowRange must stay small for
   * a matrix of 10000 rows, not report the whole matrix. */
  oneRowRange = [matrix visibleRowRange];
  PASS(oneRowRange.length > 0 && oneRowRange.length <= 4,
       "a one-row viewport reports a handful of visible rows out of %d, not all of them (got %lu)",
       TOTAL_ROWS, (unsigned long)oneRowRange.length);

  /* Resize to a realistic list viewport and confirm the range still tracks
   * the viewport, not the row count. */
  [scroll setFrame: NSMakeRect(0, 0, 300, 300)];
  [scroll tile];
  fullViewRange = [matrix visibleRowRange];
  PASS(fullViewRange.length > 0 && fullViewRange.length < 40,
       "a 300pt viewport (15 rows) still reports well under %d rows (got %lu)",
       TOTAL_ROWS, (unsigned long)fullViewRange.length);

  /* One decorated row's redraw (what -decorateCell: triggers) must not walk
   * every row of a 10000-row matrix to paint its zebra stripe. */
  middleRowRect = NSMakeRect(0, 40, 300, ROW_HEIGHT);

  canvas = [[NSImage alloc] initWithSize: NSMakeSize(300, 300)];
  [canvas lockFocus];
  matrix->frameCalls = 0;
  [matrix drawRect: middleRowRect];
  callsForOneRowRedraw = matrix->frameCalls;
  [canvas unlockFocus];

  PASS(callsForOneRowRedraw < 100,
       "one row's redraw computes well under %d row frames, not one per row (got %lu)",
       TOTAL_ROWS, (unsigned long)callsForOneRowRedraw);

  [canvas release];
  [scroll release];
  [prototype release];

  [arp release];
  return 0;
}
