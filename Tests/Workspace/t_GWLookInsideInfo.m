/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWLookInsideInfo.m - the facts a preview lists for an item that has
 * no picture of its own content (name, kind, size, item count, date).
 * Headless: only the model side of GWLookInsidePreviewView is used, no
 * view is drawn. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/LookInside/GWLookInsidePreviewView.m"
#import "../../Workspace/LookInside/GWLookInsideColumnPreviewProvider.h"

static NSString * const kTag = @"t_GWLookInsideInfo";

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"%@-%d", kTag, getpid()]];
  NSString *file = [dir stringByAppendingPathComponent: @"three.bin"];
  NSString *one = [dir stringByAppendingPathComponent: @"one"];
  NSDictionary *info;

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: one withIntermediateDirectories: YES attributes: nil error: NULL];
  [[NSData dataWithBytes: "abc" length: 3] writeToFile: file atomically: NO];
  [[NSData data] writeToFile: [dir stringByAppendingPathComponent: @"b"] atomically: NO];
  [[NSData data] writeToFile: [dir stringByAppendingPathComponent: @".hidden-file"] atomically: NO];
  [[NSData data] writeToFile: [one stringByAppendingPathComponent: @"x"] atomically: NO];

  info = [GWLookInsidePreviewView infoForPath: file];
  PASS_EQUAL([info objectForKey: GWLookInsideInfoName], @"three.bin",
    "MI-LI-21 a file's facts start with its name");
  PASS_EQUAL([info objectForKey: GWLookInsideInfoSize],
    [sizeDescription(3) stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]],
    "MI-LI-21 a file's size is given as everywhere else in Workspace, without the list's padding");
  PASS([[info objectForKey: GWLookInsideInfoKind] length] > 0,
    "MI-LI-21 a file has a kind");
  PASS([[info objectForKey: GWLookInsideInfoModified] length] > 0,
    "MI-LI-21 a file has a modification date");
  PASS([info objectForKey: GWLookInsideInfoItems] == nil,
    "MI-LI-21 a file has no item count");

  info = [GWLookInsidePreviewView infoForPath: dir];
  PASS_EQUAL([info objectForKey: GWLookInsideInfoItems], @"3 items",
    "MI-LI-22 a folder counts the items a folder window shows, not hidden ones");
  PASS([info objectForKey: GWLookInsideInfoSize] == nil,
    "MI-LI-22 a folder's size is left to the background");

  info = [GWLookInsidePreviewView infoForPath: one];
  PASS_EQUAL([info objectForKey: GWLookInsideInfoItems], @"1 item",
    "MI-LI-22 one item is counted in the singular");

  PASS([[GWLookInsidePreviewView imageExtensions] containsObject: @"png"],
    "MI-LI-13 the image extensions are the ones NSImage decodes");

  /* MI-LI-23: the column view's preview column gets a picture of the
   * content only where there is one; otherwise it keeps its icon. */
  {
    GWLookInsideColumnPreviewProvider *provider = [GWLookInsideColumnPreviewProvider sharedProvider];
    NSRect frame = NSMakeRect(0, 0, 180, 180);
    NSString *binary = [dir stringByAppendingPathComponent: @"blob.bin"];
    const unsigned char bytes[] = {0x7f, 'E', 'L', 'F', 0, 1};

    [[NSData dataWithBytes: bytes length: sizeof(bytes)] writeToFile: binary atomically: NO];
    PASS([provider previewViewForPath: dir frame: frame] == nil,
      "MI-LI-23 a folder leaves the column its icon");
    PASS([provider previewViewForPath: binary frame: frame] == nil,
      "MI-LI-23 a binary file leaves the column its icon");
    PASS([GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindImage]
         && [GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindPlainText]
         && [GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindRichText]
         && [GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindPDF],
      "MI-LI-23 images, text, rich text and PDF get a picture of the content");
    PASS(![GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindAudio]
         && ![GWLookInsideColumnPreviewProvider providesPreviewForKind: GWLookInsidePreviewKindVideo],
      "MI-LI-23 audio and video keep the icon in the column");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
