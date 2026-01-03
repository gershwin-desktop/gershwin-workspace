/* GWNetworkIconsView.m
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
#import "GWNetworkIconsView.h"
#import "GWNetworkIcon.h"
#import "GWNetworkViewer.h"
#import "NetworkServiceItem.h"

#define DEFAULT_ICON_SIZE 48
#define GRID_MARGIN 16
#define ICON_SPACING 16
#define LABEL_HEIGHT 32

@implementation GWNetworkIconsView

- (id)initWithFrame:(NSRect)frame forViewer:(GWNetworkViewer *)aViewer
{
  self = [super initWithFrame:frame];
  if (self) {
    viewer = aViewer;
    icons = [[NSMutableArray alloc] init];
    selectedIcons = [[NSMutableArray alloc] init];
    
    iconSize = DEFAULT_ICON_SIZE;
    gridWidth = iconSize + ICON_SPACING;
    gridHeight = iconSize + LABEL_HEIGHT + ICON_SPACING;
    iconsPerRow = 4;
    
    backgroundColor = [[NSColor controlBackgroundColor] retain];
    isDragTarget = NO;
    
    [self setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
  }
  return self;
}

- (void)dealloc
{
  RELEASE(icons);
  RELEASE(selectedIcons);
  RELEASE(backgroundColor);
  [super dealloc];
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)reloadServices
{
  /* Remove all existing icons */
  for (GWNetworkIcon *icon in icons) {
    [icon removeFromSuperview];
  }
  [icons removeAllObjects];
  [selectedIcons removeAllObjects];
  
  /* Get services from viewer */
  NSArray *services = [viewer services];
  
  NSLog(@"GWNetworkIconsView: Reloading with %lu services", (unsigned long)[services count]);
  
  /* Create icons for each service */
  for (NetworkServiceItem *service in services) {
    GWNetworkIcon *icon = [[GWNetworkIcon alloc] initWithService:service 
                                                        iconSize:iconSize];
    [icon setTarget:self];
    [icon setAction:@selector(iconClicked:)];
    [icon setDoubleAction:@selector(iconDoubleClicked:)];
    [icons addObject:icon];
    [self addSubview:icon];
    RELEASE(icon);
  }
  
  [self tile];
  [self setNeedsDisplay:YES];
}

- (void)tile
{
  NSRect bounds = [self bounds];
  
  /* Calculate icons per row based on available width */
  int availableWidth = bounds.size.width - (2 * GRID_MARGIN);
  iconsPerRow = MAX(1, availableWidth / gridWidth);
  
  /* Calculate number of rows */
  int rowCount = ([icons count] + iconsPerRow - 1) / iconsPerRow;
  if (rowCount == 0) rowCount = 1;
  
  /* Calculate required height */
  int requiredHeight = (rowCount * gridHeight) + (2 * GRID_MARGIN);
  
  /* Set frame size */
  NSRect newFrame = [self frame];
  newFrame.size.height = MAX(requiredHeight, bounds.size.height);
  [self setFrame:newFrame];
  
  /* Position each icon */
  int index = 0;
  for (GWNetworkIcon *icon in icons) {
    int row = index / iconsPerRow;
    int col = index % iconsPerRow;
    
    float x = GRID_MARGIN + (col * gridWidth) + (gridWidth - iconSize) / 2;
    float y = GRID_MARGIN + (row * gridHeight);
    
    NSRect iconFrame = NSMakeRect(x, y, iconSize, iconSize + LABEL_HEIGHT);
    [icon setFrame:iconFrame];
    
    index++;
  }
  
  NSLog(@"GWNetworkIconsView: Tiled %lu icons in %d rows", 
        (unsigned long)[icons count], rowCount);
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldSize
{
  [super resizeWithOldSuperviewSize:oldSize];
  [self tile];
}

- (void)drawRect:(NSRect)rect
{
  [backgroundColor set];
  NSRectFill(rect);
}

#pragma mark - Selection

- (NSArray *)selectedServices
{
  NSMutableArray *result = [NSMutableArray array];
  for (GWNetworkIcon *icon in selectedIcons) {
    [result addObject:[icon service]];
  }
  return result;
}

- (void)selectIconForService:(NetworkServiceItem *)service
{
  GWNetworkIcon *icon = [self iconForService:service];
  if (icon && ![selectedIcons containsObject:icon]) {
    [icon setSelected:YES];
    [selectedIcons addObject:icon];
  }
}

- (void)unselectAll
{
  for (GWNetworkIcon *icon in selectedIcons) {
    [icon setSelected:NO];
  }
  [selectedIcons removeAllObjects];
}

- (GWNetworkIcon *)iconForService:(NetworkServiceItem *)service
{
  for (GWNetworkIcon *icon in icons) {
    if ([[icon service] isEqual:service]) {
      return icon;
    }
  }
  return nil;
}

#pragma mark - Icon Actions

- (void)iconClicked:(GWNetworkIcon *)icon
{
  NSEvent *event = [NSApp currentEvent];
  BOOL shiftKey = ([event modifierFlags] & NSShiftKeyMask) != 0;
  BOOL cmdKey = ([event modifierFlags] & NSCommandKeyMask) != 0;
  
  if (!shiftKey && !cmdKey) {
    /* Single selection - deselect all others */
    [self unselectAll];
  }
  
  if ([selectedIcons containsObject:icon]) {
    /* Deselect if already selected and modifier key held */
    if (cmdKey) {
      [icon setSelected:NO];
      [selectedIcons removeObject:icon];
    }
  } else {
    [icon setSelected:YES];
    [selectedIcons addObject:icon];
  }
  
  NSLog(@"GWNetworkIconsView: Selected %lu icons", (unsigned long)[selectedIcons count]);
}

- (void)iconDoubleClicked:(GWNetworkIcon *)icon
{
  NetworkServiceItem *service = [icon service];
  NSLog(@"GWNetworkIconsView: Double-clicked on: %@", [service displayName]);
  
  /* TODO: Implement connection to service */
  /* For now, just log the details */
  if ([service resolved]) {
    NSLog(@"GWNetworkIconsView: Service details - host: %@, port: %d", 
          [service hostName], [service port]);
  } else {
    NSLog(@"GWNetworkIconsView: Service not yet resolved");
  }
}

#pragma mark - Mouse Events

- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  
  /* Check if clicked on empty space */
  BOOL clickedOnIcon = NO;
  for (GWNetworkIcon *icon in icons) {
    if (NSPointInRect(point, [icon frame])) {
      clickedOnIcon = YES;
      break;
    }
  }
  
  if (!clickedOnIcon) {
    [self unselectAll];
  }
  
  [[self window] makeFirstResponder:self];
}

@end
