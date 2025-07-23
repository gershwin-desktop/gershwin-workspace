/* RunExternalController.m
 *  
 * Copyright (C) 2003-2024 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale
 *          Riccardo Mottola
 * Date: August 2001
 *
 * This file is part of the GNUstep GWorkspace application
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

#import "RunExternalController.h"
#import "CompletionField.h"
#import "GWorkspace.h"


@implementation RunExternalController

- (void)dealloc
{
  [super dealloc];
}

- (instancetype)init
{
  self = [super initWithNibName:@"RunExternal"];

  if (self)
    {
      [win setFrameUsingName: @"run_external"];

      [win setTitle:NSLocalizedString(@"Run", @"")];
      [titleLabel setStringValue:NSLocalizedString(@"Run", @"")];
      [secondLabel setStringValue:NSLocalizedString(@"Type the command to execute:", @"")];
    }

  return self;
}

- (NSString *)findExecutableInPATH:(NSString *)executableName
{
  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  NSArray *paths = [pathEnv componentsSeparatedByString:@":"];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  for (NSString *dir in paths) {
    NSString *fullPath = [dir stringByAppendingPathComponent:executableName];
    if ([fileManager isExecutableFileAtPath:fullPath]) {
      return fullPath;
    }
  }
  return nil;
}

- (NSArray *)parseArgumentsRespectingQuotes:(NSString *)argsString {
  NSMutableArray *args = [NSMutableArray array];
  NSScanner *scanner = [NSScanner scannerWithString:argsString];
  [scanner setCharactersToBeSkipped:nil];
  while (![scanner isAtEnd]) {
    NSString *arg = nil;
    // Skip whitespace
    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
    if ([scanner scanString:@"'" intoString:NULL]) {
      [scanner scanUpToString:@"'" intoString:&arg];
      [scanner scanString:@"'" intoString:NULL];
    } else if ([scanner scanString:@"\"" intoString:NULL]) {
      [scanner scanUpToString:@"\"" intoString:&arg];
      [scanner scanString:@"\"" intoString:NULL];
    } else {
      [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&arg];
    }
    if ([arg length]) {
      [args addObject:arg];
    }
  }
  return args;
}

- (IBAction)okButtAction:(id)sender
{
  NSString *str = [cfield string];
  if ([str length])
    {
      NSString *command = nil;
      NSScanner *scanner = [NSScanner scannerWithString:str];
      [scanner setCharactersToBeSkipped:nil];
      // Scan command, supporting quotes
      if ([scanner scanString:@"'" intoString:NULL] || [scanner scanString:@"\"" intoString:NULL]) {
        NSString *quote = [str substringWithRange:NSMakeRange(0,1)];
        NSString *cmd = nil;
        [scanner scanUpToString:quote intoString:&cmd];
        command = cmd;
        [scanner scanString:quote intoString:NULL];
      } else {
        [scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&command];
      }
      // Skip whitespace
      [scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:NULL];
      // Remaining string is arguments
      NSString *argsString = [[scanner string] substringFromIndex:[scanner scanLocation]];
      NSArray *args = [self parseArgumentsRespectingQuotes:argsString];
      NSString *checkedCommand = [self checkCommand: command];
      if (!checkedCommand) {
        // First, treat as a path
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:command]) {
          checkedCommand = command;
        } else {
          // Try to find executable in $PATH
          checkedCommand = [self findExecutableInPATH:command];
        }
      }
      if (checkedCommand)
        {
          if ([checkedCommand hasSuffix:@".app"])
            [[NSWorkspace sharedWorkspace] launchApplication: checkedCommand];
          else
            [NSTask launchedTaskWithLaunchPath: checkedCommand arguments: args];
          [win close];
        }
      else
        {
          NSRunAlertPanel(NULL, NSLocalizedString(@"No executable found!", @""),
                          NSLocalizedString(@"OK", @""), NULL, NULL);
        }
    }
}

- (void)completionFieldDidEndLine:(id)afield
{
  [super completionFieldDidEndLine:afield];
  [win makeFirstResponder: okButt];
}

- (void)windowWillClose:(NSNotification *)aNotification
{
  [super windowWillClose:aNotification];
  [win saveFrameUsingName: @"run_external"];
}

@end
