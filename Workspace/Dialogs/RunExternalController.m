/* RunExternalController.m
 *
 * Copyright (C) 2003-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
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

#import "RunExternalController.h"
#import "CompletionField.h"
#import "AppearanceMetrics.h"
#import "Workspace.h"


@implementation RunExternalController

- (instancetype)init
{
  self = [super init];

  if (self)
    {
      CGFloat cw = METRICS_WIN_MIN_WIDTH;
      CGFloat ch = 120;

      win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, cw, ch)
                                        styleMask: NSTitledWindowMask
                                          backing: NSBackingStoreRetained
                                            defer: NO];
      [win setTitle: @""];
      [win setReleasedWhenClosed: NO];

      // Plain content view — no separator lines per AppearanceMetrics
      {
        NSView *cv = [[NSView alloc] initWithFrame: [win frame]];
        [win setContentView: cv];
        RELEASE(cv);
      }

      // Title / instruction label (System Regular 13pt)
      titleLabel = [[NSTextField alloc] initWithFrame:
                     NSMakeRect(METRICS_CONTENT_SIDE_MARGIN,
                                ch - METRICS_CONTENT_TOP_MARGIN - 16,
                                cw - 2 * METRICS_CONTENT_SIDE_MARGIN, 16)];
      [titleLabel setBackgroundColor: [NSColor windowBackgroundColor]];
      [titleLabel setBezeled: NO];
      [titleLabel setEditable: NO];
      [titleLabel setSelectable: NO];
      [titleLabel setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [titleLabel setStringValue: NSLocalizedString(@"Type the command to execute:", @"")];
      [[win contentView] addSubview: titleLabel];
      RELEASE(titleLabel);

      // Completion field in scroll view (8px below label, 22 px tall)
      {
        NSRect f = NSMakeRect(METRICS_CONTENT_SIDE_MARGIN, 56,
                              cw - 2 * METRICS_CONTENT_SIDE_MARGIN,
                              METRICS_TEXT_INPUT_FIELD_HEIGHT);
        NSScrollView *sv = [[NSScrollView alloc] initWithFrame: f];
        [sv setHasVerticalScroller: NO];
        [sv setHasHorizontalScroller: NO];
        [sv setAutoresizingMask: NSViewWidthSizable];

        cfield = [[CompletionField alloc] initWithFrame:
                   NSMakeRect(0, 0, [sv contentSize].width, [sv contentSize].height)];
        [cfield setController: self];
        [cfield setString: @""];
        [sv setDocumentView: cfield];
        RELEASE(cfield);

        [[win contentView] addSubview: sv];
        RELEASE(sv);
      }

      // Buttons (69×20, right-aligned, 10 px apart)
      {
        CGFloat bw = METRICS_BUTTON_MIN_WIDTH;
        CGFloat bh = METRICS_BUTTON_HEIGHT;
        CGFloat bx = cw - METRICS_CONTENT_SIDE_MARGIN - bw;
        CGFloat cx = bx - METRICS_BUTTON_HORIZ_INTERSPACE - bw;
        CGFloat by = METRICS_CONTENT_BOTTOM_MARGIN;

        cancelButt = [[NSButton alloc] initWithFrame:
                       NSMakeRect(cx, by, bw, bh)];
        [cancelButt setButtonType: NSMomentaryLight];
        [cancelButt setTitle: NSLocalizedString(@"Cancel", @"")];
        [cancelButt setTarget: self];
        [cancelButt setAction: @selector(cancelButtAction:)];
        [cancelButt setKeyEquivalent: @"\x1B"];
        [[win contentView] addSubview: cancelButt];
        RELEASE(cancelButt);

        okButt = [[NSButton alloc] initWithFrame:
                  NSMakeRect(bx, by, bw, bh)];
        [okButt setButtonType: NSMomentaryLight];
        [okButt setTitle: NSLocalizedString(@"Run", @"")];
        [okButt setTarget: self];
        [okButt setAction: @selector(okButtAction:)];
        [okButt setKeyEquivalent: @"\r"];
        [[win contentView] addSubview: okButt];
        RELEASE(okButt);
      }

      [win setInitialFirstResponder: cfield];
    }

  return self;
}

- (void)activate
{
  // Position every time: centered, 36 px from the top of the screen.
  NSRect sf = [[NSScreen mainScreen] frame];
  NSRect wf = [win frame];
  wf.origin.x = (sf.size.width - wf.size.width) / 2;
  wf.origin.y = sf.size.height - wf.size.height - 36;
  [win setFrame: wf display: NO];

  [super activate];
}

- (NSString *)findExecutableInPATH:(NSString *)executableName
{
  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  NSArray *paths = [pathEnv componentsSeparatedByString:@":"];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  for (NSString *dir in paths)
    {
      NSString *fullPath = [dir stringByAppendingPathComponent:executableName];
      if ([fileManager isExecutableFileAtPath:fullPath])
        {
          return fullPath;
        }
    }
  return nil;
}

- (NSArray *)parseArgumentsRespectingQuotes:(NSString *)argsString
{
  NSMutableArray *args = [NSMutableArray array];
  NSScanner *scanner = [NSScanner scannerWithString:argsString];
  [scanner setCharactersToBeSkipped:nil];
  while (![scanner isAtEnd])
    {
      NSString *arg = nil;
      [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
      if ([scanner scanString:@"'" intoString:NULL])
        {
          [scanner scanUpToString:@"'" intoString:&arg];
          [scanner scanString:@"'" intoString:NULL];
        }
      else if ([scanner scanString:@"\"" intoString:NULL])
        {
          [scanner scanUpToString:@"\"" intoString:&arg];
          [scanner scanString:@"\"" intoString:NULL];
        }
      else
        {
          [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&arg];
        }
      if ([arg length])
        {
          [args addObject:arg];
        }
    }
  return args;
}

- (IBAction)okButtAction:(id)sender
{
  NSString *str = [cfield string];
  if ([str length])
    {
      NSString *command = nil;
      NSScanner *scanner = [NSScanner scannerWithString:str];
      [scanner setCharactersToBeSkipped:nil];
      if ([scanner scanString:@"'" intoString:NULL] || [scanner scanString:@"\"" intoString:NULL])
        {
          NSString *quote = [str substringWithRange:NSMakeRange(0,1)];
          NSString *cmd = nil;
          [scanner scanUpToString:quote intoString:&cmd];
          command = cmd;
          [scanner scanString:quote intoString:NULL];
        }
      else
        {
          [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&command];
        }
      [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
      NSString *argsString = [[scanner string] substringFromIndex:[scanner scanLocation]];
      NSArray *args = [self parseArgumentsRespectingQuotes:argsString];
      NSString *checkedCommand = [self checkCommand: command];
      if (!checkedCommand)
        {
          if ([[NSFileManager defaultManager] isExecutableFileAtPath:command])
            {
              checkedCommand = command;
            }
          else
            {
              checkedCommand = [self findExecutableInPATH:command];
            }
        }
      if (checkedCommand)
        {
          if ([checkedCommand hasSuffix:@".app"])
            [[NSWorkspace sharedWorkspace] launchApplication: checkedCommand];
          else
            [NSTask launchedTaskWithLaunchPath: checkedCommand arguments: args];
          [win close];
        }
      else
        {
          [self shakeWindow];
        }
    }
}

- (void)completionFieldDidEndLine:(id)afield
{
  [super completionFieldDidEndLine:afield];
  [self okButtAction: cfield];
}

- (void)completionFieldDidCancel:(id)afield
{
  [self cancelButtAction: cfield];
}

- (void)shakeWindow
{
  NSRect originalFrame = [win frame];
  CGFloat shakeDistance = 10.0;
  int shakeCount = 2;

  for (int i = 0; i < shakeCount; i++)
    {
      NSRect leftFrame = originalFrame;
      leftFrame.origin.x -= shakeDistance;
      [win setFrameOrigin: leftFrame.origin];
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];

      NSRect rightFrame = originalFrame;
      rightFrame.origin.x += shakeDistance;
      [win setFrameOrigin: rightFrame.origin];
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];

      shakeDistance *= 0.7;
    }

  [win setFrameOrigin: originalFrame.origin];
}

@end
