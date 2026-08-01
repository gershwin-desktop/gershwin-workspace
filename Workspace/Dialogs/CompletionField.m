/* CompletionField.m
 *  
 * Copyright (C) 2003-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "GWFunctions.h"
#import "FSNFunctions.h"
#import "CompletionField.h"

@implementation CompletionField

- (void)dealloc
{
  [completionSuffix release];
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame:frameRect];
  if (self)
    {
      /* Rich text is required so setTextColor:range: can colour the grey
       * completion suffix differently from the typed text. */
      [self setRichText: YES];
      [self setImportsGraphics: NO];
      [self setUsesFontPanel: NO];
      [self setUsesRuler: NO];
      [self setEditable: YES];
      fm = [NSFileManager defaultManager];
      completionSuffix = nil;
      typedLength = 0;
    }
  return self;
}

- (void)setController:(id)aController
{
  controller = aController;
}

- (id)initWithCoder: (NSCoder *) coder
{
  self = [super initWithCoder: coder];  
  if (self)
  {
    /* Rich text required for per-range grey completion colouring. */
    [self setRichText: YES];
    [self setImportsGraphics: NO];
    [self setUsesFontPanel: NO];
    [self setUsesRuler: NO];
    [self setEditable: YES];
    fm = [NSFileManager defaultManager];
    completionSuffix = nil;
    typedLength = 0;
  }
  
  return self;  
}


- (void)setFrame:(NSRect)frameRect
{
  NSSize size;

  [super setFrame: frameRect];
  size = NSMakeSize(1e7, [self bounds].size.height);
  [[self textContainer] setContainerSize: size];
  [[self textContainer] setWidthTracksTextView: YES];
}

/* Finds the first directory entry under parent that begins with prefix
 * (ignoring exact matches), or the exact name when it is a directory. */
- (NSString *)firstPathCompletionForPrefix:(NSString *)prefix
                                     inDir:(NSString *)dir
                            pathSeparator:(NSString *)sep
{
  NSArray *contents = [fm directoryContentsAtPath: dir];
  if (contents == nil || [contents count] == 0)
    return nil;

  NSString *candidate = nil;
  for (NSString *name in contents)
    {
      if ([name hasPrefix: prefix] && ![name isEqualToString: prefix])
        {
          candidate = name;
          break;
        }
      if ([name isEqualToString: prefix])
        {
          BOOL isDir = NO;
          NSString *full = [dir stringByAppendingPathComponent: name];
          if ([fm fileExistsAtPath: full isDirectory: &isDir] && isDir)
            candidate = name; /* exact dir: keep to append separator */
        }
    }

  if (candidate == nil)
    return nil;

  BOOL isDir = NO;
  NSString *full = [dir stringByAppendingPathComponent: candidate];
  if ([fm fileExistsAtPath: full isDirectory: &isDir] && isDir)
    return [candidate stringByAppendingString: sep];

  return candidate;
}

/* Default completion source: completes application bundle names when the
 * text is a bare command, and directory/file paths when it looks like one.
 * Returns the full completed text (user text + suffix), or nil. */
- (NSString *)completionForText:(NSString *)text
{
  if (text == nil || [text length] == 0)
    return nil;

  NSString *sep = path_separator();

  if ([text hasPrefix: sep] || [text hasPrefix: @"~"] ||
      [text hasPrefix: @"."] || [text rangeOfString: sep].location != NSNotFound)
    {
      /* Path completion */
      NSString *expanded = [text stringByExpandingTildeInPath];
      NSString *parent = [expanded stringByDeletingLastPathComponent];
      NSString *last = [expanded lastPathComponent];
      NSString *completed;

      if ([parent length] == 0)
        parent = sep;

      completed = [self firstPathCompletionForPrefix: last
                                               inDir: parent
                                      pathSeparator: sep];
      if (completed == nil)
        return nil;

      /* Rebuild the path from the expanded parent and the completed name,
       * collapsing the tilde back if we started with one. */
      NSString *full = [parent stringByAppendingPathComponent: completed];
      if ([full hasPrefix: NSHomeDirectory()] && [text hasPrefix: @"~"])
        {
          NSString *rest = [full substringFromIndex: [NSHomeDirectory() length]];
          return [@"~" stringByAppendingString: rest];
        }
      return full;
    }
  else
    {
      /* Application / command completion: search standard app paths and PATH */
      NSArray *appPaths = NSStandardApplicationPaths();
      NSString *completedApp = nil;

      for (NSString *dir in appPaths)
        {
          NSArray *contents = [fm directoryContentsAtPath: dir];
          for (NSString *name in contents)
            {
              if ([name hasPrefix: text] && ![name isEqualToString: text])
                {
                  completedApp = name;
                  break;
                }
            }
          if (completedApp)
            break;
        }

      if (completedApp)
        return completedApp;

      /* Fall back to PATH executables */
      NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
      for (NSString *dir in [pathEnv componentsSeparatedByString: @":"])
        {
          NSArray *contents = [fm directoryContentsAtPath: dir];
          for (NSString *name in contents)
            {
              if ([name hasPrefix: text] && ![name isEqualToString: text])
                {
                  return name;
                }
            }
        }
    }

  return nil;
}

/* Shows (or updates) the grey completion suffix after the user's text.
 *
 * The text storage holds `typed + greySuffix`.  To recompute we must first
 * strip the old suffix (which occupies typedLength..end), then append the
 * new suffix coloured grey. */
- (void)updateTypeahead
{
  if (updatingTypeahead)
    return;

  NSString *full = [self string];
  NSUInteger fullLen = [full length];

  /* Recover the user's typed text: remove the previously shown grey suffix
   * from the END of the string (the user's new keystrokes go before it). */
  NSString *text = full;
  if (completionSuffix && [completionSuffix length] > 0)
    {
      NSUInteger sufLen = [completionSuffix length];
      if (fullLen > sufLen && [full hasSuffix: completionSuffix])
        {
          text = [full substringToIndex: fullLen - sufLen];
        }
    }

  /* Never show a completion while editing in the middle of the text. */
  NSRange sel = [self selectedRange];
  if (sel.location != [text length] || sel.length > 0)
    {
      if (completionSuffix)
        {
          [completionSuffix release];
          completionSuffix = nil;
        }
      typedLength = [text length];
      if ([full length] != [text length])
        {
          [self setString: text];
        }
      return;
    }

  NSString *completion = [self completionForText: text];
  NSString *suffix = nil;
  if (completion && [completion length] > [text length]
      && [completion hasPrefix: text])
    {
      suffix = [completion substringFromIndex: [text length]];
    }

  if (suffix)
    {
      NSString *newFull = [text stringByAppendingString: suffix];
      if ([newFull isEqualToString: full] == NO || completionSuffix == nil
          || [completionSuffix isEqualToString: suffix] == NO)
        {
          [completionSuffix release];
          completionSuffix = [suffix copy];
          typedLength = [text length];

          updatingTypeahead = YES;
          [self setString: newFull];
          updatingTypeahead = NO;
          NSColor *grey = [NSColor disabledControlTextColor];
          [self setTextColor: [NSColor textColor]
                      range: NSMakeRange(0, typedLength)];
          [self setTextColor: grey
                      range: NSMakeRange(typedLength, [suffix length])];
          [self setSelectedRange: NSMakeRange(typedLength, 0)];
        }
    }
  else
    {
      if (completionSuffix)
        {
          [completionSuffix release];
          completionSuffix = nil;
        }
      typedLength = [text length];
      if ([full length] != [text length])
        {
          updatingTypeahead = YES;
          [self setString: text];
          updatingTypeahead = NO;
          [self setTextColor: [NSColor textColor]
                      range: NSMakeRange(0, [text length])];
          [self setSelectedRange: NSMakeRange([text length], 0)];
        }
    }
}

/* Makes the grey completion part of the user's text. */
- (void)acceptCompletion
{
  if (completionSuffix)
    {
      NSString *full = [self string];
      [self setTextColor: [NSColor textColor]
                  range: NSMakeRange(0, [full length])];
      [self setSelectedRange: NSMakeRange([full length], 0)];
      [completionSuffix release];
      completionSuffix = nil;
      typedLength = [full length];
    }
}

/* Tab key completion for the current text (paths or app names). */
- (void)completeWithTab
{
  if (completionSuffix)
    {
      /* A grey completion is already shown: accept it and move the caret. */
      [self acceptCompletion];
      return;
    }

  NSString *str = [self string];
  if ([str length] == 0)
    return;

  NSString *completion = [self completionForText: str];
  if (completion)
    {
      [self setString: completion];
      [self setSelectedRange: NSMakeRange([completion length], 0)];
    }
}

- (void)didChangeText
{
  [super didChangeText];
  /* setString: called from updateTypeahead re-enters didChangeText via the
   * text storage notification; the guard prevents infinite recursion and
   * prevents the inner call from stripping the suffix we just set. */
  if (updatingTypeahead == NO)
    {
      [self updateTypeahead];
    }
}

- (void)keyDown:(NSEvent *)theEvent
{
  NSString *eventstr = [theEvent characters];
  NSString *str = [self string];

#define CHECK_SEPARATOR \
if ([path hasSuffix: pathSeparator] == NO) \
[path appendString: pathSeparator]

  if ([eventstr isEqual: @"\t"] && [str length])
    {
      /* Tab accepts the grey completion, or completes the current input. */
      if (completionSuffix)
        {
          [self acceptCompletion];
        }
      else
        {
          [self completeWithTab];
        }
      return;
    }

  if ([eventstr isEqual: @"\x1B"])
    {
      [controller completionFieldDidCancel: self];
      return;
    }

  if ([eventstr isEqual: @"\r"] && [[self string] length])
    {
      [self acceptCompletion];
      [controller completionFieldDidEndLine: self];
      return;
    }

  [super keyDown: theEvent];
  [self updateTypeahead];
}

@end



