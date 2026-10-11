/* t_FileOpInfoConfirmText.m - the confirmation sentences of the file
 * operations are whole localizable sentences, never pieces glued together
 * (a German UI used to show "Verschieben one item from: ...").
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FileOpInfo.h"

static NSString *const kRecycleOut = @"WorkspaceRecycleOutOperation";

/* The printf conversions of a format, in order. */
static NSString *
specifiers(NSString *fmt)
{
  NSMutableString *out = [NSMutableString string];
  NSUInteger i;

  for (i = 0; i + 1 < [fmt length]; i++) {
    if ([fmt characterAtIndex: i] == '%') {
      unichar c = [fmt characterAtIndex: i + 1];

      if (c == 'l' && i + 2 < [fmt length]) {
        [out appendFormat: @"l%C", [fmt characterAtIndex: i + 2]];
      } else if (c != '%') {
        [out appendFormat: @"%C", c];
      }
      i++;
    }
  }
  return out;
}

/* The language the lookup uses, as the user's setting would choose it. */
static void
setLang(NSString *lang)
{
  [NSUserDefaults setUserLanguages: [NSArray arrayWithObject: lang]];
  /* The bundle keeps the table of the language it first read; drop it so the
   * next lookup follows the language chosen here. */
  [[FileOpInfo stringsBundle] setValue: nil forKey: @"_localizations"];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Class c = [FileOpInfo class];
  NSArray *types = @[ NSWorkspaceMoveOperation, NSWorkspaceCopyOperation,
                      NSWorkspaceLinkOperation, NSWorkspaceRecycleOperation,
                      kRecycleOut ];
  /* All languages Workspace ships. */
  NSArray *langs = @[ @"English", @"German", @"French", @"Italian",
                      @"Spanish", @"Portuguese", @"BrasilPortuguese",
                      @"Dutch", @"Esperanto", @"Hungarian", @"Japanese",
                      @"Norvegian", @"Polish", @"Romanian" ];
  NSString *type;
  NSString *lang;

  PASS_EQUAL([c confirmationMessageForOperation: NSWorkspaceMoveOperation
                                      itemCount: 1
                                         source: @"/a"
                                    destination: @"/b"],
             @"Move one item from: /a\nto: /b?",
             "move of one item is one sentence");
  PASS_EQUAL([c confirmationMessageForOperation: NSWorkspaceMoveOperation
                                      itemCount: 3
                                         source: @"/a"
                                    destination: @"/b"],
             @"Move 3 items from: /a\nto: /b?",
             "move of three items is in the plural");
  PASS_EQUAL([c confirmationMessageForOperation: NSWorkspaceRecycleOperation
                                      itemCount: 2
                                         source: @"/a"
                                    destination: nil],
             @"Move 2 items from: /a\nto the Recycler?",
             "move to the Recycler has no destination path");
  PASS_EQUAL([c confirmationMessageForOperation: kRecycleOut
                                      itemCount: 1
                                         source: nil
                                    destination: @"/b"],
             @"Move one item from the Recycler\nto: /b?",
             "move out of the Recycler names only the destination");
  PASS_EQUAL([c confirmationMessageForOperation: NSWorkspaceDestroyOperation
                                      itemCount: 4
                                         source: @"/a"
                                    destination: nil],
             @"Delete the selected objects?", "delete is unchanged");

  /* The sentences must be looked up where they live: the table of the
   * application (Workspace/Resources), through the same call the code uses.
   * The test points the lookup at that table and asks for each language. */
  [FileOpInfo setStringsBundle:
    [NSBundle bundleWithPath: [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent: @"../../Workspace/Resources"]]];
  PASS([FileOpInfo stringsBundle] != nil, "application strings found");
  NSMutableDictionary *reference = [NSMutableDictionary dictionary];

  /* What a missing translation shows: the English key itself. */
  setLang(@"English");
  for (type in types) {
    NSUInteger k;

    for (k = 1; k <= 2; k++) {
      [reference setObject: [c confirmationFormatForOperation: type itemCount: k]
                    forKey: [NSString stringWithFormat: @"%@/%lu", type,
                                      (unsigned long)k]];
    }
  }
  for (lang in langs) {
    BOOL english = [lang isEqual: @"English"];

    setLang(lang);
    for (type in types) {
      NSUInteger n;
      BOOL needsSrc = ![type isEqual: kRecycleOut];
      BOOL needsDst = ![type isEqual: NSWorkspaceRecycleOperation];

      for (n = 1; n <= 2; n++) {
        NSString *loc = [c confirmationMessageForOperation: type
                                                 itemCount: n
                                                    source: @"SRCPATH"
                                               destination: @"DSTPATH"];
        NSString *fmt = [c confirmationFormatForOperation: type itemCount: n];

        PASS(!needsSrc || [loc rangeOfString: @"SRCPATH"].location != NSNotFound,
             "%s keeps the source path (%s/%lu)", [lang UTF8String],
             [type UTF8String], (unsigned long)n);
        PASS(!needsDst || [loc rangeOfString: @"DSTPATH"].location != NSNotFound,
             "%s keeps the destination path (%s/%lu)", [lang UTF8String],
             [type UTF8String], (unsigned long)n);
        PASS(n == 1 || [loc rangeOfString: @"2"].location != NSNotFound,
             "%s keeps the item count (%s)", [lang UTF8String],
             [type UTF8String]);
        if (!english) {
          NSString *ref = [reference objectForKey:
            [NSString stringWithFormat: @"%@/%lu", type, (unsigned long)n]];

          PASS_EQUAL(specifiers(fmt), specifiers(ref),
                     "%s placeholders match (%s/%lu)", [lang UTF8String],
                     [type UTF8String], (unsigned long)n);
          PASS(![fmt isEqual: ref],
               "%s sentence for %s/%lu is translated: %s", [lang UTF8String],
               [type UTF8String], (unsigned long)n, [loc UTF8String]);
        }
      }
    }
  }
  setLang(@"German");
  PASS_EQUAL([c confirmationMessageForOperation: NSWorkspaceMoveOperation
                                      itemCount: 1
                                         source: @"/a"
                                    destination: @"/b"],
             @"Ein Element verschieben von: /a\nnach: /b?",
             "the German UI shows the German move sentence");
  [arp release];
  return 0;
}
