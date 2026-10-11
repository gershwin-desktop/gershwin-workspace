/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsideColumnPreviewProvider.h - the picture in the column view's
 * preview column, from the same preview Look Inside shows: images, text,
 * rich text and PDF pages.  Every other item gets nil, so the column shows
 * its large icon, as it does without a provider. */

#import <Foundation/Foundation.h>
#import "FSNPreviewProvider.h"
#import "GWLookInsidePreviewKind.h"

@interface GWLookInsideColumnPreviewProvider : NSObject <FSNPreviewProvider>

+ (GWLookInsideColumnPreviewProvider *)sharedProvider;

/* Whether `kind` has a picture of the content worth more than the icon. */
+ (BOOL)providesPreviewForKind:(GWLookInsidePreviewKind)kind;

@end
