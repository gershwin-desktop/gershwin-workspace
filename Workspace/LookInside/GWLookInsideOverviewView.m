/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <GNUstepBase/GNUstep.h>

#import "GWLookInsideOverviewView.h"
#import "GWLookInsideGeometry.h"
#import "GWLookInsidePreviewKind.h"
#import "GWLookInsidePreviewView.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "AppearanceMetrics.h"

/* Room under each picture for the item's name. */
static const CGFloat kNameHeight = 16.0;

@implementation GWLookInsideOverviewView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self != nil)
    {
      _pictures = [NSMutableDictionary new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_paths);
  RELEASE(_pictures);
  [super dealloc];
}

- (BOOL)isOpaque
{
  return YES;
}

- (void)setPaths:(NSArray *)paths
{
  ASSIGN(_paths, paths);
  [_pictures removeAllObjects];
  _highlightedIndex = 0;
  [self setNeedsDisplay: YES];
}

- (void)setHighlightedIndex:(NSUInteger)index
{
  _highlightedIndex = index;
  [self setNeedsDisplay: YES];
}

- (NSUInteger)highlightedIndex
{
  return _highlightedIndex;
}

- (void)setTarget:(id)target
{
  _target = target;
}

- (void)setAction:(SEL)action
{
  _action = action;
}

/* The image itself for pictures, the icon for everything else, at the
 * size of the cell, so the overview shows what the preview would. */
- (NSImage *)pictureAtIndex:(NSUInteger)index side:(CGFloat)side
{
  NSNumber *key = [NSNumber numberWithUnsignedInteger: index];
  NSImage *picture = [_pictures objectForKey: key];

  if (picture == nil)
    {
      NSString *path = [_paths objectAtIndex: index];
      FSNode *node = [FSNode nodeWithPath: path];

      if (GWLookInsidePreviewKindForPath(path, [GWLookInsidePreviewView imageExtensions],
                                         [node isPackage]) == GWLookInsidePreviewKindImage)
        {
          picture = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
        }
      if (picture == nil)
        {
          picture = [[FSNodeRep sharedInstance] iconOfSize: (int)MIN(side, GWLookInsideIconMaximumSide)
                                                    forNode: node];
        }
      if (picture != nil)
        {
          [_pictures setObject: picture forKey: key];
        }
    }
  return picture;
}

static NSRect
FitRect(NSSize size, NSRect room)
{
  CGFloat scale;

  if (size.width <= 0 || size.height <= 0)
    {
      return NSZeroRect;
    }
  scale = MIN(1.0, MIN(room.size.width / size.width, room.size.height / size.height));
  size.width = floor(size.width * scale);
  size.height = floor(size.height * scale);
  return NSMakeRect(floor(NSMidX(room) - size.width / 2), floor(NSMidY(room) - size.height / 2),
                    size.width, size.height);
}

- (void)drawRect:(NSRect)rect
{
  NSRect bounds = [self bounds];
  NSUInteger count = [_paths count], i;
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle new] autorelease];
  NSDictionary *attrs;

  [[NSColor controlBackgroundColor] set];
  NSRectFill(rect);

  [style setAlignment: NSCenterTextAlignment];
  [style setLineBreakMode: NSLineBreakByTruncatingMiddle];
  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    METRICS_FONT_SYSTEM_REGULAR_11, NSFontAttributeName,
    [NSColor controlTextColor], NSForegroundColorAttributeName,
    style, NSParagraphStyleAttributeName, nil];

  for (i = 0; i < count; i++)
    {
      NSRect cell = GWLookInsideOverviewCellRect(bounds, count, i);
      NSRect nameRect = NSMakeRect(NSMinX(cell), NSMinY(cell), NSWidth(cell), kNameHeight);
      NSRect pictureRoom = NSMakeRect(NSMinX(cell), NSMinY(cell) + kNameHeight,
                                      NSWidth(cell), NSHeight(cell) - kNameHeight);
      NSImage *picture;

      if (!NSIntersectsRect(cell, rect) || NSHeight(pictureRoom) <= 0)
        {
          continue;
        }

      if (i == _highlightedIndex)
        {
          [[NSColor selectedControlColor] set];
          [[NSBezierPath bezierPathWithRoundedRect: NSInsetRect(cell, -4, -4)
                                           xRadius: 6
                                           yRadius: 6] fill];
        }

      picture = [self pictureAtIndex: i side: NSHeight(pictureRoom)];
      if (picture != nil)
        {
          [picture drawInRect: FitRect([picture size], NSInsetRect(pictureRoom, 4, 4))
                     fromRect: NSZeroRect
                    operation: NSCompositeSourceOver
                     fraction: 1.0];
        }
      [[[_paths objectAtIndex: i] lastPathComponent] drawInRect: nameRect withAttributes: attrs];
    }
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSInteger index = GWLookInsideOverviewIndexAtPoint([self bounds], [_paths count], p);

  if (index >= 0)
    {
      [self setHighlightedIndex: (NSUInteger)index];
      [NSApp sendAction: _action to: _target from: self];
    }
}

@end
