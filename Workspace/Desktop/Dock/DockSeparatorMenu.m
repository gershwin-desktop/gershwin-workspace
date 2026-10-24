/* DockSeparatorMenu.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "DockSeparatorMenu.h"

/* An NSMenuItem carries one integer, so a tag holds what the item does
 * and, for a position, which one. */
enum
{
  DockSeparatorChoiceMagnification = 1 << 8,
  DockSeparatorChoicePosition = 2 << 8,
  DockSeparatorChoicePreferences = 3 << 8,
  DockSeparatorChoiceMask = 0xff << 8
};

@implementation DockSeparatorMenuEntry

- (instancetype)initWithTitle:(NSString *)aTitle
                          tag:(NSInteger)aTag
                      checked:(BOOL)isChecked
                      submenu:(NSArray *)entries
{
  self = [super init];
  if (self)
    {
      title = [aTitle copy];
      tag = aTag;
      checked = isChecked;
      submenu = [entries retain];
    }
  return self;
}

- (void)dealloc
{
  [title release];
  [submenu release];
  [super dealloc];
}

+ (DockSeparatorMenuEntry *)entryWithTitle:(NSString *)aTitle
                                       tag:(NSInteger)aTag
                                   checked:(BOOL)isChecked
                                   submenu:(NSArray *)entries
{
  return [[[self alloc] initWithTitle: aTitle
                                  tag: aTag
                              checked: isChecked
                              submenu: entries] autorelease];
}

+ (DockSeparatorMenuEntry *)separator
{
  return [self entryWithTitle: nil tag: 0 checked: NO submenu: nil];
}

- (NSString *)title
{
  return title;
}

- (NSInteger)tag
{
  return tag;
}

- (BOOL)isChecked
{
  return checked;
}

- (NSArray *)submenu
{
  return submenu;
}

- (BOOL)isSeparator
{
  return (title == nil);
}

@end

static DockSeparatorMenuEntry *
positionEntry(NSString *title, DockPosition pos, DockSeparatorSettings current)
{
  return [DockSeparatorMenuEntry
           entryWithTitle: title
                      tag: DockSeparatorChoicePosition | pos
                  checked: (current.position == pos)
                  submenu: nil];
}

NSArray *
DockSeparatorMenuEntries(DockSeparatorSettings current)
{
  /* Left, Bottom, Right: the order the edges have on the screen, not the
   * order of the stored values. */
  NSArray *positions = [NSArray arrayWithObjects:
    positionEntry(NSLocalizedString(@"Left", @""), DockPositionLeft, current),
    positionEntry(NSLocalizedString(@"Bottom", @""), DockPositionBottom, current),
    positionEntry(NSLocalizedString(@"Right", @""), DockPositionRight, current),
    nil];
  NSString *magnification = current.magnification
    ? NSLocalizedString(@"Turn Magnification Off", @"Dock separator menu")
    : NSLocalizedString(@"Turn Magnification On", @"Dock separator menu");

  return [NSArray arrayWithObjects:
    [DockSeparatorMenuEntry entryWithTitle: magnification
                                       tag: DockSeparatorChoiceMagnification
                                   checked: NO
                                   submenu: nil],
    [DockSeparatorMenuEntry
      entryWithTitle: NSLocalizedString(@"Position on Screen",
                                        @"Dock separator menu")
                 tag: 0
             checked: NO
             submenu: positions],
    [DockSeparatorMenuEntry separator],
    [DockSeparatorMenuEntry
      entryWithTitle: NSLocalizedString(@"Dock Preferences...",
                                        @"Dock separator menu")
                 tag: DockSeparatorChoicePreferences
             checked: NO
             submenu: nil],
    nil];
}

DockSeparatorSettings
DockSeparatorSettingsAfterChoice(DockSeparatorSettings current, NSInteger tag)
{
  DockSeparatorSettings next = current;
  NSInteger value = tag & ~DockSeparatorChoiceMask;

  switch (tag & DockSeparatorChoiceMask)
    {
      case DockSeparatorChoiceMagnification:
        next.magnification = !current.magnification;
        break;
      case DockSeparatorChoicePosition:
        if (value == DockPositionLeft || value == DockPositionRight
            || value == DockPositionBottom)
          next.position = (DockPosition)value;
        break;
      default:
        break;
    }
  return next;
}

BOOL
DockSeparatorChoiceOpensPreferences(NSInteger tag)
{
  return ((tag & DockSeparatorChoiceMask) == DockSeparatorChoicePreferences);
}
