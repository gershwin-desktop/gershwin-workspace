/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "SummaryInfoWindow.h"
#import "SummaryInfoModel.h"
#import "FinderInfoModel.h"
#import "FSNodeRep.h"
#import "AppearanceMetrics.h"

#define WIN_WIDTH 360.0
#define ICON_SIDE 48.0
#define CAPTION_WIDTH 72.0
#define LINE_HEIGHT 17.0

/* Label names are the ones of the Finder Info pane, from the Inspector bundle. */
#define FI_(s) NSLocalizedStringFromTableInBundle(s, @"FinderInfo", \
  [NSBundle bundleForClass: [SummaryInfoWindow class]], @"")

/* Returns an owned field; the caller hands it to a superview and releases it. */
static NSTextField *makeText(NSFont *font, NSTextAlignment align)
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSZeroRect];

  [f setFont: font];
  [f setBezeled: NO];
  [f setDrawsBackground: NO];
  [f setEditable: NO];
  [f setSelectable: YES];
  [f setAlignment: align];
  return f;
}

@implementation SummaryInfoWindow

- (void)dealloc
{
  [_model cancel];
  [_model release];
  [_panel release];
  [super dealloc];
}

- (NSWindow *)window
{
  return _panel;
}

- (NSString *)labelDescription
{
  NSArray *names = [NSArray arrayWithObjects: @"None", @"Red", @"Orange",
                            @"Yellow", @"Green", @"Blue", @"Purple", @"Grey", nil];
  NSInteger n = [_model commonLabel];

  if (n < 0)
    {
      return NSLocalizedString(@"Mixed", @"Value differs between the items");
    }
  if ((NSUInteger)n >= [names count])
    {
      return @"-";
    }
  /* Same table as the Label menu and the Find window use. */
  return NSLocalizedString([names objectAtIndex: n], @"");
}

- (NSString *)kindsDescription
{
  NSDictionary *k = [_model kinds];
  NSMutableArray *lines = [NSMutableArray array];
  NSEnumerator *e = [[[k allKeys] sortedArrayUsingSelector: @selector(compare:)]
                      objectEnumerator];
  NSString *kind;

  while ((kind = [e nextObject]) != nil)
    {
      [lines addObject: [NSString stringWithFormat: @"%@: %@", kind,
                          [k objectForKey: kind]]];
    }
  return [lines componentsJoinedByString: @"\n"];
}

/* Called on the main thread when the background walk is done. */
- (void)modelDidFinish:(SummaryInfoModel *)model
{
  if (model != _model)
    {
      return;
    }
  [_sizeValue setStringValue:
     [SummaryInfoModel descriptionForByteCount: [model totalBytes]]];
  [_kindsValue setStringValue: [self kindsDescription]];
  [_labelValue setStringValue: [self labelDescription]];
  if ([model supportsLocking])
    {
      NSString *s = NSLocalizedString(@"No", @"Locked: no");

      if ([model lockedState] == SummaryStateAll)
        {
          s = NSLocalizedString(@"Yes", @"Locked: yes");
        }
      else if ([model lockedState] == SummaryStateMixed)
        {
          s = NSLocalizedString(@"Mixed", @"Value differs between the items");
        }
      [_lockedValue setStringValue: s];
    }
}

- (NSTextField *)addRowWithCaption:(NSString *)caption
                              value:(NSString *)value
                                  y:(CGFloat *)y
                             height:(CGFloat)h
{
  NSTextField *cap = makeText(METRICS_FONT_SYSTEM_BOLD_11, NSRightTextAlignment);
  NSTextField *val = makeText(METRICS_FONT_SYSTEM_REGULAR_11, NSLeftTextAlignment);
  NSView *content = [_panel contentView];
  CGFloat valueX = METRICS_CONTENT_SIDE_MARGIN + CAPTION_WIDTH + METRICS_SPACE_8;

  *y -= h;
  [cap setStringValue: caption];
  [cap setFrame: NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, *y + h - LINE_HEIGHT, CAPTION_WIDTH, LINE_HEIGHT)];
  [val setStringValue: value];
  [val setFrame: NSMakeRect(valueX, *y, WIN_WIDTH - valueX - METRICS_CONTENT_SIDE_MARGIN, h)];
  [[val cell] setWraps: YES];
  /* Rows hang from the top, so they keep their distance when resized. */
  [cap setAutoresizingMask: NSViewMinYMargin];
  [val setAutoresizingMask: NSViewMinYMargin | NSViewWidthSizable];
  [content addSubview: cap];
  [content addSubview: val];
  [cap release];
  [val release];
  *y -= METRICS_SPACE_8;
  return val;
}

/* The kinds are only known after the walk; the extensions give the number of
 * lines up front so the window does not have to grow afterwards. */
- (NSUInteger)estimatedKindLinesForPaths:(NSArray *)paths
{
  NSMutableSet *kinds = [NSMutableSet set];
  NSEnumerator *e = [paths objectEnumerator];
  NSString *p;

  while ((p = [e nextObject]) != nil)
    {
      BOOL d = NO;

      [[NSFileManager defaultManager] fileExistsAtPath: p isDirectory: &d];
      [kinds addObject: d ? @"/" : [[p pathExtension] lowercaseString]];
    }
  return [kinds count];
}

- (void)showForPaths:(NSArray *)paths
{
  BOOL locking = [FinderInfoModel supportsLocking];
  NSUInteger kindLines = [self estimatedKindLinesForPaths: paths];
  CGFloat kindsHeight = kindLines * LINE_HEIGHT;
  CGFloat height = METRICS_CONTENT_TOP_MARGIN + ICON_SIDE + METRICS_SPACE_16
    + 2 * (LINE_HEIGHT + METRICS_SPACE_8)            /* items, size */
    + kindsHeight + METRICS_SPACE_8                  /* kinds */
    + (LINE_HEIGHT + METRICS_SPACE_8)                /* label */
    + (locking ? LINE_HEIGHT + METRICS_SPACE_8 : 0)
    + METRICS_CONTENT_BOTTOM_MARGIN - METRICS_SPACE_8;
  CGFloat y = height - METRICS_CONTENT_TOP_MARGIN;
  CGFloat textX = METRICS_CONTENT_SIDE_MARGIN + ICON_SIDE + METRICS_SPACE_12;
  NSView *content;
  NSString *itemsText;

  [_model cancel];
  [_model release];
  _model = [[SummaryInfoModel alloc] initWithPaths: paths];
  [_panel release];

  _panel = [[NSPanel alloc]
             initWithContentRect: NSMakeRect(0, 0, WIN_WIDTH, height)
                       styleMask: NSTitledWindowMask | NSClosableWindowMask
                         backing: NSBackingStoreBuffered
                           defer: NO];
  [_panel setTitle: NSLocalizedString(@"Summary Info", @"Window title")];
  [_panel setReleasedWhenClosed: NO];
  content = [_panel contentView];

  itemsText = [NSString stringWithFormat:
                 NSLocalizedString(@"%lu items", @"Number of selected items"),
                 (unsigned long)[paths count]];

  _iconView = [[NSImageView alloc] initWithFrame:
                 NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y - ICON_SIDE,
                            ICON_SIDE, ICON_SIDE)];
  [_iconView setImage: [[FSNodeRep sharedInstance]
                         multipleSelectionIconOfSize: (int)ICON_SIDE]];
  [_iconView setAutoresizingMask: NSViewMinYMargin];
  [content addSubview: _iconView];
  [_iconView release];

  _titleField = makeText(METRICS_FONT_SYSTEM_BOLD_13, NSLeftTextAlignment);
  [_titleField setSelectable: NO];
  [_titleField setStringValue: itemsText];
  [_titleField setFrame: NSMakeRect(textX, y - ICON_SIDE / 2 - LINE_HEIGHT / 2,
                                    WIN_WIDTH - textX - METRICS_CONTENT_SIDE_MARGIN,
                                    LINE_HEIGHT + 2)];
  [_titleField setAutoresizingMask: NSViewMinYMargin | NSViewWidthSizable];
  [content addSubview: _titleField];
  [_titleField release];

  y -= ICON_SIDE + METRICS_SPACE_16;
  _itemsValue = [self addRowWithCaption: NSLocalizedString(@"Items:", @"Summary Info caption")
                                  value: itemsText y: &y height: LINE_HEIGHT];
  _sizeValue = [self addRowWithCaption: NSLocalizedString(@"Size:", @"Summary Info caption")
                                 value: NSLocalizedString(@"Calculating...", @"Size not known yet")
                                     y: &y height: LINE_HEIGHT];
  _kindsValue = [self addRowWithCaption: NSLocalizedString(@"Kinds:", @"Summary Info caption")
                                  value: @"" y: &y height: kindsHeight];
  _labelValue = [self addRowWithCaption: NSLocalizedString(@"Label:", @"Summary Info caption")
                                  value: @"" y: &y height: LINE_HEIGHT];
  if (locking)
    {
      _lockedValue = [self addRowWithCaption: NSLocalizedString(@"Locked:", @"Summary Info caption")
                                       value: @"" y: &y height: LINE_HEIGHT];
    }

  [_panel center];
  [_panel makeKeyAndOrderFront: nil];
  [_model startInBackgroundNotifying: self selector: @selector(modelDidFinish:)];
}

@end
