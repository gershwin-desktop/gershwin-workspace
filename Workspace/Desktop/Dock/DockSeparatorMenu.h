/* DockSeparatorMenu.h
 *
 * The menu of the line between the Dock's applications and its folders:
 * quick access to the Dock settings without opening the preferences.
 * It describes the items for a state of the settings and the settings
 * that choosing an item leads to; the Dock turns the description into an
 * NSMenu and applies the result through the same desktop manager methods
 * the preferences use, so the menu, the preferences and the Dock cannot
 * disagree.
 *
 * Foundation-only so that it can be tested headless (t_DockSeparatorMenu).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef DOCK_SEPARATOR_MENU_H
#define DOCK_SEPARATOR_MENU_H

#import <Foundation/Foundation.h>
#import "DockPosition.h"

/* The Dock settings the menu shows and changes. */
typedef struct DockSeparatorSettings
{
  BOOL magnification;
  DockPosition position;
} DockSeparatorSettings;

/* One item of the menu: a plain item, an item with a submenu of entries,
 * or a separator. */
@interface DockSeparatorMenuEntry : NSObject
{
  NSString *title;
  NSInteger tag;
  BOOL checked;
  NSArray *submenu;
}

+ (DockSeparatorMenuEntry *)separator;

- (NSString *)title;

/* What choosing the item does, for DockSeparatorSettingsAfterChoice(). */
- (NSInteger)tag;

- (BOOL)isChecked;

/* The entries of its submenu, or nil. */
- (NSArray *)submenu;

- (BOOL)isSeparator;

@end

/* The entries of the menu, in order, with localized titles. */
NSArray *DockSeparatorMenuEntries(DockSeparatorSettings current);

/* The settings after choosing the item with the given tag; unchanged for
 * an item that changes no setting. */
DockSeparatorSettings
DockSeparatorSettingsAfterChoice(DockSeparatorSettings current, NSInteger tag);

/* YES for the item that opens the Dock preferences. */
BOOL DockSeparatorChoiceOpensPreferences(NSInteger tag);

#endif /* DOCK_SEPARATOR_MENU_H */
