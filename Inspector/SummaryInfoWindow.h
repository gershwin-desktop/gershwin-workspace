/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class SummaryInfoModel;

/* One Info window with the totals of a multiple selection.  Built in code. */
@interface SummaryInfoWindow : NSObject
{
  NSPanel *_panel;
  SummaryInfoModel *_model;
  NSImageView *_iconView;
  NSTextField *_titleField;
  NSTextField *_sizeValue;
  NSTextField *_itemsValue;
  NSTextField *_kindsValue;
  NSTextField *_labelValue;
  NSTextField *_lockedValue;
}

- (void)showForPaths:(NSArray *)paths;
- (NSWindow *)window;

@end
