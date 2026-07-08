/* FSNMetadataProvider.h
 *
 * Protocol through which FSNode obtains Finder-style file metadata (label
 * colour, invisibility, custom icon, icon position) without depending on any
 * concrete metadata implementation.  The Workspace application registers a
 * concrete provider on FSNodeRep at startup; when no provider is set, FSNode
 * degrades gracefully (no labels/custom icons, nothing hidden by metadata).
 *
 * This keeps the generic file-representation framework decoupled from the
 * macOS-interop metadata stack (AppleDouble / xattr / .DS_Store).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_METADATA_PROVIDER_H
#define FSN_METADATA_PROVIDER_H

#import <Foundation/Foundation.h>

@class NSImage;
@class NSColor;

@protocol FSNMetadataProvider <NSObject>

/* Finder label colour for the file, or nil when it has no label.  Returning
 * the colour (rather than the raw 0..7 number) keeps the label->colour
 * mapping out of FSNode. */
- (NSColor *)labelColorForPath:(NSString *)path;

/* YES if the file is marked invisible in its Finder metadata. */
- (BOOL)isInvisibleAtPath:(NSString *)path;

/* Custom icon image for the file, or nil if it has none. */
- (NSImage *)customIconForPath:(NSString *)path;

/* Stored icon position as DS_Store/fdLocation top-left CENTER coordinates,
 * or (-1, -1) when no position is stored. */
- (NSPoint)iconPositionForPath:(NSString *)path;

/* Drop any cached metadata (called by FSNode on directory refresh so the
 * next read reflects external changes). */
- (void)invalidateCaches;

@end

#endif /* FSN_METADATA_PROVIDER_H */
