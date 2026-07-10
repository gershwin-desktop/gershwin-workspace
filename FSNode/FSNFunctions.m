/* FSNFunctions.m
 *  
 * Copyright (C) 2004-2024 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale
 *         Riccardo Mottola <rm@gnu.org>
 * Date: March 2004
 *
 * This file is part of the GNUstep FSNode framework
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

#include <math.h>
#include <sys/stat.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "FSNFunctions.h"
#import "FSNodeRep.h"
#import <dispatch/dispatch.h>
static GSFilenameExtensionDisplayMode _displayModeCache = -1;

static NSString *defaultsPlistPath(void)
{
  NSString *dir;
  NSString *env = [[[NSProcessInfo processInfo] environment]
                    objectForKey: @"GNUSTEP_USER_DEFAULTS_DIR"];
  if (env)
    dir = env;
  else
    dir = [NSHomeDirectory() stringByAppendingPathComponent: @"Library/Preferences"];
  return [dir stringByAppendingPathComponent: @"NSGlobalDomain.plist"];
}

static void pollDefaults(void)
{
  NSString *path = defaultsPlistPath();
  NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile: path];
  NSInteger mode;
  
  if (plist) {
    id val = [plist objectForKey: @"GSFilenameExtensionDisplayMode"];
    if (val) {
      mode = [val integerValue];
    } else {
      mode = GSFilenameExtensionHidePackageExtensions;
    }
  } else {
    mode = GSFilenameExtensionHidePackageExtensions;
  }
  
  if (mode < GSFilenameExtensionDisplayAll || mode > GSFilenameExtensionHideAll) {
    mode = GSFilenameExtensionHidePackageExtensions;
  }

  if (_displayModeCache == -1) {
    _displayModeCache = (GSFilenameExtensionDisplayMode)mode;
  } else if (_displayModeCache != (GSFilenameExtensionDisplayMode)mode) {
    NSLog(@"GSExt: mode changed from %ld to %ld", (long)_displayModeCache, (long)mode);
    _displayModeCache = (GSFilenameExtensionDisplayMode)mode;
    [[NSNotificationCenter defaultCenter]
      postNotificationName: NSUserDefaultsDidChangeNotification
                    object: [NSUserDefaults standardUserDefaults]];
  }
}

static void ensureDisplayModeObserver(void)
{
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                  dispatch_get_main_queue());
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                              2 * NSEC_PER_SEC, 0);
    dispatch_source_set_event_handler(t, ^{ pollDefaults(); });
    dispatch_resume(t);
  });
}

static NSSet *packageExtensions(void)
{
  static NSSet *exts = nil;
  if (exts == nil) {
    exts = [[NSSet alloc] initWithObjects:
      @"app", @"bundle", @"framework", @"plugin",
      @"prefPane", @"service", @"wdgt", @"qlgenerator",
      @"kext", @"xpc", @"ideplugin", @"metalsplugin",
      nil];
  }
  return exts;
}

BOOL
GSFilenameExtensionIsNumeric(NSString *ext)
{
  if ([ext length] == 0) {
    return NO;
  }
  NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
  return ([ext rangeOfCharacterFromSet: nonDigits].location == NSNotFound);
}

GSFilenameExtensionDisplayMode
GSCurrentExtensionDisplayMode(void)
{
  ensureDisplayModeObserver();
  if (_displayModeCache == -1) {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    [defs synchronize];
    NSInteger mode = [defs integerForKey: @"GSFilenameExtensionDisplayMode"];
    if (mode < GSFilenameExtensionDisplayAll || mode > GSFilenameExtensionHideAll) {
      mode = GSFilenameExtensionHidePackageExtensions;
    }
    _displayModeCache = (GSFilenameExtensionDisplayMode)mode;
  }
  return _displayModeCache;
}

BOOL
GSExtensionIsPackageExtension(NSString *extension)
{
  if ([extension length] == 0) {
    return NO;
  }
  return [packageExtensions() containsObject: [extension lowercaseString]];
}

NSString *
GSDisplayNameForFilename(NSString *filename, GSFilenameExtensionDisplayMode mode)
{
  if ([filename length] == 0 || [filename hasPrefix: @"."]) {
    return filename;
  }
  if (mode == GSFilenameExtensionDisplayAll) {
    return filename;
  }
  if (mode == GSFilenameExtensionHidePackageExtensions) {
    NSString *ext = [filename pathExtension];
    if ([ext length] > 0 && GSExtensionIsPackageExtension(ext) && !GSFilenameExtensionIsNumeric(ext)) {
      NSString *stripped = [filename substringToIndex: [filename length] - [ext length] - 1];
      if ([stripped length] > 0) {
        return stripped;
      }
    }
    return filename;
  }
  // GSFilenameExtensionHideAll
  {
    static NSSet *compoundExts = nil;
    if (compoundExts == nil) {
      compoundExts = [[NSSet alloc] initWithObjects:
        @"tar.gz", @"tar.bz2", @"tar.xz", @"tar.lz",
        @"tar.lzma", @"tar.zst", @"tar.Z",
        @"user.js", nil];
    }
    for (NSString *cext in compoundExts) {
      if ([filename hasSuffix: @"."] == NO && [filename length] > [cext length]
          && [[filename substringFromIndex: [filename length] - [cext length]] isEqualToString: cext]) {
        return [filename substringToIndex: [filename length] - [cext length]];
      }
    }
    NSString *ext = [filename pathExtension];
    if ([ext length] > 0 && !GSFilenameExtensionIsNumeric(ext)) {
      return [filename substringToIndex: [filename length] - [ext length] - 1];
    }
  }
  return filename;
}

NSString *
GSFilenameHiddenExtension(NSString *filename, GSFilenameExtensionDisplayMode mode)
{
  if ([filename length] == 0 || [filename hasPrefix: @"."]) {
    return @"";
  }
  if (mode == GSFilenameExtensionDisplayAll) {
    return @"";
  }
  if (mode == GSFilenameExtensionHidePackageExtensions) {
    NSString *ext = [filename pathExtension];
    if ([ext length] > 0 && GSExtensionIsPackageExtension(ext) && !GSFilenameExtensionIsNumeric(ext)) {
      return [@"." stringByAppendingString: ext];
    }
    return @"";
  }
  // GSFilenameExtensionHideAll
  {
    static NSSet *compoundExts = nil;
    if (compoundExts == nil) {
      compoundExts = [[NSSet alloc] initWithObjects:
        @"tar.gz", @"tar.bz2", @"tar.xz", @"tar.lz",
        @"tar.lzma", @"tar.zst", @"tar.Z",
        @"user.js", nil];
    }
    for (NSString *cext in compoundExts) {
      if ([filename hasSuffix: @"."] == NO && [filename length] > [cext length]
          && [[filename substringFromIndex: [filename length] - [cext length]] isEqualToString: cext]) {
        return cext;
      }
    }
    NSString *ext = [filename pathExtension];
    if ([ext length] > 0 && !GSFilenameExtensionIsNumeric(ext)) {
      return [@"." stringByAppendingString: ext];
    }
  }
  return @"";
}

NSString *path_separator(void)
{
  static NSString *separator = nil;

  if (separator == nil) {
    #if defined(__MINGW32__)
      separator = @"\\";	
    #else
      separator = @"/";	
    #endif
  }

  return separator;
}

/*
 * p1 is parent of p2
 */
BOOL isSubpathOfPath(NSString *p1, NSString *p2)
{
  int l1 = [p1 length];
  int l2 = [p2 length];  

  if ((l1 > l2) || ([p1 isEqualToString: p2])) {
    return NO;
  } else if ([[p2 substringToIndex: l1] isEqualToString: p1]) {
    if ([[p2 pathComponents] containsObject: [p1 lastPathComponent]]) {
      return YES;
    }
  }

  return NO;
}

BOOL pathsAreOnSameVolume(NSString *path1, NSString *path2)
{
  struct stat s1, s2;

  if (stat([path1 fileSystemRepresentation], &s1) != 0) {
    return NO;
  }
  if (stat([path2 fileSystemRepresentation], &s2) != 0) {
    return NO;
  }

  return (s1.st_dev == s2.st_dev);
}

NSString *subtractFirstPartFromPath(NSString *path, NSString *firstpart)
{
	if ([path isEqual: firstpart] == NO) {
    return [path substringFromIndex: [path rangeOfString: firstpart].length +1];
  }
	return path_separator();
}

NSComparisonResult compareWithExtType(id r1, id r2, void *context)
{
  FSNInfoType t1 = [(id <FSNodeRep>)r1 nodeInfoShowType];
  FSNInfoType t2 = [(id <FSNodeRep>)r2 nodeInfoShowType];

  if (t1 == FSNInfoExtendedType) {
    if (t2 != FSNInfoExtendedType) {
      return NSOrderedDescending;
    }
  } else {
    if (t2 == FSNInfoExtendedType) {
      return NSOrderedAscending;
    }
  }

  return NSOrderedSame;
}

#define ONE_KB 1024LLU
#define ONE_MB (ONE_KB * ONE_KB)
#define ONE_GB (ONE_KB * ONE_MB)
#define ONE_TB (ONE_KB * ONE_GB)

NSString *sizeDescription(unsigned long long size)
{
  NSString *sizeStr;

  if (size == 1)
    sizeStr = @"1 byte";
  else if (size == 0)
    sizeStr = @"0 bytes";
  else if (size < (ONE_KB))
    sizeStr = [NSString stringWithFormat:@" %ld bytes", (long)size];
  else if (size < (ONE_MB))
    sizeStr = [NSString stringWithFormat:@" %3.2fKB", ((double)size / (double)(ONE_KB))];
  else if (size < (ONE_GB))
    sizeStr = [NSString stringWithFormat:@" %3.2fMB", ((double)size / (double)(ONE_MB))];
  else if (size < (ONE_TB))
    sizeStr = [NSString stringWithFormat:@" %3.2fGB", ((double)size / (double)(ONE_GB))];
  else
    sizeStr = [NSString stringWithFormat:@" %3.2fTB", ((double)size / (double)(ONE_TB))];

  return sizeStr;
}

NSArray *makePathsSelection(NSArray *selnodes)
{
  NSMutableArray *selpaths = [NSMutableArray array]; 
  NSUInteger i;

  for (i = 0; i < [selnodes count]; i++) {
    [selpaths addObject: [[selnodes objectAtIndex: i] path]];
  }
  
  return selpaths;
}

double myrintf(double a)
{
  return (floor(a + 0.5));
}


NSDragOperation dragOperationForCurrentModifierFlags(void)
{
  NSUInteger flags = [NSEvent modifierFlags];

  /* Meta → Option → NSAlternateKeyMask → Copy */
  if (flags & NSAlternateKeyMask)
    {
      return NSDragOperationCopy;
    }
  /* Alt → Command → NSCommandKeyMask → Link */
  if (flags & NSCommandKeyMask)
    {
      return NSDragOperationLink;
    }

  /* No relevant modifier → let caller apply volume-based default */
  return NSDragOperationMove;
}

/* --- Text Field Editing Error Messages */

void showAlertNoPermission(Class c, NSString *name)
{
  NSRunAlertPanel(
                  NSLocalizedStringFromTableInBundle(@"Error", nil, [NSBundle bundleForClass:c], @""), 
                  [NSString stringWithFormat: @"%@ \"%@\"!\n", 
                            NSLocalizedStringFromTableInBundle(@"You do not have write permission for", nil, [NSBundle bundleForClass:c], @""), 
                            name],
                  NSLocalizedStringFromTableInBundle(@"Continue", nil, [NSBundle bundleForClass:c], @""),
                  nil, nil);   
}

void showAlertInRecycler(Class c)
{
  NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Error", nil, [NSBundle bundleForClass:c], @""),
                  NSLocalizedStringFromTableInBundle(@"You can't rename an object that is in the Recycler", nil, [NSBundle bundleForClass:c], @""),
                  NSLocalizedStringFromTableInBundle(@"Continue", nil, [NSBundle bundleForClass:c], @"")
                  , nil, nil);   
}

void showAlertInvalidName(Class c)
{
  NSDebugLLog(@"gwspace", @"Class %@ Bundle %@", c, [NSBundle bundleForClass:c]);
  NSRunAlertPanel(NSLocalizedStringFromTableInBundle(@"Error", nil, [NSBundle bundleForClass:c], @""),
                  NSLocalizedStringFromTableInBundle(@"Invalid name", nil, [NSBundle bundleForClass:c], @""),
                  NSLocalizedStringFromTableInBundle(@"Continue", nil, [NSBundle bundleForClass:c], @""),
                  nil, nil);  
}

NSInteger showAlertExtensionChange(Class c, NSString *extension)
{
  NSString *msg;
  NSInteger r;

  msg = NSLocalizedStringFromTableInBundle(@"Are you sure you want to add the extension", nil, [NSBundle bundleForClass:c], @"");

  msg = [msg stringByAppendingFormat: @"\"%@\" ", extension];
  msg = [msg stringByAppendingString: NSLocalizedStringFromTableInBundle(@"to the end of the name?", nil, [NSBundle bundleForClass:c], @"")];
  msg = [msg stringByAppendingString: NSLocalizedStringFromTableInBundle(@"\nif you make this change, your folder may appear as a single file.", nil, [NSBundle bundleForClass:c], @"")];

  r = NSRunAlertPanel(@"", msg, 
                      NSLocalizedStringFromTableInBundle(@"Cancel", nil, [NSBundle bundleForClass:c], @""), 
                      NSLocalizedStringFromTableInBundle(@"OK", nil, [NSBundle bundleForClass:c], @""), 
                      nil);
  return r;
}

void showAlertNameInUse(Class c, NSString *newname)
{
  NSRunAlertPanel(
                  NSLocalizedStringFromTableInBundle(@"Error", nil, [NSBundle bundleForClass:c], @""),
                  [NSString stringWithFormat: @"%@\"%@\" %@ ", 
                            NSLocalizedStringFromTableInBundle(@"The name ", nil, [NSBundle bundleForClass:c], @""),
                            newname,
                            NSLocalizedStringFromTableInBundle(@" is already in use!", nil, [NSBundle bundleForClass:c], @"")], 
                  NSLocalizedStringFromTableInBundle(@"Continue", nil, [NSBundle bundleForClass:c], @""), nil, nil); 
}


void
FSNDrawLabelDot(NSRect dotRect, NSColor *color)
{
  if (color == nil)
    return;

  /* Drop shadow */
  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.3] set];
  [[NSBezierPath bezierPathWithOvalInRect: NSOffsetRect(dotRect, 1, -1)] fill];

  /* Filled dot */
  [color set];
  NSBezierPath *dp = [NSBezierPath bezierPathWithOvalInRect: dotRect];
  [dp fill];

  /* Hairline border */
  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.4] set];
  [dp setLineWidth: 0.5];
  [dp stroke];
}
