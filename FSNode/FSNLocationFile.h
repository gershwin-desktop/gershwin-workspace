/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef _FSNLOCATIONFILE_H_
#define _FSNLOCATIONFILE_H_

#import <Foundation/Foundation.h>

/* Internet and file location files as the Finder knows them: .webloc,
 * .inetloc and .fileloc (a property list with a URL key, or the classic form
 * with the URL in a 'url ' resource of the resource fork), plus the
 * Windows-style .url ("[InternetShortcut]") that arrives on shared drives.
 * */
@interface FSNLocationFile : NSObject

/* YES for the path extensions above, compared without regard to case. */
+ (BOOL)isLocationFilePath:(NSString *)path;

/* The URL a location file points to, or nil if the file cannot be read or
 * holds no absolute URL.  Never guesses: a relative or scheme-less string is
 * rejected rather than turned into something that "might" open. */
+ (NSURL *)URLForLocationFileAtPath:(NSString *)path;

/* Create "<title>.webloc" in directory as an XML property list with a URL
 * key, which is what the Finder opens.  A nil or empty title falls back to
 * the host of the URL.  An existing name gets " 2", " 3", ... appended.
 * Returns the new path, or nil if the URL is not absolute or the file cannot
 * be written. */
+ (NSString *)writeWeblocForURL:(NSURL *)url
			  title:(NSString *)title
		    inDirectory:(NSString *)directory;

/* The URL a drag or paste carries when it carries no files: NSURLPboardType,
 * else an absolute URL in NSStringPboardType.  A pasteboard that also holds
 * files (Filenames, GWRemoteFilenames, GWLSFolder) is a file drop and gives
 * nil, as does any string that is not an absolute URL.  The argument is
 * anything that answers -types, -propertyListForType: and -stringForType:
 * as NSPasteboard does. */
+ (NSURL *)URLForPasteboard:(id)pasteboard;

/* Drop of a URL onto a folder: writes "<title>.webloc" there for the URL
 * from +URLForPasteboard:.  Returns the new path, or nil when the pasteboard
 * holds no such URL or the file cannot be written, in which case the drop is
 * to be refused. */
+ (NSString *)writeWeblocFromPasteboard:(id)pasteboard
			    inDirectory:(NSString *)directory;

@end

#endif
