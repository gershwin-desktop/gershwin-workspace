/* FSNIconsView.m
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
#include <unistd.h>
#include <sys/types.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepGUI/GSVersion.h>

#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"
#import "FSNIconPositionStore.h"
#import "FSNPlacementEnumerator.h"

#define DEF_ICN_SIZE 48
#define DEF_TEXT_SIZE 12
#define DEF_ICN_POS NSImageAbove

/* Left margin from view edge.  This is distinct from COLUMN_GAP_X below
 * because DS_Store positions use a ~26px left margin but 32px column gap.
 * Using the same value for both would cause AUTO-mode and DS_Store icons
 * in the rightmost column to be at different x positions (the 6px offset
 * bug).  Keep them separate and never conflate them. */
#define X_MARGIN (26)
/* Horizontal gap BETWEEN grid columns (not the left margin).
 * Matches the 128px column spacing (96px icon + 32px gap) used by DS_Store.
 * Must be separate from X_MARGIN — see above. */
#define COLUMN_GAP_X (32)
#define Y_MARGIN (12)

#define EDIT_MARGIN (4)

#ifndef max
  #define max(a,b) ((a) >= (b) ? (a):(b))
#endif

#ifndef min
  #define min(a,b) ((a) <= (b) ? (a):(b))
#endif

#define CHECK_SIZE(s) \
if (s.width < 1) s.width = 1; \
if (s.height < 1) s.height = 1; \
if (s.width > maxr.size.width) s.width = maxr.size.width; \
if (s.height > maxr.size.height) s.height = maxr.size.height

#define SETRECT(o, x, y, w, h) { \
NSRect rct = NSMakeRect(x, y, w, h); \
if (rct.size.width < 0) rct.size.width = 0; \
if (rct.size.height < 0) rct.size.height = 0; \
[o setFrame: NSIntegralRect(rct)]; \
}

/* we redefine the dockstyle to read the preferences without including Dock.h" */
typedef enum DockStyle
{
  DockStyleClassic = 0,
  DockStyleModern = 1
} DockStyle;

static void GWHighlightFrameRect(NSRect aRect)
{
  NSFrameRectWithWidthUsingOperation(aRect, 1.0, GSCompositeHighlight);
}


@implementation FSNIconsView

- (void)dealloc
{
  if (_observedClipView)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self
                                                      name: NSViewFrameDidChangeNotification
                                                    object: _observedClipView];
      _observedClipView = nil;
    }
  RELEASE (node);
  RELEASE (extInfoType);
  RELEASE (icons);
  RELEASE (labelFont);
  RELEASE (nameEditor);
  RELEASE (horizontalImage);
  RELEASE (verticalImage);
  RELEASE (lastSelection);
  RELEASE (charBuffer);
  RELEASE (backColor);
  RELEASE (textColor);
  RELEASE (disabledTextColor);
  RELEASE (backgroundImage);
  RELEASE (customIconPositions);

  [super dealloc];
}

- (id)init
{
  self = [super init];

  if (self)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *appName = [defaults stringForKey: @"DesktopApplicationName"];
      NSString *selName = [defaults stringForKey: @"DesktopApplicationSelName"];
      id defentry;

      fsnodeRep = [FSNodeRep sharedInstance];

      if (appName && selName)
	{
	  Class desktopAppClass = [[NSBundle mainBundle] classNamed: appName];
	  SEL sel = NSSelectorFromString(selName);
	  desktopApp = [desktopAppClass performSelector: sel];
	}

      /* we tie the transparent selection to the modern dock style */
      transparentSelection = NO;
      defentry = [defaults objectForKey: @"dockstyle"];
      if ([defentry intValue] == DockStyleModern)
	transparentSelection = YES;

      ASSIGN (backColor, [NSColor windowBackgroundColor]);
      ASSIGN (textColor, [NSColor controlTextColor]);
      ASSIGN (disabledTextColor, [NSColor disabledControlTextColor]);

      defentry = [defaults objectForKey: @"iconsize"];
      iconSize = defentry ? [defentry intValue] : DEF_ICN_SIZE;

      defentry = [defaults objectForKey: @"labeltxtsize"];
      labelTextSize = defentry ? [defentry intValue] : DEF_TEXT_SIZE;
      ASSIGN (labelFont, [NSFont systemFontOfSize: labelTextSize]);

      defentry = [defaults objectForKey: @"iconposition"];
      iconPosition = defentry ? [defentry intValue] : DEF_ICN_POS;

      defentry = [defaults objectForKey: @"fsn_info_type"];
      infoType = defentry ? [defentry intValue] : FSNInfoNameType;
      extInfoType = nil;

      if (infoType == FSNInfoExtendedType)
	{
	  defentry = [defaults objectForKey: @"extended_info_type"];

	  if (defentry)
	    {
	      NSArray *availableTypes = [fsnodeRep availableExtendedInfoNames];

	      if ([availableTypes containsObject: defentry])
		{
		  ASSIGN (extInfoType, defentry);
		}
	    }

	  if (extInfoType == nil)
	    {
	      infoType = FSNInfoNameType;
	    }
	}


      nameEditor = [FSNIconNameEditor new];
      [nameEditor setDelegate: self];
      [nameEditor setFont: labelFont];
      [nameEditor setBezeled: NO];
      [nameEditor setAlignment: NSCenterTextAlignment];
      [nameEditor setBackgroundColor: backColor];
      [nameEditor setTextColor: textColor];
      [nameEditor setEditable: NO];
      [nameEditor setSelectable: NO];
      editIcon = nil;

      icons = [NSMutableArray new];
      isDragTarget = NO;
      lastKeyPressedTime = 0.0;
      charBuffer = nil;
      selectionMask = NSSingleSelectionMask;
      
      // DS_Store free positioning support
      customIconPositions = nil;
      dsStoreIconHeight = 64.0; // Default icon height for coordinate conversion

      [self calculateGridSize];

      [self registerForDraggedTypes: [NSArray arrayWithObjects:
						NSFilenamesPboardType,
					      @"GWLSFolderPboardType",
					      @"GWRemoteFilenamesPboardType",
					      nil]];

      /* Enable resize notification so resizeWithOldSuperviewSize:
       * (which calls tile) is actually invoked. */
      [self setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    }

  return self;
}

- (void)sortIcons
{
  if (infoType == FSNInfoExtendedType)
    {
      [icons sortUsingFunction: compareWithExtType
		       context: (void *)NULL];
    }
  else
    {
      [icons sortUsingSelector: [fsnodeRep compareSelectorForDirectory: [node path]]];
    }
}

- (void)calculateGridSize
{
  NSSize highlightSize = NSZeroSize;
  NSSize labelSize = NSZeroSize;
  int lblmargin = [fsnodeRep labelMargin];

  highlightSize.width = ceil(iconSize + 6);
  highlightSize.height = highlightSize.width;

  labelSize.height = floor([fsnodeRep heightOfFont: labelFont]);
  labelSize.width = [fsnodeRep labelWFactor] * labelTextSize;

  gridSize.height = highlightSize.height;

  if (infoType != FSNInfoNameType)
    {
      float lbsh = (labelSize.height * 2) - 2;

      if (iconPosition == NSImageAbove)
	{
	  gridSize.height += lbsh;
	  gridSize.width = (labelSize.width > highlightSize.width) ? labelSize.width : highlightSize.width;
	}
      else
	{
	  if (lbsh > gridSize.height) {
	    gridSize.height = lbsh;
	  }
	  gridSize.width = highlightSize.width + labelSize.width + lblmargin;
	}
    }
  else
    {
      if (iconPosition == NSImageAbove)
	{
	  gridSize.height += labelSize.height;
	  gridSize.width = (labelSize.width > highlightSize.width) ? labelSize.width : highlightSize.width;
	}
      else
	{
	  gridSize.width = highlightSize.width + labelSize.width + lblmargin;
	}
    }

  // Add extra height matching FSNIcon's lblmargin/2 + 2 padding
  gridSize.height += lblmargin / 2 + 2;
    
}

- (void)tile
{
  CREATE_AUTORELEASE_POOL (pool);
  NSUInteger count = [icons count];
  NSUInteger i;
  /* Superview frame — used to fill the parent on the desktop (no scroll view). */
  NSRect svr = [[self superview] frame];

  [self calculateGridSize];

  /* Cache grid cell dimensions on the first call so they stay consistent
   * across tile calls and Clean Up.  calculateGridSize can return different
   * widths (label-width dependent), which would shift the AUTO grid
   * mid-layout; caching once avoids that.  Invalidated by setters that
   * change icon properties (icon/label size, etc.). */
  if (!_gridCached)
    {
      _cachedCellSize = gridSize;
      _cachedGapX = (CGFloat)COLUMN_GAP_X;
      _gridCached = YES;
    }

  if (!customIconPositions)
    customIconPositions = [[NSMutableDictionary alloc] init];

  /* Layout policy: set every icon's frame and fill _contentExtent. */
  [self layoutIcons];

  /* Size the document view from the reported content extent. */
  {
    CGFloat visibleWidth = [self windowContentWidthForLayout];
    CGFloat maxX = _contentExtent.width + X_MARGIN;
    /* Snap trivial overflow so a few pixels of grid rounding don't add a
     * horizontal scrollbar; keep the natural width for content genuinely
     * outside the visible area (off-screen manual positions). */
    if (maxX - X_MARGIN <= visibleWidth)
      maxX = visibleWidth;

    CGFloat fh = _contentExtent.height + Y_MARGIN;
    /* Inside a scroll view the document owns its height (>= visible so icons
     * start at the top and scrollbars are proportional); on the desktop the
     * view must fill the parent. */
    if ([[self superview] isKindOfClass: [NSClipView class]] == NO)
      {
        if (fh < svr.size.height)
          fh = svr.size.height;
      }
    else
      {
        CGFloat visibleHeight = [self visibleContentHeightForLayout];
        if (fh < visibleHeight)
          fh = visibleHeight;
      }
    SETRECT (self, 0, 0, maxX, fh);
  }

  /* Tile each icon's internal layout (highlight, label, icon image). */
  for (i = 0; i < count; i++)
    [[icons objectAtIndex: i] tile];

  {
    NSArray *selection = [self selectedReps];
    if ([selection count])
      [self scrollIconToVisible: [selection objectAtIndex: 0]];
    else
      {
        /* No selection — show the first row regardless of prior scroll pos.
         * The visual top is y=0 in a flipped view but the document's max y
         * in the bottom-left model (the scroll view clamps the point). */
        CGFloat topY = [self isFlipped] ? 0 : [self bounds].size.height;
        [self scrollPoint: NSMakePoint(0, topY)];
      }
  }

  if ([[self subviews] containsObject: nameEditor])
    [self updateNameEditor];

  RELEASE (pool);
}

/* Base layout policy: the reflow/grid layout (icons flow to fill the width,
 * saved positions honoured via refH conversion).  The spatial and desktop
 * subclasses override this with fixed-position policies.  Sets each icon's
 * frame and reports the content extent in _contentExtent. */
- (void)layoutIcons
{
  NSUInteger count = [icons count];
  NSUInteger i;
  NSRect *irects = NULL;

  /* Use the current window content width (always up to date after resize)
   * rather than the superview frame which can lag. */
  CGFloat visibleWidth = [self windowContentWidthForLayout];

  /* Browser icon views do not honor saved positions — they always auto-grid
   * and reflow to the current width.  Position-honoring views (desktop, and
   * the spatial view via its own override) keep their icons put. */
  BOOL honor = [self honorsSavedPositions];

  float maxX = visibleWidth;
  float maxY = 0;

  /* Direction-aware grid enumerator for AUTO-mode (unplaced) icons.
   * Lazily initialized when the first auto-placed icon is encountered.
   * Uses gridOriginForLayout (desktop subclass accounts for Dock/menu)
   * and respects _placementDirection so new icons appear at the correct
   * end of the grid (e.g., top-right for desktop's TopToBottomRightToLeft). */
  FSNPlacementEnumerator *autoEnumerator = nil;
  NSMutableSet *occupiedCells = nil;
  NSPoint autoGOrigin = NSZeroPoint;
  CGFloat autoCellW = 0, autoCellH = 0, autoGapX = 0;
  BOOL autoInitDone = NO;
  /* Fallback row-flood counters (used only when enumerator is exhausted). */
  float gridX = X_MARGIN;
  float gridY = Y_MARGIN;

  irects = NSZoneMalloc (NSDefaultMallocZone(), sizeof(NSRect) * count);

  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSString *filename = [[icon node] name];
      FSNIconItemData *data = [icon placementData];
      NSValue *posValue = honor ? [customIconPositions objectForKey: filename] : nil;
      NSPoint cellOrigin;

      if (posValue)
        {
          /* customIconPositions stores iloc-style (DS_Store top-down)
           * coordinates; map into this view's coordinates through the
           * overridable conversion (identity in a flipped view).
           * Uses _cachedCellSize so icons stay at their assigned grid
           * position even when gridSize.width varies with label width. */
          NSPoint center = [self viewCenterForIlocCenter: [posValue pointValue]];
          cellOrigin.x = center.x - (_cachedCellSize.width / 2);
          cellOrigin.y = center.y - (_cachedCellSize.height / 2);
        }
      else if (honor && data.placementMode == FSNIconPlacementModeManual)
        {
          /* Stored iloc (DS_Store top-left) maps through the overridable
           * conversion at layout time, so positions are correct regardless
           * of when showContentsOfNode ran; a manually dragged icon without
           * raw iloc uses its stored view-local pixel position. */
          NSPoint center;
          if (data.ilocPosition.x >= 0)
            center = [self viewCenterForIlocCenter: data.ilocPosition];
          else
            center = data.pixelPosition;
          cellOrigin.x = center.x - (_cachedCellSize.width / 2);
          cellOrigin.y = center.y - (_cachedCellSize.height / 2);
        }
      else
        {
          /* No saved position: use the direction-aware grid enumerator
           * to place the icon in the next free grid cell.  Respects
           * _placementDirection (LeftToRightTopToBottom for file-viewer
           * panels, TopToBottomRightToLeft for the desktop). */
          if (!autoInitDone)
            {
              autoCellW = _cachedCellSize.width;
              autoCellH = _cachedCellSize.height;
              autoGapX = _cachedGapX;
              autoGOrigin = [self gridOriginForLayout];
              CGFloat gWidth = [self windowContentWidthForLayout];
              CGFloat availableWidth = gWidth - autoGOrigin.x;
              if (availableWidth < autoCellW + autoGapX)
                availableWidth = gWidth;
              NSUInteger nCols = (NSUInteger)((availableWidth + autoGapX) / (autoCellW + autoGapX));
              if (nCols < 1) nCols = 1;
              NSUInteger nRows = [self isFlipped]
                ? 1 : (NSUInteger)(autoGOrigin.y / autoCellH);
              if (nRows < 1) nRows = 1;
              {
                NSUInteger neededRows = ([icons count] + nCols - 1) / nCols;
                if (nRows < neededRows) nRows = neededRows;
              }

              /* Pure reflow (no honored positions) owns its document height:
               * anchor the grid to the height the rows actually need, so in
               * the bottom-left model rows past the visible area don't run
               * into negative y (outside the document, unreachable by
               * scrolling). */
              if (!honor && ![self isFlipped])
                {
                  CGFloat neededH = (CGFloat)nRows * autoCellH + (CGFloat)Y_MARGIN;
                  if (neededH > autoGOrigin.y)
                    autoGOrigin.y = neededH;
                }

              switch (_placementDirection)
                {
                case FSNPlacementDirectionTopToBottomRightToLeft:
                  autoEnumerator = [[FSNTopToBottomRightToLeftEnumerator alloc]
                                     initWithColumns: nCols rows: nRows];
                  break;
                default:
                  autoEnumerator = [[FSNLeftToRightTopToBottomEnumerator alloc]
                                     initWithColumns: nCols rows: nRows];
                  break;
                }

              /* Pre-compute grid cells occupied by icons that already have
               * saved positions so the enumerator skips them.  Only for
               * position-honoring views: in a pure-reflow view no saved
               * position is honored, so no cell is occupied by one (stale
               * MANUAL flags or customIconPositions entries must not punch
               * phantom holes in the reflow grid). */
              occupiedCells = [[NSMutableSet alloc] init];
              if (honor)
                {
              NSUInteger j;
              for (j = 0; j < count; j++)
                {
                  FSNIcon *otherIcon = [icons objectAtIndex: j];
                  NSString *otherName = [[otherIcon node] name];
                  FSNIconItemData *odata = [otherIcon placementData];
                  NSPoint otherCenter = NSZeroPoint;
                  BOOL hasPos = NO;

                  NSValue *oval = [customIconPositions objectForKey: otherName];
                  if (oval)
                    {
                      otherCenter = [self viewCenterForIlocCenter: [oval pointValue]];
                      hasPos = YES;
                    }
                  else if (odata.placementMode == FSNIconPlacementModeManual)
                    {
                      if (odata.ilocPosition.x >= 0)
                        otherCenter = [self viewCenterForIlocCenter: odata.ilocPosition];
                      else
                        otherCenter = odata.pixelPosition;
                      hasPos = YES;
                    }

                  if (hasPos)
                    {
                      FSNGridCell ocell = [self gridCellForCenter: otherCenter
                                                         cellSize: NSMakeSize(autoCellW, autoCellH)
                                                             gapX: autoGapX
                                                           origin: autoGOrigin];
                      if (!FSNGridCellsEqual(ocell, FSNGridCellNone)
                          && ocell.col < nCols && ocell.row < nRows)
                        {
                          [occupiedCells addObject:
                            [NSString stringWithFormat: @"%lu:%lu",
                                       (unsigned long)ocell.col,
                                       (unsigned long)ocell.row]];
                        }
                    }
                }
                }
              autoInitDone = YES;
            }

          /* Advance the direction-aware enumerator to the next free
           * grid cell (skipping cells occupied by existing icons). */
          {
            FSNGridCell cell;
            BOOL found = NO;
            while ([autoEnumerator nextCell: &cell])
              {
                NSString *cellKey = [NSString stringWithFormat: @"%lu:%lu",
                                              (unsigned long)cell.col,
                                              (unsigned long)cell.row];
                if ([occupiedCells containsObject: cellKey])
                  continue;

                /* Mark this cell as taken for subsequent AUTO-mode icons. */
                [occupiedCells addObject: cellKey];

                NSPoint center = [self centerForGridCell: cell
                                                cellSize: NSMakeSize(autoCellW, autoCellH)
                                                    gapX: autoGapX
                                                  origin: autoGOrigin];
                cellOrigin.x = center.x - (_cachedCellSize.width / 2);
                cellOrigin.y = center.y - (_cachedCellSize.height / 2);

                /* Record the assigned position only for position-honoring
                 * views; browser views must recompute the grid each layout
                 * (reflow) rather than stick to the first assignment. */
                if (honor)
                  {
                    [customIconPositions setObject:
                      [NSValue valueWithPoint:
                        [self ilocCenterForViewCenter: center]]
                      forKey: filename];
                  }
                found = YES;
                break;
              }

            if (!found)
              {
                /* Grid is full or no cells available — fallback to the
                 * simple row flood so the icon is still placed somewhere
                 * visible, even if cells wrap around. */
                cellOrigin.x = gridX;
                cellOrigin.y = gridY;
                gridX += (gridSize.width + COLUMN_GAP_X);
                if (gridX > (visibleWidth - gridSize.width))
                  {
                    gridX = X_MARGIN;
                    gridY += gridSize.height;
                  }
                NSPoint gsCenter = NSMakePoint(
                  cellOrigin.x + _cachedCellSize.width / 2.0,
                  cellOrigin.y + _cachedCellSize.height / 2.0);
                if (honor)
                  {
                    [customIconPositions setObject:
                      [NSValue valueWithPoint:
                        [self ilocCenterForViewCenter: gsCenter]]
                      forKey: filename];
                  }
              }
          }
        }

      irects[i] = NSMakeRect(cellOrigin.x, cellOrigin.y,
                              _cachedCellSize.width, _cachedCellSize.height);

      if (NSEqualRects(irects[i], [icon frame]) == NO)
        {
          [icon setFrame: irects[i]];
        }

      float rightEdge = cellOrigin.x + _cachedCellSize.width;
      float topEdge  = cellOrigin.y + _cachedCellSize.height;
      if (rightEdge > maxX) maxX = rightEdge;
      if (topEdge  > maxY) maxY = topEdge;
    }

  [autoEnumerator release];
  [occupiedCells release];

  if (irects)
    NSZoneFree (NSDefaultMallocZone(), irects);

  /* Report the content extent (raw max right/top edge) to -tile, which
   * adds margins, clamps, and sizes the document view. */
  _contentExtent = NSMakeSize(maxX, maxY);
}

- (void)scrollIconToVisible:(FSNIcon *)icon
{
  NSRect irect = [icon frame];
  float border = floor(irect.size.height * 0.2);

  irect.origin.y -= border;
  irect.size.height += border * 2;
  [self scrollRectToVisible: irect];
}

- (NSString *)selectIconWithPrefix:(NSString *)prefix
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSString *name = [icon shownInfo];

      if ([name hasPrefix: prefix])
	{
	  [icon select];
	  [self scrollIconToVisible: icon];

	  return name;
	}
    }

  return nil;
}

- (void)selectIconInPrevLine
{
  FSNIcon *icon;
  NSUInteger i;
  NSInteger pos = -1;

  for (i = 0; i < [icons count]; i++)
    {
      icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  NSSize sz = [self bounds].size;
	  NSUInteger cols = (gridSize.width > 0) ? (NSUInteger)((sz.width + COLUMN_GAP_X) / (gridSize.width + COLUMN_GAP_X)) : 1;
	  if (i >= cols)
	    pos = i - cols;
	  break;
	}
    }

  if (pos >= 0 && pos < [icons count])
    {
      icon = [icons objectAtIndex: pos];
      [icon select];
      [self scrollIconToVisible: icon];
    }
}

- (void)selectIconInNextLine
{
  FSNIcon *icon;
  NSUInteger i;
  NSUInteger pos = [icons count];

  for (i = 0; i < [icons count]; i++)
    {
      icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  NSSize sz = [self bounds].size;
	  NSUInteger cols = (gridSize.width > 0) ? (NSUInteger)((sz.width + COLUMN_GAP_X) / (gridSize.width + COLUMN_GAP_X)) : 1;
	  if (i + cols < [icons count])
	    pos = i + cols;
	  break;
	}
    }

  if (pos <= ([icons count] -1))
    {
      icon = [icons objectAtIndex: pos];
      [icon select];
      [self scrollIconToVisible: icon];
    }
}

- (void)selectPrevIcon
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  if (i > 0)
	    {
	      icon = [icons objectAtIndex: i - 1];
	      [icon select];
	      [self scrollIconToVisible: icon];
	    }
	  break;
	}
    }
}

- (void)selectNextIcon
{
  NSUInteger count = [icons count];
  NSUInteger i;

  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  if (i < (count - 1))
	    {
	      icon = [icons objectAtIndex: i + 1];
	      [icon select];
	      [self scrollIconToVisible: icon];
	    }
	  break;
	}
    }
}

#pragma mark - DS_Store Free Positioning Support

- (void)setCustomIconPositions:(NSDictionary *)positions
{
  if (positions != customIconPositions)
    {
      [customIconPositions release];
      customIconPositions = [positions mutableCopy];
      
      NSDebugLLog(@"gwspace", @"╔══════════════════════════════════════════════════════════════════╗");
      NSDebugLLog(@"gwspace", @"║        CUSTOM ICON POSITIONS SET (DS_Store)                      ║");
      NSDebugLLog(@"gwspace", @"╠══════════════════════════════════════════════════════════════════╣");
      NSDebugLLog(@"gwspace", @"║ Positions for %lu icons:", (unsigned long)[positions count]);
      
      for (NSString *filename in positions)
        {
          NSValue *posValue = [positions objectForKey:filename];
          NSPoint pos = [posValue pointValue];
          NSDebugLLog(@"gwspace", @"║   '%@' -> (%.0f, %.0f)", filename, pos.x, pos.y);
        }
      
      NSDebugLLog(@"gwspace", @"╚══════════════════════════════════════════════════════════════════╝");
    }
}

- (NSDictionary *)customIconPositions
{
  return customIconPositions;
}

- (NSArray *)icons
{
  return icons;
}

- (NSPoint)firstFreeGridCenter
{
  /* Virtual grid scan: find the first grid cell that is not occupied by
   * any existing icon.  Used for initial placement of new/added items. */

  [self calculateGridSize];

  CGFloat cellW = gridSize.width;
  CGFloat cellH = gridSize.height;
  CGFloat gapX = (CGFloat)COLUMN_GAP_X;
  NSPoint gOrigin = [self gridOriginForLayout];
  CGFloat gridWidth = [self windowContentWidthForLayout];
  CGFloat availableWidth = gridWidth - gOrigin.x;
  if (availableWidth < cellW + gapX) availableWidth = gridWidth;
  NSUInteger nCols = (NSUInteger)((availableWidth + gapX) / (cellW + gapX));
  if (nCols < 1) nCols = 1;
  NSUInteger nRows = [self isFlipped] ? 1 : (NSUInteger)(gOrigin.y / cellH);
  if (nRows < 1) nRows = 1;
  {
    NSUInteger neededRows = ([icons count] + nCols - 1) / nCols;
    if (nRows < neededRows) nRows = neededRows;
  }

  FSNLeftToRightTopToBottomEnumerator *e =
    [[[FSNLeftToRightTopToBottomEnumerator alloc] initWithColumns: nCols rows: nRows] autorelease];
  [e reset];
  FSNGridCell cell;
  while ([e nextCell: &cell])
    {
      NSPoint c = [self centerForGridCell: cell
                                 cellSize: NSMakeSize(cellW, cellH)
                                     gapX: gapX
                                   origin: gOrigin];
      /* Check if any existing icon occupies this cell */
      BOOL occupied = NO;
      NSUInteger i;
      for (i = 0; i < [icons count]; i++)
        {
          FSNIcon *icon = [icons objectAtIndex: i];
          NSPoint ip = [[icon placementData] pixelPosition];
          CGFloat dx = fabs(ip.x - c.x);
          CGFloat dy = fabs(ip.y - c.y);
          if (dx < cellW / 2.0 && dy < cellH / 2.0)
            {
              occupied = YES;
              break;
            }
        }
      if (!occupied)
        return c;
    }
  return NSZeroPoint;
}

- (void)repositionIcon:(FSNIcon *)icon toCenterPoint:(NSPoint)point
{
  /* Thin wrapper — all real work is in batchRepositionIcons:toCenterPoints:. */
  if (!icon) return;
  [self batchRepositionIcons: [NSArray arrayWithObject: icon]
              toCenterPoints: [NSArray arrayWithObject: [NSValue valueWithPoint: point]]];
}

/* Batch reposition — moves many icons at once, tiles once, persists once.
 * Each entry in `icons` is an FSNIcon *, each entry in `points` is an
 * NSValue wrapping the NSPoint center.  The arrays must have equal length. */
- (BOOL)honorsSavedPositions
{
  return YES;
}

- (NSPoint)ilocCenterForViewCenter:(NSPoint)center
{
  return NSMakePoint(center.x, FSNReferenceHeightForView(self) - center.y);
}

- (NSPoint)viewCenterForIlocCenter:(NSPoint)iloc
{
  return NSMakePoint(iloc.x, FSNReferenceHeightForView(self) - iloc.y);
}

- (void)batchRepositionIcons:(NSArray *)iconList toCenterPoints:(NSArray *)points
{
  NSUInteger count = [iconList count];
  if (count == 0 || [points count] != count) return;

  /* A pure-reflow view has no positions to update or persist: just re-tile
   * (the reflow grid reasserts itself) and write nothing to disk. */
  if (![self honorsSavedPositions])
    {
      [self tile];
      return;
    }

  /* ---- Pass 1: update all placement data in memory ---- */
  NSUInteger i;
  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [iconList objectAtIndex: i];
      NSPoint point = [[points objectAtIndex: i] pointValue];
      FSNIconItemData *data = [icon placementData];

      /* Manual placement is pixel-precise — no grid snapping. */
      data.pixelPosition = point;
      data.ilocPosition = NSMakePoint(-1, -1);  /* clear raw coords */
      data.placementMode = FSNIconPlacementModeManual;

      /* Sync customIconPositions with iloc-style (top-down) coords so
       * the next tile call uses the dragged position, not a stale one. */
      NSString *name = [[icon node] name];
      if (!customIconPositions)
        customIconPositions = [[NSMutableDictionary alloc] init];
      NSPoint ilocPoint = [self ilocCenterForViewCenter: point];
      [customIconPositions setObject: [NSValue valueWithPoint: ilocPoint]
                              forKey: name];
    }

  /* ---- Pass 2: single tile ---- */
  [self tile];

  /* ---- Pass 3: single DS_Store write batch ---- */
  {
    /* Group icons by parent folder so we open each .DS_Store only once */
    NSMutableDictionary *folders = [NSMutableDictionary dictionary];

    for (i = 0; i < count; i++)
      {
        FSNIcon *icon = [iconList objectAtIndex: i];
        NSPoint point = [[points objectAtIndex: i] pointValue];
        FSNode *nd = [icon node];
        if (!nd) continue;

        NSString *fp = [nd path];
        NSString *folder = [fp stringByDeletingLastPathComponent];
        NSString *name = [nd name];
        if (!folder || !name) continue;

        /* View-center -> DS_Store iloc (top-left); identity in a flipped view. */
        NSPoint iloc = [self ilocCenterForViewCenter: point];
        int ilocX = (int)iloc.x;
        int ilocY = (int)iloc.y;

        NSMutableArray *batch = [folders objectForKey: folder];
        if (!batch)
          {
            batch = [NSMutableArray array];
            [folders setObject: batch forKey: folder];
          }
        [batch addObject: @[name, [NSNumber numberWithInt: ilocX],
                                  [NSNumber numberWithInt: ilocY]]];
      }

    /* All persistence goes through the injected icon-position store (the
     * Workspace application), which owns the folder .DS_Store / per-volume
     * cache / fdLocation xattr writes.  FSNode no longer writes those stores
     * directly. */
    [[fsnodeRep iconPositionStore] saveIconPositionsByFolder: folders];
  }
}

#pragma mark - DS_Store Tag Colors and Comments Support

- (void)setTagColorsFromDictionary:(NSDictionary *)tagDict
{
  if (!tagDict || [tagDict count] == 0)
    return;
    
  NSDebugLLog(@"gwspace", @"╔══════════════════════════════════════════════════════════════════╗");
  NSDebugLLog(@"gwspace", @"║        APPLYING TAG COLORS FROM DS_Store                         ║");
  NSDebugLLog(@"gwspace", @"╠══════════════════════════════════════════════════════════════════╣");
  
  for (FSNIcon *icon in icons)
    {
      FSNode *iconNode = [icon node];
      if (iconNode)
        {
          NSString *filename = [iconNode name];
          NSColor *tagColor = [tagDict objectForKey:filename];
          if (tagColor)
            {
              [icon setTagColor:tagColor];
              NSDebugLLog(@"gwspace", @"║   '%@' -> tag color set", filename);
            }
        }
    }
  
  NSDebugLLog(@"gwspace", @"╚══════════════════════════════════════════════════════════════════╝");
}

- (void)setCommentsFromDictionary:(NSDictionary *)commentsDict
{
  if (!commentsDict || [commentsDict count] == 0)
    return;
    
  NSDebugLLog(@"gwspace", @"╔══════════════════════════════════════════════════════════════════╗");
  NSDebugLLog(@"gwspace", @"║        APPLYING SPOTLIGHT COMMENTS FROM DS_Store                 ║");
  NSDebugLLog(@"gwspace", @"╠══════════════════════════════════════════════════════════════════╣");
  
  for (FSNIcon *icon in icons)
    {
      FSNode *iconNode = [icon node];
      if (iconNode)
        {
          NSString *filename = [iconNode name];
          NSString *comment = [commentsDict objectForKey:filename];
          if (comment)
            {
              [icon setSpotlightComment:comment];
              NSDebugLLog(@"gwspace", @"║   '%@' -> comment: '%@'", filename, comment);
            }
        }
    }
  
  NSDebugLLog(@"gwspace", @"╚══════════════════════════════════════════════════════════════════╝");
}

/* Returns the visible content width for determining virtual grid
 * dimensions.  Walks up to the enclosing NSScrollView (if any) and
 * uses its contentSize, which always reflects the current window size
 * after autoresize and already excludes sidebar / border overhead.
 * Falls back to the window content view, then superview frame. */
- (CGFloat)windowContentWidthForLayout
{
  /* Walk up to find the enclosing scroll view — its contentSize
   * is always up to date (autoresized with the window) and already
   * accounts for sidebar, borders, and scrollers. */
  NSView *v = [self superview];
  while (v)
    {
      if ([v isKindOfClass: [NSScrollView class]])
        {
          NSSize cs = [(NSScrollView *)v contentSize];
          if (cs.width > 0) return cs.width;
          break;
        }
      v = [v superview];
    }
  /* Fallback: window content view (always resized synchronously). */
  NSWindow *w = [self window];
  if (w) {
    NSView *cv = [w contentView];
    if (cv) {
      CGFloat cw = [cv bounds].size.width;
      if (cw > 0) {
        /* For browser-mode windows the content view is a vertical
         * NSSplitView — subtract the sidebar (first subview). */
        if ([cv isKindOfClass: [NSSplitView class]]
            && [(NSSplitView *)cv isVertical]
            && [[cv subviews] count] > 1) {
          cw -= [[[cv subviews] objectAtIndex: 0] frame].size.width;
          cw -= [(NSSplitView *)cv dividerThickness];
        }
        return cw;
      }
    }
  }
  /* Last resort: superview frame, then own bounds. */
  v = [self superview];
  if (v) {
    CGFloat w = [v frame].size.width;
    if (w > 0) return w;
  }
  return [self bounds].size.width;
}

/* Returns the visible content height for determining icon layout.
 * Walks up to the enclosing NSScrollView (if any) and uses its
 * contentSize height, which always reflects the current window size
 * after autoresize.  Falls back to the window content view height,
 * then superview frame, then own bounds. */
- (CGFloat)visibleContentHeightForLayout
{
  NSView *v = [self superview];
  while (v)
    {
      if ([v isKindOfClass: [NSScrollView class]])
        {
          NSSize cs = [(NSScrollView *)v contentSize];
          if (cs.height > 0) return cs.height;
          break;
        }
      v = [v superview];
    }
  /* Fallback: window content view. */
  NSWindow *w = [self window];
  if (w) {
    NSView *cv = [w contentView];
    if (cv) {
      CGFloat ch = [cv bounds].size.height;
      if (ch > 0) return ch;
    }
  }
  /* Last resort: superview frame, then own bounds. */
  v = [self superview];
  if (v) {
    CGFloat h = [v frame].size.height;
    if (h > 0) return h;
  }
  return [self bounds].size.height;
}

- (NSPoint)gridOriginForLayout
{
  /* The visual top-left corner where the grid starts, in this view's own
   * coordinates: (margin, margin) in a flipped view; (margin, height -
   * margin) in the default bottom-left model, using the visible content
   * height so icons sit relative to the visible area.  Subclasses
   * (GWDesktopView) override for Dock/menu adjustments. */
  if ([self isFlipped])
    return NSMakePoint((CGFloat)X_MARGIN, (CGFloat)Y_MARGIN);

  CGFloat visibleHeight = [self visibleContentHeightForLayout];
  return NSMakePoint((CGFloat)X_MARGIN, visibleHeight - (CGFloat)Y_MARGIN);
}

- (NSPoint)centerForGridCell:(FSNGridCell)cell
                    cellSize:(NSSize)cellSize
                        gapX:(CGFloat)gapX
                      origin:(NSPoint)gridOrigin
{
  /* Rows grow visually downward from the origin: +y in a flipped view,
   * -y in the default bottom-left model. */
  if ([self isFlipped])
    return FSNGridCellCenter(cell, gridOrigin,
                             cellSize.width, cellSize.height, gapX);

  return NSMakePoint(gridOrigin.x + (CGFloat)cell.col * (cellSize.width + gapX)
                                  + cellSize.width / 2.0,
                     gridOrigin.y - (CGFloat)(cell.row + 1) * cellSize.height
                                  + cellSize.height / 2.0);
}

- (FSNGridCell)gridCellForCenter:(NSPoint)center
                        cellSize:(NSSize)cellSize
                            gapX:(CGFloat)gapX
                          origin:(NSPoint)gridOrigin
{
  if ([self isFlipped])
    return FSNGridCellForCenter(center, gridOrigin,
                                cellSize.width, cellSize.height, gapX);

  {
    CGFloat dx = center.x - gridOrigin.x;
    CGFloat dy = gridOrigin.y - center.y;
    if (dx < 0 || dy < 0 || cellSize.width <= 0 || cellSize.height <= 0)
      return FSNGridCellNone;
    return FSNGridCellMake((NSUInteger)(dx / (cellSize.width + gapX)),
                           (NSUInteger)(dy / cellSize.height));
  }
}

- (void)setPlacementDirection:(FSNPlacementDirection)direction
{
  _placementDirection = direction;
}

- (FSNPlacementDirection)placementDirection
{
  return _placementDirection;
}

#pragma mark - Cleanup and Sort Operations

- (void)cleanupIconPositions
{
  /* "Clean Up" — snap all icons to the virtual grid. */

  [customIconPositions release];
  customIconPositions = nil;

  /* In a pure-reflow view there are no positions to snap: reset every icon
   * to AUTO and let the layout policy re-grid.  (Setting MANUAL here would
   * leave phantom placement state a reflow view never honors.) */
  if (![self honorsSavedPositions])
    {
      NSUInteger i;
      for (i = 0; i < [icons count]; i++)
        {
          FSNIconItemData *data = [[icons objectAtIndex: i] placementData];
          data.ilocPosition = NSMakePoint(-1, -1);
          data.placementMode = FSNIconPlacementModeAuto;
        }
      [self tile];
      return;
    }

  /* Use cached grid cell dimensions so Clean Up stays in sync with
   * the AUTO-mode tile positioning.  If tile hasn't been called yet,
   * compute the cache first. */
  if (!_gridCached)
    {
      [self calculateGridSize];
      _cachedCellSize = gridSize;
      _cachedGapX = (CGFloat)COLUMN_GAP_X;
      _gridCached = YES;
    }

  CGFloat cellW = _cachedCellSize.width;
  CGFloat cellH = _cachedCellSize.height;
  CGFloat gapX = _cachedGapX;
  NSPoint gOrigin = [self gridOriginForLayout];
  CGFloat gridWidth = [self windowContentWidthForLayout];
  CGFloat availableWidth = gridWidth - gOrigin.x;
  if (availableWidth < cellW + gapX) availableWidth = gridWidth;
  NSUInteger nCols = (NSUInteger)((availableWidth + gapX) / (cellW + gapX));
  if (nCols < 1) nCols = 1;
  NSUInteger nRows = [self isFlipped] ? 1 : (NSUInteger)(gOrigin.y / cellH);
  if (nRows < 1) nRows = 1;
  {
    NSUInteger neededRows = ([icons count] + nCols - 1) / nCols;
    if (nRows < neededRows) nRows = neededRows;
  }

  /* Build a fresh enumerator. */
  FSNPlacementEnumerator *e;
  switch (_placementDirection)
    {
    case FSNPlacementDirectionTopToBottomRightToLeft:
      e = [[FSNTopToBottomRightToLeftEnumerator alloc] initWithColumns: nCols rows: nRows];
      break;
    default:
      e = [[FSNLeftToRightTopToBottomEnumerator alloc] initWithColumns: nCols rows: nRows];
      break;
    }

  [e reset];
  FSNGridCell cell;
  NSUInteger ci = 0;
  while (ci < [icons count] && [e nextCell: &cell])
    {
      NSPoint gCenter = [self centerForGridCell: cell
                                       cellSize: NSMakeSize(cellW, cellH)
                                           gapX: gapX
                                         origin: gOrigin];
      FSNIcon *icon = [icons objectAtIndex: ci];
      FSNIconItemData *data = [icon placementData];
      data.pixelPosition = gCenter;
      data.ilocPosition = NSMakePoint(-1, -1);
      data.placementMode = FSNIconPlacementModeManual;
      NSRect f = NSMakeRect(gCenter.x - cellW / 2.0, gCenter.y - cellH / 2.0,
                            cellW, cellH);
      [icon setFrame: NSIntegralRect(f)];
      ci++;
    }

  [e release];
  [self tile];
}

- (void)sortIconsBy:(SEL)sortSelector
{
  if (infoType == FSNInfoExtendedType)
    {
      /* Extended info type uses function-based sort */
      /* FIXME: use appropriate compare function */
    }
  else
    {
      [icons sortUsingSelector: sortSelector];
    }

  /* After sort, all items become AUTO (layout engine owns positions) */
  NSUInteger i;
  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNIconItemData *data = [icon placementData];
      data.placementMode = FSNIconPlacementModeAuto;
    }

  [self tile];
}

- (void)mouseUp:(NSEvent *)theEvent
{
  [self setSelectionMask: NSSingleSelectionMask];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if ([theEvent modifierFlags] != NSShiftKeyMask)
    {
      selectionMask = NSSingleSelectionMask;
      selectionMask |= FSNCreatingSelectionMask;
      [self unselectOtherReps: nil];
      selectionMask = NSSingleSelectionMask;

      DESTROY (lastSelection);
      [self selectionDidChange];
      [self stopRepNameEditing];
    }
}

- (void)mouseDragged:(NSEvent *)theEvent
{
  unsigned int eventMask = NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSPeriodicMask;
  NSDate *future = [NSDate distantFuture];
  NSPoint sp;
  NSPoint p, pp;
  NSRect visibleRect;
  NSRect oldRect;
  NSRect r;
  NSRect selrect;
  float x, y, w, h;
  NSUInteger i;

  pp = NSMakePoint(0,0);

#define scrollPointToVisible(p)		\
  {						\
    NSRect sr;					\
    sr.origin = p;				\
    sr.size.width = sr.size.height = 1.0;	\
    [self scrollRectToVisible: sr];		\
  }

#define CONVERT_CHECK				\
  {						\
    NSRect br = [self bounds];			\
    pp = [self convertPoint: p fromView: nil];	\
    if (pp.x < 1)				\
      pp.x = 1;				\
    if (pp.x >= NSMaxX(br))			\
      pp.x = NSMaxX(br) - 1;			\
    if (pp.y < 0)				\
      pp.y = -1;				\
    if (pp.y > NSMaxY(br))			\
      pp.y = NSMaxY(br) + 1;			\
  }

  p = [theEvent locationInWindow];
  sp = [self convertPoint: p  fromView: nil];

  oldRect = NSZeroRect;

  [[self window] disableFlushWindow];

  [NSEvent startPeriodicEventsAfterDelay: 0.02 withPeriod: 0.05];

  while ([theEvent type] != NSLeftMouseUp)
    {
      BOOL scrolled = NO;

      CREATE_AUTORELEASE_POOL (arp);

      theEvent = [NSApp nextEventMatchingMask: eventMask
				    untilDate: future
				       inMode: NSEventTrackingRunLoopMode
				      dequeue: YES];

      if ([theEvent type] != NSPeriodic)
	{
	  p = [theEvent locationInWindow];
	}

      CONVERT_CHECK;

      visibleRect = [self visibleRect];

      if ([self mouse: pp inRect: visibleRect] == NO)
	{
	  scrollPointToVisible(pp);
	  CONVERT_CHECK;

	  scrolled = YES;
	}

      x = min(sp.x, pp.x);
      y = min(sp.y, pp.y);
      w = max(1, max(pp.x, sp.x) - min(pp.x, sp.x));
      h = max(1, max(pp.y, sp.y) - min(pp.y, sp.y));

      r = NSMakeRect(x, y, w, h);

      // Erase the previous rect
      if (transparentSelection
	  || (!transparentSelection && scrolled))
	{
	  [self setNeedsDisplayInRect: oldRect];
	  [[self window] displayIfNeeded];
	}

      // Draw the new rect
      [self lockFocus];

      if (transparentSelection)
	{
	  [[NSColor darkGrayColor] set];
	  NSFrameRect(r);
	  if (transparentSelection)
	    {
	      [[[NSColor darkGrayColor] colorWithAlphaComponent: 0.33] set];
	      NSRectFillUsingOperation(r, NSCompositeSourceOver);
	    }
	}
      else
	{
	  if (!NSEqualRects(oldRect, r) && !scrolled)
	    {
	      GWHighlightFrameRect(oldRect);
	      GWHighlightFrameRect(r);
	    }
	  else if (scrolled)
	    {
	      GWHighlightFrameRect(r);
	    }
	}

      [self unlockFocus];

      oldRect = r;

      [[self window] enableFlushWindow];
      [[self window] flushWindow];
      [[self window] disableFlushWindow];

      DESTROY (arp);
    }

  [NSEvent stopPeriodicEvents];
  [[self window] postEvent: theEvent atStart: NO];

  // Erase the previous rect

  [self setNeedsDisplayInRect: oldRect];
  [[self window] displayIfNeeded];

  [[self window] enableFlushWindow];
  [[self window] flushWindow];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  x = min(sp.x, pp.x);
  y = min(sp.y, pp.y);
  w = max(1, max(pp.x, sp.x) - min(pp.x, sp.x));
  h = max(1, max(pp.y, sp.y) - min(pp.y, sp.y));

  selrect = NSMakeRect(x, y, w, h);

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSRect iconBounds = [self convertRect: [icon iconBounds] fromView: icon];

      if (NSIntersectsRect(selrect, iconBounds))
	{
	  [icon select];
	}
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *characters;
  unichar character;
  NSString *characterStr = nil;
  NSRect vRect, hiddRect;
  NSPoint p;
  float x, y, w, h;

  characters = [theEvent characters];
  character = 0;

  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
      characterStr = [characters substringToIndex: 1];
    }

  switch (character)
    {
    case NSPageUpFunctionKey:
		  vRect = [self visibleRect];
		  p = vRect.origin;
		  x = p.x;
		  y = p.y + vRect.size.height;
		  w = vRect.size.width;
		  h = vRect.size.height;
		  hiddRect = NSMakeRect(x, y, w, h);
		  [self scrollRectToVisible: hiddRect];
		  return;

  case NSPageDownFunctionKey:
    vRect = [self visibleRect];
    p = vRect.origin;
    x = p.x;
    y = p.y - vRect.size.height;
    w = vRect.size.width;
    h = vRect.size.height;
    hiddRect = NSMakeRect(x, y, w, h);
    [self scrollRectToVisible: hiddRect];
    return;

  case NSUpArrowFunctionKey:
    [self selectIconInPrevLine];
    return;

  case NSDownArrowFunctionKey:
    [self selectIconInNextLine];
    return;

  case NSLeftArrowFunctionKey:
    {
      if ([theEvent modifierFlags] & NSControlKeyMask)
	{
	  [super keyDown: theEvent];
	}
      else
	{
	  [self selectPrevIcon];
	}
    }
    return;

  case NSRightArrowFunctionKey:
    {
      if ([theEvent modifierFlags] & NSControlKeyMask)
	{
	  [super keyDown: theEvent];
	}
      else
	{
	  [self selectNextIcon];
	}
    }
    return;

  case NSCarriageReturnCharacter:
    {
      unsigned flags = [theEvent modifierFlags];
      BOOL closesndr = ((flags == NSAlternateKeyMask)
			|| (flags == NSControlKeyMask));
      [self openSelectionInNewViewer: closesndr];
      return;
    }
  case 0x01B: // Escape
    DESTROY(charBuffer);
    selectionMask = NSSingleSelectionMask;
    selectionMask |= FSNCreatingSelectionMask;
    [self unselectOtherReps: nil];
    selectionMask = NSSingleSelectionMask;
    [self selectionDidChange];
    return;
  default:
    break;
  }

  if (([characters length] > 0) && (character < 0xF700))
    {
      if (charBuffer != nil)
	{
	  if ([theEvent timestamp] - lastKeyPressedTime < 5.0)
	    {
	      NSString *appendBuffer = [charBuffer stringByAppendingString:characterStr];

	      // Try selecting
	      if ([self selectIconWithPrefix: appendBuffer])
		{
		  ASSIGN(charBuffer, appendBuffer);
		  return;
		}
	      // unable to select - fall-through and reinit as if typed is first char
	    }
	}

      ASSIGN(charBuffer, characterStr);
      lastKeyPressedTime = [theEvent timestamp];

      // Try selecting
      if ([self selectIconWithPrefix: charBuffer])
	{
	  return;
	}

      // Selection failed, reinitialize and use mismatching character as new buffer beginning
      DESTROY(charBuffer);
    }

  [super keyDown: theEvent];
}

- (void)cancelOperation:(id)sender
{
  // Escape key - deselect all items
  selectionMask = NSSingleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;
  [self unselectOtherReps: nil];
  selectionMask = NSSingleSelectionMask;
  [self selectionDidChange];

  DESTROY(charBuffer);
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  NSArray *selnodes;
  NSMenu *menu;
  NSMenuItem *menuItem;
  NSString *firstext;
  NSDictionary *apps;
  NSEnumerator *app_enum;
  id key;
  NSUInteger i;

  if ([theEvent modifierFlags] == NSControlKeyMask)
    {
      return [super menuForEvent: theEvent];
    }

  selnodes = [self selectedNodes];

  if ([selnodes count]) {
    NSAutoreleasePool *pool;

    firstext = [[[selnodes objectAtIndex: 0] path] pathExtension];

    for (i = 0; i < [selnodes count]; i++)
      {
	FSNode *snode = [selnodes objectAtIndex: i];
	NSString *selpath = [snode path];
	NSString *ext = [selpath pathExtension];

	if ([ext isEqual: firstext] == NO)
	  {
	    return [super menuForEvent: theEvent];
	  }

	if ([snode isDirectory] == NO)
	  {
	    if ([snode isPlain] == NO) {
	      return [super menuForEvent: theEvent];
	    }
	  }
	else
	  {
	    if (([snode isPackage] == NO) || [snode isApplication])
	      {
		return [super menuForEvent: theEvent];
	      }
	  }
      }

    menu = [[NSMenu alloc] initWithTitle: NSLocalizedStringFromTableInBundle(@"Open with", nil, [NSBundle bundleForClass:[self class]], @"")];
    apps = [[NSWorkspace sharedWorkspace] infoForExtension: firstext];
    app_enum = [[apps allKeys] objectEnumerator];

    pool = [NSAutoreleasePool new];

    while ((key = [app_enum nextObject]))
      {
	menuItem = [NSMenuItem new];
	key = [key stringByDeletingPathExtension];
	[menuItem setTitle: key];
	[menuItem setTarget: desktopApp];
	[menuItem setAction: @selector(openSelectionWithApp:)];
	[menuItem setRepresentedObject: key];
	[menu addItem: menuItem];
	RELEASE (menuItem);
      }

    RELEASE (pool);

    return [menu autorelease];
  }

  return [super menuForEvent: theEvent];
}

- (void)resizeWithOldSuperviewSize:(NSSize)oldFrameSize
{
  [self tile];
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];

  /* Tear down any previous clip-view observer before setting up a new one.
   * This handles the case where the view is moved from one clip view
   * to another, or is removed from the view hierarchy entirely. */
  if (_observedClipView)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self
                                                      name: NSViewFrameDidChangeNotification
                                                    object: _observedClipView];
      _observedClipView = nil;
    }

  /* Register for NSViewFrameDidChangeNotification on the enclosing
   * NSClipView so that tile is called reliably when the window is
   * resized, even if NSClipView does not propagate the standard
   * resizeWithOldSuperviewSize: chain to its document view. */
  if ([self superview]
      && [[self superview] isKindOfClass: [NSClipView class]])
    {
      _observedClipView = [self superview];
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(clipViewFrameDidChange:)
                                                   name: NSViewFrameDidChangeNotification
                                                 object: _observedClipView];
    }

  if ([self superview])
    {
      [[self window] setBackgroundColor: backColor];
    }
}

/* Called when the enclosing NSClipView's frame changes (window resize,
 * split-view drag, etc.).  Re-tiles the icon layout so scrollbars
 * and content positioning are correct for the new visible area. */
- (void)clipViewFrameDidChange:(NSNotification *)notif
{
  [self tile];
}

- (void)drawRect:(NSRect)rect
{
  [super drawRect: rect];
  
  // Draw background image if set, otherwise use solid color
  if (backgroundImage)
    {
      // Get the bounds and image size
      NSRect bounds = [self bounds];
      NSSize imageSize = [backgroundImage size];
      
      // Spatial view backgrounds are positioned from bottom-left in our coordinate system
      // (which corresponds to top-left in .DS_Store screen coordinates)
      // The image is drawn at its natural size, positioned at the bottom-left corner
      NSRect imageRect;
      imageRect.origin = bounds.origin;
      imageRect.size = imageSize;
      
      // In GNUstep, y=0 is at the bottom, but we want the image to appear
      // as if it's positioned from the "top" visually (standard spatial view behavior)
      // So we position it at the top of the view
      imageRect.origin.y = bounds.size.height - imageSize.height;
      
      // Draw the background image
      [backgroundImage drawInRect:imageRect
                         fromRect:NSZeroRect
                        operation:NSCompositeSourceOver
                         fraction:1.0];
    }
  else
    {
      // Fall back to solid color background
      [backColor set];
      NSRectFill(rect);
    }
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

@end


@implementation FSNIconsView (NodeRepContainer)

- (void)showContentsOfNode:(FSNode *)anode
{
  CREATE_AUTORELEASE_POOL(arp);
  NSArray *subNodes = [anode subNodes];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      [[icons objectAtIndex: i] removeFromSuperview];
    }
  [icons removeAllObjects];
  editIcon = nil;

  ASSIGN (node, anode);
  [self readNodeInfo];
  _gridCached = NO; /* icon properties may have changed */
  [self calculateGridSize];

  for (i = 0; i < [subNodes count]; i++)
    {
      FSNode *subnode = [subNodes objectAtIndex: i];
      FSNIcon *icon = [[FSNIcon alloc] initForNode: subnode
				      nodeInfoType: infoType
				      extendedType: extInfoType
					  iconSize: iconSize
				      iconPosition: iconPosition
					 labelFont: labelFont
					 textColor: textColor
					 gridIndex: -1
					 dndSource: YES
					 acceptDnd: YES
					 slideBack: YES];
      [icons addObject: icon];
      [self addSubview: icon];
      RELEASE (icon);
    }

  /* Restore icon positions from fdLocation xattr and DS_Store Iloc — only for
   * position-honoring views (desktop, spatial).  Browser icon views auto-grid
   * and reflow, so they neither read nor apply saved positions.
   * fdLocation (per-file extended attribute) is checked first since it
   * follows the file even when moved; DS_Store is the folder-level fallback.
   * Icons with saved positions get MANUAL placement mode. */
  if ([self honorsSavedPositions])
  {
    NSString *folderPath = [anode path];
    /* Window content height as reference, like macOS Finder. */
    CGFloat refH = FSNReferenceHeightForView(self);

    /* Source 1: fdLocation xattr (per-file extended attribute, primary).
     * FinderInfo writes (0,0) by default when no position exists,
     * so skip (0,0) and (-1,-1) which are both "no position" markers. */
    for (i = 0; i < [icons count]; i++)
      {
        FSNIcon *icon = [icons objectAtIndex: i];
        FSNode *nd = [icon node];
        if (!nd) continue;
        NSPoint floc = [[fsnodeRep metadataProvider] iconPositionForPath: [nd path]];
        if ((floc.x > 0 || floc.y > 0) && floc.x != -1 && floc.y != -1)
          {
            NSPoint gsCenter = NSMakePoint(floc.x, refH - floc.y);
            FSNIconItemData *data = [icon placementData];
            data.ilocPosition = floc;
            data.pixelPosition = gsCenter;
            data.placementMode = FSNIconPlacementModeManual;
          }
      }

    /* Sources 2/3: folder .DS_Store Iloc, else the per-volume cache —
     * both provided by the injected position store (the app reads them via
     * the settings hierarchy).  Only fills icons not already positioned by
     * fdLocation.  Raw iloc (top-left) is stored; conversion to GNUstep
     * bottom-left happens at tile time with the correct refH. */
    NSDictionary *stored =
      [[fsnodeRep iconPositionStore] storedIconPositionsForFolder: folderPath];
    if ([stored count])
      {
        for (i = 0; i < [icons count]; i++)
          {
            FSNIcon *icon = [icons objectAtIndex: i];
            FSNIconItemData *data = [icon placementData];
            if (data.placementMode == FSNIconPlacementModeManual) continue;

            NSValue *v = [stored objectForKey: [[icon node] name]];
            if (v == nil) continue;
            NSPoint iloc = [v pointValue];
            if (iloc.x != 0 || iloc.y != 0)
              {
                data.ilocPosition = iloc;
                data.pixelPosition = NSMakePoint(iloc.x, iloc.y);
                data.placementMode = FSNIconPlacementModeManual;
              }
          }
      }
  }

  [icons sortUsingSelector: [fsnodeRep compareSelectorForDirectory: [node path]]];
  [self tile];

  DESTROY (lastSelection);
  [self selectionDidChange];
  RELEASE (arp);
}

- (NSDictionary *)readNodeInfo
{
  /* Read per-folder view settings from user defaults only.
   * Icon positions are restored separately from DS_Store / fdLocation. */
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", [node path]];
  NSDictionary *nodeDict = [defaults dictionaryForKey: prefsname];

  if (nodeDict)
    {
      id entry = [nodeDict objectForKey: @"iconsize"];
      iconSize = entry ? [entry intValue] : iconSize;

      entry = [nodeDict objectForKey: @"labeltxtsize"];
      if (entry)
	{
	  labelTextSize = [entry intValue];
	  ASSIGN (labelFont, [NSFont systemFontOfSize: labelTextSize]);
	}

      entry = [nodeDict objectForKey: @"iconposition"];
      iconPosition = entry ? [entry intValue] : iconPosition;

      entry = [nodeDict objectForKey: @"fsn_info_type"];
      infoType = entry ? [entry intValue] : infoType;

      if (infoType == FSNInfoExtendedType)
	{
	  DESTROY (extInfoType);
	  entry = [nodeDict objectForKey: @"ext_info_type"];

	  if (entry)
	    {
	      NSArray *availableTypes = [fsnodeRep availableExtendedInfoNames];
	      if ([availableTypes containsObject: entry])
		ASSIGN (extInfoType, entry);
	    }

	  if (extInfoType == nil)
	    infoType = FSNInfoNameType;
	}
    }

  return nodeDict;
}

- (NSMutableDictionary *)updateNodeInfo:(BOOL)ondisk
{
  /* Persist per-folder view settings to user defaults only.
   * Icon positions are stored via DS_Store / fdLocation, not here. */
  CREATE_AUTORELEASE_POOL(arp);
  NSMutableDictionary *updatedInfo = nil;

  if ([node isValid])
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
      NSString *prefsname = [NSString stringWithFormat: @"viewer_at_%@", [node path]];

      NSDictionary *prefs = [defaults dictionaryForKey: prefsname];
      if (prefs)
        updatedInfo = [prefs mutableCopy];
      else
        updatedInfo = [NSMutableDictionary new];

      [updatedInfo setObject: [NSNumber numberWithInt: iconSize]
                      forKey: @"iconsize"];
      [updatedInfo setObject: [NSNumber numberWithInt: labelTextSize]
                      forKey: @"labeltxtsize"];
      [updatedInfo setObject: [NSNumber numberWithInt: iconPosition]
                      forKey: @"iconposition"];
      [updatedInfo setObject: [NSNumber numberWithInt: infoType]
                      forKey: @"fsn_info_type"];

      if (infoType == FSNInfoExtendedType)
        [updatedInfo setObject: extInfoType forKey: @"ext_info_type"];

      if (ondisk)
        [defaults setObject: updatedInfo forKey: prefsname];
    }

  RELEASE (arp);
  return (AUTORELEASE (updatedInfo));
}

- (void)reloadContents
{
  NSArray *selection = [self selectedNodes];
  NSMutableArray *opennodes = [NSMutableArray array];
  NSUInteger i;

  /* A reload re-reads the directory from disk; drop cached file metadata
   * so labels/positions reflect any external change. */
  [[fsnodeRep metadataProvider] invalidateCaches];

  RETAIN (selection);

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isOpened])
	{
	  [opennodes addObject: [icon node]];
	}
    }

  RETAIN (opennodes);

  [self showContentsOfNode: node];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  for (i = 0; i < [selection count]; i++)
    {
      FSNode *nd = [selection objectAtIndex: i];

      if ([nd isValid])
	{
	  FSNIcon *icon = [self repOfSubnode: nd];

	  if (icon)
	    {
	      [icon select];
	    }
	}
    }

  selectionMask = NSSingleSelectionMask;

  RELEASE (selection);

  for (i = 0; i < [opennodes count]; i++)
    {
      FSNode *nd = [opennodes objectAtIndex: i];

      if ([nd isValid])
	{
	  FSNIcon *icon = [self repOfSubnode: nd];

	  if (icon)
	    {
	      [icon setOpened: YES];
	    }
	}
    }

  RELEASE (opennodes);

  [self checkLockedReps];
  [self tile];

  selection = [self selectedReps];

  if ([selection count])
    {
      [self scrollIconToVisible: [selection objectAtIndex: 0]];
    }

  [self selectionDidChange];
}

- (void)reloadFromNode:(FSNode *)anode
{
  if ([node isEqual: anode])
    {
      [self reloadContents];

    }
  else if ([node isSubnodeOfNode: anode])
    {
      NSArray *components = [FSNode nodeComponentsFromNode: anode toNode: node];
      int i;

      for (i = 0; i < [components count]; i++)
	{
	  FSNode *component = [components objectAtIndex: i];

	  if ([component isValid] == NO)
	    {
	      component = [FSNode nodeWithPath: [component parentPath]];
	      [self showContentsOfNode: component];
	      break;
	    }
	}
    }
}

- (FSNode *)baseNode
{
  return node;
}

- (FSNode *)shownNode
{
  return node;
}

- (BOOL)isSingleNode
{
  return YES;
}

- (BOOL)isShowingNode:(FSNode *)anode
{
  return [node isEqual: anode];
}

- (BOOL)isShowingPath:(NSString *)path
{
  return [[node path] isEqual: path];
}

- (void)sortTypeChangedAtPath:(NSString *)path
{
  if ((path == nil) || [[node path] isEqual: path])
    {
      [self reloadContents];
    }
}

- (void)nodeContentsWillChange:(NSDictionary *)info
{
  [self checkLockedReps];
}

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  NSString *operation = [info objectForKey: @"operation"];
  NSString *source = [info objectForKey: @"source"];
  NSString *destination = [info objectForKey: @"destination"];
  NSArray *files = [info objectForKey: @"files"];
  NSString *ndpath = [node path];
  NSUInteger i;

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [source lastPathComponent]];
      source = [source stringByDeletingLastPathComponent];
    }

  if (([ndpath isEqual: source] == NO) && ([ndpath isEqual: destination] == NO))
    {
      [self reloadContents];
      return;
    }

  if ([ndpath isEqual: source])
    {
      if ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceDestroyOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]) {

	if ([operation isEqual: NSWorkspaceRecycleOperation]) {
	  files = [info objectForKey: @"origfiles"];
	}

	for (i = 0; i < [files count]; i++)
	  {
	    NSString *fname = [files objectAtIndex: i];
	    FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];
	    [self removeRepOfSubnode: subnode];
	  }
      }
    }

  if ([operation isEqual: @"WorkspaceRenameOperation"])
    {
      files = [NSArray arrayWithObject: [destination lastPathComponent]];
      destination = [destination stringByDeletingLastPathComponent];
    }

  if ([ndpath isEqual: destination]
      && ([operation isEqual: NSWorkspaceMoveOperation]
	  || [operation isEqual: NSWorkspaceCopyOperation]
	  || [operation isEqual: NSWorkspaceLinkOperation]
	  || [operation isEqual: NSWorkspaceDuplicateOperation]
	  || [operation isEqual: @"WorkspaceCreateDirOperation"]
	  || [operation isEqual: @"WorkspaceCreateFileOperation"]
	  || [operation isEqual: NSWorkspaceRecycleOperation]
	  || [operation isEqual: @"WorkspaceRenameOperation"]
	  || [operation isEqual: @"WorkspaceRecycleOutOperation"]))
    {
      if ([operation isEqual: NSWorkspaceRecycleOperation])
	{
	  files = [info objectForKey: @"files"];
	}

      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];
	  FSNIcon *icon = [self repOfSubnode: subnode];

	  if (icon){
	    [icon setNode: subnode];
	  } else {
	    [self addRepForSubnode: subnode];
	  }
	}

      [self sortIcons];
    }

  [self checkLockedReps];
  [self tile];
  [self setNeedsDisplay: YES];
  [self selectionDidChange];
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  NSString *event = [info objectForKey: @"event"];
  NSArray *files = [info objectForKey: @"files"];
  NSString *ndpath = [node path];
  NSUInteger i;

  /* Files under the watched directory changed on disk — drop cached
   * metadata so re-read reflects the new state. */
  [[fsnodeRep metadataProvider] invalidateCaches];

  if ([event isEqual: @"GWFileDeletedInWatchedDirectory"])
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  NSString *fpath = [ndpath stringByAppendingPathComponent: fname];
	  [self removeRepOfSubnodePath: fpath];
	}
    }
  else if ([event isEqual: @"GWFileCreatedInWatchedDirectory"])
    {
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  FSNode *subnode = [FSNode nodeWithRelativePath: fname parent: node];

	  if (subnode && [subnode isValid])
	    {
	      FSNIcon *icon = [self repOfSubnode: subnode];

	      if (icon)
		{
		  [icon setNode: subnode];
		}
	      else
		{
		  [self addRepForSubnode: subnode];
		}
	    }
	}
    }

  [self sortIcons];
  [self tile];
  [self setNeedsDisplay: YES];
  [self selectionDidChange];
}

- (void)setShowType:(FSNInfoType)type
{
  if (infoType != type)
    {
      NSUInteger i;

      infoType = type;
      DESTROY (extInfoType);

      _gridCached = NO;
      [self calculateGridSize];

      for (i = 0; i < [icons count]; i++)
	{
	  FSNIcon *icon = [icons objectAtIndex: i];

	  [icon setNodeInfoShowType: infoType];
	  [icon tile];
	}

      [self sortIcons];
      [self tile];
    }
}

- (void)setExtendedShowType:(NSString *)type
{
  if ((extInfoType == nil) || ([extInfoType isEqual: type] == NO))
    {
      int i;

      infoType = FSNInfoExtendedType;
      ASSIGN (extInfoType, type);

      _gridCached = NO;
      [self calculateGridSize];

      for (i = 0; i < [icons count]; i++)
	{
	  FSNIcon *icon = [icons objectAtIndex: i];

	  [icon setExtendedShowType: extInfoType];
	  [icon tile];
	}

      [self sortIcons];
      [self tile];
    }
}

- (FSNInfoType)showType
{
  return infoType;
}

- (void)setIconSize:(int)size
{
  NSUInteger i;

  iconSize = size;
  _gridCached = NO;
  [self calculateGridSize];

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      [icon setIconSize: iconSize];
    }

  [self tile];
}

- (int)iconSize
{
  return iconSize;
}

- (void)setLabelTextSize:(int)size
{
  NSUInteger i;

  labelTextSize = size;
  ASSIGN (labelFont, [NSFont systemFontOfSize: labelTextSize]);
  _gridCached = NO;
  [self calculateGridSize];

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      [icon setFont: labelFont];
    }

  [nameEditor setFont: labelFont];

  [self tile];
}

- (int)labelTextSize
{
  return labelTextSize;
}

- (void)setIconPosition:(NSCellImagePosition)pos
{
  NSUInteger i;

  iconPosition = pos;
  _gridCached = NO;
  [self calculateGridSize];

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      [icon setIconPosition: iconPosition];
    }

  [self tile];
}

- (NSCellImagePosition)iconPosition
{
  return iconPosition;
}

- (void)updateIcons
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNode *inode = [icon node];
      [icon setNode: inode];
    }
}

- (id)repOfSubnode:(FSNode *)anode
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([[icon node] isEqualToNode: anode]) {
	return icon;
      }
    }

  return nil;
}

- (id)repOfSubnodePath:(NSString *)apath
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([[[icon node] path] isEqual: apath])
	{
	  return icon;
	}
    }

  return nil;
}

- (id)addRepForSubnode:(FSNode *)anode
{
  /* Never display internal metadata files */
  NSString *fname = [anode name];
  if ([fname isEqualToString: @".DS_Store"]
      || [fname hasPrefix: @"._"]
      || [fname isEqualToString: @"__MACOSX"])
    return nil;

  CREATE_AUTORELEASE_POOL(arp);
  FSNIcon *icon = [[FSNIcon alloc] initForNode: anode
                                  nodeInfoType: infoType
                                  extendedType: extInfoType
                                      iconSize: iconSize
                                  iconPosition: iconPosition
                                     labelFont: labelFont
                                     textColor: textColor
                                     gridIndex: -1
                                     dndSource: YES
                                     acceptDnd: YES
                                     slideBack: YES];
  [icons addObject: icon];
  [self addSubview: icon];
  RELEASE (icon);
  RELEASE (arp);

  return icon;
}

- (id)addRepForSubnodePath:(NSString *)apath
{
  FSNode *subnode = [FSNode nodeWithRelativePath: apath parent: node];
  return [self addRepForSubnode: subnode];
}

- (void)removeRepOfSubnode:(FSNode *)anode
{
  FSNIcon *icon = [self repOfSubnode: anode];

  if (icon)
    {
      [self removeRep: icon];
    }
}

- (void)removeRepOfSubnodePath:(NSString *)apath
{
  FSNIcon *icon = [self repOfSubnodePath: apath];

  if (icon)
    {
      [self removeRep: icon];
    }
}

- (void)removeRep:(id)arep
{
  if (arep == editIcon)
    {
      editIcon = nil;
    }
  [arep removeFromSuperview];
  [icons removeObject: arep];
}

- (void)unloadFromNode:(FSNode *)anode
{
  FSNode *parent = [FSNode nodeWithPath: [anode parentPath]];
  [self showContentsOfNode: parent];
}

- (void)repSelected:(id)arep
{
}

- (void)unselectOtherReps:(id)arep
{
  NSUInteger i;

  if (selectionMask & FSNMultipleSelectionMask)
    {
      return;
    }

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if (icon != arep)
	{
	  [icon unselect];
	}
    }
}

- (void)selectReps:(NSArray *)reps
{
  NSUInteger i;

  selectionMask = NSSingleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  [self unselectOtherReps: nil];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  for (i = 0; i < [reps count]; i++)
    {
      [[reps objectAtIndex: i] select];
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)selectRepsOfSubnodes:(NSArray *)nodes
{
  NSUInteger i;

  selectionMask = NSSingleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  [self unselectOtherReps: nil];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([nodes containsObject: [icon node]])
	{
	  [icon select];
	}
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)selectRepsOfPaths:(NSArray *)paths
{
  NSUInteger i;

  selectionMask = NSSingleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  [self unselectOtherReps: nil];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([paths containsObject: [[icon node] path]])
	{
	  [icon select];
	}
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)selectAll
{
  NSUInteger i;

  selectionMask = NSSingleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  [self unselectOtherReps: nil];

  selectionMask = FSNMultipleSelectionMask;
  selectionMask |= FSNCreatingSelectionMask;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNode *inode = [icon node];

      if ([inode isReserved] == NO) {
	[icon select];
      }
    }

  selectionMask = NSSingleSelectionMask;

  [self selectionDidChange];
}

- (void)selectAll:(id)sender
{
  [self selectAll];
}

- (void)scrollSelectionToVisible
{
  NSArray *selection = [self selectedReps];

  if ([selection count])
    {
      [self scrollIconToVisible: [selection objectAtIndex: 0]];
    }
  else
    {
      NSRect r = [self frame];
      [self scrollRectToVisible: NSMakeRect(0, r.size.height - 1, 1, 1)];
    }
}

- (NSArray *)reps
{
  return icons;
}

- (NSArray *)selectedReps
{
  NSMutableArray *selectedReps = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isSelected])

	[selectedReps addObject: icon];
    }

  return [selectedReps makeImmutableCopyOnFail: NO];
}

- (NSArray *)selectedNodes
{
  NSMutableArray *selectedNodes = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  NSArray *selection = [icon selection];

	  if (selection)
	    {
	      [selectedNodes addObjectsFromArray: selection];
	    }
	  else
	    {
	      [selectedNodes addObject: [icon node]];
	    }
	}
    }

  return [selectedNodes makeImmutableCopyOnFail: NO];
}

- (NSArray *)selectedPaths
{
  NSMutableArray *selectedPaths = [NSMutableArray array];
  NSUInteger i, j;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];

      if ([icon isSelected])
	{
	  NSArray *selection = [icon selection];

	  if (selection)
	    {
	      for (j = 0; j < [selection count]; j++)
		{
		  [selectedPaths addObject: [[selection objectAtIndex: j] path]];
		}
	    }
	  else
	    {
	      [selectedPaths addObject: [[icon node] path]];
	    }
	}
    }

  return [selectedPaths makeImmutableCopyOnFail: NO];
}

- (void)selectionDidChange
{
  if (!(selectionMask & FSNCreatingSelectionMask))
    {
      NSArray *selection = [self selectedNodes];

      if ([selection count] == 0)
	{
	  selection = [NSArray arrayWithObject: node];
	}

      if ((lastSelection == nil) || ([selection isEqual: lastSelection] == NO))
	{
	  ASSIGN (lastSelection, selection);
	  [desktopApp selectionChanged: selection];
	}

      [self updateNameEditor];
    }
}

- (void)checkLockedReps
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      [[icons objectAtIndex: i] checkLocked];
    }
}

- (void)setSelectionMask:(FSNSelectionMask)mask
{
  selectionMask = mask;
}

- (FSNSelectionMask)selectionMask
{
  return selectionMask;
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  [desktopApp openSelectionInNewViewer: newv];
}

- (void)restoreLastSelection
{
  if (lastSelection)
    {
      [self selectRepsOfSubnodes: lastSelection];
    }
}

- (void)setLastShownNode:(FSNode *)anode
{
}

- (BOOL)needsDndProxy
{
  return NO;
}

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo
{
  return [node involvedByFileOperation: opinfo];
}

- (BOOL)validatePasteOfFilenames:(NSArray *)names
			  wasCut:(BOOL)cut
{
  NSString *nodePath = [node path];
  NSString *prePath = [NSString stringWithString: nodePath];
  NSString *basePath;

  if ([names count] == 0)
    {
      return NO;
    }

  if ([node isWritable] == NO)
    {
      return NO;
    }

  basePath = [[names objectAtIndex: 0] stringByDeletingLastPathComponent];
  if ([basePath isEqual: nodePath]) {
    return NO;
  }

  if ([names containsObject: nodePath]) {
    return NO;
  }

  while (1)
    {
      if ([names containsObject: prePath])
	{
	  return NO;
	}
      if ([prePath isEqual: path_separator()])
	{
	  break;
	}
      prePath = [prePath stringByDeletingLastPathComponent];
    }

  return YES;
}

- (void)setBackgroundColor:(NSColor *)acolor
{
  ASSIGN (backColor, acolor);
  [[self window] setBackgroundColor: backColor];
  [self setNeedsDisplay: YES];
}

- (NSColor *)backgroundColor
{
  return backColor;
}

- (void)setBackgroundImage:(NSImage *)image
{
  ASSIGN (backgroundImage, image);
  [self setNeedsDisplay: YES];
}

- (NSImage *)backgroundImage
{
  return backgroundImage;
}

- (void)setTextColor:(NSColor *)acolor
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      [[icons objectAtIndex: i] setLabelTextColor: acolor];
    }

  [nameEditor setTextColor: acolor];

  ASSIGN (textColor, acolor);
}

- (NSColor *)textColor
{
  return textColor;
}

- (NSColor *)disabledTextColor
{
  return disabledTextColor;
}

@end


@implementation FSNIconsView (DraggingDestination)

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSDragOperation sourceDragMask;
  NSArray *sourcePaths;
  NSString *basePath;
  NSString *nodePath;
  NSString *prePath;
  NSUInteger count;

  isDragTarget = NO;

  pb = [sender draggingPasteboard];

  if (pb && [[pb types] containsObject: NSFilenamesPboardType])
    {
      sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
    }
  else if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

      sourcePaths = [pbDict objectForKey: @"paths"];
    }
  else if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];
      NSDictionary *pbDict = [NSUnarchiver unarchiveObjectWithData: pbData];

      sourcePaths = [pbDict objectForKey: @"paths"];
    }
  else
    {
      return NSDragOperationNone;
    }

  count = [sourcePaths count];
  if (count == 0)
    {
      return NSDragOperationNone;
    }

  if ([node isWritable] == NO)
    {
      return NSDragOperationNone;
    }

  nodePath = [node path];

  basePath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
  if ([basePath isEqual: nodePath])
    {
      return NSDragOperationNone;
    }

  if ([sourcePaths containsObject: nodePath])
    {
      return NSDragOperationNone;
    }

  prePath = [NSString stringWithString: nodePath];

  while (1)
    {
      if ([sourcePaths containsObject: prePath])
	{
	  return NSDragOperationNone;
	}
      if ([prePath isEqual: path_separator()])
	{
	  break;
	}
      prePath = [prePath stringByDeletingLastPathComponent];
    }

  if ([node isDirectory] && [node isParentOfPath: basePath])
    {
      NSArray *subNodes = [node subNodes];
      NSUInteger i;

      for (i = 0; i < [subNodes count]; i++)
	{
	  FSNode *nd = [subNodes objectAtIndex: i];

	  if ([nd isDirectory]) {
	    NSUInteger j;

	    for (j = 0; j < count; j++)
	      {
		NSString *fname = [[sourcePaths objectAtIndex: j] lastPathComponent];

		if ([[nd name] isEqual: fname])
		  {
		    return NSDragOperationNone;
		  }
	      }
	  }
	}
    }

  isDragTarget = YES;
  forceCopy = NO;

  sourceDragMask = dragOperationForCurrentModifierFlags();

  if (sourceDragMask & NSDragOperationMove)
    {
      if ([[NSFileManager defaultManager] isWritableFileAtPath: basePath]
	  && pathsAreOnSameVolume(basePath, nodePath))
	{
	  negotiatedDragOp = NSDragOperationMove;
	  return NSDragOperationMove;
	}
      forceCopy = YES;
      negotiatedDragOp = NSDragOperationCopy;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationCopy)
    {
      negotiatedDragOp = NSDragOperationCopy;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationLink)
    {
      negotiatedDragOp = NSDragOperationLink;
      return NSDragOperationLink;
    }

  isDragTarget = NO;
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSDragOperation sourceDragMask = dragOperationForCurrentModifierFlags();
  NSRect vr = [self visibleRect];
  NSRect scr = vr;
  int xsc = 0.0;
  int ysc = 0.0;
  int sc = 0;
  float margin = 4.0;
  NSRect ir = NSInsetRect(vr, margin, margin);
  NSPoint p = [sender draggingLocation];
  int i;

  p = [self convertPoint: p fromView: nil];

  if ([self mouse: p inRect: ir] == NO)
    {
      if (p.x < (NSMinX(vr) + margin))
	{
	  xsc = -gridSize.width;
	}
      else if (p.x > (NSMaxX(vr) - margin))
	{
	  xsc = gridSize.width;
	}

      if (p.y < (NSMinY(vr) + margin))
	{
	  ysc = -gridSize.height;
	}
      else if (p.y > (NSMaxY(vr) - margin))
	{
	  ysc = gridSize.height;
	}

      sc = (abs(xsc) >= abs(ysc)) ? xsc : ysc;

      for (i = 0; i < (int)fabsf(sc / margin); i++)
	{
	  CREATE_AUTORELEASE_POOL (pool);
	  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 0.01];
	  int x = (abs(xsc) >= i) ? (xsc > 0 ? margin : -margin) : 0;
	  int y = (abs(ysc) >= i) ? (ysc > 0 ? margin : -margin) : 0;

	  scr = NSOffsetRect(scr, x, y);
	  [self scrollRectToVisible: scr];

	  vr = [self visibleRect];
	  ir = NSInsetRect(vr, margin, margin);

	  p = [[self window] mouseLocationOutsideOfEventStream];
	  p = [self convertPoint: p fromView: nil];

	  if ([self mouse: p inRect: ir])
	    {
	      RELEASE (pool);
	      break;
	    }

	  [[NSRunLoop currentRunLoop] runUntilDate: limit];
	  RELEASE (pool);
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
      negotiatedDragOp = NSDragOperationCopy;
      return NSDragOperationCopy;
    }
  if (sourceDragMask & NSDragOperationLink)
    {
      negotiatedDragOp = NSDragOperationLink;
      return NSDragOperationLink;
    }

  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  isDragTarget = NO;
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return isDragTarget;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb;
  NSArray *sourcePaths;
  NSString *operation;
  NSString *source;
  NSMutableArray *files;
  NSMutableDictionary *opDict;
  NSString *trashPath;
  NSUInteger i;

  isDragTarget = NO;
  operation = nil;

  pb = [sender draggingPasteboard];

  if ([[pb types] containsObject: @"GWRemoteFilenamesPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWRemoteFilenamesPboardType"];

      [desktopApp concludeRemoteFilesDragOperation: pbData
				       atLocalPath: [node path]];
      return;
    }
  if ([[pb types] containsObject: @"GWLSFolderPboardType"])
    {
      NSData *pbData = [pb dataForType: @"GWLSFolderPboardType"];

      [desktopApp lsfolderDragOperation: pbData
			concludedAtPath: [node path]];
      return;
    }

  sourcePaths = [pb propertyListForType: NSFilenamesPboardType];

  if ([sourcePaths count] == 0)
    {
      return;
    }

  source = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];

  trashPath = [desktopApp trashPath];

  if ([source isEqual: trashPath])
    {
      operation = @"WorkspaceRecycleOutOperation";
    }
  else
    {
      switch (negotiatedDragOp)
	{
	  case NSDragOperationMove:
	    operation = NSWorkspaceMoveOperation;
	    break;
	  case NSDragOperationCopy:
	    operation = NSWorkspaceCopyOperation;
	    break;
	  case NSDragOperationLink:
	    operation = NSWorkspaceLinkOperation;
	    break;
	  default:
	    operation = NSWorkspaceCopyOperation;
	    break;
	}
    }

  files = [NSMutableArray array];
  for(i = 0; i < [sourcePaths count]; i++)
    {
      [files addObject: [[sourcePaths objectAtIndex: i] lastPathComponent]];
    }

  opDict = [NSMutableDictionary dictionary];
  [opDict setObject: operation forKey: @"operation"];
  [opDict setObject: source forKey: @"source"];
  [opDict setObject: [node path] forKey: @"destination"];
  [opDict setObject: files forKey: @"files"];

  [desktopApp performFileOperation: opDict];
}

@end


@implementation FSNIconsView (IconNameEditing)

- (void)updateNameEditor
{
  [self stopRepNameEditing];

  if (lastSelection && ([lastSelection count] == 1))
    {
      editIcon = [self repOfSubnode: [lastSelection objectAtIndex: 0]];
    }

  if (editIcon)
    {
      FSNode *ednode = [editIcon node];
      NSString *nodeDescr = [editIcon shownInfo];
      NSRect icnr = [editIcon frame];
      NSRect labr = [editIcon labelRect];
      NSCellImagePosition ipos = [editIcon iconPosition];
      int margin = [fsnodeRep labelMargin];
      float bw = [self bounds].size.width - EDIT_MARGIN;
      float edwidth = 0.0;
      NSRect edrect;

      [editIcon setNameEdited: YES];

      edwidth = [[nameEditor font] widthOfString: nodeDescr];
      edwidth += margin;

      if (ipos == NSImageAbove)
	{
	  float centerx = icnr.origin.x + (icnr.size.width / 2);

	  if ((centerx + (edwidth / 2)) >= bw)
	    {
	      centerx -= (centerx + (edwidth / 2) - bw);
	    }
	  else if ((centerx - (edwidth / 2)) < margin)
	    {
	      centerx += fabs(centerx - (edwidth / 2)) + margin;
	    }

	  edrect = [self convertRect: labr fromView: editIcon];
	  edrect.origin.x = centerx - (edwidth / 2);
	  edrect.size.width = edwidth;

	}
      else if (ipos == NSImageLeft)
	{
	  edrect = [self convertRect: labr fromView: editIcon];
	  edrect.size.width = edwidth;

	  if ((edrect.origin.x + edwidth) >= bw)
	    {
	      edrect.size.width = bw - edrect.origin.x;
	    }
	}
      else
	{
	  NSDebugLLog(@"gwspace", @"Unexpected icon position in [FSNIconsView updateNameEditor]");
	  return;
	}

      edrect = NSIntegralRect(edrect);

      [nameEditor setFrame: edrect];

      if (ipos == NSImageAbove)
	{
	  [nameEditor setAlignment: NSCenterTextAlignment];
	}
      else if (ipos == NSImageLeft)
	{
	  [nameEditor setAlignment: NSLeftTextAlignment];
	}

      [nameEditor setNode: ednode
	      stringValue: nodeDescr];

      [nameEditor setBackgroundColor: [NSColor selectedControlColor]];

      if ([editIcon isLocked] == NO)
	{
	  [nameEditor setTextColor: [NSColor controlTextColor]];
	}
      else
	{
	  [nameEditor setTextColor: [NSColor disabledControlTextColor]];
	}

      [nameEditor setEditable: NO];
      [nameEditor setSelectable: NO];
      [self addSubview: nameEditor];
    }
}

- (void)setNameEditorForRep:(id)arep
{
}

- (void)stopRepNameEditing
{
  NSUInteger i;

  if ([[self subviews] containsObject: nameEditor])
    {
      NSRect edrect = [nameEditor frame];
      [nameEditor abortEditing];
      [nameEditor setEditable: NO];
      [nameEditor setSelectable: NO];
      [nameEditor setNode: nil stringValue: @""];
      [nameEditor removeFromSuperview];
      [self setNeedsDisplayInRect: edrect];
    }

  for (i = 0; i < [icons count]; i++)
    {
      [[icons objectAtIndex: i] setNameEdited: NO];
    }

  editIcon = nil;
}

- (BOOL)canStartRepNameEditing
{
  return (editIcon && ([editIcon isLocked] == NO)
	  && ([[editIcon node] isMountPoint] == NO));
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
  NSRect icnr = [editIcon frame];
  NSCellImagePosition ipos = [editIcon iconPosition];
  float edwidth = [[nameEditor font] widthOfString: [nameEditor stringValue]];
  int margin = [fsnodeRep labelMargin];
  float bw = [self bounds].size.width - EDIT_MARGIN;
  NSRect edrect = [nameEditor frame];

  edwidth += margin;

  if (ipos == NSImageAbove)
    {
      float centerx = icnr.origin.x + (icnr.size.width / 2);

      while ((centerx + (edwidth / 2)) > bw) {
	centerx --;
	if (centerx < EDIT_MARGIN) {
	  break;
	}
      }

      while ((centerx - (edwidth / 2)) < EDIT_MARGIN)
	{
	  centerx ++;
	  if (centerx >= bw) {
	    break;
	  }
	}

      edrect.origin.x = centerx - (edwidth / 2);
      edrect.size.width = edwidth;
    }
  else if (ipos == NSImageLeft)
    {
      edrect.size.width = edwidth;

      if ((edrect.origin.x + edwidth) >= bw)
	{
	  edrect.size.width = bw - edrect.origin.x;
	}
    }

  [self setNeedsDisplayInRect: [nameEditor frame]];
  [nameEditor setFrame: NSIntegralRect(edrect)];
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
  FSNode *ednode = [nameEditor node];

#define CLEAREDITING				\
  [self stopRepNameEditing];			\
  return


  if ([ednode isParentWritable] == NO)
    {
      showAlertNoPermission([FSNode class], [ednode parentName]);
      CLEAREDITING;
    }
  else if ([ednode isSubnodeOfPath: [desktopApp trashPath]])
    {
      showAlertInRecycler([FSNode class]);
      CLEAREDITING;
    }
  else
    {
      NSString *newname = [nameEditor stringValue];
      NSString *newpath = [[ednode parentPath] stringByAppendingPathComponent: newname];
      NSString *extension = [newpath pathExtension];
      NSCharacterSet *notAllowSet = [NSCharacterSet characterSetWithCharactersInString: @"/\\*:?\33"];
      NSRange range = [newname rangeOfCharacterFromSet: notAllowSet];
      NSArray *dirContents = [ednode subNodeNamesOfParent];
      NSMutableDictionary *opinfo = [NSMutableDictionary dictionary];

      if (([newname length] == 0) || (range.length > 0))
	{
	  showAlertInvalidName([FSNode class]);
	  CLEAREDITING;
	}

      if (([extension length]
	   && ([ednode isDirectory] && ([ednode isPackage] == NO))))
	{
          if (showAlertExtensionChange([FSNode class], extension) == NSAlertDefaultReturn)
            {
              CLEAREDITING;
            }
	}

      if ([dirContents containsObject: newname])
	{
	  if ([newname isEqual: [ednode name]])
	    {
	      CLEAREDITING;
	    }
	  else
	    {
	      showAlertNameInUse([FSNode class], newname);
	      CLEAREDITING;
	    }
	}

      [opinfo setObject: @"WorkspaceRenameOperation" forKey: @"operation"];
      [opinfo setObject: [ednode path] forKey: @"source"];
      [opinfo setObject: newpath forKey: @"destination"];
      [opinfo setObject: [NSArray arrayWithObject: @""] forKey: @"files"];

      [self stopRepNameEditing];
      [desktopApp performFileOperation: opinfo];
    }
}

@end
