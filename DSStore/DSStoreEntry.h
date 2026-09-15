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

// Binary plist entries (bwsp, lsvp, ...) and legacy window geometry (fwi0)
+ (DSStoreEntry *)plistEntryForFile:(NSString *)filename code:(NSString *)code dictionary:(NSDictionary *)dictionary;
+ (DSStoreEntry *)browserWindowEntryForFile:(NSString *)filename windowBounds:(NSRect)windowBounds sidebarWidth:(int)sidebarWidth;
+ (DSStoreEntry *)windowGeometryEntryForFile:(NSString *)filename rect:(NSRect)rect viewStyle:(NSString *)viewStyle;
+ (DSStoreEntry *)listViewEntryForFile:(NSString *)filename sortColumn:(NSString *)sortColumn ascending:(BOOL)ascending textSize:(int)textSize iconSize:(int)iconSize columnWidths:(NSDictionary *)columnWidths columnVisible:(NSDictionary *)columnVisible;

// Preserving variants: like the plain factories, but when @p existing is a
// non-nil entry for the same code, only the fields Workspace owns are
// modified and every other byte/key is carried forward unchanged.  This is
// what makes Workspace a cooperative editor of .DS_Store rather than its
// owner: unknown fields in partially-understood records (icvo, fwi0, bwsp,
// lsvp, BKGD, Iloc) must survive a save cycle.
+ (DSStoreEntry *)iconLocationEntryForFile:(NSString *)filename x:(int)x y:(int)y preserving:(DSStoreEntry *)existing;
+ (DSStoreEntry *)backgroundColorEntryForFile:(NSString *)filename red:(int)red green:(int)green blue:(int)blue preserving:(DSStoreEntry *)existing;
+ (DSStoreEntry *)iconSizeEntryForFile:(NSString *)filename size:(int)size preserving:(DSStoreEntry *)existing;
+ (DSStoreEntry *)windowGeometryEntryForFile:(NSString *)filename rect:(NSRect)rect viewStyle:(NSString *)viewStyle preserving:(DSStoreEntry *)existing;
+ (DSStoreEntry *)browserWindowEntryForFile:(NSString *)filename windowBounds:(NSRect)windowBounds sidebarWidth:(int)sidebarWidth preserving:(DSStoreEntry *)existing;
+ (DSStoreEntry *)listViewEntryForFile:(NSString *)filename sortColumn:(NSString *)sortColumn ascending:(BOOL)ascending textSize:(int)textSize iconSize:(int)iconSize columnWidths:(NSDictionary *)columnWidths columnVisible:(NSDictionary *)columnVisible preserving:(DSStoreEntry *)existing;

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
