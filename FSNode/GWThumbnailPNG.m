/*
 * GWThumbnailPNG.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWThumbnailPNG.h"
#include <png.h>
#include <setjmp.h>
#include <stdlib.h>
#include <string.h>

typedef struct
{
  const unsigned char *bytes;
  size_t length;
  size_t offset;
} PNGReadCursor;

static void
ReadFromCursor(png_structp png, png_bytep out, png_size_t count)
{
  PNGReadCursor *cursor = png_get_io_ptr(png);

  if (count > cursor->length - cursor->offset)
    {
      png_error(png, "truncated PNG");
    }
  memcpy(out, cursor->bytes + cursor->offset, count);
  cursor->offset += count;
}

static void
AppendToData(png_structp png, png_bytep in, png_size_t count)
{
  [(NSMutableData *)png_get_io_ptr(png) appendBytes: in length: count];
}

static void
FlushNothing(png_structp png)
{
}

/* A corrupt or hostile .DirIcon is an ordinary input here, not news for
 * the log: the caller gets nil and records the failure itself. */
static void
FailSilently(png_structp png, png_const_charp message)
{
  png_longjmp(png, 1);
}

static void
IgnoreWarning(png_structp png, png_const_charp message)
{
}

NSData *
GWThumbnailPNGDecodeRGBA(NSData *png, NSUInteger maxSide,
                         NSUInteger *width, NSUInteger *height)
{
  PNGReadCursor cursor;
  png_structp reader;
  png_infop info;
  NSMutableData *volatile pixels = nil;
  png_bytep *volatile rows = NULL;
  png_uint_32 w, h;
  int depth, colorType;
  NSUInteger y;

  if ([png length] < 8 || png_sig_cmp((png_const_bytep)[png bytes], 0, 8) != 0)
    {
      return nil;
    }

  reader = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, FailSilently,
                                  IgnoreWarning);
  if (reader == NULL)
    {
      return nil;
    }
  info = png_create_info_struct(reader);
  if (info == NULL)
    {
      png_destroy_read_struct(&reader, NULL, NULL);
      return nil;
    }
  if (setjmp(png_jmpbuf(reader)))
    {
      free(rows);
      [pixels release];
      png_destroy_read_struct(&reader, &info, NULL);
      return nil;
    }

  cursor.bytes = [png bytes];
  cursor.length = [png length];
  cursor.offset = 0;
  png_set_read_fn(reader, &cursor, ReadFromCursor);
  png_read_info(reader, info);
  png_get_IHDR(reader, info, &w, &h, &depth, &colorType, NULL, NULL, NULL);
  if (w == 0 || h == 0 || w > maxSide || h > maxSide)
    {
      png_error(reader, "unsupported PNG size");
    }

  /* Whatever the source format, end up with 8-bit RGBA. */
  if (colorType == PNG_COLOR_TYPE_PALETTE)
    {
      png_set_palette_to_rgb(reader);
    }
  if (colorType == PNG_COLOR_TYPE_GRAY && depth < 8)
    {
      png_set_expand_gray_1_2_4_to_8(reader);
    }
  if (png_get_valid(reader, info, PNG_INFO_tRNS))
    {
      png_set_tRNS_to_alpha(reader);
    }
  if (depth == 16)
    {
      png_set_strip_16(reader);
    }
  if (colorType == PNG_COLOR_TYPE_GRAY || colorType == PNG_COLOR_TYPE_GRAY_ALPHA)
    {
      png_set_gray_to_rgb(reader);
    }
  png_set_filler(reader, 0xff, PNG_FILLER_AFTER);
  png_set_interlace_handling(reader);
  png_read_update_info(reader, info);
  if (png_get_rowbytes(reader, info) != (png_size_t)w * 4)
    {
      png_error(reader, "unexpected row size");
    }

  pixels = [[NSMutableData alloc] initWithLength: (NSUInteger)w * h * 4];
  rows = malloc(sizeof(png_bytep) * h);
  if (rows == NULL)
    {
      png_error(reader, "out of memory");
    }
  for (y = 0; y < h; y++)
    {
      rows[y] = (png_bytep)[pixels mutableBytes] + y * w * 4;
    }
  png_read_image(reader, rows);
  png_read_end(reader, NULL);

  free(rows);
  png_destroy_read_struct(&reader, &info, NULL);
  *width = w;
  *height = h;
  return [pixels autorelease];
}

NSData *
GWThumbnailPNGEncodeRGBA(NSData *rgba, NSUInteger width, NSUInteger height,
                         NSDictionary *text)
{
  NSMutableData *volatile out = nil;
  png_structp writer;
  png_infop info;
  png_textp volatile chunks = NULL;
  png_bytep *volatile rows = NULL;
  NSArray *keys = [[text allKeys] sortedArrayUsingSelector: @selector(compare:)];
  NSUInteger count = [keys count];
  NSUInteger i;

  if (width == 0 || height == 0 || [rgba length] != width * height * 4)
    {
      return nil;
    }

  writer = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, FailSilently,
                                   IgnoreWarning);
  if (writer == NULL)
    {
      return nil;
    }
  info = png_create_info_struct(writer);
  if (info == NULL)
    {
      png_destroy_write_struct(&writer, NULL);
      return nil;
    }
  if (setjmp(png_jmpbuf(writer)))
    {
      free(rows);
      free(chunks);
      [out release];
      png_destroy_write_struct(&writer, &info);
      return nil;
    }

  out = [[NSMutableData alloc] init];
  png_set_write_fn(writer, out, AppendToData, FlushNothing);
  png_set_IHDR(writer, info, (png_uint_32)width, (png_uint_32)height, 8,
               PNG_COLOR_TYPE_RGB_ALPHA, PNG_INTERLACE_NONE,
               PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);

  if (count > 0)
    {
      chunks = calloc(count, sizeof(png_text));
      if (chunks == NULL)
        {
          png_error(writer, "out of memory");
        }
      for (i = 0; i < count; i++)
        {
          NSString *key = [keys objectAtIndex: i];
          const char *k = [key cStringUsingEncoding: NSISOLatin1StringEncoding];
          const char *v = [[text objectForKey: key]
                            cStringUsingEncoding: NSISOLatin1StringEncoding];

          if (k == NULL || v == NULL)
            {
              png_error(writer, "text is not Latin-1");
            }
          chunks[i].compression = PNG_TEXT_COMPRESSION_NONE;
          chunks[i].key = (png_charp)k;
          chunks[i].text = (png_charp)v;
          chunks[i].text_length = strlen(v);
        }
      png_set_text(writer, info, chunks, (int)count);
    }

  rows = malloc(sizeof(png_bytep) * height);
  if (rows == NULL)
    {
      png_error(writer, "out of memory");
    }
  for (i = 0; i < height; i++)
    {
      rows[i] = (png_bytep)[rgba bytes] + i * width * 4;
    }
  /* png_write_info writes the text chunks set above, before any IDAT. */
  png_write_info(writer, info);
  png_write_image(writer, rows);
  png_write_end(writer, NULL);

  free(rows);
  free(chunks);
  png_destroy_write_struct(&writer, &info);
  return [out autorelease];
}
