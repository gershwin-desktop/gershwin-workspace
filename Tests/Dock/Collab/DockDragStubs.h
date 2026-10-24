/* DockDragStubs.h - what t_DockDragRemoval's DockIcon stand-in adds.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "DockIcon.h"

@interface DockIcon (DockDragStandIn)
- (id)initStandInWithPath:(NSString *)path docked:(BOOL)value;
- (BOOL)isDndSourceIconForTest;
@end
