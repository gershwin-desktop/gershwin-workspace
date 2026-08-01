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
#import "FSNFunctions.h"

#import <AppKit/AppKit.h>

/* Confirmation dialog with a scrollable list of the related items, each with
 * its own checkbox.  GNUstep NSAlert has no accessory view, so build a small
 * window modeled on GWDialog, following the spacing rules in
 * AppearanceMetrics.h. */
@interface AppDataTrashDialog : NSWindow <NSTableViewDataSource, NSTableViewDelegate>
{
  NSTableView *tableView;
  NSTextField *infoLabel;
  NSButton *cancelButt, *okButt;
  NSArray *paths;
  NSMutableArray *checked;
  NSArray *toolTipTags; /* row index -> NSToolTipTag */
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
  RELEASE (toolTipTags);
  [super dealloc];
}

- (id)initWithAppName:(NSString *)appName relatedPaths:(NSArray *)relPaths
{
  /* Compute the wrapped message height first so the window is tall enough for
   * the text in every language (translations reflow, never clip). */
  CGFloat maxWidth = METRICS_WIN_MIN_WIDTH * 2.0;
  CGFloat cw = METRICS_WIN_MIN_WIDTH;

  /* Choose the window width from the longest path in the list, clamped
   * between the minimum and maximum width.  Long paths widen the window so
   * the full path is visible without scrolling; short ones keep it compact. */
  {
    NSFont *pathFont = [NSFont systemFontOfSize: 12];
    CGFloat longest = 0;
    for (NSString *p in relPaths)
      {
        NSSize s = [p sizeWithAttributes: @{ NSFontAttributeName: pathFont }];
        if (s.width > longest)
          longest = s.width;
      }
    CGFloat listNeeds = METRICS_TEXT_LEFT /* left margin + icon space */
                        + 24 /* checkbox column */
                        + 8 /* gap */
                        + longest
                        + 11 /* vertical scroller */
                        + METRICS_CONTENT_SIDE_MARGIN /* right margin */;
    cw = listNeeds;
    if (cw < METRICS_WIN_MIN_WIDTH)
      cw = METRICS_WIN_MIN_WIDTH;
    if (cw > maxWidth)
      cw = maxWidth;
    cw = ceil(cw);
  }

  NSString *msg =
    NSLocalizedString(@"Would you like to move the auxiliary data also to "
                      @"the Trash?\nKeeping or removing the auxiliary data is "
                      @"harmless.\nClick on an item to see a description.", @"");
  CGFloat mw = cw - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN;
  NSRect measure =
    [msg boundingRectWithSize: NSMakeSize(mw, 1e6)
                      options: NSStringDrawingUsesLineFragmentOrigin
                   attributes: @{ NSFontAttributeName: METRICS_FONT_SYSTEM_REGULAR_11 }];
  CGFloat mh = ceil(measure.size.height) + 2;

  /* Height = top margin + title + gap + message + gap + list + gap + info
   * label + gap + buttons + bottom margin. */
  CGFloat listHeight = 130;
  CGFloat ch = METRICS_CONTENT_TOP_MARGIN + 18 + METRICS_TITLE_MESSAGE_GAP
               + mh + METRICS_SPACE_8 + listHeight + METRICS_SPACE_8
               + 16 + METRICS_SPACE_16 + METRICS_BUTTON_HEIGHT
               + METRICS_CONTENT_BOTTOM_MARGIN;
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

      /* Icon at top left (NSAlert metrics) */
      {
        NSButton *icoButton = [[NSButton alloc] initWithFrame:
                                 NSMakeRect(METRICS_ICON_LEFT,
                                            ch - METRICS_ICON_TOP - METRICS_ICON_SIDE,
                                            METRICS_ICON_SIDE, METRICS_ICON_SIDE)];
        [icoButton setBordered: NO];
        [icoButton setEnabled: NO];
        [[icoButton cell] setImageDimsWhenDisabled: NO];
        [[icoButton cell] setImageScaling: NSImageScaleProportionallyUpOrDown];
        [icoButton setImagePosition: NSImageOnly];
        [icoButton setImage: [[NSApplication sharedApplication] applicationIconImage]];
        [cv addSubview: icoButton];
        RELEASE(icoButton);
      }

      y = ch - METRICS_CONTENT_TOP_MARGIN;

      /* Title label: bold, to the right of the icon (NSAlert metrics) */
      titleField = [[NSTextField alloc] initWithFrame:
                     NSMakeRect(METRICS_TEXT_LEFT, y - 18,
                                cw - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN, 18)];
      [titleField setBackgroundColor: [NSColor windowBackgroundColor]];
      [titleField setBezeled: NO];
      [titleField setEditable: NO];
      [titleField setSelectable: NO];
      [titleField setFont: METRICS_FONT_SYSTEM_BOLD_13];
      [titleField setStringValue:
        [NSString stringWithFormat:
          NSLocalizedString(@"%@ has related auxiliary data.", @""),
          appName]];
      [cv addSubview: titleField];
      RELEASE(titleField);

      y -= 18 + METRICS_TITLE_MESSAGE_GAP;

      /* Message: single wrapped text field (question, then "keeping or
       * removing...", then the hint on separate lines).  Height was computed
       * up front so translations reflow and never clip. */
      messageField = [[NSTextField alloc] initWithFrame:
                       NSMakeRect(METRICS_TEXT_LEFT, y - mh,
                                  mw, mh)];
      [messageField setBackgroundColor: [NSColor windowBackgroundColor]];
      [messageField setBezeled: NO];
      [messageField setEditable: NO];
      [messageField setSelectable: NO];
      [messageField setFont: METRICS_FONT_SYSTEM_REGULAR_11];
      [[messageField cell] setWraps: YES];
      [[messageField cell] setLineBreakMode: NSLineBreakByWordWrapping];
      [messageField setStringValue: msg];
      [cv addSubview: messageField];
      RELEASE(messageField);

      y -= mh + METRICS_SPACE_8;

      /* Scrollable list with a per-item checkbox column, below the message */
      scroll = [[NSScrollView alloc] initWithFrame:
                 NSMakeRect(METRICS_TEXT_LEFT, y - listHeight,
                            cw - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN, listHeight)];
      [scroll setHasVerticalScroller: YES];
      [scroll setBorderType: NSBezelBorder];

      tableView = [[NSTableView alloc] initWithFrame: [scroll bounds]];

      checkColumn = [[NSTableColumn alloc] initWithIdentifier: @"check"];
      [checkColumn setWidth: 24];
      [checkColumn setResizingMask: NSTableColumnNoResizing];
      checkCell = [[NSButtonCell alloc] init];
      [checkCell setButtonType: NSSwitchButton];
      [checkCell setEditable: YES];
      [checkColumn setDataCell: checkCell];
      RELEASE(checkCell);
      [tableView addTableColumn: checkColumn];
      RELEASE(checkColumn);

      pathColumn = [[NSTableColumn alloc] initWithIdentifier: @"path"];
      [pathColumn setWidth: cw - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN - 24 - 20];
      [tableView addTableColumn: pathColumn];
      RELEASE(pathColumn);

      [tableView setDataSource: self];
      [tableView setDelegate: self];
      [tableView setHeaderView: nil];
      [scroll setDocumentView: tableView];
      RELEASE(tableView);
      [cv addSubview: scroll];
      RELEASE(scroll);

      /* Tooltip per row: a tracking rect for each row fires mouseEntered: as
       * the cursor moves between lines, so the description updates to match
       * the row currently hovered. */
      {
        NSMutableArray *tags = [NSMutableArray array];
        NSInteger nRows = [tableView numberOfRows];
        NSInteger r;
        for (r = 0; r < nRows; r++)
          {
            NSToolTipTag t = [tableView addToolTipRect: [tableView rectOfRow: r]
                                                 owner: self
                                              userData: NULL];
            [tags addObject: [NSNumber numberWithInteger: t]];
          }
        ASSIGN (toolTipTags, tags);
      }

      y -= listHeight + METRICS_SPACE_8;

      /* Label below the list: shows the well-known directory description of
       * the selected item when a row is clicked; empty until then. */
      infoLabel = [[NSTextField alloc] initWithFrame:
                    NSMakeRect(METRICS_TEXT_LEFT, y - 16,
                               cw - METRICS_TEXT_LEFT - METRICS_CONTENT_SIDE_MARGIN, 16)];
      [infoLabel setBackgroundColor: [NSColor windowBackgroundColor]];
      [infoLabel setBezeled: NO];
      [infoLabel setEditable: NO];
      [infoLabel setSelectable: NO];
      [infoLabel setFont: METRICS_FONT_SYSTEM_REGULAR_11];
      [infoLabel setTextColor: [NSColor secondaryLabelColor]];
      [infoLabel setStringValue: @""];
      [cv addSubview: infoLabel];
      RELEASE(infoLabel);

      y -= 16 + METRICS_SPACE_16;

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

/* NSTableView calls this when a switch button cell is toggled, so clicking a
 * checkbox updates our state instead of closing the dialog. */
- (void)tableView:(NSTableView *)aTableView
   setObjectValue:(id)anObject
   forTableColumn:(NSTableColumn *)aTableColumn
              row:(NSInteger)rowIndex
{
  if ([[aTableColumn identifier] isEqual: @"check"]
      && rowIndex >= 0 && rowIndex < [checked count])
    {
      [checked replaceObjectAtIndex: rowIndex
                         withObject: anObject];
    }
}

/* Returns the description for the well-known directory that owns the given
 * related-data path, or nil.  The path is something like
 * .../Library/Caches/<app>; find the first ancestor that has a description. */
+ (NSString *)descriptionForRelatedPath:(NSString *)path
{
  if (path == nil)
    return nil;

  NSString *p = [path stringByDeletingLastPathComponent];
  while (p && [p length] > 1)
    {
      NSString *desc = GSDirectoryDescriptionForPath(p);
      if (desc)
        return desc;
      p = [p stringByDeletingLastPathComponent];
    }
  return nil;
}

/* When the user clicks a row, show the well-known directory description of
 * that item in the label below the list.  Cleared when nothing is selected. */
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
  NSInteger row = [tableView selectedRow];
  if (row >= 0 && row < [paths count])
    {
      NSString *desc =
        [AppDataTrashDialog descriptionForRelatedPath: [paths objectAtIndex: row]];
      if (desc)
        {
          [infoLabel setStringValue: desc];
          return;
        }
    }
  [infoLabel setStringValue: @""];
}

/* GSToolTips owner: called for the tooltip rect added per row.  Maps the
 * tracking tag back to its row and returns that row's description. */
- (NSString *)view:(NSView *)view
 stringForToolTip:(NSToolTipTag)tag
            point:(NSPoint)point
         userData:(void *)data
{
  NSUInteger i;
  for (i = 0; i < [toolTipTags count]; i++)
    {
      if ([[toolTipTags objectAtIndex: i] integerValue] == tag)
        {
          if (i < [paths count])
            {
              NSString *desc =
                [AppDataTrashDialog descriptionForRelatedPath: [paths objectAtIndex: i]];
              if (desc)
                return desc;
            }
          break;
        }
    }
  return @"";
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
