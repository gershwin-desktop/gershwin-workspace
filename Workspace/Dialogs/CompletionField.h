/* CompletionField.h
 *  
 * Copyright (C) 2003 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: August 2001
 *
 * This file is part of the GNUstep Workspace application
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


#import <AppKit/NSTextView.h>

@interface CompletionField : NSTextView
{
  id fm;
  id controller;

  /* Grey typeahead state: the completion suffix currently shown in grey
   * after the user's text, and how much of the string is the user's input. */
  NSString *completionSuffix;
  NSUInteger typedLength;

  /* Re-entrancy guard: setString: inside updateTypeahead would otherwise
   * re-enter didChangeText recursively. */
  BOOL updatingTypeahead;

  /* Set while an updateTypeahead has been deferred to the run loop, so rapid
   * typing coalesces into a single grey-suffix update. */
  BOOL typeaheadPending;
}

- (void)setController:(id)aController;

/* Returns the full completion for the given (user-typed) text, or nil when
 * there is no unique completion.  Subclasses/controllers may override to
 * provide their own completion source. */
- (NSString *)completionForText:(NSString *)text;

/* Accepts the currently displayed grey completion, making it part of the
 * user's text. */
- (void)acceptCompletion;

/* Returns only the user's typed text, without any grey completion suffix.
 * This is what dialogs should use when executing or opening something. */
- (NSString *)typedText;

@end


@interface NSObject (CompletionField)

- (void)completionFieldDidEndLine:(id)afield;
- (void)completionFieldDidCancel:(id)afield;

@end
