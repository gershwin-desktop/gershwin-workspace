/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A file whose Finder metadata says "hide extension" is shown without it in
 * the icon, list and browser views (all three take the name from
 * -[FSNode displayName]), unless the user chose to show all extensions.
 * The metadata provider is a test double; its selectors are optional. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "FSNMetadataProvider.h"

@interface HidingProvider : NSObject <FSNMetadataProvider>
{
@public
  NSMutableSet *hidden;
}
@end

@implementation HidingProvider
- (id)init
{
  self = [super init];
  hidden = [NSMutableSet new];
  return self;
}
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSMakePoint(-1, -1); }
- (void)invalidateCaches {}
- (BOOL)isExtensionHiddenForPath:(NSString *)path
{
  return [hidden containsObject: path];
}
@end

/* A provider that predates the selector: must behave as "not hidden". */
@interface OldProvider : NSObject <FSNMetadataProvider>
@end

@implementation OldProvider
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSMakePoint(-1, -1); }
- (void)invalidateCaches {}
@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_FSNHiddenExtension_%d", (int)getpid ()]];
  NSString *txt = [dir stringByAppendingPathComponent: @"report.txt"];
  NSString *plain = [dir stringByAppendingPathComponent: @"README"];
  NSString *dotted = [dir stringByAppendingPathComponent: @".bashrc"];
  NSString *multi = [dir stringByAppendingPathComponent: @"a.b.txt"];
  FSNodeRep *rep;
  HidingProvider *provider = [HidingProvider new];
  OldProvider *old = [OldProvider new];
  FSNode *node;

  /* The tester's own global preference must not decide the outcome; the
   * display mode is cached on first use. */
  [[NSUserDefaults standardUserDefaults] setInteger: GSFilenameExtensionHidePackageExtensions
                                             forKey: @"GSFilenameExtensionDisplayMode"];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [@"x" writeToFile: txt atomically: YES];
  [@"x" writeToFile: plain atomically: YES];
  [@"x" writeToFile: dotted atomically: YES];
  [@"x" writeToFile: multi atomically: YES];

  /* --- pure function: the per-file bit against the global mode ------- */

  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"report.txt", GSFilenameExtensionHidePackageExtensions, YES),
              @"report", "MI-FSN-1 the per-file bit hides a plain extension in the default mode");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"report.txt", GSFilenameExtensionHidePackageExtensions, NO),
              @"report.txt", "MI-FSN-2 without the bit the default mode keeps it");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"report.txt", GSFilenameExtensionDisplayAll, YES),
              @"report.txt", "MI-FSN-3 the global show-all-extensions mode wins over the bit");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"report.txt", GSFilenameExtensionHideAll, NO),
              @"report", "MI-FSN-4 the global hide-all mode still hides without the bit");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"Foo.app", GSFilenameExtensionHidePackageExtensions, NO),
              @"Foo", "MI-FSN-5 the package mode behaviour stays");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"a.b.txt", GSFilenameExtensionHidePackageExtensions, YES),
              @"a.b", "MI-FSN-6 only the last extension is hidden");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"README", GSFilenameExtensionHidePackageExtensions, YES),
              @"README", "MI-FSN-7 a name without extension is unchanged");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@".bashrc", GSFilenameExtensionHidePackageExtensions, YES),
              @".bashrc", "MI-FSN-8 a dot file is not an extension");
  PASS_EQUAL (GSDisplayNameForFilenameHidingExtension (@"v1.2", GSFilenameExtensionHidePackageExtensions, YES),
              @"v1", "MI-FSN-9 the bit hides even a numeric extension, as Finder does");

  /* --- the rename commit: what an editor's text means ----------------- */

  PASS (GSRenamedFilename (@"report.txt", @"report.txt", GSFilenameExtensionHideAll) == nil,
        "MI-FSN-60 the editor's unchanged full name is no rename");
  PASS (GSRenamedFilename (@"report", @"report.txt", GSFilenameExtensionHideAll) == nil,
        "MI-FSN-61 the displayed name, unchanged, is no rename either");
  PASS_EQUAL (GSRenamedFilename (@"notes", @"report.txt", GSFilenameExtensionHideAll),
              @"notes.txt", "MI-FSN-62 a new base name keeps the hidden extension");
  PASS_EQUAL (GSRenamedFilename (@"notes.md", @"report.txt", GSFilenameExtensionHideAll),
              @"notes.md", "MI-FSN-63 text with its own extension is taken as typed");
  PASS_EQUAL (GSRenamedFilename (@"notes", @"report.txt", GSFilenameExtensionHidePackageExtensions),
              @"notes", "MI-FSN-64 nothing is hidden by the mode, nothing is appended");
  PASS_EQUAL (GSRenamedFilename (@"Bar", @"Foo.app", GSFilenameExtensionHidePackageExtensions),
              @"Bar.app", "MI-FSN-65 a package keeps its extension");
  PASS_EQUAL (GSRenamedFilename (@"", @"report.txt", GSFilenameExtensionHideAll),
              @".txt", "MI-FSN-66 empty text is left to the callers' validation");

  /* --- FSNodeRep and FSNode ------------------------------------------ */

  rep = [FSNodeRep sharedInstance];
  [rep setMetadataProvider: nil];
  PASS (![rep isExtensionHiddenForPath: txt], "MI-FSN-10 no provider: not hidden");
  node = [FSNode nodeWithPath: txt];
  PASS_EQUAL ([node displayName], @"report.txt", "MI-FSN-11 no provider: full display name");

  [rep setMetadataProvider: old];
  PASS (![rep isExtensionHiddenForPath: txt], "MI-FSN-12 a provider without the selector: not hidden");

  [rep setMetadataProvider: provider];
  [provider->hidden addObject: txt];
  [provider->hidden addObject: dotted];
  [provider->hidden addObject: multi];
  [provider->hidden addObject: plain];
  PASS ([rep isExtensionHiddenForPath: txt], "MI-FSN-13 the provider's answer is used");
  PASS (![rep isExtensionHiddenForPath: @"/nonexistent/other.txt"], "MI-FSN-14 other paths are not hidden");

  node = [FSNode nodeWithPath: txt];
  PASS_EQUAL ([node displayName], @"report", "MI-FSN-15 the display name drops the extension");
  PASS_EQUAL ([node name], @"report.txt", "MI-FSN-16 the real name keeps it, the rename editor shows it");
  PASS_EQUAL ([node lastPathComponent], @"report.txt", "MI-FSN-17 the never-translated name keeps it");
  PASS_EQUAL ([[FSNode nodeWithPath: multi] displayName], @"a.b", "MI-FSN-18 only the last one goes");
  PASS_EQUAL ([[FSNode nodeWithPath: plain] displayName], @"README", "MI-FSN-19 no extension, nothing to hide");
  PASS_EQUAL ([[FSNode nodeWithPath: dotted] displayName], @".bashrc", "MI-FSN-20 dot file stays");

  [provider->hidden removeObject: txt];
  PASS_EQUAL ([[FSNode nodeWithPath: txt] displayName], @"report.txt", "MI-FSN-21 clearing the bit shows it again");

  [rep setMetadataProvider: nil];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
