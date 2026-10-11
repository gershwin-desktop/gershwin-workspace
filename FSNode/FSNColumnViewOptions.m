/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "FSNColumnViewOptions.h"
#import "FSNBrowserLayout.h"
#import "FSNIconsView.h"

NSString * const FSNColumnViewOptionsDidChangeNotification = @"FSNColumnViewOptionsDidChange";

NSString * const FSNColumnViewTextSizeKey = @"ColumnViewTextSize";
NSString * const FSNColumnViewShowsIconsKey = @"ColumnViewShowsIcons";
NSString * const FSNColumnViewShowsIconPreviewKey = @"ColumnViewShowsIconPreview";
NSString * const FSNColumnViewShowsPreviewColumnKey = @"ColumnViewShowsPreviewColumn";
NSString * const FSNColumnViewArrangeByKey = @"ColumnViewArrangeBy";
NSString * const FSNColumnViewColumnWidthKey = @"ColumnViewColumnWidth";

const CGFloat FSNColumnViewDefaultColumnWidth = 205.0;

static NSString * const FSNArrangeNoneCode = @"none";

@implementation FSNColumnViewOptions

+ (FSNColumnViewOptions *)sharedOptions
{
  static FSNColumnViewOptions *shared = nil;

  if (shared == nil)
    {
      shared = [FSNColumnViewOptions new];
    }
  return shared;
}

+ (NSDictionary *)finderCodes
{
  static NSDictionary *codes = nil;

  if (codes == nil)
    {
      codes = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithInteger: FSNIconsArrangeName], @"dnam",
        [NSNumber numberWithInteger: FSNIconsArrangeKind], @"kipl",
        [NSNumber numberWithInteger: FSNIconsArrangeDateModified], @"modd",
        [NSNumber numberWithInteger: FSNIconsArrangeDateCreated], @"ascd",
        [NSNumber numberWithInteger: FSNIconsArrangeSize], @"phys",
        [NSNumber numberWithInteger: FSNIconsArrangeLabel], @"labl",
        nil];
    }
  return codes;
}

+ (FSNIconsArrangement)arrangementForFinderCode:(NSString *)code
{
  NSNumber *n = code ? [[self finderCodes] objectForKey: code] : nil;

  return n ? (FSNIconsArrangement)[n integerValue] : FSNIconsArrangeNone;
}

+ (NSString *)finderCodeForArrangement:(FSNIconsArrangement)value
{
  NSArray *keys = [[self finderCodes] allKeysForObject: [NSNumber numberWithInteger: value]];

  return [keys count] ? [keys objectAtIndex: 0] : nil;
}

- (id)init
{
  self = [super init];

  if (self)
    {
      [self reload];
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(defaultsDidChange:)
                                                   name: NSUserDefaultsDidChangeNotification
                                                 object: nil];
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

- (void)postChange
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName: FSNColumnViewOptionsDidChangeNotification
                  object: self];
}

static BOOL
boolDefault(NSUserDefaults *defs, NSString *key, BOOL fallback)
{
  return [defs objectForKey: key] ? [defs boolForKey: key] : fallback;
}

- (BOOL)reload
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
  int size;
  BOOL icons, preview, previewColumn;
  FSNIconsArrangement arr;
  CGFloat width;
  NSString *code;
  BOOL changed;

  if ([defs objectForKey: FSNColumnViewTextSizeKey])
    size = [defs integerForKey: FSNColumnViewTextSizeKey];
  else if ([defs objectForKey: @"NSFontSize"])
    size = [defs integerForKey: @"NSFontSize"];
  else
    size = 12;
  size = [FSNIconsView clampedLabelTextSize: size];

  icons = boolDefault (defs, FSNColumnViewShowsIconsKey, YES);
  preview = boolDefault (defs, FSNColumnViewShowsIconPreviewKey, YES);
  previewColumn = boolDefault (defs, FSNColumnViewShowsPreviewColumnKey, YES);

  code = [defs stringForKey: FSNColumnViewArrangeByKey];
  arr = (code == nil) ? FSNIconsArrangeName
    : [FSNColumnViewOptions arrangementForFinderCode: code];

  width = [defs objectForKey: FSNColumnViewColumnWidthKey]
    ? FSNBrowserClampedColumnWidth ([defs integerForKey: FSNColumnViewColumnWidthKey])
    : FSNColumnViewDefaultColumnWidth;

  changed = (size != textSize || icons != showsIcons || preview != showsIconPreview
             || previewColumn != showsPreviewColumn || arr != arrangement
             || width != columnWidth);

  textSize = size;
  showsIcons = icons;
  showsIconPreview = preview;
  showsPreviewColumn = previewColumn;
  arrangement = arr;
  columnWidth = width;

  return changed;
}

- (void)defaultsDidChange:(NSNotification *)notification
{
  if ([self reload])
    {
      [self postChange];
    }
}

- (int)textSize
{
  return textSize;
}

/* Each setter writes its own key only: the other options stay unwritten
 * until they are changed, so their defaults can still change with a newer
 * release. */
- (void)setTextSize:(int)size
{
  size = [FSNIconsView clampedLabelTextSize: size];
  if (size == textSize)
    return;
  textSize = size;
  [[NSUserDefaults standardUserDefaults] setInteger: size forKey: FSNColumnViewTextSizeKey];
  [self postChange];
}

- (BOOL)showsIcons
{
  return showsIcons;
}

- (void)setShowsIcons:(BOOL)flag
{
  if (flag == showsIcons)
    return;
  showsIcons = flag;
  [[NSUserDefaults standardUserDefaults] setBool: flag forKey: FSNColumnViewShowsIconsKey];
  [self postChange];
}

- (BOOL)showsIconPreview
{
  return showsIconPreview;
}

- (void)setShowsIconPreview:(BOOL)flag
{
  if (flag == showsIconPreview)
    return;
  showsIconPreview = flag;
  [[NSUserDefaults standardUserDefaults] setBool: flag forKey: FSNColumnViewShowsIconPreviewKey];
  [self postChange];
}

- (BOOL)showsPreviewColumn
{
  return showsPreviewColumn;
}

- (void)setShowsPreviewColumn:(BOOL)flag
{
  if (flag == showsPreviewColumn)
    return;
  showsPreviewColumn = flag;
  [[NSUserDefaults standardUserDefaults] setBool: flag forKey: FSNColumnViewShowsPreviewColumnKey];
  [self postChange];
}

- (FSNIconsArrangement)arrangement
{
  return arrangement;
}

- (void)setArrangement:(FSNIconsArrangement)value
{
  NSString *code = [FSNColumnViewOptions finderCodeForArrangement: value];

  if (value == arrangement)
    return;
  arrangement = value;
  [[NSUserDefaults standardUserDefaults] setObject: (code ? code : FSNArrangeNoneCode)
                                            forKey: FSNColumnViewArrangeByKey];
  [self postChange];
}

- (CGFloat)columnWidth
{
  return columnWidth;
}

- (void)setColumnWidth:(CGFloat)width
{
  width = FSNBrowserClampedColumnWidth (width);
  if (width == columnWidth)
    return;
  columnWidth = width;
  [[NSUserDefaults standardUserDefaults] setInteger: (NSInteger)width
                                             forKey: FSNColumnViewColumnWidthKey];
  [self postChange];
}

@end
