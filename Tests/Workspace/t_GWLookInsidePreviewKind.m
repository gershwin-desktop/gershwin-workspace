/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWLookInsidePreviewKind.m - which preview an item gets, decided from
 * real files in a scratch directory.  Headless. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/LookInside/GWLookInsidePreviewKind.m"

static NSString *
Make(NSString *dir, NSString *name, NSData *data)
{
  NSString *path = [dir stringByAppendingPathComponent: name];

  [data writeToFile: path atomically: NO];
  return path;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWLookInsidePreviewKind-%d", getpid()]];
  NSArray *images = [NSArray arrayWithObjects: @"png", @"jpg", @"tiff", nil];
  NSData *text = [@"hello\nworld\n" dataUsingEncoding: NSUTF8StringEncoding];
  const unsigned char binaryBytes[] = {0x7f, 'E', 'L', 'F', 0, 0, 1, 2};
  NSData *binary = [NSData dataWithBytes: binaryBytes length: sizeof(binaryBytes)];
  const unsigned char cutBytes[] = {'a', 'b', 0xC3};      /* half of a two byte character */
  const unsigned char badBytes[] = {'a', 0xFF, 'b', 'c'}; /* never valid UTF-8 */

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];

  PASS(GWLookInsidePreviewKindForPath([dir stringByAppendingPathComponent: @"missing"], images, NO)
       == GWLookInsidePreviewKindNone, "MI-LI-11 a missing item has no preview");
  PASS(GWLookInsidePreviewKindForPath(dir, images, NO) == GWLookInsidePreviewKindFolder,
       "MI-LI-12 a folder gets the folder preview");
  PASS(GWLookInsidePreviewKindForPath(dir, images, YES) == GWLookInsidePreviewKindOther,
       "MI-LI-12 an application or other package is one item, not a folder");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.PNG", binary), images, NO)
       == GWLookInsidePreviewKindImage, "MI-LI-13 a decodable image extension is an image");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.rtf", text), images, NO)
       == GWLookInsidePreviewKindRichText, "MI-LI-14 RTF is rich text");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.pdf", binary), images, NO)
       == GWLookInsidePreviewKindPDF, "MI-LI-15 PDF is PDF");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.mp3", binary), images, NO)
       == GWLookInsidePreviewKindAudio, "MI-LI-16 an mp3 is audio");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.mkv", binary), images, NO)
       == GWLookInsidePreviewKindVideo, "MI-LI-16 an mkv is video");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"README", text), images, NO)
       == GWLookInsidePreviewKindPlainText, "MI-LI-17 text without an extension is read as text");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"notes.weird", text), images, NO)
       == GWLookInsidePreviewKindPlainText, "MI-LI-17 text with an unknown extension is read as text");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"a.out", binary), images, NO)
       == GWLookInsidePreviewKindOther, "MI-LI-18 a binary file gets the icon and its facts");
  PASS(GWLookInsidePreviewKindForPath(Make(dir, @"empty", [NSData data]), images, NO)
       == GWLookInsidePreviewKindOther, "MI-LI-18 an empty file gets the icon and its facts");

  PASS(GWLookInsideDataLooksLikeText([NSData dataWithBytes: cutBytes length: sizeof(cutBytes)]),
       "MI-LI-17 a character cut off by the sample does not make text binary");
  PASS(!GWLookInsideDataLooksLikeText([NSData dataWithBytes: badBytes length: sizeof(badBytes)]),
       "MI-LI-18 bytes that are not UTF-8 are not text");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
