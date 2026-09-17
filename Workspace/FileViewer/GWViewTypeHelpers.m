/*
 * GWViewTypeHelpers.m
 *
 * Shared view-type helpers for the Workspace file viewers.
 *
 * The GWViewType enum is the canonical representation of a viewer's layout
 * (browsing columns, icons, or list).  The legacy string names
 * ("Icon"/"List"/"Browser") are only used by the spatial viewer's defaults
 * and by DS_Store settings, so the enum <-> string conversion lives here
 * once instead of being duplicated in each viewer.  Resolving the requested
 * type from a menu sender prefers the item's tag (which carries the
 * GWViewType) and falls back to parsing the localized title, which makes
 * switching robust on non-English locales where title parsing alone failed.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import "GWViewer.h"

/* The helpers receive menu senders (NSMenuItem); declare tag/title so the
 * compiler knows about them without importing AppKit here. */
@interface NSObject (GWViewTypeSenderMethods)
- (NSInteger)tag;
- (NSString *)title;
@end

@implementation NSObject (GWViewTypeHelpers)

- (NSString *)GWViewTypeName:(GWViewType)type
{
  switch (type)
    {
      case GWViewTypeBrowser: return @"Browser";
      case GWViewTypeIcon:    return @"Icon";
      case GWViewTypeList:    return @"List";
    }
  return nil;
}

- (GWViewType)GWViewTypeFromName:(NSString *)name
{
  if (name == nil)
    return 0;
  if ([name isEqualToString: @"Browser"])
    return GWViewTypeBrowser;
  if ([name isEqualToString: @"Icon"])
    return GWViewTypeIcon;
  if ([name isEqualToString: @"List"])
    return GWViewTypeList;
  return 0;
}

- (GWViewType)GWViewTypeFromSender:(id)sender
{
  /* Prefer the tag, which the View menu items carry as the GWViewType. */
  NSInteger tag = [sender tag];
  if (tag == GWViewTypeBrowser || tag == GWViewTypeIcon || tag == GWViewTypeList)
    {
      return tag;
    }

  /* Fall back to the localized title for senders that only provide one. */
  NSString *upperTitle = [[sender title] uppercaseString];
  if (upperTitle)
    {
      if ([upperTitle rangeOfString: @"BROWSER"].location != NSNotFound
          || [upperTitle rangeOfString: @"COLUMN"].location != NSNotFound
          || [upperTitle rangeOfString: @"SPALTEN"].location != NSNotFound)
        {
          return GWViewTypeBrowser;
        }
      if ([upperTitle rangeOfString: @"ICON"].location != NSNotFound
          || [upperTitle rangeOfString: @"SYMBOL"].location != NSNotFound)
        {
          return GWViewTypeIcon;
        }
      if ([upperTitle rangeOfString: @"LIST"].location != NSNotFound
          || [upperTitle rangeOfString: @"LISTE"].location != NSNotFound)
        {
          return GWViewTypeList;
        }
    }

  return 0;
}

@end
