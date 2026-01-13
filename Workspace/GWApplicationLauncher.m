/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "GWApplicationLauncher.h"
#import <unistd.h>

@implementation GWApplicationLauncher

+ (void)launchAndMonitor:(NSString *)path withArguments:(NSArray *)args
{
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:path];
  [task setArguments:args ? args : [NSArray array]];
  
  [self launchAndMonitorTask:task];
  [task release];
}

+ (void)launchAndMonitorTask:(NSTask *)task
{
  /* Launch and monitor in background thread to avoid blocking UI. */
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                        task, @"task",
                        [task launchPath], @"path",
                        nil];
  [NSThread detachNewThreadSelector:@selector(_monitorLaunchThread:)
                           toTarget:self
                         withObject:info];
}

+ (void)_monitorLaunchThread:(id)anObject
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSDictionary *info = (NSDictionary *)anObject;
  NSTask *task = [info objectForKey:@"task"];
  NSString *path = [info objectForKey:@"path"];
  
  @try {
    NSPipe *errPipe = [NSPipe pipe];
    [task setStandardError:errPipe];

    @try {
      [task launch];
    } @catch (NSException *ex) {
      NSString *reason = [ex reason] ? [ex reason] : NSLocalizedString(@"(failed to launch)", @"launcher exception fallback");
      NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                 path, @"path",
                                 [NSNumber numberWithInt:-1], @"status",
                                 reason, @"stderr",
                                 nil];
      [self performSelectorOnMainThread:@selector(_showErrorAlert:)
                             withObject:errorInfo
                          waitUntilDone:NO];
      [pool drain];
      return;
    }

    /* Wait up to 10s for the process to exit; if it exits within that time with
       non-zero status, show an alert with stderr */
    int checks = 100; /* 100 * 0.1s = 10s */
    for (int i = 0; i < checks; i++) {
      usleep(100000);
      if (![task isRunning]) break;
    }

    if (![task isRunning]) {
      int status = [task terminationStatus];
      if (status != 0) {
        NSData *d = [[[errPipe fileHandleForReading] readDataToEndOfFile] retain];
        NSString *s = nil;
        if (d) s = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
        if (!s) s = @"(no stderr output)";
        NSDictionary *errorInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                   path, @"path",
                                   [NSNumber numberWithInt:status], @"status",
                                   s, @"stderr",
                                   nil];
        [self performSelectorOnMainThread:@selector(_showErrorAlert:)
                               withObject:errorInfo
                            waitUntilDone:NO];
        [d release];
      }
    }

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

  /* Truncate stderr: show first 5 and last 10 lines if long */
  NSString *detail = stderrOut ? stderrOut : @"";
  NSArray *lines = [detail componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
  NSUInteger total = [lines count];
  NSString *displayText = detail;
  if (total > 15) {
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < 5; i++) [parts addObject:[lines objectAtIndex:i]];
    NSUInteger omitted = total - 15;
    [parts addObject:[NSString stringWithFormat:@"... %lu lines omitted ...", (unsigned long)omitted]];
    for (NSUInteger i = total - 10; i < total; i++) [parts addObject:[lines objectAtIndex:i]];
    displayText = [parts componentsJoinedByString:@"\n"];
  }

  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:title];
  [alert setInformativeText:msg];
  [alert addButtonWithTitle:@"OK"];
  if ([displayText length] > 0) {
    NSTextView *tv = [[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,200)] autorelease];
    [tv setString:displayText];
    [tv setEditable:NO];
    [tv setSelectable:YES];
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,400,200)] autorelease];
    [sv setHasVerticalScroller:YES];
    [sv setDocumentView:tv];
    if ([alert respondsToSelector:@selector(setAccessoryView:)]) {
      [(id)alert setAccessoryView:sv];
    } else {
      /* Fallback: append truncated stderr to informative text if accessory
         view isn't available on this platform/SDK. */
      [alert setInformativeText:[NSString stringWithFormat:@"%@\n\n%@", msg, displayText]];
    }
  }
  [alert runModal];
}

@end
