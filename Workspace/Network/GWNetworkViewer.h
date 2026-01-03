/* GWNetworkViewer.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class NetworkServiceManager;
@class NetworkServiceItem;
@class GWNetworkIconsView;
@class Workspace;

/**
 * GWNetworkViewer displays discovered network services in a Workspace window.
 * It shows SFTP-SSH and AFP services discovered via mDNS/Bonjour.
 */
@interface GWNetworkViewer : NSObject <NSWindowDelegate>
{
  NSWindow *window;
  NSScrollView *scrollView;
  GWNetworkIconsView *iconsView;
  
  NetworkServiceManager *serviceManager;
  NSMutableArray *displayedServices;
  
  Workspace *gworkspace;
  NSNotificationCenter *nc;
  
  BOOL isActive;
}

/**
 * Returns the shared network viewer instance.
 */
+ (instancetype)sharedViewer;

/**
 * Shows the network viewer window, bringing it to front.
 */
- (void)showWindow;

/**
 * Returns the window.
 */
- (NSWindow *)window;

/**
 * Returns YES if the viewer is currently visible.
 */
- (BOOL)isVisible;

/**
 * Activate the viewer window.
 */
- (void)activate;

/**
 * Returns the currently selected services.
 */
- (NSArray *)selectedServices;

/**
 * Returns all services currently being displayed.
 */
- (NSArray *)services;

@end
