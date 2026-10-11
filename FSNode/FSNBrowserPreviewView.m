/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#include <math.h>
#import <AppKit/AppKit.h>
#import "FSNBrowserPreviewView.h"
#import "FSNBrowser.h"
#import "FSNPreviewProvider.h"
#import "FSNIconPreview.h"
#import "FSNode.h"
#import "FSNFunctions.h"
#import "FSNTextCell.h"

/* Margins and gaps of the Gershwin appearance metrics (METRICS_SPACE_12,
 * METRICS_SPACE_8); FSNode does not link the theme that defines them. */
#define MARGIN 12.0
#define GAP 8.0
#define LABEL_GAP 6.0
/* A picture larger than this only costs memory: the column is rarely
 * wider. */
#define MAX_PICTURE 512.0
/* The small system font of the metrics (METRICS_FONT_SYSTEM_REGULAR_11). */
#define INFO_FONT_SIZE 11.0

/* The framework's own strings: the application cannot be expected to
 * translate what FSNode shows. */
#define localized(key, comment) \
  NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleForClass: [FSNode class]], comment)

@implementation FSNBrowserPreviewView

+ (NSArray *)infoRowsForNode:(FSNode *)anode
{
  NSDate *now = [NSDate date];
  NSString *size;

  if (anode == nil)
    {
      return [NSArray array];
    }

  /* The space the file takes on its disk, as the list view's size column
   * says it; a folder (a package) is not counted here, that would read the
   * whole package for one line. */
  size = [anode isDirectory] ? @"--"
    : FSNFinderSizeDescription (FSNAllocatedSizeOfPath ([anode path]), nil);

  return [NSArray arrayWithObjects:
    [NSArray arrayWithObjects: localized (@"Name:", @"Preview column"), [anode name], nil],
    [NSArray arrayWithObjects: localized (@"Kind:", @"Preview column"),
             [anode typeDescription] ? [anode typeDescription] : @"", nil],
    [NSArray arrayWithObjects: localized (@"Size:", @"Preview column"), size, nil],
    [NSArray arrayWithObjects: localized (@"Created:", @"Preview column"),
             FSNFinderDateDescription ([anode creationDate], now, NO, nil), nil],
    [NSArray arrayWithObjects: localized (@"Modified:", @"Preview column"),
             FSNFinderDateDescription ([anode modificationDate], now, NO, nil), nil],
    nil];
}

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];

  if (self)
    {
      infoFields = [NSMutableArray new];
      ASSIGN (backColor, [NSColor windowBackgroundColor]);
      pictureSize = NSZeroSize;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (node);
  RELEASE (providedView);
  RELEASE (iconView);
  RELEASE (infoFields);
  RELEASE (backColor);
  [super dealloc];
}

/* The values are FSNTextCells, which shorten a name that does not fit with
 * dots and drop a date's time before its year, as the list view does. */
- (NSTextField *)infoFieldWithString:(NSString *)str alignment:(NSTextAlignment)align
                               color:(NSColor *)color dateCell:(BOOL)isDate
{
  NSTextField *field = [[NSTextField alloc] initWithFrame: NSZeroRect];
  FSNTextCell *cell = [FSNTextCell new];

  [cell setDateCell: isDate];
  [field setCell: cell];
  RELEASE (cell);
  [field setStringValue: str];
  [field setEditable: NO];
  [field setSelectable: NO];
  [field setBezeled: NO];
  [field setBordered: NO];
  [field setDrawsBackground: NO];
  [field setAlignment: align];
  [field setFont: [NSFont systemFontOfSize: INFO_FONT_SIZE]];
  [field setTextColor: color];
  return AUTORELEASE (field);
}

- (NSRect)pictureFrame
{
  NSRect b = [self bounds];
  CGFloat side = MIN (NSWidth (b) - 2 * MARGIN, floor (NSHeight (b) * 0.5));

  side = floor (MIN (side, MAX_PICTURE));
  if (side < 0)
    {
      side = 0;
    }
  return NSMakeRect (floor ((NSWidth (b) - side) / 2),
                     NSHeight (b) - MARGIN - side, side, side);
}

/* Provider views are built for one frame and never resized again (the
 * content viewers lay out only when built), so a new size asks for a new
 * view. */
- (void)loadPicture
{
  NSRect pic = [self pictureFrame];
  id<FSNPreviewProvider> provider = [FSNBrowser previewProvider];

  [providedView removeFromSuperview];
  DESTROY (providedView);
  [iconView removeFromSuperview];
  DESTROY (iconView);
  pictureSize = pic.size;

  if (node == nil || NSWidth (pic) < 1)
    {
      return;
    }

  if (provider != nil)
    {
      NSView *v = [provider previewViewForPath: [node path] frame: pic];

      if (v != nil)
        {
          ASSIGN (providedView, v);
          [providedView setFrame: pic];
          [self addSubview: providedView];
          return;
        }
    }

  iconView = [[NSImageView alloc] initWithFrame: pic];
  [iconView setImageScaling: NSScaleProportionally];
  [iconView setImageFrameStyle: NSImageFrameNone];
  [iconView setEditable: NO];
  [iconView setImage: [FSNIconPreview iconForNode: node
                                             size: (int)NSWidth (pic)
                                     showsPreview: YES]];
  [self addSubview: iconView];
}

- (void)layoutInfo
{
  NSRect b = [self bounds];
  NSRect pic = [self pictureFrame];
  CGFloat lineh = ceil ([[NSFont systemFontOfSize: INFO_FONT_SIZE] defaultLineHeightForFont]) + 2;
  CGFloat inner = NSWidth (b) - 2 * MARGIN;
  NSFont *font = [NSFont systemFontOfSize: INFO_FONT_SIZE];
  CGFloat labelw = 0;
  CGFloat y = NSMinY (pic) - GAP - lineh;
  NSUInteger i;

  /* The labels take what the longest of them needs, the values the rest. */
  for (i = 0; i + 1 < [infoFields count]; i += 2)
    {
      labelw = MAX (labelw, ceil ([font widthOfString:
                                          [[infoFields objectAtIndex: i] stringValue]]) + 4);
    }
  labelw = MIN (labelw, floor (inner / 2));

  for (i = 0; i + 1 < [infoFields count]; i += 2)
    {
      [[infoFields objectAtIndex: i]
        setFrame: NSMakeRect (MARGIN, y, labelw, lineh)];
      [[infoFields objectAtIndex: i + 1]
        setFrame: NSMakeRect (MARGIN + labelw + LABEL_GAP, y,
                              MAX (0, inner - labelw - LABEL_GAP), lineh)];
      y -= lineh;
    }
}

- (void)showNode:(FSNode *)anode
{
  NSArray *rows;
  NSUInteger i;

  ASSIGN (node, anode);

  for (i = 0; i < [infoFields count]; i++)
    {
      [[infoFields objectAtIndex: i] removeFromSuperview];
    }
  [infoFields removeAllObjects];

  rows = [FSNBrowserPreviewView infoRowsForNode: node];
  for (i = 0; i < [rows count]; i++)
    {
      NSArray *row = [rows objectAtIndex: i];
      NSTextField *label = [self infoFieldWithString: [row objectAtIndex: 0]
                                           alignment: NSRightTextAlignment
                                               color: [NSColor disabledControlTextColor]
                                            dateCell: NO];
      NSTextField *value = [self infoFieldWithString: [row objectAtIndex: 1]
                                           alignment: NSLeftTextAlignment
                                               color: [NSColor controlTextColor]
                                            dateCell: (i >= 3)];  /* Created, Modified */

      [infoFields addObject: label];
      [infoFields addObject: value];
      [self addSubview: label];
      [self addSubview: value];
    }

  [self loadPicture];
  [self layoutInfo];
  [self setNeedsDisplay: YES];
}

- (FSNode *)node
{
  return node;
}

- (NSView *)providedView
{
  return providedView;
}

- (NSImage *)iconImage
{
  return [iconView image];
}

- (void)setBackgroundColor:(NSColor *)color
{
  ASSIGN (backColor, color);
  [self setNeedsDisplay: YES];
}

- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  if (NSEqualSizes ([self pictureFrame].size, pictureSize) == NO)
    {
      [self loadPicture];
    }
  else
    {
      [providedView setFrame: [self pictureFrame]];
      [iconView setFrame: [self pictureFrame]];
    }
  [self layoutInfo];
}

- (void)drawRect:(NSRect)rect
{
  [backColor set];
  NSRectFill (rect);
}

@end
