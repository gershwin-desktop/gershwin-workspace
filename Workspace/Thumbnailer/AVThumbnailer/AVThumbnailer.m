/*
 * AVThumbnailer.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 *         Riccardo Mottola <rm@gnu.org>
 * Date: July 2026
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#include <math.h>
#import "AVThumbnailer.h"

static NSArray *supportedExtensions = nil;

@implementation AVThumbnailer

+ (void)initialize
{
  if (self == [AVThumbnailer class])
    {
      supportedExtensions = [[NSArray alloc] initWithObjects:
        @"mp3", @"m4a", @"m4r", @"flac", @"ogg", @"wav", @"aiff", @"aif", nil];
    }
}

- (void)dealloc
{
  [super dealloc];
}

- (BOOL)canProvideThumbnailForPath:(NSString *)path
{
  NSString *ext = [[path pathExtension] lowercaseString];
  return (ext && [supportedExtensions containsObject: ext]);
}

- (NSData *)makeThumbnailForPath:(NSString *)path
{
  if (path == nil)
    return nil;

  NSURL *url = [NSURL fileURLWithPath: path];
  AVURLAsset *asset = [[AVURLAsset alloc] initWithURL: url options: nil];
  NSData *coverData = nil;

  NSArray *metadata = [asset commonMetadata];
  for (AVMetadataItem *item in metadata)
    {
      id key = [item key];
      if ([key isKindOfClass: [NSString class]]
          && [(NSString *)key isEqualToString: AVMetadataCommonKeyArtwork])
        {
          id value = [item value];
          if ([value isKindOfClass: [NSData class]])
            {
              coverData = [(NSData *)value retain];
            }
          break;
        }
    }

  [asset release];

  if (coverData == nil)
    return nil;

  NSImage *sourceImage = [[NSImage alloc] initWithData: coverData];
  [coverData release];

  if (sourceImage == nil)
    return nil;

  NSSize sourceSize = [sourceImage size];

  if ((sourceSize.width <= TMBMAX) && (sourceSize.height <= TMBMAX))
    {
      NSData *tiffData = [sourceImage TIFFRepresentation];
      [sourceImage release];
      return tiffData;
    }

  float fact = (sourceSize.width >= sourceSize.height)
    ? (sourceSize.width / TMBMAX)
    : (sourceSize.height / TMBMAX);

  NSSize destSize = NSMakeSize(
    (NSInteger)floor(sourceSize.width / fact + 0.5),
    (NSInteger)floor(sourceSize.height / fact + 0.5));

  NSImage *destImage = [[NSImage alloc] initWithSize: destSize];
  [destImage lockFocus];
  [sourceImage drawInRect: NSMakeRect(0, 0, destSize.width, destSize.height)
                 fromRect: NSMakeRect(0, 0, sourceSize.width, sourceSize.height)
                operation: NSCompositeCopy
                 fraction: 1.0];
  [destImage unlockFocus];

  NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData: [destImage TIFFRepresentation]];
  NSData *tiffData = [[rep TIFFRepresentation] retain];

  [destImage release];
  [sourceImage release];

  return [tiffData autorelease];
}

- (NSString *)fileNameExtension
{
  return @"tiff";
}

- (NSString *)description
{
  return @"Audio Thumbnailer";
}

@end
