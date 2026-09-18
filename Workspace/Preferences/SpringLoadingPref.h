/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef SPRING_LOADING_PREF_H
#define SPRING_LOADING_PREF_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "PrefProtocol.h"

/* Whether folders spring open under a drag, and how long the pointer has to
 * rest on one first. */
@interface SpringLoadingPref : NSObject <PrefProtocol>
{
  NSBox *prefbox;
  NSButton *enabledCheck;
  NSTextField *delayLabel;
  NSSlider *delaySlider;
  NSTextField *shortLabel;
  NSTextField *longLabel;
}

- (void)enabledChanged:(id)sender;

- (void)delayChanged:(id)sender;

@end

#endif
