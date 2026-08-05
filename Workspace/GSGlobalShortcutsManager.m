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

#import "Workspace.h"
#import <GNUstepGUI/GSDisplayServer.h>

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

        // Close window shortcut (Alt+W) - initialized when display is ready
        closeWindowKeyCode = 0;
        closeWindowModifier = 0;

        // Close window shortcut (Alt+W) - initialized when display is ready
        closeWindowKeyCode = 0;
        closeWindowModifier = 0;
        
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
        return NO;
    }
    
    if (![self loadShortcuts]) {
        [self stop];
        return NO;
    }
    
    if (![self grabKeys]) {
        [self stop];
        return NO;
    }
    
    if (![self setupEventProcessing]) {
        [self stop];
        return NO;
    }
    
    running = YES;
    
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
    }
}

- (BOOL)setupX11
{
    display = XOpenDisplay(NULL);
    if (!display) {
        return NO;
    }
    
    rootWindow = DefaultRootWindow(display);
    if (rootWindow == None) {
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
                if (verbose) break;
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
        [shortcuts release];
        shortcuts = [[NSMutableDictionary alloc] init];

        // Restore protected Alt-Space if it existed
        if (protectedKey && protectedShortcut) {
            [shortcuts setObject:protectedShortcut forKey:protectedKey];
            if (verbose) [protectedKey release];
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
        if (verbose) [protectedKey release];
        [protectedShortcut release];
    }

    lastDefaultsModTime = time(NULL);
    
    [defaults release];
    return YES;
}

- (BOOL)grabKeys
{
    int successCount = 0;
    
    NSEnumerator *enumerator = [shortcuts keyEnumerator];
    NSString *keyCombo;
    
    while ((keyCombo = [enumerator nextObject])) {
        if ([self grabKeyCombo:keyCombo]) {
            successCount++;
        }
    }

    // Grab Alt+W (Cmd+W in Gershwin) to handle window closing
    // at the X11 level before the window manager can intercept it.
    [self grabCloseWindowShortcut];

    return (successCount > 0);
}

- (void)ungrabKeys
{
    // Ungrab keys individually so we can preserve protected shortcuts (e.g., Alt-Space)
    [self ungrabCloseWindowShortcut];

    if (!shortcuts || [shortcuts count] == 0) return;

    NSEnumerator *enumerator = [shortcuts keyEnumerator];
    NSString *keyCombo;
    while ((keyCombo = [enumerator nextObject])) {
        if (isAltSpaceCombo(keyCombo)) {
            if (verbose) {
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
        return NO;
    }
    
    KeyCode keycode = XKeysymToKeycode(display, keysym);
    if (keycode == 0) {
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
    }
    
    return YES;
}

- (void)ungrabKeyCombo:(NSString *)keyCombo
{
    // Never ungrab the Alt-Space global shortcut once it has been registered
    if (isAltSpaceCombo(keyCombo)) {
        if (verbose) {
        }
        return;
    }

    NSArray *parts = parseKeyCombo(keyCombo);
    if (!parts || [parts count] < 1) {
        if (verbose) {
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
        }
        return;
    }
    
    KeySym keysym = keysymFromName(keyString);
    if (keysym == NoSymbol) {
        if (verbose) {
        }
        return;
    }
    
    int keycode = XKeysymToKeycode(display, keysym);
    if (keycode == 0) {
        if (verbose) {
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
    
    return YES;
}

- (void)processX11Events
{
    if (!display || !rootWindow) return;
    
    XEvent event;
    int eventsProcessed = 0;
    const int maxEventsPerCall = 10; // Limit to prevent CPU hogging
    
    while (XPending(display) > 0 && eventsProcessed < maxEventsPerCall) {
        XNextEvent(display, &event);
        eventsProcessed++;
        
        if (event.type == KeyPress) {
            if (verbose) {
            }


            // Mask out lock keys for normal shortcuts
            event.xkey.state &= ~(numlock_mask | capslock_mask | scrolllock_mask);
            
            // Find matching shortcut
            NSEnumerator *enumerator = [shortcuts keyEnumerator];
            NSString *keyCombo;
            BOOL matched = NO;
            
            while ((keyCombo = [enumerator nextObject])) {
                if ([self matchesEvent:&event.xkey withKeyCombo:keyCombo]) {
                    NSDictionary *shortcutDict = [shortcuts objectForKey:keyCombo];
                    NSString *command = [shortcutDict objectForKey:@"command"];
                    
                    if (![self runCommand:command]) {
                        [self showCommandFailureAlert:command shortcut:keyCombo];
                    }
                    matched = YES;
                    break;
                }
            }
            
            // If no shortcut matched, forward the event to the focused window
            // so it reaches the intended application (e.g. Shift+T in a terminal).
            // XGrabKey may intercept events with modifier mismatches on some
            // X server configurations; discarding them would make keys vanish.
            if (!matched) {
                Window focused;
                int revert;
                XGetInputFocus(display, &focused, &revert);
                if (focused != None && focused != rootWindow) {
                    event.xkey.window = focused;
                    XSendEvent(display, focused, True, KeyPressMask, &event);
                    XFlush(display);
                }
            }
        }
    }
}

- (BOOL)runCommand:(NSString *)command
{
    if (!command || [command length] == 0) {
        return NO;
    }
    
    if ([command length] > 1024) {
        return NO;
    }
    
    NSArray *components = [command componentsSeparatedByString:@" "];
    if ([components count] == 0) {
        return NO;
    }
    
    NSString *executable = [components objectAtIndex:0];
    
    // Security check - reject commands with dangerous characters
    NSCharacterSet *dangerousChars = [NSCharacterSet characterSetWithCharactersInString:@"`$;|&<>"];
    if ([command rangeOfCharacterFromSet:dangerousChars].location != NSNotFound) {
    }
    
    NSString *fullPath = [self findExecutableInPath:executable];
    
    if (!fullPath) {
        return NO;
    }
    
    if (verbose) {
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
                return NO;
            }
        }
        
        if (WIFEXITED(status) && WEXITSTATUS(status) != 0) {
            return NO;
        }
        
        return YES;
    } else {
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
    
    if (running) {
        
        // Extract shortcuts data directly from userInfo
        NSDictionary *userInfo = [notification userInfo];
        
        NSNumber *shortcutCount = [userInfo objectForKey:@"shortcutCount"];
        NSArray *shortcutsArray = [userInfo objectForKey:@"shortcuts"];
        
        
        if (shortcutCount) {
        }
        
        if (shortcutsArray) {
            [self processShortcutsData:shortcutsArray];
        } else {
            [self reloadShortcutsIfChanged];
        }
    } else {
    }
}

- (void)processShortcutsData:(NSArray *)shortcutsArray
{

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
                if (verbose) break;
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
        if (verbose) [protectedKey release];
        [protectedShortcut release];
    }
    
    // Process the new shortcuts data
    for (NSDictionary *shortcutDict in shortcutsArray) {
        
        NSString *key = [shortcutDict objectForKey:@"key"];
        NSString *command = [shortcutDict objectForKey:@"command"];
        NSString *modifiersStr = [shortcutDict objectForKey:@"modifiers"];
        NSString *keyStr = [shortcutDict objectForKey:@"keyStr"];
        
        if (key && command && modifiersStr && keyStr) {
            NSDictionary *shortcut = @{
                @"command": command,
                @"modifiers": modifiersStr,
                @"keyStr": keyStr
            };
            [shortcuts setObject:shortcut forKey:key];
        }
    }
    
    // Grab the new keys
    [self grabKeys];
}

- (void)reloadShortcutsIfChanged
{
    
    // Check if our GlobalShortcuts domain has changed
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults synchronize];
    
    NSDictionary *newConfig = [defaults persistentDomainForName:defaultsDomain];
    
    
    // Compare with current shortcuts
    BOOL needsReload = NO;
    
    if (!shortcuts && !newConfig) {
        return;
    }
    
    if (!shortcuts || !newConfig) {
        needsReload = YES;
    } else if ([shortcuts count] != [newConfig count]) {
        needsReload = YES;
    } else {
        // Check if any key-command pairs have changed
        NSEnumerator *keyEnum = [shortcuts keyEnumerator];
        NSString *keyCombo;
        while ((keyCombo = [keyEnum nextObject])) {
            NSString *oldCommand = [shortcuts objectForKey:keyCombo];
            NSString *newCommand = [newConfig objectForKey:keyCombo];
            
            if (!newCommand || ![oldCommand isEqualToString:newCommand]) {
                needsReload = YES;
                break;
            }
        }
        
        // Check for new shortcuts that weren't in the old config
        if (!needsReload) {
            keyEnum = [newConfig keyEnumerator];
            while ((keyCombo = [keyEnum nextObject])) {
                if (![shortcuts objectForKey:keyCombo]) {
                    needsReload = YES;
                    break;
                }
            }
        }
        
        if (!needsReload) {
        }
    }
    
    if (needsReload) {
        
        // Ungrab all current keys
        [self ungrabAllKeys];
        
        // Load new configuration
        if ([self loadShortcuts]) {
            // Grab new keys
            if ([self grabKeys]) {
            } else {
            }
        } else {
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
            }
            continue;
        }
        [self ungrabKeyCombo:keyCombo];
    }

    if (verbose) {
    }
}


// X11 error handler to catch BadAccess from XGrabKey
// Returns 0 to tell the X server we handled it (prevents abort)
static int GWX11GrabErrorHandler(Display *dpy, XErrorEvent *ev)
{
    char errbuf[256];
    XGetErrorText(dpy, ev->error_code, errbuf, sizeof(errbuf));
    NSLog(@"GSGlobalShortcutsManager: X11 error: %s (request=%d resource=%ld)",
        errbuf, ev->request_code, ev->resourceid);
    return 0;
}

- (void)grabCloseWindowShortcut
{
    if (!display || rootWindow == None) return;

    // Map the 'w' key to an X11 keycode
    KeySym keysym = XStringToKeysym("w");
    if (keysym == NoSymbol) {
        NSLog(@"GSGlobalShortcutsManager: Could not find keysym for 'w'");
        return;
    }

    // We need to use the MAIN application X11 display (the one the GNUstep
    // backend uses to own our windows), not our separate display connection.
    // This ensures that grabbed events flow through the normal GNUstep event
    // path and reach the menu key-equivalent system.
    GSDisplayServer *server = GSCurrentServer();
    if (!server) {
        NSLog(@"GSGlobalShortcutsManager: No display server available");
        return;
    }
    Display *appDisplay = (Display *)[server serverDevice];
    if (!appDisplay) {
        NSLog(@"GSGlobalShortcutsManager: No X11 display from server");
        return;
    }

    closeWindowKeyCode = XKeysymToKeycode(appDisplay, keysym);
    if (closeWindowKeyCode == 0) {
        NSLog(@"GSGlobalShortcutsManager: Could not map 'w' to keycode");
        return;
    }

    // Mod1Mask = Alt key (Cmd in Gershwin)
    closeWindowModifier = Mod1Mask;

    // Install temporary error handler to catch BadAccess from XGrabKey
    XErrorHandler old_handler = XSetErrorHandler(GWX11GrabErrorHandler);

    unsigned int modifiers[] = {
        closeWindowModifier,
        closeWindowModifier | numlock_mask,
        closeWindowModifier | capslock_mask,
        closeWindowModifier | numlock_mask | capslock_mask,
        closeWindowModifier | scrolllock_mask,
        closeWindowModifier | numlock_mask | scrolllock_mask,
        closeWindowModifier | capslock_mask | scrolllock_mask,
        closeWindowModifier | numlock_mask | capslock_mask | scrolllock_mask
    };

    // Grab on each application window using the MAIN display connection.
    // With owner_events=True: the event is delivered normally through the
    // GNUstep backend's event path (since the grabbing display OWNS these
    // windows). This overrides the window manager's root-window grab for
    // our windows, and the normal menu key-equivalent processing handles it.
    NSArray *appWindows = [NSApp windows];
    
    for (NSWindow *win in appWindows)
    {
        // Skip desktop window
        if ([win isKindOfClass: NSClassFromString(@"GWDesktopWindow")])
            continue;
        
        void *winptr = [server windowDevice: [win windowNumber]];
        if (!winptr)
            continue;
        
        Window xwindow = (Window)(uintptr_t)winptr;
        if (xwindow == 0)
            continue;
        
        for (int i = 0; i < 8; i++) {
            XGrabKey(appDisplay, closeWindowKeyCode, modifiers[i], xwindow,
                     True, GrabModeAsync, GrabModeAsync);
        }
    }
    
    XSync(appDisplay, False);

    // Restore previous error handler
    XSetErrorHandler(old_handler);

}

- (void)ungrabCloseWindowShortcut
{
    if (closeWindowKeyCode == 0) return;

    GSDisplayServer *server = GSCurrentServer();
    if (!server) return;
    Display *appDisplay = (Display *)[server serverDevice];
    if (!appDisplay) return;

    unsigned int modifiers[] = {
        closeWindowModifier,
        closeWindowModifier | numlock_mask,
        closeWindowModifier | capslock_mask,
        closeWindowModifier | numlock_mask | capslock_mask,
        closeWindowModifier | scrolllock_mask,
        closeWindowModifier | numlock_mask | scrolllock_mask,
        closeWindowModifier | capslock_mask | scrolllock_mask,
        closeWindowModifier | numlock_mask | capslock_mask | scrolllock_mask
    };

    // Ungrab from all application windows
    NSArray *appWindows = [NSApp windows];
    for (NSWindow *win in appWindows)
    {
        void *winptr = [server windowDevice: [win windowNumber]];
        if (!winptr)
            continue;
        
        Window xwindow = (Window)(uintptr_t)winptr;
        if (xwindow == 0)
            continue;
        
        for (int i = 0; i < 8; i++) {
            XUngrabKey(appDisplay, closeWindowKeyCode, modifiers[i], xwindow);
        }
    }

    closeWindowKeyCode = 0;
    closeWindowModifier = 0;

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
        [self ungrabAllKeys];
    } else {
    }
}

- (void)reEnableAllShortcuts:(NSNotification *)notification
{
    if (running) {
        [self grabKeys];
    } else {
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
