/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWLookInsideColumnPreviewProvider.h"
#import "GWLookInsidePreviewKind.h"
#import "GWLookInsidePreviewView.h"
#import "FSNode.h"

@implementation GWLookInsideColumnPreviewProvider

+ (GWLookInsideColumnPreviewProvider *)sharedProvider
{
  static GWLookInsideColumnPreviewProvider *shared = nil;

  if (shared == nil)
    {
      shared = [self new];
    }
  return shared;
}

+ (BOOL)providesPreviewForKind:(GWLookInsidePreviewKind)kind
{
  switch (kind)
    {
    case GWLookInsidePreviewKindImage:
    case GWLookInsidePreviewKindPlainText:
    case GWLookInsidePreviewKindRichText:
    case GWLookInsidePreviewKindPDF:
      return YES;
    default:
      return NO;
    }
}

- (NSView *)previewViewForPath:(NSString *)path frame:(NSRect)frame
{
  FSNode *node = [FSNode nodeWithPath: path];
  GWLookInsidePreviewKind kind =
    GWLookInsidePreviewKindForPath(path, [GWLookInsidePreviewView imageExtensions],
                                   [node isPackage]);
  GWLookInsidePreviewView *view;

  if (![[self class] providesPreviewForKind: kind])
    {
      return nil;
    }
  view = [[GWLookInsidePreviewView alloc] initWithFrame: frame
                                                  style: GWLookInsidePreviewStyleCompact];
  [view showPath: path];
  return AUTORELEASE(view);
}

@end
