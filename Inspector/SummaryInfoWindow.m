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

- (void)setLabelWriter:(id)writer
{
  _labelWriter = writer;
}

- (NSWindow *)window
{
  return _panel;
}

/* Label names as the Label menu and the Find window have them; the tag of a
 * pop-up item is the label number, -1 stands for Mixed. */
static NSArray *labelNames(void)
{
  return [NSArray arrayWithObjects: @"None", @"Red", @"Orange", @"Yellow",
                  @"Green", @"Blue", @"Purple", @"Grey", nil];
}

- (void)fillLabelPopUp
{
  NSInteger n = [_model commonLabel];
  NSArray *names = labelNames();
  NSUInteger i;

  [_labelPopUp removeAllItems];
  if (n < 0)
    {
      /* Mixed is shown, not offered: it is not a label to give. */
      [_labelPopUp addItemWithTitle: NSLocalizedString(@"Mixed", @"Value differs between the items")];
      [[_labelPopUp lastItem] setTag: -1];
    }
  for (i = 0; i < [names count]; i++)
    {
      [_labelPopUp addItemWithTitle: NSLocalizedString([names objectAtIndex: i], @"")];
      [[_labelPopUp lastItem] setTag: i];
    }
  [_labelPopUp selectItemAtIndex: n < 0 ? 0 : MIN(n, 7)];
}

- (void)labelChanged:(id)sender
{
  NSInteger label = [[_labelPopUp selectedItem] tag];
  NSUInteger failures;

  if (label < 0)
    {
      return;
    }
  failures = [_model applyLabel: label writer: _labelWriter];
  if (failures > 0)
    {
      NSRunAlertPanel(NSLocalizedString(@"Summary Info", @"Window title"),
                      NSLocalizedString(@"The label could not be set on %lu items.",
                                        @"Alert text after a failed label change"),
                      nil, nil, nil, (unsigned long)failures);
    }
  [self fillLabelPopUp];
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
  [self fillLabelPopUp];
  [_labelPopUp setEnabled: YES];
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

- (void)addControl:(NSControl *)control withCaption:(NSString *)caption y:(CGFloat *)y
{
  NSTextField *cap = makeText(METRICS_FONT_SYSTEM_BOLD_11, NSRightTextAlignment);
  NSView *content = [_panel contentView];
  CGFloat valueX = METRICS_CONTENT_SIDE_MARGIN + CAPTION_WIDTH + METRICS_SPACE_8;
  CGFloat h = METRICS_TEXT_INPUT_FIELD_HEIGHT;

  *y -= h;
  [cap setStringValue: caption];
  [cap setFrame: NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, *y + (h - LINE_HEIGHT) / 2 - 1,
                            CAPTION_WIDTH, LINE_HEIGHT)];
  [control setFrame: NSMakeRect(valueX, *y, 140.0, h)];
  [cap setAutoresizingMask: NSViewMinYMargin];
  [control setAutoresizingMask: NSViewMinYMargin];
  [content addSubview: cap];
  [content addSubview: control];
  [cap release];
  *y -= METRICS_SPACE_8;
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
    + (METRICS_TEXT_INPUT_FIELD_HEIGHT + METRICS_SPACE_8) /* label */
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
  _labelPopUp = [[NSPopUpButton alloc] initWithFrame: NSZeroRect pullsDown: NO];
  [_labelPopUp addItemWithTitle: NSLocalizedString(@"Calculating...", @"Size not known yet")];
  [_labelPopUp setTarget: self];
  [_labelPopUp setAction: @selector(labelChanged:)];
  /* Items are counted first; a label cannot be given before the walk is done. */
  [_labelPopUp setEnabled: NO];
  [self addControl: _labelPopUp withCaption: NSLocalizedString(@"Label:", @"Summary Info caption")
                 y: &y];
  [_labelPopUp release];
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
