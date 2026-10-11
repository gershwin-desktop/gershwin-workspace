/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FinderInfoPanel.h"
#import "FinderInfoModel.h"
#import "FSNodeRep.h"
#import "AppearanceMetrics.h"

#define FI_(s) NSLocalizedStringFromTableInBundle(s, @"FinderInfo", \
  [NSBundle bundleForClass: [FinderInfoPanel class]], @"")

#define ICON_SIDE 48.0
#define CAPTION_WIDTH 92.0
#define FIELD_HEIGHT METRICS_TEXT_INPUT_FIELD_HEIGHT
#define ROW_GAP METRICS_SPACE_8

/* Resizes with its pane: the panel owns the geometry. */
@interface FinderInfoView : NSView
{
  FinderInfoPanel *_panel;   /* not retained: the panel owns the view */
}
- (void)setPanel:(FinderInfoPanel *)panel;
@end

@implementation FinderInfoView
- (void)setPanel:(FinderInfoPanel *)panel { _panel = panel; }
/* libs-gui's -setFrame: does not go through -setFrameSize:, and a box
 * resizes its content view with either one. */
- (void)setFrameSize:(NSSize)size
{
  [super setFrameSize: size];
  [_panel layoutInSize: size];
}
- (void)setFrame:(NSRect)frame
{
  [super setFrame: frame];
  [_panel layoutInSize: frame.size];
}
@end

@implementation FinderInfoPanel

- (NSTextField *)captionWithKey:(NSString *)key
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, CAPTION_WIDTH, 17)];

  [f setFont: [NSFont systemFontOfSize: 12]];
  [f setAlignment: NSLeftTextAlignment];
  [f setBezeled: NO];
  [f setDrawsBackground: NO];
  [f setEditable: NO];
  [f setSelectable: NO];
  [f setStringValue: FI_(key)];
  [_view addSubview: f];
  return [f autorelease];
}

- (NSButton *)checkboxWithKey:(NSString *)key
{
  NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, METRICS_RADIO_BUTTON_LINE_SPACING)];

  [b setButtonType: NSSwitchButton];
  [b setTitle: FI_(key)];
  [b setFont: [NSFont systemFontOfSize: 12]];
  [b setTarget: self];
  [b setAction: @selector(controlChanged:)];
  [_view addSubview: b];
  return [b autorelease];
}

- (NSButton *)pushButtonWithKey:(NSString *)key action:(SEL)action
{
  NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 100, METRICS_BUTTON_HEIGHT)];

  [b setButtonType: NSMomentaryPushInButton];
  [b setBezelStyle: NSRoundedBezelStyle];
  [b setTitle: FI_(key)];
  [b setFont: [NSFont systemFontOfSize: 12]];
  [b setTarget: self];
  [b setAction: action];
  [_view addSubview: b];
  return [b autorelease];
}

- (NSTextField *)codeField
{
  NSTextField *f = [[NSTextField alloc] initWithFrame: NSMakeRect(0, 0, 80, FIELD_HEIGHT)];

  [f setFont: [NSFont systemFontOfSize: 12]];
  [f setDelegate: self];
  [_view addSubview: f];
  return [f autorelease];
}

- (instancetype)initForInspector:(id)insp
{
  self = [super init];
  if (self) {
    FinderInfoView *v = [[FinderInfoView alloc] initWithFrame: NSMakeRect(0, 0, 272, 400)];
    NSArray *labelKeys = [NSArray arrayWithObjects: @"None", @"Red", @"Orange", @"Yellow",
                                  @"Green", @"Blue", @"Purple", @"Grey", nil];
    NSUInteger i;

    _inspector = insp;
    _view = v;
    [v setPanel: self];
    [v setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    _iconWell = [[NSImageView alloc] initWithFrame: NSMakeRect(0, 0, ICON_SIDE, ICON_SIDE)];
    [_iconWell setImageFrameStyle: NSImageFrameNone];
    [_iconWell setImageScaling: NSScaleProportionally];
    [_iconWell setEditable: YES];
    [_iconWell setTarget: self];
    [_iconWell setAction: @selector(iconDropped:)];
    [_view addSubview: _iconWell];
    [_iconWell release];

    _nameField = [[NSTextField alloc] initWithFrame: NSZeroRect];
    [_nameField setFont: [NSFont boldSystemFontOfSize: 13]];
    [_nameField setBezeled: NO];
    [_nameField setDrawsBackground: NO];
    [_nameField setEditable: NO];
    [_nameField setSelectable: NO];
    [[_nameField cell] setLineBreakMode: NSLineBreakByTruncatingMiddle];
    [_view addSubview: _nameField];
    [_nameField release];

    _noticeField = [[NSTextField alloc] initWithFrame: NSZeroRect];
    [_noticeField setFont: [NSFont systemFontOfSize: 14]];
    [_noticeField setTextColor: [NSColor grayColor]];
    [_noticeField setAlignment: NSCenterTextAlignment];
    [_noticeField setBezeled: NO];
    [_noticeField setDrawsBackground: NO];
    [_noticeField setEditable: NO];
    [_noticeField setSelectable: NO];
    [_noticeField setStringValue: FI_(@"Select a single item")];
    [_view addSubview: _noticeField];
    [_noticeField release];

    _hideExtensionButton = [self checkboxWithKey: @"Hide extension"];
    _lockedButton = [self checkboxWithKey: @"Locked"];
    _nameLockedButton = [self checkboxWithKey: @"Name locked"];
    _stationeryButton = [self checkboxWithKey: @"Stationery pad"];
    _invisibleButton = [self checkboxWithKey: @"Invisible"];

    _labelCaption = [self captionWithKey: @"Label:"];
    _labelPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 120, FIELD_HEIGHT)
                                             pullsDown: NO];
    for (i = 0; i < [labelKeys count]; i++)
      [_labelPopUp addItemWithTitle: FI_([labelKeys objectAtIndex: i])];
    [_labelPopUp setTarget: self];
    [_labelPopUp setAction: @selector(controlChanged:)];
    [_view addSubview: _labelPopUp];
    [_labelPopUp release];

    _typeCaption = [self captionWithKey: @"Type code:"];
    _typeField = [self codeField];
    _creatorCaption = [self captionWithKey: @"Creator code:"];
    _creatorField = [self codeField];

    _iconCaption = [self captionWithKey: @"Custom icon:"];
    _pasteIconButton = [self pushButtonWithKey: @"Paste Icon" action: @selector(pasteIcon:)];
    _clearIconButton = [self pushButtonWithKey: @"Clear Icon" action: @selector(clearIcon:)];

    _commentCaption = [self captionWithKey: @"Comment:"];
    _commentScroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 100, 60)];
    [_commentScroll setHasVerticalScroller: YES];
    [_commentScroll setBorderType: NSBezelBorder];
    /* An unconfigured NSTextView grows without bound and steals clicks. */
    _commentView = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 100, 60)];
    [_commentView setMinSize: NSMakeSize(0, 0)];
    [_commentView setMaxSize: NSMakeSize(1e7, 1e7)];
    [_commentView setVerticallyResizable: YES];
    [_commentView setHorizontallyResizable: NO];
    [_commentView setAutoresizingMask: NSViewWidthSizable];
    [[_commentView textContainer] setWidthTracksTextView: YES];
    [_commentView setFont: [NSFont systemFontOfSize: 12]];
    [_commentView setDelegate: self];
    [_commentScroll setDocumentView: _commentView];
    [_commentView release];
    [_view addSubview: _commentScroll];
    [_commentScroll release];

    _revertButton = [self pushButtonWithKey: @"Revert" action: @selector(revert:)];
    _applyButton = [self pushButtonWithKey: @"Apply" action: @selector(apply:)];
    [_applyButton setKeyEquivalent: @"\r"];

    [self showModel: nil];
    [self layoutInSize: [_view frame].size];
  }
  return self;
}

- (void)dealloc
{
  [_view release];
  [_currentPath release];
  [_model release];
  [super dealloc];
}

- (NSView *)inspView { return _view; }

- (NSString *)winname { return FI_(@"Finder Info Inspector"); }

#pragma mark - Geometry

/* Rows are laid out from the top; AppKit's origin is bottom left. */
- (void)layoutInSize:(NSSize)size
{
  CGFloat m = METRICS_SPACE_12;
  CGFloat w = size.width - 2 * m;
  CGFloat y = size.height - m;   /* top edge of the next row */
  CGFloat fieldX = m + CAPTION_WIDTH;
  CGFloat bw = floor((w - METRICS_BUTTON_HORIZ_INTERSPACE) / 2);
  NSArray *checks = [NSArray arrayWithObjects: _hideExtensionButton, _lockedButton,
                                  _nameLockedButton, _stationeryButton, _invisibleButton, nil];
  NSEnumerator *e;
  NSButton *b;

  [_noticeField setFrame: NSMakeRect(m, size.height / 2 - 20, w, 40)];

  [_iconWell setFrame: NSMakeRect(m, y - ICON_SIDE, ICON_SIDE, ICON_SIDE)];
  [_nameField setFrame: NSMakeRect(m + ICON_SIDE + ROW_GAP, y - ICON_SIDE / 2 - 9,
                                   w - ICON_SIDE - ROW_GAP, 18)];
  y -= ICON_SIDE + METRICS_SPACE_16;

  e = [checks objectEnumerator];
  while ((b = [e nextObject]) != nil) {
    [b setFrame: NSMakeRect(m, y - METRICS_RADIO_BUTTON_LINE_SPACING, w,
                            METRICS_RADIO_BUTTON_LINE_SPACING)];
    y -= METRICS_RADIO_BUTTON_LINE_SPACING;
  }
  y -= ROW_GAP;

  [_labelCaption setFrame: NSMakeRect(m, y - FIELD_HEIGHT + 3, CAPTION_WIDTH, 17)];
  [_labelPopUp setFrame: NSMakeRect(fieldX, y - FIELD_HEIGHT, MIN(140, w - CAPTION_WIDTH), FIELD_HEIGHT)];
  y -= FIELD_HEIGHT + ROW_GAP;

  [_typeCaption setFrame: NSMakeRect(m, y - FIELD_HEIGHT + 3, CAPTION_WIDTH, 17)];
  [_typeField setFrame: NSMakeRect(fieldX, y - FIELD_HEIGHT, 80, FIELD_HEIGHT)];
  y -= FIELD_HEIGHT + ROW_GAP;
  [_creatorCaption setFrame: NSMakeRect(m, y - FIELD_HEIGHT + 3, CAPTION_WIDTH, 17)];
  [_creatorField setFrame: NSMakeRect(fieldX, y - FIELD_HEIGHT, 80, FIELD_HEIGHT)];
  y -= FIELD_HEIGHT + ROW_GAP;

  [_iconCaption setFrame: NSMakeRect(m, y - 17, w, 17)];
  y -= 17 + 4;
  [_pasteIconButton setFrame: NSMakeRect(m, y - METRICS_BUTTON_HEIGHT, bw, METRICS_BUTTON_HEIGHT)];
  [_clearIconButton setFrame: NSMakeRect(m + bw + METRICS_BUTTON_HORIZ_INTERSPACE,
                                         y - METRICS_BUTTON_HEIGHT, bw, METRICS_BUTTON_HEIGHT)];
  y -= METRICS_BUTTON_HEIGHT + ROW_GAP;

  /* Apply and Revert sit on the bottom edge; the comment takes what is left. */
  [_applyButton setFrame: NSMakeRect(m + bw + METRICS_BUTTON_HORIZ_INTERSPACE, m, bw,
                                     METRICS_BUTTON_HEIGHT)];
  [_revertButton setFrame: NSMakeRect(m, m, bw, METRICS_BUTTON_HEIGHT)];

  [_commentCaption setFrame: NSMakeRect(m, y - 17, w, 17)];
  y -= 17 + 4;
  {
    CGFloat bottom = m + METRICS_BUTTON_HEIGHT + METRICS_BUTTON_VERT_INTERSPACE;

    [_commentScroll setFrame: NSMakeRect(m, bottom, w, MAX(30.0, y - bottom))];
  }
}

#pragma mark - Model <-> controls

- (NSArray *)detailControls
{
  return [NSArray arrayWithObjects: _iconWell, _nameField, _hideExtensionButton, _lockedButton,
                  _nameLockedButton, _stationeryButton, _invisibleButton, _labelCaption,
                  _labelPopUp, _typeCaption, _typeField, _creatorCaption, _creatorField,
                  _iconCaption, _pasteIconButton, _clearIconButton, _commentCaption,
                  _commentScroll, _revertButton, _applyButton, nil];
}

- (void)setDirty:(BOOL)dirty
{
  _dirty = dirty;
  [_applyButton setEnabled: dirty && _model != nil];
  [_revertButton setEnabled: dirty && _model != nil];
}

- (void)showModel:(FinderInfoModel *)model
{
  BOOL single = (model != nil);
  BOOL file = single && ![model isDirectory];
  NSEnumerator *e = [[self detailControls] objectEnumerator];
  NSView *v;

  while ((v = [e nextObject]) != nil)
    [v setHidden: !single];
  [_noticeField setHidden: single];

  [_model release];
  _model = [model retain];
  if (single) {
    FSNode *node = [FSNode nodeWithPath: [model path]];
    NSImage *icon = nil;

    if ([model customIconICNS] != nil)
      icon = [[[NSImage alloc] initWithData: [model customIconICNS]] autorelease];
    if (icon == nil)
      icon = [[FSNodeRep sharedInstance] iconOfSize: (int)ICON_SIDE forNode: node];
    [_iconWell setImage: icon];
    [_nameField setStringValue: [node name]];

    [_hideExtensionButton setState: [model hideExtension] ? NSOnState : NSOffState];
    [_lockedButton setState: [model locked] ? NSOnState : NSOffState];
    [_nameLockedButton setState: [model nameLocked] ? NSOnState : NSOffState];
    [_stationeryButton setState: [model stationery] ? NSOnState : NSOffState];
    [_invisibleButton setState: [model invisible] ? NSOnState : NSOffState];
    [_labelPopUp selectItemAtIndex: MIN(MAX([model labelNumber], 0), 7)];
    [_typeField setStringValue: [model typeCode]];
    [_creatorField setStringValue: [model creatorCode]];
    [_commentView setString: [model comment] ? [model comment] : @""];

    /* Why disabled: no unprivileged lock on this system; folders keep a
     * window rectangle where files keep type and creator. */
    [_lockedButton setEnabled: [FinderInfoModel supportsLocking]];
    [_stationeryButton setEnabled: file];
    [_typeField setEnabled: file];
    [_creatorField setEnabled: file];
    [_iconWell setEditable: file];
    [_pasteIconButton setEnabled: file];
    [_clearIconButton setEnabled: file];
  }
  [self setDirty: NO];
}

- (void)pullControlsIntoModel
{
  [_model setHideExtension: [_hideExtensionButton state] == NSOnState];
  [_model setLocked: [_lockedButton state] == NSOnState];
  [_model setNameLocked: [_nameLockedButton state] == NSOnState];
  [_model setInvisible: [_invisibleButton state] == NSOnState];
  [_model setLabelNumber: [_labelPopUp indexOfSelectedItem]];
  [_model setComment: [_commentView string]];
  if (![_model isDirectory]) {
    [_model setStationery: [_stationeryButton state] == NSOnState];
    [_model setTypeCode: [_typeField stringValue]];
    [_model setCreatorCode: [_creatorField stringValue]];
  }
}

- (void)showError:(NSError *)error
{
  NSString *reason = [error localizedDescription];

  if (reason == nil)
    reason = FI_(@"Unknown error");
  NSRunAlertPanel(FI_(@"Could not change Finder Info"), @"%@", FI_(@"OK"), nil, nil, reason);
}

#pragma mark - Actions

- (void)controlChanged:(id)sender { [self setDirty: YES]; }
- (void)controlTextDidChange:(NSNotification *)note { [self setDirty: YES]; }
- (void)textDidChange:(NSNotification *)note { [self setDirty: YES]; }

- (void)setIconFromImage:(NSImage *)image
{
  if (image == nil || [_model setCustomIconFromImage: image] == NO) {
    [self showError: [NSError errorWithDomain: GWFinderInfoErrorDomain code: 2
                                     userInfo: [NSDictionary dictionaryWithObject:
                                                  FI_(@"The image could not be used as an icon.")
                                                                           forKey: NSLocalizedDescriptionKey]]];
    return;
  }
  [_iconWell setImage: image];
  [self setDirty: YES];
}

- (void)iconDropped:(id)sender { [self setIconFromImage: [_iconWell image]]; }

- (void)pasteIcon:(id)sender
{
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSImage *image = nil;

  if ([NSImage canInitWithPasteboard: pb])
    image = [[[NSImage alloc] initWithPasteboard: pb] autorelease];
  [self setIconFromImage: image];
}

- (void)clearIcon:(id)sender
{
  FSNode *node = [FSNode nodeWithPath: [_model path]];

  [_model clearCustomIcon];
  [_iconWell setImage: [[FSNodeRep sharedInstance] iconOfSize: (int)ICON_SIDE forNode: node]];
  [self setDirty: YES];
}

- (void)revert:(id)sender
{
  [self showModel: [FinderInfoModel modelForPath: _currentPath]];
}

- (void)apply:(id)sender
{
  NSError *error = nil;

  [self pullControlsIntoModel];
  if ([_model write: &error] == NO) {
    [self showError: error];
    /* Show what is really on disk, not what the failed write left half done. */
    [self showModel: [FinderInfoModel modelForPath: _currentPath]];
    return;
  }
  [self showModel: [FinderInfoModel modelForPath: _currentPath]];
}

#pragma mark - Inspector protocol

- (void)activateForPaths:(NSArray *)paths
{
  if (_currentPath != nil) {
    [_inspector removeWatcherForPath: _currentPath];
    DESTROY(_currentPath);
  }
  if ([paths count] != 1) {
    [self showModel: nil];
    return;
  }
  _currentPath = [[paths objectAtIndex: 0] copy];
  [_inspector addWatcherForPath: _currentPath];
  [self showModel: [FinderInfoModel modelForPath: _currentPath]];
}

- (void)watchedPathDidChange:(NSDictionary *)info
{
  NSString *path = [info objectForKey: @"path"];

  if (_currentPath == nil || [_currentPath isEqual: path] == NO)
    return;
  if ([[info objectForKey: @"event"] isEqual: @"GWWatchedPathDeleted"]) {
    [_inspector removeWatcherForPath: _currentPath];
    DESTROY(_currentPath);
    [self showModel: nil];
  } else if (_dirty == NO) {
    /* Unsaved edits win over a refresh. */
    [self showModel: [FinderInfoModel modelForPath: _currentPath]];
  }
}

@end
