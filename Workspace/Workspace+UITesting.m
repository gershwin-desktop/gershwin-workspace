/*
 *  Workspace+UITesting.m - GUI Testing support for Workspace
 *
 *  Copyright (C) 2025 Free Software Foundation, Inc.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This category implements the WorkspaceUITesting protocol, which is
 *  enabled only when Workspace is started with -d or --debug flags.
 *
 *  Features:
 *  - Query UI state as JSON
 *  - Click on UI elements at coordinates
 *  - Open menus and select items
 *  - Send keyboard shortcuts
 *  - Highlight failed elements in red for visual feedback
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <unistd.h>
#import <pthread.h>
#import <errno.h>
#import "Workspace.h"
#import "WorkspaceUITesting.h"

/* Global flag to track if debug mode is enabled */
static BOOL uiTestingEnabled = NO;

/* Storage for failure highlight overlay views */
static NSMutableArray *activeHighlightOverlays = nil;

/* Circular buffer for recent log messages (last 100 lines) */
#define LOG_BUFFER_SIZE 100
static NSMutableArray *recentLogMessages = nil;
static NSLock *logBufferLock = nil;

/* Stderr redirection for capturing all output */
static int originalStderr = -1;
static int stderrPipe[2] = {-1, -1};
static pthread_t logReaderThread;
static BOOL logReaderRunning = NO;

/**
 * Add a message to the circular log buffer (raw, no timestamp)
 */
static void _addToLogBufferRaw(NSString *message) {
  if (!recentLogMessages) {
    recentLogMessages = [[NSMutableArray alloc] initWithCapacity:LOG_BUFFER_SIZE];
    logBufferLock = [[NSLock alloc] init];
  }
  
  [logBufferLock lock];
  @try {
    /* Keep only last LOG_BUFFER_SIZE messages */
    if ([recentLogMessages count] >= LOG_BUFFER_SIZE) {
      [recentLogMessages removeObjectAtIndex:0];
    }
    [recentLogMessages addObject:message];
  } @finally {
    [logBufferLock unlock];
  }
}

/**
 * Add a message to the circular log buffer with timestamp
 */
static void _addToLogBuffer(NSString *message) {
  /* Add timestamp to message */
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
  [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
  NSString *timestamp = [formatter stringFromDate:[NSDate date]];
  [formatter release];
  
  NSString *logLine = [NSString stringWithFormat:@"[%@] %@", timestamp, message];
  _addToLogBufferRaw(logLine);
}

/**
 * Background thread to read from stderr pipe and add to log buffer
 */
static void* _logReaderThread(void *arg) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  char buffer[4096];
  NSMutableString *lineBuffer = [[NSMutableString alloc] init];
  
  while (logReaderRunning) {
    ssize_t bytesRead = read(stderrPipe[0], buffer, sizeof(buffer) - 1);
    if (bytesRead > 0) {
      buffer[bytesRead] = '\0';
      NSString *chunk = [NSString stringWithUTF8String:buffer];
      
      /* Also write to original stderr so we can still see output */
      if (originalStderr != -1) {
        write(originalStderr, buffer, bytesRead);
      }
      
      /* Split by newlines and add each line to buffer */
      [lineBuffer appendString:chunk];
      NSArray *lines = [lineBuffer componentsSeparatedByString:@"\n"];
      
      /* Process all complete lines (all but the last, which might be incomplete) */
      for (NSUInteger i = 0; i < [lines count] - 1; i++) {
        NSString *line = [lines objectAtIndex:i];
        if ([line length] > 0) {
          /* Add timestamp */
          NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
          [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
          NSString *timestamp = [formatter stringFromDate:[NSDate date]];
          [formatter release];
          NSString *logLine = [NSString stringWithFormat:@"[%@] %@", timestamp, line];
          _addToLogBufferRaw(logLine);
        }
      }
      
      /* Keep the last incomplete line in the buffer */
      [lineBuffer setString:[lines lastObject]];
    } else if (bytesRead < 0) {
      if (errno == EINTR) {
        continue; /* Interrupted, try again */
      }
      break; /* Error or EOF */
    } else {
      usleep(10000); /* 10ms sleep to avoid busy-wait */
    }
  }
  
  /* Process any remaining data in line buffer */
  if ([lineBuffer length] > 0) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    [formatter release];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@", timestamp, lineBuffer];
    _addToLogBufferRaw(logLine);
  }
  
  [lineBuffer release];
  [pool release];
  return NULL;
}

/**
 * Start capturing stderr to log buffer
 */
static void _startStderrCapture(void) {
  if (originalStderr != -1) {
    return; /* Already capturing */
  }
  
  /* Create a pipe for stderr */
  if (pipe(stderrPipe) != 0) {
    NSLog(@"UITesting: Failed to create pipe for stderr capture");
    return;
  }
  
  /* Duplicate the original stderr */
  originalStderr = dup(STDERR_FILENO);
  if (originalStderr == -1) {
    NSLog(@"UITesting: Failed to duplicate stderr");
    close(stderrPipe[0]);
    close(stderrPipe[1]);
    return;
  }
  
  /* Redirect stderr to the pipe */
  if (dup2(stderrPipe[1], STDERR_FILENO) == -1) {
    NSLog(@"UITesting: Failed to redirect stderr");
    close(originalStderr);
    close(stderrPipe[0]);
    close(stderrPipe[1]);
    originalStderr = -1;
    return;
  }
  
  /* Make stderr unbuffered so we get output immediately */
  setbuf(stderr, NULL);
  
  /* Start reader thread */
  logReaderRunning = YES;
  if (pthread_create(&logReaderThread, NULL, _logReaderThread, NULL) != 0) {
    NSLog(@"UITesting: Failed to create log reader thread");
    logReaderRunning = NO;
    /* Restore stderr */
    dup2(originalStderr, STDERR_FILENO);
    close(originalStderr);
    close(stderrPipe[0]);
    close(stderrPipe[1]);
    originalStderr = -1;
    return;
  }
  
  NSLog(@"UITesting: stderr capture started");
}

/**
 * Get contents of log buffer as a string
 */
static NSString* _getLogBufferContents(void) {
  if (!recentLogMessages) {
    return @"(no log messages captured)";
  }
  
  [logBufferLock lock];
  NSString *result;
  @try {
    result = [[recentLogMessages componentsJoinedByString:@"\n"] retain];
  } @finally {
    [logBufferLock unlock];
  }
  return [result autorelease];
}

/**
 * Custom NSLog replacement that also captures to buffer
 */
#define UITestLog(format, ...) do { \
  NSString *_msg = [NSString stringWithFormat:format, ##__VA_ARGS__]; \
  NSLog(@"%@", _msg); \
  _addToLogBuffer(_msg); \
} while(0)

/* Forward declarations */
static NSMutableDictionary* _buildViewDict(NSView *view);
static NSMutableDictionary* _buildWindowDict(NSWindow *window);
static NSView* _findViewWithText(NSView *view, NSString *text);
static NSWindow* _findWindowWithTitle(NSString *title);

/**
 * Public function to enable/disable UI testing
 */
void WorkspaceUITestingSetEnabled(BOOL enabled)
{
  uiTestingEnabled = enabled;
  if (enabled) {
    /* Initialize log buffer */
    if (!recentLogMessages) {
      recentLogMessages = [[NSMutableArray alloc] initWithCapacity:LOG_BUFFER_SIZE];
      logBufferLock = [[NSLock alloc] init];
    }
    
    /* Start capturing stderr */
    _startStderrCapture();
    
    UITestLog(@"Workspace: UI Testing mode enabled (WorkspaceUITesting protocol)");
    if (!activeHighlightOverlays) {
      activeHighlightOverlays = [[NSMutableArray alloc] init];
    }
  }
}

/**
 * Helper: Check if UI testing is enabled
 */
static inline BOOL isUITestingEnabled(void)
{
  return uiTestingEnabled;
}

/**
 * Helper: Find a window by title
 */
static NSWindow* _findWindowWithTitle(NSString *title)
{
  NSArray *windows = [[NSApplication sharedApplication] windows];
  for (NSWindow *window in windows) {
    if ([[window title] isEqualToString:title] ||
        [[window title] containsString:title]) {
      return window;
    }
  }
  return nil;
}

/**
 * Helper: Find a view containing specific text
 */
static NSView* _findViewWithText(NSView *view, NSString *text)
{
  /* Check if this view contains the text */
  NSString *viewText = nil;
  
  if ([view respondsToSelector:@selector(stringValue)]) {
    viewText = [view stringValue];
  } else if ([view respondsToSelector:@selector(title)]) {
    viewText = [view title];
  } else if ([view respondsToSelector:@selector(string)]) {
    viewText = [view string];
  } else if ([view respondsToSelector:@selector(attributedStringValue)]) {
    viewText = [[view attributedStringValue] string];
  }
  
  if (viewText && [viewText containsString:text]) {
    return view;
  }
  
  /* Recursively search subviews */
  for (NSView *subview in [view subviews]) {
    NSView *found = _findViewWithText(subview, text);
    if (found) {
      return found;
    }
  }
  
  return nil;
}

/**
 * Recursively build a dictionary representation of a view and its children
 */
static NSMutableDictionary* _buildViewDict(NSView *view)
{
  NSMutableDictionary *viewDict = [NSMutableDictionary dictionary];
  NSString *className = NSStringFromClass([view class]);
  
  [viewDict setObject:className forKey:@"class"];
  
  /* Visibility state */
  [viewDict setObject:([view isHidden] ? @"hidden" : @"visible") 
              forKey:@"visibility"];
  
  /* Enabled state (for controls) */
  if ([view respondsToSelector:@selector(isEnabled)]) {
    BOOL isEnabled = [view isEnabled];
    [viewDict setObject:(isEnabled ? @"enabled" : @"disabled") 
                forKey:@"state"];
  }
  
  /* Checked state (for buttons, checkboxes) */
  if ([view respondsToSelector:@selector(state)]) {
    NSInteger buttonState = [view state];
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
    [viewDict setObject:stateStr forKey:@"checkState"];
  }
  
  /* Text content - try various properties */
  NSString *textContent = nil;
  
  if ([view respondsToSelector:@selector(stringValue)]) {
    NSString *value = [view stringValue];
    if (value && [value length] > 0) {
      textContent = value;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(title)]) {
    NSString *title = [view title];
    if (title && [title length] > 0) {
      textContent = title;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(string)]) {
    NSString *string = [view string];
    if (string && [string length] > 0) {
      textContent = string;
    }
  }
  
  if (!textContent && [view respondsToSelector:@selector(attributedStringValue)]) {
    NSAttributedString *attrStr = [view attributedStringValue];
    if (attrStr && [attrStr length] > 0) {
      textContent = [attrStr string];
    }
  }
  
  if (textContent) {
    [viewDict setObject:textContent forKey:@"text"];
  }
  
  /* Frame/bounds information */
  NSRect frame = [view frame];
  NSDictionary *frameDic = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithDouble:frame.origin.x], @"x",
    [NSNumber numberWithDouble:frame.origin.y], @"y",
    [NSNumber numberWithDouble:frame.size.width], @"width",
    [NSNumber numberWithDouble:frame.size.height], @"height",
    nil];
  [viewDict setObject:frameDic forKey:@"frame"];
  
  /* Recursively process child views */
  NSArray *subviews = [view subviews];
  if ([subviews count] > 0) {
    NSMutableArray *childrenArray = [NSMutableArray array];
    for (NSView *subview in subviews) {
      [childrenArray addObject:_buildViewDict(subview)];
    }
    [viewDict setObject:childrenArray forKey:@"children"];
  }
  
  return viewDict;
}

/**
 * Recursively build a dictionary representation of a window
 */
static NSMutableDictionary* _buildWindowDict(NSWindow *window)
{
  NSMutableDictionary *windowDict = [NSMutableDictionary dictionary];
  
  [windowDict setObject:[window title] forKey:@"title"];
  [windowDict setObject:NSStringFromClass([window class]) forKey:@"class"];
  [windowDict setObject:([window isVisible] ? @"visible" : @"hidden") 
                forKey:@"visibility"];
  [windowDict setObject:([window isKeyWindow] ? @"yes" : @"no") 
                forKey:@"isKeyWindow"];
  
  /* Window frame */
  NSRect windowFrame = [window frame];
  NSDictionary *frameDic = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithDouble:windowFrame.origin.x], @"x",
    [NSNumber numberWithDouble:windowFrame.origin.y], @"y",
    [NSNumber numberWithDouble:windowFrame.size.width], @"width",
    [NSNumber numberWithDouble:windowFrame.size.height], @"height",
    nil];
  [windowDict setObject:frameDic forKey:@"frame"];
  
  /* Content view hierarchy */
  NSView *contentView = [window contentView];
  if (contentView) {
    [windowDict setObject:_buildViewDict(contentView) forKey:@"contentView"];
  }
  
  return windowDict;
}

/**
 * Helper class to take delayed failure screenshots
 */
@interface _UITestScreenshotHelper : NSObject
{
  NSString *_windowTitle;
  NSString *_elementText;
}
- (id)initWithWindow:(NSString *)window element:(NSString *)element;
- (void)takeScreenshot;
@end

@implementation _UITestScreenshotHelper
- (id)initWithWindow:(NSString *)window element:(NSString *)element {
  self = [super init];
  if (self) {
    _windowTitle = [window copy];
    _elementText = [element copy];
  }
  return self;
}

- (void)dealloc {
  [_windowTitle release];
  [_elementText release];
  [super dealloc];
}

- (void)takeScreenshot {
  @try {
    /* Build directory name with timestamp */
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd-HHmmss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    [formatter release];
    
    /* Create sanitized names from window/element names */
    NSString *sanitizedWindow = [[_windowTitle componentsSeparatedByCharactersInSet:
      [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    NSString *sanitizedElement = [[_elementText componentsSeparatedByCharactersInSet:
      [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"_"];
    
    /* Create directory name */
    NSString *dirName = [NSString stringWithFormat:@"TestFailure-%@-%@-%@",
      sanitizedWindow, sanitizedElement, timestamp];
    
    /* Get Desktop path */
    NSArray *desktopPaths = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
    NSString *desktopPath = [desktopPaths count] > 0 ? [desktopPaths objectAtIndex:0] : @"~";
    desktopPath = [desktopPath stringByExpandingTildeInPath];
    
    /* Create the failure directory */
    NSString *failureDir = [desktopPath stringByAppendingPathComponent:dirName];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    
    if (![fm createDirectoryAtPath:failureDir 
       withIntermediateDirectories:YES 
                        attributes:nil 
                             error:&error]) {
      NSLog(@"UITesting: Failed to create directory %@: %@", failureDir, [error localizedDescription]);
      [self release];
      return;
    }
    
    /* Save log file with last 100 lines */
    NSString *logPath = [failureDir stringByAppendingPathComponent:@"workspace.log"];
    NSString *logContents = _getLogBufferContents();
    
    /* Add header to log file */
    NSString *logHeader = [NSString stringWithFormat:
      @"=== Workspace UI Test Failure Log ===\n"
      @"Timestamp: %@\n"
      @"Window: %@\n"
      @"Element: %@\n"
      @"=== Last %d log messages ===\n\n",
      timestamp, _windowTitle, _elementText, LOG_BUFFER_SIZE];
    NSString *fullLog = [logHeader stringByAppendingString:logContents];
    
    if (![fullLog writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
      NSLog(@"UITesting: Failed to write log file %@: %@", logPath, [error localizedDescription]);
    } else {
      NSLog(@"UITesting: Log saved to %@", logPath);
    }
    
    /* Take screenshot */
    NSString *screenshotPath = [failureDir stringByAppendingPathComponent:@"screenshot.png"];
    NSString *screenshotApp = @"/System/Applications/Screenshot.app/Screenshot";
    
    /* Check if Screenshot app exists */
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:screenshotApp]) {
      NSLog(@"UITesting: Screenshot app not found at %@", screenshotApp);
      [self release];
      return;
    }
    
    /* Use NSTask to run screenshot */
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:screenshotApp];
    [task setArguments:[NSArray arrayWithObjects:@"-s", @"-o", screenshotPath, nil]];
    
    /* Silence output */
    [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    
    [task launch];
    /* Don't wait - let it run in background */
    
    NSLog(@"UITesting: Failure artifacts saved to %@", failureDir);
    [task release];
    
  } @catch (NSException *e) {
    NSLog(@"UITesting: Failed to save failure artifacts: %@", [e reason]);
  }
  
  /* Release self - we were retained for the delayed call */
  [self release];
}
@end

/**
 * Category to add UI testing support to Workspace
 */
@interface Workspace (UITesting) <WorkspaceUITesting>
@end

@implementation Workspace (UITesting)

/**
 * Returns the current window and view hierarchy as a JSON string
 * Only available if UI testing is enabled via -d/--debug flag
 */
- (NSString *)currentWindowHierarchyAsJSON
{
  if (!isUITestingEnabled()) {
    return @"{ \"error\": \"UI Testing disabled. Start Workspace with -d or --debug flag\" }";
  }
  
  NSMutableArray *windowsArray = [NSMutableArray array];
  
  /* Get windows from the application */
  @try {
    NSArray *windows = [[NSApplication sharedApplication] windows];
    
    for (NSWindow *window in windows) {
      NSMutableDictionary *windowDict = _buildWindowDict(window);
      [windowsArray addObject:windowDict];
    }
  } @catch (NSException *e) {
    NSString *error = [NSString stringWithFormat:@"{ \"error\": \"Failed to access windows: %@\" }", [e reason]];
    return error;
  }
  
  /* Build final dictionary */
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  [result setObject:windowsArray forKey:@"windows"];
  [result setObject:@"Workspace" forKey:@"application"];
  [result setObject:@YES forKey:@"uiTestingEnabled"];
  
  /* Convert to JSON string */
  @try {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) {
      return [NSString stringWithFormat:@"{ \"error\": \"JSON serialization failed: %@\" }", [error localizedDescription]];
    }
    
    NSString *jsonString = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
    return jsonString ?: @"{ \"error\": \"Failed to convert JSON data to string\" }";
  } @catch (NSException *e) {
    return [NSString stringWithFormat:@"{ \"error\": \"Exception: %@\" }", [e reason]];
  }
}

/**
 * Returns all window titles currently visible
 * Only available if UI testing is enabled via -d/--debug flag
 */
- (NSArray *)allWindowTitles
{
  if (!isUITestingEnabled()) {
    return @[];
  }
  
  @try {
    NSArray *windows = [[NSApplication sharedApplication] windows];
    return [windows valueForKey:@"title"];
  } @catch (NSException *e) {
    return @[];
  }
}

/**
 * Click at screen coordinates
 */
- (NSDictionary *)clickAtX:(CGFloat)x y:(CGFloat)y
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    /* Find the window at this coordinate */
    NSArray *windows = [[NSApplication sharedApplication] windows];
    
    for (NSWindow *window in windows) {
      if (![window isVisible]) continue;
      
      NSRect windowFrame = [window frame];
      
      /* Check if coordinate is within window bounds */
      if (x >= windowFrame.origin.x && 
          x <= (windowFrame.origin.x + windowFrame.size.width) &&
          y >= windowFrame.origin.y && 
          y <= (windowFrame.origin.y + windowFrame.size.height)) {
        
        /* Convert to window-local coordinates */
        NSPoint windowPoint = NSMakePoint(x - windowFrame.origin.x, 
                                          y - windowFrame.origin.y);
        
        /* Convert to content view coordinates */
        NSView *contentView = [window contentView];
        NSPoint viewPoint = [contentView convertPoint:windowPoint fromView:nil];
        
        /* Find the view at this point */
        NSView *hitView = [contentView hitTest:viewPoint];
        
        if (hitView) {
          NSString *className = NSStringFromClass([hitView class]);
          
          /* Perform click action based on view type */
          if ([hitView respondsToSelector:@selector(performClick:)]) {
            [hitView performSelector:@selector(performClick:) withObject:nil];
            return @{
              @"success": @YES,
              @"element": className,
              @"action": @"clicked",
              @"window": [window title] ?: @"Unknown"
            };
          } else if ([hitView respondsToSelector:@selector(mouseDown:)]) {
            /* Simulate mouse down/up events */
            NSEvent *mouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                                    location:windowPoint
                                               modifierFlags:0
                                                   timestamp:[[NSProcessInfo processInfo] systemUptime]
                                                windowNumber:[window windowNumber]
                                                     context:nil
                                                 eventNumber:0
                                                  clickCount:1
                                                    pressure:1.0];
            
            NSEvent *mouseUp = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
                                                  location:windowPoint
                                             modifierFlags:0
                                                 timestamp:[[NSProcessInfo processInfo] systemUptime]
                                              windowNumber:[window windowNumber]
                                                   context:nil
                                               eventNumber:0
                                                clickCount:1
                                                  pressure:0.0];
            
            [hitView mouseDown:mouseDown];
            [hitView mouseUp:mouseUp];
            
            return @{
              @"success": @YES,
              @"element": className,
              @"action": @"mouseDown/mouseUp",
              @"window": [window title] ?: @"Unknown"
            };
          }
          
          return @{
            @"success": @NO,
            @"element": className,
            @"error": @"Element not clickable"
          };
        }
      }
    }
    
    return @{@"success": @NO, @"error": @"No element found at coordinates"};
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Open and click a menu item by path
 */
- (NSDictionary *)openMenu:(NSString *)menuPath
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    /* Parse menu path like "Info > About" or "File > New Browser" */
    NSArray *components = [menuPath componentsSeparatedByString:@" > "];
    if ([components count] == 0) {
      components = [menuPath componentsSeparatedByString:@">"];
    }
    
    if ([components count] == 0) {
      return @{@"success": @NO, @"error": @"Invalid menu path"};
    }
    
    /* Get the main menu */
    NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
    if (!mainMenu) {
      return @{@"success": @NO, @"error": @"No main menu found"};
    }
    
    /* Navigate through menu hierarchy */
    NSMenu *currentMenu = mainMenu;
    NSMenuItem *targetItem = nil;
    
    for (NSString *component in components) {
      NSString *menuName = [component stringByTrimmingCharactersInSet:
                            [NSCharacterSet whitespaceCharacterSet]];
      
      targetItem = nil;
      
      /* Find the menu item matching this component */
      for (NSMenuItem *item in [currentMenu itemArray]) {
        if ([[item title] isEqualToString:menuName] ||
            [[item title] containsString:menuName]) {
          targetItem = item;
          break;
        }
      }
      
      if (!targetItem) {
        return @{@"success": @NO, @"error": [NSString stringWithFormat:@"Menu item not found: %@", menuName]};
      }
      
      /* If this item has a submenu, navigate into it */
      if ([targetItem hasSubmenu]) {
        currentMenu = [targetItem submenu];
      }
    }
    
    if (targetItem && ![targetItem hasSubmenu]) {
      /* Perform the menu action */
      if ([targetItem isEnabled]) {
        [[NSApplication sharedApplication] sendAction:[targetItem action]
                                                   to:[targetItem target]
                                                 from:targetItem];
        
        return @{
          @"success": @YES,
          @"menuItem": [targetItem title],
          @"action": @"executed"
        };
      } else {
        return @{@"success": @NO, @"error": @"Menu item is disabled"};
      }
    }
    
    return @{@"success": @NO, @"error": @"No executable menu item found"};
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Send a keyboard shortcut
 */
- (NSDictionary *)sendShortcut:(NSString *)shortcut
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    /* Parse shortcut string like "Cmd+i", "Cmd+Shift+n" */
    NSArray *parts = [shortcut componentsSeparatedByString:@"+"];
    if ([parts count] == 0) {
      return @{@"success": @NO, @"error": @"Invalid shortcut format"};
    }
    
    NSEventModifierFlags modifiers = 0;
    NSString *keyChar = nil;
    
    for (NSString *part in parts) {
      NSString *partLower = [part lowercaseString];
      
      if ([partLower isEqualToString:@"cmd"] || [partLower isEqualToString:@"command"]) {
        modifiers |= NSEventModifierFlagCommand;
      } else if ([partLower isEqualToString:@"shift"]) {
        modifiers |= NSEventModifierFlagShift;
      } else if ([partLower isEqualToString:@"alt"] || [partLower isEqualToString:@"option"]) {
        modifiers |= NSEventModifierFlagOption;
      } else if ([partLower isEqualToString:@"ctrl"] || [partLower isEqualToString:@"control"]) {
        modifiers |= NSEventModifierFlagControl;
      } else {
        keyChar = partLower;
      }
    }
    
    if (!keyChar || [keyChar length] == 0) {
      return @{@"success": @NO, @"error": @"No key specified in shortcut"};
    }
    
    /* Find menu item with this shortcut and execute it */
    NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
    
    /* Search all menus for matching shortcut */
    for (NSMenuItem *menuItem in [mainMenu itemArray]) {
      if ([menuItem hasSubmenu]) {
        for (NSMenuItem *subItem in [[menuItem submenu] itemArray]) {
          NSString *keyEquiv = [[subItem keyEquivalent] lowercaseString];
          NSEventModifierFlags itemMods = [subItem keyEquivalentModifierMask];
          
          if ([keyEquiv isEqualToString:keyChar] && itemMods == modifiers) {
            if ([subItem isEnabled]) {
              [[NSApplication sharedApplication] sendAction:[subItem action]
                                                         to:[subItem target]
                                                       from:subItem];
              
              return @{
                @"success": @YES,
                @"shortcut": shortcut,
                @"menuItem": [subItem title],
                @"action": @"executed"
              };
            }
          }
        }
      }
    }
    
    /* If no menu item found, try sending key event directly */
    NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
    if (keyWindow) {
      NSEvent *keyEvent = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                           location:NSZeroPoint
                                      modifierFlags:modifiers
                                          timestamp:[[NSProcessInfo processInfo] systemUptime]
                                       windowNumber:[keyWindow windowNumber]
                                            context:nil
                                         characters:keyChar
                        charactersIgnoringModifiers:keyChar
                                          isARepeat:NO
                                            keyCode:0];
      
      [[NSApplication sharedApplication] sendEvent:keyEvent];
      
      return @{
        @"success": @YES,
        @"shortcut": shortcut,
        @"action": @"keyEventSent"
      };
    }
    
    return @{@"success": @NO, @"error": @"No matching shortcut found"};
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Highlight a UI element with a red overlay to indicate failure
 */
- (NSDictionary *)highlightFailedElementInWindow:(NSString *)windowTitle 
                                        withText:(NSString *)elementText
                                        duration:(CGFloat)duration
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    /* Find the window */
    NSWindow *window = _findWindowWithTitle(windowTitle);
    if (!window) {
      return @{@"success": @NO, @"error": [NSString stringWithFormat:@"Window not found: %@", windowTitle]};
    }
    
    /* Find the element with the specified text */
    NSView *contentView = [window contentView];
    NSView *targetView = _findViewWithText(contentView, elementText);
    
    if (!targetView) {
      return @{@"success": @NO, @"error": [NSString stringWithFormat:@"Element with text not found: %@", elementText]};
    }
    
    /* Create a red overlay view */
    NSRect viewFrame = [targetView frame];
    NSRect overlayFrame = [targetView convertRect:viewFrame toView:contentView];
    
    /* Expand the overlay slightly for visibility */
    overlayFrame = NSInsetRect(overlayFrame, -3, -3);
    
    /* Create overlay and label */
    NSView *overlay = [[NSView alloc] initWithFrame:overlayFrame];
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(overlayFrame), 20)];
    [label setStringValue:@"TEST FAILED"];
    [label setBackgroundColor:[NSColor redColor]];
    [label setTextColor:[NSColor whiteColor]];
    [label setDrawsBackground:YES];
    [label setBezeled:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setAlignment:NSCenterTextAlignment];
    [label setFont:[NSFont boldSystemFontOfSize:14]];
    [overlay addSubview:label];
    [label release];
    [contentView addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    [overlay setNeedsDisplay:YES];
    [contentView setNeedsDisplay:YES];
    
    /* If duration > 0, schedule removal */
    if (duration > 0) {
      [overlay performSelector:@selector(removeFromSuperview)
                    withObject:nil
                    afterDelay:duration];
    }
    
    NSLog(@"UITesting: Highlighted '%@' in window '%@'", elementText, windowTitle);
    UITestLog(@"UITesting: Highlighted '%@' in window '%@' (legacy method)", elementText, windowTitle);
    
    /* Return simple success - avoid complex objects that may fail DO marshaling */
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithBool:YES], @"success",
            elementText, @"highlighted",
            nil];
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * NEW: Oneway void version that doesn't return a value (avoids DO crashes)
 */
- (oneway void)showFailureHighlightInWindow:(NSString *)windowTitle 
                                   withText:(NSString *)elementText
                                   duration:(CGFloat)duration
{
  if (!isUITestingEnabled()) {
    UITestLog(@"UITesting: UI Testing disabled");
    return;
  }
  
  @try {
    /* Find the window */
    NSWindow *window = _findWindowWithTitle(windowTitle);
    if (!window) {
      UITestLog(@"UITesting: Window not found: %@", windowTitle);
      return;
    }
    
    /* Find the element with the specified text */
    NSView *contentView = [window contentView];
    NSView *targetView = _findViewWithText(contentView, elementText);
    
    if (!targetView) {
      UITestLog(@"UITesting: Element not found: %@", elementText);
      return;
    }
    
    /* Create a red overlay view */
    NSRect viewFrame = [targetView frame];
    NSRect overlayFrame = [targetView convertRect:viewFrame toView:contentView];
    overlayFrame = NSInsetRect(overlayFrame, -3, -3);
    
    /* Create overlay and label */
    NSView *overlay = [[NSView alloc] initWithFrame:overlayFrame];
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, NSWidth(overlayFrame), 20)];
    [label setStringValue:@"TEST FAILED"];
    [label setBackgroundColor:[NSColor redColor]];
    [label setTextColor:[NSColor whiteColor]];
    [label setDrawsBackground:YES];
    [label setBezeled:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setAlignment:NSCenterTextAlignment];
    [label setFont:[NSFont boldSystemFontOfSize:14]];
    [overlay addSubview:label];
    [label release];
    [contentView addSubview:overlay positioned:NSWindowAbove relativeTo:nil];
    [overlay setNeedsDisplay:YES];
    [contentView setNeedsDisplay:YES];
    
    /* Store overlay for cleanup */
    if (activeHighlightOverlays) {
      [activeHighlightOverlays addObject:overlay];
    }
    
    /* If duration > 0, schedule removal */
    if (duration > 0) {
      [overlay performSelector:@selector(removeFromSuperview)
                    withObject:nil
                    afterDelay:duration];
    }
    
    UITestLog(@"UITesting: Highlighted '%@' in window '%@'", elementText, windowTitle);
    
    /* Take a failure screenshot after a brief delay to let the overlay render */
    _UITestScreenshotHelper *helper = [[_UITestScreenshotHelper alloc] 
      initWithWindow:windowTitle element:elementText];
    /* Retain helper during the delayed call - it will release itself in takeScreenshot */
    [helper retain];
    [helper performSelector:@selector(takeScreenshot) withObject:nil afterDelay:0.2];
    [helper release];
    
  } @catch (NSException *e) {
    UITestLog(@"UITesting: Error highlighting: %@", [e reason]);
  }
}

/**
 * NEW: Oneway void version to clear highlights (avoids DO crashes)
 */
- (oneway void)clearFailureHighlights
{
  if (!isUITestingEnabled()) {
    return;
  }
  
  @try {
    if (activeHighlightOverlays) {
      for (NSView *overlay in activeHighlightOverlays) {
        [overlay removeFromSuperview];
      }
      [activeHighlightOverlays removeAllObjects];
    }
    UITestLog(@"UITesting: Cleared all failure highlights");
  } @catch (NSException *e) {
    UITestLog(@"UITesting: Error clearing highlights: %@", [e reason]);
  }
}

/**
 * Clear all failure highlights from all windows
 */
- (NSDictionary *)clearAllHighlights
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    NSInteger count = [activeHighlightOverlays count];
    
    for (NSDictionary *info in activeHighlightOverlays) {
      NSView *overlay = [info objectForKey:@"overlay"];
      [overlay removeFromSuperview];
      [overlay release];
    }
    
    [activeHighlightOverlays removeAllObjects];
    
    return @{
      @"success": @YES,
      @"cleared": [NSNumber numberWithInteger:count]
    };
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Find a UI element by text content in a specific window
 */
- (NSDictionary *)findElementInWindow:(NSString *)windowTitle withText:(NSString *)text
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    NSWindow *window = _findWindowWithTitle(windowTitle);
    if (!window) {
      return @{@"found": @NO, @"error": @"Window not found"};
    }
    
    NSView *contentView = [window contentView];
    NSView *found = _findViewWithText(contentView, text);
    
    if (found) {
      NSRect frame = [found frame];
      return @{
        @"found": @YES,
        @"class": NSStringFromClass([found class]),
        @"frame": @{
          @"x": [NSNumber numberWithDouble:frame.origin.x],
          @"y": [NSNumber numberWithDouble:frame.origin.y],
          @"width": [NSNumber numberWithDouble:frame.size.width],
          @"height": [NSNumber numberWithDouble:frame.size.height]
        },
        @"text": text,
        @"window": [window title]
      };
    }
    
    return @{@"found": @NO, @"error": @"Element not found"};
    
  } @catch (NSException *e) {
    return @{@"found": @NO, @"error": [e reason]};
  }
}

/**
 * Wait for a window to appear with timeout
 */
- (NSDictionary *)waitForWindow:(NSString *)windowTitle timeout:(CGFloat)timeout
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    NSDate *startTime = [NSDate date];
    CGFloat waitTime = 0;
    
    while (waitTime < timeout) {
      NSWindow *window = _findWindowWithTitle(windowTitle);
      if (window && [window isVisible]) {
        return @{
          @"success": @YES,
          @"window": [window title],
          @"waitTime": [NSNumber numberWithDouble:waitTime]
        };
      }
      
      /* Run loop briefly to allow window to appear */
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
      waitTime = [[NSDate date] timeIntervalSinceDate:startTime];
    }
    
    return @{
      @"success": @NO,
      @"error": [NSString stringWithFormat:@"Window '%@' did not appear within %.1f seconds", windowTitle, timeout]
    };
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Close a window by title
 */
- (NSDictionary *)closeWindow:(NSString *)windowTitle
{
  if (!isUITestingEnabled()) {
    return @{@"success": @NO, @"error": @"UI Testing disabled"};
  }
  
  @try {
    NSWindow *window = _findWindowWithTitle(windowTitle);
    if (!window) {
      return @{@"success": @NO, @"error": @"Window not found"};
    }
    
    NSString *title = [window title];
    [window close];
    
    return @{
      @"success": @YES,
      @"closed": title
    };
    
  } @catch (NSException *e) {
    return @{@"success": @NO, @"error": [e reason]};
  }
}

/**
 * Get all menus and menu items with their enabled/disabled state
 * Returns a JSON string for distributed objects compatibility
 */
- (NSString *)allMenuItemsWithStateAsJSON
{
  if (!isUITestingEnabled()) {
    return @"{\"success\":false,\"error\":\"UI Testing disabled\"}";
  }
  
  NSLog(@"allMenuItemsWithStateAsJSON called");
  
  NS_DURING {
    NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
    if (!mainMenu) {
      NSLog(@"mainMenu is nil");
      return @"{\"success\":false,\"error\":\"Main menu not available\"}";
    }
    
    NSMutableArray *menusArray = [NSMutableArray array];
    NSArray *topItems = [mainMenu itemArray];
    NSLog(@"Found %lu top-level menu items", (unsigned long)[topItems count]);
    
    for (NSMenuItem *topItem in topItems) {
      NSMutableDictionary *menuDict = [NSMutableDictionary dictionary];
      NSString *title = [topItem title];
      if (!title) title = @"";
      [menuDict setObject:title forKey:@"title"];
      [menuDict setObject:[NSNumber numberWithBool:[topItem isEnabled]] forKey:@"enabled"];
      
      if ([topItem hasSubmenu]) {
        NSMenu *submenu = [topItem submenu];
        NSMutableArray *itemsArray = [NSMutableArray array];
        
        for (NSMenuItem *item in [submenu itemArray]) {
          if ([item isSeparatorItem]) {
            [itemsArray addObject:[NSDictionary dictionaryWithObject:@YES forKey:@"separator"]];
          } else {
            NSMutableDictionary *itemDict = [NSMutableDictionary dictionary];
            NSString *itemTitle = [item title];
            if (!itemTitle) itemTitle = @"";
            [itemDict setObject:itemTitle forKey:@"title"];
            [itemDict setObject:[NSNumber numberWithBool:[item isEnabled]] forKey:@"enabled"];
            [itemDict setObject:[NSNumber numberWithBool:[item hasSubmenu]] forKey:@"hasSubmenu"];
            
            /* Build shortcut string */
            NSString *keyEquiv = [item keyEquivalent];
            if (keyEquiv && [keyEquiv length] > 0) {
              NSUInteger mods = [item keyEquivalentModifierMask];
              NSMutableString *shortcut = [NSMutableString string];
              if (mods & NSControlKeyMask) [shortcut appendString:@"Ctrl+"];
              if (mods & NSAlternateKeyMask) [shortcut appendString:@"Alt+"];
              if (mods & NSShiftKeyMask) [shortcut appendString:@"Shift+"];
              if (mods & NSCommandKeyMask) [shortcut appendString:@"Cmd+"];
              [shortcut appendString:[keyEquiv uppercaseString]];
              [itemDict setObject:shortcut forKey:@"shortcut"];
            }
            
            /* Include action selector name for debugging */
            SEL action = [item action];
            if (action) {
              [itemDict setObject:NSStringFromSelector(action) forKey:@"action"];
            }
            
            [itemsArray addObject:itemDict];
          }
        }
        
        [menuDict setObject:itemsArray forKey:@"items"];
      }
      
      [menusArray addObject:menuDict];
    }
    
    NSLog(@"allMenuItemsWithStateAsJSON returning %lu menus", (unsigned long)[menusArray count]);
    
    /* Convert to JSON string */
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            @YES, @"success",
                            menusArray, @"menus",
                            nil];
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    if (error) {
      NSLog(@"JSON serialization error: %@", error);
      return @"{\"success\":false,\"error\":\"JSON serialization failed\"}";
    }
    
    NSString *jsonString = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
    return jsonString;
    
  } NS_HANDLER {
    NSLog(@"allMenuItemsWithStateAsJSON exception: %@", localException);
    return [NSString stringWithFormat:@"{\"success\":false,\"error\":\"%@\"}", 
            [localException reason] ?: @"Unknown error"];
  } NS_ENDHANDLER
  
  return @"{\"success\":false,\"error\":\"Unexpected end\"}";
}

/* Keep old method for compatibility, but delegate to JSON version */
- (bycopy NSDictionary *)allMenuItemsWithState
{
  NSString *json = [self allMenuItemsWithStateAsJSON];
  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  NSError *error = nil;
  NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error) {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @NO, @"success",
            @"JSON parse error", @"error",
            nil];
  }
  return dict;
}

@end
