/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The global column view options (E30-E32): defaults, the keys they are
 * kept under, Finder's arrange-by codes and changes from outside. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNColumnViewOptions.h"

@interface Counter : NSObject
{
@public
  int count;
}
@end

@implementation Counter
- (void)changed:(NSNotification *)n
{
  count++;
}
@end

static NSArray *
allKeys(void)
{
  return [NSArray arrayWithObjects: FSNColumnViewTextSizeKey, FSNColumnViewShowsIconsKey,
                  FSNColumnViewShowsIconPreviewKey, FSNColumnViewShowsPreviewColumnKey,
                  FSNColumnViewArrangeByKey, FSNColumnViewColumnWidthKey, @"NSFontSize", nil];
}

static void
clearDefaults(void)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  NSEnumerator *e = [allKeys () objectEnumerator];
  NSString *key;

  while ((key = [e nextObject]) != nil)
    [defs removeObjectForKey: key];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  FSNColumnViewOptions *options;
  Counter *counter = [Counter new];
  Class C = [FSNColumnViewOptions class];

  /* This tool's own defaults domain; the NSFontSize of the app domain
   * hides whatever the user has globally. */
  clearDefaults ();
  [defs setInteger: 13 forKey: @"NSFontSize"];
  options = [FSNColumnViewOptions sharedOptions];
  [[NSNotificationCenter defaultCenter] addObserver: counter selector: @selector(changed:)
                                               name: FSNColumnViewOptionsDidChangeNotification
                                             object: options];

  /* --- Finder's codes ------------------------------------------------- */
  PASS ([C arrangementForFinderCode: @"dnam"] == FSNIconsArrangeName
        && [C arrangementForFinderCode: @"kipl"] == FSNIconsArrangeKind
        && [C arrangementForFinderCode: @"modd"] == FSNIconsArrangeDateModified
        && [C arrangementForFinderCode: @"ascd"] == FSNIconsArrangeDateCreated
        && [C arrangementForFinderCode: @"phys"] == FSNIconsArrangeSize
        && [C arrangementForFinderCode: @"labl"] == FSNIconsArrangeLabel,
        "MI-CLM-80 Finder's six ArrangeBy codes");
  PASS_EQUAL ([C finderCodeForArrangement: FSNIconsArrangeSize], @"phys",
              "MI-CLM-81 and back to the code");
  PASS ([C finderCodeForArrangement: FSNIconsArrangeNone] == nil
        && [C arrangementForFinderCode: @"xxxx"] == FSNIconsArrangeNone,
        "MI-CLM-82 None has no Finder code");

  /* --- defaults --------------------------------------------------------- */
  PASS ([options showsIcons] && [options showsIconPreview] && [options showsPreviewColumn],
        "MI-CLM-83 icons, icon preview and the preview column are on by default");
  PASS ([options arrangement] == FSNIconsArrangeName, "MI-CLM-84 arranged by name by default");
  PASS ([options columnWidth] == 205, "MI-CLM-85 columns are 205 points wide by default");
  PASS ([options textSize] == 13, "MI-CLM-86 without a text size of its own the NSFontSize is used");

  /* --- setters write typed values under their own keys ------------------ */
  [options setTextSize: 20];
  PASS ([options textSize] == 16 && [[defs objectForKey: FSNColumnViewTextSizeKey] intValue] == 16,
        "MI-CLM-87 the text size is held to 16 and kept");
  [options setShowsIcons: NO];
  PASS ([defs objectForKey: FSNColumnViewShowsIconsKey] != nil
        && [defs boolForKey: FSNColumnViewShowsIconsKey] == NO,
        "MI-CLM-88 show icons is kept under its own name");
  PASS ([defs objectForKey: FSNColumnViewShowsPreviewColumnKey] == nil,
        "MI-CLM-89 an option not changed is not written");
  [options setArrangement: FSNIconsArrangeSize];
  PASS_EQUAL ([defs stringForKey: FSNColumnViewArrangeByKey], @"phys",
              "MI-CLM-90 the arrangement is kept as Finder's code");
  [options setArrangement: FSNIconsArrangeNone];
  PASS ([options arrangement] == FSNIconsArrangeNone
        && [[defs stringForKey: FSNColumnViewArrangeByKey] isEqual: @"none"],
        "MI-CLM-91 None is kept too");
  [options setColumnWidth: 50.7];
  PASS ([options columnWidth] == 100 && [defs integerForKey: FSNColumnViewColumnWidthKey] == 100,
        "MI-CLM-92 a column width below 100 points is held at 100");
  PASS (counter->count == 5, "MI-CLM-93 every change is posted once");
  [options setColumnWidth: 100];
  PASS (counter->count == 5, "MI-CLM-94 setting the same value posts nothing");

  /* --- changes from outside, e.g. defaults write or an Integrator ------- */
  [defs setInteger: 300 forKey: FSNColumnViewColumnWidthKey];
  [defs setObject: @"kipl" forKey: FSNColumnViewArrangeByKey];
  PASS ([options columnWidth] == 300 && [options arrangement] == FSNIconsArrangeKind
        && counter->count == 7,
        "MI-CLM-95 options changed in the defaults are taken over and posted, each change once");
  [[NSNotificationCenter defaultCenter] postNotificationName: NSUserDefaultsDidChangeNotification
                                                      object: defs];
  PASS (counter->count == 7, "MI-CLM-96 a defaults change that changes no option posts nothing");

  [[NSNotificationCenter defaultCenter] removeObserver: counter];
  clearDefaults ();
  [arp release];
  return 0;
}
