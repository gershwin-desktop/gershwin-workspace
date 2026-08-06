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

/* Directory listing cache so typing does not rescan the application and PATH
 * directories on every keystroke.  Keyed by directory path; the value is an
 * array of the entry names.  A short TTL keeps it fresh. */
#define COMPLETION_CACHE_TTL 10.0
static NSMutableDictionary *completionCache = nil;
static double completionCacheStamp = 0.0;

static NSArray *CompletionCachedContents(NSFileManager *fm, NSString *dir)
{
  if (completionCache == nil)
    completionCache = [NSMutableDictionary new];

  double now = [[NSProcessInfo processInfo] systemUptime];
  if (now - completionCacheStamp > COMPLETION_CACHE_TTL)
    {
      [completionCache removeAllObjects];
      completionCacheStamp = now;
    }

  NSArray *cached = [completionCache objectForKey: dir];
  if (cached == nil)
    {
      cached = [fm directoryContentsAtPath: dir];
      if (cached == nil)
        cached = [NSArray array];
      [completionCache setObject: cached forKey: dir];
    }
  return cached;
}

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
      [self setAllowsUndo: YES];
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
    [self setAllowsUndo: YES];
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
  NSArray *contents = CompletionCachedContents(fm, dir);
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
      /* Application completion: search the standard, LOCAL application
       * directories.  PATH executables are deliberately NOT scanned here -
       * doing the filesystem walk synchronously on every keystroke blocks
       * the main thread (a slow or network-mounted PATH entry would wedge
       * the whole app while typing); the full PATH completion is available
       * via the Tab key (completeWithTab). */
      NSArray *appPaths = NSStandardApplicationPaths();
      NSString *completedApp = nil;

      for (NSString *dir in appPaths)
        {
          NSArray *contents = CompletionCachedContents(fm, dir);
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
    }

  return nil;
}

/* Completes from PATH executables as well; only used by explicit Tab
 * completion, never during typing. */
- (NSString *)completionForTextIncludingPath:(NSString *)text
{
  NSString *completed = [self completionForText: text];
  if (completed)
    return completed;

  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
  for (NSString *dir in [pathEnv componentsSeparatedByString: @":"])
    {
      NSArray *contents = CompletionCachedContents(fm, dir);
      for (NSString *name in contents)
        {
          if ([name hasPrefix: text] && ![name isEqualToString: text])
            {
              return name;
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
  typeaheadPending = NO;

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
          /* Light grey so the suggested completion is clearly distinct from
           * the user's black typed text. */
          NSColor *grey = [NSColor lightGrayColor];
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

/* Returns only the user's typed text, stripping any grey completion suffix.
 * Used by dialogs to execute/open exactly what the user typed, not the
 * suggested (grey) completion. */
- (NSString *)typedText
{
  NSString *full = [self string];
  if (completionSuffix && [completionSuffix length] > 0
      && [full hasSuffix: completionSuffix])
    {
      return [full substringToIndex: [full length] - [completionSuffix length]];
    }
  return full;
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

  /* Tab completion may also consult the PATH (unlike the per-keystroke grey
   * typeahead, which only scans the local application directories). */
  NSString *completion = [self completionForTextIncludingPath: str];
  if (completion)
    {
      [self setString: completion];
      [self setSelectedRange: NSMakeRange([completion length], 0)];
    }
}

- (void)didChangeText
{
  [super didChangeText];
  /* Defer the grey typeahead out of the text-change callback.  Mutating the
   * text storage with setString: from inside the edit notification (plus the
   * per-keystroke directory scans) can wedge GNUstep's text system while the
   * user types.  Coalesce: rapid keystrokes collapse into one update. */
  if (updatingTypeahead == NO && typeaheadPending == NO)
    {
      typeaheadPending = YES;
      [self performSelector: @selector(updateTypeahead)
                 withObject: nil afterDelay: 0.05];
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

  /* Right Arrow at the end of the typed text confirms the grey completion:
   * accept it (making it black) and move the caret to the very end.  Without
   * this the arrow would step into the grey suffix and updateTypeahead would
   * strip the suggestion instead of confirming it.  The event's characters
   * carry the Unicode function-key character (0xF703) for arrow keys. */
  if (completionSuffix
      && [eventstr isEqualToString: [NSString stringWithFormat: @"%C",
                                     (unichar)NSRightArrowFunctionKey]])
    {
      [self acceptCompletion];
      return;
    }

  if ([eventstr isEqual: @"\x1B"])
    {
      [controller completionFieldDidCancel: self];
      return;
    }

  if ([eventstr isEqual: @"\r"] && [[self string] length])
    {
      /* Execute only the user's typed text; the grey suggestion is not
       * accepted on Return (use Tab to accept it first). */
      [controller completionFieldDidEndLine: self];
      return;
    }

  [super keyDown: theEvent];
}

@end



