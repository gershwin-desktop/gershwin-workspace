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

@implementation FSNLocationFile

+ (BOOL)isLocationFilePath:(NSString *)path
{
  NSString *ext = [[path pathExtension] lowercaseString];

  return [ext isEqualToString: @"webloc"] || [ext isEqualToString: @"inetloc"]
    || [ext isEqualToString: @"fileloc"] || [ext isEqualToString: @"url"];
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
  int n = 1;

  if ([[url scheme] length] == 0)
    {
      return nil;
    }
  base = safeFileName([title length] ? title : ([url host] ? [url host]
						 : [url absoluteString]));
  if ([base length] == 0)
    {
      base = @"Internet Location";
    }
  plist = [NSPropertyListSerialization
	    dataWithPropertyList: [NSDictionary dictionaryWithObject:
				   [url absoluteString] forKey: @"URL"]
			  format: NSPropertyListXMLFormat_v1_0
			 options: 0
			   error: NULL];
  path = [directory stringByAppendingPathComponent:
	    [base stringByAppendingPathExtension: @"webloc"]];
  while ([fm fileExistsAtPath: path])
    {
      n++;
      path = [directory stringByAppendingPathComponent:
		[[NSString stringWithFormat: @"%@ %d", base, n]
		  stringByAppendingPathExtension: @"webloc"]];
    }
  return (plist && [plist writeToFile: path atomically: YES]) ? path : nil;
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
