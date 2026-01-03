/* GWNetworkIcon.h
 *  
 * Copyright (C) 2025 Free Software Foundation, Inc.
 *
 * Author: Simon Peter
 * Date: January 2025
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class NetworkServiceItem;

/**
 * GWNetworkIcon represents a single network service as an icon with label.
 */
@interface GWNetworkIcon : NSControl
{
  NetworkServiceItem *service;
  NSImage *icon;
  int iconSize;
  BOOL isSelected;
  
  NSRect iconRect;
  NSRect labelRect;
  
  id target;
  SEL action;
  SEL doubleAction;
  
  NSTimeInterval lastClickTime;
}

- (id)initWithService:(NetworkServiceItem *)aService iconSize:(int)size;

/**
 * Returns the service this icon represents.
 */
- (NetworkServiceItem *)service;

/**
 * Sets whether this icon is selected.
 */
- (void)setSelected:(BOOL)selected;

/**
 * Returns YES if this icon is selected.
 */
- (BOOL)isSelected;

/**
 * Sets the target for click actions.
 */
- (void)setTarget:(id)aTarget;

/**
 * Sets the action for single click.
 */
- (void)setAction:(SEL)anAction;

/**
 * Sets the action for double click.
 */
- (void)setDoubleAction:(SEL)anAction;

@end
