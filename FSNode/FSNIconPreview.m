/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>
#import "FSNIconPreview.h"
#import "FSNode.h"
#import "FSNodeRep.h"
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

  image = [fsnodeRep thumbnailForPath: path];
  if (image == nil && [node fileSize] <= FSNIconPreviewMaxFileSize)
    image = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
  if (image == nil || [image isValid] == NO)
    return nil;

  /* Blowing a picture smaller than the icon up to the icon size would only
   * make it blurry. */
  sz = [image size];
  if (sz.width > size || sz.height > size)
    image = [fsnodeRep resizedIcon: image ofSize: size];

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
