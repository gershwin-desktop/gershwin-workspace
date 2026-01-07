/*
 *  WorkspaceUITesting.h - Protocol for GUI testing support in Workspace
 *
 *  Copyright (C) 2025 Free Software Foundation, Inc.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 */

#ifndef WORKSPACE_UI_TESTING_H
#define WORKSPACE_UI_TESTING_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/**
 * WorkspaceUITesting Protocol
 * 
 * Implement this protocol in the Workspace application delegate to enable
 * GUI testing via the uitest command-line tool. This allows automated testing
 * of Workspace's user interface without manual interaction.
 * 
 * Example implementation:
 * 
 * @interface Workspace (UITesting) <WorkspaceUITesting>
 * @end
 * 
 * @implementation Workspace (UITesting)
 * 
 * - (NSDictionary *)currentWindowHierarchyAsJSON
 * {
 *   NSMutableArray *windowsData = [NSMutableArray array];
 *   NSArray *windows = [NSApplication sharedApplication].windows;
 *   
 *   for (NSWindow *window in windows) {
 *     NSMutableDictionary *windowDict = [NSMutableDictionary dictionary];
 *     [windowDict setObject:[window title] forKey:@"title"];
 *     [windowDict setObject:NSStringFromClass([window class]) forKey:@"class"];
 *     [windowDict setObject:([window isVisible] ? @"visible" : @"hidden") 
 *                    forKey:@"visibility"];
 *     [windowDict setObject:([window isKeyWindow] ? @"yes" : @"no") 
 *                    forKey:@"isKeyWindow"];
 *     
 *     // Add view hierarchy...
 *     [windowsData addObject:windowDict];
 *   }
 *   
 *   return @{
 *     @"windows": windowsData,
 *     @"timestamp": [NSDate date]
 *   };
 * }
 * 
 * - (NSArray *)allWindowTitles
 * {
 *   return [[NSApplication sharedApplication].windows valueForKey:@"title"];
 * }
 * 
 * @end
 */
@protocol WorkspaceUITesting <NSObject>

/**
 * Returns the current window and view hierarchy as a JSON-serializable dictionary.
 * 
 * The returned dictionary should contain:
 * - windows: Array of window dictionaries with their properties and view hierarchy
 * - timestamp: When the state was captured
 * 
 * Each window should include:
 * - title: Window title
 * - class: Window class name
 * - visibility: "visible" or "hidden"
 * - isKeyWindow: "yes" or "no"
 * - views: Array of view dictionaries with state information
 * 
 * Each view should include:
 * - class: View class name (NSButton, NSTextField, NSLabel, etc.)
 * - visibility: "visible" or "hidden"
 * - state: "enabled" or "disabled" (for controls)
 * - text: Text content if applicable
 * - checkState: "checked", "unchecked", "mixed" (for buttons)
 * - frame: {x, y, width, height} coordinates
 * - children: Array of child views
 * 
 * @return NSDictionary representing the window hierarchy, JSON-serializable
 */
- (NSDictionary *)currentWindowHierarchyAsJSON;

/**
 * Returns an array of all currently visible window titles.
 * 
 * @return NSArray of NSString window titles
 */
- (NSArray *)allWindowTitles;

@optional

/**
 * Highlight a UI element with red overlay to indicate test failure.
 * Uses oneway void to avoid distributed objects return value issues.
 * 
 * @param windowTitle Title of the window containing the element
 * @param elementText Text content to search for
 * @param duration How long to show the highlight (0 = permanent)
 */
- (oneway void)showFailureHighlightInWindow:(NSString *)windowTitle 
                                   withText:(NSString *)elementText
                                   duration:(CGFloat)duration;

/**
 * Clear all failure highlight overlays
 */
- (oneway void)clearFailureHighlights;

/**
 * Returns all menus and menu items with their enabled/disabled state.
 * 
 * The returned dictionary should contain:
 * - menus: Array of menu dictionaries
 * 
 * Each menu contains:
 * - title: Menu title (e.g., "File", "Edit")
 * - items: Array of menu item dictionaries
 * 
 * Each menu item contains:
 * - title: Item title
 * - enabled: Boolean indicating if item is enabled
 * - shortcut: Key equivalent string (e.g., "⌘N")
 * - hasSubmenu: Boolean indicating if item has a submenu
 * 
 * @return NSDictionary with menu structure, JSON-serializable (bycopy for DO)
 */
- (bycopy NSDictionary *)allMenuItemsWithState;

/**
 * Returns all menus and menu items as a JSON string.
 * This method is more reliable for distributed objects.
 * 
 * @return NSString with JSON representation of menu structure
 */
- (NSString *)allMenuItemsWithStateAsJSON;

@end

#endif /* WORKSPACE_UI_TESTING_H */
