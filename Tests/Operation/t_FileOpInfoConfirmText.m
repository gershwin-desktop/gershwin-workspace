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

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Class c = [FileOpInfo class];
  NSArray *types = @[ NSWorkspaceMoveOperation, NSWorkspaceCopyOperation,
                      NSWorkspaceLinkOperation, NSWorkspaceRecycleOperation,
                      kRecycleOut ];
  NSArray *langs = @[ @"English", @"German" ];
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

  for (lang in langs) {
    NSString *path = [NSString stringWithFormat:
      @"../../Operation/Resources/%@.lproj/Localizable.strings", lang];
    NSDictionary *tbl = [NSDictionary dictionaryWithContentsOfFile: path];
    NSString *key;

    PASS(tbl != nil, "%s strings readable", [lang UTF8String]);
    for (type in types) {
      NSUInteger n;

      for (n = 1; n <= 2; n++) {
        NSString *en = [c confirmationMessageForOperation: type
                                                itemCount: n
                                                   source: @"%@"
                                              destination: @"%@"];
        NSString *fmt = [c confirmationFormatForOperation: type itemCount: n];
        NSString *loc = [tbl objectForKey: fmt];

        PASS(loc != nil, "%s has the sentence for %s/%lu",
             [lang UTF8String], [type UTF8String], (unsigned long)n);
        PASS_EQUAL(specifiers(loc), specifiers(fmt),
                   "placeholders of the %s sentence match", [lang UTF8String]);
        if ([lang isEqual: @"German"]) {
          PASS([loc rangeOfString: @"item"].location == NSNotFound
               && [loc rangeOfString: @" from"].location == NSNotFound
               && [loc rangeOfString: @"Recycler"].location == NSNotFound,
               "German sentence has no English words: %s", [loc UTF8String]);
        }
        (void)en;
      }
    }
    key = @"Delete the selected objects?";
    PASS([tbl objectForKey: key] != nil, "%s keeps %s", [lang UTF8String],
         [key UTF8String]);
  }
  [arp release];
  return 0;
}
