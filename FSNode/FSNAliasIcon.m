/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "FSNAliasIcon.h"
#import <AppKit/AppKit.h>
#include <math.h>

/* One filled shape of the artwork, in a unit square with y pointing down. */
typedef struct {
  const float *pts;	/* x, y pairs; NULL for a circle */
  int count;		/* points; unused for a circle */
  float cx, cy, r;	/* circle */
  uint8_t rgb[3];
} Shape;

#define MAX_SHAPES 12
#define SAMPLES 3

static BOOL
shapeCovers(const Shape *s, float x, float y)
{
  int i;
  int j;
  BOOL in = NO;

  if (s->pts == NULL)
    {
      return (x - s->cx) * (x - s->cx) + (y - s->cy) * (y - s->cy)
	<= s->r * s->r;
    }
  for (i = 0, j = s->count - 1; i < s->count; j = i++)
    {
      float xi = s->pts[2 * i], yi = s->pts[2 * i + 1];
      float xj = s->pts[2 * j], yj = s->pts[2 * j + 1];

      if (((yi > y) != (yj > y))
	  && x < (xj - xi) * (y - yi) / (yj - yi) + xi)
	{
	  in = !in;
	}
    }
  return in;
}

static void
setPoly(Shape *s, const float *pts, int count, uint8_t r, uint8_t g, uint8_t b)
{
  s->pts = pts;
  s->count = count;
  s->rgb[0] = r; s->rgb[1] = g; s->rgb[2] = b;
}

static void
setCircle(Shape *s, float cx, float cy, float r, uint8_t red, uint8_t g,
	  uint8_t b)
{
  s->pts = NULL;
  s->cx = cx; s->cy = cy; s->r = r;
  s->rgb[0] = red; s->rgb[1] = g; s->rgb[2] = b;
}

static const float pageOuter[] = { .20,.06, .62,.06, .82,.26, .82,.94, .20,.94 };
static const float pageInner[] = { .225,.085, .605,.085, .795,.275, .795,.915,
				   .225,.915 };
static const float pageFold[] = { .605,.085, .605,.275, .795,.275 };
static const float folderOuter[] = { .06,.22, .38,.22, .46,.30, .94,.30,
				     .94,.86, .06,.86 };
static const float folderInner[] = { .085,.245, .37,.245, .45,.325, .915,.325,
				     .915,.835, .085,.835 };

/* The arrow points up and to the right, as the alias arrow does: drawn
 * pointing right, then turned by 45 degrees around the badge centre. */
static void
arrowPoints(float *out, float cx, float cy)
{
  static const float local[] = { -.11,-.025, .03,-.025, .03,-.075, .11,0,
				 .03,.075, .03,.025, -.11,.025 };
  const float c = 0.70710678f;
  int i;

  for (i = 0; i < 7; i++)
    {
      float x = local[2 * i], y = local[2 * i + 1];

      out[2 * i] = cx + c * x + c * y;
      out[2 * i + 1] = cy - c * x + c * y;
    }
}

static NSData *
pngForSize(int size, BOOL isDirectory)
{
  NSBitmapImageRep *rep;
  Shape shapes[MAX_SHAPES];
  float arrow[14];
  int n = 0;
  int x;
  int y;

  if (isDirectory)
    {
      setPoly(&shapes[n++], folderOuter, 6, 70, 100, 150);
      setPoly(&shapes[n++], folderInner, 6, 120, 170, 225);
    }
  else
    {
      setPoly(&shapes[n++], pageOuter, 5, 110, 110, 110);
      setPoly(&shapes[n++], pageInner, 5, 245, 245, 245);
      setPoly(&shapes[n++], pageFold, 3, 200, 200, 200);
    }
  setCircle(&shapes[n++], .27, .74, .24, 60, 60, 60);
  setCircle(&shapes[n++], .27, .74, .215, 255, 255, 255);
  arrowPoints(arrow, .27, .74);
  setPoly(&shapes[n++], arrow, 7, 30, 30, 30);

  rep = [[[NSBitmapImageRep alloc]
	   initWithBitmapDataPlanes: NULL
			 pixelsWide: size
			 pixelsHigh: size
		      bitsPerSample: 8
		    samplesPerPixel: 4
			   hasAlpha: YES
			   isPlanar: NO
		     colorSpaceName: NSDeviceRGBColorSpace
		       bitmapFormat: NSAlphaNonpremultipliedBitmapFormat
			bytesPerRow: 0
		       bitsPerPixel: 32] autorelease];
  for (y = 0; y < size; y++)
    {
      uint8_t *row = [rep bitmapData] + y * [rep bytesPerRow];

      for (x = 0; x < size; x++)
	{
	  int covered = 0;
	  int sum[3] = { 0, 0, 0 };
	  int sx;
	  int sy;

	  /* Supersampling keeps the edges smooth without a graphics context. */
	  for (sy = 0; sy < SAMPLES; sy++)
	    {
	      for (sx = 0; sx < SAMPLES; sx++)
		{
		  float fx = (x + (sx + 0.5f) / SAMPLES) / size;
		  float fy = (y + (sy + 0.5f) / SAMPLES) / size;
		  int k;

		  for (k = n - 1; k >= 0; k--)
		    {
		      if (shapeCovers(&shapes[k], fx, fy))
			{
			  covered++;
			  sum[0] += shapes[k].rgb[0];
			  sum[1] += shapes[k].rgb[1];
			  sum[2] += shapes[k].rgb[2];
			  break;
			}
		    }
		}
	    }
	  if (covered > 0)
	    {
	      row[4 * x] = sum[0] / covered;
	      row[4 * x + 1] = sum[1] / covered;
	      row[4 * x + 2] = sum[2] / covered;
	    }
	  else
	    {
	      row[4 * x] = row[4 * x + 1] = row[4 * x + 2] = 0;
	    }
	  row[4 * x + 3] = covered * 255 / (SAMPLES * SAMPLES);
	}
    }
  return [rep representationUsingType: NSPNGFileType properties: nil];
}

static void
appendBE32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v };

  [d appendBytes: b length: 4];
}

static void
appendChunk(NSMutableData *icns, const char *type, NSData *png)
{
  [icns appendBytes: type length: 4];
  appendBE32(icns, (uint32_t)[png length] + 8);
  [icns appendData: png];
}

@implementation FSNAliasIcon

+ (NSData *)icnsDataForDirectory:(BOOL)isDirectory
{
  NSData *small = pngForSize(128, isDirectory);
  NSData *large = pngForSize(256, isDirectory);
  NSMutableData *icns = [NSMutableData data];

  if (small == nil || large == nil)
    {
      return nil;
    }
  [icns appendBytes: "icns" length: 4];
  appendBE32(icns, (uint32_t)([small length] + [large length]) + 8 + 16);
  appendChunk(icns, "ic07", small);
  appendChunk(icns, "ic08", large);
  return icns;
}

@end
