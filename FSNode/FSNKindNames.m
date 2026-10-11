/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNKindNames.h"

/* Key of the localized name, then the extensions that have it. */
static const struct { NSString *kind; NSString *extensions; } kindTable[] = {
    { @"Plain Text Document", @"txt text log" },
    { @"Markdown Document", @"md markdown" },
    { @"Rich Text Document", @"rtf rtfd" },
    { @"PDF Document", @"pdf" },
    { @"PostScript Document", @"ps eps" },
    { @"HTML Document", @"html htm xhtml" },
    { @"XML Document", @"xml" },
    { @"JSON Document", @"json" },
    { @"Property List", @"plist" },
    { @"CSS Stylesheet", @"css" },
    { @"JavaScript Source", @"js" },
    { @"PNG Image", @"png" },
    { @"JPEG Image", @"jpg jpeg" },
    { @"GIF Image", @"gif" },
    { @"TIFF Image", @"tif tiff" },
    { @"BMP Image", @"bmp" },
    { @"SVG Image", @"svg" },
    { @"Icon Image", @"icns ico" },
    { @"WebP Image", @"webp" },
    { @"MP3 Audio", @"mp3" },
    { @"WAV Audio", @"wav" },
    { @"Ogg Audio", @"ogg oga opus" },
    { @"FLAC Audio", @"flac" },
    { @"AAC Audio", @"aac m4a" },
    { @"MPEG-4 Movie", @"mp4 m4v" },
    { @"QuickTime Movie", @"mov" },
    { @"Matroska Movie", @"mkv" },
    { @"AVI Movie", @"avi" },
    { @"WebM Movie", @"webm" },
    { @"ZIP Archive", @"zip" },
    { @"Tar Archive", @"tar" },
    { @"Compressed Archive", @"gz bz2 xz tgz 7z rar" },
    { @"Disk Image", @"iso dmg img" },
    { @"C Source", @"c" },
    { @"C Header", @"h" },
    { @"Objective-C Source", @"m" },
    { @"C++ Source", @"cpp cc cxx" },
    { @"Python Script", @"py" },
    { @"Shell Script", @"sh" },
    { @"Microsoft Word Document", @"doc docx" },
    { @"Microsoft Excel Spreadsheet", @"xls xlsx" },
    { @"OpenDocument Text", @"odt" },
    { @"Spreadsheet", @"ods csv" }
};

@implementation FSNKindNames

+ (NSDictionary *)kindKeysByExtension
{
  static NSDictionary *map = nil;

  if (map == nil)
    {
      NSMutableDictionary *m = [NSMutableDictionary dictionary];
      size_t i;

      for (i = 0; i < sizeof(kindTable) / sizeof(kindTable[0]); i++)
        {
          NSEnumerator *e = [[kindTable[i].extensions componentsSeparatedByString: @" "]
                              objectEnumerator];
          NSString *ext;

          while ((ext = [e nextObject]) != nil)
            {
              [m setObject: kindTable[i].kind forKey: ext];
            }
        }
      map = [m copy];
    }
  return map;
}

+ (NSString *)kindForExtension:(NSString *)extension
{
  NSString *key = [[self kindKeysByExtension] objectForKey: [extension lowercaseString]];

  if (key == nil)
    {
      return nil;
    }
  /* Looked up in the FSNode framework's table, not the application's. */
  return NSLocalizedStringFromTableInBundle(key, nil,
                                            [NSBundle bundleForClass: self], @"");
}

+ (BOOL)isIdentifierName:(NSString *)name
{
  if ([name length] == 0)
    {
      return YES;
    }
  /* Words for a person contain a space; identifiers do not. */
  return [name rangeOfString: @" "].location == NSNotFound;
}

@end
