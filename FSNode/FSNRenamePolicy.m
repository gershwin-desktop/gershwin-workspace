/*
 * FSNRenamePolicy.m - when renaming an item starts, what is preselected,
 * and which new names need a question or are refused.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNRenamePolicy.h"
#import "FSNSelectionModel.h"

/* The extension the reference protects: what follows the last dot, unless
   the dot starts the name. */
static NSString *FSNRenameExtension(NSString *name)
{
  NSRange dot = [name rangeOfString: @"." options: NSBackwardsSearch];

  if (dot.location == NSNotFound || dot.location == 0
      || NSMaxRange(dot) >= [name length])
    return @"";
  return [name substringFromIndex: NSMaxRange(dot)];
}

static NSString *FSNRenameBase(NSString *name)
{
  NSString *ext = FSNRenameExtension(name);

  if ([ext length] == 0)
    return name;
  return [name substringToIndex: [name length] - [ext length] - 1];
}

@implementation FSNRenamePolicy

+ (BOOL)clickStartsRenamingWithCount:(NSInteger)clickCount
                              onName:(BOOL)onName
                     wasOnlySelected:(BOOL)wasOnlySelected
                           modifiers:(unsigned)modifiers
{
  return (clickCount == 1 && onName && wasOnlySelected
          && (modifiers & ~FSNSelectionModifierOption) == 0);
}

+ (BOOL)keyStartsRenaming:(unichar)key
                modifiers:(unsigned)modifiers
           selectionCount:(NSUInteger)count
{
  /* Return, and Enter as AppKit reports it (NSEnterCharacter). */
  return ((key == '\r' || key == 0x03) && modifiers == 0 && count == 1);
}

+ (NSRange)initialSelectionForText:(NSString *)text
                              name:(NSString *)name
                       plainFolder:(BOOL)plainFolder
{
  if (plainFolder || [text isEqualToString: name] == NO)
    return NSMakeRange(0, [text length]);
  return NSMakeRange(0, [FSNRenameBase(text) length]);
}

+ (BOOL)textMovementCommits:(NSInteger)movement
{
  return (movement != FSNRenameMovementCancel);
}

+ (BOOL)isValidName:(NSString *)name
{
  NSMutableCharacterSet *refused;

  if ([name length] == 0 || [name isEqualToString: @"."] || [name isEqualToString: @".."])
    return NO;
  if ([name lengthOfBytesUsingEncoding: NSUTF8StringEncoding] > 255)
    return NO;

  /* The colon too: the reference refuses it, and it is the path separator
     of the volumes it writes, so a name with one would not survive there. */
  refused = [[NSCharacterSet controlCharacterSet] mutableCopy];
  [refused addCharactersInString: @"/:"];
  if ([name rangeOfCharacterFromSet: refused].location != NSNotFound)
    {
      RELEASE(refused);
      return NO;
    }
  RELEASE(refused);
  return YES;
}

+ (BOOL)needsHiddenNameConfirmation:(NSString *)newName oldName:(NSString *)oldName
{
  return ([newName hasPrefix: @"."] && [oldName hasPrefix: @"."] == NO);
}

+ (BOOL)needsExtensionConfirmation:(NSString *)newName
                           oldName:(NSString *)oldName
                       plainFolder:(BOOL)plainFolder
{
  NSString *oldExt = FSNRenameExtension(oldName);

  if (plainFolder || [oldExt length] == 0)
    return NO;
  return ([FSNRenameExtension(newName) caseInsensitiveCompare: oldExt] != NSOrderedSame);
}

+ (NSString *)name:(NSString *)newName keepingExtensionOf:(NSString *)oldName
{
  NSString *oldExt = FSNRenameExtension(oldName);

  if ([oldExt length] == 0)
    return newName;
  return [NSString stringWithFormat: @"%@.%@", FSNRenameBase(newName), oldExt];
}

+ (BOOL)name:(NSString *)newName
    isTakenAmong:(NSArray *)names
         oldName:(NSString *)oldName
{
  if ([newName isEqualToString: oldName])
    return NO;
  return [names containsObject: newName];
}

@end
