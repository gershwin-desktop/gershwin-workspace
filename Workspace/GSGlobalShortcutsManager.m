/*
 * GSGlobalShortcutsManager.m
 *
 * Global shortcuts manager for GNUstep Workspace
 */

#import "GSGlobalShortcutsManager.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSAlert.h>
#import <dispatch/dispatch.h>
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

// Return YES if the given key combo represents Alt (or Mod1) + Space
static BOOL isAltSpaceCombo(NSString *keyCombo)
{
    if (!keyCombo || [keyCombo length] == 0) return NO;
    NSArray *parts = parseKeyCombo(keyCombo);
    if (!parts || [parts count] < 1) return NO;

    NSString *keyStr = [[parts lastObject] lowercaseString];
    // Accept "space" as the key name
    if (![keyStr isEqualToString:@"space"] && ![keyStr isEqualToString:@" "]) return NO;

    // Check for alt or mod1 in the modifier list
    for (NSUInteger i = 0; i < [parts count] - 1; i++) {
        NSString *p = [parts objectAtIndex:i];
        if ([p isEqualToString:@"alt"] || [p isEqualToString:@"mod1"]) {
            return YES;
        }
    }
    return NO;
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
        
        // Register for distributed notifications for cross-application communication
        [[NSDistributedNotificationCenter defaultCenter] 
            addObserver:self
               selector:@selector(globalShortcutsConfigurationChanged:)
                   name:@"GSGlobalShortcutsConfigurationChanged"
                 object:@"GlobalShortcuts"];
        
        // Register for temporary disable/enable notifications
        [[NSDistributedNotificationCenter defaultCenter] 
            addObserver:self
               selector:@selector(temporarilyDisableAllShortcuts:)
                   name:@"GSGlobalShortcutsTemporaryDisable"
                 object:@"GlobalShortcuts"];
        
        [[NSDistributedNotificationCenter defaultCenter] 
            addObserver:self
               selector:@selector(reEnableAllShortcuts:)
                   name:@"GSGlobalShortcutsReEnable"
                 object:@"GlobalShortcuts"];
        
        NSLog(@"GSGlobalShortcutsManager: Registered for distributed GlobalShortcuts notifications");
    }
    return self;
}

- (void)dealloc
{
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
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
            KeySym keysym = XkbKeycodeToKeysym(display, keycode, 0, 0);
            
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
    // Preserve any existing Alt-Space shortcut so it survives a reload
    NSString *protectedKey = nil;
    NSDictionary *protectedShortcut = nil;
    if (shortcuts && [shortcuts count] > 0) {
        NSEnumerator *ke = [shortcuts keyEnumerator];
        NSString *k;
        while ((k = [ke nextObject])) {
            if (isAltSpaceCombo(k)) {
                protectedKey = [k retain];
                protectedShortcut = [[shortcuts objectForKey:k] retain];
                if (verbose) NSLog(@"GSGlobalShortcutsManager: Preserving existing Alt-Space shortcut during load: %@", k);
                break;
            }
        }
    }

    // Create a completely fresh NSUserDefaults instance to avoid caching issues
    NSUserDefaults *defaults = [[NSUserDefaults alloc] init];
    [defaults addSuiteNamed:NSGlobalDomain];
    [defaults synchronize];
    
    // Merge system and user GlobalShortcuts like the pref pane: system files are read first, then user overrides
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    NSArray *systemPaths = @[@"/System/Library/Preferences/GlobalShortcuts.plist",
                             @"/Library/Preferences/GlobalShortcuts.plist"];
    for (NSString *p in systemPaths) {
        NSDictionary *sys = [NSDictionary dictionaryWithContentsOfFile:p];
        if (sys && [sys count] > 0) {
            [merged addEntriesFromDictionary:sys];
        }
    }

    NSDictionary *userConfig = [defaults persistentDomainForName:defaultsDomain];
    if (userConfig && [userConfig count] > 0) {
        [merged addEntriesFromDictionary:userConfig];
    }

    if (!merged || [merged count] == 0) {
        NSLog(@"GSGlobalShortcutsManager: No configuration found");
        NSLog(@"  Create shortcuts using: defaults write %@ 'ctrl+shift+t' 'Terminal'", defaultsDomain);
        [shortcuts release];
        shortcuts = [[NSMutableDictionary alloc] init];

        // Restore protected Alt-Space if it existed
        if (protectedKey && protectedShortcut) {
            [shortcuts setObject:protectedShortcut forKey:protectedKey];
            if (verbose) NSLog(@"GSGlobalShortcutsManager: Restored protected Alt-Space shortcut: %@", protectedKey);
            [protectedKey release];
            [protectedShortcut release];
        }

        lastDefaultsModTime = time(NULL);
        [defaults release];
        return YES;
    }

    [shortcuts release];
    shortcuts = [[NSMutableDictionary alloc] init];
    
    // Convert old plist format (keyCombo -> command) to new internal format
    NSEnumerator *enumerator = [merged keyEnumerator];
    NSString *keyCombo;
    while ((keyCombo = [enumerator nextObject])) {
        NSString *command = [merged objectForKey:keyCombo];
        
        // Parse keyCombo to extract modifiers and key
        NSArray *parts = [keyCombo componentsSeparatedByString:@"+"];
        NSString *keyStr = [parts lastObject];
        NSMutableArray *modifierParts = [NSMutableArray array];
        for (NSUInteger i = 0; i < [parts count] - 1; i++) {
            [modifierParts addObject:[parts objectAtIndex:i]];
        }
        NSString *modifiersStr = [modifierParts componentsJoinedByString:@"+"];
        
        // Create shortcut dictionary in the new internal format
        NSDictionary *shortcut = @{
            @"command": command,
            @"modifiers": modifiersStr ?: @"",
            @"keyStr": keyStr ?: @""
        };
        [shortcuts setObject:shortcut forKey:keyCombo];
    }
    
    // Re-add protected Alt-Space if it existed and isn't in the newly loaded config
    if (protectedKey && protectedShortcut && ![shortcuts objectForKey:protectedKey]) {
        [shortcuts setObject:protectedShortcut forKey:protectedKey];
        if (verbose) NSLog(@"GSGlobalShortcutsManager: Restored protected Alt-Space shortcut: %@", protectedKey);
        [protectedKey release];
        [protectedShortcut release];
    }

    lastDefaultsModTime = time(NULL);
    
    NSLog(@"GSGlobalShortcutsManager: Loaded %lu shortcuts", 
        (unsigned long)[shortcuts count]);
    
    if (verbose) {
        NSEnumerator *enumerator = [shortcuts keyEnumerator];
        NSString *key;
        while ((key = [enumerator nextObject])) {
            NSDictionary *shortcut = [shortcuts objectForKey:key];
            NSString *command = [shortcut objectForKey:@"command"];
            NSLog(@"  %@ -> %@", key, command);
        }
    }
    
    [defaults release];
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
    // Ungrab keys individually so we can preserve protected shortcuts (e.g., Alt-Space)
    if (!shortcuts || [shortcuts count] == 0) return;

    NSEnumerator *enumerator = [shortcuts keyEnumerator];
    NSString *keyCombo;
    while ((keyCombo = [enumerator nextObject])) {
        if (isAltSpaceCombo(keyCombo)) {
            if (verbose) {
                NSLog(@"GSGlobalShortcutsManager: Preserving protected Alt-Space shortcut; not ungrabbing %@", keyCombo);
            }
            continue;
        }
        [self ungrabKeyCombo:keyCombo];
    }
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

- (void)ungrabKeyCombo:(NSString *)keyCombo
{
    // Never ungrab the Alt-Space global shortcut once it has been registered
    if (isAltSpaceCombo(keyCombo)) {
        if (verbose) {
            NSLog(@"GSGlobalShortcutsManager: Not ungrabbing protected Alt-Space shortcut: %@", keyCombo);
        }
        return;
    }

    NSArray *parts = parseKeyCombo(keyCombo);
    if (!parts || [parts count] < 1) {
        if (verbose) {
            NSLog(@"GSGlobalShortcutsManager: Invalid key combo format: %@", keyCombo);
        }
        return;
    }
    
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
        } else if ([part isEqualToString:@"mod2"]) {
            modifier |= Mod2Mask;
        } else if ([part isEqualToString:@"mod3"]) {
            modifier |= Mod3Mask;
        } else if ([part isEqualToString:@"mod4"]) {
            modifier |= Mod4Mask;
        } else if ([part isEqualToString:@"mod5"]) {
            modifier |= Mod5Mask;
        }
    }
    
    // Last part is the key
    if ([parts count] > 0) {
        keyString = [parts objectAtIndex:[parts count] - 1];
    }
    
    if (!keyString) {
        if (verbose) {
            NSLog(@"GSGlobalShortcutsManager: No key name found in: %@", keyCombo);
        }
        return;
    }
    
    KeySym keysym = keysymFromName(keyString);
    if (keysym == NoSymbol) {
        if (verbose) {
            NSLog(@"GSGlobalShortcutsManager: Unknown key name: %@", keyString);
        }
        return;
    }
    
    int keycode = XKeysymToKeycode(display, keysym);
    if (keycode == 0) {
        if (verbose) {
            NSLog(@"GSGlobalShortcutsManager: No keycode for keysym: %s", XKeysymToString(keysym));
        }
        return;
    }
    
    // Ungrab the key with all lock key variations
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
        XUngrabKey(display, keycode, modifiers[i], rootWindow);
    }
    
    if (verbose) {
        NSLog(@"GSGlobalShortcutsManager: Ungrabbed key combo: %@", keyCombo);
    }
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
                    NSDictionary *shortcutDict = [shortcuts objectForKey:keyCombo];
                    NSString *command = [shortcutDict objectForKey:@"command"];
                    NSLog(@"GSGlobalShortcutsManager: Executing command for %@: %@",
                        keyCombo, command);
                    
                    if (![self runCommand:command]) {
                        NSLog(@"GSGlobalShortcutsManager: Warning: Failed to execute command: %@",
                            command);
                        [self showCommandFailureAlert:command shortcut:keyCombo];
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
    
    NSLog(@"GSGlobalShortcutsManager: Attempting to execute command: %@", command);
    
    pid_t pid = fork();
    if (pid == 0) {
        // Child process
        NSLog(@"GSGlobalShortcutsManager: Child process created for command: %@", command);
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
            
            NSLog(@"GSGlobalShortcutsManager: Grandchild executing: %s -c '%@'", shell, command);
            
            execl(shell, shell, "-c", [command UTF8String], (char *)NULL);
            NSLog(@"GSGlobalShortcutsManager: ERROR: execl failed for command: %@", command);
            _exit(127);
        } else if (grandchild > 0) {
            NSLog(@"GSGlobalShortcutsManager: Grandchild process %d started for command: %@", grandchild, command);
            _exit(0);
        } else {
            NSLog(@"GSGlobalShortcutsManager: ERROR: Failed to create grandchild for command: %@", command);
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
        
        NSLog(@"GSGlobalShortcutsManager: Command executed successfully: %@", command);
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

- (void)globalShortcutsConfigurationChanged:(NSNotification *)notification
{
    NSLog(@"GSGlobalShortcutsManager: Received GlobalShortcuts configuration changed notification");
    
    if (running) {
        NSLog(@"GSGlobalShortcutsManager: Manager is running, processing new shortcuts data");
        
        // Extract shortcuts data directly from userInfo
        NSDictionary *userInfo = [notification userInfo];
        NSLog(@"GSGlobalShortcutsManager: Received userInfo: %@", userInfo);
        
        NSNumber *shortcutCount = [userInfo objectForKey:@"shortcutCount"];
        NSArray *shortcutsArray = [userInfo objectForKey:@"shortcuts"];
        
        NSLog(@"GSGlobalShortcutsManager: shortcutCount = %@, shortcutsArray = %@", shortcutCount, shortcutsArray);
        
        if (shortcutCount) {
            NSLog(@"GSGlobalShortcutsManager: New configuration has %@ shortcuts", shortcutCount);
        }
        
        if (shortcutsArray) {
            NSLog(@"GSGlobalShortcutsManager: Processing shortcuts data from IPC (no disk I/O needed)");
            [self processShortcutsData:shortcutsArray];
        } else {
            NSLog(@"GSGlobalShortcutsManager: No shortcuts data in notification, falling back to plist read");
            [self reloadShortcutsIfChanged];
        }
    } else {
        NSLog(@"GSGlobalShortcutsManager: Manager not running, ignoring notification");
    }
}

- (void)processShortcutsData:(NSArray *)shortcutsArray
{
    NSLog(@"GSGlobalShortcutsManager: Processing %lu shortcuts from IPC data", (unsigned long)[shortcutsArray count]);
    NSLog(@"GSGlobalShortcutsManager: Raw shortcuts array: %@", shortcutsArray);

    // Preserve any existing Alt-Space shortcut so it is not lost during reconfiguration
    NSString *protectedKey = nil;
    NSDictionary *protectedShortcut = nil;
    if (shortcuts && [shortcuts count] > 0) {
        NSEnumerator *ke = [shortcuts keyEnumerator];
        NSString *k;
        while ((k = [ke nextObject])) {
            if (isAltSpaceCombo(k)) {
                protectedKey = [k retain];
                protectedShortcut = [[shortcuts objectForKey:k] retain];
                if (verbose) NSLog(@"GSGlobalShortcutsManager: Found protected Alt-Space shortcut in current config: %@", k);
                break;
            }
        }
    }

    // Ungrab current keys first (we will skip actually ungrabbing Alt-Space in ungrabAllKeys)
    [self ungrabAllKeys];

    // Clear current shortcuts
    [shortcuts removeAllObjects];

    // Re-add the preserved Alt-Space shortcut if we found one
    if (protectedKey && protectedShortcut) {
        [shortcuts setObject:protectedShortcut forKey:protectedKey];
        if (verbose) NSLog(@"GSGlobalShortcutsManager: Preserved protected shortcut %@", protectedKey);
        [protectedKey release];
        [protectedShortcut release];
    }
    
    // Process the new shortcuts data
    NSLog(@"GSGlobalShortcutsManager: Starting to process shortcuts...");
    NSUInteger processedCount = 0;
    for (NSDictionary *shortcutDict in shortcutsArray) {
        processedCount++;
        NSLog(@"GSGlobalShortcutsManager: Processing shortcut %lu/%lu: %@", (unsigned long)processedCount, (unsigned long)[shortcutsArray count], shortcutDict);
        
        NSString *key = [shortcutDict objectForKey:@"key"];
        NSString *command = [shortcutDict objectForKey:@"command"];
        NSString *modifiersStr = [shortcutDict objectForKey:@"modifiers"];
        NSString *keyStr = [shortcutDict objectForKey:@"keyStr"];
        
        NSLog(@"GSGlobalShortcutsManager: Extracted - key: '%@', command: '%@', modifiers: '%@', keyStr: '%@'", 
              key, command, modifiersStr, keyStr);
        
        if (key && command && modifiersStr && keyStr) {
            NSDictionary *shortcut = @{
                @"command": command,
                @"modifiers": modifiersStr,
                @"keyStr": keyStr
            };
            [shortcuts setObject:shortcut forKey:key];
            NSLog(@"GSGlobalShortcutsManager: Successfully added shortcut %@ -> %@", key, command);
        } else {
            NSLog(@"GSGlobalShortcutsManager: ERROR - Skipping incomplete shortcut data: %@", shortcutDict);
            NSLog(@"GSGlobalShortcutsManager: key=%@, command=%@, modifiers=%@, keyStr=%@", key, command, modifiersStr, keyStr);
        }
    }
    NSLog(@"GSGlobalShortcutsManager: Finished processing shortcuts. Processed %lu shortcuts.", (unsigned long)processedCount);
    
    NSLog(@"GSGlobalShortcutsManager: Loaded %lu shortcuts from IPC data", (unsigned long)[shortcuts count]);
    
    // Debug: show what shortcuts we have before grabbing keys
    for (NSString *key in shortcuts) {
        NSDictionary *shortcut = [shortcuts objectForKey:key];
        NSLog(@"GSGlobalShortcutsManager: About to grab shortcut %@ (modifiers: %@, keyStr: %@) -> %@", 
              key, [shortcut objectForKey:@"modifiers"], [shortcut objectForKey:@"keyStr"], [shortcut objectForKey:@"command"]);
    }
    
    // Grab the new keys
    NSLog(@"GSGlobalShortcutsManager: Calling grabKeys to register new shortcuts...");
    [self grabKeys];
}

- (void)reloadShortcutsIfChanged
{
    NSLog(@"GSGlobalShortcutsManager: Checking if GlobalShortcuts configuration changed...");
    
    // Check if our GlobalShortcuts domain has changed
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
    
    NSDictionary *newConfig = [defaults persistentDomainForName:defaultsDomain];
    
    NSLog(@"GSGlobalShortcutsManager: Current shortcuts count: %lu, New config count: %lu", 
        (unsigned long)(shortcuts ? [shortcuts count] : 0), 
        (unsigned long)(newConfig ? [newConfig count] : 0));
    
    // Compare with current shortcuts
    BOOL needsReload = NO;
    
    if (!shortcuts && !newConfig) {
        NSLog(@"GSGlobalShortcutsManager: Both old and new configs are nil, no change");
        return;
    }
    
    if (!shortcuts || !newConfig) {
        needsReload = YES;
        NSLog(@"GSGlobalShortcutsManager: Configuration changed (one is nil), reload needed");
    } else if ([shortcuts count] != [newConfig count]) {
        needsReload = YES;
        NSLog(@"GSGlobalShortcutsManager: Shortcut count changed (%lu -> %lu), reload needed", 
            (unsigned long)[shortcuts count], (unsigned long)[newConfig count]);
    } else {
        // Check if any key-command pairs have changed
        NSEnumerator *keyEnum = [shortcuts keyEnumerator];
        NSString *keyCombo;
        while ((keyCombo = [keyEnum nextObject])) {
            NSString *oldCommand = [shortcuts objectForKey:keyCombo];
            NSString *newCommand = [newConfig objectForKey:keyCombo];
            
            if (!newCommand || ![oldCommand isEqualToString:newCommand]) {
                needsReload = YES;
                NSLog(@"GSGlobalShortcutsManager: Command changed for %@: '%@' -> '%@'", 
                    keyCombo, oldCommand, newCommand ?: @"(removed)");
                break;
            }
        }
        
        // Check for new shortcuts that weren't in the old config
        if (!needsReload) {
            keyEnum = [newConfig keyEnumerator];
            while ((keyCombo = [keyEnum nextObject])) {
                if (![shortcuts objectForKey:keyCombo]) {
                    needsReload = YES;
                    NSLog(@"GSGlobalShortcutsManager: New shortcut added: %@", keyCombo);
                    break;
                }
            }
        }
        
        if (!needsReload) {
            NSLog(@"GSGlobalShortcutsManager: No changes detected in GlobalShortcuts");
        }
    }
    
    if (needsReload) {
        NSLog(@"GSGlobalShortcutsManager: Global shortcuts configuration changed, reloading");
        
        // Ungrab all current keys
        [self ungrabAllKeys];
        
        // Load new configuration
        if ([self loadShortcuts]) {
            // Grab new keys
            if ([self grabKeys]) {
                NSLog(@"GSGlobalShortcutsManager: Successfully reloaded %lu shortcuts", 
                    (unsigned long)[shortcuts count]);
            } else {
                NSLog(@"GSGlobalShortcutsManager: Warning: Failed to grab some keys after reload");
            }
        } else {
            NSLog(@"GSGlobalShortcutsManager: Error: Failed to reload shortcuts");
        }
    }
}

- (void)ungrabAllKeys
{
    if (!shortcuts || [shortcuts count] == 0) {
        return;
    }

    NSEnumerator *enumerator = [shortcuts keyEnumerator];
    NSString *keyCombo;

    while ((keyCombo = [enumerator nextObject])) {
        if (isAltSpaceCombo(keyCombo)) {
            if (verbose) {
                NSLog(@"GSGlobalShortcutsManager: Preserving protected Alt-Space key (%@) while ungrabbing other keys", keyCombo);
            }
            continue;
        }
        [self ungrabKeyCombo:keyCombo];
    }

    if (verbose) {
        NSLog(@"GSGlobalShortcutsManager: Ungrabbed all non-protected keys");
    }
}

- (void)showCommandFailureAlert:(NSString *)command shortcut:(NSString *)shortcut
{
    NSAlert *alert = [NSAlert alertWithMessageText:@"Global Shortcut Failed"
                                     defaultButton:@"OK"
                                   alternateButton:nil
                                       otherButton:nil
                         informativeTextWithFormat:@"The command '%@' assigned to shortcut '%@' could not be executed.\n\nPossible reasons:\n• Command not found in PATH\n• Insufficient permissions\n• Command syntax error", command, shortcut];
    
    [alert setAlertStyle:NSWarningAlertStyle];
    
    // Run the alert on the main thread since X11 event processing may be on a background thread
    dispatch_async(dispatch_get_main_queue(), ^{
        [alert runModal];
    });
}

- (void)temporarilyDisableAllShortcuts:(NSNotification *)notification
{
    if (running && shortcuts && [shortcuts count] > 0) {
        NSLog(@"GSGlobalShortcutsManager: Temporarily disabling all shortcuts for key capture");
        [self ungrabAllKeys];
    } else {
        NSLog(@"GSGlobalShortcutsManager: Cannot disable shortcuts - not running or no shortcuts loaded");
    }
}

- (void)reEnableAllShortcuts:(NSNotification *)notification
{
    if (running) {
        NSLog(@"GSGlobalShortcutsManager: Re-enabling all shortcuts after key capture");
        [self grabKeys];
    } else {
        NSLog(@"GSGlobalShortcutsManager: Cannot re-enable shortcuts - not running");
    }
}

- (BOOL)isShortcutAlreadyTaken:(NSString *)keyCombo
{
    // Check if the key combination is already in use
    for (NSString *key in shortcuts) {
        NSDictionary *shortcut = [shortcuts objectForKey:key];
        NSString *existingCombo = [NSString stringWithFormat:@"%@+%@", 
                                  [shortcut objectForKey:@"modifiers"],
                                  [shortcut objectForKey:@"keyStr"]];
        if ([existingCombo isEqualToString:keyCombo]) {
            return YES;
        }
    }
    return NO;
}

@end
