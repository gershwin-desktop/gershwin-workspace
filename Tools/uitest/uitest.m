/*
 *  uitest.m: GUI testing command-line tool for Workspace
 *
 *  Copyright (C) 2025 Free Software Foundation, Inc.
 *
 *   Author: Workspace Development
 *   Date: January 2025
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1335  USA
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/* Protocol for UI testing support - can be implemented by Workspace */
@protocol WorkspaceUITesting
- (NSDictionary *)currentWindowHierarchyAsJSON;
- (NSArray *)allWindowTitles;
@end

typedef enum {
  TestActionNone = 0,
  TestActionAbout,
  TestActionShowHelp,
  TestActionAtCoordinate,
  TestActionRunScript,
  TestActionQuery,
  TestActionClick,
  TestActionMenu,
  TestActionShortcut,
  TestActionHighlight,
  TestActionClearHighlights,
  TestActionWaitWindow,
  TestActionCloseWindow,
  TestActionFindElement,
  TestActionListMenus
} TestAction;

/* Forward declarations */
void printUIElementInfo(NSArray *elements);
void printUIElementInfoWithIndent(NSArray *elements, int indent);

void printUsage(const char *programName) {
  fprintf(stderr, "Usage: %s [command] [options]\n\n", programName);
  fprintf(stderr, "Commands:\n");
  fprintf(stderr, "  about                Open the Workspace About box and extract text from it\n");
  fprintf(stderr, "  at-coordinate X Y    Show all UI elements at screen coordinates X, Y\n");
  fprintf(stderr, "  query [options]      Query UI state in various formats\n");
  fprintf(stderr, "                       --json (default) | --tree | --text\n");
  fprintf(stderr, "  list-menus           List all menus and items with enabled/disabled state\n");
  fprintf(stderr, "  run-script PATH      Run Python test script against Workspace\n");
  fprintf(stderr, "\n");
  fprintf(stderr, "UI Interaction Commands:\n");
  fprintf(stderr, "  click X Y            Click at screen coordinates X, Y\n");
  fprintf(stderr, "  menu \"Path\"          Open menu item by path (e.g., \"Info > About\")\n");
  fprintf(stderr, "  shortcut \"Keys\"      Send keyboard shortcut (e.g., \"Cmd+i\")\n");
  fprintf(stderr, "  wait-window \"Title\" [timeout]  Wait for window to appear (default 5s)\n");
  fprintf(stderr, "  close-window \"Title\" Close a window by title\n");
  fprintf(stderr, "  find \"Window\" \"Text\" Find element with text in window\n");
  fprintf(stderr, "\n");
  fprintf(stderr, "Failure Highlighting:\n");
  fprintf(stderr, "  highlight \"Window\" \"Text\" [duration]  Highlight element with red overlay\n");
  fprintf(stderr, "  clear-highlights     Remove all red failure highlights\n");
  fprintf(stderr, "\n");
  fprintf(stderr, "  help                 Show this help message\n\n");
  fprintf(stderr, "This tool communicates with a running Workspace instance\n");
  fprintf(stderr, "via distributed objects (requires Workspace started with -d flag).\n");
}

NSMutableDictionary* getViewState(NSView *view) {
  NSMutableDictionary *state = [NSMutableDictionary dictionary];
  NSString *className = NSStringFromClass([view class]);
  
  [state setObject:className forKey:@"class"];
  
  /* Visibility state */
  if ([view respondsToSelector:@selector(isHidden)]) {
    BOOL isHidden = [view isHidden];
    [state setObject:(isHidden ? @"hidden" : @"visible") forKey:@"visibility"];
  } else {
    [state setObject:@"visible" forKey:@"visibility"];
  }
  
  /* Enabled state (for controls) */
  if ([view respondsToSelector:@selector(isEnabled)]) {
    NSNumber *enabledNum = (NSNumber *)[view performSelector:@selector(isEnabled)];
    BOOL isEnabled = [enabledNum boolValue];
    [state setObject:(isEnabled ? @"enabled" : @"disabled") forKey:@"state"];
  }
  
  /* Checked state (for buttons, checkboxes, etc.) */
  if ([view respondsToSelector:@selector(state)]) {
    NSInteger buttonState = [[view performSelector:@selector(state)] integerValue];
    NSString *stateStr;
    switch (buttonState) {
      case NSControlStateValueOff:
        stateStr = @"unchecked";
        break;
      case NSControlStateValueOn:
        stateStr = @"checked";
        break;
      case NSControlStateValueMixed:
        stateStr = @"mixed";
        break;
      default:
        stateStr = @"unknown";
    }
    [state setObject:stateStr forKey:@"checkState"];
  }
  
  /* Text content */
  NSString *textContent = nil;
  
  if ([view respondsToSelector:@selector(stringValue)]) {
    NSString *value = (NSString *)[view performSelector:@selector(stringValue)];
    if (value && [value length] > 0) {
      textContent = value;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(title)]) {
    NSString *title = (NSString *)[view performSelector:@selector(title)];
    if (title && [title length] > 0) {
      textContent = title;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(string)]) {
    NSString *string = (NSString *)[view performSelector:@selector(string)];
    if (string && [string length] > 0) {
      textContent = string;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(attributedStringValue)]) {
    NSAttributedString *attrStr = (NSAttributedString *)[view performSelector:@selector(attributedStringValue)];
    if (attrStr && [attrStr length] > 0) {
      textContent = [attrStr string];
    }
  }
  
  if (textContent) {
    [state setObject:textContent forKey:@"text"];
  }
  
  /* Frame/bounds */
  NSRect frame = [view frame];
  NSDictionary *frameDic = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithDouble:frame.origin.x], @"x",
    [NSNumber numberWithDouble:frame.origin.y], @"y",
    [NSNumber numberWithDouble:frame.size.width], @"width",
    [NSNumber numberWithDouble:frame.size.height], @"height",
    nil];
  [state setObject:frameDic forKey:@"frame"];
  
  return state;
}

NSMutableArray* buildViewTree(NSView *view) {
  NSMutableArray *tree = [NSMutableArray array];
  NSMutableDictionary *nodeDict = [getViewState(view) mutableCopy];
  
  /* Add subviews */
  if ([view respondsToSelector:@selector(subviews)]) {
    NSArray *subviews = [view subviews];
    if ([subviews count] > 0) {
      NSMutableArray *children = [NSMutableArray array];
      for (NSView *subview in subviews) {
        NSMutableArray *childTree = buildViewTree(subview);
        [children addObjectsFromArray:childTree];
      }
      [nodeDict setObject:children forKey:@"children"];
    }
  }
  
  [tree addObject:nodeDict];
  return tree;
}

void printUITreeAsJSON(NSWindow *window) {
  NSString *windowTitle = [window title];
  NSMutableDictionary *windowData = [NSMutableDictionary dictionary];
  NSString *windowClassName = NSStringFromClass([window class]);
  
  [windowData setObject:windowTitle forKey:@"windowTitle"];
  [windowData setObject:windowClassName forKey:@"windowClass"];
  
  /* Window visibility and state */
  BOOL isVisible = [window isVisible];
  [windowData setObject:(isVisible ? @"visible" : @"hidden") forKey:@"windowVisibility"];
  
  if ([window respondsToSelector:@selector(isKeyWindow)]) {
    [windowData setObject:([window isKeyWindow] ? @"key" : @"notKey") forKey:@"focus"];
  }
  
  /* Build view tree */
  NSView *contentView = [window contentView];
  if (contentView) {
    NSMutableArray *viewTree = buildViewTree(contentView);
    [windowData setObject:viewTree forKey:@"views"];
  }
  
  /* Serialize to JSON */
  NSError *error = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:windowData
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:&error];
  
  if (error) {
    fprintf(stderr, "Error serializing to JSON: %s\n", [[error localizedDescription] UTF8String]);
  } else {
    NSString *jsonString = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
    fprintf(stdout, "%s\n", [jsonString UTF8String]);
  }
}

void extractTextFromView(NSView *view, int indent) {
  NSString *className = NSStringFromClass([view class]);
  NSString *indentStr = [@"" stringByPaddingToLength:(indent * 2) withString:@" " startingAtIndex:0];
  
  /* Try to extract text from various widget types */
  if ([view respondsToSelector:@selector(stringValue)]) {
    NSString *value = [view performSelector:@selector(stringValue)];
    if (value && [value length] > 0) {
      fprintf(stdout, "%s[%s] %s\n", [indentStr UTF8String], [className UTF8String], [value UTF8String]);
    }
  }
  
  if ([view respondsToSelector:@selector(title)]) {
    NSString *title = [view performSelector:@selector(title)];
    if (title && [title length] > 0) {
      fprintf(stdout, "%s[%s] %s\n", [indentStr UTF8String], [className UTF8String], [title UTF8String]);
    }
  }
  
  if ([view respondsToSelector:@selector(string)]) {
    NSString *string = [view performSelector:@selector(string)];
    if (string && [string length] > 0) {
      fprintf(stdout, "%s[%s] %s\n", [indentStr UTF8String], [className UTF8String], [string UTF8String]);
    }
  }
  
  if ([view respondsToSelector:@selector(attributedStringValue)]) {
    NSAttributedString *attrStr = [view performSelector:@selector(attributedStringValue)];
    if (attrStr && [attrStr length] > 0) {
      fprintf(stdout, "%s[%s] %s\n", [indentStr UTF8String], [className UTF8String], [[attrStr string] UTF8String]);
    }
  }
  
  /* Recursively extract text from subviews */
  if ([view respondsToSelector:@selector(subviews)]) {
    NSArray *subviews = [view subviews];
    for (NSView *subview in subviews) {
      extractTextFromView(subview, indent + 1);
    }
  }
}

void extractAndLogWindowText(NSWindow *window) {
  NSString *windowTitle = [window title];
  fprintf(stdout, "\n=== Window: %s ===\n", [windowTitle UTF8String]);
  
  /* Get the content view and extract text from it */
  NSView *contentView = [window contentView];
  if (contentView) {
    extractTextFromView(contentView, 1);
  }
}

int openAboutBoxAndExtractText(void) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSConnection *connection = nil;
  id appDelegate = nil;
  int result = 0;
  
  NS_DURING {
    /* Attempt to get the connection to the running Workspace application */
    connection = [NSConnection connectionWithRegisteredName:@"Workspace" host:@""];
    
    if (connection == nil) {
      fprintf(stderr, "Error: Cannot contact Workspace application.\n");
      fprintf(stderr, "Make sure Workspace is running.\n");
      result = 1;
    } else {
      /* Get the root object (typically the application delegate) */
      appDelegate = [connection rootProxy];
      
      /* Use a more generic approach: try to respond to showInfo: selector */
      @try {
        if ([appDelegate respondsToSelector:@selector(showInfo:)]) {
          /* If the object responds to showInfo:, call it */
          [appDelegate performSelector:@selector(showInfo:) withObject:nil];
          fprintf(stdout, "About box opened successfully.\n");
        } else if ([appDelegate respondsToSelector:@selector(orderFrontAboutPanel:)]) {
          /* Try alternative selector used by some applications */
          [appDelegate performSelector:@selector(orderFrontAboutPanel:) withObject:nil];
          fprintf(stdout, "About box opened successfully.\n");
        } else {
          /* Fallback: send via NSNotification if direct methods don't work */
          NSNotification *notification = [NSNotification notificationWithName:@"WorkspaceUITest"
                                                                       object:@"showAbout"];
          [[NSNotificationCenter defaultCenter] postNotification:notification];
          fprintf(stdout, "About box request sent via notification.\n");
        }
        
        /* Wait a moment for the window to appear */
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        
        /* Extract structured UI state as JSON */
        fprintf(stdout, "\n--- UI State (JSON) ---\n");
        
        /* Try to get UI state if Workspace implements UITesting protocol */
        @try {
          if ([appDelegate respondsToSelector:@selector(currentWindowHierarchyAsJSON)]) {
            NSString *jsonStr = (NSString *)[appDelegate performSelector:@selector(currentWindowHierarchyAsJSON)];
            if (jsonStr && [jsonStr isKindOfClass:[NSString class]]) {
              fprintf(stdout, "%s\n", [jsonStr UTF8String]);
            } else {
              fprintf(stdout, "{ \"error\": \"Invalid response from Workspace\" }\n");
            }
          } else {
            fprintf(stdout, "{\n");
            fprintf(stdout, "  \"tool\": \"uitest\",\n");
            fprintf(stdout, "  \"action\": \"showAbout\",\n");
            fprintf(stdout, "  \"status\": \"window_opened\",\n");
            fprintf(stdout, "  \"note\": \"Workspace does not implement WorkspaceUITesting protocol\",\n");
            fprintf(stdout, "  \"hint\": \"Start Workspace with -d or --debug flag to enable UI testing\"\n");
            fprintf(stdout, "}\n");
          }
        } @catch (NSException *e) {
          fprintf(stdout, "{\n");
          fprintf(stdout, "  \"error\": \"Failed to retrieve UI state\",\n");
          fprintf(stdout, "  \"exception\": \"%s\"\n", [[e reason] UTF8String]);
          fprintf(stdout, "}\n");
        }
        
      } @catch (NSException *exception) {
        fprintf(stderr, "Error: Failed to open About box.\n");
        fprintf(stderr, "Exception: %s\n", [[exception reason] UTF8String]);
        result = 1;
      }
    }
  }
  NS_HANDLER {
    fprintf(stderr, "Error: Exception occurred during operation.\n");
    fprintf(stderr, "Details: %s\n", [[localException reason] UTF8String]);
    result = 1;
  }
  NS_ENDHANDLER
  
  [pool release];
  return result;
}

int queryUIAtCoordinate(CGFloat x, CGFloat y) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSConnection *connection = nil;
  id appDelegate = nil;
  int result = 0;
  
  @try {
    fprintf(stdout, "=== UI Elements at Coordinate (%.0f, %.0f) ===\n\n", x, y);
    
    /* Connect to Workspace to get window information */
    connection = [NSConnection connectionWithRegisteredName:@"Workspace" host:@""];
    
    if (connection == nil) {
      fprintf(stderr, "Error: Cannot contact Workspace application.\n");
      result = 1;
    } else {
      appDelegate = [connection rootProxy];
      
      @try {
        /* Try to get all windows via the protocol */
        if ([appDelegate respondsToSelector:@selector(currentWindowHierarchyAsJSON)]) {
          NSString *jsonStr = (NSString *)[appDelegate performSelector:@selector(currentWindowHierarchyAsJSON)];
          if (jsonStr && [jsonStr isKindOfClass:[NSString class]]) {
            /* Parse JSON and find windows at coordinate */
            NSError *parseError = nil;
            NSData *jsonData = [jsonStr dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *data = [NSJSONSerialization JSONObjectWithData:jsonData 
                                                                  options:0 
                                                                    error:&parseError];
            
            if (data) {
              NSArray *windows = [data objectForKey:@"windows"];
              BOOL foundElements = NO;
              
              for (NSDictionary *window in windows) {
                NSDictionary *frame = [window objectForKey:@"frame"];
                NSNumber *x_num = [frame objectForKey:@"x"];
                NSNumber *y_num = [frame objectForKey:@"y"];
                NSNumber *w_num = [frame objectForKey:@"width"];
                NSNumber *h_num = [frame objectForKey:@"height"];
                
                if (x_num && y_num && w_num && h_num) {
                  CGFloat wx = [x_num doubleValue];
                  CGFloat wy = [y_num doubleValue];
                  CGFloat ww = [w_num doubleValue];
                  CGFloat wh = [h_num doubleValue];
                  
                  /* Check if coordinate is within window bounds */
                  if (x >= wx && x <= (wx + ww) && y >= wy && y <= (wy + wh)) {
                    NSString *windowTitle = [window objectForKey:@"title"];
                    if (!windowTitle) {
                      windowTitle = [window objectForKey:@"windowTitle"];
                    }
                    if (!windowTitle) {
                      windowTitle = @"(Unknown)";
                    }
                    
                    fprintf(stdout, "Window: %s\n", [windowTitle UTF8String]);
                    fprintf(stdout, "─────────────────────────────────\n");
                    
                    /* Print window elements */
                    NSArray *views = [window objectForKey:@"views"];
                    NSMutableDictionary *contentView = [window objectForKey:@"contentView"];
                    
                    if (views && [views count] > 0) {
                      printUIElementInfo(views);
                      foundElements = YES;
                    } else if (contentView && [contentView objectForKey:@"children"]) {
                      NSArray *children = [contentView objectForKey:@"children"];
                      printUIElementInfo(children);
                      foundElements = YES;
                    }
                    fprintf(stdout, "\n");
                  }
                }
              }
              
              if (!foundElements) {
                fprintf(stdout, "No UI elements found at coordinate (%.0f, %.0f)\n", x, y);
              }
            }
          }
        } else {
          fprintf(stderr, "Error: Workspace doesn't implement UI testing protocol\n");
          fprintf(stderr, "Make sure Workspace is running with -d flag\n");
          result = 1;
        }
      } @catch (NSException *e) {
        fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
        result = 1;
      }
    }
    
  } @catch (NSException *exception) {
    fprintf(stderr, "Error: %s\n", [[exception reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

void printUIElementInfo(NSArray *elements) {
  for (NSDictionary *element in elements) {
    NSString *className = [element objectForKey:@"class"];
    NSString *text = [element objectForKey:@"text"];
    
    fprintf(stdout, "  ├─ %s", [className UTF8String]);
    if (text) {
      fprintf(stdout, " \"%s\"", [text UTF8String]);
    }
    fprintf(stdout, "\n");
    
    NSArray *children = [element objectForKey:@"children"];
    if (children && [children count] > 0) {
      printUIElementInfoWithIndent(children, 1);
    }
  }
}

void printUIElementInfoWithIndent(NSArray *elements, int indent) {
  for (NSDictionary *element in elements) {
    NSString *className = [element objectForKey:@"class"];
    NSString *text = [element objectForKey:@"text"];
    NSString *indentStr = [@"" stringByPaddingToLength:(indent * 2) withString:@" " startingAtIndex:0];
    
    fprintf(stdout, "%s  ├─ %s", [indentStr UTF8String], [className UTF8String]);
    if (text) {
      fprintf(stdout, " \"%s\"", [text UTF8String]);
    }
    fprintf(stdout, "\n");
    
    NSArray *children = [element objectForKey:@"children"];
    if (children && [children count] > 0) {
      printUIElementInfoWithIndent(children, indent + 1);
    }
  }
}

int runPythonTestScript(const char *scriptPath) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  /* Verify script exists */
  NSString *path = [NSString stringWithUTF8String:scriptPath];
  NSFileManager *fm = [NSFileManager defaultManager];
  
  if (![fm fileExistsAtPath:path]) {
    fprintf(stderr, "Error: Script file not found: %s\n", scriptPath);
    [pool release];
    return 1;
  }
  
  /* Set PYTHONPATH to include uitest library directory */
  NSString *uitestDir = [[NSBundle mainBundle] resourcePath];
  if (!uitestDir) {
    /* Fallback: use relative path */
    uitestDir = @"Tools/uitest/python";
  }
  
  setenv("PYTHONPATH", [uitestDir UTF8String], 1);
  
  /* Execute python script */
  NSTask *task = [NSTask new];
  [task setLaunchPath:@"/usr/bin/python3"];
  [task setArguments:@[path]];
  
  @try {
    [task launch];
    [task waitUntilExit];
    int exitCode = [task terminationStatus];
    result = exitCode;
  } @catch (NSException *exception) {
    fprintf(stderr, "Error: Failed to run Python script: %s\n", [[exception reason] UTF8String]);
    result = 1;
  }
  
  [task release];
  [pool release];
  return result;
}

/* Helper to get connection to Workspace */
id getWorkspaceProxy(void) {
  NSConnection *connection = [NSConnection connectionWithRegisteredName:@"Workspace" host:@""];
  if (connection == nil) {
    fprintf(stderr, "Error: Cannot contact Workspace application.\n");
    fprintf(stderr, "Make sure Workspace is running with -d flag.\n");
    return nil;
  }
  return [connection rootProxy];
}

/* Helper to print NSDictionary result as JSON */
void printResultAsJSON(NSDictionary *result) {
  @try {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) {
      fprintf(stdout, "{ \"error\": \"JSON serialization failed\" }\n");
    } else {
      NSString *jsonStr = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
      fprintf(stdout, "%s\n", [jsonStr UTF8String]);
    }
  } @catch (NSException *e) {
    fprintf(stdout, "{ \"error\": \"%s\" }\n", [[e reason] UTF8String]);
  }
}

int doClick(CGFloat x, CGFloat y) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    if ([proxy respondsToSelector:@selector(clickAtX:y:)]) {
      NSDictionary *response = [proxy clickAtX:x y:y];
      printResultAsJSON(response);
      if (![[response objectForKey:@"success"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support click command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doListMenus(void) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  NS_DURING {
    NSConnection *connection = [NSConnection connectionWithRegisteredName:@"Workspace" host:@""];
    if (connection == nil) {
      fprintf(stderr, "Error: Cannot contact Workspace application.\n");
      fprintf(stderr, "Make sure Workspace is running with -d flag.\n");
      [pool release];
      return 1;
    }
    
    id proxy = [connection rootProxy];
    
    /* Use the JSON string method which is more reliable with distributed objects */
    if ([proxy respondsToSelector:@selector(allMenuItemsWithStateAsJSON)]) {
      NSString *jsonResponse = [proxy allMenuItemsWithStateAsJSON];
      
      if (jsonResponse && [jsonResponse length] > 0) {
        /* Parse to verify it's valid JSON */
        NSData *data = [jsonResponse dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error = nil;
        NSDictionary *response = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        
        if (error) {
          fprintf(stderr, "Error: Failed to parse JSON response: %s\n", [[error description] UTF8String]);
          result = 1;
        } else {
          /* Print the JSON directly - it's already formatted */
          printf("%s\n", [jsonResponse UTF8String]);
          if (![[response objectForKey:@"success"] boolValue]) {
            result = 1;
          }
        }
      } else {
        fprintf(stderr, "Error: Empty response from Workspace\n");
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support list-menus command.\n");
      fprintf(stderr, "Make sure Workspace is rebuilt with the latest UITesting support.\n");
      result = 1;
    }
  } NS_HANDLER {
    fprintf(stderr, "Error: %s\n", [[localException reason] UTF8String]);
    result = 1;
  } NS_ENDHANDLER
  
  [pool release];
  return result;
}

int doMenu(const char *menuPath) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    NSString *path = [NSString stringWithUTF8String:menuPath];
    
    if ([proxy respondsToSelector:@selector(openMenu:)]) {
      NSDictionary *response = [proxy openMenu:path];
      printResultAsJSON(response);
      if (![[response objectForKey:@"success"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support menu command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doShortcut(const char *shortcut) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    NSString *keys = [NSString stringWithUTF8String:shortcut];
    
    if ([proxy respondsToSelector:@selector(sendShortcut:)]) {
      NSDictionary *response = [proxy sendShortcut:keys];
      printResultAsJSON(response);
      if (![[response objectForKey:@"success"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support shortcut command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doHighlight(const char *windowTitle, const char *elementText, CGFloat duration) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  NS_DURING {
    NSConnection *connection = [NSConnection connectionWithRegisteredName:@"Workspace" host:@""];
    if (connection == nil) {
      fprintf(stderr, "Error: Cannot contact Workspace application.\n");
      fprintf(stderr, "Make sure Workspace is running with -d flag.\n");
      [pool release];
      return 1;
    }
    
    id proxy = [connection rootProxy];
    NSString *window = [NSString stringWithUTF8String:windowTitle];
    NSString *text = [NSString stringWithUTF8String:elementText];
    
    /* Use the new oneway void method that doesn't return a value */
    if ([proxy respondsToSelector:@selector(showFailureHighlightInWindow:withText:duration:)]) {
      [proxy showFailureHighlightInWindow:window withText:text duration:duration];
      /* Since it's oneway void, we don't wait for a response - just assume success */
      printf("{\"success\":true,\"highlighted\":\"%s\",\"window\":\"%s\"}\n", elementText, windowTitle);
    } else if ([proxy respondsToSelector:@selector(highlightFailedElementInWindow:withText:duration:)]) {
      /* Fallback to old method */
      NSDictionary *response = [proxy highlightFailedElementInWindow:window withText:text duration:duration];
      if (response) {
        printResultAsJSON(response);
        if (![[response objectForKey:@"success"] boolValue]) {
          result = 1;
        }
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support highlight command.\n");
      result = 1;
    }
  } NS_HANDLER {
    fprintf(stderr, "Error: %s\n", [[localException reason] UTF8String]);
    result = 1;
  } NS_ENDHANDLER
  
  [pool release];
  return result;
}

int doClearHighlights(void) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    if ([proxy respondsToSelector:@selector(clearAllHighlights)]) {
      NSDictionary *response = [proxy clearAllHighlights];
      printResultAsJSON(response);
    } else {
      fprintf(stderr, "Error: Workspace doesn't support clear-highlights command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doWaitWindow(const char *windowTitle, CGFloat timeout) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    NSString *title = [NSString stringWithUTF8String:windowTitle];
    
    if ([proxy respondsToSelector:@selector(waitForWindow:timeout:)]) {
      NSDictionary *response = [proxy waitForWindow:title timeout:timeout];
      printResultAsJSON(response);
      if (![[response objectForKey:@"success"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support wait-window command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doCloseWindow(const char *windowTitle) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    NSString *title = [NSString stringWithUTF8String:windowTitle];
    
    if ([proxy respondsToSelector:@selector(closeWindow:)]) {
      NSDictionary *response = [proxy closeWindow:title];
      printResultAsJSON(response);
      if (![[response objectForKey:@"success"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support close-window command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int doFindElement(const char *windowTitle, const char *text) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  int result = 0;
  
  @try {
    id proxy = getWorkspaceProxy();
    if (!proxy) {
      [pool release];
      return 1;
    }
    
    NSString *window = [NSString stringWithUTF8String:windowTitle];
    NSString *elementText = [NSString stringWithUTF8String:text];
    
    if ([proxy respondsToSelector:@selector(findElementInWindow:withText:)]) {
      NSDictionary *response = [proxy findElementInWindow:window withText:elementText];
      printResultAsJSON(response);
      if (![[response objectForKey:@"found"] boolValue]) {
        result = 1;
      }
    } else {
      fprintf(stderr, "Error: Workspace doesn't support find command.\n");
      result = 1;
    }
  } @catch (NSException *e) {
    fprintf(stderr, "Error: %s\n", [[e reason] UTF8String]);
    result = 1;
  }
  
  [pool release];
  return result;
}

int main(int argc, char** argv) {
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  TestAction action = TestActionNone;
  int result = 0;
  
  /* Parse command-line arguments */
  if (argc > 1) {
    NSString *command = [NSString stringWithUTF8String:argv[1]];
    
    if ([command isEqualToString:@"about"]) {
      action = TestActionAbout;
    } else if ([command isEqualToString:@"at-coordinate"] || [command isEqualToString:@"at"]) {
      action = TestActionAtCoordinate;
    } else if ([command isEqualToString:@"query"]) {
      action = TestActionQuery;
    } else if ([command isEqualToString:@"run-script"] || [command isEqualToString:@"run"]) {
      action = TestActionRunScript;
    } else if ([command isEqualToString:@"click"]) {
      action = TestActionClick;
    } else if ([command isEqualToString:@"menu"]) {
      action = TestActionMenu;
    } else if ([command isEqualToString:@"shortcut"]) {
      action = TestActionShortcut;
    } else if ([command isEqualToString:@"highlight"]) {
      action = TestActionHighlight;
    } else if ([command isEqualToString:@"clear-highlights"]) {
      action = TestActionClearHighlights;
    } else if ([command isEqualToString:@"wait-window"]) {
      action = TestActionWaitWindow;
    } else if ([command isEqualToString:@"close-window"]) {
      action = TestActionCloseWindow;
    } else if ([command isEqualToString:@"find"]) {
      action = TestActionFindElement;
    } else if ([command isEqualToString:@"list-menus"]) {
      action = TestActionListMenus;
    } else if ([command isEqualToString:@"help"] || 
               [command isEqualToString:@"--help"] ||
               [command isEqualToString:@"-h"]) {
      action = TestActionShowHelp;
    } else {
      fprintf(stderr, "Unknown command: %s\n\n", argv[1]);
      printUsage(argv[0]);
      [pool release];
      exit(1);
    }
  } else {
    printUsage(argv[0]);
    [pool release];
    exit(1);
  }
  
  /* Execute the requested action */
  switch (action) {
    case TestActionAbout:
      result = openAboutBoxAndExtractText();
      break;
      
    case TestActionAtCoordinate:
      if (argc < 4) {
        fprintf(stderr, "Error: at-coordinate requires X and Y coordinates.\n");
        fprintf(stderr, "Usage: %s at-coordinate X Y\n", argv[0]);
        result = 1;
      } else {
        CGFloat x = atof(argv[2]);
        CGFloat y = atof(argv[3]);
        result = queryUIAtCoordinate(x, y);
      }
      break;
      
    case TestActionRunScript:
      if (argc < 3) {
        fprintf(stderr, "Error: run-script requires a script path.\n");
        fprintf(stderr, "Usage: %s run-script PATH\n", argv[0]);
        result = 1;
      } else {
        result = runPythonTestScript(argv[2]);
      }
      break;
      
    case TestActionQuery:
      result = openAboutBoxAndExtractText();
      break;
      
    case TestActionClick:
      if (argc < 4) {
        fprintf(stderr, "Error: click requires X and Y coordinates.\n");
        fprintf(stderr, "Usage: %s click X Y\n", argv[0]);
        result = 1;
      } else {
        CGFloat x = atof(argv[2]);
        CGFloat y = atof(argv[3]);
        result = doClick(x, y);
      }
      break;
      
    case TestActionMenu:
      if (argc < 3) {
        fprintf(stderr, "Error: menu requires a menu path.\n");
        fprintf(stderr, "Usage: %s menu \"Info > About\"\n", argv[0]);
        result = 1;
      } else {
        result = doMenu(argv[2]);
      }
      break;
      
    case TestActionShortcut:
      if (argc < 3) {
        fprintf(stderr, "Error: shortcut requires key combination.\n");
        fprintf(stderr, "Usage: %s shortcut \"Cmd+i\"\n", argv[0]);
        result = 1;
      } else {
        result = doShortcut(argv[2]);
      }
      break;
      
    case TestActionHighlight:
      if (argc < 4) {
        fprintf(stderr, "Error: highlight requires window title and element text.\n");
        fprintf(stderr, "Usage: %s highlight \"Window\" \"Text\" [duration]\n", argv[0]);
        result = 1;
      } else {
        CGFloat duration = (argc > 4) ? atof(argv[4]) : 0;
        result = doHighlight(argv[2], argv[3], duration);
      }
      break;
      
    case TestActionClearHighlights:
      result = doClearHighlights();
      break;
      
    case TestActionWaitWindow:
      if (argc < 3) {
        fprintf(stderr, "Error: wait-window requires window title.\n");
        fprintf(stderr, "Usage: %s wait-window \"Title\" [timeout]\n", argv[0]);
        result = 1;
      } else {
        CGFloat timeout = (argc > 3) ? atof(argv[3]) : 5.0;
        result = doWaitWindow(argv[2], timeout);
      }
      break;
      
    case TestActionCloseWindow:
      if (argc < 3) {
        fprintf(stderr, "Error: close-window requires window title.\n");
        fprintf(stderr, "Usage: %s close-window \"Title\"\n", argv[0]);
        result = 1;
      } else {
        result = doCloseWindow(argv[2]);
      }
      break;
      
    case TestActionFindElement:
      if (argc < 4) {
        fprintf(stderr, "Error: find requires window title and text.\n");
        fprintf(stderr, "Usage: %s find \"Window\" \"Text\"\n", argv[0]);
        result = 1;
      } else {
        result = doFindElement(argv[2], argv[3]);
      }
      break;
      
    case TestActionListMenus:
      result = doListMenus();
      break;
      
    case TestActionShowHelp:
      printUsage(argv[0]);
      result = 0;
      break;
      
    default:
      printUsage(argv[0]);
      result = 1;
      break;
  }
  
  [pool release];
  exit(result);
}
