/* Dialogs.m
 *
 * Copyright (C) 2003-2025 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: August 2001
 *
 * This file is part of the GNUstep Workspace application
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
#import <GNUstepBase/GNUstep.h>

#import "AppearanceMetrics.h"
#import "Dialogs.h"


@implementation GWDialogView

- (id)initWithFrame:(NSRect)frameRect useSwitch:(BOOL)aBool
{
  self = [super initWithFrame: frameRect];

  if (self)
    {
      useSwitch = aBool;
    }

  return self;
}

- (void)drawRect:(NSRect)rect
{
  /* No separator lines — AppearanceMetrics specifies:
   * "Must not use horizontal lines in dialogs or alert panels, use spacing only."
   */
}

@end

@implementation GWDialog

- (void)dealloc
{
  [validator release];
  [super dealloc];
}

- (id)initWithTitle:(NSString *)title
           editText:(NSString *)eText
        switchTitle:(NSString *)swTitle
{
  BOOL hasSwitch = (swTitle != nil);
  CGFloat cw = METRICS_WIN_MIN_WIDTH;
  CGFloat ch = hasSwitch ? 155 : 120;
  NSRect r = NSMakeRect(0, 0, cw, ch);

  self = [super initWithContentRect: r
                          styleMask: NSTitledWindowMask
                            backing: NSBackingStoreRetained
                              defer: NO];
  if (self)
    {
      NSView *cv;
      CGFloat y;

      useSwitch = hasSwitch;

      /* Plain content view — no separator lines per AppearanceMetrics */
      cv = [[NSView alloc] initWithFrame: [self frame]];
      [self setContentView: cv];
      RELEASE(cv);
      [self setTitle: @""];

      /* Center the window, 36 px from the top of the screen */
      {
        NSRect sf = [[NSScreen mainScreen] frame];
        NSRect wf = [self frame];
        wf.origin.x = (sf.size.width - wf.size.width) / 2;
        wf.origin.y = sf.size.height - wf.size.height - 36;
        [self setFrame: wf display: NO];
      }

      y = ch - METRICS_CONTENT_TOP_MARGIN;

      /* Title label: System Regular 13 pt */
      titleField = [[NSTextField alloc] initWithFrame:
                     NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, y - 16,
                                cw - 2 * METRICS_CONTENT_SIDE_MARGIN, 16)];
      [titleField setBackgroundColor: [NSColor windowBackgroundColor]];
      [titleField setBezeled: NO];
      [titleField setEditable: NO];
      [titleField setSelectable: NO];
      [titleField setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [titleField setStringValue: title];
      [cv addSubview: titleField];
      RELEASE(titleField);

      y -= 16;

      if (hasSwitch)
        {
          y -= METRICS_SPACE_8;

          switchButt = [[NSButton alloc] initWithFrame:
                         NSMakeRect(METRICS_CONTENT_SIDE_MARGIN,
                                    y - METRICS_RADIO_BUTTON_SIZE,
                                    cw - 2 * METRICS_CONTENT_SIDE_MARGIN,
                                    METRICS_RADIO_BUTTON_SIZE)];
          [switchButt setButtonType: NSSwitchButton];
          [switchButt setTitle: swTitle];
          [cv addSubview: switchButt];
          RELEASE(switchButt);

          y -= METRICS_RADIO_BUTTON_SIZE;
        }

      y -= METRICS_SPACE_16;

      /* Edit field: 22 px tall */
      editField = [[NSTextField alloc] initWithFrame:
                    NSMakeRect(METRICS_CONTENT_SIDE_MARGIN,
                               y - METRICS_TEXT_INPUT_FIELD_HEIGHT,
                               cw - 2 * METRICS_CONTENT_SIDE_MARGIN,
                               METRICS_TEXT_INPUT_FIELD_HEIGHT)];
      [editField setStringValue: eText];
      [cv addSubview: editField];
      RELEASE(editField);

      /* Buttons: 69×20, right-aligned, 10 px interspace */
      {
        CGFloat bw = METRICS_BUTTON_MIN_WIDTH;
        CGFloat bh = METRICS_BUTTON_HEIGHT;
        CGFloat okX = cw - METRICS_CONTENT_SIDE_MARGIN - bw;
        CGFloat cancelX = okX - METRICS_BUTTON_HORIZ_INTERSPACE - bw;
        CGFloat by = METRICS_CONTENT_BOTTOM_MARGIN;

        cancelButt = [[NSButton alloc] initWithFrame:
                       NSMakeRect(cancelX, by, bw, bh)];
        [cancelButt setButtonType: NSMomentaryLight];
        [cancelButt setTitle: NSLocalizedString(@"Cancel", @"")];
        [cancelButt setTarget: self];
        [cancelButt setAction: @selector(buttonAction:)];
        [cancelButt setKeyEquivalent: @"\x1B"];
        [cv addSubview: cancelButt];
        RELEASE(cancelButt);

        okButt = [[NSButton alloc] initWithFrame:
                  NSMakeRect(okX, by, bw, bh)];
        [okButt setButtonType: NSMomentaryLight];
        [okButt setTitle: NSLocalizedString(@"OK", @"")];
        [okButt setTarget: self];
        [okButt setAction: @selector(buttonAction:)];
        [okButt setKeyEquivalent: @"\r"];
        [cv addSubview: okButt];
        RELEASE(okButt);
      }

      [self setInitialFirstResponder: editField];
    }

  return self;
}

- (NSModalResponse)runModal
{
  [[NSApplication sharedApplication] runModalForWindow: self];
  return result;
}

- (NSString *)getEditFieldText
{
  return [editField stringValue];
}

- (NSControlStateValue)switchButtonState
{
  if (useSwitch)
    {
      return [switchButt state];
    }
  return NSOffState;
}

- (void)setValidator:(GWDialogValidator)aValidator
{
  if (validator != aValidator)
    {
      [validator release];
      validator = [aValidator copy];
    }
}

- (void)shakeWindow
{
  NSRect originalFrame = [self frame];
  CGFloat shakeDistance = 10.0;
  int shakeCount = 2;

  for (int i = 0; i < shakeCount; i++)
    {
      NSRect leftFrame = originalFrame;
      leftFrame.origin.x -= shakeDistance;
      [self setFrameOrigin: leftFrame.origin];
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];

      NSRect rightFrame = originalFrame;
      rightFrame.origin.x += shakeDistance;
      [self setFrameOrigin: rightFrame.origin];
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];

      shakeDistance *= 0.7;
    }

  [self setFrameOrigin: originalFrame.origin];
}

- (void)buttonAction:(id)sender
{
  if (sender == okButt)
    {
      if (validator && !validator([editField stringValue]))
        {
          [self shakeWindow];
          return;
        }
      result = NSAlertDefaultReturn;
    }
  else
    {
      result = NSAlertAlternateReturn;
    }

  [[NSApplication sharedApplication] stopModal];
  [self orderOut: nil];
}

@end
