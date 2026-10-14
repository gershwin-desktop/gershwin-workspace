/*
 * GWThumbnailImage.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWThumbnailImage.h"
#import "GWThumbnailFormat.h"
#import "GWThumbnailPNG.h"
#include <math.h>

NSData *
GWThumbnailRGBAFromBitmap(NSBitmapImageRep *rep, NSUInteger maxSide,
                          NSUInteger *width, NSUInteger *height)
{
  NSString *space = [rep colorSpaceName];
  NSInteger w = [rep pixelsWide];
  NSInteger h = [rep pixelsHigh];
  NSInteger spp = [rep samplesPerPixel];
  NSInteger bps = [rep bitsPerSample];
  BOOL alpha = [rep hasAlpha];
  NSBitmapFormat format = [rep bitmapFormat];
  BOOL alphaFirst = (format & NSAlphaFirstBitmapFormat) != 0;
  BOOL premultiplied = alpha && (format & NSAlphaNonpremultipliedBitmapFormat) == 0;
  BOOL grey, inverted;
  NSInteger colours = spp - (alpha ? 1 : 0);
  NSUInteger max = (bps == 16) ? 65535 : 255;
  NSMutableData *out;
  unsigned char *d;
  NSInteger x, y;

  grey = [space isEqualToString: NSCalibratedWhiteColorSpace]
    || [space isEqualToString: NSDeviceWhiteColorSpace]
    || [space isEqualToString: NSCalibratedBlackColorSpace]
    || [space isEqualToString: NSDeviceBlackColorSpace];
  inverted = [space isEqualToString: NSCalibratedBlackColorSpace]
    || [space isEqualToString: NSDeviceBlackColorSpace];
  if (w <= 0 || h <= 0 || (NSUInteger)w > maxSide || (NSUInteger)h > maxSide
      || (bps != 8 && bps != 16) || colours != (grey ? 1 : 3)
      || (grey == NO && [space isEqualToString: NSCalibratedRGBColorSpace] == NO
          && [space isEqualToString: NSDeviceRGBColorSpace] == NO))
    {
      return nil;
    }

  out = [NSMutableData dataWithLength: (NSUInteger)(w * h * 4)];
  d = [out mutableBytes];

  /* The usual layout read straight from memory: a message per pixel costs
   * tens of milliseconds for a large icon, and icons are converted on the
   * main thread. */
  if ([rep isPlanar] == NO && bps == 8 && [rep bitmapData] != NULL
      && [rep bitsPerPixel] >= spp * 8)
    {
      const unsigned char *data = [rep bitmapData];
      NSInteger bpr = [rep bytesPerRow];
      NSInteger stride = [rep bitsPerPixel] / 8;
      NSInteger first = (alpha && alphaFirst) ? 1 : 0;

      for (y = 0; y < h; y++)
        {
          const unsigned char *p = data + y * bpr;

          for (x = 0; x < w; x++, p += stride, d += 4)
            {
              unsigned a = alpha ? p[alphaFirst ? 0 : colours] : 255;
              NSInteger i;

              for (i = 0; i < 3; i++)
                {
                  unsigned c = p[first + (grey ? 0 : i)];

                  if (inverted)
                    {
                      c = 255 - c;
                    }
                  if (premultiplied)
                    {
                      c = (a == 0) ? 0 : MIN(255u, (c * 255 + a / 2) / a);
                    }
                  d[i] = (unsigned char)c;
                }
              d[3] = (unsigned char)a;
            }
        }
      *width = (NSUInteger)w;
      *height = (NSUInteger)h;
      return out;
    }

  /* getPixel: hands back the samples in the rep's own order whatever its
   * layout (planar, padded rows), which is all this needs to know. */
  for (y = 0; y < h; y++)
    {
      for (x = 0; x < w; x++, d += 4)
        {
          NSUInteger s[5] = { 0, 0, 0, 0, 0 };
          NSUInteger c[3], a = max;
          NSInteger first = (alpha && alphaFirst) ? 1 : 0;
          NSInteger i;

          [rep getPixel: s atX: x y: y];
          if (alpha)
            {
              a = alphaFirst ? s[0] : s[colours];
            }
          for (i = 0; i < 3; i++)
            {
              c[i] = s[first + (grey ? 0 : i)];
              if (inverted)
                {
                  c[i] = max - c[i];
                }
              if (premultiplied)
                {
                  c[i] = (a == 0) ? 0 : MIN(max, (c[i] * max + a / 2) / a);
                }
              d[i] = (unsigned char)((c[i] * 255 + max / 2) / max);
            }
          d[3] = (unsigned char)((a * 255 + max / 2) / max);
        }
    }
  *width = (NSUInteger)w;
  *height = (NSUInteger)h;
  return out;
}

static NSBitmapImageRep *
LargestBitmap(NSArray *reps)
{
  NSBitmapImageRep *best = nil;
  NSUInteger i;

  for (i = 0; i < [reps count]; i++)
    {
      NSImageRep *rep = [reps objectAtIndex: i];

      if ([rep isKindOfClass: [NSBitmapImageRep class]]
          && (best == nil || [rep pixelsWide] * [rep pixelsHigh]
              > [best pixelsWide] * [best pixelsHigh]))
        {
          best = (NSBitmapImageRep *)rep;
        }
    }
  return best;
}

NSData *
GWThumbnailRGBAFromImage(NSImage *image, NSUInteger maxSide,
                         NSUInteger *width, NSUInteger *height)
{
  NSBitmapImageRep *rep = LargestBitmap([image representations]);

  return rep ? GWThumbnailRGBAFromBitmap(rep, maxSide, width, height) : nil;
}

NSData *
GWThumbnailRGBAFromData(NSData *data, NSUInteger maxSide,
                        NSUInteger *width, NSUInteger *height)
{
  NSData *rgba = GWThumbnailPNGDecodeRGBA(data, maxSide, width, height);
  NSBitmapImageRep *rep;

  if (rgba != nil)
    {
      return rgba;
    }
  rep = LargestBitmap([NSBitmapImageRep imageRepsWithData: data]);
  return rep ? GWThumbnailRGBAFromBitmap(rep, maxSide, width, height) : nil;
}

NSImage *
GWThumbnailImageFromPNG(NSData *png, CGFloat points, CGFloat scale)
{
  NSUInteger box = (NSUInteger)ceil(points * scale);
  NSUInteger w = 0, h = 0, tw = 0, th = 0, i;
  NSData *rgba = GWThumbnailPNGDecodeRGBA(png, GW_THUMBNAIL_MAX_DECODE_SIDE, &w, &h);
  NSBitmapImageRep *rep;
  const unsigned char *src;
  unsigned char *dst;
  NSSize size;
  NSImage *image;

  if (rgba == nil || box == 0)
    {
      return nil;
    }
  GWThumbnailFitSize(w, h, box, &tw, &th);
  if (tw != w || th != h)
    {
      rgba = GWThumbnailDownscaleRGBA(rgba, w, h, tw, th);
    }

  rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                pixelsWide: tw
                                                pixelsHigh: th
                                             bitsPerSample: 8
                                           samplesPerPixel: 4
                                                  hasAlpha: YES
                                                  isPlanar: NO
                                            colorSpaceName: NSDeviceRGBColorSpace
                                               bytesPerRow: tw * 4
                                              bitsPerPixel: 32];
  /* The default bitmap format is premultiplied, PNG is not. */
  src = [rgba bytes];
  dst = [rep bitmapData];
  for (i = 0; i < tw * th; i++, src += 4, dst += 4)
    {
      dst[0] = (unsigned char)((src[0] * src[3] + 127) / 255);
      dst[1] = (unsigned char)((src[1] * src[3] + 127) / 255);
      dst[2] = (unsigned char)((src[2] * src[3] + 127) / 255);
      dst[3] = src[3];
    }
  size = NSMakeSize(tw / scale, th / scale);
  [rep setSize: size];
  image = [[NSImage alloc] initWithSize: size];
  [image addRepresentation: rep];
  [rep release];
  return [image autorelease];
}
