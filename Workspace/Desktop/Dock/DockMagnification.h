/* DockMagnification.h
 *
 * The geometry of the Dock's magnification, as described by the expired
 * patent US7434177 ("User interface for providing consolidation and
 * access").  The tiles around the pointer are drawn larger so that many of
 * them fit in one bar and the one being aimed at is still legible; the
 * tiles beyond the effect region slide away to make room, and the bar grows
 * by twice the spread.
 *
 * The patent's own terms are kept here: h is the size of an unmagnified
 * tile, H the size of the tile the pointer is on, W how far to either side
 * of the pointer the effect reaches, and S the resulting spread.
 *
 *   S  = ((H - h) / 2) / sin(pi * (h / 2) / (W * 2))          (1)
 *   d' = S * sin(pi / 2 * d / W)                              (2), (3)
 *
 * An edge of a tile at distance d from the pointer is drawn at d', so a
 * tile spanning d1 to d2 is drawn between d1' and d2', which scales it by
 * 1 + (d2' - d1') / (d2 - d1)                                 (4)
 *
 * Because neighbouring tiles share an edge, and the same distance always
 * yields the same displacement, the tiles stay adjacent with no gaps and no
 * overlaps.  This is Foundation-only inline code so that it can be tested
 * headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_MAGNIFICATION_H
#define DOCK_MAGNIFICATION_H

#import <Foundation/Foundation.h>
#include <math.h>

typedef struct
{
  CGFloat tileSize;       /* h */
  CGFloat magnifiedSize;  /* H */
  CGFloat effectWidth;    /* W */
  CGFloat spread;         /* S */
} DockMagnification;

static inline DockMagnification
DockMagnificationMake(CGFloat tileSize, CGFloat magnifiedSize,
                      CGFloat effectWidth)
{
  DockMagnification m;

  /* Below one tile the sine of equation (1) is past its peak, which would
   * make nearer edges move further than farther ones and shuffle the tiles
   * around each other. */
  if (effectWidth < tileSize)
    effectWidth = tileSize;

  m.tileSize = tileSize;
  m.magnifiedSize = (magnifiedSize > tileSize) ? magnifiedSize : tileSize;
  m.effectWidth = effectWidth;
  m.spread = ((m.magnifiedSize - tileSize) / 2.0)
             / sin(M_PI * (tileSize / 2.0) / (effectWidth * 2.0));

  return m;
}

/* The largest magnification that fits in the room there is beside the bar,
 * which grows by up to twice the spread: the effect region is narrowed
 * first, because that keeps the icon the pointer is on at the size it was
 * asked to be; only when even the narrowest region would push the bar past
 * the edge of the screen are the icons themselves drawn smaller. */
static inline DockMagnification
DockMagnificationFit(DockMagnification m, CGFloat room)
{
  CGFloat maxSpread = (room > 0.0) ? (room / 2.0) : 0.0;
  CGFloat rise, sine, width;

  if (m.spread <= maxSpread)
    return m;

  if (maxSpread <= 0.0)
    return DockMagnificationMake(m.tileSize, m.tileSize, m.effectWidth);

  /* Equation (1) read backwards: the sine the spread would have to sit on. */
  rise = (m.magnifiedSize - m.tileSize) / 2.0;
  sine = rise / maxSpread;

  if (sine <= 1.0)
    {
      width = (M_PI * m.tileSize / 4.0) / asin(sine);

      if (width >= m.tileSize)
        return DockMagnificationMake(m.tileSize, m.magnifiedSize, width);
    }

  /* The narrowest region is one tile wide, where equation (1) leaves the
   * spread at the rise over sin(pi / 4). */
  return DockMagnificationMake(m.tileSize,
                               m.tileSize + 2.0 * maxSpread * sin(M_PI / 4.0),
                               m.tileSize);
}

/* Where an edge at distance d from the pointer is drawn, relative to where
 * it lies without magnification. */
static inline CGFloat
DockMagnificationDisplacement(DockMagnification m, CGFloat d)
{
  if (d > m.effectWidth)
    d = m.effectWidth;
  else if (d < -m.effectWidth)
    d = -m.effectWidth;

  return m.spread * sin(M_PI / 2.0 * d / m.effectWidth);
}

/* The magnification part of the way up, for an effect that comes up as the
 * pointer nears the Dock rather than all at once.  The effect region stays
 * as wide as it is, so the spread grows with the fraction and the tiles
 * never need more room than the whole effect was given. */
static inline DockMagnification
DockMagnificationScale(DockMagnification m, CGFloat fraction)
{
  if (fraction <= 0.0)
    return DockMagnificationMake(m.tileSize, m.tileSize, m.effectWidth);

  if (fraction >= 1.0)
    return m;

  return DockMagnificationMake(m.tileSize,
                               m.tileSize
                                 + fraction * (m.magnifiedSize - m.tileSize),
                               m.effectWidth);
}

/* Whether a pointer that far from the bar is on the Dock, and so asks for
 * the effect: on the bar itself, or on the part of a tile that has already
 * grown out beyond it.  The tiles therefore keep the pointer they grew
 * towards, and the effect ends where they end, as the patent has it. */
static inline CGFloat
DockMagnificationTarget(CGFloat distance, CGFloat rise)
{
  return (distance <= rise) ? 1.0 : 0.0;
}

/* One frame of the effect on its way in or out: the whole way takes the
 * same time however fast the frames come, and a frame that came late moves
 * further rather than faster.  The phase is the plain part of the way that
 * has been covered; the size follows it along a curve. */
static inline CGFloat
DockMagnificationPhase(CGFloat phase, CGFloat target, CGFloat seconds,
                       CGFloat duration)
{
  CGFloat step;

  if (duration <= 0.0)
    return target;

  step = seconds / duration;

  if (target > phase)
    return (phase + step >= target) ? target : (phase + step);
  if (target < phase)
    return (phase - step <= target) ? target : (phase - step);

  return phase;
}

/* The curve the size follows: it leaves rest and settles at the far end
 * gently, and covers the middle quickly, which is what makes the growing
 * look like a movement rather than a switch. */
static inline CGFloat
DockMagnificationSmooth(CGFloat phase)
{
  if (phase <= 0.0)
    return 0.0;
  if (phase >= 1.0)
    return 1.0;

  return phase * phase * (3.0 - 2.0 * phase);
}

/* Where the tile lying from start to start + length along the bar is drawn
 * with the pointer at cursor. */
static inline void
DockMagnificationSpan(DockMagnification m, CGFloat cursor,
                      CGFloat start, CGFloat length,
                      CGFloat *outStart, CGFloat *outLength)
{
  CGFloat first = start + DockMagnificationDisplacement(m, start - cursor);
  CGFloat last = start + length
                 + DockMagnificationDisplacement(m, start + length - cursor);

  *outStart = first;
  *outLength = last - first;
}

#endif /* DOCK_MAGNIFICATION_H */
