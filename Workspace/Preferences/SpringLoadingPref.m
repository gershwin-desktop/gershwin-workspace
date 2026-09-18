/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "SpringLoadingPref.h"
#import "FSNSpringLoader.h"

/* The same keys and range the spring loader reads. */
static NSString *const SpringEnabledKey = @"SpringLoadedFolders";
static NSString *const SpringDelayKey = @"SpringLoadedFoldersDelay";
static const double SpringDelayMin = 0.1;
static const double SpringDelayMax = 2.0;

/* The pane area of the preferences window. */
static const CGFloat PaneW = 396.0;
static const CGFloat PaneH = 256.0;

/* Appearance metrics. */
static const CGFloat MarginTop = 15.0;
static const CGFloat MarginSide = 24.0;
static const CGFloat CheckH = 18.0;
static const CGFloat CheckIndent = 26.0;   /* box size 18 + 8 to its title */
static const CGFloat Space8 = 8.0;
static const CGFloat Space20 = 20.0;
static const CGFloat RowH = 22.0;
static const CGFloat SmallLabelH = 14.0;

static NSTextField *SpringLabel(NSString *text, CGFloat size, NSRect frame)
{
  NSTextField *label = AUTORELEASE ([[NSTextField alloc] initWithFrame: frame]);

  [label setStringValue: text];
  [label setFont: [NSFont systemFontOfSize: size]];
  [label setEditable: NO];
  [label setSelectable: NO];
  [label setBezeled: NO];
  [label setDrawsBackground: NO];

  return label;
}

@implementation SpringLoadingPref

- (void)dealloc
{
  RELEASE (prefbox);
  [super dealloc];
}

- (id)init
{
  self = [super init];

  if (self)
    {
      FSNSpringLoader *loader = [FSNSpringLoader sharedLoader];
      CGFloat y;
      CGFloat labelW;
      CGFloat sliderX;
      CGFloat sliderW;

      prefbox = [[NSBox alloc] initWithFrame: NSMakeRect(0, 0, PaneW, PaneH)];
      [prefbox setTitlePosition: NSNoTitle];
      [prefbox setBorderType: NSNoBorder];
      [prefbox setContentViewMargins: NSZeroSize];

      /* Row 1: the switch. */
      y = PaneH - MarginTop - CheckH;                               /* 223 */
      enabledCheck = AUTORELEASE ([[NSButton alloc] initWithFrame:
        NSMakeRect(MarginSide, y, PaneW - MarginSide * 2, CheckH)]);
      [enabledCheck setButtonType: NSSwitchButton];
      [enabledCheck setTitle: NSLocalizedString(@"Spring-loaded folders and windows", @"")];
      [enabledCheck setTarget: self];
      [enabledCheck setAction: @selector(enabledChanged:)];
      [[prefbox contentView] addSubview: enabledCheck];

      /* Row 2: the delay, indented under the switch's title because it only
       * matters while the switch is on. */
      y -= Space20 + RowH;                                          /* 181 */
      delayLabel = SpringLabel(NSLocalizedString(@"Delay:", @""), 13.0,
                               NSMakeRect(MarginSide + CheckIndent, y, 0, RowH));
      /* As wide as its text in whatever language, so it is never cut. */
      [delayLabel sizeToFit];
      labelW = [delayLabel frame].size.width;
      [delayLabel setFrame: NSMakeRect(MarginSide + CheckIndent, y, labelW, RowH)];
      [[prefbox contentView] addSubview: delayLabel];

      sliderX = MarginSide + CheckIndent + labelW + Space8;
      sliderW = PaneW - MarginSide - sliderX;
      delaySlider = AUTORELEASE ([[NSSlider alloc] initWithFrame:
        NSMakeRect(sliderX, y, sliderW, RowH)]);
      [delaySlider setMinValue: SpringDelayMin];
      [delaySlider setMaxValue: SpringDelayMax];
      [delaySlider setContinuous: NO];
      [delaySlider setTarget: self];
      [delaySlider setAction: @selector(delayChanged:)];
      [[prefbox contentView] addSubview: delaySlider];

      /* Under the slider's two ends. */
      y -= Space8 + SmallLabelH;                                    /* 159 */
      shortLabel = SpringLabel(NSLocalizedString(@"Short", @""), 10.0,
                               NSMakeRect(sliderX, y, sliderW / 2, SmallLabelH));
      [[prefbox contentView] addSubview: shortLabel];
      longLabel = SpringLabel(NSLocalizedString(@"Long", @""), 10.0,
                              NSMakeRect(sliderX + sliderW / 2, y, sliderW / 2, SmallLabelH));
      [longLabel setAlignment: NSRightTextAlignment];
      [[prefbox contentView] addSubview: longLabel];

      /* The loader answers with the built-in defaults when nothing is set. */
      [enabledCheck setState: [loader isEnabled] ? NSOnState : NSOffState];
      [delaySlider setDoubleValue: [loader delay]];
      [delaySlider setEnabled: [loader isEnabled]];
    }

  return self;
}

- (NSView *)prefView
{
  return prefbox;
}

- (NSString *)prefName
{
  return NSLocalizedString(@"Spring-loading", @"");
}

- (void)enabledChanged:(id)sender
{
  BOOL on = ([enabledCheck state] == NSOnState);

  [[NSUserDefaults standardUserDefaults] setBool: on forKey: SpringEnabledKey];
  [delaySlider setEnabled: on];
}

- (void)delayChanged:(id)sender
{
  [[NSUserDefaults standardUserDefaults] setDouble: [delaySlider doubleValue]
                                            forKey: SpringDelayKey];
}

@end
