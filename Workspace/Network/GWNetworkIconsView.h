/* GWNetworkIconsView.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class GWNetworkViewer;
@class NetworkServiceItem;
@class GWNetworkIcon;

/**
 * GWNetworkIconsView displays network service icons in a grid layout.
 */
@interface GWNetworkIconsView : NSView
{
  GWNetworkViewer *viewer;
  NSMutableArray *icons;            // Array of GWNetworkIcon
  NSMutableArray *selectedIcons;    // Array of selected GWNetworkIcon
  
  int iconSize;
  int gridWidth;
  int gridHeight;
  int iconsPerRow;
  
  NSColor *backgroundColor;
  
  BOOL isDragTarget;
}

- (id)initWithFrame:(NSRect)frame forViewer:(GWNetworkViewer *)aViewer;

/**
 * Reload all service icons from the viewer's service list.
 */
- (void)reloadServices;

/**
 * Returns the currently selected services.
 */
- (NSArray *)selectedServices;

/**
 * Select the icon for the given service.
 */
- (void)selectIconForService:(NetworkServiceItem *)service;

/**
 * Clear all selections.
 */
- (void)unselectAll;

/**
 * Returns the icon for the given service.
 */
- (GWNetworkIcon *)iconForService:(NetworkServiceItem *)service;

@end
