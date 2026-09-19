/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#include <math.h>

#import <GNUstepGUI/GSDisplayServer.h>

#import "DockStack.h"
#import "DockIcon.h"
#import "Dock.h"
#import "Workspace.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"

/* A fan beyond this many items would reach far up the screen; the rest are
 * in the folder, one click away. */
static const NSUInteger DockStackFanMaximum = 15;
/* Automatic shows a fan up to this many items, a grid beyond. */
static const NSUInteger DockStackAutomaticFanLimit = 12;
/* A list is a menu, and a menu longer than the screen cannot be scrolled. */
static const NSUInteger DockStackListMaximum = 60;

static const CGFloat DockStackIconSize = 48;
static const CGFloat DockStackGap = 4;

static const CGFloat DockStackGridColumns = 6;
static const CGFloat DockStackGridMinimumColumns = 3;
static const CGFloat DockStackGridVisibleRows = 4;
static const CGFloat DockStackGridCellWidth = 96;
static const CGFloat DockStackGridCellHeight = 84;
static const CGFloat DockStackGridPadding = 8;
static const CGFloat DockStackGridMargin = 16;
static const CGFloat DockStackGridHeaderHeight = 32;
static const CGFloat DockStackGridFooterHeight = 44;
static const CGFloat DockStackCornerRadius = 8;

static const CGFloat DockStackFanRowHeight = 56;
static const CGFloat DockStackFanCurve = 36;
static const CGFloat DockStackFanLabelMaximum = 220;

static DockStack *shownStack = nil;


/* The items of a folder as a stack shows them: what a viewer of it would
 * show, in the order the stack is sorted by. */
static NSArray *DockStackItems(NSString *folder, DockStackSort sort)
{
  FSNode *parent = [FSNode nodeWithPath: folder];
  NSArray *names = [[FSNodeRep sharedInstance] directoryContentsAtPath: folder];
  NSMutableArray *nodes = [NSMutableArray arrayWithCapacity: [names count]];
  NSUInteger i;

  for (i = 0; i < [names count]; i++)
    {
      FSNode *nd = [FSNode nodeWithRelativePath: [names objectAtIndex: i]
                                         parent: parent];
      if (nd != nil && [nd isValid])
        [nodes addObject: nd];
    }

  [nodes sortUsingComparator: ^NSComparisonResult (id a, id b) {
      FSNode *na = a;
      FSNode *nb = b;
      NSComparisonResult r = NSOrderedSame;

      switch (sort)
        {
          case DockStackSortDateAdded:
            /* Newest first: what was just put there is what is looked for. */
            r = [[nb creationDate] compare: [na creationDate]];
            break;
          case DockStackSortDateModified:
            r = [[nb modificationDate] compare: [na modificationDate]];
            break;
          case DockStackSortKind:
            r = [[na typeDescription] caseInsensitiveCompare: [nb typeDescription]];
            break;
          case DockStackSortName:
          default:
            break;
        }
      if (r == NSOrderedSame)
        r = [[na name] localizedCaseInsensitiveCompare: [nb name]];
      return r;
    }];

  return nodes;
}

static NSImage *DockStackIconOfNode(FSNode *node, int size)
{
  return [[FSNodeRep sharedInstance] iconOfSize: size forNode: node];
}

/* Opens the item as a double click in a viewer would. */
static void DockStackOpen(NSString *path)
{
  [[Workspace gworkspace] openSelectedPaths: [NSArray arrayWithObject: path]
                                  newViewer: YES];
}

static NSString *DockStackOpenFolderTitle(void)
{
  return NSLocalizedString(@"Open in Workspace", @"");
}


@interface DockStack (Private)
- (id)initWithIcon:(DockIcon *)anIcon;
- (void)showWithEvent:(NSEvent *)event;
- (void)showWindowWithContentView:(NSView *)view;
- (void)placeWindow;
- (void)closeStack;
- (void)openItem:(id)sender;
- (void)openFolder:(id)sender;
- (NSMenu *)listMenuForFolder:(NSString *)folder;
- (NSMenu *)menuForFolder:(NSString *)folder;
- (void)menuNeedsUpdate:(NSMenu *)list;
- (DockIcon *)icon;
- (NSWindow *)stackWindow;
@end


/* Borderless, yet takes the keyboard when the window manager lets it:
 * Escape closes it. */
@interface DockStackWindow : NSWindow
@end

@implementation DockStackWindow

- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

- (void)keyDown:(NSEvent *)event
{
  if ([[event charactersIgnoringModifiers] isEqual: @"\e"])
    [DockStack close];
  else
    [super keyDown: event];
}

- (void)cancelOperation:(id)sender
{
  [DockStack close];
}

@end


/* The items of a stack, laid out by a subclass: hovering lights an item up,
 * a click opens it, dragging takes it out of the stack. */
@interface DockStackItemsView : NSView
{
  NSArray *items;
  NSInteger hover;
  NSInteger pressed;
  NSPoint pressPoint;
  BOOL dragging;
}
- (void)setItems:(NSArray *)nodes;
- (NSArray *)items;
- (NSRect)iconRectForIndex:(NSInteger)i;
- (NSRect)hitRectForIndex:(NSInteger)i;
- (NSInteger)indexAtPoint:(NSPoint)p;
- (NSInteger)itemCount;
- (void)activateIndex:(NSInteger)i;
- (FSNode *)nodeForIndex:(NSInteger)i;
@end

@implementation DockStackItemsView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self)
    {
      hover = -1;
      pressed = -1;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (items);
  [super dealloc];
}

- (void)setItems:(NSArray *)nodes
{
  ASSIGN (items, nodes);
  hover = -1;
  pressed = -1;
  [self setNeedsDisplay: YES];
}

- (NSArray *)items
{
  return items;
}

- (NSInteger)itemCount
{
  return (NSInteger)[items count];
}

- (FSNode *)nodeForIndex:(NSInteger)i
{
  return (i >= 0 && i < (NSInteger)[items count]) ? [items objectAtIndex: i] : nil;
}

- (NSRect)iconRectForIndex:(NSInteger)i
{
  return NSZeroRect;
}

- (NSRect)hitRectForIndex:(NSInteger)i
{
  return [self iconRectForIndex: i];
}

- (NSInteger)indexAtPoint:(NSPoint)p
{
  NSInteger i;

  for (i = 0; i < [self itemCount]; i++)
    {
      if (NSPointInRect(p, [self hitRectForIndex: i]))
        return i;
    }
  return -1;
}

- (void)activateIndex:(NSInteger)i
{
  FSNode *node = [self nodeForIndex: i];

  if (node == nil)
    return;

  [DockStack close];
  DockStackOpen([node path]);
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

/* Hovering ends when the pointer leaves the items. */
- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  if ([self window] != nil)
    [self addTrackingRect: [self bounds] owner: self userData: NULL
             assumeInside: NO];
}

- (void)setHover:(NSInteger)i
{
  if (i == hover)
    return;
  if (hover >= 0)
    [self setNeedsDisplayInRect: NSInsetRect([self hitRectForIndex: hover], -4, -4)];
  hover = i;
  if (hover >= 0)
    [self setNeedsDisplayInRect: NSInsetRect([self hitRectForIndex: hover], -4, -4)];
}

- (void)mouseMoved:(NSEvent *)event
{
  [self setHover: [self indexAtPoint:
    [self convertPoint: [event locationInWindow] fromView: nil]]];
}

- (void)mouseExited:(NSEvent *)event
{
  [self setHover: -1];
}

- (void)mouseDown:(NSEvent *)event
{
  pressPoint = [self convertPoint: [event locationInWindow] fromView: nil];
  pressed = [self indexAtPoint: pressPoint];
  dragging = NO;
  [self setHover: pressed];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  FSNode *node = [self nodeForIndex: pressed];
  NSPasteboard *pb;
  NSRect r;

  if (node == nil || dragging)
    return;
  if (fabs(p.x - pressPoint.x) < 4 && fabs(p.y - pressPoint.y) < 4)
    return;

  dragging = YES;
  pb = [NSPasteboard pasteboardWithName: NSDragPboard];
  [pb declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType] owner: nil];
  [pb setPropertyList: [NSArray arrayWithObject: [node path]]
              forType: NSFilenamesPboardType];

  r = [self iconRectForIndex: pressed];
  /* The stack gets out of the way of wherever the item is going. */
  [[self window] orderOut: nil];
  [self dragImage: DockStackIconOfNode(node, (int)DockStackIconSize)
               at: NSMakePoint(NSMinX(r), [self isFlipped] ? NSMaxY(r) : NSMinY(r))
           offset: NSZeroSize
            event: event
       pasteboard: pb
           source: self
        slideBack: YES];
}

- (void)mouseUp:(NSEvent *)event
{
  NSPoint p = [self convertPoint: [event locationInWindow] fromView: nil];
  NSInteger i = [self indexAtPoint: p];

  if (dragging == NO && i >= 0 && i == pressed)
    [self activateIndex: i];
  pressed = -1;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
  return NSDragOperationCopy | NSDragOperationMove | NSDragOperationLink
    | NSDragOperationGeneric;
}

- (void)draggedImage:(NSImage *)image
             endedAt:(NSPoint)point
           operation:(NSDragOperation)operation
{
  dragging = NO;
  /* Not from inside the drag's own call chain: the view is still in use
   * there. */
  [DockStack performSelector: @selector(close) withObject: nil afterDelay: 0];
}

@end


/* The grid: items in rows of icons with their names, scrolling when there
 * are more than fit. */
@interface DockStackGridItemsView : DockStackItemsView
{
  NSInteger columns;
}
- (void)setColumns:(NSInteger)n;
@end

@implementation DockStackGridItemsView

- (BOOL)isFlipped
{
  return YES;
}

- (void)setColumns:(NSInteger)n
{
  columns = MAX (1, n);
}

- (NSRect)cellRectForIndex:(NSInteger)i
{
  NSInteger row = i / columns;
  NSInteger col = i % columns;

  return NSMakeRect(DockStackGridPadding + col * DockStackGridCellWidth,
                    DockStackGridPadding + row * DockStackGridCellHeight,
                    DockStackGridCellWidth, DockStackGridCellHeight);
}

- (NSRect)hitRectForIndex:(NSInteger)i
{
  return NSInsetRect([self cellRectForIndex: i], 2, 2);
}

- (NSRect)iconRectForIndex:(NSInteger)i
{
  NSRect cell = [self cellRectForIndex: i];

  return NSMakeRect(NSMidX(cell) - DockStackIconSize / 2, NSMinY(cell) + 6,
                    DockStackIconSize, DockStackIconSize);
}

- (void)activateIndex:(NSInteger)i
{
  FSNode *node = [self nodeForIndex: i];

  /* A folder opens right in the grid; the header takes the way back. */
  if ([node isDirectory] && [node isPackage] == NO)
    {
      [(id)[[self enclosingScrollView] superview] performSelector: @selector(enterFolder:)
                                                        withObject: [node path]];
      return;
    }
  [super activateIndex: i];
}

- (void)drawRect:(NSRect)rect
{
  NSMutableParagraphStyle *style = AUTORELEASE ([[NSParagraphStyle defaultParagraphStyle] mutableCopy]);
  NSDictionary *attrs;
  NSInteger i;

  [style setAlignment: NSCenterTextAlignment];
  [style setLineBreakMode: NSLineBreakByTruncatingMiddle];
  attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont systemFontOfSize: 11], NSFontAttributeName,
    [NSColor controlTextColor], NSForegroundColorAttributeName,
    style, NSParagraphStyleAttributeName, nil];

  for (i = 0; i < [self itemCount]; i++)
    {
      NSRect cell = [self cellRectForIndex: i];
      FSNode *node;
      NSRect textRect;

      if (NSIntersectsRect(cell, rect) == NO)
        continue;

      node = [self nodeForIndex: i];
      if (i == hover)
        {
          [[NSColor selectedControlColor] set];
          [[NSBezierPath bezierPathWithRoundedRect: [self hitRectForIndex: i]
                                           xRadius: 6
                                           yRadius: 6] fill];
        }

      [DockStackIconOfNode(node, (int)DockStackIconSize)
        drawInRect: [self iconRectForIndex: i]
          fromRect: NSZeroRect
         operation: NSCompositeSourceOver
          fraction: 1.0
    respectFlipped: YES
             hints: nil];

      textRect = NSMakeRect(NSMinX(cell) + 4,
                            NSMinY(cell) + 6 + DockStackIconSize + 4,
                            NSWidth(cell) - 8, 16);
      [[node displayName] drawInRect: textRect withAttributes: attrs];
    }
}

@end


/* The window around the grid: the folder's name with a way back from the
 * folders gone into, the items, and a button that opens the folder. */
@interface DockStackGridView : NSView
{
  DockStack *stack;
  NSString *root;
  NSMutableArray *trail;
  DockStackSort sort;
  NSTextField *title;
  NSButton *back;
  NSScrollView *scroll;
  DockStackGridItemsView *itemsView;
  NSTextField *empty;
  NSButton *openButton;
}
- (id)initForFolder:(NSString *)folder
               sort:(DockStackSort)aSort
              stack:(DockStack *)aStack;
- (void)enterFolder:(NSString *)folder;
@end

@implementation DockStackGridView

- (void)dealloc
{
  RELEASE (root);
  RELEASE (trail);
  [super dealloc];
}

- (NSString *)folder
{
  return [trail lastObject];
}

- (id)initForFolder:(NSString *)folder
               sort:(DockStackSort)aSort
              stack:(DockStack *)aStack
{
  NSArray *nodes = DockStackItems(folder, aSort);
  NSInteger count = (NSInteger)[nodes count];
  NSInteger cols = MIN ((NSInteger)DockStackGridColumns,
                        MAX ((NSInteger)DockStackGridMinimumColumns, count));
  NSInteger rows = MAX (1, (count + cols - 1) / cols);
  NSInteger shownRows = MIN (rows, (NSInteger)DockStackGridVisibleRows);
  BOOL scrolls = (rows > shownRows);
  CGFloat itemsW = cols * DockStackGridCellWidth + 2 * DockStackGridPadding;
  CGFloat itemsH = shownRows * DockStackGridCellHeight + 2 * DockStackGridPadding;
  CGFloat scrollerW = scrolls ? [NSScroller scrollerWidth] : 0;
  CGFloat w = itemsW + scrollerW + 2 * DockStackGridMargin;
  CGFloat h = DockStackGridHeaderHeight + itemsH + DockStackGridFooterHeight;

  self = [super initWithFrame: NSMakeRect(0, 0, w, h)];
  if (self == nil)
    return nil;

  stack = aStack;
  sort = aSort;
  ASSIGN (root, folder);
  trail = [[NSMutableArray alloc] initWithObjects: folder, nil];

  title = AUTORELEASE ([[NSTextField alloc] initWithFrame:
    NSMakeRect(DockStackGridMargin + 32, h - DockStackGridHeaderHeight + 6,
               w - 2 * (DockStackGridMargin + 32), 20)]);
  [title setEditable: NO];
  [title setSelectable: NO];
  [title setBezeled: NO];
  [title setDrawsBackground: NO];
  [title setAlignment: NSCenterTextAlignment];
  [title setFont: [NSFont boldSystemFontOfSize: 13]];
  [title setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
  [self addSubview: title];

  back = AUTORELEASE ([[NSButton alloc] initWithFrame:
    NSMakeRect(DockStackGridMargin, h - DockStackGridHeaderHeight + 6, 28, 20)]);
  [back setTitle: @"<"];
  [back setTarget: self];
  [back setAction: @selector(goBack:)];
  [back setAutoresizingMask: NSViewMinYMargin];
  [self addSubview: back];

  scroll = AUTORELEASE ([[NSScrollView alloc] initWithFrame:
    NSMakeRect(DockStackGridMargin, DockStackGridFooterHeight,
               itemsW + scrollerW, itemsH)]);
  /* Decided once, not left to autohiding: a document just as tall as the
   * view sent GNUstep's scroll view into endless re-tiling. */
  [scroll setHasVerticalScroller: scrolls];
  [scroll setBorderType: NSNoBorder];
  [scroll setDrawsBackground: NO];
  itemsView = AUTORELEASE ([[DockStackGridItemsView alloc] initWithFrame:
    NSMakeRect(0, 0, itemsW, itemsH)]);
  [itemsView setColumns: cols];
  [scroll setDocumentView: itemsView];
  [self addSubview: scroll];

  empty = AUTORELEASE ([[NSTextField alloc] initWithFrame:
    NSMakeRect(DockStackGridMargin, DockStackGridFooterHeight + itemsH / 2 - 10,
               itemsW, 20)]);
  [empty setEditable: NO];
  [empty setSelectable: NO];
  [empty setBezeled: NO];
  [empty setDrawsBackground: NO];
  [empty setAlignment: NSCenterTextAlignment];
  [empty setTextColor: [NSColor disabledControlTextColor]];
  [empty setStringValue: NSLocalizedString(@"No Items", @"")];
  [self addSubview: empty];

  openButton = AUTORELEASE ([[NSButton alloc] initWithFrame: NSZeroRect]);
  [openButton setTitle: DockStackOpenFolderTitle()];
  [openButton setTarget: self];
  [openButton setAction: @selector(openShownFolder:)];
  [openButton sizeToFit];
  {
    NSRect f = [openButton frame];

    f.size.width = MAX (f.size.width, 100);
    f.size.height = 20;
    f.origin.x = w - DockStackGridMargin - f.size.width;
    f.origin.y = (DockStackGridFooterHeight - f.size.height) / 2;
    [openButton setFrame: f];
  }
  [self addSubview: openButton];

  [self showFolder: folder items: nodes];
  return self;
}

- (void)showFolder:(NSString *)folder items:(NSArray *)nodes
{
  NSInteger cols = (NSInteger)DockStackGridColumns;
  NSRect visible = [[scroll contentView] frame];
  NSInteger rows;
  CGFloat docW = NSWidth(visible);

  /* The window keeps its size while going into folders: the columns that
   * fit it stay. */
  cols = MAX (1, (NSInteger)((docW - 2 * DockStackGridPadding) / DockStackGridCellWidth));
  rows = MAX (1, ((NSInteger)[nodes count] + cols - 1) / cols);
  [itemsView setColumns: cols];
  [itemsView setFrame: NSMakeRect(0, 0, docW,
    MAX (NSHeight(visible), rows * DockStackGridCellHeight + 2 * DockStackGridPadding))];
  [itemsView setItems: nodes];
  [itemsView scrollPoint: NSZeroPoint];

  [title setStringValue: [[FSNode nodeWithPath: folder] displayName]];
  [back setHidden: ([trail count] < 2)];
  [empty setHidden: ([nodes count] > 0)];
  [self setNeedsDisplay: YES];
}

- (void)enterFolder:(NSString *)folder
{
  [trail addObject: folder];
  [self showFolder: folder items: DockStackItems(folder, sort)];
}

- (void)goBack:(id)sender
{
  if ([trail count] < 2)
    return;
  [trail removeLastObject];
  [self showFolder: [self folder] items: DockStackItems([self folder], sort)];
}

- (void)openShownFolder:(id)sender
{
  NSString *folder = RETAIN ([self folder]);

  [DockStack close];
  [[Workspace gworkspace] newViewerAtPath: folder];
  RELEASE (folder);
}

- (void)drawRect:(NSRect)rect
{
  NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:
    NSInsetRect([self bounds], 0.5, 0.5) xRadius: DockStackCornerRadius
                                          yRadius: DockStackCornerRadius];

  [[NSColor windowBackgroundColor] set];
  NSRectFill(rect);
  [[NSColor gridColor] set];
  [outline setLineWidth: 1];
  [outline stroke];
}

@end


/* The fan: the items rising from a Dock at the bottom of the screen in a
 * gentle curve, each with its name on a plate beside it, and the folder
 * itself at the top. */
@interface DockStackFanView : DockStackItemsView
{
  NSString *folder;
  NSUInteger total;
  NSImage *picture;
  CGFloat labelWidth;
}
- (id)initForFolder:(NSString *)aFolder
              items:(NSArray *)nodes
            maxRows:(NSUInteger)maxRows;
- (NSImage *)shapePicture;
- (CGFloat)anchorX;
@end

@implementation DockStackFanView

- (void)dealloc
{
  RELEASE (folder);
  RELEASE (picture);
  [super dealloc];
}

+ (NSDictionary *)labelAttributes
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont boldSystemFontOfSize: 12], NSFontAttributeName,
    [NSColor whiteColor], NSForegroundColorAttributeName, nil];
}

/* The rows are the items, then the folder at the top. */
- (NSInteger)rowCount
{
  return [self itemCount] + 1;
}

- (NSString *)labelForRow:(NSInteger)i
{
  if (i < [self itemCount])
    return [[self nodeForIndex: i] displayName];

  if (total > [items count])
    return [NSString stringWithFormat: NSLocalizedString(@"%lu More in Workspace", @""),
                     (unsigned long)(total - [items count])];
  return DockStackOpenFolderTitle();
}

- (NSImage *)iconForRow:(NSInteger)i
{
  if (i < [self itemCount])
    return DockStackIconOfNode([self nodeForIndex: i], (int)DockStackIconSize);
  return DockStackIconOfNode([FSNode nodeWithPath: folder], (int)DockStackIconSize);
}

- (CGFloat)curveForRow:(NSInteger)i
{
  CGFloat t;

  if ([self rowCount] < 2)
    return 0;
  t = (CGFloat)i / (CGFloat)([self rowCount] - 1);
  return round(DockStackFanCurve * t * t);
}

- (NSRect)iconRectForIndex:(NSInteger)i
{
  return NSMakeRect(labelWidth + 8 + [self curveForRow: i],
                    DockStackGap + i * DockStackFanRowHeight,
                    DockStackIconSize, DockStackIconSize);
}

- (NSRect)plateRectForRow:(NSInteger)i
{
  NSRect icn = [self iconRectForIndex: i];
  CGFloat w = MIN ([[self labelForRow: i] sizeWithAttributes:
                      [[self class] labelAttributes]].width + 16,
                   DockStackFanLabelMaximum);

  return NSMakeRect(NSMinX(icn) - 6 - w, NSMidY(icn) - 10, w, 20);
}

- (NSRect)hitRectForIndex:(NSInteger)i
{
  return NSUnionRect([self iconRectForIndex: i], [self plateRectForRow: i]);
}

- (NSInteger)indexAtPoint:(NSPoint)p
{
  NSInteger i;

  for (i = 0; i < [self rowCount]; i++)
    {
      if (NSPointInRect(p, [self hitRectForIndex: i]))
        return i;
    }
  return -1;
}

- (void)activateIndex:(NSInteger)i
{
  if (i == [self itemCount])
    {
      NSString *f = RETAIN (folder);

      [DockStack close];
      [[Workspace gworkspace] newViewerAtPath: f];
      RELEASE (f);
      return;
    }
  [super activateIndex: i];
}

- (id)initForFolder:(NSString *)aFolder
              items:(NSArray *)nodes
            maxRows:(NSUInteger)maxRows
{
  /* One row stays for the folder itself at the top. */
  NSUInteger shown = MIN ([nodes count],
                          MIN (DockStackFanMaximum, MAX (maxRows, 2) - 1));
  NSDictionary *attrs = [[self class] labelAttributes];
  NSUInteger i;

  self = [super initWithFrame: NSZeroRect];
  if (self == nil)
    return nil;

  ASSIGN (folder, aFolder);
  total = [nodes count];
  [self setItems: [nodes subarrayWithRange: NSMakeRange(0, shown)]];

  labelWidth = 0;
  for (i = 0; i <= shown; i++)
    {
      labelWidth = MAX (labelWidth,
        MIN ([[self labelForRow: i] sizeWithAttributes: attrs].width + 16,
             DockStackFanLabelMaximum));
    }
  labelWidth += 6;

  [self setFrame: NSMakeRect(0, 0,
    labelWidth + 8 + DockStackFanCurve + DockStackIconSize + DockStackGap,
    [self rowCount] * DockStackFanRowHeight)];
  return self;
}

/* Where the icons of the lowest row are centred, which is what sits over
 * the folder's icon in the Dock. */
- (CGFloat)anchorX
{
  return NSMidX([self iconRectForIndex: 0]);
}

- (void)drawRow:(NSInteger)i lit:(BOOL)lit
{
  NSRect plate = [self plateRectForRow: i];
  NSDictionary *attrs = [[self class] labelAttributes];
  NSString *label = [self labelForRow: i];
  NSSize ts = [label sizeWithAttributes: attrs];
  NSRect textRect = NSMakeRect(NSMinX(plate) + 8,
                               NSMidY(plate) - ts.height / 2,
                               NSWidth(plate) - 16, ts.height);
  NSMutableParagraphStyle *style = AUTORELEASE ([[NSParagraphStyle defaultParagraphStyle] mutableCopy]);
  NSMutableDictionary *textAttrs = [NSMutableDictionary dictionaryWithDictionary: attrs];

  /* Solid: the fan is a shaped window, and without a compositor it can
   * show nothing half transparent. */
  [(lit ? [NSColor selectedControlColor]
        : [NSColor colorWithCalibratedWhite: 0.2 alpha: 1.0]) set];
  [[NSBezierPath bezierPathWithRoundedRect: plate xRadius: 10 yRadius: 10] fill];

  [style setLineBreakMode: NSLineBreakByTruncatingMiddle];
  [textAttrs setObject: style forKey: NSParagraphStyleAttributeName];
  if (lit)
    [textAttrs setObject: [NSColor selectedControlTextColor]
                  forKey: NSForegroundColorAttributeName];
  [label drawInRect: textRect withAttributes: textAttrs];

  [[self iconForRow: i] drawInRect: [self iconRectForIndex: i]
                          fromRect: NSZeroRect
                         operation: NSCompositeSourceOver
                          fraction: 1.0];
}

/* The fan without any row lit: what the window is shaped after. */
- (NSImage *)shapePicture
{
  NSImage *image = AUTORELEASE ([[NSImage alloc] initWithSize: [self bounds].size]);
  NSInteger i;

  [image setBackgroundColor: [NSColor clearColor]];
  [image lockFocus];
  for (i = 0; i < [self rowCount]; i++)
    [self drawRow: i lit: NO];
  [image unlockFocus];

  return image;
}

- (void)setShape:(NSImage *)image
{
  ASSIGN (picture, image);
}

- (void)drawRect:(NSRect)rect
{
  [picture drawAtPoint: NSZeroPoint
              fromRect: NSZeroRect
             operation: NSCompositeCopy
              fraction: 1.0];
  if (hover >= 0)
    [self drawRow: hover lit: YES];
}

@end


@implementation DockStack

+ (void)toggleForIcon:(DockIcon *)anIcon event:(NSEvent *)event
{
  BOOL same = (shownStack != nil && [shownStack icon] == anIcon);

  [self close];
  if (same)
    return;

  shownStack = [[DockStack alloc] initWithIcon: anIcon];
  [shownStack showWithEvent: event];
}

+ (void)close
{
  DockStack *stack = shownStack;

  if (stack == nil)
    return;
  shownStack = nil;
  [stack closeStack];
  RELEASE (stack);
}

+ (void)closeForIcon:(DockIcon *)anIcon
{
  if (shownStack != nil && [shownStack icon] == anIcon)
    [self close];
}

+ (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)aWindow
{
  NSEventType type = [event type];
  NSView *hit;

  if (shownStack == nil || aWindow == [shownStack stackWindow])
    return;
  if (type != NSLeftMouseDown && type != NSRightMouseDown
      && type != NSOtherMouseDown)
    return;

  /* A press on the stack's own icon is the first half of the click that
   * puts it away (see -toggleForIcon:event:). */
  hit = [[[aWindow contentView] superview] hitTest: [event locationInWindow]];
  while (hit != nil && hit != (NSView *)[shownStack icon])
    hit = [hit superview];
  if (hit != nil)
    return;

  [self close];
}

@end


@implementation DockStack (Private)

- (id)initWithIcon:(DockIcon *)anIcon
{
  self = [super init];
  if (self)
    ASSIGN (icon, anIcon);
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  RELEASE (window);
  RELEASE (menu);
  RELEASE (menuFolders);
  RELEASE (icon);
  [super dealloc];
}

- (DockIcon *)icon
{
  return icon;
}

- (NSWindow *)stackWindow
{
  return window;
}

- (void)showWithEvent:(NSEvent *)event
{
  NSString *folder = [icon path];
  DockStackSort sort = [icon stackSort];
  DockStackViewStyle style = [icon stackViewStyle];
  BOOL bottom = ([[icon dock] position] == DockPositionBottom);
  NSArray *nodes = DockStackItems(folder, sort);

  if (style == DockStackViewAutomatic)
    style = (bottom && [nodes count] <= DockStackAutomaticFanLimit)
      ? DockStackViewFan : DockStackViewGrid;
  /* A fan rises from a Dock along the bottom edge; beside a Dock on the
   * side it would run off the screen. */
  if (style == DockStackViewFan && bottom == NO)
    style = DockStackViewList;

  switch (style)
    {
      case DockStackViewFan:
        {
          DockStackFanView *fan = AUTORELEASE ([[DockStackFanView alloc]
            initForFolder: folder items: nodes maxRows: [self fanRowsThatFit]]);
          NSImage *shape = FSNShapeableImage([fan shapePicture],
                                             [[icon window] userSpaceScaleFactor]);

          [fan setShape: shape];
          [self showWindowWithContentView: fan];
          [GSServerForWindow(window) restrictWindow: [window windowNumber]
                                             toImage: shape];
          [window makeKeyAndOrderFront: nil];
          /* Shown from inside the Dock's mouse handling, it would wait for
           * the run loop to draw it; the shape is already on screen. */
          [window display];
        }
        break;

      case DockStackViewList:
        ASSIGN (menu, [self listMenuForFolder: folder]);
        /* Runs until the menu is done with; the stack is then over. */
        [NSMenu popUpContextMenu: menu withEvent: event forView: icon];
        break;

      case DockStackViewGrid:
      default:
        {
          DockStackGridView *grid = AUTORELEASE ([[DockStackGridView alloc]
            initForFolder: folder sort: sort stack: self]);
          NSBezierPath *round;
          NSImage *outline = AUTORELEASE ([[NSImage alloc] initWithSize:
                                                             [grid bounds].size]);

          [self showWindowWithContentView: grid];

          /* Rounded corners, cut into the window. */
          [outline setBackgroundColor: [NSColor clearColor]];
          [outline lockFocus];
          [[NSColor blackColor] set];
          round = [NSBezierPath bezierPathWithRoundedRect: [grid bounds]
                                                  xRadius: DockStackCornerRadius
                                                  yRadius: DockStackCornerRadius];
          [round fill];
          [outline unlockFocus];
          [GSServerForWindow(window) restrictWindow: [window windowNumber]
              toImage: FSNShapeableImage(outline, [[icon window] userSpaceScaleFactor])];
          [window makeKeyAndOrderFront: nil];
          [window display];
        }
        break;
    }
}

- (void)showWindowWithContentView:(NSView *)view
{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

  window = [[DockStackWindow alloc] initWithContentRect: [view bounds]
                                              styleMask: NSBorderlessWindowMask
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
  [window setReleasedWhenClosed: NO];
  [window setLevel: NSPopUpMenuWindowLevel];
  [window setAcceptsMouseMovedEvents: YES];
  [window setContentView: view];
  /* In points; the window's frame is then in the screen's pixels. */
  [window setContentSize: [view bounds].size];
  [self placeWindow];

  /* A click anywhere else - another of the application's windows, another
   * application - puts the stack away. */
  [nc addObserver: self
         selector: @selector(otherWindowBecameKey:)
             name: NSWindowDidBecomeKeyNotification
           object: nil];
  [nc addObserver: self
         selector: @selector(stackShouldClose:)
             name: NSApplicationDidResignActiveNotification
           object: NSApp];
}

/* As many rows of a fan as fit between the Dock and the top of the
 * screen. */
- (NSUInteger)fanRowsThatFit
{
  NSRect anchor = [[icon window] convertRectToScreen:
                     [icon convertRect: [icon bounds] toView: nil]];
  NSRect screen = [[[icon window] screen] visibleFrame];
  CGFloat scale = [[icon window] userSpaceScaleFactor];
  CGFloat room = (NSMaxY(screen) - NSMaxY(anchor)) / scale - 2 * DockStackGap;

  return (NSUInteger)MAX (0, floor(room / DockStackFanRowHeight));
}

- (void)otherWindowBecameKey:(NSNotification *)note
{
  if ([note object] != window)
    [self stackShouldClose: note];
}

- (void)stackShouldClose:(NSNotification *)note
{
  if (shownStack == self)
    [DockStack close];
}

/* Next to the folder's icon, on the side of the Dock facing the screen,
 * kept on the screen. */
- (void)placeWindow
{
  NSRect anchor = [[icon window] convertRectToScreen:
                     [icon convertRect: [icon bounds] toView: nil]];
  NSRect screen = [[[icon window] screen] frame];
  NSRect frame = [window frame];
  CGFloat scale = [[icon window] userSpaceScaleFactor];
  DockPosition position = [[icon dock] position];
  NSView *content = [window contentView];

  if (position == DockPositionBottom)
    {
      CGFloat centre = [content respondsToSelector: @selector(anchorX)]
        ? [(DockStackFanView *)content anchorX] * scale
        : NSWidth(frame) / 2;

      frame.origin.x = NSMidX(anchor) - centre;
      frame.origin.y = NSMaxY(anchor) + DockStackGap * scale;
    }
  else
    {
      frame.origin.y = NSMidY(anchor) - NSHeight(frame) / 2;
      if (position == DockPositionLeft)
        frame.origin.x = NSMaxX(anchor) + DockStackGap * scale;
      else
        frame.origin.x = NSMinX(anchor) - DockStackGap * scale - NSWidth(frame);
    }

  frame.origin.x = MAX (NSMinX(screen), MIN (frame.origin.x, NSMaxX(screen) - NSWidth(frame)));
  frame.origin.y = MAX (NSMinY(screen), MIN (frame.origin.y, NSMaxY(screen) - NSHeight(frame)));
  [window setFrameOrigin: frame.origin];
}

- (void)closeStack
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [window orderOut: nil];
  [window close];
}

- (void)openItem:(id)sender
{
  NSString *path = [sender representedObject];

  [DockStack close];
  DockStackOpen(path);
}

- (void)openFolder:(id)sender
{
  NSString *path = [sender representedObject];

  [DockStack close];
  [[Workspace gworkspace] newViewerAtPath: path];
}

/* The list: a menu of the folder's items, folders in it as submenus filled
 * when they open, and the folder itself at the end. */
- (NSMenu *)listMenuForFolder:(NSString *)folder
{
  NSMenu *list = [self menuForFolder: folder];

  [self menuNeedsUpdate: list];
  return list;
}

- (NSMenu *)menuForFolder:(NSString *)folder
{
  NSMenu *list = AUTORELEASE ([[NSMenu alloc] initWithTitle:
                               [[FSNode nodeWithPath: folder] displayName]]);

  if (menuFolders == nil)
    menuFolders = [NSMutableDictionary new];
  [menuFolders setObject: folder
                  forKey: [NSValue valueWithNonretainedObject: list]];
  [list setDelegate: (id)self];
  /* A folder's submenu is filled only when it opens; judged by its empty
   * submenu, the folder showed as disabled. */
  [list setAutoenablesItems: NO];
  return list;
}

- (void)menuNeedsUpdate:(NSMenu *)list
{
  NSString *folder = [menuFolders objectForKey:
                        [NSValue valueWithNonretainedObject: list]];
  NSArray *nodes;
  NSUInteger i, shown;
  NSMenuItem *item;

  if (folder == nil || [list numberOfItems] > 0)
    return;

  nodes = DockStackItems(folder, [icon stackSort]);
  shown = MIN ([nodes count], DockStackListMaximum);

  for (i = 0; i < shown; i++)
    {
      FSNode *node = [nodes objectAtIndex: i];

      item = AUTORELEASE ([[NSMenuItem alloc] initWithTitle: [node displayName]
                                                     action: @selector(openItem:)
                                              keyEquivalent: @""]);
      [item setTarget: self];
      [item setRepresentedObject: [node path]];
      [item setImage: DockStackIconOfNode(node, 16)];

      if ([node isDirectory] && [node isPackage] == NO)
        {
          [item setSubmenu: [self menuForFolder: [node path]]];
        }
      [list addItem: item];
    }

  if ([list numberOfItems] > 0)
    [list addItem: [NSMenuItem separatorItem]];

  item = AUTORELEASE ([[NSMenuItem alloc] initWithTitle:
      (([nodes count] > shown)
        ? [NSString stringWithFormat: NSLocalizedString(@"%lu More in Workspace", @""),
                    (unsigned long)([nodes count] - shown)]
        : DockStackOpenFolderTitle())
                                                 action: @selector(openFolder:)
                                          keyEquivalent: @""]);
  [item setTarget: self];
  [item setRepresentedObject: folder];
  [list addItem: item];
}

@end
