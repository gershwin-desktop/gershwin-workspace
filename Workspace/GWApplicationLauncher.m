/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <dispatch/dispatch.h>
#import "GWApplicationLauncher.h"
#import <unistd.h>
#include <fcntl.h>

@implementation GWApplicationLauncher

+ (void)launchAndMonitor:(NSString *)path withArguments:(NSArray *)args
{
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setArguments:args ? args : [NSArray array]];
  
  [self launchAndMonitorTask:task];
  [task release];
}

+ (BOOL)launchAndMonitorTask:(NSTask *)task
{
  @try {
    /* Per-app stderr log file; O_APPEND | O_NONBLOCK so write(2) can never
       block the child's main thread. Writes to a regular POSIX file do not
       block on pipe back-pressure, so no Workspace stall can ever wedge a
       child's UI (this was the prior design flaw). A failed open falls
       through to /dev/null rather than a blocking pipe. */
    NSString *appName = [[task launchPath] lastPathComponent];
    NSString *logDir  = [NSHomeDirectory()
                         stringByAppendingPathComponent:@"Library/Logs"];
    NSString *logPath = [logDir stringByAppendingPathComponent:
                          [appName stringByAppendingPathExtension:@"log"]];

    [[NSFileManager defaultManager] createDirectoryAtPath:logDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    NSFileHandle *errHandle;
    int fd = open([logPath fileSystemRepresentation],
                  O_WRONLY | O_CREAT | O_APPEND | O_NONBLOCK, 0644);
    if (fd >= 0) {
      errHandle = [[[NSFileHandle alloc]
                     initWithFileDescriptor:fd
                             closeOnDealloc:YES] autorelease];
    } else {
      errHandle = [NSFileHandle fileHandleWithNullDevice];
    }
    [task setStandardError:errHandle];
    [task launch];

    /* Event-driven exit monitor via NSTaskDidTerminateNotification.
     *
     * NSTask posts this notification from its own SIGCHLD/waitpid
     * plumbing, so no custom thread parks in usleep or waitpid. The
     * block observer fires once, reads the log tail (bounded I/O on a
     * regular file), forwards the alert to the main queue, and
     * unregisters itself. POSIX-portable (Linux / FreeBSD / macOS) and
     * does not depend on libdispatch PROC sources, which are unavailable
     * on non-Apple libdispatch builds. */
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          task, @"task",
                          [task launchPath], @"path",
                          logPath, @"logPath",
                          nil];
    [info retain]; /* owned by the observer block, released on removal */

    __block id token = nil;
    token = [[[NSNotificationCenter defaultCenter]
              addObserverForName:NSTaskDidTerminateNotification
                          object:task
                           queue:nil
                      usingBlock:^(NSNotification *n) {
                        [self _handleTaskExit:info];
                        [[NSNotificationCenter defaultCenter]
                          removeObserver:token];
                        [token release];
                        [info release];
                      }] retain];
    return YES;
  } @catch (NSException *ex) {
    NSString *path = [task launchPath];
    NSString *reason = [ex reason] ? [ex reason] : NSLocalizedString(@"(failed to launch)", @"launcher exception fallback");
    NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                               path, @"path",
                               [NSNumber numberWithInt:-1], @"status",
                               reason, @"stderr",
                               nil];
    [self performSelectorOnMainThread: @selector(_showErrorAlert:)
                           withObject: errorInfo
                        waitUntilDone: NO];
    return NO;
  }
}

+ (void)_handleTaskExit:(id)anObject
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDictionary *info = (NSDictionary *)anObject;
  NSTask *task = [info objectForKey:@"task"];
  NSString *path = [info objectForKey:@"path"];
  NSString *logPath = [info objectForKey:@"logPath"];

  @try {
    /* Invoked from DISPATCH_PROC_EXIT handler — the child is gone. */
    int status = [task terminationStatus];
    if (status == 0) {
      return;
    }

    NSString *s = nil;
    NSData *d = [NSData dataWithContentsOfFile:logPath
                                       options:NSDataReadingMappedIfSafe
                                         error:NULL];
    if (d) {
      /* Bound the alert payload to the last 64 KiB even if the log file
         has accumulated across prior invocations. */
      NSUInteger cap = 64 * 1024;
      if ([d length] > cap) {
        d = [d subdataWithRange:NSMakeRange([d length] - cap, cap)];
      }
      s = [[[NSString alloc] initWithData:d
                                 encoding:NSUTF8StringEncoding] autorelease];
    }
    if (!s) s = @"(no stderr output)";

    NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                               path, @"path",
                               [NSNumber numberWithInt:status], @"status",
                               s, @"stderr",
                               nil];
    [self performSelectorOnMainThread: @selector(_showErrorAlert:)
                           withObject: errorInfo
                        waitUntilDone: NO];
  } @finally {
    [pool drain];
  }
}

+ (void)_showErrorAlert:(NSDictionary *)info
{
  NSString *path = [info objectForKey:@"path"];
  NSNumber *status = [info objectForKey:@"status"];
  NSString *stderrOut = [info objectForKey:@"stderr"];

  NSString *title = nil;
  NSString *msg = nil;
  if ([status intValue] < 0) {
    title = @"Application Failed to Launch";
    msg = [NSString stringWithFormat:@"The application \"%@\" could not be launched.", [path lastPathComponent]];
  } else {
    title = @"Application Error";
    msg = [NSString stringWithFormat:@"The application \"%@\" exited with status %d.", [path lastPathComponent], [status intValue]];
  }

  /* Never truncate or omit lines: the complete stderr is always shown,
     long text is handled by gershwin-eau-theme. */
  NSString *detail = stderrOut ? stderrOut : @"";
  BOOL hasOutput = ([detail length] > 0);

  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:title];
  [alert setInformativeText:msg];
  [alert addButtonWithTitle:@"OK"];
  if (hasOutput) {
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,200)] autorelease];
    [tv setString:detail];
    [tv setEditable:NO];
    [tv setSelectable:YES];
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,400,200)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setDocumentView:tv];
    if ([alert respondsToSelector:@selector(setAccessoryView:)]) {
      [(id)alert setAccessoryView:sv];
    } else {
      /* Fallback: append full stderr to informative text if accessory view
         isn't available on this platform/SDK. */
      [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@", msg, detail]];
    }
  } else {
    /* No stderr output - show a meaningful message instead of an empty view */
    [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@ has quit unexpectedly.", msg, [path lastPathComponent]]];
  }
  [alert runModal];
}

@end
