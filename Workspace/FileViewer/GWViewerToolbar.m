/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWViewerToolbar.h"
#import "AppearanceMetrics.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "Finder.h"
#import "GWNavigationHistory.h"
#import "GWViewer.h"
#import "GWViewerToolbarModel.h"
#import "GWViewerWindow.h"
#import "Workspace.h"

/* Bordered controls that look alike next to each other; the search field
 * keeps the text field height. */
static const CGFloat kControlHeight = METRICS_BUTTON_HEIGHT;
static const CGFloat kButtonWidth = 36.0;
static const CGFloat kPullDownWidth = 44.0;
static const CGFloat kSegmentWidth = 28.0;
static const CGFloat kSearchWidth = 180.0;
static const CGFloat kSearchMinWidth = 100.0;
static const CGFloat kSearchMaxWidth = 240.0;
static const int kPathIconSize = 16;

/* GSToolbarView's own item geometry (libs-gui NSToolbarItem.m and
 * GSToolbarView.m), which the sizes above have to agree with. */
static const CGFloat kItemMinimumWidth = 60.0;
static const CGFloat kItemViewInset = 10.0;
static const CGFloat kItemLabelInset = 3.0;

/* The plain buttons: one action each, taken over from the menus. */
typedef struct {
  NSString *const *identifier;
  NSString *label;
  NSString *imageName;
  const char *action;
  BOOL sentToWindow; /* else to the application's Workspace controller */
  GWToolbarControl control;
} GWToolbarButtonSpec;

static const GWToolbarButtonSpec kButtonSpecs[] = {
  { &GWToolbarLookInsideItemIdentifier, @"Look Inside", @"GWToolbarLookInside", "lookInside:", NO,
    GWToolbarControlLookInside },
  { &GWToolbarNewFolderItemIdentifier, @"New Folder", @"GWToolbarNewFolder", "newFolder:", YES,
    GWToolbarControlNewFolder },
  { &GWToolbarDeleteItemIdentifier, @"Delete", @"GWToolbarDelete", "recycleFiles:", YES,
    GWToolbarControlDelete },
  { &GWToolbarGetInfoItemIdentifier, @"Get Info", @"GWToolbarGetInfo",
    "showAttributesInspector:", YES, GWToolbarControlGetInfo },
  { &GWToolbarEjectItemIdentifier, @"Eject", @"GWToolbarEject", "ejectVolumes:", YES,
    GWToolbarControlEject },
  { &GWToolbarConnectItemIdentifier, @"Connect", @"GWToolbarConnect", "connectToServer:", NO,
    GWToolbarControlConnect },
};

static const GWToolbarButtonSpec *buttonSpecForIdentifier(NSString *identifier)
{
  NSUInteger i;

  for (i = 0; i < sizeof(kButtonSpecs) / sizeof(kButtonSpecs[0]); i++) {
    if ([*kButtonSpecs[i].identifier isEqual:identifier])
      return &kButtonSpecs[i];
  }
  return NULL;
}

/* The order of the view mode segments, left to right. */
static const GWViewType kViewModeSegments[] = { GWViewTypeIcon, GWViewTypeList, GWViewTypeBrowser };

static NSString *const kViewModeImages[] = { @"GWToolbarIconView", @"GWToolbarListView",
                                             @"GWToolbarColumnView" };

static NSString *const kViewModeToolTips[] = { @"as Icons", @"as List", @"as Columns" };

enum { kBackSegment = 0, kForwardSegment = 1 };

/* A bordered button that drops its menu below itself on a press.  A
 * GNUstep pull-down lists its title item as an empty first entry, which a
 * toolbar menu of commands has no use for. */
@interface GWToolbarMenuButton : NSButton
@end

@implementation GWToolbarMenuButton

- (void)mouseDown:(NSEvent *)event
{
  NSRect bounds = [self bounds];
  NSPoint corner;
  NSEvent *at;

  if ([self isEnabled] == NO || [self menu] == nil)
    return;

  corner = NSMakePoint(NSMinX(bounds), [self isFlipped] ? NSMaxY(bounds) : NSMinY(bounds));
  corner = [self convertPoint:corner toView:nil];
  at = [NSEvent mouseEventWithType:NSLeftMouseDown
                          location:corner
                     modifierFlags:0
                         timestamp:[event timestamp]
                      windowNumber:[[self window] windowNumber]
                           context:nil
                       eventNumber:[event eventNumber]
                        clickCount:1
                          pressure:1.0];

  [self highlight:YES];
  [NSMenu popUpContextMenu:[self menu] withEvent:at forView:self];
  [self highlight:NO];
}

@end

/* NSToolbarItem leaves items with a view of their own unvalidated, but the
 * segments, buttons and menus here must follow the window, so every item
 * asks the toolbar's delegate. */
@interface GWViewerToolbarItem : NSToolbarItem
@end

@interface GWViewerToolbar (Validation)
- (void)validateViewerToolbarItem:(NSToolbarItem *)item;
@end

@implementation GWViewerToolbarItem

- (void)validate
{
  id delegate = [[self toolbar] delegate];

  if ([delegate respondsToSelector:@selector(validateViewerToolbarItem:)])
    [delegate validateViewerToolbarItem:self];
  else
    [super validate];
}

@end

@implementation GWViewerToolbar

- (id)initForViewer:(GWViewer *)aViewer
{
  self = [super init];
  if (self) {
    NSString *configKey = [@"NSToolbar Config " stringByAppendingString:GWViewerToolbarIdentifier];

    viewer = aViewer;
    toolbar = [[NSToolbar alloc] initWithIdentifier:GWViewerToolbarIdentifier];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    /* Icons only until the user picks another mode, which NSToolbar then
     * keeps in the saved configuration. */
    if ([[NSUserDefaults standardUserDefaults] objectForKey:configKey] == nil)
      [toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
    [toolbar setDelegate:self];
  }
  return self;
}

- (void)dealloc
{
  [self invalidate];
  [super dealloc];
}

- (NSToolbar *)toolbar
{
  return toolbar;
}

- (void)invalidate
{
  /* NSToolbar keeps every toolbar with the same identifier in a list,
   * forwards customization to them all and copies a new one's items from
   * them, so this one has to leave the list completely: off the window, no
   * delegate, last reference dropped. */
  if (toolbar != nil) {
    NSToolbar *tb = toolbar;
    NSWindow *window = [viewer win];

    toolbar = nil;
    if ([window toolbar] == tb)
      [window setToolbar:nil];
    viewer = nil;
    [tb setDelegate:nil];
    [tb release];
  }
}

/* ---------------------------------------------------------------- items */

- (NSButton *)buttonWithImage:(NSString *)imageName
{
  NSButton *button =
      [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, kButtonWidth, kControlHeight)];

  [button setButtonType:NSMomentaryPushInButton];
  [button setBezelStyle:NSTexturedRoundedBezelStyle];
  [button setImagePosition:NSImageOnly];
  [button setImage:[NSImage imageNamed:imageName]];
  [button setRefusesFirstResponder:YES];
  return [button autorelease];
}

- (GWToolbarMenuButton *)menuButtonWithImage:(NSString *)imageName
{
  GWToolbarMenuButton *button =
      [[GWToolbarMenuButton alloc] initWithFrame:NSMakeRect(0, 0, kPullDownWidth, kControlHeight)];

  [button setButtonType:NSMomentaryPushInButton];
  [button setBezelStyle:NSTexturedRoundedBezelStyle];
  [button setImagePosition:NSImageOnly];
  [button setImage:[NSImage imageNamed:imageName]];
  [button setRefusesFirstResponder:YES];
  [button setMenu:[[[NSMenu alloc] initWithTitle:@""] autorelease]];
  return [button autorelease];
}

/* GSToolbarView makes an item at least 60 points and its label wide, even
 * when only icons are shown, but shares out the flexible space by the
 * items' minimum sizes; a minimum below the width the item really gets
 * pushes the items at the right end out of the window.  So a view gets that
 * width up front. */
- (CGFloat)viewWidthForLabel:(NSString *)label minimum:(CGFloat)minimum
{
  NSDictionary *attrs =
      [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:[NSFont systemFontSize]]
                                  forKey:NSFontAttributeName];
  CGFloat labelWidth = [label sizeWithAttributes:attrs].width + 2 * kItemLabelInset;

  return ceil(MAX(minimum, MAX(kItemMinimumWidth, labelWidth) - 2 * kItemViewInset));
}

/* Look Inside and Action stand side by side as a pair, so they get one
 * width, whichever of their labels is the longer in the user's language. */
- (CGFloat)lookInsideAndActionWidth
{
  return MAX([self viewWidthForLabel:NSLocalizedString(@"Look Inside", @"")
                             minimum:kPullDownWidth],
             [self viewWidthForLabel:NSLocalizedString(@"Action", @"")
                             minimum:kPullDownWidth]);
}

- (NSToolbarItem *)itemWithIdentifier:(NSString *)identifier
                                label:(NSString *)label
                                 view:(NSView *)view
{
  NSToolbarItem *item = [[GWViewerToolbarItem alloc] initWithItemIdentifier:identifier];
  NSSize size = [view frame].size;

  size.width = [self viewWidthForLabel:label minimum:size.width];
  [view setFrameSize:size];

  [item setLabel:label];
  [item setPaletteLabel:label];
  [item setToolTip:label];
  [item setView:view];
  [item setMinSize:size];
  [item setMaxSize:size];
  return [item autorelease];
}

- (NSToolbarItem *)backForwardItem
{
  NSSegmentedControl *control = [[[NSSegmentedControl alloc]
      initWithFrame:NSMakeRect(0, 0, kSegmentWidth * 2, kControlHeight)] autorelease];
  NSToolbarItem *item;

  [control setSegmentCount:2];
  [[control cell] setTrackingMode:NSSegmentSwitchTrackingMomentary];
  [control setImage:[NSImage imageNamed:@"GWToolbarBack"] forSegment:kBackSegment];
  [control setImage:[NSImage imageNamed:@"GWToolbarForward"] forSegment:kForwardSegment];
  [control setWidth:kSegmentWidth forSegment:kBackSegment];
  [control setWidth:kSegmentWidth forSegment:kForwardSegment];
  [[control cell] setToolTip:NSLocalizedString(@"Back", @"") forSegment:kBackSegment];
  [[control cell] setToolTip:NSLocalizedString(@"Forward", @"") forSegment:kForwardSegment];
  [control setTarget:self];
  [control setAction:@selector(backOrForward:)];

  item = [self itemWithIdentifier:GWToolbarBackForwardItemIdentifier
                            label:NSLocalizedString(@"Back", @"")
                             view:control];
  [item setPaletteLabel:NSLocalizedString(@"Back/Forward", @"")];
  return item;
}

- (NSToolbarItem *)viewModeItem
{
  NSUInteger count = sizeof(kViewModeSegments) / sizeof(kViewModeSegments[0]);
  NSSegmentedControl *control = [[[NSSegmentedControl alloc]
      initWithFrame:NSMakeRect(0, 0, kSegmentWidth * count, kControlHeight)] autorelease];
  NSUInteger i;

  [control setSegmentCount:count];
  [[control cell] setTrackingMode:NSSegmentSwitchTrackingSelectOne];
  for (i = 0; i < count; i++) {
    [control setImage:[NSImage imageNamed:kViewModeImages[i]] forSegment:i];
    [control setWidth:kSegmentWidth forSegment:i];
    [[control cell] setToolTip:NSLocalizedString(kViewModeToolTips[i], @"") forSegment:i];
  }
  [control setTarget:self];
  [control setAction:@selector(changeViewMode:)];

  return [self itemWithIdentifier:GWToolbarViewModeItemIdentifier
                            label:NSLocalizedString(@"View", @"")
                             view:control];
}

- (NSToolbarItem *)actionItem
{
  GWToolbarMenuButton *button = [self menuButtonWithImage:@"GWToolbarAction"];
  NSMenu *menu = [button menu];
  NSMenuItem *menuItem;

  [button setFrameSize:NSMakeSize([self lookInsideAndActionWidth], kControlHeight)];

  /* The same actions as the menu bar, sent along the responder chain so
   * they reach the window or Workspace exactly as the menu items do and
   * are enabled by the same validation. */
#define ADD_ACTION(title, sel)                                                                     \
  menuItem = (NSMenuItem *)[menu addItemWithTitle:NSLocalizedString(title, @"")                    \
                                           action:@selector(sel)                                   \
                                    keyEquivalent:@""];                                            \
  [menuItem setTarget:nil]

  ADD_ACTION(@"New Folder", newFolder:);
  ADD_ACTION(@"Open", openSelection:);
  [menu addItem:[NSMenuItem separatorItem]];
  ADD_ACTION(@"Move to Trash", recycleFiles:);
  [menu addItem:[NSMenuItem separatorItem]];
  ADD_ACTION(@"Get Info", showAttributesInspector:);
  ADD_ACTION(@"Compress", compressFiles:);
  ADD_ACTION(@"Duplicate", duplicateFiles:);
  ADD_ACTION(@"Make Alias", makeAliasFiles:);
  ADD_ACTION(@"Look Inside", lookInside:);
  [menu addItem:[NSMenuItem separatorItem]];
  ADD_ACTION(@"Copy", copy:);
  [menu addItem:[NSMenuItem separatorItem]];
  ADD_ACTION(@"Clean Up", cleanUp:);
  ADD_ACTION(@"Show View Options", showViewOptions:);
#undef ADD_ACTION

  return [self itemWithIdentifier:GWToolbarActionItemIdentifier
                            label:NSLocalizedString(@"Action", @"")
                             view:button];
}

- (NSToolbarItem *)pathItem
{
  return [self itemWithIdentifier:GWToolbarPathItemIdentifier
                            label:NSLocalizedString(@"Path", @"")
                             view:[self menuButtonWithImage:@"GWToolbarPath"]];
}

- (NSToolbarItem *)searchItem
{
  NSSearchField *field = [[[NSSearchField alloc]
      initWithFrame:NSMakeRect(0, 0, kSearchWidth, METRICS_TEXT_INPUT_FIELD_HEIGHT)] autorelease];
  NSToolbarItem *item;

  /* The search tool walks the whole folder tree, so it starts on Return
   * rather than on every key typed. */
  [[field cell] setSendsWholeSearchString:YES];
  [[field cell] setPlaceholderString:NSLocalizedString(@"Search", @"")];
  [field setTarget:self];
  [field setAction:@selector(search:)];

  item = [self itemWithIdentifier:GWToolbarSearchItemIdentifier
                            label:NSLocalizedString(@"Search", @"")
                             view:field];
  /* Grows with the window, as the only item that is not a fixed button. */
  [item setMinSize:NSMakeSize(kSearchMinWidth, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
  [item setMaxSize:NSMakeSize(kSearchMaxWidth, METRICS_TEXT_INPUT_FIELD_HEIGHT)];
  return item;
}

- (NSToolbarItem *)buttonItemForSpec:(const GWToolbarButtonSpec *)spec
{
  NSButton *button = [self buttonWithImage:spec->imageName];

  if (*spec->identifier == GWToolbarLookInsideItemIdentifier)
    [button setFrameSize:NSMakeSize([self lookInsideAndActionWidth], kControlHeight)];
  [button setAction:sel_registerName(spec->action)];
  /* The window forwards to its viewer as it does for the menus; the
   * application-wide actions go to Workspace. */
  [button setTarget:spec->sentToWindow ? (id)[viewer win] : (id)[Workspace gworkspace]];

  return [self itemWithIdentifier:*spec->identifier
                            label:NSLocalizedString(spec->label, @"")
                             view:button];
}

/* ------------------------------------------------------ NSToolbar delegate */

- (NSToolbarItem *)toolbar:(NSToolbar *)tb
        itemForItemIdentifier:(NSString *)identifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
  const GWToolbarButtonSpec *spec;

  if ([identifier isEqual:GWToolbarBackForwardItemIdentifier])
    return [self backForwardItem];
  if ([identifier isEqual:GWToolbarViewModeItemIdentifier])
    return [self viewModeItem];
  if ([identifier isEqual:GWToolbarActionItemIdentifier])
    return [self actionItem];
  if ([identifier isEqual:GWToolbarPathItemIdentifier])
    return [self pathItem];
  if ([identifier isEqual:GWToolbarSearchItemIdentifier])
    return [self searchItem];

  spec = buttonSpecForIdentifier(identifier);
  if (spec != NULL)
    return [self buttonItemForSpec:spec];

  return nil;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)tb
{
  return [GWViewerToolbarModel defaultItemIdentifiers];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)tb
{
  return [GWViewerToolbarModel allowedItemIdentifiers];
}

/* ---------------------------------------------------------------- actions */

- (void)backOrForward:(id)sender
{
  NSInteger segment = [sender selectedSegment];

  /* GNUstep's segmented cell keeps a momentary segment selected after the
   * click, which would leave it drawn pressed. */
  [sender setSelected:NO forSegment:kBackSegment];
  [sender setSelected:NO forSegment:kForwardSegment];

  if (segment == kBackSegment)
    [viewer goBackwardInHistory];
  else if (segment == kForwardSegment)
    [viewer goForwardInHistory];
}

- (void)changeViewMode:(id)sender
{
  NSInteger segment = [sender selectedSegment];
  NSUInteger count = sizeof(kViewModeSegments) / sizeof(kViewModeSegments[0]);

  if (segment < 0 || (NSUInteger)segment >= count)
    return;
  /* Rebuilding the view for the mode already shown would only lose the
   * scroll position. */
  if (kViewModeSegments[segment] != [viewer viewType])
    [viewer showViewType:kViewModeSegments[segment]];
}

- (void)search:(id)sender
{
  NSString *text = [sender stringValue];
  FSNode *folder = [viewer shownFolderNode];

  if ([text length] == 0 || folder == nil)
    return;
  [[Finder finder] findItemsNamed:text inFolder:[folder path]];
}

- (void)openPathMenuItem:(id)sender
{
  FSNode *node = [FSNode nodeWithPath:[sender representedObject]];

  if ([node isValid])
    [viewer navigateToNode:node];
}

@end

@implementation GWViewerToolbar (Validation)

- (GWViewerToolbarState)windowState
{
  GWViewerToolbarState state;
  GWNavigationHistory *history = [viewer navigationHistory];
  FSNode *folder = [viewer shownFolderNode];
  NSArray *selection = [viewer lastSelection];
  Workspace *gw = [Workspace gworkspace];
  NSUInteger i;

  memset(&state, 0, sizeof(state));
  state.canGoBack = [history canGoBack];
  state.canGoForward = [history canGoForward];
  state.showsTrash = [[folder path] isEqual:[gw trashPath]];
  state.folderWritable = [folder isWritable];
  /* With nothing selected the viewer reports the shown folder itself. */
  state.hasSelection = ([selection count] > 0) &&
                       !([selection count] == 1 && [[selection objectAtIndex:0] isEqual:folder]);

  for (i = 0; state.hasSelection && i < [selection count]; i++) {
    FSNode *node = [selection objectAtIndex:i];

    if ([node isMountPoint] && ([gw isRootFilesystem:[node path]] == NO)) {
      state.selectionHasVolume = YES;
      break;
    }
  }
  return state;
}

/* Rebuilt only when the window shows another folder, so an open menu is
 * not replaced under the pointer. */
- (void)updatePathMenu:(NSButton *)button
{
  NSString *folderPath = [[viewer shownFolderNode] path];
  NSMenu *menu = [button menu];
  FSNodeRep *rep = [FSNodeRep sharedInstance];
  NSString *path;

  /* The first entry is the shown folder itself. */
  if (folderPath == nil ||
      ([menu numberOfItems] > 0 && [[[menu itemAtIndex:0] representedObject] isEqual:folderPath]))
    return;

  while ([menu numberOfItems] > 0)
    [menu removeItemAtIndex:0];

  path = folderPath;
  while (path != nil) {
    FSNode *node = [FSNode nodeWithPath:path];
    NSString *parent = [path stringByDeletingLastPathComponent];
    NSString *title = [viewer titleForNode:node];
    NSMenuItem *menuItem;

    menuItem = (NSMenuItem *)[menu addItemWithTitle:title
                                             action:@selector(openPathMenuItem:)
                                      keyEquivalent:@""];
    [menuItem setImage:[rep iconOfSize:kPathIconSize forNode:node]];
    [menuItem setRepresentedObject:path];
    [menuItem setTarget:self];

    path = [parent isEqual:path] ? nil : parent;
  }
}

- (void)validateViewerToolbarItem:(NSToolbarItem *)item
{
  NSString *identifier = [item itemIdentifier];
  id view = [item view];
  GWViewerToolbarState state;
  const GWToolbarButtonSpec *spec;

  if (viewer == nil)
    return;

  state = [self windowState];

  if ([identifier isEqual:GWToolbarBackForwardItemIdentifier]) {
    [view setEnabled:[GWViewerToolbarModel isControl:GWToolbarControlBack enabledInState:state]
          forSegment:kBackSegment];
    [view setEnabled:[GWViewerToolbarModel isControl:GWToolbarControlForward enabledInState:state]
          forSegment:kForwardSegment];
  }
  else if ([identifier isEqual:GWToolbarViewModeItemIdentifier]) {
    NSUInteger count = sizeof(kViewModeSegments) / sizeof(kViewModeSegments[0]);
    NSUInteger i;

    for (i = 0; i < count; i++) {
      if (kViewModeSegments[i] == [viewer viewType] && [view selectedSegment] != (NSInteger)i)
        [view setSelectedSegment:i];
    }
  }
  else if ([identifier isEqual:GWToolbarPathItemIdentifier]) {
    [self updatePathMenu:view];
  }
  else if ((spec = buttonSpecForIdentifier(identifier)) != NULL) {
    [view setEnabled:[GWViewerToolbarModel isControl:spec->control enabledInState:state]];
  }
}

@end
