/*
 * GSGlobalShortcutsManager.m
 *
 * Global shortcuts manager for GNUstep Workspace
 */

#import "GSGlobalShortcutsManager.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/XKBlib.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <stdarg.h>
#include <fcntl.h>
#include <time.h>
#include <errno.h>
#include <string.h>

static GSGlobalShortcutsManager *sharedManager = nil;

typedef struct {
    int keycode;
    unsigned int modifiers;
} KeyCombo;

// Parse a key combination string like "ctrl+shift+t"
static NSArray *parseKeyCombo(NSString *combo)
{
    NSArray *parts = [combo componentsSeparatedByString:@"+"];
    if ([parts count] < 1) return nil;
    
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *part in parts) {
        [result addObject:[part lowercaseString]];
    }
    return result;
}

// Convert a keysym name to its keysym value
static KeySym keysymFromName(NSString *name)
{
    if ([name length] == 1) {
        // Single character
        return XStringToKeysym([name UTF8String]);
    }
    return XStringToKeysym([name UTF8String]);
}

@implementation GSGlobalShortcutsManager

+ (GSGlobalShortcutsManager *)sharedManager
{
    if (!sharedManager) {
        sharedManager = [[GSGlobalShortcutsManager alloc] init];
    }
    return sharedManager;
}

- (id)init
{
    if ((self = [super init])) {
        shortcuts = nil;
        display = NULL;
        rootWindow = None;
        numlock_mask = 0;
        capslock_mask = 0;
        scrolllock_mask = 0;
        running = NO;
        verbose = NO;
        lastDefaultsModTime = 0;
        defaultsDomain = @"GlobalShortcuts";
        eventProcessingTimer = nil;
    }
    return self;
}

- (void)dealloc
{
    [self stop];
    [shortcuts release];
    [defaultsDomain release];
    [super dealloc];
}

- (BOOL)startWithVerbose:(BOOL)verboseLogging
{
    verbose = verboseLogging;
    
    if (![self setupX11]) {
        NSLog(@"GSGlobalShortcutsManager: Failed to setup X11");
        return NO;
    }
    
    if (![self loadShortcuts]) {
        NSLog(@"GSGlobalShortcutsManager: Failed to load shortcuts");
        [self stop];
        return NO;
    }
    
    if (![self grabKeys]) {
        NSLog(@"GSGlobalShortcutsManager: Failed to grab keys");
        [self stop];
        return NO;
    }
    
    if (![self setupEventProcessing]) {
        NSLog(@"GSGlobalShortcutsManager: Failed to setup event processing");
        [self stop];
        return NO;
    }
    
    running = YES;
    NSLog(@"GSGlobalShortcutsManager: Started successfully with %lu shortcuts",
        (unsigned long)[shortcuts count]);
    
    return YES;
}

- (void)stop
{
    if (running) {
        running = NO;
        
        if (eventProcessingTimer) {
            [eventProcessingTimer invalidate];
            DESTROY(eventProcessingTimer);
        }
        
        [self ungrabKeys];
        if (display) {
            XCloseDisplay(display);
            display = NULL;
        }
        NSLog(@"GSGlobalShortcutsManager: Stopped");
    }
}

- (BOOL)setupX11
{
    display = XOpenDisplay(NULL);
    if (!display) {
        NSLog(@"GSGlobalShortcutsManager: Could not open X11 display");
        return NO;
    }
    
    rootWindow = DefaultRootWindow(display);
    if (rootWindow == None) {
        NSLog(@"GSGlobalShortcutsManager: Could not get root window");
        XCloseDisplay(display);
        display = NULL;
        return NO;
    }
    
    // Determine modifier masks for lock keys
    XModifierKeymap *modmap = XGetModifierMapping(display);
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < modmap->max_keypermod; j++) {
            KeyCode keycode = modmap->modifiermap[i * modmap->max_keypermod + j];
            KeySym keysym = XKeycodeToKeysym(display, keycode, 0);
            
            if (keysym == XK_Num_Lock) {
                numlock_mask = 1 << i;
            } else if (keysym == XK_Caps_Lock) {
                capslock_mask = 1 << i;
            } else if (keysym == XK_Scroll_Lock) {
                scrolllock_mask = 1 << i;
            }
        }
    }
    XFreeModifiermap(modmap);
    
    XAllowEvents(display, AsyncBoth, CurrentTime);
    
    if (verbose) {
        NSLog(@"GSGlobalShortcutsManager: X11 setup complete");
        NSLog(@"  numlock_mask=0x%x, capslock_mask=0x%x, scrolllock_mask=0x%x",
            numlock_mask, capslock_mask, scrolllock_mask);
    }
    
    return YES;
}

- (BOOL)loadShortcuts
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
    
    if (shortcuts) {
        [defaults release];
        defaults = [[NSUserDefaults alloc] init];
        [defaults synchronize];
    }
    
    NSDictionary *config = [defaults persistentDomainForName:defaultsDomain];
    
    if (shortcuts && defaults != [NSUserDefaults standardUserDefaults]) {
        [defaults release];
    }
    
    if (!config) {
        NSLog(@"GSGlobalShortcutsManager: No configuration found");
        NSLog(@"  Create shortcuts using: defaults write %@ 'ctrl+shift+t' 'Terminal'", 
            defaultsDomain);
        [shortcuts release];
        shortcuts = [[NSDictionary alloc] init];
        lastDefaultsModTime = time(NULL);
        return YES;
    }
    
    [shortcuts release];
    shortcuts = [config retain];
    lastDefaultsModTime = time(NULL);
    
    NSLog(@"GSGlobalShortcutsManager: Loaded %lu shortcuts", 
        (unsigned long)[shortcuts count]);
    
    if (verbose) {
        NSEnumerator *enumerator = [shortcuts keyEnumerator];
        NSString *key;
        while ((key = [enumerator nextObject])) {
            NSLog(@"  %@ -> %@", key, [shortcuts objectForKey:key]);
        }
    }
    
    return YES;
}

- (BOOL)grabKeys
{
    int successCount = 0;
    int totalShortcuts = [shortcuts count];
    
    NSEnumerator *enumerator = [shortcuts keyEnumerator];
    NSString *keyCombo;
    
    while ((keyCombo = [enumerator nextObject])) {
        if ([self grabKeyCombo:keyCombo]) {
            successCount++;
        }
    }
    
    NSLog(@"GSGlobalShortcutsManager: Successfully grabbed %d of %d shortcuts",
        successCount, totalShortcuts);
    
    return successCount > 0;
}

- (void)ungrabKeys
{
    XUngrabKey(display, AnyKey, AnyModifier, rootWindow);
}

- (BOOL)grabKeyCombo:(NSString *)keyCombo
{
    NSArray *parts = parseKeyCombo(keyCombo);
    if (!parts || [parts count] < 1) return NO;
    
    unsigned int modifier = 0;
    NSString *keyString = nil;
    
    // Parse modifiers
    for (int i = 0; i < [parts count] - 1; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part isEqualToString:@"ctrl"]) {
            modifier |= ControlMask;
        } else if ([part isEqualToString:@"shift"]) {
            modifier |= ShiftMask;
        } else if ([part isEqualToString:@"alt"] || [part isEqualToString:@"mod1"]) {
            modifier |= Mod1Mask;
        } else if ([part isEqualToString:@"super"] || [part isEqualToString:@"mod4"]) {
            modifier |= Mod4Mask;
        }
    }
    
    keyString = [parts objectAtIndex:[parts count] - 1];
    KeySym keysym = keysymFromName(keyString);
    if (keysym == NoSymbol) {
        NSLog(@"GSGlobalShortcutsManager: Unknown key: %@", keyString);
        return NO;
    }
    
    KeyCode keycode = XKeysymToKeycode(display, keysym);
    if (keycode == 0) {
        NSLog(@"GSGlobalShortcutsManager: Could not map keysym to keycode: %@", keyString);
        return NO;
    }
    
    // Grab the key with all lock key variations
    unsigned int modifiers[] = {
        modifier,
        modifier | numlock_mask,
        modifier | capslock_mask,
        modifier | numlock_mask | capslock_mask,
        modifier | scrolllock_mask,
        modifier | numlock_mask | scrolllock_mask,
        modifier | capslock_mask | scrolllock_mask,
        modifier | numlock_mask | capslock_mask | scrolllock_mask
    };
    
    for (int i = 0; i < 8; i++) {
        XGrabKey(display, keycode, modifiers[i], rootWindow, True, GrabModeAsync, GrabModeAsync);
    }
    
    if (verbose) {
        NSLog(@"GSGlobalShortcutsManager: Grabbed key combo: %@", keyCombo);
    }
    
    return YES;
}

- (BOOL)matchesEvent:(XKeyEvent *)keyEvent withKeyCombo:(NSString *)keyCombo
{
    NSArray *parts = parseKeyCombo(keyCombo);
    if (!parts || [parts count] < 1) return NO;
    
    unsigned int modifier = 0;
    NSString *keyString = nil;
    
    for (int i = 0; i < [parts count] - 1; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part isEqualToString:@"ctrl"]) {
            modifier |= ControlMask;
        } else if ([part isEqualToString:@"shift"]) {
            modifier |= ShiftMask;
        } else if ([part isEqualToString:@"alt"] || [part isEqualToString:@"mod1"]) {
            modifier |= Mod1Mask;
        } else if ([part isEqualToString:@"super"] || [part isEqualToString:@"mod4"]) {
            modifier |= Mod4Mask;
        }
    }
    
    keyString = [parts objectAtIndex:[parts count] - 1];
    KeySym keysym = keysymFromName(keyString);
    if (keysym == NoSymbol) return NO;
    
    KeyCode keycode = XKeysymToKeycode(display, keysym);
    if (keycode == 0) return NO;
    
    // Check if keycode matches
    if (keyEvent->keycode != keycode) return NO;
    
    // Check if modifiers match (ignoring lock keys)
    unsigned int eventMods = keyEvent->state & ~(numlock_mask | capslock_mask | scrolllock_mask);
    if (eventMods != modifier) return NO;
    
    return YES;
}

- (BOOL)setupEventProcessing
{
    // Create a timer that periodically processes X11 events
    // This integrates with the NSApplication event loop
    eventProcessingTimer = [[NSTimer scheduledTimerWithTimeInterval:0.05
                                                             target:self
                                                           selector:@selector(processX11Events)
                                                           userInfo:nil
                                                            repeats:YES] retain];
    
    NSLog(@"GSGlobalShortcutsManager: Event processing timer started (50ms interval)");
    return YES;
}

- (void)processX11Events
{
    if (!display || !rootWindow) return;
    
    XEvent event;
    while (XPending(display) > 0) {
        XNextEvent(display, &event);
        
        if (event.type == KeyPress) {
            if (verbose) {
                NSLog(@"GSGlobalShortcutsManager: Key press: keycode=%d, state=0x%x",
                    event.xkey.keycode, event.xkey.state);
            }
            
            // Mask out lock keys
            event.xkey.state &= ~(numlock_mask | capslock_mask | scrolllock_mask);
            
            // Find matching shortcut
            NSEnumerator *enumerator = [shortcuts keyEnumerator];
            NSString *keyCombo;
            
            while ((keyCombo = [enumerator nextObject])) {
                if ([self matchesEvent:&event.xkey withKeyCombo:keyCombo]) {
                    NSString *command = [shortcuts objectForKey:keyCombo];
                    NSLog(@"GSGlobalShortcutsManager: Executing command for %@: %@",
                        keyCombo, command);
                    
                    if (![self runCommand:command]) {
                        NSLog(@"GSGlobalShortcutsManager: Warning: Failed to execute command: %@",
                            command);
                    }
                    break;
                }
            }
        }
    }
}

- (BOOL)runCommand:(NSString *)command
{
    if (!command || [command length] == 0) {
        NSLog(@"GSGlobalShortcutsManager: Warning: Empty command");
        return NO;
    }
    
    if ([command length] > 1024) {
        NSLog(@"GSGlobalShortcutsManager: Warning: Command too long (>1024 chars): %@", command);
        return NO;
    }
    
    NSArray *components = [command componentsSeparatedByString:@" "];
    if ([components count] == 0) {
        NSLog(@"GSGlobalShortcutsManager: Warning: No command components");
        return NO;
    }
    
    NSString *executable = [components objectAtIndex:0];
    
    // Security check - reject commands with dangerous characters
    NSCharacterSet *dangerousChars = [NSCharacterSet characterSetWithCharactersInString:@"`$;|&<>"];
    if ([command rangeOfCharacterFromSet:dangerousChars].location != NSNotFound) {
        NSLog(@"GSGlobalShortcutsManager: Warning: Command contains potentially dangerous characters: %@",
            command);
    }
    
    NSString *fullPath = [self findExecutableInPath:executable];
    
    if (!fullPath) {
        NSLog(@"GSGlobalShortcutsManager: Warning: executable '%@' not found in PATH", executable);
        return NO;
    }
    
    if (verbose) {
        NSLog(@"GSGlobalShortcutsManager: Found executable: %@ -> %@", executable, fullPath);
    }
    
    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        setsid();
        
        // Close file descriptors
        close(STDIN_FILENO);
        close(STDOUT_FILENO);
        close(STDERR_FILENO);
        
        int devnull = open("/dev/null", O_RDWR);
        if (devnull >= 0) {
            dup2(devnull, STDIN_FILENO);
            dup2(devnull, STDOUT_FILENO);
            dup2(devnull, STDERR_FILENO);
            if (devnull > STDERR_FILENO) {
                close(devnull);
            }
        }
        
        pid_t grandchild = fork();
        if (grandchild == 0) {
            // Grandchild process - execute command
            const char *shell = getenv("SHELL");
            if (!shell) shell = "/bin/sh";
            
            execl(shell, shell, "-c", [command UTF8String], (char *)NULL);
            _exit(127);
        } else if (grandchild > 0) {
            _exit(0);
        } else {
            _exit(1);
        }
    } else if (pid > 0) {
        // Parent process - wait for child to exit
        int status;
        while (waitpid(pid, &status, 0) < 0) {
            if (errno == EINTR) {
                continue;
            } else if (errno == ECHILD) {
                // Process already exited
                return YES;
            } else {
                NSLog(@"GSGlobalShortcutsManager: Warning: waitpid failed for command: %@ (errno=%d)",
                    command, errno);
                return NO;
            }
        }
        
        if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
            NSLog(@"GSGlobalShortcutsManager: Warning: child process exited with status %d for command: %@",
                WEXITSTATUS(status), command);
            return NO;
        }
        
        return YES;
    } else {
        NSLog(@"GSGlobalShortcutsManager: Error: failed to fork process for command: %@", command);
        return NO;
    }
}

- (NSString *)findExecutableInPath:(NSString *)command
{
    // If command contains a slash, treat it as an absolute or relative path
    if ([command containsString:@"/"]) {
        struct stat statbuf;
        const char *cPath = [command UTF8String];
        if (stat(cPath, &statbuf) == 0 && (statbuf.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH))) {
            return command;
        }
        return nil;
    }
    
    // Search in PATH
    NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
    if (!pathEnv) {
        pathEnv = @"/usr/local/bin:/usr/bin:/bin";
    }
    
    NSArray *pathComponents = [pathEnv componentsSeparatedByString:@":"];
    NSEnumerator *enumerator = [pathComponents objectEnumerator];
    NSString *pathDir;
    
    while ((pathDir = [enumerator nextObject])) {
        if ([pathDir length] == 0) continue;
        
        NSString *fullPath = [pathDir stringByAppendingPathComponent:command];
        struct stat statbuf;
        const char *cPath = [fullPath UTF8String];
        
        if (stat(cPath, &statbuf) == 0 && (statbuf.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH))) {
            return fullPath;
        }
    }
    
    return nil;
}

@end
