/* GWNetworkIcon.m
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

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "GWNetworkIcon.h"
#import "NetworkServiceItem.h"

#define DOUBLE_CLICK_TIME 0.3
#define LABEL_HEIGHT 28
#define LABEL_FONT_SIZE 11

@implementation GWNetworkIcon

- (id)initWithService:(NetworkServiceItem *)aService iconSize:(int)size
{
  NSRect frame = NSMakeRect(0, 0, size, size + LABEL_HEIGHT);
  self = [super initWithFrame:frame];
  if (self) {
    ASSIGN(service, aService);
    iconSize = size;
    isSelected = NO;
    lastClickTime = 0;
    
    [self loadIcon];
    [self calculateRects];
  }
  return self;
}

- (void)dealloc
{
  RELEASE(service);
  RELEASE(icon);
  [super dealloc];
}

- (void)loadIcon
{
  /* Try to load a network-specific icon, fall back to generic */
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *iconName = nil;
  
  if ([service isSFTPService]) {
    iconName = @"Network_SFTP";
  } else if ([service isAFPService]) {
    iconName = @"Network_AFP";
  }
  
  if (iconName) {
    NSString *path = [bundle pathForResource:iconName ofType:@"tiff"];
    if (path) {
      icon = [[NSImage alloc] initWithContentsOfFile:path];
    }
  }
  
  /* Fall back to a generic network icon or file manager icon */
  if (icon == nil) {
    NSString *path = [bundle pathForResource:@"Network" ofType:@"tiff"];
    if (path) {
      icon = [[NSImage alloc] initWithContentsOfFile:path];
    }
  }
  
  /* Last resort: use a system folder icon */
  if (icon == nil) {
    icon = [[[NSWorkspace sharedWorkspace] iconForFile:@"/Network"] retain];
  }
  
  /* Resize icon if needed */
  if (icon) {
    [icon setSize:NSMakeSize(iconSize, iconSize)];
  }
}

- (void)calculateRects
{
  NSRect bounds = [self bounds];
  
  /* Icon centered at top */
  float iconX = (bounds.size.width - iconSize) / 2;
  iconRect = NSMakeRect(iconX, 0, iconSize, iconSize);
  
  /* Label at bottom */
  labelRect = NSMakeRect(0, iconSize + 2, bounds.size.width, LABEL_HEIGHT - 2);
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame:frame];
  [self calculateRects];
}

- (BOOL)isFlipped
{
  return YES;
}

- (NetworkServiceItem *)service
{
  return service;
}

- (void)setSelected:(BOOL)selected
{
  if (isSelected != selected) {
    isSelected = selected;
    [self setNeedsDisplay:YES];
  }
}

- (BOOL)isSelected
{
  return isSelected;
}

- (void)setTarget:(id)aTarget
{
  target = aTarget;
}

- (void)setAction:(SEL)anAction
{
  action = anAction;
}

- (void)setDoubleAction:(SEL)anAction
{
  doubleAction = anAction;
}

- (void)drawRect:(NSRect)rect
{
  /* Draw selection highlight */
  if (isSelected) {
    [[NSColor selectedControlColor] set];
    
    /* Draw highlight behind icon */
    NSRect highlightRect = NSInsetRect(iconRect, -4, -4);
    highlightRect = NSIntegralRect(highlightRect);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:highlightRect
                                                         xRadius:6
                                                         yRadius:6];
    [path fill];
  }
  
  /* Draw the icon */
  if (icon) {
    NSRect destRect = iconRect;
    [icon drawInRect:destRect
            fromRect:NSZeroRect
           operation:NSCompositeSourceOver
            fraction:1.0];
  }
  
  /* Draw the label */
  NSString *labelText = [service displayName];
  if (labelText) {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setAlignment:NSCenterTextAlignment];
    [style setLineBreakMode:NSLineBreakByTruncatingMiddle];
    
    NSDictionary *attributes = @{
      NSFontAttributeName: [NSFont systemFontOfSize:LABEL_FONT_SIZE],
      NSForegroundColorAttributeName: isSelected ? [NSColor selectedControlTextColor] : [NSColor controlTextColor],
      NSParagraphStyleAttributeName: style
    };
    
    /* If selected, draw label background */
    if (isSelected) {
      NSRect labelBgRect = labelRect;
      labelBgRect.size.height = LABEL_FONT_SIZE + 4;
      labelBgRect.origin.y = labelRect.origin.y + (labelRect.size.height - labelBgRect.size.height) / 2;
      
      [[NSColor selectedControlColor] set];
      NSBezierPath *labelPath = [NSBezierPath bezierPathWithRoundedRect:labelBgRect
                                                                xRadius:3
                                                                yRadius:3];
      [labelPath fill];
    }
    
    [labelText drawInRect:labelRect withAttributes:attributes];
  }
  
  /* Draw service type indicator (small text below name) */
  NSString *typeText = nil;
  if ([service isSFTPService]) {
    typeText = @"SFTP";
  } else if ([service isAFPService]) {
    typeText = @"AFP";
  }
  
  if (typeText && !isSelected) {
    NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setAlignment:NSCenterTextAlignment];
    
    NSDictionary *attributes = @{
      NSFontAttributeName: [NSFont systemFontOfSize:9],
      NSForegroundColorAttributeName: [NSColor grayColor],
      NSParagraphStyleAttributeName: style
    };
    
    NSRect typeRect = labelRect;
    typeRect.origin.y += LABEL_FONT_SIZE + 2;
    typeRect.size.height = 12;
    
    [typeText drawInRect:typeRect withAttributes:attributes];
  }
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  
  /* Check for double-click */
  if (now - lastClickTime < DOUBLE_CLICK_TIME) {
    if (target && doubleAction) {
      [target performSelector:doubleAction withObject:self];
    }
    lastClickTime = 0;
  } else {
    /* Single click */
    if (target && action) {
      [target performSelector:action withObject:self];
    }
    lastClickTime = now;
  }
}

@end
