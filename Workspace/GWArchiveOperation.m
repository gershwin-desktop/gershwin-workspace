/* GWArchiveOperation.m
 *
 * Background archive operation with progress panel.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWArchiveOperation.h"
#import "GWMetaArchive.h"

#include <dispatch/dispatch.h>

/* =================================================================
 * Private helpers
 * ================================================================= */

static void
count_items(NSString *path, NSUInteger *total, NSFileManager *fm)
{
  BOOL isDir;
  if (![fm fileExistsAtPath: path isDirectory: &isDir])
    return;

  (*total)++;

  if (isDir)
    {
      NSArray *kids = [fm directoryContentsAtPath: path];
      for (NSString *name in kids)
        {
          if ([name hasPrefix: @"._"])
            continue;
          count_items([path stringByAppendingPathComponent: name], total, fm);
        }
    }
}

@implementation GWArchiveOperation

/* =================================================================
 * Convenience class methods — block until done, show progress
 * ================================================================= */

+ (BOOL)compressPaths:(NSArray *)paths toArchive:(NSString *)outputPath
{
  GWArchiveOperation *op = [[self alloc] init];
  op->operationType = @"compress";
  op->paths         = paths;
  op->outputPath    = outputPath;

  BOOL ok = [op run];
  RELEASE(op);
  return ok;
}

+ (BOOL)extractArchive:(NSString *)archivePath toDirectory:(NSString *)destDir
{
  GWArchiveOperation *op = [[self alloc] init];
  op->operationType = @"extract";
  op->paths         = @[archivePath];
  op->outputPath    = destDir;

  BOOL ok = [op run];
  RELEASE(op);
  return ok;
}

/* =================================================================
 * Instance — build the progress window
 * ================================================================= */

- (id)init
{
  self = [super init];
  if (self)
    {
      running   = NO;
      cancelled = NO;
      error     = nil;
    }
  return self;
}

- (void)dealloc
{
  RELEASE(error);
  RELEASE(progressWindow);
  [super dealloc];
}

- (void)buildProgressWindow
{
  CGFloat panelWidth  = 400;
  CGFloat panelHeight = 120;

  NSRect panelRect = NSMakeRect(0, 0, panelWidth, panelHeight);

  progressWindow = [[NSWindow alloc]
    initWithContentRect: panelRect
              styleMask: NSTitledWindowMask
                backing: NSBackingStoreBuffered
                  defer: YES];
  [progressWindow setTitle: ([operationType isEqual: @"compress"]
                             ? NSLocalizedString(@"Compressing...", @"")
                             : NSLocalizedString(@"Extracting...", @""))];
  [progressWindow center];

  NSView *content = [progressWindow contentView];

  /* Status label */
  statusField = [[NSTextField alloc] initWithFrame:
    NSMakeRect(20, panelHeight - 35, panelWidth - 40, 17)];
  [statusField setEditable: NO];
  [statusField setBezeled: NO];
  [statusField setDrawsBackground: NO];
  [statusField setStringValue: NSLocalizedString(@"Preparing...", @"")];
  [content addSubview: statusField];
  RELEASE(statusField);

  /* Progress bar */
  progressBar = [[NSProgressIndicator alloc] initWithFrame:
    NSMakeRect(20, panelHeight - 60, panelWidth - 40, 16)];
  [progressBar setIndeterminate: NO];
  [progressBar setMinValue: 0.0];
  [progressBar setMaxValue: 100.0];
  [content addSubview: progressBar];
  RELEASE(progressBar);

  /* Cancel button */
  cancelButton = [[NSButton alloc] initWithFrame:
    NSMakeRect(panelWidth - 100, 12, 80, 28)];
  [cancelButton setTitle: NSLocalizedString(@"Cancel", @"")];
  [cancelButton setTarget: self];
  [cancelButton setAction: @selector(cancelOperation:)];
  [cancelButton setBezelStyle: NSRoundedBezelStyle];
  [content addSubview: cancelButton];
  RELEASE(cancelButton);
}

- (void)cancelOperation:(id)sender
{
  cancelled = YES;
  [cancelButton setEnabled: NO];
  [statusField setStringValue: NSLocalizedString(@"Cancelling...", @"")];
}

- (void)updateProgress:(double)value status:(NSString *)status
{
  [progressBar setDoubleValue: value];
  if (status)
    [statusField setStringValue: status];
}

- (void)doneWithSuccess:(BOOL)ok
{
  running = NO;
  [progressWindow orderOut: nil];

  if (!ok && !cancelled && error)
    {
      NSRunAlertPanel(NSLocalizedString(@"Operation Failed", @""),
                      [error localizedDescription],
                      NSLocalizedString(@"OK", @""), nil, nil);
    }
}

/* =================================================================
 * Main entry — build UI, run work on background queue, block
 * ================================================================= */

- (BOOL)run
{
  [self buildProgressWindow];

  running = YES;

  /* Semaphore signalled on the main thread when the worker finishes. */
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    BOOL ok;

    if ([operationType isEqual: @"compress"])
      ok = [self runCompress];
    else
      ok = [self runExtract];

    dispatch_async(dispatch_get_main_queue(), ^{
      [self doneWithSuccess: ok];
      dispatch_semaphore_signal(sem);
    });
  });

  /* Present the progress panel as a proper modal session so events are
   * confined to it — the user can no longer trigger menu actions or other
   * windows mid-operation (the previous hand-pumped NSAnyEventMask loop
   * dispatched every event and was reentrant).  The archive work runs on a
   * background queue; each iteration we advance the modal session, then run
   * the default run-loop mode briefly so libdispatch's main-queue completion
   * block can fire, and poll the semaphore for completion. */
  NSModalSession session = [NSApp beginModalSessionForWindow: progressWindow];
  while (dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW) != 0)
    {
      if ([NSApp runModalSession: session] != NSRunContinuesResponse)
        break;
      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.03]];
    }
  [NSApp endModalSession: session];

  dispatch_release(sem);

  return (error == nil && !cancelled);
}

/* =================================================================
 * Compress worker — runs on background thread
 * ================================================================= */

- (BOOL)runCompress
{
  NSFileManager *fm = [NSFileManager defaultManager];

  /* Count total items */
  NSUInteger totalItems = 0;
  for (NSString *p in paths)
    count_items(p, &totalItems, fm);

  if (totalItems == 0)
    {
      ASSIGN(error, [NSError errorWithDomain: @"GWArchiveOperation"
                                        code: 1
                                    userInfo: @{NSLocalizedDescriptionKey: @"No files to compress"}]);
      return NO;
    }

  dispatch_async(dispatch_get_main_queue(), ^{
    [progressBar setMaxValue: (double)totalItems];
    [self updateProgress: 0.0 status: NSLocalizedString(@"Compressing...", @"")];
  });

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  /* Compress via GWMetaArchive, which enumerates the tree itself. */
  NSError *compressError = nil;
  BOOL ok = [GWMetaArchive compressPaths: paths toArchiveAt: outputPath error: &compressError];

  if (!ok)
    ASSIGN(error, compressError);

  dispatch_async(dispatch_get_main_queue(), ^{
    [self updateProgress: 100.0 status: (ok ? NSLocalizedString(@"Done.", @"")
                                           : NSLocalizedString(@"Failed.", @""))];
  });

  [pool release];
  return ok;
}

/* =================================================================
 * Extract worker — runs on background thread
 * ================================================================= */

- (BOOL)runExtract
{
  NSString *archivePath = [paths objectAtIndex: 0];

  dispatch_async(dispatch_get_main_queue(), ^{
    [progressBar setIndeterminate: YES];
    [progressBar startAnimation: nil];
    [self updateProgress: 0.0 status: NSLocalizedString(@"Extracting...", @"")];
  });

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *extractError = nil;
  BOOL ok = [GWMetaArchive extractArchive: archivePath toDir: outputPath error: &extractError];

  if (!ok)
    ASSIGN(error, extractError);

  dispatch_async(dispatch_get_main_queue(), ^{
    [progressBar setIndeterminate: NO];
    [progressBar stopAnimation: nil];
    [self updateProgress: 100.0 status: (ok ? NSLocalizedString(@"Done.", @"")
                                           : NSLocalizedString(@"Failed.", @""))];
  });
  [pool release];

  return ok;
}

@end
