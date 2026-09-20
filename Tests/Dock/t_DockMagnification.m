/* t_DockMagnification.m - headless coverage for the Dock's magnification.
 *
 * DockMagnification.h carries the geometry of the magnification described by
 * the expired patent US7434177: the tiles around the pointer grow along a
 * sine curve and the ones beyond the effect region slide away to make room.
 * It is Foundation-only inline code, so it runs headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockMagnification.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* The sizes of the patent's own example: 64 pixel tiles magnified to 128,
   * with the effect reaching three tiles to either side of the pointer. */
  CGFloat h = 64.0, H = 128.0, W = 192.0;
  DockMagnification m = DockMagnificationMake(h, H, W);
  CGFloat expectedSpread = ((H - h) / 2.0) / sin(M_PI * (h / 2.0) / (W * 2.0));
  CGFloat cursor, s, l, prevEnd;
  int i;

  PASS(CLOSE(m.spread, expectedSpread),
       "the spread S follows equation (1) of the patent");

  PASS(CLOSE(DockMagnificationDisplacement(m, 0.0), 0.0),
       "an edge under the pointer does not move");

  PASS(CLOSE(DockMagnificationDisplacement(m, W), m.spread)
       && CLOSE(DockMagnificationDisplacement(m, -W), -m.spread),
       "an edge at the border of the effect region moves by the full spread");

  PASS(CLOSE(DockMagnificationDisplacement(m, 10 * W), m.spread)
       && CLOSE(DockMagnificationDisplacement(m, -10 * W), -m.spread),
       "distances beyond the effect region are clamped to it");

  /* The tile the pointer is in the middle of reaches the magnified size. */
  cursor = 500.0;
  DockMagnificationSpan(m, cursor, cursor - h / 2.0, h, &s, &l);
  PASS(CLOSE(l, H), "the tile under the pointer is drawn at the magnified size");
  PASS(CLOSE(s + l / 2.0, cursor),
       "the tile under the pointer keeps its middle");

  /* A row of tiles stays a row: no gaps, no overlaps, order kept. */
  prevEnd = 0.0;
  for (i = 0; i < 12; i++)
    {
      CGFloat start, len;

      DockMagnificationSpan(m, 400.0, i * h, h, &start, &len);
      if (i > 0)
        PASS(CLOSE(start, prevEnd), "tiles stay next to each other");
      PASS(len >= h - 0.001, "no tile is drawn smaller than its own size");
      PASS(len <= H + 0.001, "no tile is drawn larger than the magnified size");
      prevEnd = start + len;
    }

  /* The bar grows by 2S when the whole effect region is inside it. */
  {
    CGFloat firstStart, firstLen, lastStart, lastLen;
    CGFloat barLength = 12 * h;

    DockMagnificationSpan(m, barLength / 2.0, 0, h, &firstStart, &firstLen);
    DockMagnificationSpan(m, barLength / 2.0, 11 * h, h, &lastStart, &lastLen);
    PASS(CLOSE((lastStart + lastLen) - firstStart, barLength + 2 * m.spread),
         "the bar grows by twice the spread");
  }

  /* Without magnification the layout is the one the Dock has at rest. */
  {
    DockMagnification none = DockMagnificationMake(h, h, W);

    PASS(CLOSE(none.spread, 0.0), "equal sizes mean no spread");
    DockMagnificationSpan(none, 100.0, 300.0, h, &s, &l);
    PASS(CLOSE(s, 300.0) && CLOSE(l, h), "no spread leaves every tile in place");
  }

  /* An effect region narrower than a tile would turn the sine around and
   * shuffle the tiles; it is widened to a tile instead. */
  {
    DockMagnification narrow = DockMagnificationMake(h, H, h / 4.0);

    PASS(narrow.effectWidth >= h, "the effect region is at least one tile wide");
    PASS(narrow.spread > 0.0, "a narrow effect region still magnifies");
  }

  /* The bar may not grow past the edge of the screen, so the effect is cut
   * down to the room beside it. */
  {
    DockMagnification wide = DockMagnificationFit(m, 4 * m.spread);
    DockMagnification tight = DockMagnificationFit(m, m.spread);
    DockMagnification pinched = DockMagnificationFit(m, h / 4.0);
    DockMagnification none = DockMagnificationFit(m, 0.0);

    PASS(CLOSE(wide.spread, m.spread) && CLOSE(wide.effectWidth, m.effectWidth),
         "room to spare leaves the magnification alone");

    PASS(tight.spread <= m.spread / 2.0 + 0.001,
         "a tight bar spreads only as far as there is room for");
    PASS(CLOSE(tight.magnifiedSize, H),
         "the effect region is narrowed before the icons are made smaller");
    PASS(tight.effectWidth >= h,
         "the narrowed effect region is still at least one tile wide");
    DockMagnificationSpan(tight, 500.0, 500.0 - h / 2.0, h, &s, &l);
    PASS(CLOSE(l, H), "the tile under the pointer keeps the magnified size");

    PASS(pinched.spread <= h / 8.0 + 0.001,
         "with hardly any room the spread is hardly anything");
    PASS(pinched.magnifiedSize < H && pinched.magnifiedSize > h,
         "and the icons are drawn smaller than asked for, but still larger");

    PASS(CLOSE(none.spread, 0.0) && CLOSE(none.magnifiedSize, h),
         "no room at all means no magnification");
  }

  /* The magnification comes up as the pointer nears the Dock, so the tiles
   * are drawn at a fraction of the way to the full effect. */
  {
    DockMagnification half = DockMagnificationScale(m, 0.5);
    DockMagnification off = DockMagnificationScale(m, 0.0);
    DockMagnification full = DockMagnificationScale(m, 1.0);

    PASS(CLOSE(half.magnifiedSize, h + (H - h) / 2.0),
         "half way is half the growth");
    PASS(CLOSE(half.spread, m.spread / 2.0),
         "and half the spread, so the tiles never leave the room kept for them");
    PASS(CLOSE(half.effectWidth, m.effectWidth),
         "over the same effect region");
    PASS(CLOSE(off.spread, 0.0) && CLOSE(off.magnifiedSize, h),
         "nothing of the way is the Dock at rest");
    PASS(CLOSE(full.magnifiedSize, H) && CLOSE(full.spread, m.spread),
         "all the way is the magnification itself");

    DockMagnificationSpan(off, 300.0, 100.0, h, &s, &l);
    PASS(CLOSE(s, 100.0) && CLOSE(l, h), "at rest every tile lies where it is");
  }

  /* The effect belongs to the pointer being on the Dock: on the bar, or on
   * the part of a tile that has grown out past it. */
  {
    PASS(CLOSE(DockMagnificationTarget(0.0, 0.0), 1.0),
         "a pointer on the bar asks for the effect");
    PASS(CLOSE(DockMagnificationTarget(1.0, 0.0), 0.0),
         "a pointer just off a Dock at rest asks for nothing");
    PASS(CLOSE(DockMagnificationTarget(40.0, 64.0), 1.0),
         "a pointer on a tile that grew out to it keeps the effect");
    PASS(CLOSE(DockMagnificationTarget(70.0, 64.0), 0.0),
         "a pointer past the grown tiles asks for nothing");
  }

  /* The effect takes the same time to come up however the frames fall, and
   * follows a curve that starts and ends gently. */
  {
    CGFloat duration = 0.2, dt = 1.0 / 60.0;
    CGFloat phase = 0.0;
    int steps = 0;

    PASS(CLOSE(DockMagnificationPhase(0.0, 1.0, dt, duration), dt / duration),
         "a frame covers its own share of the way");
    PASS(CLOSE(DockMagnificationPhase(0.0, 1.0, 10.0, duration), 1.0),
         "a frame that came very late lands on the target, never past it");
    PASS(CLOSE(DockMagnificationPhase(0.5, 0.0, 10.0, duration), 0.0),
         "and the same on the way back");
    PASS(CLOSE(DockMagnificationPhase(0.4, 0.4, dt, duration), 0.4),
         "nothing moves while the pointer holds still");

    while ((phase < 1.0) && (steps < 600))
      {
        phase = DockMagnificationPhase(phase, 1.0, dt, duration);
        steps++;
      }
    PASS(phase == 1.0, "the effect arrives");
    PASS((steps >= 11) && (steps <= 13),
         "in the fifth of a second it is given, at sixty frames a second");

    PASS(CLOSE(DockMagnificationSmooth(0.0), 0.0)
         && CLOSE(DockMagnificationSmooth(1.0), 1.0),
         "the curve runs from rest to the whole effect");
    PASS(CLOSE(DockMagnificationSmooth(0.5), 0.5),
         "through the middle at the middle");
    PASS(DockMagnificationSmooth(0.1) < 0.1
         && DockMagnificationSmooth(0.9) > 0.9,
         "leaving rest and settling gently");
    PASS(DockMagnificationSmooth(0.55) - DockMagnificationSmooth(0.45)
         > DockMagnificationSmooth(0.1) - DockMagnificationSmooth(0.0),
         "and covering the middle of the way faster than the ends");
    PASS(CLOSE(DockMagnificationSmooth(-1.0), 0.0)
         && CLOSE(DockMagnificationSmooth(2.0), 1.0),
         "a phase outside the way is held at its ends");
  }

  [arp release];
  return 0;
}
