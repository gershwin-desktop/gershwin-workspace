/*
 * GWThumbnailSpec.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWThumbnailSpec.h"
#import <GNUstepBase/NSData+GNUstepBase.h>
#include <limits.h>
#include <string.h>

NSString * const GWThumbnailKeyURI = @"Thumb::URI";
NSString * const GWThumbnailKeyMTime = @"Thumb::MTime";
NSString * const GWThumbnailKeySize = @"Thumb::Size";
NSString * const GWThumbnailKeyMimetype = @"Thumb::Mimetype";
NSString * const GWThumbnailKeySoftware = @"Software";

const NSTimeInterval GWThumbnailOrphanAge = 30.0 * 86400.0;

NSString *
GWThumbnailCacheDirectory(NSString *xdgCacheHome, NSString *homeDirectory)
{
  NSString *base;

  if ([xdgCacheHome length] > 0 && [xdgCacheHome isAbsolutePath])
    {
      base = xdgCacheHome;
    }
  else
    {
      base = [homeDirectory stringByAppendingPathComponent: @".cache"];
    }
  return [base stringByAppendingPathComponent: @"thumbnails"];
}

/* The characters g_filename_to_uri() leaves unescaped in a path (GLib's
 * UNSAFE_PATH mask): other thumbnailers hash GLib's spelling, so any other
 * choice would name the same file differently. */
static BOOL
URIKeepsByte(unsigned char c)
{
  if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
    {
      return YES;
    }
  return (c != 0 && strchr("!$&'()*+,-./:=@_~", c) != NULL);
}

NSString *
GWThumbnailURIForPath(NSString *absolutePath)
{
  static const char hex[] = "0123456789ABCDEF";
  const unsigned char *bytes;
  NSMutableString *uri;

  if ([absolutePath isAbsolutePath] == NO)
    {
      return nil;
    }

  bytes = (const unsigned char *)[absolutePath fileSystemRepresentation];
  uri = [NSMutableString stringWithString: @"file://"];
  for (; *bytes != 0; bytes++)
    {
      if (URIKeepsByte(*bytes))
        {
          [uri appendFormat: @"%c", *bytes];
        }
      else
        {
          [uri appendFormat: @"%%%c%c", hex[*bytes >> 4], hex[*bytes & 0xf]];
        }
    }
  return uri;
}

static int
HexValue(unichar c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

NSString *
GWThumbnailPathForURI(NSString *uri)
{
  NSString *prefix = @"file:///";
  NSMutableData *bytes;
  NSUInteger i, len;

  if ([uri hasPrefix: prefix] == NO)
    {
      return nil;
    }

  len = [uri length];
  bytes = [NSMutableData dataWithCapacity: len];
  /* Keep the slash that starts the absolute path. */
  for (i = [prefix length] - 1; i < len; i++)
    {
      unichar c = [uri characterAtIndex: i];
      unsigned char b;

      if (c == '%')
        {
          int hi, lo;

          if (i + 2 >= len)
            {
              return nil;
            }
          hi = HexValue([uri characterAtIndex: i + 1]);
          lo = HexValue([uri characterAtIndex: i + 2]);
          if (hi < 0 || lo < 0 || (hi == 0 && lo == 0))
            {
              return nil;
            }
          b = (unsigned char)(hi << 4 | lo);
          i += 2;
        }
      else if (c > 0x7f)
        {
          return nil;
        }
      else
        {
          b = (unsigned char)c;
        }
      [bytes appendBytes: &b length: 1];
    }

  return [[NSFileManager defaultManager]
           stringWithFileSystemRepresentation: [bytes bytes]
                                       length: [bytes length]];
}

NSString *
GWThumbnailFileNameForURI(NSString *uri)
{
  NSData *digest = [[uri dataUsingEncoding: NSUTF8StringEncoding] md5Digest];
  const unsigned char *d = [digest bytes];
  NSMutableString *name = [NSMutableString stringWithCapacity: 36];
  NSUInteger i;

  for (i = 0; i < [digest length]; i++)
    {
      [name appendFormat: @"%02x", d[i]];
    }
  [name appendString: @".png"];
  return name;
}

NSArray *
GWThumbnailSizeDirectories(void)
{
  return [NSArray arrayWithObjects: @"normal", @"large", @"x-large",
                  @"xx-large", nil];
}

NSUInteger
GWThumbnailPixelsForSizeDirectory(NSString *directory)
{
  NSUInteger index = [GWThumbnailSizeDirectories() indexOfObject: directory];

  if (index == NSNotFound)
    {
      return 0;
    }
  return (NSUInteger)128 << index;
}

NSString *
GWThumbnailSizeDirectoryForPixels(NSUInteger pixels)
{
  NSArray *dirs = GWThumbnailSizeDirectories();
  NSUInteger i;

  for (i = 0; i < [dirs count]; i++)
    {
      if (pixels <= ((NSUInteger)128 << i))
        {
          return [dirs objectAtIndex: i];
        }
    }
  /* Nothing holds more than xx-large; it is the closest there is. */
  return [dirs lastObject];
}

NSString *
GWThumbnailFailureDirectoryName(NSString *program, NSString *version)
{
  return [NSString stringWithFormat: @"%@-%@", program, version];
}

static uint32_t
ReadBE32(const unsigned char *p)
{
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
    | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

NSDictionary *
GWThumbnailTextChunksInPNG(NSData *png)
{
  const unsigned char *bytes = [png bytes];
  NSUInteger length = [png length];
  NSUInteger offset = 8;
  NSMutableDictionary *text;

  if (length < 8 || memcmp(bytes, "\x89PNG\r\n\x1a\n", 8) != 0)
    {
      return nil;
    }

  text = [NSMutableDictionary dictionary];
  while (offset + 8 <= length)
    {
      uint32_t chunkLength = ReadBE32(bytes + offset);
      const unsigned char *type = bytes + offset + 4;
      const unsigned char *payload = bytes + offset + 8;

      if (memcmp(type, "IDAT", 4) == 0 || memcmp(type, "IEND", 4) == 0)
        {
          break;
        }
      if ((NSUInteger)chunkLength > length - offset - 8)
        {
          break;
        }
      if (memcmp(type, "tEXt", 4) == 0)
        {
          const unsigned char *nul = memchr(payload, 0, chunkLength);

          if (nul != NULL && nul != payload)
            {
              NSUInteger keyLength = nul - payload;
              NSString *key = [[NSString alloc] initWithBytes: payload
                                                       length: keyLength
                                                     encoding: NSISOLatin1StringEncoding];
              NSString *value = [[NSString alloc] initWithBytes: nul + 1
                                                         length: chunkLength - keyLength - 1
                                                       encoding: NSISOLatin1StringEncoding];

              if (key != nil && value != nil)
                {
                  [text setObject: value forKey: key];
                }
              [key release];
              [value release];
            }
        }
      offset += 12 + (NSUInteger)chunkLength;
    }
  return text;
}

/* The keys hold decimal integers; anything else (a sign, trailing junk, an
 * empty string) is treated as unusable rather than read as a prefix, so a
 * damaged entry is regenerated instead of trusted. */
static BOOL
ParseDecimal(NSString *s, long long *out)
{
  const char *c = [s UTF8String];
  long long v = 0;

  if (c == NULL || *c == 0)
    {
      return NO;
    }
  for (; *c != 0; c++)
    {
      if (*c < '0' || *c > '9' || v > (LLONG_MAX - 9) / 10)
        {
          return NO;
        }
      v = v * 10 + (*c - '0');
    }
  *out = v;
  return YES;
}

static BOOL
StampMatches(NSDictionary *text, GWThumbnailFileStamp stamp)
{
  NSString *size = [text objectForKey: GWThumbnailKeySize];
  long long value;

  if (ParseDecimal([text objectForKey: GWThumbnailKeyMTime], &value) == NO
      || value != stamp.mtime)
    {
      return NO;
    }
  if (size != nil && (ParseDecimal(size, &value) == NO || value != stamp.size))
    {
      return NO;
    }
  return YES;
}

BOOL
GWThumbnailMatchesFile(NSDictionary *text, NSString *uri,
                       GWThumbnailFileStamp stamp)
{
  if ([[text objectForKey: GWThumbnailKeyURI] isEqualToString: uri] == NO)
    {
      return NO;
    }
  return StampMatches(text, stamp);
}

BOOL
GWThumbnailIsStale(NSDictionary *text, NSString *software,
                   GWThumbnailOriginalState original, NSTimeInterval entryAge)
{
  if ([[text objectForKey: GWThumbnailKeySoftware] isEqualToString: software] == NO)
    {
      return NO;
    }
  if (GWThumbnailPathForURI([text objectForKey: GWThumbnailKeyURI]) == nil)
    {
      return NO;
    }
  if (original.exists == NO)
    {
      return original.parentExists || entryAge > GWThumbnailOrphanAge;
    }
  return StampMatches(text, original.stamp) == NO;
}

void
GWThumbnailFitSize(NSUInteger width, NSUInteger height, NSUInteger box,
                   NSUInteger *outWidth, NSUInteger *outHeight)
{
  if (width <= box && height <= box)
    {
      *outWidth = width;
      *outHeight = height;
    }
  else if (width >= height)
    {
      *outWidth = box;
      *outHeight = MAX((NSUInteger)1, (height * box + width / 2) / width);
    }
  else
    {
      *outHeight = box;
      *outWidth = MAX((NSUInteger)1, (width * box + height / 2) / height);
    }
}

NSData *
GWThumbnailDownscaleRGBA(NSData *rgba, NSUInteger width, NSUInteger height,
                         NSUInteger newWidth, NSUInteger newHeight)
{
  const unsigned char *src = [rgba bytes];
  NSMutableData *out;
  unsigned char *dst;
  NSUInteger x, y;

  if (width == 0 || height == 0 || newWidth == 0 || newHeight == 0
      || [rgba length] != width * height * 4
      || newWidth > width || newHeight > height)
    {
      return nil;
    }

  out = [NSMutableData dataWithLength: newWidth * newHeight * 4];
  dst = [out mutableBytes];
  for (y = 0; y < newHeight; y++)
    {
      NSUInteger y0 = y * height / newHeight;
      NSUInteger y1 = MAX(y0 + 1, (y + 1) * height / newHeight);

      for (x = 0; x < newWidth; x++)
        {
          NSUInteger x0 = x * width / newWidth;
          NSUInteger x1 = MAX(x0 + 1, (x + 1) * width / newWidth);
          unsigned long long r = 0, g = 0, b = 0, a = 0, n = 0;
          unsigned char *d = dst + (y * newWidth + x) * 4;
          NSUInteger sx, sy;

          for (sy = y0; sy < y1; sy++)
            {
              for (sx = x0; sx < x1; sx++)
                {
                  const unsigned char *s = src + (sy * width + sx) * 4;

                  r += (unsigned long long)s[0] * s[3];
                  g += (unsigned long long)s[1] * s[3];
                  b += (unsigned long long)s[2] * s[3];
                  a += s[3];
                  n++;
                }
            }
          if (a > 0)
            {
              d[0] = (unsigned char)((r + a / 2) / a);
              d[1] = (unsigned char)((g + a / 2) / a);
              d[2] = (unsigned char)((b + a / 2) / a);
            }
          d[3] = (unsigned char)((a + n / 2) / n);
        }
    }
  return out;
}
