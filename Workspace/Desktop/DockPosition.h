/* DockPosition.h
 *
 * The screen edge the Dock is on, as stored in the "dockposition" default.
 * In a header of its own so that Foundation-only code (DockSeparatorMenu)
 * can name it without the AppKit headers GWDesktopManager.h pulls in.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef DOCK_POSITION_H
#define DOCK_POSITION_H

/* The values are in users' defaults and must never change. */
typedef enum {
  DockPositionLeft,
  DockPositionRight,
  DockPositionBottom
} DockPosition;

#endif /* DOCK_POSITION_H */
