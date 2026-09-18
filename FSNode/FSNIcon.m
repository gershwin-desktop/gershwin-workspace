/* FSNIcon.m
 *
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
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

#include <math.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "FSNIcon.h"
#import "FSNTextCell.h"
#import "FSNode.h"
#import "FSNFunctions.h"
#import "FSNIconDragSession.h"
#import "FSNMetadataProvider.h"
#import "FSNIconPlacement.h"
#import "FSNIconsView.h"

/* Private extension for FSNIcon */
@interface FSNIcon (Private)
- (void)loadLabelColorFromMetadata;
@end

/* Forward declaration for batch repositioning called on container (FSNIconsView) */
@interface NSView (FSNIconContainerMethods)
- (void)batchRepositionIcons:(NSArray *)icons toCenterPoints:(NSArray *)points;
- (BOOL)foreignWindowIsUnderPointer;
@end

/* Forward declaration to expose class methods used for ISO drop handling */
@interface ISOWriteHandler : NSObject
+ (BOOL)canHandleISODrop:(NSString *)path ontoNode:(FSNode *)node;
+ (BOOL)handleISODrop:(NSString *)path ontoNode:(FSNode *)node;
/* Return nil if the drop is valid and will be handled, otherwise an explanatory
   message describing why the ISO drop would be rejected. */
+ (NSString *)validationMessageForISODrop:(NSString *)path ontoNode:(FSNode *)node;
@end

#define BRANCH_SIZE 7
#define ARROW_ORIGIN_X (BRANCH_SIZE + 4)

#define DOUBLE_CLICK_LIMIT  300
#define EDIT_CLICK_LIMIT   1000

/* we redefine the dockstyle to read the preferences without including Dock.h" */
typedef enum DockStyle
{
  DockStyleClassic = 0,
  DockStyleModern = 1
} DockStyle;

static id <DesktopApplication> desktopApp = nil;

static NSImage *branchImage;

/* The file operation a negotiated drag operation stands for. */
static NSString *FSNOperationForDragMask(NSDragOperation op)
{
  switch (op)
    {
      case NSDragOperationMove:
	return NSWorkspaceMoveOperation;
      case NSDragOperationLink:
	return FSNLinkDropOperation();
      case NSDragOperationCopy:
      default:
	return NSWorkspaceCopyOperation;
    }
}

/* The rect grown to whole pixels of its window, whose base coordinates are
 * device pixels.  At a fractional scale factor a rect's edge can fall inside
 * a pixel, and a redraw clipped there blends that pixel row half old, half
 * new: a line is left across whatever the edge cut through. */
static NSRect FSNPixelAlignedRect(NSView *view, NSRect r)
{
  NSRect w = NSIntegralRect([view convertRect: r toView: nil]);

  return [view convertRect: w fromView: nil];
}

/* Redraws part of an icon view right away.  A moving icon has to show up
 * under the pointer before the next mouse-moved event is read, and the drag
 * loop does not return to the run loop that would otherwise redraw it. */
static void FSNRedrawContainerRect(NSView *container, NSRect dirty)
{
  if (container == nil || NSIsEmptyRect(dirty))
    return;

  [container setNeedsDisplayInRect: FSNPixelAlignedRect(container, dirty)];
  [container displayIfNeeded];
}

/* Asking the window server what lies under the pointer costs several
 * synchronous round trips, and motion arrives far faster than that: asking
 * for every event alone makes a drag stutter.  Ten times a second is soon
 * enough to notice the pointer reaching another application's window, and in
 * between the last answer stands.  The answer is dropped when a drag starts
 * so that no gesture begins on one left over from the previous one. */
static NSTimeInterval foreignCheckTime = 0.0;
static BOOL foreignCheckAnswer = NO;

/* Drawing faster than the screen refreshes shows nothing more, and a mouse
 * reports its position up to a thousand times a second: redrawing the icons
 * for every report is what kept a drag from keeping up with the pointer. */
static const NSTimeInterval FSNMoveFrameInterval = 1.0 / 60.0;

static void FSNForgetForeignWindowAnswer(void)
{
  foreignCheckTime = 0.0;
  foreignCheckAnswer = NO;
}

@implementation FSNIcon

@synthesize placementData = _placementData;

- (void)dealloc
{
  /* Drop pending loader items referencing self before anything else. */
  [[FSNIconLoader sharedLoader] cancelClient: self];

  if (trectTag != -1)
    {
      [self removeTrackingRect: trectTag];
    }
  /* Stop watching and drop the badge observer BEFORE releasing node: both
   * stopWatchingCurrentNode and gitBadgeCountChanged: dereference self.node,
   * so releasing it first would be a use-after-free on every git-repo icon's
   * deallocation (i.e. when a viewer showing such icons is closed). */
  [self stopWatchingCurrentNode];
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  RELEASE (node);
  RELEASE (hostname);
  RELEASE (selection);
  RELEASE (selectionTitle);
  RELEASE (extInfoType);
  RELEASE (icon);
  RELEASE (selectedicon);
  RELEASE (highlightPath);
  RELEASE (label);
  RELEASE (infolabel);
  RELEASE (labelFrameColor);
  RELEASE (tagColor);
  RELEASE (spotlightComment);
  RELEASE (_placementData);
  RELEASE (draggedLook);
  [super dealloc];
}

+ (void)initialize
{
  static BOOL initialized = NO;

  if (initialized == NO)
    {
      if (desktopApp == nil)
        {
          NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
          NSString *appName = [defaults stringForKey: @"DesktopApplicationName"];
          NSString *selName = [defaults stringForKey: @"DesktopApplicationSelName"];

          if (appName && selName)
            {
              Class desktopAppClass = [[NSBundle mainBundle] classNamed: appName];
              SEL sel = NSSelectorFromString(selName);
              desktopApp = [desktopAppClass performSelector: sel];
            }
        }

      branchImage = [NSBrowserCell branchImage];
      initialized = YES;
    }
}

+ (NSImage *)branchImage
{
  return branchImage;
}

/* we try to find a good host name.
 * We try to find something different from localhost, if possibile without dots,
 * else the first part of the qualified hostname gets taken */
+ (NSString *)getBestHostName
{
  NSHost *host = [NSHost currentHost];
  NSString *hname;
  NSRange range;
  NSArray *hnames;

  hnames = [host names];
  if ([hnames count] > 0)
    {
      hname = [hnames objectAtIndex:0];

      if ([hnames count] > 1)
        {
          NSUInteger i;

          for (i = 0; i < [hnames count]; i++)
            {
              NSString *better;

              better = [hnames objectAtIndex:i];
              if (![better isEqualToString:@"localhost"])
                {
                  if ([hname isEqualToString:@"localhost"] || [hname isEqualToString:@"127.0.0.1"])
                    hname = better;
                  else if ([better rangeOfString:@"."].location == NSNotFound)
                    hname = better;
                }
            }
        }

      range = [hname rangeOfString: @"."];
      if (range.length != 0)
        hname = [hname substringToIndex: range.location];
    }
  else
    {
      hname = @"unknown";
    }
  return hname;
}

- (NSString*) description
{
  NSString *s;

  s = [super description];
  s = [s stringByAppendingString:@" {"];
  s = [s stringByAppendingString:[node path]];
  if ([node isMountPoint])
    s = [s stringByAppendingString:@" isMountPoint "];
  if (_placementData)
    s = [s stringByAppendingString: [NSString stringWithFormat:@" mode:%lu iloc:(%.0f,%.0f)",
                (unsigned long)_placementData.placementMode,
                _placementData.ilocPosition.x,
                _placementData.ilocPosition.y]];
  s = [s stringByAppendingString:@" }"];
  return s;
}

- (id)initForNode:(FSNode *)anode
     nodeInfoType:(FSNInfoType)type
     extendedType:(NSString *)exttype
         iconSize:(int)isize
     iconPosition:(NSUInteger)ipos
        labelFont:(NSFont *)lfont
        textColor:(NSColor *)tcolor
        gridIndex:(NSUInteger)gindex
        dndSource:(BOOL)dndsrc
        acceptDnd:(BOOL)dndaccept
        slideBack:(BOOL)slback
{
  self = [super init];

  if (self)
    {
      NSFontManager *fmanager = [NSFontManager sharedFontManager];
      NSFont *infoFont;
      NSRect r = NSZeroRect;
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

      fsnodeRep = [FSNodeRep sharedInstance];

      iconSize = isize;
      icnBounds = NSMakeRect(0, 0, iconSize, iconSize);
      icnPoint = NSZeroPoint;
      brImgBounds = NSMakeRect(0, 0, BRANCH_SIZE, BRANCH_SIZE);

      ASSIGN (node, anode);
      selection = nil;
      selectionTitle = nil;

      /* The icon image loads later via -decorate (FSNIconLoader): a large
       * directory must not pay the icon pipeline per icon at fill time. */
      icon = nil;
      drawicon = nil;
      decorated = NO;
      selectedicon = nil;

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector (gitBadgeCountChanged:)
               name: FSNBadgeCountDidChangeNotification
             object: nil];
      [self updateBadgeCount];
      [self startWatchingCurrentNode];

      /* Initialize placement data */
      _placementData = [[FSNIconItemData alloc] init];
      [_placementData setFilename: [anode name]];

      /* Load Finder label color eagerly from the metadata provider */
      ASSIGN (tagColor,
              [[[FSNodeRep sharedInstance] metadataProvider]
                labelColorForPath: [anode path]]);

      dndSource = dndsrc;
      acceptDnd = dndaccept;
      slideBack = slback;

      selectable = YES;
      isLeaf = YES;

      hlightRect = NSZeroRect;
      hlightRect.size.width = iconSize + 6;
      hlightRect.size.height = hlightRect.size.width;
      hlightRect = NSIntegralRect(hlightRect);
      ASSIGN (highlightPath, [fsnodeRep highlightPathOfSize: hlightRect.size]);

      if ([[node path] isEqual: path_separator()] && ([node isMountPoint] == NO))
	{
	  NSString *hname;

	  hname = [FSNIcon getBestHostName];
	  ASSIGN (hostname, hname);
	}

      label = [FSNTextCell new];
      [label setFont: lfont];
      [label setTextColor: tcolor];

      infoFont = [fmanager convertFont: lfont
				toSize: ([lfont pointSize] - 2)];
      infoFont = [fmanager convertFont: infoFont
			   toHaveTrait: NSItalicFontMask];

      infolabel = [FSNTextCell new];
      [infolabel setFont: infoFont];
      [infolabel setTextColor: tcolor];

      if (exttype)
	{
	  [self setExtendedShowType: exttype];
	}
      else
	{
	  [self setNodeInfoShowType: type];
	}

      labelRect = NSZeroRect;
      labelRect.size.width = [label uncutTitleLenght] + [fsnodeRep labelMargin];
      labelRect.size.height = [fsnodeRep heightOfFont: [label font]];
      labelRect = NSIntegralRect(labelRect);

      infoRect = NSZeroRect;
      if ((showType != FSNInfoNameType) && [[infolabel stringValue] length])
	{
	  infoRect.size.width = [infolabel uncutTitleLenght] + [fsnodeRep labelMargin];
	}
      else
	{
	  infoRect.size.width = labelRect.size.width;
	}
      infoRect.size.height = [fsnodeRep heightOfFont: [infolabel font]];
      infoRect = NSIntegralRect(infoRect);

      icnPosition = ipos;
      gridIndex = gindex;

      if (icnPosition == NSImageLeft)
	{
	  [label setAlignment: NSLeftTextAlignment];
	  [infolabel setAlignment: NSLeftTextAlignment];

	  r.size.width = hlightRect.size.width + labelRect.size.width;
	  r.size.height = hlightRect.size.height;

	  if (showType != FSNInfoNameType)
	    {
	      float lbsh = labelRect.size.height + infoRect.size.height;

	      if (lbsh > hlightRect.size.height)
		{
		  r.size.height = lbsh;
		}
	    }

	}
      else if (icnPosition == NSImageAbove)
	{
	  [label setAlignment: NSCenterTextAlignment];
	  [infolabel setAlignment: NSCenterTextAlignment];

	  if (labelRect.size.width > hlightRect.size.width)
	    {
	      r.size.width = labelRect.size.width;
	    }
	  else
	    {
	      r.size.width = hlightRect.size.width;
	    }

	  r.size.height = labelRect.size.height + hlightRect.size.height;

	  if (showType != FSNInfoNameType)
	    {
	      r.size.height += infoRect.size.height;
	    }

	  // Add space for lblmargin/2 bottom padding + 1px gap + 1px top safety
	  r.size.height += [fsnodeRep labelMargin] / 2 + 2;
	}
      else if (icnPosition == NSImageOnly)
	{
	  r.size.width = hlightRect.size.width;
	  r.size.height = hlightRect.size.height;
	}
      else
	{
	  r.size = icnBounds.size;
	}

      trectTag = -1;
      [self setFrame: NSIntegralRect(r)];

      if (acceptDnd)
	{
	  NSArray *pbTypes = [NSArray arrayWithObjects: NSFilenamesPboardType,
				      @"GWLSFolderPboardType",
				      @"GWRemoteFilenamesPboardType",
				      nil];
	  [self registerForDraggedTypes: pbTypes];
	}

      isLocked = [node isLocked];

      /* Set tooltip to well-known directory description if applicable.
         Must happen after setFrame: so the tooltip tracking rect has valid bounds. */
      if (node)
        {
          NSString *desc = GSDirectoryDescriptionForPath([node path]);
          if (desc)
            {
              [self setToolTip: desc];
            }
        }

      container = nil;

      isSelected = NO;
      isOpened = NO;
      nameEdited = NO;
      editstamp = 0.0;

      dragdelay = 0;
      isDragTarget = NO;
      onSelf = NO;

      labelFrameColor = [NSColor controlColor];
      if ([[defaults objectForKey: @"dockstyle"] intValue] == DockStyleModern)
	{
	  labelFrameColor = [labelFrameColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	  labelFrameColor = [labelFrameColor colorWithAlphaComponent:0.5];
	}
      [labelFrameColor retain];

      drawLabelBackground = NO;

      /* The icon image loads through the FSNIconLoader instead of here, so
       * a large directory fills without the per-icon pipeline.  Icons
       * created outside a decorated container (desktop, shelf, dock,
       * path components) are covered by this self-enqueue; containers that
       * schedule decoration themselves just promote or dedup against it. */
      [[FSNIconLoader sharedLoader] enqueueNode: anode
                                         client: self
                                         urgent: NO];
    }

  return self;
}

- (void)setSelectable:(BOOL)value
{
  if ((icnPosition == NSImageOnly) && (selectable != value))
    {
      selectable = value;
      [self tile];
    }
}

- (void)setSuppressSelectionDrawing:(BOOL)flag
{
  if (suppressSelectionDrawing != flag)
    {
      suppressSelectionDrawing = flag;
      [self setNeedsDisplay: YES];
    }
}

- (NSRect)iconBounds
{
  return icnBounds;
}

- (NSRect)nodeBounds
{
  if (icnPosition == NSImageOnly)
    return icnBounds;

  return NSUnionRect(icnBounds, labelRect);
}

- (float)labelTextWidth
{
  return [label uncutTitleLenght] + [fsnodeRep labelMargin];
}

- (void)tile
{
  NSRect frameRect = [self bounds];
  NSSize sz = [icon size];
  int lblmargin = [fsnodeRep labelMargin];
  BOOL hasinfo = ([[infolabel stringValue] length] > 0);

  if (icnPosition == NSImageAbove)
    {
      float hlx, hly;

      labelRect.size.width = [label uncutTitleLenght] + lblmargin;

      if (labelRect.size.width >= frameRect.size.width)
	{
	  labelRect.size.width = frameRect.size.width;
	  labelRect.origin.x = 0;
	}
      else
	{
	  labelRect.origin.x = (frameRect.size.width - labelRect.size.width) / 2;
	}

      if (showType != FSNInfoNameType)
	{
	  if (hasinfo)
	    {
	      infoRect.size.width = [infolabel uncutTitleLenght] + lblmargin;
	    }
	  else
	    {
	      infoRect.size.width = labelRect.size.width;
	    }

	  if (infoRect.size.width >= frameRect.size.width)
	    {
	      infoRect.size.width = frameRect.size.width;
	      infoRect.origin.x = 0;
	    }
	  else
	    {
	      infoRect.origin.x = (frameRect.size.width - infoRect.size.width) / 2;
	    }
	}

      if (showType == FSNInfoNameType)
	{
	  labelRect.origin.y = 0;
	  labelRect.origin.y += lblmargin / 2;
	  labelRect = NSIntegralRect(labelRect);
	  infoRect = labelRect;
	}
      else
	{
	  infoRect.origin.y = 0;
	  infoRect.origin.y += lblmargin / 2;
	  infoRect = NSIntegralRect(infoRect);

	  labelRect.origin.y = infoRect.origin.y + infoRect.size.height;
	  labelRect = NSIntegralRect(labelRect);
	}

      hlx = myrintf((frameRect.size.width - hlightRect.size.width) / 2);
      // Position hlightRect so its bottom edge is 1px above the top of the label
      hly = myrintf(labelRect.origin.y + labelRect.size.height + 1);

      if ((hlightRect.origin.x != hlx) || (hlightRect.origin.y != hly))
	{
	  NSAffineTransform *transform = [NSAffineTransform transform];

	  [transform translateXBy: hlx - hlightRect.origin.x
			      yBy: hly - hlightRect.origin.y];

	  [highlightPath transformUsingAffineTransform: transform];

	  hlightRect.origin.x = hlx;
	  hlightRect.origin.y = hly;
	}

      icnBounds.origin.x = hlightRect.origin.x + ((hlightRect.size.width - iconSize) / 2);
      icnBounds.origin.y = hlightRect.origin.y + ((hlightRect.size.height - iconSize) / 2);
      icnBounds = NSIntegralRect(icnBounds);

      icnPoint.x = myrintf(hlightRect.origin.x + ((hlightRect.size.width - sz.width) / 2));
      icnPoint.y = myrintf(hlightRect.origin.y + ((hlightRect.size.height - sz.height) / 2));

    }
  else if (icnPosition == NSImageLeft)
    {
      float icnspacew = hlightRect.size.width;
      float hryorigin = 0;

      if (isLeaf == NO)
	{
	  icnspacew += BRANCH_SIZE;
	}

      labelRect.size.width = myrintf([label uncutTitleLenght] + lblmargin);

      if (labelRect.size.width >= (frameRect.size.width - icnspacew))
	{
	  labelRect.size.width = (frameRect.size.width - icnspacew);
	}

      if (showType != FSNInfoNameType)
	{
	  if (hasinfo)
	    {
	      infoRect.size.width = [infolabel uncutTitleLenght] + lblmargin;
	    }
	  else
	    {
	      infoRect.size.width = labelRect.size.width;
	    }

	  if (infoRect.size.width >= (frameRect.size.width - icnspacew))
	    {
	      infoRect.size.width = (frameRect.size.width - icnspacew);
	    }
	}
      else
	{
	  infoRect.size.width = labelRect.size.width;
	}

      infoRect = NSIntegralRect(infoRect);

      if (showType != FSNInfoNameType)
	{
	  float lbsh = labelRect.size.height + infoRect.size.height;

	  if (lbsh > hlightRect.size.height)
	    {
	      hryorigin = myrintf((lbsh - hlightRect.size.height) / 2);
	    }
	}

      if ((hlightRect.origin.x != 0) || (hlightRect.origin.y != hryorigin))
	{
	  NSAffineTransform *transform = [NSAffineTransform transform];

	  [transform translateXBy: 0 - hlightRect.origin.x
			      yBy: hryorigin - hlightRect.origin.y];

	  [highlightPath transformUsingAffineTransform: transform];

	  hlightRect.origin.x = 0;
	  hlightRect.origin.y = hryorigin;
	}

      icnBounds.origin.x = (hlightRect.size.width - iconSize) / 2;
      icnBounds.origin.y = hlightRect.origin.y + ((hlightRect.size.height - iconSize) / 2);
      icnBounds = NSIntegralRect(icnBounds);

      icnPoint.x = myrintf((hlightRect.size.width - sz.width) / 2);
      icnPoint.y = myrintf(hlightRect.origin.y + ((hlightRect.size.height - sz.height) / 2));

      labelRect.origin.x = hlightRect.size.width;
      infoRect.origin.x = hlightRect.size.width;

      if (showType != FSNInfoNameType)
	{
	  float lbsh = labelRect.size.height + infoRect.size.height;

	  infoRect.origin.y = 0;

	  if (hasinfo){
	    if (hlightRect.size.height > lbsh) {
	      infoRect.origin.y = (hlightRect.size.height - lbsh) / 2;
	    }

	    labelRect.origin.y = infoRect.origin.y + infoRect.size.height;
	  }
	  else
	    {
	      if (hlightRect.size.height > lbsh)
		{
		  labelRect.origin.y = (hlightRect.size.height - labelRect.size.height) / 2;
		}
	      else
		{
		  labelRect.origin.y = (lbsh - labelRect.size.height) / 2;
		}
	    }

	}
      else
	{
	  labelRect.origin.y = (hlightRect.size.height - labelRect.size.height) / 2;
	}

      infoRect = NSIntegralRect(infoRect);
      labelRect = NSIntegralRect(labelRect);

    }
  else if (icnPosition == NSImageOnly)
    {
      if (selectable)
	{
	  float hlx = myrintf((frameRect.size.width - hlightRect.size.width) / 2);
	  float hly = myrintf((frameRect.size.height - hlightRect.size.height) / 2);

	  if ((hlightRect.origin.x != hlx) || (hlightRect.origin.y != hly))
	    {
	      NSAffineTransform *transform = [NSAffineTransform transform];

	      [transform translateXBy: hlx - hlightRect.origin.x
				  yBy: hly - hlightRect.origin.y];

	      [highlightPath transformUsingAffineTransform: transform];

	      hlightRect.origin.x = hlx;
	      hlightRect.origin.y = hly;
	    }
	}

      icnBounds.origin.x = (frameRect.size.width - iconSize) / 2;
      icnBounds.origin.y = (frameRect.size.height - iconSize) / 2;
      icnBounds = NSIntegralRect(icnBounds);

      icnPoint.x = myrintf((frameRect.size.width - sz.width) / 2);
      icnPoint.y = myrintf((frameRect.size.height - sz.height) / 2);
    }

  brImgBounds.origin.x = frameRect.size.width - ARROW_ORIGIN_X;
  brImgBounds.origin.y = myrintf(icnBounds.origin.y + (icnBounds.size.height / 2) - (BRANCH_SIZE / 2));
  brImgBounds = NSIntegralRect(brImgBounds);

  if ([self window])
    {
      if (trectTag != -1)
	{
	  [self removeTrackingRect: trectTag];
	}

      trectTag = [self addTrackingRect: icnBounds
				 owner: self
			      userData: nil
			  assumeInside: NO];
    }

  [self setNeedsDisplay: YES];
}

// DS_Store tag/label color support
- (void)setTagColor:(NSColor *)color
{
  ASSIGN(tagColor, color);
  [self setNeedsDisplay: YES];
}

- (NSColor *)tagColor
{
  return tagColor;
}

- (void)setSpotlightComment:(NSString *)comment
{
  ASSIGN(spotlightComment, comment);
  // Could update tooltip here if desired
  if (comment && [comment length] > 0) {
    [self setToolTip:comment];
  }
}

- (NSString *)spotlightComment
{
  return spotlightComment;
}

//
// Private: Attempt to load the Finder label colour from the metadata provider.
// Called during draws when tagColor is nil (fallback/lazy-load path).
// Sets tagColor if a non-zero label is found, so the existing draw code picks it up.
// Once tagColor is set, subsequent draws skip this method entirely.
//
- (void)loadLabelColorFromMetadata
{
  if (tagColor != nil)
    return;  // Already have a colour (e.g., from DS_Store lclr).

  if (labelChecked)
    return;  // Probed already and found no label — don't re-check every draw.

  if (node == nil)
    return;

  NSString *path = [node path];
  if (path == nil || [path length] == 0)
    return;

  labelChecked = YES;

  NSColor *color = [[[FSNodeRep sharedInstance] metadataProvider]
                     labelColorForPath: path];
  if (color)
    [self setTagColor: color];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown)
    {
      /* Beside the image and name a left click belongs to the view behind
         the icon, so a right click there must not select the icon either. */
      if ([self pointIsOnNode:
	     [self convertPoint: [theEvent locationInWindow] fromView: nil]] == NO)
	{
	  return [container menuForEvent: theEvent];
	}

      // Select the icon if it's not already selected so the context menu shows
      if (!isSelected && selectable)
        {
          [container stopRepNameEditing];
          // If there's already a multi-selection, preserve it by adding to the selection
          NSArray *selectedNodes = [container selectedNodes];
          if ([selectedNodes count] > 1) {
            [container setSelectionMask: FSNMultipleSelectionMask];
          } else {
            [container setSelectionMask: NSSingleSelectionMask];
          }
          [self select];
          [container selectionDidChange];
        }
      return [container menuForEvent: theEvent];
    }
  return [super menuForEvent: theEvent];
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];
  container = (NSView <FSNodeRepContainer> *)[self superview];
}

- (void)mouseUp:(NSEvent *)theEvent
{
  NSPoint location = [theEvent locationInWindow];
  BOOL onself = NO;

  location = [self convertPoint: location fromView: nil];

  if (icnPosition == NSImageOnly)
    {
      onself = [self mouse: location inRect: icnBounds];
    }
  else
    {
      onself = ([self mouse: location inRect: icnBounds]
		|| [self mouse: location inRect: labelRect]);
    }

  if ([container respondsToSelector: @selector(setSelectionMask:)])
    {
      [container setSelectionMask: NSSingleSelectionMask];
    }

  if (onself)
    {
      if (([node isLocked] == NO) && ([theEvent clickCount] > 1))
	{
	  if ([container respondsToSelector: @selector(openSelectionInNewViewer:)]) {
	    BOOL newv = (([theEvent modifierFlags] & NSControlKeyMask)
			 || ([theEvent modifierFlags] & NSAlternateKeyMask));

	    [container openSelectionInNewViewer: newv];
	  }
	}
    }
  else
    {
      [container mouseUp: theEvent];
    }
}

- (void)mouseDown:(NSEvent *)theEvent
{
  NSPoint location = [theEvent locationInWindow];
  NSPoint selfloc = [self convertPoint: location fromView: nil];
  BOOL onself = NO;
  NSEvent *nextEvent = nil;
  BOOL startdnd = NO;
  BOOL editing = NO;
  NSSize offset;

  if (icnPosition == NSImageOnly)
    {
      onself = [self mouse: selfloc inRect: icnBounds];
    }
  else
    {
      onself = ([self mouse: selfloc inRect: icnBounds]
		|| [self mouse: selfloc inRect: labelRect]);
    }

  if (onself)
    {
      if (selectable == NO)
	{
	  return;
	}

      if ([theEvent clickCount] == 1)
	{
	  if (isSelected == NO)
	    {
	      if ([container respondsToSelector: @selector(stopRepNameEditing)])
		{
		  [container stopRepNameEditing];
		}
	    }

	  if ([theEvent modifierFlags] & NSShiftKeyMask)
	    {
	      if ([container respondsToSelector: @selector(setSelectionMask:)])
		{
		  [container setSelectionMask: FSNMultipleSelectionMask];
		}

	      if (isSelected)
		{
		  if ([container selectionMask] == FSNMultipleSelectionMask)
		    {
		      [self unselect];
		      if ([container respondsToSelector: @selector(selectionDidChange)])
			{
			  [container selectionDidChange];
			}
		      return;
		    }
		}
	      else
		{
		  [self select];
		}
	    }
	  else
	    {
	      if ([container respondsToSelector: @selector(setSelectionMask:)])
		{
		  [container setSelectionMask: NSSingleSelectionMask];
		}

	      if (isSelected == NO)
		{
		  [self select];
		}
	      else
		{
		  NSTimeInterval interval = ([theEvent timestamp] - editstamp);

		  /* labelRect is in our own coordinates, so the hit test needs
		   * the converted point: with the window location a click
		   * anywhere on an icon near the window origin started
		   * renaming, while clicking the name of any other icon
		   * never did. */
		  if ((interval > DOUBLE_CLICK_LIMIT)
		      && [self mouse: selfloc inRect: labelRect])
		    {
		      if ([container respondsToSelector: @selector(setNameEditorForRep:)])
			{
			  [container setNameEditorForRep: self];
			  editing = YES;
			}
		    }
		}
	    }
	}

      /* A press that follows a click closely comes as the second click of a
       * double click, and it drags the icon just the same: the item opens
       * when the button comes up where it went down, not before.  Only the
       * single click used to start a drag, so an icon clicked and then
       * quickly pulled away stayed put.  Once the name editor is up the
       * label belongs to the text field, so a drag there selects text
       * instead of moving the icon. */
      if (dndSource && (editing == NO))
	{
	  while (1)
	    {
	      nextEvent = [[self window] nextEventMatchingMask:
					   NSLeftMouseUpMask | NSLeftMouseDraggedMask];

	      if ([nextEvent type] == NSLeftMouseUp)
		{
		  [[self window] postEvent: nextEvent atStart: NO];

		  if ([container respondsToSelector: @selector(repSelected:)])
		    {
		      [container repSelected: self];
		    }

		  break;

		}
	      /* Anywhere the press selects the icon also starts a drag:
	       * requiring the image swallowed every drag begun on the
	       * name, and with it the events until the mouse came up. */
	      else if ([nextEvent type] == NSLeftMouseDragged)
		{
		  NSPoint p = [nextEvent locationInWindow];
		  offset = NSMakeSize(p.x - location.x, p.y - location.y);
		  startdnd = YES;
		  break;
		}
	    }
	}

      if (startdnd)
	{
	  /* Local reposition only in position-honoring containers; a
	   * pure-reflow container (browser icon view) has no meaningful
	   * icon positions, so a drag is an external file drag. */
	  BOOL canReposition =
	    [container respondsToSelector: @selector(repositionIcon:toCenterPoint:)];
	  if (canReposition
	      && [container respondsToSelector: @selector(honorsSavedPositions)])
	    canReposition = [(FSNIconsView *)container honorsSavedPositions];

	  if ([container respondsToSelector: @selector(stopRepNameEditing)])
	    [container stopRepNameEditing];

	  if (canReposition)
	    {
	      [self repositionLocal: theEvent offset: offset];
	    }
	  else
	    {
	      if ([container respondsToSelector: @selector(setFocusedRep:)])
		[container setFocusedRep: nil];

	      [self startExternalDragOnEvent: theEvent withMouseOffset: offset];
	    }
	}

      if ([theEvent clickCount] == 1)
	editstamp = [theEvent timestamp];
    }
  else
    {
      [container mouseDown: theEvent];
    }
}

- (void)mouseEntered:(NSEvent *)theEvent
{
  if ([container respondsToSelector: @selector(setFocusedRep:)])
    {
      [container setFocusedRep: self];
    }
}

- (void)mouseExited:(NSEvent *)theEvent
{
  if ([container respondsToSelector: @selector(setFocusedRep:)])
    {
      [container setFocusedRep: nil];
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
  return YES;
}

- (void)setFrame:(NSRect)frameRect
{
  /* Following the pointer changes nothing inside the icon, and laying it
   * out again marks all of it for a second redraw after every step.  The
   * layout catches up when the icon is let go. */
  if (beingDragged && NSEqualSizes(frameRect.size, [self frame].size))
    {
      [super setFrame: frameRect];
      return;
    }

  [super setFrame: frameRect];
  [self tile];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldBoundsSize
{
  [self tile];
}

- (void)drawRect:(NSRect)rect
{
  if (beingDragged && draggedLook != nil)
    {
      [draggedLook drawInRect: [self bounds]
                     fromRect: NSZeroRect
                    operation: NSCompositeSourceOver
                     fraction: 1.0
               respectFlipped: YES
                        hints: nil];
      return;
    }

  /* A dragged icon is a ghost floating over whatever the pointer is on.  Its
   * selection plate is opaque, so painting that too would hide the folder the
   * icon is about to be dropped on, drop highlight and all. */
  if ((isSelected || selectionPreview) && !suppressSelectionDrawing
      && (beingDragged == NO))
    {
      [[NSColor selectedControlColor] set];
      [highlightPath fill];

      // Draw the text label background with the standard selected color (blue)
      if (nameEdited == NO)
        {
          [[NSColor selectedControlColor] set];
          NSRectFill(labelRect);
        }
    }
  else
    {
      if (nameEdited == NO)
        {
          [[container backgroundColor] set];
        }
    }
  if (decorated && icnPosition != NSImageOnly)
    {
      if (nameEdited == NO)
        {
          [label setBackgroundColor:labelFrameColor];
          [label setDrawsBackground: drawLabelBackground];

          [label drawWithFrame: labelRect inView: self];
        }

      if ((showType != FSNInfoNameType) && [[infolabel stringValue] length])
        {
          [infolabel drawWithFrame: infoRect inView: self];
        }
    }

  if (isLocked == NO)
    {
      if (isOpened == NO && beingDragged == NO)
        {
          [drawicon compositeToPoint: icnPoint operation: NSCompositeSourceOver];
        }
      else
        {
          [drawicon dissolveToPoint: icnPoint fraction: 0.5];
        }
    }
  else
    {
      [drawicon dissolveToPoint: icnPoint fraction: 0.3];
    }

  /* Gate all icon overlays on decorated so they appear atomically with the
   * icon image, matching the label gating above. */
  if (decorated)
    {
      if (isLeaf == NO)
        [[object_getClass(self) branchImage] compositeToPoint: brImgBounds.origin
                                                    operation: NSCompositeSourceOver];

      // Draw tag color indicator (from DS_Store lclr or FinderInfo fdFlags).
      // Lazily check the metadata provider if no colour has been set yet.
      if (tagColor == nil)
        [self loadLabelColorFromMetadata];

      if (tagColor)
        {
          // Small colored dot in the bottom-right corner of the icon
          CGFloat dotSize = 10.0;
          CGFloat dotMargin = 2.0;
          NSRect dotRect = NSMakeRect(icnBounds.origin.x + icnBounds.size.width - dotSize - dotMargin,
                                      icnBounds.origin.y + dotMargin,
                                      dotSize, dotSize);
          FSNDrawLabelDot(dotRect, tagColor);
        }

      /* Red git change-count badge: a rounded pill with the number in white,
       * drawn at the icon's top-right corner (>= 48px icons only), mirroring
       * the Dock's app-icon badge.  The count arrives asynchronously; until
       * then badgeCount is 0 / pending and nothing is drawn here. */
      if (gitBadgeCount > 0 && iconSize >= 48)
        {
          NSString *countStr = (gitBadgeCount > 99)
            ? @"99+"
            : [NSString stringWithFormat: @"%ld", (long) gitBadgeCount];
          CGFloat badgeH = MAX (12.0, round ((CGFloat) iconSize * 0.34));
          NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont boldSystemFontOfSize: badgeH * 0.6],
            NSForegroundColorAttributeName: [NSColor whiteColor]
          };
          NSSize strSize = [countStr sizeWithAttributes: attrs];
          CGFloat pad = badgeH * 0.375;
          CGFloat badgeW = strSize.width + pad * 2.0;
          if (badgeW < badgeH)
            {
              badgeW = badgeH;
            }
          CGFloat margin = 2.0;
          NSRect badgeRect = NSMakeRect (
            icnBounds.origin.x + icnBounds.size.width - badgeW - margin,
            icnBounds.origin.y + icnBounds.size.height - badgeH - margin,
            badgeW, badgeH);
          [[NSColor redColor] set];
          [[NSBezierPath bezierPathWithRoundedRect: badgeRect
                                           xRadius: badgeH / 2.0
                                           yRadius: badgeH / 2.0] fill];
          NSPoint strPoint = NSMakePoint (
            badgeRect.origin.x + (badgeW - strSize.width) / 2.0,
            badgeRect.origin.y + (badgeH - strSize.height) / 2.0);
          [countStr drawAtPoint: strPoint withAttributes: attrs];
        }
    }

  /* The git-repository badge (the git logo) is already baked into the icon
   * image by FSNodeRep's iconOfSize:forNode:, so nothing else is drawn here. */
}


//
// FSNodeRep protocol
//

/* Query the decoration delegate for the git change-count of this node.  Returns
 * immediately: a known count (possibly 0) is stored, while an in-flight
 * computation yields -1 and the badge is filled in later when
 * gitBadgeCountChanged: fires.  Non-directories are skipped. */
- (void)updateBadgeCount
{
  gitBadgeCount = 0;
  if (node == nil || [node isDirectory] == NO)
    {
      return;
    }
  id dd = [fsnodeRep decorationDelegate];
  if (dd != nil && [dd respondsToSelector: @selector (badgeCountForNode:)])
    {
      NSInteger c = [dd badgeCountForNode: node];
      if (c > 0)
        {
          gitBadgeCount = c;
        }
    }
}

/* A background git count finished; if it was for this node, store it and
 * redraw so the red badge appears without re-blocking the UI. */
- (void)gitBadgeCountChanged:(NSNotification *)note
{
  NSString *path = [note object];
  if (path == nil || node == nil || [[node path] isEqual: path] == NO)
    {
      return;
    }
  [self updateBadgeCount];
  [self setNeedsDisplay: YES];
}

/* Ask the decoration delegate to begin/end watching this node's backing
 * repository, so the count badge can refresh on external changes.  Guarded by
 * respondsToSelector because not every decoration delegate implements watching
 * (and the delegate may be nil while extensions are still loading). */
- (void)startWatchingCurrentNode
{
  if (node == nil || [node isDirectory] == NO)
    {
      return;
    }
  id dd = [fsnodeRep decorationDelegate];
  if (dd != nil && [dd respondsToSelector: @selector (startWatchingNode:)])
    {
      @try { [dd performSelector: @selector (startWatchingNode:) withObject: node]; }
      @catch (NSException *e) { /* ignore: watching is best-effort */ }
    }
}

- (void)stopWatchingCurrentNode
{
  if (node == nil || [node isDirectory] == NO)
    {
      return;
    }
  id dd = [fsnodeRep decorationDelegate];
  if (dd != nil && [dd respondsToSelector: @selector (stopWatchingNode:)])
    {
      @try { [dd performSelector: @selector (stopWatchingNode:) withObject: node]; }
      @catch (NSException *e) { /* ignore: watching is best-effort */ }
    }
}

- (void)setNode:(FSNode *)anode
{
  [self stopWatchingCurrentNode];
  DESTROY (selection);
  DESTROY (selectionTitle);
  DESTROY (hostname);
  DESTROY (tagColor);
  labelChecked = NO;

  ASSIGN (node, anode);
  if (decorated)
    {
      ASSIGN (icon, [fsnodeRep iconOfSize: iconSize forNode: node]);
      drawicon = icon;
    }
  DESTROY (selectedicon);
  [self updateBadgeCount];
  [self startWatchingCurrentNode];

  if ([[node path] isEqual: path_separator()] && ([node isMountPoint] == NO))
    {
      NSString *hname;

      hname = [FSNIcon getBestHostName];
      ASSIGN (hostname, hname);
    }

  /* Reload label colour eagerly from the metadata provider,
   * same as initForNode: does, rather than deferring to
   * drawRect: — so colour labels survive updateIcons and
   * other setNode: callers even if the view isn't redrawn. */
  ASSIGN (tagColor,
           [[[FSNodeRep sharedInstance] metadataProvider]
             labelColorForPath: [anode path]]);

  /* The git-repository badge (git logo) is baked into the icon image by
   * FSNodeRep's iconOfSize:forNode:, so FSNIcon needs no separate badge
   * handling here. */

  if (extInfoType)
    {
      [self setExtendedShowType: extInfoType];
    }
  else
    {
      [self setNodeInfoShowType: showType];
    }

  [self setLocked: [node isLocked]];
  [self tile];

  /* Set tooltip to well-known directory description if applicable */
  if (node)
    {
      NSString *desc = GSDirectoryDescriptionForPath([node path]);
      if (desc)
        {
          [self setToolTip: desc];
        }
    }
}

- (void)setNode:(FSNode *)anode
   nodeInfoType:(FSNInfoType)type
   extendedType:(NSString *)exttype
{
  [self setNode: anode];

  if (exttype)
    {
      [self setExtendedShowType: exttype];
    }
  else
    {
      [self setNodeInfoShowType: type];
    }
}

- (FSNode *)node
{
  return node;
}

- (void)showSelection:(NSArray *)selnodes
{
  NSUInteger i;

  ASSIGN (node, [selnodes objectAtIndex: 0]);
  ASSIGN (selection, selnodes);
  ASSIGN (selectionTitle, ([NSString stringWithFormat: @"%lu %@",
                                     (unsigned long)[selection count], NSLocalizedString(@"elements", @"")]));
  ASSIGN (icon, [fsnodeRep multipleSelectionIconOfSize: iconSize]);
  drawicon = icon;
  DESTROY (selectedicon);

  [label setStringValue: selectionTitle];
  [infolabel setStringValue: @""];

  [self setLocked: NO];
  for (i = 0; i < [selnodes count]; i++)
    {
      if ([fsnodeRep isNodeLocked: [selnodes objectAtIndex: i]])
	{
	  [self setLocked: YES];
	  break;
	}
    }

  [self tile];
}

- (BOOL)isShowingSelection
{
  return (selection != nil);
}

- (NSArray *)selection
{
  return selection;
}

- (NSArray *)pathsSelection
{
  if (selection)
    {
      NSMutableArray *selpaths = [NSMutableArray array];
      NSUInteger i;

      for (i = 0; i < [selection count]; i++)
	{
	  [selpaths addObject: [[selection objectAtIndex: i] path]];
	}

      return [NSArray arrayWithArray: selpaths];
    }

  return nil;
}

- (void)setFont:(NSFont *)fontObj
{
  NSFontManager *fmanager = [NSFontManager sharedFontManager];
  int lblmargin = [fsnodeRep labelMargin];
  NSFont *infoFont;

  [label setFont: fontObj];

  infoFont = [fmanager convertFont: fontObj
                            toSize: ([fontObj pointSize] - 2)];
  infoFont = [fmanager convertFont: infoFont
                       toHaveTrait: NSItalicFontMask];

  [infolabel setFont: infoFont];

  labelRect.size.width = myrintf([label uncutTitleLenght] + lblmargin);
  labelRect.size.height = myrintf([fsnodeRep heightOfFont: [label font]]);
  labelRect = NSIntegralRect(labelRect);

  infoRect = NSZeroRect;
  if ((showType != FSNInfoNameType) && [[infolabel stringValue] length])
    {
      infoRect.size.width = [infolabel uncutTitleLenght] + lblmargin;
    }
  else
    {
      infoRect.size.width = labelRect.size.width;
    }
  infoRect.size.height = [fsnodeRep heightOfFont: infoFont];
  infoRect = NSIntegralRect(infoRect);

  [self tile];
}

- (NSFont *)labelFont
{
  return [label font];
}

- (void)setLabelTextColor:(NSColor *)acolor
{
  [label setTextColor: acolor];
  [infolabel setTextColor: acolor];
}

- (NSColor *)labelTextColor
{
  return [label textColor];
}

- (void)setIconSize:(int)isize
{
  iconSize = isize;
  icnBounds = NSMakeRect(0, 0, iconSize, iconSize);
  if (decorated)
    {
      if (selection == nil)
        {
          ASSIGN (icon, [fsnodeRep iconOfSize: iconSize forNode: node]);
        }
      else
        {
          ASSIGN (icon, [fsnodeRep multipleSelectionIconOfSize: iconSize]);
        }
    }
  drawicon = icon;
  DESTROY (selectedicon);
  hlightRect.size.width = myrintf(iconSize + 6);
  hlightRect.size.height = myrintf(hlightRect.size.width);
  hlightRect.origin.x = 0;
  hlightRect.origin.y = 0;
  ASSIGN (highlightPath, [fsnodeRep highlightPathOfSize: hlightRect.size]);

  labelRect.size.width = [label uncutTitleLenght] + [fsnodeRep labelMargin];
  labelRect.size.height = [fsnodeRep heightOfFont: [label font]];

  [self tile];
}

- (int)iconSize
{
  return iconSize;
}

- (void)decorate
{
  if (decorated || node == nil || selection != nil)
    {
      return;
    }

  ASSIGN (icon, [fsnodeRep iconOfSize: iconSize forNode: node]);
  drawicon = icon;
  decorated = YES;

  /* The icon image may arrive after the last -tile (a lazy icon is laid
   * out and tiled while its image is still nil), and tile computes the
   * drawing point from [icon size].  Re-tile so the image is centered in
   * its highlight rect instead of drawn from its bottom-left. */
  [self tile];

  [self setNeedsDisplay: YES];
}

- (BOOL)isDecorated
{
  return decorated;
}

//
// FSNDecorationClient (self-decorate through the FSNIconLoader)
//

/* The loader item IS this icon, so there is no separate generation to
 * track; staleness is covered by -dealloc (cancelClient) and the no-op
 * -decorate when the state moved on. */
- (NSInteger)fsnDecorationGeneration
{
  return 0;
}

- (BOOL)fsnLoaderDecorateNode:(FSNode *)anode
{
  [self decorate];

  return YES;
}

- (void)setIconPosition:(NSCellImagePosition)ipos
{
  icnPosition = ipos;

  if (icnPosition == NSImageLeft)
    {
      [label setAlignment: NSLeftTextAlignment];
      [infolabel setAlignment: NSLeftTextAlignment];
    }
  else if (icnPosition == NSImageAbove)
    {
      [label setAlignment: NSCenterTextAlignment];
      [infolabel setAlignment: NSCenterTextAlignment];
    }

  [self tile];
}

- (NSCellImagePosition)iconPosition
{
  return icnPosition;
}

- (NSRect)labelRect
{
  return labelRect;
}

- (void)setNodeInfoShowType:(FSNInfoType)type
{
  showType = type;
  DESTROY (extInfoType);

  if (selection)
    {
      [label setStringValue: selectionTitle];
      [infolabel setStringValue: @""];
      return;
    }

  [label setStringValue: (hostname ? hostname : [node displayName])];

  switch(showType) {
    case FSNInfoNameType:
      [infolabel setStringValue: @""];
      break;
    case FSNInfoKindType:
      [infolabel setStringValue: [node typeDescription]];
      break;
    case FSNInfoDateType:
      [infolabel setStringValue: [node modDateDescription]];
      break;
    case FSNInfoSizeType:
      [infolabel setStringValue: [node sizeDescription]];
      break;
    case FSNInfoOwnerType:
      [infolabel setStringValue: [node owner]];
      break;
    default:
      [infolabel setStringValue: @""];
      break;
  }
}

- (BOOL)setExtendedShowType:(NSString *)type
{
  ASSIGN (extInfoType, type);
  showType = FSNInfoExtendedType;

  [self setNodeInfoShowType: showType];

  if (selection == nil)
    {
      NSDictionary *info = [fsnodeRep extendedInfoOfType: type forNode: node];

      if (info)
	{
	  [infolabel setStringValue: [info objectForKey: @"labelstr"]];
	  return YES;
	}
    }

  return NO;
}

- (FSNInfoType)nodeInfoShowType
{
  return showType;
}

- (NSString *)shownInfo
{
  return [label stringValue];
}

- (void)setNameEdited:(BOOL)value
{
  if (nameEdited != value)
    {
      nameEdited = value;
      [self setNeedsDisplay: YES];
    }
}

- (void)setLeaf:(BOOL)flag
{
  if (isLeaf != flag)
    {
      isLeaf = flag;
      [self tile];
    }
}

- (BOOL)isLeaf
{
  return isLeaf;
}

- (void)select
{
  if (isSelected)
    {
      return;
    }
  isSelected = YES;

  if ([container respondsToSelector: @selector(unselectOtherReps:)])
    {
      [container unselectOtherReps: self];
    }
  if ([container respondsToSelector: @selector(selectionDidChange)])
    {
      [container selectionDidChange];
    }

  [self setNeedsDisplay: YES];
}

- (void)unselect
{
  if (isSelected == NO) {
    return;
  }
	isSelected = NO;
  [self setNeedsDisplay: YES];
}

- (BOOL)isSelected
{
  return isSelected;
}

- (void)setOpened:(BOOL)value
{
  if (isOpened == value)
    {
      return;
    }
  isOpened = value;
  [self setNeedsDisplay: YES];
}

- (BOOL)isOpened
{
  return isOpened;
}

- (void)setLocked:(BOOL)value
{
  if (isLocked == value)
    {
      return;
    }
  isLocked = value;
  [label setTextColor: (isLocked ? [container disabledTextColor]
			: [container textColor])];
  [infolabel setTextColor: (isLocked ? [container disabledTextColor]
			    : [container textColor])];

  [self setNeedsDisplay: YES];
}

- (void)checkLocked
{
  if (selection == nil)
    {
      [self setLocked: [node isLocked]];
    }
  else
    {
      NSUInteger i;
    
      [self setLocked: NO];
    
      for (i = 0; i < [selection count]; i++)
	{
	  if ([[selection objectAtIndex: i] isLocked])
	    {
	      [self setLocked: YES];
	      break;
	    }
	}
    }
}

- (BOOL)isLocked
{
  return isLocked;
}

- (void)setGridIndex:(NSUInteger)index
{
  gridIndex = index;
}

- (NSUInteger)gridIndex
{
  return gridIndex;
}

- (int)compareAccordingToName:(id)aIcon
{
  return [node compareAccordingToName: [aIcon node]];
}

- (int)compareAccordingToKind:(id)aIcon
{
  return [node compareAccordingToKind: [aIcon node]];
}

- (int)compareAccordingToDate:(id)aIcon
{
  return [node compareAccordingToDate: [aIcon node]];
}

- (int)compareAccordingToSize:(id)aIcon
{
  return [node compareAccordingToSize: [aIcon node]];
}

- (int)compareAccordingToOwner:(id)aIcon
{
  return [node compareAccordingToOwner: [aIcon node]];
}

- (int)compareAccordingToGroup:(id)aIcon
{
  return [node compareAccordingToGroup: [aIcon node]];
}

- (int)compareAccordingToIndex:(id)aIcon
{
  return (gridIndex <= [aIcon gridIndex]) ? NSOrderedAscending : NSOrderedDescending;
}

- (BOOL)pointIsOnNode:(NSPoint)selfPoint
{
  if (icnPosition == NSImageOnly)
    return [self mouse: selfPoint inRect: icnBounds];

  return ([self mouse: selfPoint inRect: icnBounds]
	  || [self mouse: selfPoint inRect: labelRect]);
}

- (void)setSelectionPreview:(BOOL)flag
{
  if (selectionPreview == flag)
    return;

  selectionPreview = flag;
  [container setNeedsDisplayInRect: [self frame]];
}

/* The icon as it draws itself now, on a transparent picture of its bounds. */
- (NSImage *)imageOfCurrentLook
{
  NSRect b = [self bounds];
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: b.size]);

  [image setBackgroundColor: [NSColor clearColor]];
  [image lockFocus];
  if ([self isFlipped])
    {
      NSAffineTransform *flip = [NSAffineTransform transform];

      [flip translateXBy: 0 yBy: b.size.height];
      [flip scaleXBy: 1 yBy: -1];
      [flip concat];
    }
  [self drawRect: b];
  [image unlockFocus];

  return image;
}

- (NSImage *)restingLookImage
{
  BOOL wasDragged = beingDragged;
  BOOL wasSuppressed = suppressSelectionDrawing;
  NSImage *image;

  /* The flags are changed only around this one drawing, without asking for
   * a redisplay: the icon on screen must not flicker. */
  beingDragged = NO;
  suppressSelectionDrawing = YES;
  image = [self imageOfCurrentLook];
  beingDragged = wasDragged;
  suppressSelectionDrawing = wasSuppressed;

  return image;
}

- (void)setBeingDragged:(BOOL)flag
{
  if (beingDragged == flag)
    return;

  beingDragged = flag;

  /* The ghost is redrawn for every step of the move, and laying out its name
   * each time is most of what it costs; nothing about its look changes
   * until it is let go. */
  if (beingDragged)
    {
      ASSIGN (draggedLook, [self imageOfCurrentLook]);
    }
  else
    {
      DESTROY (draggedLook);
      [self tile];
    }

  FSNRedrawContainerRect(container, [self frame]);
}

/* The flash before a folder springs open inverts the look it rests in - lit
 * for a folder that takes the drop, plain for one that does not - and then
 * restores it. */
- (void)setSpringHighlightVisible:(BOOL)visible
{
  if (selectedicon == nil)
    ASSIGN (selectedicon, [fsnodeRep openFolderIconOfSize: iconSize forNode: node]);
  if (selectedicon == nil)
    return;

  if (visible)
    {
      if (springRestingIcon != nil)
	drawicon = springRestingIcon;
      springRestingIcon = nil;
    }
  else
    {
      if (springRestingIcon == nil)
	springRestingIcon = drawicon;
      drawicon = (springRestingIcon == selectedicon) ? icon : selectedicon;
    }

  FSNRedrawContainerRect(container, [self frame]);
}

- (void)setDropHighlighted:(BOOL)flag
{
  if (flag)
    {
      if (selectedicon == nil)
	ASSIGN (selectedicon, [fsnodeRep openFolderIconOfSize: iconSize forNode: node]);

      if (drawicon == selectedicon)
	return;

      drawicon = selectedicon;
    }
  else
    {
      if (drawicon == icon)
	return;

      drawicon = icon;
    }

  FSNRedrawContainerRect(container, [self frame]);
}

/* Redraws the areas right away, each on its own.  A view keeps one dirty
 * rectangle, so marking icons spread over it would redraw everything in
 * between; areas that overlap are joined so nothing is drawn twice. */
static void FSNRedrawContainerRects(NSView *container, NSMutableArray *rects)
{
  NSUInteger i, j;

  for (i = 0; i < [rects count]; i++)
    {
      for (j = i + 1; j < [rects count]; j++)
        {
          NSRect a = [[rects objectAtIndex: i] rectValue];
          NSRect b = [[rects objectAtIndex: j] rectValue];

          if (NSIntersectsRect(a, b))
            {
              [rects replaceObjectAtIndex: i
                               withObject: [NSValue valueWithRect: NSUnionRect(a, b)]];
              [rects removeObjectAtIndex: j];
              /* The joined area may now reach ones already passed over. */
              j = i;
            }
        }
    }

  for (i = 0; i < [rects count]; i++)
  for (i = 0; i < [rects count]; i++)
    [container displayRect: FSNPixelAlignedRect(container,
                                                [[rects objectAtIndex: i] rectValue])];
}

/* Moves the dragged icons to their original frames offset by (dx, dy), as
 * far as FSNClampedGroupDelta lets the group leave the container.
 *
 * Only the area each icon is leaving and the one it now covers is redrawn;
 * redisplaying the window would redraw every icon in it for every step.  The
 * vacated area is the icon's CURRENT frame, not its original one - after the
 * first step those differ, and redrawing the original left the intermediate
 * positions smeared on screen.
 */
static void FSNMoveDraggedIcons(NSView *container, NSArray *dragged,
                                NSArray *frames, CGFloat dx, CGFloat dy)
{
  NSMutableArray *dirty;
  NSRect group = NSZeroRect;
  NSSize delta;
  NSUInteger i, count = [dragged count];

  if (count == 0 || container == nil)
    return;

  for (i = 0; i < count; i++)
    {
      NSRect orig = [[frames objectAtIndex: i] rectValue];
      group = (i == 0) ? orig : NSUnionRect(group, orig);
    }
  delta = FSNClampedGroupDelta(group, [container bounds], NSMakeSize(dx, dy));

  dirty = [NSMutableArray arrayWithCapacity: count];
  for (i = 0; i < count; i++)
    {
      FSNIcon *ic = [dragged objectAtIndex: i];
      NSRect orig = [[frames objectAtIndex: i] rectValue];
      NSRect was = [ic frame];

      [ic setFrame: NSOffsetRect(orig, delta.width, delta.height)];
      [dirty addObject: [NSValue valueWithRect: NSUnionRect(was, [ic frame])]];
    }

  FSNRedrawContainerRects(container, dirty);
}

typedef struct
{
  NSArray *order;
  NSArray *dragged;
} FSNStackingContext;

static NSComparisonResult FSNDraggedIconsOnTop(id a, id b, void *context)
{
  FSNStackingContext *ctx = (FSNStackingContext *)context;
  BOOL aDragged = [ctx->dragged indexOfObjectIdenticalTo: a] != NSNotFound;
  BOOL bDragged = [ctx->dragged indexOfObjectIdenticalTo: b] != NSNotFound;
  NSUInteger ia, ib;

  if (aDragged != bDragged)
    return aDragged ? NSOrderedDescending : NSOrderedAscending;

  ia = [ctx->order indexOfObjectIdenticalTo: a];
  ib = [ctx->order indexOfObjectIdenticalTo: b];
  if (ia == ib)
    return NSOrderedSame;
  return (ia < ib) ? NSOrderedAscending : NSOrderedDescending;
}

/* Views draw in the order of their superview's subviews, so an icon
 * dragged over one that comes later went underneath it: a folder hid the
 * ghost that was about to be dropped on it.  The dragged icons move to the
 * end; every other icon keeps its place, so overlapping ones do not swap. */
static void FSNRaiseDraggedIcons(NSView *container, NSArray *dragged)
{
  FSNStackingContext ctx;

  ctx.order = [NSArray arrayWithArray: [container subviews]];
  ctx.dragged = dragged;
  [container sortSubviewsUsingFunction: FSNDraggedIconsOnTop context: &ctx];
}

static void FSNSetIconsBeingDragged(NSArray *dragged, BOOL flag)
{
  NSUInteger i;

  for (i = 0; i < [dragged count]; i++)
    [[dragged objectAtIndex: i] setBeingDragged: flag];
}

/* Puts the dragged icons back where the gesture started.  -setFrame: does not
 * redraw the superview, so the area the icons are leaving has to be redrawn
 * explicitly or they stay painted at the dragged position. */
static void FSNRestoreDraggedIcons(NSView *container, NSArray *dragged,
                                   NSArray *frames)
{
  NSRect dirty = NSZeroRect;
  NSUInteger i;

  for (i = 0; i < [dragged count]; i++)
    {
      FSNIcon *ic = [dragged objectAtIndex: i];

      dirty = NSUnionRect(dirty, [ic frame]);
      [ic setFrame: [[frames objectAtIndex: i] rectValue]];
      dirty = NSUnionRect(dirty, [ic frame]);
    }

  FSNRedrawContainerRect(container, dirty);
}

/* Whether another application's window is under the pointer.  Such a window
 * can only be reached through GNUstep's drag machinery, which talks to other
 * applications; the application's own windows are handled by the move
 * itself (see FSNIconDragSession). */
- (BOOL)otherApplicationIsUnderPointer
{
  NSTimeInterval now;

  if ([container respondsToSelector: @selector(foreignWindowIsUnderPointer)] == NO)
    return NO;

  now = [NSDate timeIntervalSinceReferenceDate];
  if ((now - foreignCheckTime) >= 0.1)
    {
      foreignCheckTime = now;
      foreignCheckAnswer = [container foreignWindowIsUnderPointer];
    }

  return foreignCheckAnswer;
}

/* The icon whose image or name is under the pointer, leaving out the ones
 * being dragged; nil when there is none. */
- (FSNIcon *)localIconAtPoint:(NSPoint)containerPoint
                    excluding:(NSArray *)dragged
{
  NSArray *reps;
  NSUInteger i;

  if ([container respondsToSelector: @selector(reps)] == NO)
    return nil;

  reps = [container reps];
  for (i = 0; i < [reps count]; i++)
    {
      FSNIcon *ic = [reps objectAtIndex: i];

      if ([ic isKindOfClass: [FSNIcon class]] == NO)
	continue;
      if ([dragged containsObject: ic])
	continue;
      if ([ic pointIsOnNode: [ic convertPoint: containerPoint fromView: container]])
	return ic;
    }

  return nil;
}

/* Whether the dragged files could be filed into this icon.  Candidates are
 * all siblings of what is being dragged, which is what makes the test this
 * short: the long validation in -draggingEntered: guards drops that cross
 * folders, and none of what it rules out - a folder into itself or into its
 * own subtree, a name already taken by a directory over there, an
 * unwritable source - can arise between siblings of one folder. */
- (BOOL)iconTakesLocalDrop:(FSNIcon *)ic
{
  FSNode *nd = [ic node];

  if (ic == nil)
    return NO;
  if (([nd isDirectory] == NO) || [nd isLocked] || ([nd isWritable] == NO))
    return NO;
  if ([nd isPackage] && ([nd isApplication] == NO))
    return NO;

  return YES;
}

/* File the dragged icons into the icon they were dropped on: hand them to it
 * if it is an application, otherwise run the operation the held modifiers
 * ask for.  Source and destination are in one folder, hence one volume, so a
 * plain drag always moves. */
- (void)finishLocalDrop:(NSArray *)dragged onIcon:(FSNIcon *)target
{
  NSMutableArray *paths = [NSMutableArray arrayWithCapacity: [dragged count]];
  NSUInteger i;

  for (i = 0; i < [dragged count]; i++)
    [paths addObject: [[[dragged objectAtIndex: i] node] path]];

  if ([[target node] isApplication])
    [target openDroppedPaths: paths];
  else
    [target fileDroppedPaths: paths
		   operation: FSNOperationForDragMask(dragOperationForCurrentModifierFlags())];
}

/* Icons dropped into another window stay hidden while their files move
 * away: showing them back at the old place first would look like the drop
 * had failed.  A copy or link leaves the originals, so they come back at
 * once; a move that did not happen - cancelled in its confirmation, or
 * refused - brings them back once there has been time for it. */
- (void)revealIconsAfterDrop:(NSArray *)dragged accepted:(BOOL)accepted
{
  NSDragOperation op = dragOperationForCurrentModifierFlags();

  if (accepted == NO || (op & (NSDragOperationCopy | NSDragOperationLink)))
    {
      [self revealIconsStillPresent: dragged];
      return;
    }

  [self performSelector: @selector(revealIconsStillPresent:)
             withObject: dragged
             afterDelay: 1.5];
}

- (void)revealIconsStillPresent:(NSArray *)dragged
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUInteger i;

  for (i = 0; i < [dragged count]; i++)
    {
      FSNIcon *ic = [dragged objectAtIndex: i];

      if ([fm fileExistsAtPath: [[ic node] path]] && [ic isHidden])
	{
	  [ic setHidden: NO];
	  [[ic superview] setNeedsDisplayInRect: [ic frame]];
	}
    }
}

/*
 * Local icon repositioning (free positioning mode).
 * Moves ALL selected icons together, keeping labels visible.
 * On drop persists every moved icon's position via the container.
 *
 * Over the view the icons live in, they follow the pointer as views.  Over
 * any other of the application's windows, or another drop view of this one,
 * they travel on as an image and that window's drop views get the drag (see
 * FSNIconDragSession).  Only another application's window needs GNUstep's
 * drag machinery, and the move hands over to it there.
 */
- (void)repositionLocal:(NSEvent *)firstEvent offset:(NSSize)initialOffset
{
  NSWindow *win = [self window];
  NSPoint startLoc = [firstEvent locationInWindow];
  NSPoint curLoc = NSMakePoint(startLoc.x + initialOffset.width,
                               startLoc.y + initialOffset.height);
  NSPoint lastLoc = NSMakePoint(-1, -1);
  NSUInteger mask = NSLeftMouseDraggedMask | NSLeftMouseUpMask | NSPeriodicMask;
  FSNSpringLoader *loader = [FSNSpringLoader sharedLoader];
  FSNIconDragSession *session;
  NSView *home;
  NSEvent *event;
  FSNIcon *dropTarget = nil;
  FSNIcon *springIcon = nil;
  BOOL didMove = NO;
  NSTimeInterval lastFrame = 0.0;
  BOOL framePending = NO;

  /* Collect all selected icons and record their original frames */
  NSMutableArray *allIcons = [NSMutableArray arrayWithObject: self];
  NSMutableArray *origFrames = [NSMutableArray array];
  [origFrames addObject: [NSValue valueWithRect: [self frame]]];

  if ([container respondsToSelector: @selector(selectedReps)])
    {
      NSArray *sel = [container selectedReps];
      NSUInteger i;
      for (i = 0; i < [sel count]; i++)
        {
          id rep = [sel objectAtIndex: i];
          if (rep != self && [rep isKindOfClass: [FSNIcon class]])
            {
              [allIcons addObject: rep];
              [origFrames addObject: [NSValue valueWithRect: [rep frame]]];
            }
        }
    }

  /* Drag deltas must be expressed in the container's coordinate space,
   * not window base coords: the spatial container (GWSpatialIconsView)
   * is flipped, so window Y-up would move frames the wrong way.
   * -convertPoint:fromView:nil accounts for the flip; for non-flipped
   * containers (browser/desktop) the container delta equals the window
   * delta, so this is a no-op there. */
  NSPoint startLocal = [container convertPoint: startLoc fromView: nil];

  home = [container enclosingScrollView];
  if (home == nil)
    home = container;

  session = AUTORELEASE ([[FSNIconDragSession alloc] initWithIcons: allIcons
                                                            source: self
                                                          inWindow: win]);

  FSNForgetForeignWindowAnswer();
  FSNRaiseDraggedIcons(container, allIcons);
  FSNSetIconsBeingDragged(allIcons, YES);

  /* Apply the initial offset from the drag-start event immediately.
   * The first drag event is consumed by mouseDown's while-loop before
   * we're called, so we seed the movement here. */
  {
    NSPoint seedEndLocal = [container convertPoint: curLoc fromView: nil];
    CGFloat dx = seedEndLocal.x - startLocal.x;
    CGFloat dy = seedEndLocal.y - startLocal.y;

    if (fabs(dx) > 0.5 || fabs(dy) > 0.5)
      {
        FSNMoveDraggedIcons(container, allIcons, origFrames, dx, dy);
        didMove = YES;
      }
  }

  /* Periodic events keep the loop turning while the pointer rests: that is
   * what times a folder springing open under it. */
  [NSEvent startPeriodicEventsAfterDelay: 0.05 withPeriod: 0.05];

  while (1)
    {
      NSEvent *pendingUp = nil;
      NSPoint screen;
      NSWindow *under;
      NSView *hit;
      BOOL overHome = NO;

      /* A position held back until the next frame is acted on when that
       * frame is due, whether or not the pointer moves on by then. */
      event = [NSApp nextEventMatchingMask: mask
                                 untilDate: framePending
          ? [NSDate dateWithTimeIntervalSinceReferenceDate: lastFrame + FSNMoveFrameInterval]
          : [NSDate distantFuture]
                                    inMode: NSEventTrackingRunLoopMode
                                   dequeue: YES];

      /* X11 delivers motion faster than the icons can be redrawn, so only the
       * newest position is acted on - but it is always acted on, even when the
       * button has already come up behind it.  That last position is the one
       * that decides where the icons land and whether a folder takes them, so
       * dropping it would lose the drop. */
      while ([event type] != NSLeftMouseUp)
        {
          NSEvent *queued;

          if ([event type] == NSLeftMouseDragged)
            curLoc = [event locationInWindow];

          queued = [NSApp nextEventMatchingMask: mask
                                      untilDate: [NSDate distantPast]
                                         inMode: NSEventTrackingRunLoopMode
                                        dequeue: YES];
          if (queued == nil)
            break;
          if ([queued type] == NSLeftMouseUp)
            {
              pendingUp = queued;
              break;
            }
          event = queued;
        }

      if ([event type] == NSLeftMouseUp)
        break;

      /* A tick with the pointer at rest only times a spring: nothing moved,
       * so nothing needs to be looked up or drawn again.  Redrawing the icons
       * on every tick is what made a drag across the Desktop stutter. */
      if (NSEqualPoints(curLoc, lastLoc))
        {
          if ([session isAway])
            {
              [session dragAwayRests];
            }
          else
            {
              if (springIcon != nil)
                [loader pointerRestsOnNode: [springIcon node]
                                    inView: springIcon
                                   flasher: springIcon
                              draggedPaths: [session paths]];
              [loader dragIsOverWindow: win];
            }

          if (pendingUp != nil)
            break;
          continue;
        }
      if (pendingUp == nil
          && [NSDate timeIntervalSinceReferenceDate] - lastFrame < FSNMoveFrameInterval)
        {
          framePending = YES;
          continue;
        }
      framePending = NO;
      lastFrame = [NSDate timeIntervalSinceReferenceDate];
      lastLoc = curLoc;

      screen = [win convertBaseToScreen: curLoc];

      /* Another application's window: only GNUstep's drag machinery reaches
       * it.  The icons go back to where the gesture started first. */
      if ([self otherApplicationIsUnderPointer])
        {
          [NSEvent stopPeriodicEvents];
          [session returnToSource];
          [dropTarget setDropHighlighted: NO];
          [loader pointerLeftView: springIcon];
          FSNSetIconsBeingDragged(allIcons, NO);
          FSNRestoreDraggedIcons(container, allIcons, origFrames);
          [self startExternalDragOnEvent: firstEvent withMouseOffset: initialOffset];
          return;
        }

      under = [session windowAtScreenPoint: screen];
      if (under == win)
        {
          for (hit = [[[win contentView] superview] hitTest: curLoc];
               hit != nil; hit = [hit superview])
            {
              if (hit == home)
                {
                  overHome = YES;
                  break;
                }
            }
        }

      if (overHome)
        {
          NSPoint localInContainer;
          FSNIcon *hover;

          [session returnToSource];

          /* Reach the parts of a canvas larger than its viewport.  The
           * deltas below are in container coordinates, which scrolling does
           * not change, so this composes with the move. */
          if ([event type] == NSLeftMouseDragged)
            [container autoscroll: event];

          /* Delta in container space (see startLocal above): correct for
           * both the flipped spatial container and non-flipped ones. */
          localInContainer = [container convertPoint: curLoc fromView: nil];

          hover = [self localIconAtPoint: localInContainer excluding: allIcons];

          /* A folder under the pointer opens up to say that letting go here
           * files the icons into it instead of leaving them on the spot. */
          {
            FSNIcon *target = [self iconTakesLocalDrop: hover] ? hover : nil;

            if (target != dropTarget)
              {
                [dropTarget setDropHighlighted: NO];
                dropTarget = target;
                [dropTarget setDropHighlighted: YES];
              }
          }

          /* A folder the icons rest on springs open - also one that cannot
           * take them itself, since the move may be heading further down. */
          if (hover != springIcon)
            {
              [loader pointerLeftView: springIcon];
              springIcon = hover;
            }
          if (springIcon != nil)
            [loader pointerRestsOnNode: [springIcon node]
                                inView: springIcon
                               flasher: springIcon
                          draggedPaths: [session paths]];

          FSNMoveDraggedIcons(container, allIcons, origFrames,
                              localInContainer.x - startLocal.x,
                              localInContainer.y - startLocal.y);
          didMove = YES;

          [loader dragIsOverWindow: win];
        }
      else
        {
          [dropTarget setDropHighlighted: NO];
          dropTarget = nil;
          [loader pointerLeftView: springIcon];
          springIcon = nil;

          [session dragAwayOverWindow: under atScreenPoint: screen];
        }

      if (pendingUp != nil)
        break;
    }

  [NSEvent stopPeriodicEvents];
  [loader pointerLeftView: springIcon];

  if ([session isAway])
    {
      BOOL accepted = [session dropAtScreenPoint: [win convertBaseToScreen: curLoc]];

      FSNSetIconsBeingDragged(allIcons, NO);
      /* Back to where they were while still hidden, so nothing jumps. */
      FSNRestoreDraggedIcons(container, allIcons, origFrames);
      [self revealIconsAfterDrop: allIcons accepted: accepted];
      return;
    }

  FSNSetIconsBeingDragged(allIcons, NO);

  /* The drop lands in this window, where the gesture started: nothing a
   * folder sprang open in stays open. */
  [loader dragDroppedInWindow: win];

  /* Let go over a folder: the icons go back where they were and the files
   * move into it.  A free-position drag never reaches the drag machinery, so
   * this is the only place such a drop can be recognised. */
  if (dropTarget)
    {
      [dropTarget setDropHighlighted: NO];
      FSNRestoreDraggedIcons(container, allIcons, origFrames);
      [self finishLocalDrop: allIcons onIcon: dropTarget];
      return;
    }

  if (didMove && [container respondsToSelector: @selector(batchRepositionIcons:toCenterPoints:)])
    {
      /* Batch-reposition all moved icons — tiles once, persists once.
       * No legacy fallback: batchReposition is the only code path. */
      NSUInteger i;
      NSMutableArray *centers = [NSMutableArray arrayWithCapacity: [allIcons count]];
      for (i = 0; i < [allIcons count]; i++)
        {
          FSNIcon *ic = [allIcons objectAtIndex: i];
          NSRect frm = [ic frame];
          NSPoint center = NSMakePoint(frm.origin.x + frm.size.width / 2.0,
                                        frm.origin.y + frm.size.height / 2.0);
          [centers addObject: [NSValue valueWithPoint: center]];
        }
      [container batchRepositionIcons: allIcons toCenterPoints: centers];
    }
  else if (!didMove)
    {
      FSNRestoreDraggedIcons(container, allIcons, origFrames);
    }
}

@end


@implementation FSNIcon (DraggingSource)

- (void)startExternalDragOnEvent:(NSEvent *)event
                 withMouseOffset:(NSSize)offset
{
  if ([container respondsToSelector: @selector(selectedPaths)])
    {
      NSArray *selectedPaths = [container selectedPaths];
      NSPasteboard *pb = [NSPasteboard pasteboardWithName: NSDragPboard];

      [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
		 owner: nil];

      if ([pb setPropertyList: selectedPaths forType: NSFilenamesPboardType])
	{
	  NSImage *dragIcon;

	  if ([selectedPaths count] == 1)
	    {
	      dragIcon = icon;
	    }
	  else
	    {
	      dragIcon = [fsnodeRep multipleSelectionIconOfSize: iconSize];
	    }

	  /* Command+Alternate drags create Alias records - mark the drag
	   * with the alias arrow so the user can tell it from a copy or
	   * symlink. */
	  if (FSNLinkDropCreatesAlias())
	    {
	      dragIcon = FSNLinkBadgedImage(dragIcon);
	    }

	  /* Check if all selected paths are mountpoints and notify the Dock */
	  [self notifyDockAboutDragWithPaths: selectedPaths];

	  [self dragImage: dragIcon
		       at: icnPoint
		   offset: offset
		    event: event
	       pasteboard: pb
		   source: self
		slideBack: slideBack];
	}
    }
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag
{
  return NSDragOperationEvery;
}

- (void)draggedImage:(NSImage *)anImage
             endedAt:(NSPoint)aPoint
           deposited:(BOOL)flag
{
  dragdelay = 0;
  onSelf = NO;

  /* Notify the Dock that the drag has ended */
  [[NSNotificationCenter defaultCenter] postNotificationName: @"GWDragMountpointEnded" object: nil];

  if ([container respondsToSelector: @selector(restoreLastSelection)])
    {
      [container restoreLastSelection];
    }

  if (flag == NO)
    {
      if ([container respondsToSelector: @selector(removeUndepositedRep:)])
	{
	  [container removeUndepositedRep: self];
	}
    }
}

- (void)notifyDockAboutDragWithPaths:(NSArray *)paths
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSArray *volumePaths = [workspace mountedLocalVolumePaths];
  BOOL allAreMountpoints = YES;
  NSUInteger i;

  if ([paths count] == 0) {
    allAreMountpoints = NO;
  } else {
    for (i = 0; i < [paths count]; i++) {
      NSString *path = [paths objectAtIndex: i];
      if (![volumePaths containsObject: path]) {
        allAreMountpoints = NO;
        break;
      }
    }
  }

  /* Post notification to update the Dock's Trash icon */
  NSDictionary *userInfo = [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: allAreMountpoints]
                                                      forKey: @"allAreMountpoints"];
  [[NSNotificationCenter defaultCenter] postNotificationName: @"GWDragMountpointStarted" 
                                                      object: nil 
                                                    userInfo: userInfo];
}

@end


@implementation FSNIcon (DraggingDestination)

/* The drag machinery picks its destination by view frame, and ours also
 * covers the padding around the image and the name.  Only image and name
 * stand for the node, so anywhere else the icon steps aside and lets the view
 * behind it handle the drag: a drop in the padding around a plain file used
 * to do nothing at all, and one in the padding around a folder went into that
 * folder although nothing had highlighted to say so. */
/* Only a container that implements the whole NSDraggingDestination sequence
 * can be handed a drag: the path view, for one, answers -draggingUpdated:
 * alone, and the rest of the sequence would be sent into nothing. */
- (BOOL)containerTakesDrags
{
  return ([container respondsToSelector: @selector(draggingEntered:)]
          && [container respondsToSelector: @selector(draggingUpdated:)]
          && [container respondsToSelector: @selector(prepareForDragOperation:)]
          && [container respondsToSelector: @selector(performDragOperation:)]
          && [container respondsToSelector: @selector(concludeDragOperation:)]);
}

- (BOOL)draggingPointIsOnNode:(id <NSDraggingInfo>)sender
{
  NSPoint p = [self convertPoint: [sender draggingLocation] fromView: nil];

  if (icnPosition == NSImageOnly)
    return [self mouse: p inRect: icnBounds];

  return ([self mouse: p inRect: icnBounds] || [self mouse: p inRect: labelRect]);
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSDragOperation sourceDragMask;
  NSArray *sourcePaths;
  NSString *fromPath;
  NSString *nodePath;
  NSString *prePath;
  NSUInteger i, count;

  isDragTarget = NO;
  onSelf = NO;

  if ([self draggingPointIsOnNode: sender] == NO && [self containerTakesDrags])
    {
      dragProxied = YES;
      return [container draggingEntered: sender];
    }
  dragProxied = NO;

  pb = [sender draggingPasteboard];
  sourcePaths = nil;

  if ([[pb types] containsObject: NSFilenamesPboardType])
    {
      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
    }
  
  /* Check for ISO drop onto mount point BEFORE general writability checks */
  if (sourcePaths && [sourcePaths count] == 1 && [node isMountPoint])
    {
      NSString *droppedPath = [sourcePaths objectAtIndex: 0];
      Class handlerClass = NSClassFromString(@"ISOWriteHandler");


      if (!handlerClass) {
      } else if ([handlerClass respondsToSelector:@selector(validationMessageForISODrop:ontoNode:)]) {
        NSString *diag = [handlerClass validationMessageForISODrop:droppedPath ontoNode:node];
        if (diag == nil) {
          isDragTarget = YES;
          return NSDragOperationCopy;
        } else {
        }
      } else if ([handlerClass respondsToSelector: @selector(canHandleISODrop:ontoNode:)]) {
        if ([handlerClass canHandleISODrop: droppedPath ontoNode: node]) {
          isDragTarget = YES;
          return NSDragOperationCopy;
        } else {
        }
      } else {
      }
    }

  if (selection || isLocked || ([node isDirectory] == NO)
      || (([node isWritable] == NO) && ([node isApplication] == NO)))
    {
      return NSDragOperationNone;
    }

  if ([node isDirectory])
    {
      if ([node isSubnodeOfPath: [desktopApp trashPath]])
	{
	  return NSDragOperationNone;
	}
    }

  if ([node isPackage] && ([node isApplication] == NO))
    {
      if ([container respondsToSelector: @selector(baseNode)])
	{
	  if ([node isEqual: [container baseNode]] == NO)
	    {
	      return NSDragOperationNone;
	    }
	}
      else
	{
	  return NSDragOperationNone;
	}
    }

  if (sourcePaths == nil && [[pb types] containsObject: NSFilenamesPboardType])
    {
      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
    }
  else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      if ([node isPackage] == NO)
	{
	  NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
	  NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

	  sourcePaths = [pbDict objectForKey: @"paths"];
	}
    }
  else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      if ([node isPackage] == NO)
	{
	  NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
	  NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

	  sourcePaths = [pbDict objectForKey: @"paths"];
	}
    }

  if (sourcePaths == nil)
    {
    return NSDragOperationNone;
    }

  count = [sourcePaths count];
  if (count == 0)
    {
      return NSDragOperationNone;
    }

  nodePath = [node path];

  if (selection)
    {
      if ([selection isEqual: sourcePaths])
	{
	  onSelf = YES;
	}
    }
  else if (count == 1)
    {
      if ([nodePath isEqual: [sourcePaths objectAtIndex: 0]])
	{
	  onSelf = YES;
	}
    }

  if (onSelf)
    {
      isDragTarget = YES;
      return NSDragOperationMove;
    }

  fromPath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  if ([nodePath isEqual: fromPath])
    {
      return NSDragOperationNone;
    }

  if ([sourcePaths containsObject: nodePath])
    {
      return NSDragOperationNone;
    }

  prePath = [NSString stringWithString: nodePath];

  while (![prePath isEqual: path_separator()])
    {
      if ([sourcePaths containsObject: prePath])
        return NSDragOperationNone;
      prePath = [prePath stringByDeletingLastPathComponent];
    }


  if ([node isDirectory] && [node isParentOfPath: fromPath])
    {
      NSArray *subNodes = [node subNodes];

      for (i = 0; i < [subNodes count]; i++)
	{
	  FSNode *nd = [subNodes objectAtIndex: i];

	  if ([nd isDirectory])
	    {
	      NSUInteger j;

	      for (j = 0; j < count; j++) {
		NSString *fname = [[sourcePaths objectAtIndex: j] lastPathComponent];

		if ([[nd name] isEqual: fname])
		  {
		    return NSDragOperationNone;
		  }
	      }
	    }
	}
    }

  if ([node isApplication])
    {
      if (([container respondsToSelector: @selector(baseNode)] == NO)
	  || ([node isEqual: [container baseNode]] == NO))
	{
	  for (i = 0; i < count; i++)
	    {
	      CREATE_AUTORELEASE_POOL(arp);
	      FSNode *nd = [FSNode nodeWithPath: [sourcePaths objectAtIndex: i]];

	      if (([nd isPlain] == NO) && ([nd isPackage] == NO))
		{
		  RELEASE (arp);
		  return NSDragOperationNone;
		}
	      RELEASE (arp);
	    }
	}
      else if ([node isEqual: [container baseNode]] == NO)
	{
	  return NSDragOperationNone;
	}
    }

  isDragTarget = YES;
  forceCopy = NO;

  onApplication = ([node isApplication]
		   && [container respondsToSelector: @selector(baseNode)]
		   && [node isEqual: [container baseNode]]);

  sourceDragMask = dragOperationForCurrentModifierFlags();
  if (sourceDragMask & NSDragOperationMove)
    {
      if (([[NSFileManager defaultManager] isWritableFileAtPath: fromPath]
	   && pathsAreOnSameVolume(fromPath, nodePath))
	  || ([node isApplication] && (onApplication == NO)))
	{
	  negotiatedDragOp = NSDragOperationMove;
	  return NSDragOperationMove;
	}
      else if (([node isApplication] == NO) || onApplication)
	{
	  forceCopy = YES;
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
    }

  if (sourceDragMask & NSDragOperationCopy)
    {
      if ([node isApplication])
	{
	  negotiatedDragOp = (onApplication ? NSDragOperationCopy : NSDragOperationMove);
	  return negotiatedDragOp;
	}
      else
	{
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
    }

  if (sourceDragMask & NSDragOperationLink)
    {
      if ([node isApplication])
	{
	  negotiatedDragOp = (onApplication ? NSDragOperationLink : NSDragOperationMove);
	  return negotiatedDragOp;
	}
      else
	{
	  negotiatedDragOp = NSDragOperationLink;
	  return NSDragOperationLink;
	}
    }

  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSDragOperation sourceDragMask = dragOperationForCurrentModifierFlags();

  if ([self draggingPointIsOnNode: sender] == NO)
    {
      [[FSNSpringLoader sharedLoader] pointerLeftView: self];

      if (drawicon == selectedicon)
	{
	  drawicon = icon;
	  [self setNeedsDisplay: YES];
	}
      /* The view behind us never saw the drag enter, so announce it there
	 before asking it what it makes of the drag. */
      if (dragProxied == NO && [self containerTakesDrags])
	{
	  isDragTarget = NO;
	  dragProxied = YES;
	  [container draggingEntered: sender];
	}
      return [container draggingUpdated: sender];
    }
  else
    {
      if (dragProxied)
	{
	  dragProxied = NO;
	  [container draggingExited: sender];
	  return [self draggingEntered: sender];
	}

      if ((selectedicon == nil) && isDragTarget && (onSelf == NO))
	{
	  ASSIGN (selectedicon, [fsnodeRep openFolderIconOfSize: iconSize forNode: node]);
	}
      if (selectedicon && (drawicon == icon) && isDragTarget && (onSelf == NO))
	{
	  drawicon = selectedicon;
	  [self setNeedsDisplay: YES];
	}

      /* A folder the drag rests on springs open after a while - also one
	 that cannot take the drop itself, since the drag may be heading for
	 a folder further down. */
      if (onSelf == NO)
	{
	  [[FSNSpringLoader sharedLoader]
	    pointerRestsOnNode: node
			inView: self
		       flasher: self
		  draggedPaths: [FSNSpringLoader draggedPathsOfDraggingInfo: sender]];
	}
    }

  if (isDragTarget == NO)
    {
      return NSDragOperationNone;
    }

  if (sourceDragMask & NSDragOperationMove)
    {
      negotiatedDragOp = forceCopy ? NSDragOperationCopy : NSDragOperationMove;
      return negotiatedDragOp;
    }

  if (sourceDragMask & NSDragOperationCopy)
    {
      if ([node isApplication])
	{
	  negotiatedDragOp = (onApplication ? NSDragOperationCopy : NSDragOperationMove);
	  return negotiatedDragOp;
	}
      else
	{
	  negotiatedDragOp = NSDragOperationCopy;
	  return NSDragOperationCopy;
	}
    }

  if (sourceDragMask & NSDragOperationLink)
    {
      if ([node isApplication])
	{
	  negotiatedDragOp = (onApplication ? NSDragOperationLink : NSDragOperationMove);
	  return negotiatedDragOp;
	}
      else
	{
	  negotiatedDragOp = NSDragOperationLink;
	  return NSDragOperationLink;
	}
    }

  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  [[FSNSpringLoader sharedLoader] pointerLeftView: self];
  isDragTarget = NO;

  if (dragProxied)
    {
      dragProxied = NO;
      [container draggingExited: sender];
    }

  if (onSelf == NO)
    {
      drawicon = icon;
      [container setNeedsDisplayInRect: [self frame]];
      [self setNeedsDisplay: YES];
    }

  onSelf = NO;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  if (dragProxied)
    return [container prepareForDragOperation: sender];

  return isLocked ? NO : isDragTarget;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  if (dragProxied)
    return [container performDragOperation: sender];

  return isLocked ? NO : isDragTarget;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSArray *sourcePaths;
  NSString *operation;
  NSString *source;
  NSString *trashPath;

  isDragTarget = NO;
  operation = nil;

  if (dragProxied)
    {
      dragProxied = NO;
      [container concludeDragOperation: sender];
      return;
    }

  if (isLocked)
    {
      return;
    }

  if (onSelf)
    {
      [container resizeWithOldSuperviewSize: [container frame].size];
      onSelf = NO;
      return;
    }

  drawicon = icon;
  [self setNeedsDisplay: YES];

  pb = [sender draggingPasteboard];

  if ([node isPackage] == NO)
    {
      if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
	{
	  NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];

	  [desktopApp concludeRemoteFilesDragOperation: pbData
					   atLocalPath: [node path]];
	  return;

	}
      else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
	{
	  NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];

	  [desktopApp lsfolderDragOperation: pbData
			    concludedAtPath: [node path]];
	  return;
	}
    }

  sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

  /* Check for ISO file drop onto physical device mount point */
  if ([sourcePaths count] == 1 && [node isMountPoint])
    {
      NSString *droppedPath = [sourcePaths objectAtIndex: 0];
      Class handlerClass = NSClassFromString(@"ISOWriteHandler");
      
      if (handlerClass && 
          [handlerClass respondsToSelector: @selector(canHandleISODrop:ontoNode:)] &&
          [handlerClass canHandleISODrop: droppedPath ontoNode: node])
        {
          /* Let ISOWriteHandler handle this - it will show confirmation dialog */
          if ([handlerClass handleISODrop: droppedPath ontoNode: node])
            {
              return; /* ISO write flow handled it */
            }
          /* If handleISODrop returns NO, user chose to copy file normally */
        }
    }

  if (([node isApplication] == NO) || onApplication)
    {
      source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
      trashPath = [desktopApp trashPath];

      if ([source isEqual: trashPath])
	{
	  operation = @"WorkspaceRecycleOutOperation";
	}
      else
	{
	  operation = FSNOperationForDragMask(negotiatedDragOp);
	}

      [self fileDroppedPaths: sourcePaths operation: operation];
    }
  else
    {
      [self openDroppedPaths: sourcePaths];
    }
}

- (void)openDroppedPaths:(NSArray *)paths
{
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex: i];

      NS_DURING
        {
          /* Resolve Workspace at runtime to avoid circular link dependency
           * between FSNode framework and Workspace app. */
          Class wsClass = NSClassFromString(@"Workspace");
          id gw = nil;
          if (wsClass && [wsClass respondsToSelector: @selector(gworkspace)])
            gw = [wsClass performSelector: @selector(gworkspace)];
          if (gw)
            [gw openFile: path withApplication: [node name]];
          else
            [[NSWorkspace sharedWorkspace] openFile: path withApplication: [node name]];
        }
      NS_HANDLER
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""),
                  [NSString stringWithFormat: @"%@ %@!",
                    NSLocalizedString(@"Can't open ", @""), [node name]],
                  NSLocalizedString(@"OK", @""),
                  nil,
                  nil);
        }
      NS_ENDHANDLER
    }
}

- (void)fileDroppedPaths:(NSArray *)paths operation:(NSString *)operation
{
  NSMutableArray *files = [NSMutableArray arrayWithCapacity: [paths count]];
  NSMutableDictionary *opDict = [NSMutableDictionary dictionaryWithCapacity: 4];
  NSUInteger i;

  if ([paths count] == 0)
    return;

  for (i = 0; i < [paths count]; i++)
    [files addObject: [[paths objectAtIndex: i] lastPathComponent]];

  [opDict setObject: operation forKey: @"operation"];
  [opDict setObject: [[paths objectAtIndex: 0] stringByDeletingLastPathComponent]
	      forKey: @"source"];
  [opDict setObject: [node path] forKey: @"destination"];
  [opDict setObject: files forKey: @"files"];

  [desktopApp performFileOperation: opDict];
}

@end


@implementation FSNIconNameEditor

- (void)dealloc
{
  RELEASE (node);
  [super dealloc];
}

- (void)setNode:(FSNode *)anode
    stringValue:(NSString *)str
{
  DESTROY (node);
  if (anode)
    {
      ASSIGN (node, anode);
    }
  [self setStringValue: str];
}

- (FSNode *)node
{
  return node;
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];
  container = (NSView <FSNodeRepContainer> *)[self superview];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if ([self isEditable] == NO)
    {
      if ([container respondsToSelector: @selector(canStartRepNameEditing)]
	  && [container canStartRepNameEditing])
	{
	  [self setAlignment: NSLeftTextAlignment];
	  [self setSelectable: YES];
	  [self setEditable: YES];
	  [[self window] makeFirstResponder: self];
	}
    }
  else
    {
      [super mouseDown: theEvent];
    }
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  if ([self window] && node)
    {
      NSString *desc = GSDirectoryDescriptionForPath([node path]);
      if (desc)
        {
          [self setToolTip: desc];
        }
    }
}

@end
