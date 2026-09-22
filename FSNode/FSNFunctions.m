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
#ifdef __GLIBC__
#include <malloc.h>
#endif

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "FSNFunctions.h"
#import "FSNAlias.h"
#import "FSNodeRep.h"

static GSFilenameExtensionDisplayMode _displayModeCache = -1;

/* The mode as the defaults have it.  The first reading and every later poll
 * must come from the same place: a poll that read only the user's own
 * NSGlobalDomain file missed a system-wide setting the first reading had
 * seen, so every label changed a moment after launch. */
static GSFilenameExtensionDisplayMode modeFromDefaults(void)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  id val;
  NSInteger mode;

  /* Picks up a change the Workspace preferences wrote from another
   * process. */
  [defs synchronize];
  val = [defs objectForKey: @"GSFilenameExtensionDisplayMode"];
  mode = (val != nil) ? [val integerValue] : GSFilenameExtensionHidePackageExtensions;

  if (mode < GSFilenameExtensionDisplayAll || mode > GSFilenameExtensionHideAll)
    mode = GSFilenameExtensionHidePackageExtensions;

  return (GSFilenameExtensionDisplayMode)mode;
}

static void pollDefaults(void)
{
  GSFilenameExtensionDisplayMode mode = modeFromDefaults();

  if (_displayModeCache == -1) {
    _displayModeCache = mode;
  } else if (_displayModeCache != mode) {
    NSLog(@"GSExt: mode changed from %ld to %ld", (long)_displayModeCache, (long)mode);
    _displayModeCache = mode;
    [[NSNotificationCenter defaultCenter]
      postNotificationName: NSUserDefaultsDidChangeNotification
                    object: [NSUserDefaults standardUserDefaults]];
  }
}

static void ensureDisplayModeObserver(void)
{
  static BOOL observerScheduled = NO;

  if (observerScheduled == NO)
    {
      observerScheduled = YES;
      /* Poll the defaults plist for an external change of the display mode
       * preference (e.g. written by the Workspace prefs panel).  A repeating
       * timer on the main run loop replaces the old libdispatch source, so
       * FSNode keeps no dependency on libdispatch/GCD. */
      [NSTimer scheduledTimerWithTimeInterval: 2.0
                                      repeats: YES
                                        block: ^(NSTimer *timer) {
                                          pollDefaults();
                                        }];
    }
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
  /* -invertedSet copies the whole Unicode bitmap, some 139 KB, so building it
     per call costs that much per directory entry while a folder loads. */
  static NSCharacterSet *nonDigits = nil;

  if ([ext length] == 0) {
    return NO;
  }
  if (nonDigits == nil) {
    nonDigits = [[[NSCharacterSet decimalDigitCharacterSet] invertedSet] retain];
  }
  return ([ext rangeOfCharacterFromSet: nonDigits].location == NSNotFound);
}

GSFilenameExtensionDisplayMode
GSCurrentExtensionDisplayMode(void)
{
  ensureDisplayModeObserver();
  if (_displayModeCache == -1) {
    _displayModeCache = modeFromDefaults();
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
      /* The dot in front of the extension belongs to it, so cut one more
         character; otherwise the name is shown with a trailing dot. */
      NSUInteger keep;

      if ([filename length] <= [cext length] + 1) {
        continue;
      }
      keep = [filename length] - [cext length] - 1;
      if ([filename characterAtIndex: keep] == '.'
          && [[filename substringFromIndex: keep + 1] isEqualToString: cext]) {
        return [filename substringToIndex: keep];
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


BOOL
FSNLinkDropCreatesAlias(void)
{
  NSUInteger flags = [NSEvent modifierFlags];

  return (flags & NSCommandKeyMask) && (flags & NSAlternateKeyMask);
}

NSString *
FSNLinkDropOperation(void)
{
  if (FSNLinkDropCreatesAlias())
    {
      return FSNWorkspaceCreateAliasOperation;
    }
  return NSWorkspaceLinkOperation;
}

NSDragOperation dragOperationForCurrentModifierFlags(void)
{
  NSUInteger flags = [NSEvent modifierFlags];

  /* Command+Alternate → Alias drop; the destination still negotiates
   * NSDragOperationLink, FSNLinkDropOperation() tells the two apart. */
  if ((flags & NSCommandKeyMask) && (flags & NSAlternateKeyMask))
    {
      return NSDragOperationLink;
    }
  /* Option → Copy */
  if (flags & NSAlternateKeyMask)
    {
      return NSDragOperationCopy;
    }
  /* Command → Link */
  if (flags & NSCommandKeyMask)
    {
      return NSDragOperationLink;
    }

  /* No relevant modifier → let caller apply volume-based default */
  return NSDragOperationMove;
}

NSImage *
FSNLinkBadgedImage(NSImage *image)
{
  NSSize size = [image size];
  CGFloat badge = MAX(16.0, MIN(size.width, size.height) * 0.4);
  NSImage *badged;

  badged = [[NSImage alloc] initWithSize: size];
  [badged lockFocus];
  [image drawAtPoint: NSMakePoint(0, 0)
	     fromRect: NSMakeRect(0, 0, size.width, size.height)
	    operation: NSCompositeSourceOver
	     fraction: 1.0];

  /* Classic alias arrow in the lower-left corner: white outline,
   * black shaft, pointing to the upper left. */
  {
    CGFloat x = badge * 0.15;
    CGFloat y = x;
    NSBezierPath *shaft = [NSBezierPath bezierPath];
    NSBezierPath *arrowhead = [NSBezierPath bezierPath];
    NSPoint head[3] = { NSMakePoint(x + badge * 0.0, y + badge * 0.9),
			NSMakePoint(x + badge * 0.55, y + badge * 0.62),
			NSMakePoint(x + badge * 0.28, y + badge * 0.35) };

    /* Shaft: diagonal bar from lower right of the badge area up-left. */
    [shaft moveToPoint: NSMakePoint(x + badge * 0.85, y + badge * 0.15)];
    [shaft lineToPoint: NSMakePoint(x + badge * 0.25, y + badge * 0.75)];
    [shaft setLineCapStyle: NSRoundLineCapStyle];

    [[NSColor whiteColor] setStroke];
    [shaft setLineWidth: badge * 0.34];
    [shaft stroke];

    [[NSColor blackColor] setStroke];
    [shaft setLineWidth: badge * 0.2];
    [shaft stroke];

    /* Head: solid triangle at the upper-left end of the shaft. */
    [arrowhead appendBezierPathWithPoints: head count: 3];
    [arrowhead closePath];
    [[NSColor whiteColor] setStroke];
    [arrowhead setLineWidth: badge * 0.12];
    [arrowhead stroke];
    [[NSColor blackColor] setFill];
    [arrowhead fill];
  }

  [badged unlockFocus];
  return [badged autorelease];
}

NSImage *
FSNGitBadgedImage(NSImage *image, NSImage *logo)
{
  if (image == nil)
    {
      return nil;
    }

  NSSize sz = [image size];

  /* Read the base icon as a bitmap.  imageRepWithData: returns a rep whose
   * bitmapData is read-only (it is backed by the TIFF buffer), so we must
   * NOT write into it.  We copy the pixels into a bitmap WE allocate
   * (writable) and apply the darkening while copying. */
  NSBitmapImageRep *srcRep =
    [NSBitmapImageRep imageRepWithData: [image TIFFRepresentation]];
  if (srcRep == nil || [srcRep samplesPerPixel] < 3 || [srcRep isPlanar])
    {
      return [[image copy] autorelease];
    }

  /* No logo: nothing to overlay, return the original icon cheaply. */
  if (logo == nil)
    {
      return [[image copy] autorelease];
    }

  NSInteger w = [srcRep pixelsWide];
  NSInteger h = [srcRep pixelsHigh];

  /* Half the icon, aspect-preserving.  Anchored toward the bottom via the
   * golden ratio (badge centre at (1 - 1/phi) of the height from the bottom),
   * then lifted a further 2% of the icon height so it sits centred on the
   * front of the folder instead of poking into the tab. */
  const CGFloat golden = 0.6180339887498949;
  const CGFloat upShift = 0.02;   /* fraction of icon height to lift */
  const CGFloat strength = 0.35;  /* subtle darkening where the logo is dark;
                                   * white/transparent logo areas are left
                                   * untouched (no hue shift). */
  CGFloat badge = 0.5 * MIN (sz.width, sz.height);
  NSSize ls = [logo size];
  CGFloat scale = (ls.width > 0 && ls.height > 0)
                    ? MIN (badge / ls.width, badge / ls.height)
                    : 1.0;
  CGFloat dw = ls.width * scale;
  CGFloat dh = ls.height * scale;
  CGFloat cx = sz.width / 2.0;
  CGFloat cyFromBottom = sz.height * (1.0 - golden) + sz.height * upShift;
  NSRect dest = NSMakeRect (cx - dw / 2.0, cyFromBottom - dh / 2.0, dw, dh);

      /* Cache the logo's bitmap rep; the NSImage (from the extension) is reused
       * for every git folder, so decode it only when it changes.  Both the
       * cached rep and the logo must be RETAINED: they come from autoreleased
       * calls, and a static must not hold a dangling pointer after the current
       * autorelease pool drains (that dangling pointer was causing a crash on
       * the second selection of a git folder). */
      static NSBitmapImageRep *cachedLogoRep = nil;
      static NSImage *cachedLogoImg = nil;
      if (logo != cachedLogoImg)
        {
          [cachedLogoRep release];
          cachedLogoRep =
            [[NSBitmapImageRep imageRepWithData: [logo TIFFRepresentation]] retain];
          [cachedLogoImg release];
          cachedLogoImg = [logo retain];
        }
  NSBitmapImageRep *logoRep = cachedLogoRep;

  if (logoRep == nil || [logoRep isPlanar] || [logoRep samplesPerPixel] < 1)
    {
      return [[image copy] autorelease];
    }

  /* Build a writable RGBA bitmap and copy the base icon into it, darkening
   * only where the logo's own pixels are dark. */
  NSBitmapImageRep *dstRep =
    [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                            pixelsWide: w
                                            pixelsHigh: h
                                         bitsPerSample: 8
                                       samplesPerPixel: 4
                                              hasAlpha: YES
                                              isPlanar: NO
                                        colorSpaceName: NSDeviceRGBColorSpace
                                           bytesPerRow: 0
                                          bitsPerPixel: 0];

  unsigned char *sdata = [srcRep bitmapData];
  NSInteger sRow = [srcRep bytesPerRow];
  NSInteger sSpp = [srcRep samplesPerPixel];
  unsigned char *ddata = [dstRep bitmapData];
  NSInteger dRow = [dstRep bytesPerRow];

  NSInteger lw = [logoRep pixelsWide];
  NSInteger lh = [logoRep pixelsHigh];
  NSInteger lSpp = [logoRep samplesPerPixel];
  NSInteger lRowBytes = [logoRep bytesPerRow];
  unsigned char *ldata = [logoRep bitmapData];

  NSInteger x0 = (NSInteger) floor (dest.origin.x);
  NSInteger x1 = (NSInteger) ceil (dest.origin.x + dw);
  /* y-up, like dest; compared against yUp below, not the top-down row. */
  NSInteger y0 = (NSInteger) floor (dest.origin.y);
  NSInteger y1 = (NSInteger) ceil (dest.origin.y + dh);
  x0 = MAX (0, x0); x1 = MIN (w, x1);
  y0 = MAX (0, y0); y1 = MIN (h, y1);

  NSInteger x;
  for (x = 0; x < w; x++)
    {
      NSInteger y;
      for (y = 0; y < h; y++)
        {
          /* src and dst are both top-down (row 0 = top).  The badge geometry
           * is expressed y-up (0 = bottom), so convert for the logo lookup. */
          unsigned char *sp = sdata + y * sRow + x * sSpp;
          unsigned char *dp = ddata + y * dRow + x * 4;
          unsigned char sa = (sSpp >= 4) ? sp[3] : 255;
          CGFloat sr = sp[0];
          CGFloat sg = sp[1];
          CGFloat sb = sp[2];

          NSInteger yUp = h - 1 - y;
          if (x >= x0 && x < x1 && yUp >= y0 && yUp < y1)
            {
              CGFloat fx = (CGFloat) (x - dest.origin.x) / dw;
              CGFloat fyUp = (CGFloat) (yUp - dest.origin.y) / dh;
              NSInteger lx = (NSInteger) (fx * (lw - 1));
              NSInteger lv = (NSInteger) ((1.0 - fyUp) * (lh - 1));
              lx = MAX (0, MIN (lx, lw - 1));
              lv = MAX (0, MIN (lv, lh - 1));

              unsigned char *lp = ldata + lv * lRowBytes + lx * lSpp;
              unsigned char la = (lSpp >= 4) ? lp[3] : 255;
              CGFloat lr, lg, lb;
              if (lSpp >= 3)
                {
                  lr = lp[0]; lg = lp[1]; lb = lp[2];
                }
              else if (lSpp == 2)
                {
                  lr = lg = lb = lp[0]; la = lp[1];
                }
              else
                {
                  lr = lg = lb = lp[0];
                }
              CGFloat lum = (0.299 * lr + 0.587 * lg + 0.114 * lb) / 255.0;
              CGFloat alpha = la / 255.0;

              /* Only the logo's own dark, opaque pixels darken the icon. */
              CGFloat dark = (1.0 - lum) * alpha * strength;
              if (dark > 0.0)
                {
                  sr *= (1.0 - dark);
                  sg *= (1.0 - dark);
                  sb *= (1.0 - dark);
                }
            }

          dp[0] = (unsigned char) sr;
          dp[1] = (unsigned char) sg;
          dp[2] = (unsigned char) sb;
          dp[3] = sa;
        }
    }

  NSImage *result = [[NSImage alloc] initWithSize: sz];
  [result addRepresentation: dstRep];
  [dstRep release];
  return [result autorelease];
}

NSString *FSNBadgeCountDidChangeNotification = @"FSNBadgeCountDidChangeNotification";

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

NSString *GSDirectoryDescriptionForPath(NSString *path);
static NSString *GSDirectoryDescriptionExactMatch(NSDictionary *cached,
                                                  NSString *path);
/* The wildcard keys of the table, longest first, so the first one that
 * matches is also the most specific.  Kept apart from the table because a
 * folder asks for a description once per entry, and picking the wildcard
 * keys out of all 467 keys every time was the largest single cost of
 * opening a folder. */
static NSArray *directoryDescriptionGlobKeys = nil;
static BOOL GSDirectoryGlobMatch(NSString *pattern, NSString *string);

NSString *
GSDirectoryDescriptionForPath(NSString *path)
{
  if ([path length] == 0)
    return nil;

  static NSDictionary *cached = nil;
  static BOOL cacheBuilt = NO;

  if (cacheBuilt == NO)
    {
      /* Build the description table once.  The first caller initializes it;
       * there is no libdispatch dependency (dispatch_once) here. */
      cacheBuilt = YES;
      NSBundle *bundle = [NSBundle bundleForClass: [FSNodeRep class]];
      NSString *plistPath = [bundle pathForResource: @"WellKnownLocations"
                                            ofType: @"plist"];
      NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile: plistPath];
      if (raw == nil)
        {
          cached = nil;
        }
      else
        {
          NSMutableDictionary *expanded = [NSMutableDictionary dictionary];
          NSString *home = NSHomeDirectory();
          NSDictionary *domains = @{
            @"$System":  @"/System",
            @"$Local":   @"/Local",
            @"$Network": @"/Network",
            @"$User":    home
          };

          for (NSString *key in raw)
            {
              NSString *desc = [raw objectForKey: key];
              NSString *resolved = key;
              for (NSString *var in domains)
                {
                  if ([resolved hasPrefix: var])
                    {
                      NSString *suffix = [resolved substringFromIndex: [var length]];
                      resolved = [[domains objectForKey: var] stringByAppendingString: suffix];
                      break;
                    }
                }
              [expanded setObject: desc forKey: resolved];
            }

          cached = [expanded copy];
          directoryDescriptionGlobKeys = [[[expanded allKeys]
            filteredArrayUsingPredicate:
              [NSPredicate predicateWithFormat: @"SELF CONTAINS '*'"]]
            sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
              NSUInteger la = [(NSString *)a length];
              NSUInteger lb = [(NSString *)b length];

              if (la > lb) return NSOrderedAscending;
              if (la < lb) return NSOrderedDescending;
              return NSOrderedSame;
            }];
          RETAIN (directoryDescriptionGlobKeys);
        }
    }

  /* Prefer a description for the path as given: e.g. /sys/class/net/wlan0 is
   * a symlink into /sys/devices/..., but the class-specific description is
   * far more useful than the generic device-tree one.  Only when the given
   * path has no entry do we follow symlinks and use the target's description
   * (which handles real symlinks such as /var/run -> /run). */
  NSString *direct = GSDirectoryDescriptionExactMatch(cached, path);
  if (direct)
    return direct;

  NSString *resolved = [path stringByResolvingSymlinksInPath];
  if (resolved && [resolved isEqualToString: path] == NO)
    {
      NSString *targetDesc = GSDirectoryDescriptionExactMatch(cached, resolved);
      if (targetDesc)
        return targetDesc;
    }

  return nil;
}

/* Exact match plus wildcard fallback: keys may contain '*' which matches
 * any run of characters (e.g. "/dev/tty*" matches "/dev/tty0", and
 * "/dev/nvme*n*p*" matches "/dev/nvme0n1p1").  When several wildcards
 * match, the longest (most specific) key wins. */
static NSString *GSDirectoryDescriptionExactMatch(NSDictionary *cached,
                                                  NSString *path)
{
  NSString *exact = [cached objectForKey: path];
  if (exact)
    return exact;

  NSUInteger i;

  for (i = 0; i < [directoryDescriptionGlobKeys count]; i++)
    {
      NSString *key = [directoryDescriptionGlobKeys objectAtIndex: i];

      if (GSDirectoryGlobMatch(key, path))
        return [cached objectForKey: key];
    }

  return nil;
}

/* Classic '*' glob match (only '*' is special; '.' and '/' are literal). */
static BOOL GSDirectoryGlobMatch(NSString *pattern, NSString *string)
{
  NSUInteger p = 0, s = 0;
  NSUInteger starP = NSNotFound, starS = 0;
  NSUInteger plen = [pattern length], slen = [string length];

  while (s < slen)
    {
      unichar pc = (p < plen) ? [pattern characterAtIndex: p] : 0;
      unichar sc = [string characterAtIndex: s];

      if (pc == '*')
        {
          starP = p;
          starS = s;
          p++;
        }
      else if (pc == sc)
        {
          p++;
          s++;
        }
      else if (starP != NSNotFound)
        {
          p = starP + 1;
          s = ++starS;
        }
      else
        {
          return NO;
        }
    }

  while (p < plen && [pattern characterAtIndex: p] == '*')
    p++;

  return (p == plen);
}

/* The alpha, in 256ths, up to which the X backend leaves a pixel out of a
 * window's shape (ALPHA_THRESHOLD in libs-back's XGServerWindow.m). */
static const CGFloat FSNShapeAlphaThreshold = 158;

NSImage *FSNShapeableImage(NSImage *picture, CGFloat scale)
{
  NSSize size = [picture size];
  NSBitmapImageRep *drawn;
  NSBitmapImageRep *bitmap;
  NSImage *image;
  NSInteger w, h, x, y;

  /* The window server can only read transparency from a bitmap: from a
   * cached picture it got none, and the window stayed a rectangle showing
   * whatever had been on the screen beneath it. */
  [picture lockFocus];
  drawn = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect:
    NSMakeRect(0, 0, size.width, size.height)]);
  [picture unlockFocus];

  /* At the window's size in pixels: a bitmap of the size in points, drawn
   * scaled up, was cut by a shape that no longer fitted it.  Pixels only
   * partly covered - the soft edge of an icon or a letter - have nothing
   * beneath them to blend with and showed leftovers of the screen, so each
   * is made shown or not, cut where the window server cuts the shape. */
  w = MAX (1, (NSInteger)lrint(size.width * scale));
  h = MAX (1, (NSInteger)lrint(size.height * scale));
  bitmap = AUTORELEASE ([[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL
                  pixelsWide: w
                  pixelsHigh: h
               bitsPerSample: 8
             samplesPerPixel: 4
                    hasAlpha: YES
                    isPlanar: NO
              colorSpaceName: NSDeviceRGBColorSpace
                 bytesPerRow: 0
                bitsPerPixel: 0]);

  for (y = 0; y < h; y++)
    {
      for (x = 0; x < w; x++)
        {
          NSInteger sx = MIN ((NSInteger)(x * [drawn pixelsWide] / w),
                              [drawn pixelsWide] - 1);
          NSInteger sy = MIN ((NSInteger)(y * [drawn pixelsHigh] / h),
                              [drawn pixelsHigh] - 1);
          NSColor *c = [[drawn colorAtX: sx y: sy]
                         colorUsingColorSpaceName: NSDeviceRGBColorSpace];
          CGFloat a = [c alphaComponent];

          if (a * 256 <= FSNShapeAlphaThreshold)
            c = [NSColor colorWithDeviceRed: 0 green: 0 blue: 0 alpha: 0];
          else if (a < 1.0)
            c = [[NSColor whiteColor] blendedColorWithFraction: a
                                                       ofColor: [c colorWithAlphaComponent: 1.0]];

          [bitmap setColor: c atX: x y: y];
        }
    }

  /* Its size in points, so that it covers its window exactly. */
  [bitmap setSize: size];
  image = AUTORELEASE ([[NSImage alloc] initWithSize: size]);
  [image setBackgroundColor: [NSColor clearColor]];
  [image addRepresentation: bitmap];

  return image;
}

void FSNReleaseFreedHeapMemory(void)
{
#ifdef __GLIBC__
  /* glibc gives memory back only from the top of the heap.  After a burst
     of short-lived allocations the freed pages below a surviving object
     stay resident for the life of the process (about 25 MB in Workspace
     after launch).  The allocators of the BSDs return such pages on their
     own, so there is nothing to do there. */
  malloc_trim(0);
#endif
}

void FSNPutBackDequeuedEvent(NSWindow *window, NSEvent *event)
{
  /* At the end of the queue the event would come after everything a busy
   * app already has waiting behind it.  For a mouse-up that is fatal to a
   * double click: the second press is handled first, the window gives the
   * first release to the view in its place (NSWindow keeps only the view of
   * the last press), and the second release, the one that opens the item,
   * reaches no view. */
  [window postEvent: event atStart: YES];
}

NSEvent *FSNNextMouseUpOrDraggedEvent(NSWindow *window)
{
  NSEvent *event = [window nextEventMatchingMask:
			     NSLeftMouseUpMask | NSLeftMouseDraggedMask];

  if ([event type] == NSLeftMouseUp)
    {
      FSNPutBackDequeuedEvent(window, event);
    }
  return event;
}
