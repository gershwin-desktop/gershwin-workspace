/* GWX11SpatialPath.h
 *
 * Manages X11 atoms for spatial path communication between Workspace
 * and WindowManager.  Sets _GW_SPATIAL_PATH on the viewer window so
 * the WM can display a path-component popup when the user modifier-
 * clicks on the titlebar.  Polls _GW_SPATIAL_NAVIGATE to receive
 * navigation requests from the WM.
 *
 * Author: Gershwin Team
 */

#import <Foundation/Foundation.h>

@class FSNode;
@class NSWindow;

@interface GWX11SpatialPath : NSObject
{
  NSWindow *_window;
  NSString *_currentPath;
  NSTimer *_pollTimer;
}

- (instancetype)initWithWindow:(NSWindow *)window path:(NSString *)path;
- (void)setPath:(NSString *)path;
- (void)invalidate;

@end
