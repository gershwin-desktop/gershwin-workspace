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

  /* GNUstep-thread worker instead of libdispatch: a GCD worker thread running
   * ObjC can race the main thread's +load dispatch and crash the app (GPF in
   * libobjc's load_messages_insert).  The flag is only touched on the main
   * thread (the worker posts doneWithSuccess: back here), so it needs no
   * synchronization. */
  volatile BOOL done = NO;
  doneFlag = &done;

  [NSThread detachNewThreadSelector: @selector(runArchiveWorker:)
                           toTarget: self
                         withObject: nil];

  /* Present the progress panel as a proper modal session so events are
   * confined to it — the user can no longer trigger menu actions or other
   * windows mid-operation (the previous hand-pumped NSAnyEventMask loop
   * dispatched every event and was reentrant).  The archive work runs on a
   * background thread; each iteration we advance the modal session, then run
   * the default run-loop mode briefly so the completion posts to the main
   * thread can fire, and poll the flag for completion. */
  NSModalSession session = [NSApp beginModalSessionForWindow: progressWindow];
  while (!done)
    {
      if ([NSApp runModalSession: session] != NSRunContinuesResponse)
        break;
      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.03]];
    }
  [NSApp endModalSession: session];

  doneFlag = NULL;

  return (error == nil && !cancelled);
}

/* Archive worker — runs on a background thread (GNUstep thread, not
 * libdispatch; see the caller).  Posts the result back to the main thread. */
- (void)runArchiveWorker:(id)unused
{
  @autoreleasepool
    {
      BOOL ok;
      if ([operationType isEqual: @"compress"])
        ok = [self runCompress];
      else
        ok = [self runExtract];
      NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithBool: ok], @"ok", nil];
      [self performSelectorOnMainThread: @selector(archiveWorkerFinished:)
                             withObject: result
                          waitUntilDone: NO];
    }
}

/* Main-thread half of the archive worker: finish the operation and release
 * the modal progress loop. */
- (void)archiveWorkerFinished:(NSDictionary *)result
{
  BOOL ok = [[result objectForKey: @"ok"] boolValue];
  [self doneWithSuccess: ok];
  if (doneFlag) *doneFlag = YES;
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

  [self performSelectorOnMainThread: @selector(beginCompressProgress:)
                         withObject: [NSNumber numberWithLongLong: totalItems]
                      waitUntilDone: NO];

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  /* Compress via GWMetaArchive, which enumerates the tree itself. */
  NSError *compressError = nil;
  BOOL ok = [GWMetaArchive compressPaths: paths toArchiveAt: outputPath error: &compressError];

  if (!ok)
    ASSIGN(error, compressError);

  [self performSelectorOnMainThread: @selector(finishCompressProgress:)
                         withObject: [NSNumber numberWithBool: ok]
                      waitUntilDone: NO];

  [pool release];
  return ok;
}

/* Main-thread halves of the compress progress updates. */
- (void)beginCompressProgress:(NSNumber *)totalItemsNum
{
  [progressBar setMaxValue: [totalItemsNum doubleValue]];
  [self updateProgress: 0.0 status: NSLocalizedString(@"Compressing...", @"")];
}

- (void)finishCompressProgress:(NSNumber *)okNum
{
  [self updateProgress: 100.0 status: ([okNum boolValue]
    ? NSLocalizedString(@"Done.", @"") : NSLocalizedString(@"Failed.", @""))];
}

/* =================================================================
 * Extract worker — runs on background thread
 * ================================================================= */

- (BOOL)runExtract
{
  NSString *archivePath = [paths objectAtIndex: 0];

  [self performSelectorOnMainThread: @selector(beginExtractProgress)
                         withObject: nil
                      waitUntilDone: NO];

  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *extractError = nil;
  BOOL ok = [GWMetaArchive extractArchive: archivePath toDir: outputPath error: &extractError];

  if (!ok)
    ASSIGN(error, extractError);

  [self performSelectorOnMainThread: @selector(finishExtractProgress:)
                         withObject: [NSNumber numberWithBool: ok]
                      waitUntilDone: NO];
  [pool release];

  return ok;
}

/* Main-thread halves of the extract progress updates. */
- (void)beginExtractProgress
{
  [progressBar setIndeterminate: YES];
  [progressBar startAnimation: nil];
  [self updateProgress: 0.0 status: NSLocalizedString(@"Extracting...", @"")];
}

- (void)finishExtractProgress:(NSNumber *)okNum
{
  [progressBar setIndeterminate: NO];
  [progressBar stopAnimation: nil];
  [self updateProgress: 100.0 status: ([okNum boolValue]
    ? NSLocalizedString(@"Done.", @"") : NSLocalizedString(@"Failed.", @""))];
}

@end
