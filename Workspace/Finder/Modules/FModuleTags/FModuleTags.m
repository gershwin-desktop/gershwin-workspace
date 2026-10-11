/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FinderModulesProtocol.h"
#import "GSFileMetadata.h"

/*
 * Finds files by Finder tag: a file matches when any one of its tags is the
 * given text ("is") or contains it ("contains"). There is no "is not": a file
 * with several tags would match it through another tag, which a smart folder
 * cannot say either.
 */
@interface FModuleTags : NSObject <FinderModulesProtocol>
{
  NSView *controlsBox;
  NSPopUpButton *popUp;
  NSTextField *textField;
  NSInteger index;
  BOOL used;

  NSString *searchStr;
  NSInteger how;
}

@end

@implementation FModuleTags

enum { IS, CONTAINS };

- (void)dealloc
{
  RELEASE (controlsBox);
  RELEASE (popUp);
  RELEASE (textField);
  RELEASE (searchStr);
  [super dealloc];
}

- (id)initInterface
{
  self = [super init];

  if (self) {
    controlsBox = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 30)];
    popUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 4, 100, 22)
                                       pullsDown: NO];
    textField = [[NSTextField alloc] initWithFrame: NSMakeRect(108, 4, 160, 22)];
    [popUp setAutoresizingMask: NSViewMinYMargin | NSViewMaxYMargin];
    [textField setAutoresizingMask: NSViewMinYMargin | NSViewMaxYMargin
                                    | NSViewWidthSizable];

    [popUp addItemWithTitle: NSLocalizedString(@"is", @"")];
    [popUp addItemWithTitle: NSLocalizedString(@"contains", @"")];

    [controlsBox addSubview: popUp];
    [controlsBox addSubview: textField];

    used = NO;
    index = 0;
  }

  return self;
}

- (id)initWithSearchCriteria:(NSDictionary *)criteria
                  searchTool:(id)tool
{
  self = [super init];

  if (self) {
    ASSIGN (searchStr, [criteria objectForKey: @"what"]);
    how = [[criteria objectForKey: @"how"] integerValue];
  }

  return self;
}

- (void)setControlsState:(NSDictionary *)info
{
  NSNumber *num = [info objectForKey: @"how"];
  NSString *str = [info objectForKey: @"what"];

  if (num) {
    [popUp selectItemAtIndex: [num intValue]];
  }

  if (str) {
    [textField setStringValue: str];
  }
}

- (id)controls
{
  return controlsBox;
}

- (NSString *)moduleName
{
  return NSLocalizedString(@"tags", @"");
}

- (BOOL)used
{
  return used;
}

- (void)setInUse:(BOOL)value
{
  used = value;
}

- (NSInteger)index
{
  return index;
}

- (void)setIndex:(NSInteger)idx
{
  index = idx;
}

- (NSDictionary *)searchCriteria
{
  NSMutableDictionary *criteria = [NSMutableDictionary dictionary];

  [criteria setObject: [NSNumber numberWithInteger: [popUp indexOfSelectedItem]]
               forKey: @"how"];
  [criteria setObject: [textField stringValue] forKey: @"what"];

  return criteria;
}

- (BOOL)checkPath:(NSString *)path 
   withAttributes:(NSDictionary *)attributes
{
  GSFileMetadata *md;
  NSString *tag;

  if ([searchStr length] == 0) {
    return NO;
  }

  /* Read afresh: the shared per-path cache would hide a tag that was
   * changed since the last search. */
  md = [GSFileMetadata metadataForFileAtPath: path forceSidecar: NO];

  for (tag in [md userTags]) {
    NSRange nl;

    if ([tag isKindOfClass: [NSString class]] == NO) {
      continue;
    }
    /* Later Finders append the colour number after a newline. */
    nl = [tag rangeOfString: @"\n"];
    if (nl.location != NSNotFound) {
      tag = [tag substringToIndex: nl.location];
    }
    if (how == IS ? [tag isEqualToString: searchStr]
                  : ([tag rangeOfString: searchStr].location != NSNotFound)) {
      return YES;
    }
  }

  return NO;
}

- (NSComparisonResult)compareModule:(id <FinderModulesProtocol>)module
{
  NSInteger i1 = [self index];
  NSInteger i2 = [module index];

  if (i1 < i2) {
    return NSOrderedAscending;
  } else if (i1 > i2) {
    return NSOrderedDescending;
  } 

  return NSOrderedSame;
}

/* A tag change does not change the modification date. */
- (BOOL)reliesOnModDate
{
  return NO;
}

- (BOOL)metadataModule
{
  return NO;
}

@end
