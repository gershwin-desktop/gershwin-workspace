/* AppDataTrash.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Offers to move an application's user data (caches, logs, preferences,
 * application support) to the Trash along with the application bundle.
 */

#import "AppDataTrash.h"
#import "AppearanceMetrics.h"

#import <AppKit/AppKit.h>

/* Confirmation dialog with a scrollable list of the related items, each with
 * its own checkbox.  GNUstep NSAlert has no accessory view, so build a small
 * window modeled on GWDialog, following the spacing rules in
 * AppearanceMetrics.h. */
@interface AppDataTrashDialog : NSWindow <NSTableViewDataSource>
{
  NSTableView *tableView;
  NSButton *cancelButt, *okButt;
  NSArray *paths;
  NSMutableArray *checked;
  NSModalResponse result;
}
- (id)initWithAppName:(NSString *)appName relatedPaths:(NSArray *)paths;
- (NSModalResponse)runModal;
- (NSArray *)selectedPaths;
- (void)buttonAction:(id)sender;
@end

@implementation AppDataTrashDialog

- (void)dealloc
{
  RELEASE (paths);
  RELEASE (checked);
  [super dealloc];
}

- (id)initWithAppName:(NSString *)appName relatedPaths:(NSArray *)relPaths
{
  CGFloat cw = METRICS_WIN_MIN_WIDTH;
  CGFloat ch = 300;
  NSRect r = NSMakeRect(0, 0, cw, ch);

  self = [super initWithContentRect: r
                          styleMask: NSTitledWindowMask
                            backing: NSBackingStoreRetained
                              defer: NO];
  if (self)
    {
      NSView *cv;
      NSTextField *titleField;
      NSTextField *messageField;
      NSScrollView *scroll;
      NSTableColumn *checkColumn;
      NSTableColumn *pathColumn;
      NSButtonCell *checkCell;
      CGFloat y;
      NSUInteger i;

      ASSIGN (paths, relPaths);

      checked = [[NSMutableArray alloc] initWithCapacity: [paths count]];
      for (i = 0; i < [paths count]; i++)
        {
          /* Preference plists are unchecked by default so a user's settings
           * are only moved if explicitly requested. */
          NSString *p = [paths objectAtIndex: i];
          int on = ([[p pathExtension] isEqualToString: @"plist"]) ? 0 : 1;
          [checked addObject: [NSNumber numberWithInt: on]];
        }

      cv = [[NSView alloc] initWithFrame: [self frame]];
      [self setContentView: cv];
      RELEASE(cv);
      [self setTitle: @""];

      /* Center the window, 36 px from the top of the screen */
      {
        NSRect sf = [[NSScreen mainScreen] frame];
        NSRect wf = [self frame];
        wf.origin.x = (sf.size.width - wf.size.width) / 2;
        wf.origin.y = sf.size.height - wf.size.height - 36;
        [self setFrame: wf display: NO];
      }

      y = ch - METRICS_CONTENT_TOP_MARGIN;

      /* Title label: System Regular 13 pt */
      titleField = [[NSTextField alloc] initWithFrame:
                     NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y - 16,
                                cw - 2 * METRICS_CONTENT_SIDE_MARGIN, 16)];
      [titleField setBackgroundColor: [NSColor windowBackgroundColor]];
      [titleField setBezeled: NO];
      [titleField setEditable: NO];
      [titleField setSelectable: NO];
      [titleField setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [titleField setStringValue:
        NSLocalizedString(@"Move related application data to the Trash?", @"")];
      [cv addSubview: titleField];
      RELEASE(titleField);

      y -= 16 + METRICS_TITLE_MESSAGE_GAP;

      /* Message label: System Regular 13 pt, wrapped */
      messageField = [[NSTextField alloc] initWithFrame:
                       NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y - 40,
                                  cw - 2 * METRICS_CONTENT_SIDE_MARGIN, 40)];
      [messageField setBackgroundColor: [NSColor windowBackgroundColor]];
      [messageField setBezeled: NO];
      [messageField setEditable: NO];
      [messageField setSelectable: NO];
      [messageField setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [messageField setStringValue:
        [NSString stringWithFormat:
          NSLocalizedString(@"\"%@\" has related user data. Select the items to "
                            @"move to the Trash:", @""),
          appName]];
      [cv addSubview: messageField];
      RELEASE(messageField);

      y -= 40 + METRICS_SPACE_8;

      /* Scrollable list with a per-item checkbox column */
      scroll = [[NSScrollView alloc] initWithFrame:
                 NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y - 130,
                            cw - 2 * METRICS_CONTENT_SIDE_MARGIN, 130)];
      [scroll setHasVerticalScroller: YES];
      [scroll setBorderType: NSBezelBorder];

      tableView = [[NSTableView alloc] initWithFrame: [scroll bounds]];

      checkColumn = [[NSTableColumn alloc] initWithIdentifier: @"check"];
      [checkColumn setWidth: 24];
      [checkColumn setResizingMask: NSTableColumnNoResizing];
      checkCell = [[NSButtonCell alloc] init];
      [checkCell setButtonType: NSSwitchButton];
      [checkCell setEditable: YES];
      [checkCell setTarget: self];
      [checkCell setAction: @selector(checkboxClicked:)];
      [checkColumn setDataCell: checkCell];
      RELEASE(checkCell);
      [tableView addTableColumn: checkColumn];
      RELEASE(checkColumn);

      pathColumn = [[NSTableColumn alloc] initWithIdentifier: @"path"];
      [pathColumn setWidth: cw - 2 * METRICS_CONTENT_SIDE_MARGIN - 24 - 20];
      [tableView addTableColumn: pathColumn];
      RELEASE(pathColumn);

      [tableView setDataSource: self];
      [tableView setHeaderView: nil];
      [scroll setDocumentView: tableView];
      RELEASE(tableView);
      [cv addSubview: scroll];
      RELEASE(scroll);

      y -= 130 + METRICS_SPACE_16;

      /* Buttons: right-aligned, default "Move to Trash" in the lower-right
       * corner, Cancel to its left (AppearanceMetrics ordering).  Size each
       * button to fit its title so text is never clipped. */
      {
        CGFloat bh = METRICS_BUTTON_HEIGHT;
        CGFloat by = METRICS_CONTENT_BOTTOM_MARGIN;

        cancelButt = [[NSButton alloc] initWithFrame:
                       NSMakeRect(0, by, METRICS_BUTTON_MIN_WIDTH, bh)];
        [cancelButt setButtonType: NSMomentaryLight];
        [cancelButt setTitle: NSLocalizedString(@"Cancel", @"")];
        [cancelButt setTarget: self];
        [cancelButt setAction: @selector(buttonAction:)];
        [cancelButt setKeyEquivalent: @"\x1B"];
        [cancelButt sizeToFit];
        [cancelButt setFrameSize: NSMakeSize(MAX([cancelButt frame].size.width,
                                                 METRICS_BUTTON_MIN_WIDTH),
                                             METRICS_BUTTON_HEIGHT)];
        [cv addSubview: cancelButt];
        RELEASE(cancelButt);

        okButt = [[NSButton alloc] initWithFrame:
                   NSMakeRect(0, by, METRICS_BUTTON_MIN_WIDTH, bh)];
        [okButt setButtonType: NSMomentaryLight];
        [okButt setTitle: NSLocalizedString(@"Move to Trash", @"")];
        [okButt setTarget: self];
        [okButt setAction: @selector(buttonAction:)];
        [okButt setKeyEquivalent: @"\r"];
        [okButt sizeToFit];
        [okButt setFrameSize: NSMakeSize(MAX([okButt frame].size.width,
                                             METRICS_BUTTON_MIN_WIDTH),
                                         METRICS_BUTTON_HEIGHT)];

        /* Right-align both buttons with a fixed 10 px interspace */
        {
          CGFloat bw = [okButt frame].size.width + [cancelButt frame].size.width
                       + METRICS_BUTTON_HORIZ_INTERSPACE;
          CGFloat startX = cw - METRICS_CONTENT_SIDE_MARGIN - bw;
          NSRect of = [okButt frame];
          of.origin.x = startX + [cancelButt frame].size.width
                        + METRICS_BUTTON_HORIZ_INTERSPACE;
          [okButt setFrameOrigin: of.origin];
          NSRect cf = [cancelButt frame];
          cf.origin.x = startX;
          [cancelButt setFrameOrigin: cf.origin];
        }

        [cv addSubview: okButt];
        RELEASE(okButt);
      }

      result = NSAlertAlternateReturn;
    }

  return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
  return [paths count];
}

- (id)tableView:(NSTableView *)aTableView
objectValueForTableColumn:(NSTableColumn *)aTableColumn
            row:(NSInteger)rowIndex
{
  if ([[aTableColumn identifier] isEqual: @"check"])
    return [checked objectAtIndex: rowIndex];
  return [paths objectAtIndex: rowIndex];
}

- (void)checkboxClicked:(id)sender
{
  NSInteger row = [tableView clickedRow];
  if (row >= 0 && row < [checked count])
    {
      BOOL on = ([sender state] == NSOnState);
      [checked replaceObjectAtIndex: row withObject: [NSNumber numberWithInt: on]];
      [tableView reloadData];
    }
}

- (NSModalResponse)runModal
{
  [[NSApplication sharedApplication] runModalForWindow: self];
  return result;
}

- (NSArray *)selectedPaths
{
  NSMutableArray *selected = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      if ([[checked objectAtIndex: i] boolValue])
        [selected addObject: [paths objectAtIndex: i]];
    }

  return selected;
}

- (void)buttonAction:(id)sender
{
  if (sender == okButt)
    result = NSAlertDefaultReturn;
  else
    result = NSAlertAlternateReturn;

  [[NSApplication sharedApplication] stopModal];
  [self orderOut: nil];
}

@end

@implementation AppDataTrash

/* The standard per-user directories an application may own.  All of them are
 * derived from the running system (Foundation's search-path API and the
 * GNUstep user config), never hard-coded: the user's ApplicationSupport and
 * Caches come from NSSearchPathForDirectoriesInDomains, the Preferences
 * directory from GSDefaultsRootForUser(), and logs live under the resolved
 * user Library directory. */
+ (NSArray *)userLibraryDirectories
{
  return NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                             NSUserDomainMask, YES);
}

+ (NSString *)preferencesDirectory
{
  return GSDefaultsRootForUser(NSUserName());
}

/* Returns the candidate data locations for one identifier variant (the full
 * bundle identifier, its last path component, or the application name).
 * Only standard, system-derived directories are considered. */
+ (NSArray *)candidateUserDataPathsForIdentifier:(NSString *)identifier
{
  if (identifier == nil || [identifier length] == 0)
    return nil;

  NSMutableArray *candidates = [NSMutableArray array];

  for (NSString *dir in NSSearchPathForDirectoriesInDomains(
         NSApplicationSupportDirectory, NSUserDomainMask, YES))
    [candidates addObject: [dir stringByAppendingPathComponent: identifier]];

  for (NSString *dir in NSSearchPathForDirectoriesInDomains(
         NSCachesDirectory, NSUserDomainMask, YES))
    [candidates addObject: [dir stringByAppendingPathComponent: identifier]];

  for (NSString *dir in [self userLibraryDirectories])
    {
      /* Logs are conventionally located under the user's Library. */
      [candidates addObject:
        [dir stringByAppendingPathComponent:
          [@"Logs" stringByAppendingPathComponent: identifier]]];
    }

  {
    NSString *prefsDir = [self preferencesDirectory];
    if (prefsDir)
      {
        /* Preference files are usually <identifier>.plist in the user's
         * preferences directory, but may also be a directory. */
        [candidates addObject:
          [prefsDir stringByAppendingPathComponent:
            [identifier stringByAppendingPathExtension: @"plist"]]];
        [candidates addObject:
          [prefsDir stringByAppendingPathComponent: identifier]];
      }
  }

  return candidates;
}

/* Returns the identifier variants to look for: the full bundle identifier,
 * its last path component (for reverse-DNS identifiers whose data lives
 * under just the final name component), and the application name. */
+ (NSArray *)identifierVariantsForApplicationAtPath:(NSString *)appPath
{
  NSMutableArray *variants = [NSMutableArray array];

  NSString *name =
    [[appPath lastPathComponent] stringByDeletingPathExtension];

  NSBundle *bundle = [NSBundle bundleWithPath: appPath];
  NSString *identifier =
    [bundle objectForInfoDictionaryKey: @"CFBundleIdentifier"];

  if (identifier && [identifier length])
    {
      if ([variants containsObject: identifier] == NO)
        [variants addObject: identifier];

      /* Reverse-DNS identifiers (e.g. org.gnustep.MyApp) often store data
       * under just the final name component.  NSString's lastPathComponent
       * does not split on dots, so take the last dot-separated segment. */
      NSArray *parts = [identifier componentsSeparatedByString: @"."];
      NSString *final = [parts lastObject];
      if (final && [final length] && [final isEqualToString: identifier] == NO)
        {
          if ([variants containsObject: final] == NO)
            [variants addObject: final];
        }
    }

  if (name && [name length] && [variants containsObject: name] == NO)
    [variants addObject: name];

  return variants;
}

+ (NSArray *)relatedUserDataPathsForApplicationAtPath:(NSString *)appPath
{
  if (appPath == nil || [[appPath pathExtension] isEqualToString: @"app"] == NO)
    return nil;

  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableArray *existing = [NSMutableArray array];
  NSMutableArray *candidates = [NSMutableArray array];

  for (NSString *identifier in [self identifierVariantsForApplicationAtPath: appPath])
    {
      NSArray *paths = [self candidateUserDataPathsForIdentifier: identifier];
      if (paths)
        [candidates addObjectsFromArray: paths];
    }

  for (NSString *candidate in candidates)
    {
      if ([candidate length] == 0)
        continue;
      if ([existing containsObject: candidate])
        continue;
      if ([fm fileExistsAtPath: candidate])
        [existing addObject: candidate];
    }

  return [existing count] ? existing : nil;
}

/* Shows the confirmation dialog listing relatedPaths (each with its own
 * checkbox) that would be moved to the Trash along with appName.  Returns
 * YES to proceed (trash the app bundle), NO to cancel.  If YES,
 * *pathsToMove is set to the subset of relatedPaths the user checked. */
+ (BOOL)confirmTrashForApplicationNamed:(NSString *)appName
                          relatedPaths:(NSArray *)relatedPaths
                           pathsToMove:(NSArray **)pathsToMove
{
  if (pathsToMove)
    *pathsToMove = nil;

  AppDataTrashDialog *dialog =
    [[AppDataTrashDialog alloc] initWithAppName: appName
                                   relatedPaths: relatedPaths];
  NSModalResponse response = [dialog runModal];
  BOOL proceed = (response == NSAlertDefaultReturn);

  if (proceed && pathsToMove)
    *pathsToMove = [[dialog selectedPaths] retain];

  RELEASE(dialog);
  return proceed;
}

/* Moves each path in paths to the user's Trash (~/.Trash), resolving name
 * collisions by appending _copy, _copy2, ... like the normal trash flow.
 * Items that are missing or fail to move are skipped so one failure never
 * blocks the others or the application bundle's own trashing. */
+ (void)movePathsToTrash:(NSArray *)paths
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *copystr = NSLocalizedString(@"_copy", @"");
  NSString *trashPath =
    [NSHomeDirectory() stringByAppendingPathComponent: @".Trash"];

  for (NSString *srcpath in paths)
    {
      if (srcpath == nil || [fm fileExistsAtPath: srcpath] == NO)
        continue;

      NSString *filename = [srcpath lastPathComponent];
      NSString *destpath = [trashPath stringByAppendingPathComponent: filename];
      NSString *newname = filename;

      if ([fm fileExistsAtPath: destpath])
        {
          NSString *ext = [filename pathExtension];
          NSString *base = [filename stringByDeletingPathExtension];
          NSUInteger count = 1;

          while (1)
            {
              if (count == 1)
                newname = [base stringByAppendingString: copystr];
              else
                newname = [base stringByAppendingFormat: @"%@%lu",
                            copystr, (unsigned long)count];
              if ([ext length])
                newname = [newname stringByAppendingPathExtension: ext];

              destpath = [trashPath stringByAppendingPathComponent: newname];
              if ([fm fileExistsAtPath: destpath] == NO)
                break;
              count++;
            }
        }

      [fm movePath: srcpath toPath: destpath handler: nil];
    }
}

@end
