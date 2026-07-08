/* t_FSNIlocTransform.m — headless coverage for the canonical iloc<->view
 * transform.
 *
 * FSNViewCenterFromIloc / FSNIlocFromViewCenter are the single definition of
 * how a stored DS_Store/fdLocation iloc (top-left origin, y down) maps to an
 * icon center in a view's own space, for both flipped (spatial) and
 * non-flipped (desktop) views.  Foundation-only inlines in FSNIconPlacement.h,
 * so this runs headless.  Pinning the convention here guards against the
 * coordinate-reference split that caused the drag Y-flip and the invisible
 * desktop icons.
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

  const CGFloat refH = 800.0;

  /* --- flipped view: identity in both directions, any refHeight --- */
  {
    NSPoint iloc = NSMakePoint(120, 50);
    NSPoint c = FSNViewCenterFromIloc(iloc, refH, YES);
    PASS(NSEqualPoints(c, iloc), "flipped: view center == iloc (identity)");
    PASS(NSEqualPoints(FSNIlocFromViewCenter(c, refH, YES), iloc),
         "flipped: iloc round-trips");
    PASS(NSEqualPoints(FSNViewCenterFromIloc(iloc, 123.0, YES), iloc),
         "flipped: identity is independent of refHeight");
  }

  /* --- non-flipped view: y flips about the content height --- */
  {
    NSPoint iloc = NSMakePoint(120, 50);   /* 50 px from the top */
    NSPoint c = FSNViewCenterFromIloc(iloc, refH, NO);
    PASS(NSEqualPoints(c, NSMakePoint(120, 750)),
         "non-flipped: iloc y=50 (from top) -> view y=750 (from bottom)");
    PASS(NSEqualPoints(FSNIlocFromViewCenter(c, refH, NO), iloc),
         "non-flipped: iloc round-trips through the flip");
  }

  /* --- the transform is its own inverse (both orientations) --- */
  {
    NSPoint p = NSMakePoint(37, 611);
    PASS(NSEqualPoints(FSNIlocFromViewCenter(FSNViewCenterFromIloc(p, refH, NO), refH, NO), p),
         "non-flipped: FSNIloc(FSNView(p)) == p");
    PASS(NSEqualPoints(FSNViewCenterFromIloc(FSNIlocFromViewCenter(p, refH, NO), refH, NO), p),
         "non-flipped: FSNView(FSNIloc(p)) == p");
    PASS(NSEqualPoints(FSNIlocFromViewCenter(FSNViewCenterFromIloc(p, refH, YES), refH, YES), p),
         "flipped: round-trip is identity");
  }

  /* --- a point at the vertical midline is a fixed point (non-flipped) --- */
  {
    NSPoint mid = NSMakePoint(10, refH / 2.0);
    PASS(NSEqualPoints(FSNViewCenterFromIloc(mid, refH, NO), mid),
         "non-flipped: the content mid-height is a fixed point of the flip");
  }

  [arp release];
  return 0;
}
