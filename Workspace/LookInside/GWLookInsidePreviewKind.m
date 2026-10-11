/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWLookInsidePreviewKind.h"

/* Enough of a file to tell text from binary without reading all of it. */
static const NSUInteger kTextSampleLength = 4096;

static NSSet *
SetOf(NSString *first, ...)
{
  NSMutableSet *set = [NSMutableSet set];
  va_list ap;
  NSString *s;

  va_start(ap, first);
  for (s = first; s != nil; s = va_arg(ap, NSString *))
    {
      [set addObject: s];
    }
  va_end(ap);
  return set;
}

GWLookInsidePreviewKind
GWLookInsidePreviewKindForPath(NSString *path, NSArray *imageExtensions, BOOL isPackage)
{
  static NSSet *richText = nil;
  static NSSet *audio = nil;
  static NSSet *video = nil;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *extension = [[path pathExtension] lowercaseString];
  NSFileHandle *handle;
  NSData *sample;
  BOOL isDirectory = NO;

  if (richText == nil)
    {
      richText = [SetOf(@"rtf", @"rtfd", nil) retain];
      audio = [SetOf(@"mp3", @"m4a", @"aac", @"flac", @"ogg", @"oga", @"opus",
                     @"wav", @"aif", @"aiff", @"au", @"snd", nil) retain];
      video = [SetOf(@"mp4", @"m4v", @"mov", @"mkv", @"webm", @"avi", @"mpg",
                     @"mpeg", @"ogv", @"wmv", @"flv", nil) retain];
    }

  if (path == nil || ![fm fileExistsAtPath: path isDirectory: &isDirectory])
    {
      return GWLookInsidePreviewKindNone;
    }
  /* An .rtfd is a directory, but it is one document. */
  if ([richText containsObject: extension])
    {
      return GWLookInsidePreviewKindRichText;
    }
  if (isDirectory)
    {
      return isPackage ? GWLookInsidePreviewKindOther : GWLookInsidePreviewKindFolder;
    }
  if ([extension isEqualToString: @"pdf"])
    {
      return GWLookInsidePreviewKindPDF;
    }
  if ([extension length] > 0 && [imageExtensions containsObject: extension])
    {
      return GWLookInsidePreviewKindImage;
    }
  if ([audio containsObject: extension])
    {
      return GWLookInsidePreviewKindAudio;
    }
  if ([video containsObject: extension])
    {
      return GWLookInsidePreviewKindVideo;
    }

  /* Everything else is judged by its bytes, not its name: source files,
   * READMEs, configuration and logs come with any extension or none. */
  handle = [NSFileHandle fileHandleForReadingAtPath: path];
  sample = [handle readDataOfLength: kTextSampleLength];
  [handle closeFile];

  if ([sample length] > 0 && GWLookInsideDataLooksLikeText(sample))
    {
      return GWLookInsidePreviewKindPlainText;
    }
  return GWLookInsidePreviewKindOther;
}

BOOL
GWLookInsideDataLooksLikeText(NSData *sample)
{
  const unsigned char *bytes = [sample bytes];
  NSUInteger length = [sample length];
  NSUInteger i = 0;

  while (i < length)
    {
      unsigned char c = bytes[i];
      NSUInteger follow, k;

      if (c == 0)
        {
          return NO;
        }
      if (c < 0x80)
        {
          i++;
          continue;
        }
      if (c >= 0xC2 && c <= 0xDF)
        {
          follow = 1;
        }
      else if (c >= 0xE0 && c <= 0xEF)
        {
          follow = 2;
        }
      else if (c >= 0xF0 && c <= 0xF4)
        {
          follow = 3;
        }
      else
        {
          return NO;
        }
      for (k = 1; k <= follow; k++)
        {
          if (i + k >= length)
            {
              /* Cut off by the end of the sample, not broken. */
              return YES;
            }
          if ((bytes[i + k] & 0xC0) != 0x80)
            {
              return NO;
            }
        }
      i += follow + 1;
    }
  return YES;
}
