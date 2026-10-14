/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>
#import "FSNIconPreview.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "GWThumbnailStore.h"
#import "GWThumbnailImage.h"
#import "GWThumbnailPNG.h"
#include <math.h>
#import "FSNMetadataProvider.h"

/* Decoding an image on the main thread to draw its preview is the price of
 * the option; above this size the type icon is cheaper than the wait. */
static const unsigned long long FSNIconPreviewMaxFileSize = 4ULL * 1000 * 1000;

@implementation FSNIconPreview

+ (BOOL)isPlainImageNode:(FSNode *)node
{
  NSString *ext;

  if (node == nil || [node isDirectory] || [node isLink])
    return NO;

  ext = [[[node path] pathExtension] lowercaseString];
  return ([ext length] > 0
          && [[NSImage imageFileTypes] containsObject: ext]);
}

/* The picture from the thumbnail store, scaled in plain C to exactly
 * the pixels needed, when it is there, still describes the file and is
 * not smaller than needed: a 64 pixel thumbnail of a large photo made by a
 * Thumbnailer bundle is not enough for a large icon. */
+ (NSImage *)storedPreviewOfNode:(FSNode *)node size:(int)size
{
  GWThumbnailStore *store = [[FSNodeRep sharedInstance] thumbnailStore];
  NSData *png = [store dataForPath: [node path]
                              kind: GWThumbnailKindThumbnail
                            source: nil];
  NSUInteger w = 0, h = 0;
  NSUInteger needed = (NSUInteger)ceil(size * [store scaleFactor]);

  if (png == nil || GWThumbnailPNGDimensions(png, &w, &h) == NO)
    return nil;
  if (MAX(w, h) < MIN(needed, [store pixelSize]))
    return nil;
  return GWThumbnailImageFromPNG(png, size, [store scaleFactor]);
}

/* Decoding the image file is what made a folder of photos slow to show;
 * the store keeps the picture for the next start. */
+ (void)storePreview:(NSImage *)image ofNode:(FSNode *)node
{
  GWThumbnailStore *store = [[FSNodeRep sharedInstance] thumbnailStore];
  NSUInteger w = 0, h = 0;
  NSData *rgba;

  if ([store isWritable] == NO)
    return;
  rgba = GWThumbnailRGBAFromImage(image, GW_THUMBNAIL_MAX_DECODE_SIDE, &w, &h);
  if (rgba != nil)
    {
      [store storeRGBAInBackground: rgba width: w height: h forPath: [node path]
                              kind: GWThumbnailKindThumbnail source: nil
                        watchCTime: NO];
    }
}

+ (NSImage *)previewImageForNode:(FSNode *)node size:(int)size
{
  static NSCache *cache = nil;
  FSNodeRep *fsnodeRep = [FSNodeRep sharedInstance];
  NSString *path = [node path];
  NSString *key = [NSString stringWithFormat: @"%@|%d|%.0f", path, size,
                            [[node modificationDate] timeIntervalSince1970]];
  NSImage *image;
  NSSize sz;

  if (cache == nil)
    {
      cache = [NSCache new];
      [cache setCountLimit: 512];
    }

  image = [cache objectForKey: key];
  if (image != nil)
    return image;

  image = [self storedPreviewOfNode: node size: size];
  if (image == nil)
    {
      if ([node fileSize] <= FSNIconPreviewMaxFileSize)
        image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
      if (image == nil || [image isValid] == NO)
        return nil;
      [self storePreview: image ofNode: node];

      /* Blowing a picture smaller than the icon up to the icon size would
       * only make it blurry. */
      sz = [image size];
      if (sz.width > size || sz.height > size)
        image = [fsnodeRep resizedIcon: image ofSize: size];
    }

  [cache setObject: image forKey: key];
  return image;
}

/* Bypasses the thumbnail cache that -[FSNodeRep iconOfSize:forNode:]
 * consults for every file. */
+ (NSImage *)genericTypeIconForNode:(FSNode *)node size:(int)size
{
  FSNodeRep *fsnodeRep = [FSNodeRep sharedInstance];
  NSString *path = [node path];
  NSString *key = [[path pathExtension] lowercaseString];
  NSImage *generic = [fsnodeRep cachedIconOfSize: size forKey: key];

  if (generic == nil)
    {
      NSImage *base = [[NSWorkspace sharedWorkspace] iconForFile: path];

      generic = [fsnodeRep cachedIconOfSize: size
                                     forKey: key
                                addBaseIcon: base];
    }
  return generic;
}

+ (NSImage *)iconForNode:(FSNode *)node size:(int)size showsPreview:(BOOL)showsPreview
{
  FSNodeRep *fsnodeRep = [FSNodeRep sharedInstance];

  if ([self isPlainImageNode: node]
      && [[fsnodeRep metadataProvider] customIconForPath: [node path]] == nil)
    {
      NSImage *image = showsPreview
        ? [self previewImageForNode: node size: size]
        : [self genericTypeIconForNode: node size: size];

      if (image != nil)
        return image;
    }

  return [fsnodeRep iconOfSize: size forNode: node];
}

@end
