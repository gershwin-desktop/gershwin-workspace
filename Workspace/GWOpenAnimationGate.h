/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The open animation shows that something is being opened, so it may only
 * play once the open really goes ahead: not while a question such as "Trust
 * This Application?" is still open, not after Cancel, and not when no
 * application is found.  The item's icon is taken when the user acts
 * (armed), and the animation plays only where the open is committed (fire);
 * an open that ends without committing disarms it. */

#ifndef GW_OPEN_ANIMATION_GATE_H
#define GW_OPEN_ANIMATION_GATE_H

#import <Foundation/Foundation.h>

@interface GWOpenAnimationGate : NSObject
{
  id pending;
}

/* Holds `request` until it is fired or disarmed; replaces an older one. */
- (void)arm:(id)request;

/* The armed request, once: nil when nothing is armed or it was fired. */
- (id)fire;

- (void)disarm;

@end

#endif
