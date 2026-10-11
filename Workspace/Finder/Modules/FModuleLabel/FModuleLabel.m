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
 * Finds files by Finder label colour. The criteria hold Finder's own colour
 * number (0 none, 1 grey, 2 green, 3 purple, 4 blue, 5 yellow, 6 red,
 * 7 orange), which is also what a smart folder's kMDItemFSLabel and the
 * search index use, so no second numbering exists.
 */
@interface FModuleLabel : NSObject <FinderModulesProtocol>
{
  NSView *controlsBox;
  NSPopUpButton *isPopUp;
  NSPopUpButton *colorPopUp;
  NSInteger index;
  BOOL used;

  NSInteger color;
  NSInteger how;
}

@end

@implementation FModuleLabel

enum { IS, IS_NOT };

- (void)dealloc
{
  RELEASE (controlsBox);
  RELEASE (isPopUp);
  RELEASE (colorPopUp);
  [super dealloc];
}

- (void)addColor:(NSString *)title number:(NSUInteger)number
{
  [colorPopUp addItemWithTitle: NSLocalizedString(title, @"")];
  [[colorPopUp lastItem] setTag: number];
}

- (id)initInterface
{
  self = [super init];

  if (self) {

    controlsBox = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 260, 34)];
    isPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 0, 111, 20)
                                         pullsDown: NO];
    colorPopUp = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(126, 0, 124, 20)
                                            pullsDown: NO];
    /* Same frames as the modules from the nib (popups 20 high, flush with the
     * bottom of the row), so every row of the Find window lines up. */
    [isPopUp setAutoresizingMask: NSViewMaxYMargin];
    [colorPopUp setAutoresizingMask: NSViewMaxYMargin];

    [isPopUp addItemWithTitle: NSLocalizedString(@"is", @"")];
    [isPopUp addItemWithTitle: NSLocalizedString(@"is not", @"")];

    /* the menu order of the labels, each with Finder's colour number */
    [self addColor: @"None" number: 0];
    [self addColor: @"Red" number: [GSFileMetadata finderColorForLabel: GSFileLabelRed]];
    [self addColor: @"Orange" number: [GSFileMetadata finderColorForLabel: GSFileLabelOrange]];
    [self addColor: @"Yellow" number: [GSFileMetadata finderColorForLabel: GSFileLabelYellow]];
    [self addColor: @"Green" number: [GSFileMetadata finderColorForLabel: GSFileLabelGreen]];
    [self addColor: @"Blue" number: [GSFileMetadata finderColorForLabel: GSFileLabelBlue]];
    [self addColor: @"Purple" number: [GSFileMetadata finderColorForLabel: GSFileLabelPurple]];
    [self addColor: @"Grey" number: [GSFileMetadata finderColorForLabel: GSFileLabelGrey]];

    [controlsBox addSubview: isPopUp];
    [controlsBox addSubview: colorPopUp];

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
    color = [[criteria objectForKey: @"what"] integerValue];
    how = [[criteria objectForKey: @"how"] integerValue];
  }

  return self;
}

- (void)setControlsState:(NSDictionary *)info
{
  NSNumber *num = [info objectForKey: @"how"];

  if (num) {
    [isPopUp selectItemAtIndex: [num intValue]];
  }

  num = [info objectForKey: @"what"];

  if (num) {
    [colorPopUp selectItemWithTag: [num intValue]];
  }
}

- (id)controls
{
  return controlsBox;
}

- (NSString *)moduleName
{
  return NSLocalizedString(@"label", @"");
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

  [criteria setObject: [NSNumber numberWithInteger: [isPopUp indexOfSelectedItem]]
               forKey: @"how"];
  [criteria setObject: [NSNumber numberWithInteger: [[colorPopUp selectedItem] tag]]
               forKey: @"what"];

  return criteria;
}

- (BOOL)checkPath:(NSString *)path 
   withAttributes:(NSDictionary *)attributes
{
  /* Read afresh: the shared per-path cache would hide a label that was
   * changed since the last search. */
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path
                                                forceSidecar: NO];
  NSInteger found = md
    ? (NSInteger)[GSFileMetadata finderColorForLabel:
                  (GSFileLabel)[md labelNumber]]
    : 0;

  return (how == IS) ? (found == color) : (found != color);
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

/* A label change does not change the modification date. */
- (BOOL)reliesOnModDate
{
  return NO;
}

- (BOOL)metadataModule
{
  return NO;
}

@end
