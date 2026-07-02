/* t_FSNGridCellCenter.m — headless coverage for the spatial grid geometry.
 *
 * FSNGridCellCenter is the single source for AUTO icon placement in the
 * spatial view (GWSpatialIconsView).  It's a Foundation-only inline in
 * FSNIconPlacement.h, so it runs headless with no gnustep-gui/libarchive.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNIconPlacement.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  NSPoint origin = NSMakePoint(26, 12);   /* top-left grid origin */
  CGFloat cellW = 96, cellH = 80, gapX = 32;

  NSPoint c00 = FSNGridCellCenter(FSNGridCellMake(0, 0), origin, cellW, cellH, gapX);
  PASS(c00.x == 74.0 && c00.y == 52.0,
       "cell (0,0) center = origin + half-cell");

  NSPoint c21 = FSNGridCellCenter(FSNGridCellMake(2, 1), origin, cellW, cellH, gapX);
  PASS(c21.x == 330.0 && c21.y == 132.0,
       "cell (2,1) center");

  NSPoint c10 = FSNGridCellCenter(FSNGridCellMake(1, 0), origin, cellW, cellH, gapX);
  PASS((c10.x - c00.x) == (cellW + gapX),
       "adjacent columns are spaced by cellW + gapX");

  NSPoint c01 = FSNGridCellCenter(FSNGridCellMake(0, 1), origin, cellW, cellH, gapX);
  PASS((c01.y - c00.y) == cellH,
       "adjacent rows are spaced by cellH");

  /* Flipped spatial view uses the center directly as the iloc (top-left)
   * coordinate; the icon frame is center - half-cell.  Assert that
   * round-trip (frame origin -> center) is the identity. */
  NSRect frame = NSMakeRect(c21.x - cellW / 2.0, c21.y - cellH / 2.0, cellW, cellH);
  NSPoint back = NSMakePoint(NSMidX(frame), NSMidY(frame));
  PASS(back.x == c21.x && back.y == c21.y,
       "center <-> frame round-trips (flipped identity)");

  [arp release];
  return 0;
}
