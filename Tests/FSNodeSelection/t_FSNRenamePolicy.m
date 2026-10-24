/* t_FSNRenamePolicy.m - when renaming starts, what is preselected and which
 * names need a question, as measured on the reference. Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../FSNode/FSNSelectionModel.h"
#include "../../FSNode/FSNRenamePolicy.m"

static NSString *selected(NSString *text, NSString *name, BOOL folder)
{
  NSRange r = [FSNRenamePolicy initialSelectionForText: text name: name plainFolder: folder];

  return [text substringWithRange: r];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSArray *names = [NSArray arrayWithObjects: @"alpha.txt", @"beta.txt", @"bravo.txt",
                                              @"sub", nil];

  START_SET("start")
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 1 onName: YES wasOnlySelected: YES
                                           modifiers: 0],
       "a click on the name of the only selected item starts renaming");
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 1 onName: YES wasOnlySelected: YES
                                           modifiers: FSNSelectionModifierOption],
       "Option does not stop it");
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 1 onName: NO wasOnlySelected: YES
                                           modifiers: 0] == NO,
       "a slow second click on the icon does not");
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 1 onName: YES wasOnlySelected: NO
                                           modifiers: 0] == NO,
       "the click that selects the item does not");
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 2 onName: YES wasOnlySelected: YES
                                           modifiers: 0] == NO,
       "a double click opens instead");
  PASS([FSNRenamePolicy clickStartsRenamingWithCount: 1 onName: YES wasOnlySelected: YES
                                           modifiers: FSNSelectionModifierShift] == NO,
       "a Shift-click does not");

  PASS([FSNRenamePolicy keyStartsRenaming: '\r' modifiers: 0 selectionCount: 1],
       "Return starts renaming the selected item");
  PASS([FSNRenamePolicy keyStartsRenaming: 0x03 modifiers: 0 selectionCount: 1],
       "so does Enter");
  PASS([FSNRenamePolicy keyStartsRenaming: '\r' modifiers: 0 selectionCount: 2] == NO,
       "not with several items selected");
  PASS([FSNRenamePolicy keyStartsRenaming: '\r' modifiers: FSNSelectionModifierCommand
                           selectionCount: 1] == NO,
       "not with a modifier");
  END_SET("start")

  START_SET("preselection")
  PASS_EQUAL(selected(@"alpha.txt", @"alpha.txt", NO), @"alpha",
             "the name without its extension is selected");
  PASS_EQUAL(selected(@"sub.one.txt", @"sub.one.txt", NO), @"sub.one",
             "only the last extension is left out");
  PASS_EQUAL(selected(@"sub", @"sub", YES), @"sub", "a folder's whole name");
  PASS_EQUAL(selected(@"my.folder", @"my.folder", YES), @"my.folder",
             "a folder's whole name even with a dot");
  PASS_EQUAL(selected(@".profile", @".profile", NO), @".profile",
             "a name that only starts with a dot is all name");
  PASS_EQUAL(selected(@"bravo", @"bravo.txt", NO), @"bravo",
             "the whole text when the extension is hidden");
  PASS_EQUAL(selected(@"README", @"README", NO), @"README", "a name without extension");
  END_SET("preselection")

  START_SET("commit or cancel")
  PASS([FSNRenamePolicy textMovementCommits: FSNRenameMovementReturn], "Return renames");
  PASS([FSNRenamePolicy textMovementCommits: FSNRenameMovementTab], "Tab renames");
  PASS([FSNRenamePolicy textMovementCommits: FSNRenameMovementOther],
       "a click elsewhere or another window renames");
  PASS([FSNRenamePolicy textMovementCommits: FSNRenameMovementCancel] == NO,
       "Escape keeps the old name");
  END_SET("commit or cancel")

  START_SET("validation")
  PASS([FSNRenamePolicy isValidName: @"gamma.txt"], "a plain name is valid");
  PASS([FSNRenamePolicy isValidName: @"what?*.txt"], "punctuation the file system takes is valid");
  PASS([FSNRenamePolicy isValidName: @""] == NO, "an empty name is not");
  PASS([FSNRenamePolicy isValidName: @"be:ta.txt"] == NO, "a colon is not");
  PASS([FSNRenamePolicy isValidName: @"be/ta.txt"] == NO, "a slash is not");
  PASS([FSNRenamePolicy isValidName: @"a\tb"] == NO, "a control character is not");
  PASS([FSNRenamePolicy isValidName: @".."] == NO, "\"..\" is not");
  PASS([FSNRenamePolicy isValidName: [@"" stringByPaddingToLength: 256 withString: @"x" startingAtIndex: 0]] == NO,
       "more than 255 bytes is not");

  PASS([FSNRenamePolicy needsHiddenNameConfirmation: @".beta.txt" oldName: @"beta.txt"],
       "a new leading dot asks");
  PASS([FSNRenamePolicy needsHiddenNameConfirmation: @".profile2" oldName: @".profile"] == NO,
       "an item that already was hidden does not ask");

  PASS([FSNRenamePolicy needsExtensionConfirmation: @"beta.rtf" oldName: @"beta.txt"
                                       plainFolder: NO],
       "changing the extension asks");
  PASS([FSNRenamePolicy needsExtensionConfirmation: @"beta" oldName: @"beta.txt"
                                       plainFolder: NO],
       "removing the extension asks");
  PASS([FSNRenamePolicy needsExtensionConfirmation: @"gamma.txt" oldName: @"beta.txt"
                                       plainFolder: NO] == NO,
       "keeping the extension does not ask");
  PASS([FSNRenamePolicy needsExtensionConfirmation: @"gamma.TXT" oldName: @"beta.txt"
                                       plainFolder: NO] == NO,
       "nor a different case of it");
  PASS([FSNRenamePolicy needsExtensionConfirmation: @"notes.txt" oldName: @"notes"
                                       plainFolder: NO] == NO,
       "adding an extension to a name without one does not ask");
  PASS([FSNRenamePolicy needsExtensionConfirmation: @"sub.d" oldName: @"sub"
                                       plainFolder: YES] == NO,
       "a plain folder has no extension to protect");
  PASS_EQUAL([FSNRenamePolicy name: @"beta.rtf" keepingExtensionOf: @"beta.txt"], @"beta.txt",
             "Keep puts the old extension back");
  PASS_EQUAL([FSNRenamePolicy name: @"gamma" keepingExtensionOf: @"beta.txt"], @"gamma.txt",
             "also after it was removed");

  PASS([FSNRenamePolicy name: @"bravo.txt" isTakenAmong: names oldName: @"beta.txt"],
       "another item's name is taken");
  PASS([FSNRenamePolicy name: @"gamma.txt" isTakenAmong: names oldName: @"beta.txt"] == NO,
       "a free name is not");
  PASS([FSNRenamePolicy name: @"Beta.txt" isTakenAmong: names oldName: @"beta.txt"] == NO,
       "changing only the case of the own name is allowed");
  END_SET("validation")

  [arp release];
  return 0;
}
