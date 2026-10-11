/* FSNTextCell.m
 *
 * Copyright (C) 2004-2021 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale <enrico@imago.ro>
 *          Riccardo Mottola <rm@gnu.org>
 * Date: March 2004
 *
 * This file is part of the GNUstep FSNode framework
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNTextCell.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"
#import "FSNodeRep.h"


@implementation FSNTextCell

- (void)dealloc
{
  RELEASE (uncutTitle);
  RELEASE (fittedTitle);
  RELEASE (fittedResult);
  RELEASE (fontAttr);
  RELEASE (dots);
  RELEASE (icon);
  RELEASE (displayIcon);
  RELEASE (tagColor);
  RELEASE (nodePath);
  [super dealloc];
}

/*
 * Build an icon image with the label coloured dot composited
 * directly onto it. Because the badge is part of the image
 * pixels it can never be obscured by selection highlights
 * or any later drawing.
 */
- (void)rebuildDisplayIcon
{
  DESTROY (displayIcon);

  if (icon == nil)
    return;

  if (tagColor == nil)
    {
      displayIcon = [icon retain];
      return;
    }

  NSSize sz = [icon size];
  displayIcon = [[NSImage alloc] initWithSize: sz];
  [displayIcon lockFocus];
  [icon compositeToPoint: NSZeroPoint operation: NSCompositeSourceOver];

  CGFloat dotSize = (sz.width >= 48) ? 10.0 : 8.0;
  CGFloat dotMargin = 2.0;
  CGFloat dotTop = (sz.width >= 48) ? dotMargin : 12.0;
  NSRect dotRect = NSMakeRect(sz.width - dotSize - dotMargin,
                               dotTop, dotSize, dotSize);

  FSNDrawLabelDot(dotRect, tagColor);

  [displayIcon unlockFocus];
}

- (id)init
{
  self = [super init];

  if (self)
    {
      ASSIGN (fontAttr, [NSDictionary dictionaryWithObject: [self font]
					      forKey: NSFontAttributeName]);
      ASSIGN (dots, @"...");
      titlesize = NSMakeSize(0, 0);
      icon = nil;
      displayIcon = nil;
      dateCell = NO;
    }

  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  FSNTextCell *c = [super copyWithZone: zone];

  c->fontAttr = [fontAttr copyWithZone: zone];
  c->dots = [dots copyWithZone: zone];

  c->dateCell = dateCell;

  if (uncutTitle) {
    c->uncutTitle = [uncutTitle copyWithZone: zone];
  } else {
    c->uncutTitle = nil;
  }

  /* The copy shares the pointers without owning them. */
  c->fittedTitle = nil;
  c->fittedResult = nil;

  c->icon = [icon retain];
  c->displayIcon = [displayIcon retain];
  c->tagColor = [tagColor retain];
  c->nodePath = [nodePath retain];
  c->tagColorLookedUp = tagColorLookedUp;

  return c;
}

- (void)setStringValue:(NSString *)aString
{
  [super setStringValue: aString];
  titlesize = [[self stringValue] sizeWithAttributes: fontAttr];
}

- (void)setFont:(NSFont *)fontObj
{
  [super setFont: fontObj];
  ASSIGN (fontAttr, [NSDictionary dictionaryWithObject: [self font]
                                                forKey: NSFontAttributeName]);
  titlesize = [[self stringValue] sizeWithAttributes: fontAttr];
  DESTROY (fittedTitle);
}

- (void)setIcon:(NSImage *)icn
{
  ASSIGN (icon, icn);
  [self rebuildDisplayIcon];
}

- (NSImage *)icon
{
  return icon;
}

- (void)setTagColor:(NSColor *)color
{
  ASSIGN (tagColor, color);
  [self rebuildDisplayIcon];
}

- (NSColor *)tagColor
{
  return tagColor;
}

- (void)setNodePath:(NSString *)path
{
  /* A row's cell is reused across many draws with the same path; only a
   * real path change invalidates the "already looked up" state below. */
  if ([nodePath isEqualToString: path] == NO)
    {
      tagColorLookedUp = NO;
    }
  ASSIGN (nodePath, path);
}

- (float)uncutTitleLenght
{
  return titlesize.width;
}

- (void)setDateCell:(BOOL)value
{
  dateCell = value;
}

- (BOOL)isDateCell
{
  return dateCell;
}

- (NSString *)cutTitle:(NSString *)title
            toFitWidth:(float)width
{
  int tl = [title length];

  if (tl <= 5)
    {
      return dots;
    }
  else
    {
      int fpto = (tl / 2) - 2;
      int spfr = fpto + 3;
      NSString *fp = [title substringToIndex: fpto];
      NSString *sp = [title substringFromIndex: spfr];
      NSString *dotted = [NSString stringWithFormat: @"%@%@%@", fp, dots, sp];
      int dl = [dotted length];
      float dotl = [dotted sizeWithAttributes: fontAttr].width;
      int p = 0;

      while (dotl > width) {
        if (dl <= 5) {
          return dots;
        }

        if (p) {
          fpto--;
        } else {
          spfr++;
        }
        p = !p;

        fp = [title substringToIndex: fpto];
        sp = [title substringFromIndex: spfr];
        dotted = [NSString stringWithFormat: @"%@%@%@", fp, dots, sp];
        dotl = [dotted sizeWithAttributes: fontAttr].width;
        dl = [dotted length];
      }

      return dotted;
    }

  return title;
}

/* The date text without its time: "08.10.2026 09:30" -> "08.10.2026",
 * "1/9/26 9:30 AM" -> "1/9/26", "Heute, 09:51" -> "Heute".  nil when the
 * text has no time. */
static NSString *
dateWithoutTime(NSString *title)
{
  NSMutableArray *words = [[[title componentsSeparatedByString: @" "] mutableCopy] autorelease];
  NSString *last = [words lastObject];

  if ([last length] && [last rangeOfString: @":"].location == NSNotFound
      && [words count] > 2)
    {
      /* An AM/PM marker follows the clock time. */
      [words removeLastObject];
      last = [words lastObject];
    }
  if ([words count] < 2 || [last rangeOfString: @":"].location == NSNotFound)
    {
      return nil;
    }
  [words removeLastObject];

  title = [words componentsJoinedByString: @" "];
  while ([title hasSuffix: @","])
    {
      title = [title substringToIndex: [title length] - 1];
    }
  return title;
}

/* "08.10.2026" -> "08.10.26": the four digit year of a numeric date as two. */
static NSString *
dateWithShortYear(NSString *date)
{
  NSUInteger i, n = [date length];

  for (i = 0; i + 4 <= n; i++)
    {
      NSRange r = NSMakeRange (i, 4);
      NSString *year = [date substringWithRange: r];
      BOOL digits = [[year stringByTrimmingCharactersInSet:
                       [NSCharacterSet decimalDigitCharacterSet]] length] == 0;
      BOOL edges = (i == 0 || ![[NSCharacterSet decimalDigitCharacterSet]
                                 characterIsMember: [date characterAtIndex: i - 1]])
                   && (i + 4 == n || ![[NSCharacterSet decimalDigitCharacterSet]
                                        characterIsMember: [date characterAtIndex: i + 4]]);

      if (digits && edges && i > 0)
        {
          return [date stringByReplacingCharactersInRange: r
                                               withString: [year substringFromIndex: 2]];
        }
    }
  return nil;
}

- (NSString *)cutDateTitle:(NSString *)title
                toFitWidth:(float)width
{
  NSString *candidate = dateWithoutTime (title);
  NSString *shorter;

  /* Finder drops the time before anything else of a date, then shows the
   * numeric short date; only when even that does not fit is it dotted. */
  if (candidate && [candidate sizeWithAttributes: fontAttr].width <= width)
    {
      return candidate;
    }
  if (candidate == nil)
    {
      candidate = title;
    }
  shorter = dateWithShortYear (candidate);
  if (shorter && [shorter sizeWithAttributes: fontAttr].width <= width)
    {
      return shorter;
    }
  return [self cutTitle: (shorter ? shorter : candidate) toFitWidth: width];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame
                       inView:(NSView *)controlView
{
  NSRect title_rect = cellFrame;
  CGFloat textlength;
  NSString *cutTitle;

#define LEFT_MARGIN (2.0)
#define ICON_TEXT_SPACING (8.0)

  textlength = title_rect.size.width - LEFT_MARGIN;
  if (icon)
    textlength -= ([icon size].width + ICON_TEXT_SPACING);

  ASSIGN (uncutTitle, [self stringValue]);

  /* Measuring and shortening a title lays out its text several times over,
   * and an icon view redraws its labels many times a second while icons are
   * dragged across it.  The outcome only changes with the title, the width
   * or the font. */
  if (fittedTitle == nil || fittedWidth != textlength
      || [fittedTitle isEqualToString: uncutTitle] == NO)
    {
      NSString *fitted = nil;

      /* Measured here too: a table view hands its cells their text through
       * -setObjectValue:, past -setStringValue:, and a title never measured
       * was drawn in a box of no height. */
      titlesize = [uncutTitle sizeWithAttributes: fontAttr];
      if (titlesize.width > textlength)
        {
          if (dateCell)
            fitted = [self cutDateTitle: uncutTitle toFitWidth: textlength];
          else
            fitted = [self cutTitle: uncutTitle toFitWidth: textlength];
        }
      ASSIGN (fittedTitle, uncutTitle);
      ASSIGN (fittedResult, fitted);
      fittedWidth = textlength;
    }

  /* Straight to NSCell: the title size kept here is that of the whole
   * title, and measuring the shortened one only to throw it away is what
   * this avoids. */
  cutTitle = fittedResult;
  if (cutTitle)
    [super setStringValue: cutTitle];

  title_rect.size.height = titlesize.height;
  title_rect.origin.y += ((cellFrame.size.height - titlesize.height) / 2.0);

  if (icon == nil) {
    [super drawInteriorWithFrame: title_rect inView: controlView];
  } else {
    NSRect icon_rect;

    icon_rect.origin = cellFrame.origin;
    icon_rect.size = [icon size];
    icon_rect.origin.x += LEFT_MARGIN;
    icon_rect.origin.y += ((cellFrame.size.height - icon_rect.size.height) / 2.0);
    if ([controlView isFlipped]) {
      icon_rect.origin.y += icon_rect.size.height;
    }

    title_rect.origin.x += (icon_rect.size.width + ICON_TEXT_SPACING);
    title_rect.size.width -= (icon_rect.size.width + ICON_TEXT_SPACING);
    title_rect = NSIntegralRect(title_rect);

    [super drawInteriorWithFrame: title_rect inView: controlView];

    /* Lazily load tag colour from the metadata provider, but only once per
     * nodePath: "no label" (the common case) must not be re-queried on
     * every redraw of the same row. */
    if (tagColor == nil && nodePath != nil && tagColorLookedUp == NO)
      {
        NSColor *color = [[[FSNodeRep sharedInstance] metadataProvider]
                           labelColorForPath: nodePath];
        tagColorLookedUp = YES;
        if (color)
          [self setTagColor: color];
      }

    /* Draw the (possibly badged) icon. If a label is set the icon
     * already has the badge baked into its pixels. */
    [displayIcon compositeToPoint: icon_rect.origin
			operation: NSCompositeSourceOver];
  }

  /* we reset the title to the orginal string */
  if (cutTitle)
    [super setStringValue: uncutTitle];
}

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
  return NO;
}

@end
