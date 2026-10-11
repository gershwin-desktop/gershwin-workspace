/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "FSNLocationFile.h"
#import <AppKit/AppKit.h>
#import "GSFileMetadata.h"

/* Location files are tiny; a bigger one is not one. */
#define LOCATION_FILE_MAX (256 * 1024)

/* The classic Internet Config location files keep the URL in the 'url '
 * resource. */
static NSString * const kClassicURLResource = @"url ";

/* The 'drag' 128 resource of a Finder-made location file: the flavors
 * (TEXT 256, url  256) a drag of the file offers.  Identical in the webloc,
 * ftploc and mailtoloc captures whatever the URL, so it is written verbatim;
 * the meaning of the fields is inferred from those bytes, not documented. */
static const uint8_t kDragResource[48] = {
  0, 0, 0, 1,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 2,
  'T', 'E', 'X', 'T',  0, 0, 1, 0,  0, 0, 0, 0,  0, 0, 0, 0,
  'u', 'r', 'l', ' ',  0, 0, 1, 0,  0, 0, 0, 0,  0, 0, 0, 0
};

static NSURL *
absoluteURL(NSString *string)
{
  NSString *s = [string stringByTrimmingCharactersInSet:
		   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSURL *url = [s length] ? [NSURL URLWithString: s] : nil;

  return [[url scheme] length] ? url : nil;
}

/* "[InternetShortcut]" files: the URL= line of that section. */
static NSURL *
urlFromInternetShortcut(NSString *text)
{
  BOOL inSection = NO;

  for (NSString *line in [text componentsSeparatedByCharactersInSet:
			    [NSCharacterSet newlineCharacterSet]])
    {
      NSString *l = [line stringByTrimmingCharactersInSet:
		       [NSCharacterSet whitespaceCharacterSet]];

      if ([l hasPrefix: @"["])
	{
	  inSection = [l caseInsensitiveCompare: @"[InternetShortcut]"]
	    == NSOrderedSame;
	}
      else if (inSection && [l length] > 4
	       && [[l substringToIndex: 4] caseInsensitiveCompare: @"URL="]
	       == NSOrderedSame)
	{
	  return absoluteURL([l substringFromIndex: 4]);
	}
    }
  return nil;
}

static NSURL *
urlFromData(NSData *data)
{
  id plist = nil;
  NSString *text;

  if ([data length] == 0)
    {
      return nil;
    }
  NS_DURING
    plist = [NSPropertyListSerialization propertyListWithData: data
						      options: 0
						       format: NULL
							error: NULL];
  NS_HANDLER
    plist = nil;
  NS_ENDHANDLER
  if ([plist isKindOfClass: [NSDictionary class]])
    {
      id value = [plist objectForKey: @"URL"];

      return [value isKindOfClass: [NSString class]] ? absoluteURL(value) : nil;
    }
  text = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]
	   autorelease];
  return text ? urlFromInternetShortcut(text) : nil;
}

/* File names cannot hold the path separator, and ':' is the old separator
 * that other systems still show as "/". */
static NSString *
safeFileName(NSString *title)
{
  NSString *s = [[title stringByReplacingOccurrencesOfString: @"/"
						  withString: @"-"]
		  stringByReplacingOccurrencesOfString: @":" withString: @"-"];

  s = [s stringByTrimmingCharactersInSet:
	   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  /* A leading dot would hide the file; the ._ prefix is the sidecar. */
  while ([s hasPrefix: @"."])
    {
      s = [s substringFromIndex: 1];
    }
  return s;
}

/* The name Finder gives a URL dragged into a folder (evidence E27): the URL
 * without its scheme and "//", with "/" stored as ":", which a Mac shows as
 * "/" again.  Very long URLs are cut so the name fits NAME_MAX. */
static NSString *
finderNameForURL(NSURL *url)
{
  NSString *s = [url absoluteString];
  NSRange colon = [s rangeOfString: @":"];

  if (colon.location != NSNotFound)
    {
      s = [s substringFromIndex: NSMaxRange(colon)];
    }
  if ([s hasPrefix: @"//"])
    {
      s = [s substringFromIndex: 2];
    }
  s = [s stringByReplacingOccurrencesOfString: @"/" withString: @":"];
  s = [s stringByTrimmingCharactersInSet:
	   [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  while ([s hasPrefix: @"."])
    {
      s = [s substringFromIndex: 1];
    }
  while ([s lengthOfBytesUsingEncoding: NSUTF8StringEncoding] > 200)
    {
      s = [s substringToIndex:
	       [s rangeOfComposedCharacterSequenceAtIndex: [s length] - 1]
		 .location];
    }
  return s;
}

/* The classic fork and Finder Info of a Finder-made location file, so an
 * older Finder opens the file and shows its name without the extension. */
/* The plist exactly as the Finder writes it (tab indented); the GNUstep XML
 * writer indents with spaces, which parses the same but is not the same file. */
static NSData *
xmlPlistForURL(NSString *urlString)
{
  NSString *escaped = [[[urlString
    stringByReplacingOccurrencesOfString: @"&" withString: @"&amp;"]
    stringByReplacingOccurrencesOfString: @"<" withString: @"&lt;"]
    stringByReplacingOccurrencesOfString: @">" withString: @"&gt;"];
  NSString *xml = [NSString stringWithFormat:
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
    @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    @"<plist version=\"1.0\">\n<dict>\n\t<key>URL</key>\n"
    @"\t<string>%@</string>\n</dict>\n</plist>\n", escaped];

  return [xml dataUsingEncoding: NSUTF8StringEncoding];
}

static BOOL
storeForks(NSString *path, NSString *type, NSURL *url)
{
  GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
  NSData *text = [[url absoluteString] dataUsingEncoding: NSUTF8StringEncoding];
  NSArray *resources = [NSArray arrayWithObjects:
    [GSFileMetadata resourceEntryWithType:
       [GSFileMetadata osTypeFromString: @"drag"] resourceID: 128
       data: [NSData dataWithBytes: kDragResource length: sizeof(kDragResource)]],
    [GSFileMetadata resourceEntryWithType:
       [GSFileMetadata osTypeFromString: @"TEXT"] resourceID: 256 data: text],
    [GSFileMetadata resourceEntryWithType:
       [GSFileMetadata osTypeFromString: kClassicURLResource] resourceID: 256
       data: text],
    nil];

  [md setTypeCode: [GSFileMetadata osTypeFromString: type]];
  [md setCreatorCode: [GSFileMetadata osTypeFromString: @"MACS"]];
  [md setExtensionHidden: YES];
  [md setResourceFork: [GSFileMetadata resourceForkWithResources: resources]];
  return [md writeToFileAtPath: path error: NULL];
}

@implementation FSNLocationFile

+ (BOOL)isLocationFilePath:(NSString *)path
{
  NSString *ext = [[path pathExtension] lowercaseString];

  return [ext isEqualToString: @"webloc"] || [ext isEqualToString: @"inetloc"]
    || [ext isEqualToString: @"fileloc"] || [ext isEqualToString: @"url"]
    || [ext isEqualToString: @"ftploc"] || [ext isEqualToString: @"mailtoloc"];
}

+ (NSURL *)URLForLocationFileAtPath:(NSString *)path
{
  NSDictionary *attrs = [[NSFileManager defaultManager]
			  attributesOfItemAtPath: path error: NULL];
  NSURL *url = nil;
  NSData *fork;
  NSData *res;
  NSString *text;

  if ([self isLocationFilePath: path] == NO
      || [[attrs fileType] isEqualToString: NSFileTypeRegular] == NO)
    {
      return nil;
    }
  if ([[attrs objectForKey: NSFileSize] unsignedLongLongValue]
      <= LOCATION_FILE_MAX)
    {
      url = urlFromData([NSData dataWithContentsOfFile: path]);
    }
  if (url != nil)
    {
      return url;
    }
  fork = [[GSFileMetadata metadataForFileAtPath: path] resourceFork];
  res = fork ? [GSFileMetadata firstDataForResourceType:
		  [GSFileMetadata osTypeFromString: kClassicURLResource]
						 inFork: fork] : nil;
  text = [res length]
    ? [[[NSString alloc] initWithData: res encoding: NSUTF8StringEncoding]
	autorelease] : nil;
  return text ? absoluteURL(text) : nil;
}

+ (NSString *)writeWeblocForURL:(NSURL *)url
			  title:(NSString *)title
		    inDirectory:(NSString *)directory
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base;
  NSString *path;
  NSData *plist;
  NSString *ext = @"webloc";
  NSString *type = @"ilht";
  int n = 1;

  if ([[url scheme] length] == 0)
    {
      return nil;
    }
  base = [title length] ? safeFileName(title) : finderNameForURL(url);
  if ([base length] == 0)
    {
      base = @"Internet Location";
    }
  plist = xmlPlistForURL([url absoluteString]);
  /* The Finder names and types the file after the protocol. */
  if ([[url scheme] caseInsensitiveCompare: @"ftp"] == NSOrderedSame)
    {
      ext = @"ftploc";
      type = @"ilft";
    }
  else if ([[url scheme] caseInsensitiveCompare: @"mailto"] == NSOrderedSame)
    {
      ext = @"mailtoloc";
      type = @"ilma";
    }
  path = [directory stringByAppendingPathComponent:
	    [base stringByAppendingPathExtension: ext]];
  while ([fm fileExistsAtPath: path])
    {
      n++;
      path = [directory stringByAppendingPathComponent:
		[[NSString stringWithFormat: @"%@ %d", base, n]
		  stringByAppendingPathExtension: ext]];
    }
  if (plist == nil || [plist writeToFile: path atomically: YES] == NO)
    {
      return nil;
    }
  return storeForks(path, type, url) ? path : nil;
}

+ (NSURL *)URLForPasteboard:(id)pasteboard
{
  NSArray *types = [pasteboard types];
  NSURL *url = nil;

  if ([types containsObject: NSFilenamesPboardType]
      || [types containsObject: @"GWRemoteFilenamesPboardType"]
      || [types containsObject: @"GWLSFolderPboardType"])
    {
      return nil;
    }
  if ([types containsObject: NSURLPboardType])
    {
      /* A list of [URL string, base URL string] or the bare string,
       * depending on who put it there. */
      id value = [pasteboard propertyListForType: NSURLPboardType];

      if ([value isKindOfClass: [NSArray class]])
	{
	  value = [value count] ? [value objectAtIndex: 0] : nil;
	}
      url = [value isKindOfClass: [NSString class]] ? absoluteURL(value) : nil;
    }
  if (url == nil && [types containsObject: NSStringPboardType])
    {
      NSString *text = [pasteboard stringForType: NSStringPboardType];

      /* A dropped text that merely contains a URL is text, not a link. */
      if ([text rangeOfCharacterFromSet:
	     [NSCharacterSet whitespaceAndNewlineCharacterSet]].location
	  == NSNotFound)
	{
	  url = absoluteURL(text);
	}
    }
  return url;
}

+ (NSString *)writeWeblocFromPasteboard:(id)pasteboard
			    inDirectory:(NSString *)directory
{
  NSURL *url = [self URLForPasteboard: pasteboard];

  return url ? [self writeWeblocForURL: url title: nil inDirectory: directory]
	     : nil;
}

@end
