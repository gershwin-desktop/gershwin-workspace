/*
 * GWThumbnailFormat.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWThumbnailFormat.h"
#include <limits.h>
#include <string.h>

NSString * const GWThumbnailKindThumbnail = @"thumbnail";
NSString * const GWThumbnailKindIcon = @"icon";
NSString * const GWThumbnailKindFailure = @"failure";

NSString * const GWThumbnailEntryName = @"name";
NSString * const GWThumbnailEntryKind = @"kind";
NSString * const GWThumbnailEntryMTime = @"mtime";
NSString * const GWThumbnailEntrySize = @"size";
NSString * const GWThumbnailEntryCTime = @"ctime";
NSString * const GWThumbnailEntrySource = @"source";

NSString * const GWThumbnailTextPath = @"GW::Path";
NSString * const GWThumbnailTextKind = @"GW::Kind";
NSString * const GWThumbnailTextMTime = @"GW::MTime";
NSString * const GWThumbnailTextSize = @"GW::Size";
NSString * const GWThumbnailTextCTime = @"GW::CTime";
NSString * const GWThumbnailTextSource = @"GW::Source";
NSString * const GWThumbnailTextSoftware = @"Software";

const NSTimeInterval GWThumbnailOrphanAge = 30.0 * 86400.0;

NSDictionary *
GWThumbnailEntryFromIndexValue(id value)
{
  if ([value isKindOfClass: [NSDictionary class]])
    {
      return value;
    }
  if ([value isKindOfClass: [NSString class]] && [value length] > 0)
    {
      return [NSDictionary dictionaryWithObjectsAndKeys:
        value, GWThumbnailEntryName,
        GWThumbnailKindThumbnail, GWThumbnailEntryKind, nil];
    }
  return nil;
}

NSDictionary *
GWThumbnailMakeEntry(NSString *name, NSString *kind, NSString *source,
                     GWThumbnailFileStamp stamp, BOOL watchCTime)
{
  NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithCapacity: 6];

  [entry setObject: name forKey: GWThumbnailEntryName];
  [entry setObject: kind forKey: GWThumbnailEntryKind];
  [entry setObject: [NSNumber numberWithLongLong: stamp.mtime]
            forKey: GWThumbnailEntryMTime];
  [entry setObject: [NSNumber numberWithLongLong: stamp.size]
            forKey: GWThumbnailEntrySize];
  if (watchCTime)
    {
      [entry setObject: [NSNumber numberWithLongLong: stamp.ctime]
                forKey: GWThumbnailEntryCTime];
    }
  if (source != nil)
    {
      [entry setObject: source forKey: GWThumbnailEntrySource];
    }
  return entry;
}

NSString *
GWThumbnailEntrySourcePath(NSDictionary *entry, NSString *path)
{
  NSString *source = [entry objectForKey: GWThumbnailEntrySource];

  return ([source length] > 0) ? source : path;
}

/* Index values come back from a property list as strings or numbers
 * depending on who wrote them; both are read, anything else is unusable. */
static BOOL
NumberValue(id value, long long *out)
{
  if ([value isKindOfClass: [NSNumber class]])
    {
      *out = [value longLongValue];
      return YES;
    }
  if ([value isKindOfClass: [NSString class]])
    {
      const char *c = [value UTF8String];
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
  return NO;
}

BOOL
GWThumbnailEntryMatches(NSDictionary *entry, GWThumbnailFileStamp stamp)
{
  id ctime = [entry objectForKey: GWThumbnailEntryCTime];
  long long v;

  if (NumberValue([entry objectForKey: GWThumbnailEntryMTime], &v) == NO
      || v != stamp.mtime)
    {
      return NO;
    }
  if (NumberValue([entry objectForKey: GWThumbnailEntrySize], &v) == NO
      || v != stamp.size)
    {
      return NO;
    }
  if (ctime != nil && (NumberValue(ctime, &v) == NO || v != stamp.ctime))
    {
      return NO;
    }
  return YES;
}

BOOL
GWThumbnailEntryIsStale(NSDictionary *entry, GWThumbnailSourceState source,
                        NSTimeInterval entryAge)
{
  if (source.exists == NO)
    {
      return source.parentExists || entryAge > GWThumbnailOrphanAge;
    }
  return GWThumbnailEntryMatches(entry, source.stamp) == NO;
}

static NSString *
DecimalString(id value)
{
  long long v;

  return NumberValue(value, &v) ? [NSString stringWithFormat: @"%lld", v] : nil;
}

NSDictionary *
GWThumbnailTextForEntry(NSString *path, NSDictionary *entry, NSString *software)
{
  NSMutableDictionary *text = [NSMutableDictionary dictionaryWithCapacity: 7];
  NSString *ctime = DecimalString([entry objectForKey: GWThumbnailEntryCTime]);
  NSString *source = [entry objectForKey: GWThumbnailEntrySource];

  [text setObject: path forKey: GWThumbnailTextPath];
  [text setObject: [entry objectForKey: GWThumbnailEntryKind] forKey: GWThumbnailTextKind];
  [text setObject: DecimalString([entry objectForKey: GWThumbnailEntryMTime])
           forKey: GWThumbnailTextMTime];
  [text setObject: DecimalString([entry objectForKey: GWThumbnailEntrySize])
           forKey: GWThumbnailTextSize];
  if (ctime != nil)
    {
      [text setObject: ctime forKey: GWThumbnailTextCTime];
    }
  if (source != nil)
    {
      [text setObject: source forKey: GWThumbnailTextSource];
    }
  [text setObject: software forKey: GWThumbnailTextSoftware];
  return text;
}

NSDictionary *
GWThumbnailEntryFromText(NSDictionary *text, NSString *name, NSString **outPath)
{
  NSString *path = [text objectForKey: GWThumbnailTextPath];
  NSString *kind = [text objectForKey: GWThumbnailTextKind];
  id ctime = [text objectForKey: GWThumbnailTextCTime];
  GWThumbnailFileStamp stamp;

  if ([path isAbsolutePath] == NO || [kind length] == 0
      || NumberValue([text objectForKey: GWThumbnailTextMTime], &stamp.mtime) == NO
      || NumberValue([text objectForKey: GWThumbnailTextSize], &stamp.size) == NO
      || (ctime != nil && NumberValue(ctime, &stamp.ctime) == NO))
    {
      return nil;
    }
  if (ctime == nil)
    {
      stamp.ctime = 0;
    }
  *outPath = path;
  return GWThumbnailMakeEntry(name, kind, [text objectForKey: GWThumbnailTextSource],
                              stamp, ctime != nil);
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

BOOL
GWThumbnailPNGDimensions(NSData *png, NSUInteger *width, NSUInteger *height)
{
  const unsigned char *b = [png bytes];

  if ([png length] < 24 || memcmp(b, "\x89PNG\r\n\x1a\n", 8) != 0
      || memcmp(b + 12, "IHDR", 4) != 0)
    {
      return NO;
    }
  *width = ReadBE32(b + 16);
  *height = ReadBE32(b + 20);
  return (*width > 0 && *height > 0);
}

long
GWThumbnailNameCounter(NSString *name)
{
  NSString *base = [name stringByDeletingPathExtension];
  const char *c = [base UTF8String];
  long v = 0;

  if (c == NULL || *c == 0 || [[name pathExtension] length] == 0)
    {
      return -1;
    }
  for (; *c != 0; c++)
    {
      int d;

      if (*c >= '0' && *c <= '9') d = *c - '0';
      else if (*c >= 'a' && *c <= 'f') d = *c - 'a' + 10;
      else return -1;
      if (v > (LONG_MAX - 15) / 16)
        {
          return -1;
        }
      v = v * 16 + d;
    }
  return v;
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
GWThumbnailPathForFileURI(NSString *uri)
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
