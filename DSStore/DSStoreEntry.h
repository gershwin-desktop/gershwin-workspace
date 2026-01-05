/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "SimpleColor.h"  // Simple color replacement for headless systems

@interface DSStoreEntry : NSObject
{
    NSString *_filename;
    NSString *_code;
    NSString *_type;
    id _value;
}

@property (nonatomic, retain) NSString *filename;
@property (nonatomic, retain) NSString *code;
@property (nonatomic, retain) NSString *type;
@property (nonatomic, retain) id value;

- (id)initWithFilename:(NSString *)filename code:(NSString *)code type:(NSString *)type value:(id)value;
- (NSUInteger)byteLength;
- (NSData *)encode;

// Comparison methods for sorting
- (NSComparisonResult)compare:(DSStoreEntry *)other;

// CRUD convenience methods for all DS_Store field types
+ (DSStoreEntry *)iconLocationEntryForFile:(NSString *)filename x:(int)x y:(int)y;
+ (DSStoreEntry *)backgroundColorEntryForFile:(NSString *)filename red:(int)red green:(int)green blue:(int)blue;
+ (DSStoreEntry *)backgroundImageEntryForFile:(NSString *)filename imagePath:(NSString *)imagePath;
+ (DSStoreEntry *)viewStyleEntryForFile:(NSString *)filename style:(NSString *)style;
+ (DSStoreEntry *)iconSizeEntryForFile:(NSString *)filename size:(int)size;
+ (DSStoreEntry *)commentsEntryForFile:(NSString *)filename comments:(NSString *)comments;
+ (DSStoreEntry *)logicalSizeEntryForFile:(NSString *)filename size:(long long)size;
+ (DSStoreEntry *)physicalSizeEntryForFile:(NSString *)filename size:(long long)size;
+ (DSStoreEntry *)modificationDateEntryForFile:(NSString *)filename date:(NSDate *)date;
+ (DSStoreEntry *)booleanEntryForFile:(NSString *)filename code:(NSString *)code value:(BOOL)value;
+ (DSStoreEntry *)longEntryForFile:(NSString *)filename code:(NSString *)code value:(int32_t)value;

// Icon view options
+ (DSStoreEntry *)gridSpacingEntryForFile:(NSString *)filename spacing:(int)spacing;
+ (DSStoreEntry *)textSizeEntryForFile:(NSString *)filename size:(int)size;
+ (DSStoreEntry *)labelPositionEntryForFile:(NSString *)filename position:(int)position;  // 0=bottom, 1=right
+ (DSStoreEntry *)showItemInfoEntryForFile:(NSString *)filename show:(BOOL)show;
+ (DSStoreEntry *)showIconPreviewEntryForFile:(NSString *)filename show:(BOOL)show;
+ (DSStoreEntry *)iconArrangementEntryForFile:(NSString *)filename arrangement:(int)arrangement;
+ (DSStoreEntry *)sortByEntryForFile:(NSString *)filename sortBy:(NSString *)sortBy;

// Window chrome
+ (DSStoreEntry *)sidebarWidthEntryForFile:(NSString *)filename width:(int)width;
+ (DSStoreEntry *)showToolbarEntryForFile:(NSString *)filename show:(BOOL)show;
+ (DSStoreEntry *)showSidebarEntryForFile:(NSString *)filename show:(BOOL)show;
+ (DSStoreEntry *)showPathBarEntryForFile:(NSString *)filename show:(BOOL)show;
+ (DSStoreEntry *)showStatusBarEntryForFile:(NSString *)filename show:(BOOL)show;

// Label colors
+ (DSStoreEntry *)labelColorEntryForFile:(NSString *)filename color:(int)colorIndex;

// Value extraction methods
- (NSPoint)iconLocation;
- (SimpleColor *)backgroundColor;
- (NSString *)backgroundImagePath;
- (NSString *)viewStyle;
- (int)iconSize;
- (NSString *)comments;
- (long long)logicalSize;
- (long long)physicalSize;
- (NSDate *)modificationDate;
- (BOOL)booleanValue;
- (int32_t)longValue;

// Icon view options extraction
- (int)gridSpacing;
- (int)textSize;
- (int)labelPosition;
- (BOOL)showItemInfo;
- (BOOL)showIconPreview;
- (int)iconArrangement;
- (NSString *)sortBy;

// Window chrome extraction  
- (int)sidebarWidth;

// Label color extraction
- (int)labelColor;

@end
