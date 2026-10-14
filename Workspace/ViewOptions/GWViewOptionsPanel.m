/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWViewOptionsPanel.h"
#import "GWViewOptionsModel.h"
#import "GWViewersManager.h"
#import "GWThumbnailStore.h"
#import "GWViewSettingsManager.h"
#import "GWFolderViewOptions.h"
#import "DSStoreInfo.h"
#import "DSStore.h"
#import "FSNIconsView.h"
#import "FSNListView.h"
#import "FSNBrowser.h"
#import "FSNColumnViewOptions.h"
#import "FSNode.h"
#import "../AppearanceMetrics.h"

#define VOStr(s) NSLocalizedStringFromTable (s, @"ViewOptions", @"")

/* How long after the last change the folder's records are written, so that
 * dragging a slider or a colour writes once. */
static const NSTimeInterval PersistDelay = 0.4;

static const CGFloat LabelWidth = 180.0;
static const CGFloat RowHeight = 24.0;
#define PanelMinWidth ([GWViewOptionsModel minimumPanelWidth])
#define PanelMaxWidth ([GWViewOptionsModel maximumPanelWidth])
static NSString *const PlacementDefaultsKey = @"GWViewOptionsPanelPlacement";
static const CGFloat PictureWellSize = 64.0;
static const CGFloat ControlsLeft = 24.0 + 180.0 + 8.0;

/* Top-down layout is simpler to state than bottom-up. */
@interface GWViewOptionsFlippedView : NSView
@end

@implementation GWViewOptionsFlippedView
- (BOOL)isFlipped
{
  return YES;
}
@end

/* The well Finder shows for a background picture: an image file dropped on
 * it is the picture.  The plain image view hands over the image only, and
 * the folder's record needs the file. */
@interface GWViewOptionsPictureWell : NSImageView
{
  NSString *droppedPath;
}
- (NSString *)droppedPath;
@end

@implementation GWViewOptionsPictureWell

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self)
    {
      [self setImageFrameStyle: NSImageFrameGrayBezel];
      [self setImageScaling: NSImageScaleProportionallyUpOrDown];
      [self registerForDraggedTypes: [NSArray arrayWithObject: NSFilenamesPboardType]];
    }
  return self;
}

- (void)dealloc
{
  RELEASE (droppedPath);
  [super dealloc];
}

- (NSString *)droppedPath
{
  return droppedPath;
}

- (NSString *)imageFileInPasteboard:(NSPasteboard *)pboard
{
  NSArray *files = [pboard propertyListForType: NSFilenamesPboardType];
  NSString *file = [files count] == 1 ? [files objectAtIndex: 0] : nil;

  if (file && [[NSImage imageFileTypes] containsObject: [[file pathExtension] lowercaseString]])
    return file;
  return nil;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  return [self imageFileInPasteboard: [sender draggingPasteboard]]
    ? NSDragOperationCopy : NSDragOperationNone;
}

/* The image view's own versions refuse what it has no image for; the drop
 * is decided here by the file alone. */
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  return [self draggingEntered: sender];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return [self imageFileInPasteboard: [sender draggingPasteboard]] != nil;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  NSString *file = [self imageFileInPasteboard: [sender draggingPasteboard]];

  if (file == nil)
    return NO;
  ASSIGN (droppedPath, file);
  return [self sendAction: [self action] to: [self target]];
}

@end

static GWViewOptionsPanel *sharedPanel = nil;

@interface GWViewOptionsPanel (Private)
- (void)buildPanel;
- (NSTextField *)labelWithTitle:(NSString *)title inView:(NSView *)pane y:(CGFloat)y;
- (NSPopUpButton *)popUpWithTitles:(NSArray *)titles inView:(NSView *)pane y:(CGFloat)y;
- (NSButton *)checkBoxWithTitle:(NSString *)title inView:(NSView *)pane y:(CGFloat)y;
- (NSSlider *)sliderFrom:(double)low to:(double)high inView:(NSView *)pane y:(CGFloat)y;
- (void)reloadFromViewer;
- (void)controlsFromModel;
- (void)modelFromControls;
- (void)controlsChanged:(id)sender;
- (void)pictureDropped:(id)sender;
- (void)restorePlacement;
- (void)savePlacement:(NSNotification *)notification;
- (void)persist;
- (void)flushPendingPersist;
- (void)mainWindowChanged:(NSNotification *)notification;
- (void)viewerWindowWillClose:(NSNotification *)notification;
- (id)nodeView;
@end

@implementation GWViewOptionsPanel

+ (GWViewOptionsPanel *)sharedPanel
{
  if (sharedPanel == nil)
    sharedPanel = [[GWViewOptionsPanel alloc] init];
  return sharedPanel;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      model = [[GWViewOptionsModel alloc] init];
      columnButtons = [[NSMutableDictionary alloc] init];
      [self buildPanel];
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(mainWindowChanged:)
               name: NSWindowDidBecomeMainNotification
             object: nil];
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  RELEASE (panel);
  RELEASE (model);
  RELEASE (columnButtons);
  [super dealloc];
}

- (NSPanel *)panel
{
  return panel;
}

- (void)setViewersManager:(GWViewersManager *)manager
{
  viewersManager = manager;
}

/* ---------------------------------------------------------------- */
/* Building the interface                                            */
/* ---------------------------------------------------------------- */

- (NSTextField *)labelWithTitle:(NSString *)title inView:(NSView *)pane y:(CGFloat)y
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame:
    NSMakeRect (METRICS_CONTENT_SIDE_MARGIN, y + 3, LabelWidth, 17)] autorelease];

  [field setStringValue: title];
  [field setEditable: NO];
  [field setSelectable: NO];
  [field setBezeled: NO];
  [field setDrawsBackground: NO];
  [field setAlignment: NSRightTextAlignment];
  [field setFont: METRICS_FONT_SYSTEM_REGULAR_13];
  [pane addSubview: field];
  return field;
}

- (NSPopUpButton *)popUpWithTitles:(NSArray *)titles inView:(NSView *)pane y:(CGFloat)y
{
  CGFloat width = [pane frame].size.width - ControlsLeft - METRICS_CONTENT_SIDE_MARGIN;
  NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:
    NSMakeRect (ControlsLeft, y, width, RowHeight - 4) pullsDown: NO] autorelease];

  [popUp addItemsWithTitles: titles];
  [popUp setAutoresizingMask: NSViewWidthSizable];
  [popUp setTarget: self];
  [popUp setAction: @selector(controlsChanged:)];
  [pane addSubview: popUp];
  return popUp;
}

- (NSButton *)checkBoxWithTitle:(NSString *)title inView:(NSView *)pane y:(CGFloat)y
{
  CGFloat width = [pane frame].size.width - ControlsLeft - METRICS_CONTENT_SIDE_MARGIN;
  NSButton *button = [[[NSButton alloc] initWithFrame:
    NSMakeRect (ControlsLeft, y, width, 18)] autorelease];

  [button setButtonType: NSSwitchButton];
  [button setTitle: title];
  [button setAutoresizingMask: NSViewWidthSizable];
  [button setTarget: self];
  [button setAction: @selector(controlsChanged:)];
  [pane addSubview: button];
  return button;
}

- (NSSlider *)sliderFrom:(double)low to:(double)high inView:(NSView *)pane y:(CGFloat)y
{
  CGFloat width = [pane frame].size.width - ControlsLeft - METRICS_CONTENT_SIDE_MARGIN;
  NSSlider *slider = [[[NSSlider alloc] initWithFrame:
    NSMakeRect (ControlsLeft, y, width, 20)] autorelease];

  [slider setMinValue: low];
  [slider setMaxValue: high];
  [slider setContinuous: YES];
  [slider setAutoresizingMask: NSViewWidthSizable];
  [slider setTarget: self];
  [slider setAction: @selector(controlsChanged:)];
  [pane addSubview: slider];
  return slider;
}

- (NSArray *)textSizeTitles
{
  NSMutableArray *titles = [NSMutableArray array];
  int size;

  for (size = FSNMinLabelTextSize; size <= FSNMaxLabelTextSize; size++)
    [titles addObject: [NSString stringWithFormat: @"%d pt", size]];
  return titles;
}

static NSString *
columnTitle (NSString *columnId)
{
  static NSDictionary *titles = nil;

  if (titles == nil)
    {
      titles = [[NSDictionary alloc] initWithObjectsAndKeys:
        VOStr (@"Date Modified"), FSNListColumnIdDateModified,
        VOStr (@"Date Created"), FSNListColumnIdDateCreated,
        VOStr (@"Date Last Opened"), FSNListColumnIdDateLastOpened,
        VOStr (@"Size"), FSNListColumnIdSize,
        VOStr (@"Kind"), FSNListColumnIdKind,
        VOStr (@"Label"), FSNListColumnIdLabel,
        VOStr (@"Version"), FSNListColumnIdVersion,
        VOStr (@"Comments"), FSNListColumnIdComments,
        nil];
    }
  return [titles objectForKey: columnId];
}

- (void)buildPanel
{
  CGFloat width = PanelMinWidth;
  CGFloat paneHeight = 0;
  CGFloat bottomHeight = METRICS_CONTENT_BOTTOM_MARGIN + 18 + METRICS_SPACE_12;
  CGFloat y;
  NSView *content;
  NSString *columnId;

  /* Icon pane, rows from the top. */
  iconPane = [[GWViewOptionsFlippedView alloc] initWithFrame: NSMakeRect (0, 0, width, 10)];
  y = METRICS_CONTENT_TOP_MARGIN;

  iconSizeLabel = [self labelWithTitle: @"" inView: iconPane y: y];
  iconSizeSlider = [self sliderFrom: 16 to: GWThumbnailMaximumPoints inView: iconPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Grid spacing:") inView: iconPane y: y];
  gridSpacingSlider = [self sliderFrom: 54 to: 100 inView: iconPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Text size:") inView: iconPane y: y];
  textSizePopUp = [self popUpWithTitles: [self textSizeTitles] inView: iconPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Label position:") inView: iconPane y: y];
  labelPositionPopUp = [self popUpWithTitles:
    [NSArray arrayWithObjects: VOStr (@"Bottom"), VOStr (@"Right"), nil]
                                      inView: iconPane y: y];
  y += RowHeight + 4;

  itemInfoButton = [self checkBoxWithTitle: VOStr (@"Show item info") inView: iconPane y: y];
  y += RowHeight;
  iconPreviewButton = [self checkBoxWithTitle: VOStr (@"Show icon preview") inView: iconPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Arrange by:") inView: iconPane y: y];
  /* In the order of +[GWViewOptionsModel arrangeByValues]. */
  arrangePopUp = [self popUpWithTitles:
    [NSArray arrayWithObjects: VOStr (@"None"), VOStr (@"Snap to Grid"), VOStr (@"Name"),
             VOStr (@"Kind"), VOStr (@"Date Modified"), VOStr (@"Date Created"),
             VOStr (@"Size"), VOStr (@"Label"), nil]
                               inView: iconPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Background:") inView: iconPane y: y];
  backgroundPopUp = [self popUpWithTitles:
    [NSArray arrayWithObjects: VOStr (@"White"), VOStr (@"Color"), VOStr (@"Picture"), nil]
                                   inView: iconPane y: y];
  y += RowHeight + 4;

  colorWell = [[[NSColorWell alloc] initWithFrame:
    NSMakeRect (ControlsLeft, y, 44, 24)] autorelease];
  [colorWell setTarget: self];
  [colorWell setAction: @selector(controlsChanged:)];
  [iconPane addSubview: colorWell];
  pictureWell = [[[GWViewOptionsPictureWell alloc] initWithFrame:
    NSMakeRect (ControlsLeft, y, PictureWellSize, PictureWellSize)] autorelease];
  [pictureWell setTarget: self];
  [pictureWell setAction: @selector(pictureDropped:)];
  [iconPane addSubview: pictureWell];
  pictureButton = [[[NSButton alloc] initWithFrame:
    NSMakeRect (ControlsLeft + PictureWellSize + METRICS_SPACE_12,
                y + (PictureWellSize - METRICS_BUTTON_HEIGHT) / 2, 120, METRICS_BUTTON_HEIGHT + 4)] autorelease];
  [pictureButton setBezelStyle: NSRoundedBezelStyle];
  [pictureButton setTitle: VOStr (@"Select...")];
  [pictureButton setTarget: self];
  [pictureButton setAction: @selector(choosePicture:)];
  [iconPane addSubview: pictureButton];
  y += PictureWellSize + 4;
  paneHeight = y;

  /* List pane. */
  listPane = [[GWViewOptionsFlippedView alloc] initWithFrame: NSMakeRect (0, 0, width, 10)];
  y = METRICS_CONTENT_TOP_MARGIN;

  [self labelWithTitle: VOStr (@"Text size:") inView: listPane y: y];
  listTextSizePopUp = [self popUpWithTitles: [self textSizeTitles] inView: listPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Icon size:") inView: listPane y: y];
  listIconSizePopUp = [self popUpWithTitles:
    [NSArray arrayWithObjects: VOStr (@"Small"), VOStr (@"Large"), nil]
                                     inView: listPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Show columns:") inView: listPane y: y];
  for (columnId in [GWViewOptionsModel optionalListColumnIds])
    {
      NSButton *button = [self checkBoxWithTitle: columnTitle (columnId)
                                          inView: listPane y: y];

      [columnButtons setObject: button forKey: columnId];
      y += RowHeight - 4;
    }
  y += 8;
  relativeDatesButton = [self checkBoxWithTitle: VOStr (@"Use relative dates")
                                         inView: listPane y: y];
  y += RowHeight - 4;
  allSizesButton = [self checkBoxWithTitle: VOStr (@"Calculate all sizes")
                                    inView: listPane y: y];
  y += RowHeight;
  if (y > paneHeight)
    paneHeight = y;

  /* Column pane: the options are the same for all folders [O:E30]. */
  columnPane = [[GWViewOptionsFlippedView alloc] initWithFrame: NSMakeRect (0, 0, width, 10)];
  y = METRICS_CONTENT_TOP_MARGIN;

  [self labelWithTitle: VOStr (@"Text size:") inView: columnPane y: y];
  columnTextSizePopUp = [self popUpWithTitles: [self textSizeTitles] inView: columnPane y: y];
  y += RowHeight + 4;

  columnIconsButton = [self checkBoxWithTitle: VOStr (@"Show icons") inView: columnPane y: y];
  y += RowHeight;
  columnPreviewButton = [self checkBoxWithTitle: VOStr (@"Show icon preview") inView: columnPane y: y];
  y += RowHeight;
  columnPreviewColumnButton = [self checkBoxWithTitle: VOStr (@"Show preview column")
                                               inView: columnPane y: y];
  y += RowHeight + 4;

  [self labelWithTitle: VOStr (@"Arrange by:") inView: columnPane y: y];
  /* In the order of FSNIconsArrangement. */
  columnArrangePopUp = [self popUpWithTitles:
    [NSArray arrayWithObjects: VOStr (@"None"), VOStr (@"Name"), VOStr (@"Kind"),
             VOStr (@"Date Modified"), VOStr (@"Date Created"), VOStr (@"Size"),
             VOStr (@"Label"), nil]
                                      inView: columnPane y: y];
  y += RowHeight + 4;
  if (y > paneHeight)
    paneHeight = y;

  content = [[[GWViewOptionsFlippedView alloc] initWithFrame:
    NSMakeRect (0, 0, width, paneHeight + bottomHeight)] autorelease];
  [iconPane setFrame: NSMakeRect (0, 0, width, paneHeight)];
  [listPane setFrame: NSMakeRect (0, 0, width, paneHeight)];
  [columnPane setFrame: NSMakeRect (0, 0, width, paneHeight)];
  [columnPane setAutoresizingMask: NSViewWidthSizable];
  [content addSubview: columnPane];
  RELEASE (columnPane);
  [iconPane setAutoresizingMask: NSViewWidthSizable];
  [listPane setAutoresizingMask: NSViewWidthSizable];
  [content addSubview: iconPane];
  [content addSubview: listPane];
  RELEASE (iconPane);
  RELEASE (listPane);

  emptyLabel = [[[NSTextField alloc] initWithFrame:
    NSMakeRect (METRICS_CONTENT_SIDE_MARGIN, METRICS_CONTENT_TOP_MARGIN,
                width - 2 * METRICS_CONTENT_SIDE_MARGIN, 34)] autorelease];
  [emptyLabel setStringValue: VOStr (@"This window has no view options.")];
  [emptyLabel setEditable: NO];
  [emptyLabel setSelectable: NO];
  [emptyLabel setBezeled: NO];
  [emptyLabel setDrawsBackground: NO];
  [emptyLabel setAutoresizingMask: NSViewWidthSizable];
  [content addSubview: emptyLabel];

  alwaysOpenButton = [[[NSButton alloc] initWithFrame:
    NSMakeRect (METRICS_CONTENT_SIDE_MARGIN, paneHeight + METRICS_SPACE_12,
                width - 2 * METRICS_CONTENT_SIDE_MARGIN, 18)] autorelease];
  [alwaysOpenButton setButtonType: NSSwitchButton];
  [alwaysOpenButton setAutoresizingMask: NSViewWidthSizable];
  [alwaysOpenButton setTarget: self];
  [alwaysOpenButton setAction: @selector(controlsChanged:)];
  [content addSubview: alwaysOpenButton];

  panel = [[NSPanel alloc] initWithContentRect: [content frame]
                                     styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                | NSResizableWindowMask | NSUtilityWindowMask
                                       backing: NSBackingStoreBuffered
                                         defer: YES];
  [panel setTitle: VOStr (@"View Options")];
  [panel setReleasedWhenClosed: NO];
  [panel setBecomesKeyOnlyIfNeeded: YES];
  [panel setFloatingPanel: YES];
  /* The menu bar belongs to another application, so using a menu deactivates this one. */
  [panel setHidesOnDeactivate: NO];
  /* Only the width can change; the limits are for the whole window, with
   * its title bar, in pixels like the frame. */
  [panel setMinSize: NSMakeSize (PanelMinWidth * [panel userSpaceScaleFactor], [panel frame].size.height)];
  [panel setMaxSize: NSMakeSize (PanelMaxWidth * [panel userSpaceScaleFactor], [panel frame].size.height)];
  [panel setContentView: content];
  /* A new window starts at the screen's lower left corner. */
  [panel center];
  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(savePlacement:)
                                               name: NSWindowDidMoveNotification object: panel];
  [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(savePlacement:)
                                               name: NSWindowDidResizeNotification object: panel];
  [self controlsFromModel];
}

/* ---------------------------------------------------------------- */
/* Showing                                                           */
/* ---------------------------------------------------------------- */

- (void)showForViewer:(id)aviewer
{
  [self flushPendingPersist];
  viewer = aviewer;
  [self reloadFromViewer];
  [panel orderFront: nil];
  if (placementRestored == NO)
    {
      placementRestored = YES;
      /* The window manager has not framed the window yet, so its frame
       * math would still be a guess; the saved placement goes on once it
       * has. */
      [self performSelector: @selector(restorePlacement) withObject: nil afterDelay: 0.5];
    }
}

- (void)restorePlacement
{
  NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey: PlacementDefaultsKey];
  NSPoint origin;
  CGFloat width;

  if (saved && [GWViewOptionsModel getPlacement: saved origin: &origin width: &width])
    {
      NSRect frame = [panel frame];

      /* The height limits were taken from the frame before the window
       * manager framed the window, 3 pixels more than it really has; left
       * so, the frame grows by them and the panel creeps with every restart. */
      [panel setMinSize: NSMakeSize ([panel minSize].width, frame.size.height)];
      [panel setMaxSize: NSMakeSize ([panel maxSize].width, frame.size.height)];
      frame.size.width = width * [panel userSpaceScaleFactor];
      frame.origin = origin;
      [panel setFrame: frame display: YES];
    }
  placementSaving = YES;
}

- (void)savePlacement:(NSNotification *)notification
{
  NSRect frame = [panel frame];

  /* Not before the saved placement is back, or the guessed one overwrites it. */
  if (placementSaving == NO)
    return;
  [[NSUserDefaults standardUserDefaults]
    setObject: [GWViewOptionsModel placementStringWithOrigin: frame.origin
                                                  width: frame.size.width / [panel userSpaceScaleFactor]]
       forKey: PlacementDefaultsKey];
  /* The panel is moved or resized by hand rarely, and the application may
   * be quit before the defaults are written on their own. */
  [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSWindow *)frontViewerWindow
{
  NSWindow *window = [NSApp keyWindow] ? [NSApp keyWindow] : [NSApp mainWindow];

  /* The menu bar lives in another application, so while a menu is used
   * this one is inactive and has no key or main window; the viewer window
   * that was main last is the one meant. */
  if (window == nil || [viewersManager hasViewerWithWindow: window] == NO)
    window = lastViewerWindow;
  if (window && [viewersManager hasViewerWithWindow: window])
    return window;
  return nil;
}

- (BOOL)hasViewerToEdit
{
  return [self frontViewerWindow] != nil;
}

- (void)showForMainWindow
{
  NSWindow *window = [self frontViewerWindow];

  [self showForViewer: window ? [viewersManager viewerWithWindow: window] : nil];
}

- (void)mainWindowChanged:(NSNotification *)notification
{
  NSWindow *window = [notification object];

  if (window == panel || viewersManager == nil
      || [viewersManager hasViewerWithWindow: window] == NO)
    return;

  lastViewerWindow = window;
  if ([panel isVisible] == NO)
    return;

  [self flushPendingPersist];
  viewer = [viewersManager viewerWithWindow: window];
  [self reloadFromViewer];
}

- (void)viewerWindowWillClose:(NSNotification *)notification
{
  [self flushPendingPersist];
  viewer = nil;
  [self reloadFromViewer];
}

- (id)nodeView
{
  return [viewer nodeView];
}

- (void)reloadFromViewer
{
  id view = viewer ? [self nodeView] : nil;
  BOOL icons = [view isKindOfClass: [FSNIconsView class]];
  BOOL list = [view isKindOfClass: [FSNListView class]];
  BOOL column = [view isKindOfClass: [FSNBrowser class]];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSWindow *window = (icons || list || column) ? [view window] : nil;

  if (viewerWindow)
    {
      [nc removeObserver: self name: NSWindowWillCloseNotification object: viewerWindow];
    }
  viewerWindow = window;
  if (window)
    {
      [nc addObserver: self selector: @selector(viewerWindowWillClose:)
                 name: NSWindowWillCloseNotification object: window];
    }

  RELEASE (model);
  model = [[GWViewOptionsModel alloc] init];
  if (icons || list || column)
    {
      /* What the folder keeps first (background, grid spacing and the
       * options of the other kind of view), then what the window shows. */
      NSString *path = [[view shownNode] path];
      DSStoreInfo *info = [[GWViewSettingsManager managerForDirectoryPath: path] readSettings];

      [model takeFromInfo: info];
      if (icons)
        [model takeFromIconsView: view];
      else if (list)
        [model takeFromListDataSource: [(FSNListView *)view dataSource]];
      else
        [model takeFromColumnViewOptions: [FSNColumnViewOptions sharedOptions]];
      [model setAlwaysOpenStyle: icons ? DSStoreViewStyleIcon
                                       : (list ? DSStoreViewStyleList : DSStoreViewStyleColumn)];
      [panel setTitle: [NSString stringWithFormat: @"%@ %@",
                                 [path lastPathComponent], VOStr (@"View Options")]];
    }
  else
    {
      [panel setTitle: VOStr (@"View Options")];
    }

  [iconPane setHidden: icons == NO];
  [listPane setHidden: list == NO];
  [columnPane setHidden: column == NO];
  [emptyLabel setHidden: icons || list || column];
  [alwaysOpenButton setHidden: (icons || list || column) == NO];
  [alwaysOpenButton setTitle: list ? VOStr (@"Always open in list view")
                                   : (column ? VOStr (@"Always open in column view")
                                             : VOStr (@"Always open in icon view"))];
  [self controlsFromModel];
}

/* ---------------------------------------------------------------- */
/* Controls and model                                                */
/* ---------------------------------------------------------------- */

- (void)controlsFromModel
{
  NSString *columnId;
  NSUInteger arrange = [[GWViewOptionsModel arrangeByValues] indexOfObject: [model arrangeBy]];

  loading = YES;
  [iconSizeSlider setIntValue: [model iconSize]];
  [iconSizeLabel setStringValue: [NSString stringWithFormat: @"%@ %d x %d",
                                           VOStr (@"Icon size:"), [model iconSize], [model iconSize]]];
  [gridSpacingSlider setDoubleValue: [model gridSpacing]];
  [textSizePopUp selectItemAtIndex: [model textSize] - FSNMinLabelTextSize];
  [labelPositionPopUp selectItemAtIndex: [model labelOnRight] ? 1 : 0];
  [itemInfoButton setState: [model showsItemInfo] ? NSOnState : NSOffState];
  [iconPreviewButton setState: [model showsIconPreview] ? NSOnState : NSOffState];
  [arrangePopUp selectItemAtIndex: arrange == NSNotFound ? 0 : (NSInteger)arrange];
  [backgroundPopUp selectItemAtIndex: [model backgroundType]];
  if ([model backgroundColor])
    [colorWell setColor: [model backgroundColor]];
  [colorWell setHidden: [model backgroundType] != DSStoreBackgroundColor];
  [pictureButton setHidden: [model backgroundType] != DSStoreBackgroundPicture];
  [pictureWell setHidden: [model backgroundType] != DSStoreBackgroundPicture];
  [pictureWell setImage: [model backgroundImagePath]
    ? [[[NSImage alloc] initWithContentsOfFile: [model backgroundImagePath]] autorelease] : nil];

  [listTextSizePopUp selectItemAtIndex: [model listTextSize] - FSNMinLabelTextSize];
  [listIconSizePopUp selectItemAtIndex: [model listLargeIcons] ? 1 : 0];
  for (columnId in columnButtons)
    {
      [[columnButtons objectForKey: columnId]
        setState: [[model visibleColumns] containsObject: columnId] ? NSOnState : NSOffState];
    }
  [columnTextSizePopUp selectItemAtIndex: [model columnTextSize] - FSNMinLabelTextSize];
  [columnIconsButton setState: [model columnShowsIcons] ? NSOnState : NSOffState];
  [columnPreviewButton setState: [model columnShowsIconPreview] ? NSOnState : NSOffState];
  /* Without icons there is nothing to preview, as in Finder. */
  [columnPreviewButton setEnabled: [model columnShowsIcons]];
  [columnPreviewColumnButton setState: [model columnShowsPreviewColumn] ? NSOnState : NSOffState];
  [columnArrangePopUp selectItemAtIndex: [model columnArrangement]];
  [relativeDatesButton setState: [model usesRelativeDates] ? NSOnState : NSOffState];
  [allSizesButton setState: [model calculatesAllSizes] ? NSOnState : NSOffState];
  [alwaysOpenButton setState: [model alwaysOpen] ? NSOnState : NSOffState];
  loading = NO;
}

- (void)modelFromControls
{
  NSMutableSet *shown = [NSMutableSet set];
  NSString *columnId;

  [model setIconSize: [iconSizeSlider intValue]];
  [model setGridSpacing: [gridSpacingSlider doubleValue]];
  [model setTextSize: FSNMinLabelTextSize + (int)[textSizePopUp indexOfSelectedItem]];
  [model setLabelOnRight: [labelPositionPopUp indexOfSelectedItem] == 1];
  [model setShowsItemInfo: [itemInfoButton state] == NSOnState];
  [model setShowsIconPreview: [iconPreviewButton state] == NSOnState];
  [model setArrangeBy: [[GWViewOptionsModel arrangeByValues]
                         objectAtIndex: [arrangePopUp indexOfSelectedItem]]];
  [model setBackgroundType: (DSStoreBackgroundType)[backgroundPopUp indexOfSelectedItem]];
  if ([model backgroundType] == DSStoreBackgroundColor)
    [model setBackgroundColor: [colorWell color]];

  [model setListTextSize: FSNMinLabelTextSize + (int)[listTextSizePopUp indexOfSelectedItem]];
  [model setListLargeIcons: [listIconSizePopUp indexOfSelectedItem] == 1];
  for (columnId in columnButtons)
    {
      if ([[columnButtons objectForKey: columnId] state] == NSOnState)
        [shown addObject: columnId];
    }
  [model setVisibleColumns: shown];
  [model setColumnTextSize: FSNMinLabelTextSize + (int)[columnTextSizePopUp indexOfSelectedItem]];
  [model setColumnShowsIcons: [columnIconsButton state] == NSOnState];
  [model setColumnShowsIconPreview: [columnPreviewButton state] == NSOnState];
  [model setColumnShowsPreviewColumn: [columnPreviewColumnButton state] == NSOnState];
  [model setColumnArrangement: (FSNIconsArrangement)[columnArrangePopUp indexOfSelectedItem]];
  [model setUsesRelativeDates: [relativeDatesButton state] == NSOnState];
  [model setCalculatesAllSizes: [allSizesButton state] == NSOnState];
  [model setAlwaysOpen: [alwaysOpenButton state] == NSOnState];
}

- (void)pictureDropped:(id)sender
{
  [model setBackgroundImagePath: [(GWViewOptionsPictureWell *)sender droppedPath]];
  [self controlsChanged: sender];
}

- (void)choosePicture:(id)sender
{
  NSOpenPanel *open = [NSOpenPanel openPanel];

  [open setCanChooseDirectories: NO];
  [open setAllowsMultipleSelection: NO];
  if ([open runModalForTypes: [NSImage imageFileTypes]] == NSOKButton)
    {
      [model setBackgroundImagePath: [open filename]];
      [self controlsChanged: sender];
    }
  else if ([model backgroundImagePath] == nil)
    {
      /* Cancelled with nothing to show: a picture background without a
       * picture would only look like white. */
      [model setBackgroundType: DSStoreBackgroundDefault];
      [self controlsFromModel];
    }
}

- (void)controlsChanged:(id)sender
{
  id view;
  BOOL dragging;

  if (loading || viewer == nil)
    return;

  [self modelFromControls];
  /* Picking a picture needs the picture from choosePicture:. */
  if (sender == backgroundPopUp && [model backgroundType] == DSStoreBackgroundPicture
      && [model backgroundImagePath] == nil)
    {
      [self controlsFromModel];
      [self choosePicture: sender];
      return;
    }

  view = [self nodeView];
  if ([view isKindOfClass: [FSNIconsView class]])
    [model applyToIconsView: view];
  else if ([view isKindOfClass: [FSNListView class]])
    [model applyToListDataSource: [(FSNListView *)view dataSource]];
  else if ([view isKindOfClass: [FSNBrowser class]])
    [model applyToColumnViewOptions: [FSNColumnViewOptions sharedOptions]];
  [self controlsFromModel];

  dragging = [[NSApp currentEvent] type] == NSLeftMouseDragged;
  [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(persist) object: nil];
  if (dragging == NO)
    [self performSelector: @selector(persist) withObject: nil afterDelay: PersistDelay];
}

- (void)flushPendingPersist
{
  [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(persist) object: nil];
}

- (void)persist
{
  id view = viewer ? [self nodeView] : nil;
  NSString *path = [[view shownNode] path];
  GWViewSettingsManager *settings;
  DSStoreInfo *info;

  if (path == nil)
    return;
  settings = [GWViewSettingsManager managerForDirectoryPath: path];
  info = [settings readSettings];
  if (info == nil)
    {
      NSLog (@"View Options: no settings for %@", path);
      return;
    }

  [model putIntoInfo: info
         forViewKind: [view isKindOfClass: [FSNBrowser class]] ? GWViewOptionsColumnView
                      : ([view isKindOfClass: [FSNListView class]] ? GWViewOptionsListView
                                                                   : GWViewOptionsIconView)];
  /* The window's own state wins for what it has: the scroll position, the
   * complete column description. */
  if ([view isKindOfClass: [FSNIconsView class]])
    [GWFolderViewOptions takeIconViewOptionsOf: view into: info];
  else if ([view isKindOfClass: [FSNListView class]])
    [GWFolderViewOptions takeListViewOptionsOf: (FSNListViewDataSource *)[(FSNListView *)view dataSource]
                                          into: info];

  if ([settings writeSettings: info] == NO)
    NSLog (@"View Options: cannot write the settings of %@", path);
  /* Finder keeps a folder's view style only for "Always open in"; without
   * it the record of an earlier choice goes, and the window no longer counts
   * its view type as chosen for the folder [O:E5]. */
  if ([model alwaysOpen] == NO)
    {
      [settings removeViewStyle];
      if ([viewer respondsToSelector: @selector(forgetChosenViewType)])
        [viewer forgetChosenViewType];
    }
}

@end
