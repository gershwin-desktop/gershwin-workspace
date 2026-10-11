/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Through this protocol the preview column of the column view shows the
 * contents of a file without FSNode knowing how files are rendered: the
 * application that renders them (Workspace's Look Inside) registers a
 * provider with +[FSNBrowser setPreviewProvider:].  Without one, the
 * preview column shows the file's large icon. */

#ifndef FSN_PREVIEW_PROVIDER_H
#define FSN_PREVIEW_PROVIDER_H

#import <Foundation/Foundation.h>

@class NSView;

@protocol FSNPreviewProvider <NSObject>

/* A view showing the contents of the file at path, built for frame (it is
 * not resized afterwards), or nil when the provider has nothing better to
 * show than the file's icon.  The preview column owns the view only through
 * its superview and drops it when another file is selected. */
- (NSView *)previewViewForPath:(NSString *)path frame:(NSRect)frame;

@end

#endif /* FSN_PREVIEW_PROVIDER_H */
