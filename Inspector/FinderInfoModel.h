/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
@protocol FinderInfoLocking;


extern NSString * const GWFinderInfoErrorDomain;

/**
 * Editable snapshot of the Finder metadata of one file, as shown by the
 * Inspector's Finder Info pane.  Values are loaded from GSFileMetadata (and
 * the file's immutable flag), changed in memory and written back as a unit
 * by -writeToPath:error:, so the UI can offer Apply and Revert.
 */
@interface FinderInfoModel : NSObject
{
  NSString *_path;
  id<FinderInfoLocking> _locker;
  BOOL _isDirectory;
  BOOL _hideExtension;
  BOOL _locked;
  BOOL _nameLocked;
  BOOL _stationery;
  BOOL _invisible;
  NSInteger _labelNumber;
  NSString *_typeCode;
  NSString *_creatorCode;
  NSString *_comment;
  NSData *_customIconICNS;
  BOOL _hasCustomIcon;
  BOOL _iconChanged;
  BOOL _commentChanged;
}

+ (instancetype)modelForPath:(NSString *)path;

/** The object that reads and changes the immutable flag; replaceable by tests. */
+ (void)setDefaultLocker:(id<FinderInfoLocking>)locker;

/** YES when this platform can lock a file against modification (BSD
 *  UF_IMMUTABLE, Linux FS_IMMUTABLE_FL). */
+ (BOOL)supportsLocking;

/** A code field is valid when empty (no code) or exactly four printable
 *  ASCII characters. */
+ (BOOL)isValidCodeString:(NSString *)string;
+ (uint32_t)codeFromString:(NSString *)string;
+ (NSString *)stringFromCode:(uint32_t)code;

@property (nonatomic, readonly) NSString *path;
/** Folders keep a window rectangle where files keep type and creator, and
 *  Finder stores a folder's custom icon in an "Icon\r" file, so those fields
 *  are not editable for them. */
@property (nonatomic, readonly) BOOL isDirectory;
@property (nonatomic) BOOL hideExtension;
/** Finder's "Locked" checkbox: the user-immutable flag, not kNameLocked. */
@property (nonatomic) BOOL locked;
/** kNameLocked in fdFlags. */
@property (nonatomic) BOOL nameLocked;
@property (nonatomic) BOOL stationery;
@property (nonatomic) BOOL invisible;
@property (nonatomic) NSInteger labelNumber;
@property (nonatomic, copy) NSString *typeCode;
@property (nonatomic, copy) NSString *creatorCode;
@property (nonatomic, copy) NSString *comment;
@property (nonatomic, readonly) BOOL hasCustomIcon;
/** icns data currently stored or pending; nil when there is none. */
@property (nonatomic, readonly) NSData *customIconICNS;

/** Replace the custom icon with the image, rendered into an icns container. */
- (BOOL)setCustomIconFromImage:(NSImage *)image;
- (void)clearCustomIcon;

/** Writes every field back to the file.  A locked file is unlocked for the
 *  write and locked again afterwards. */
- (BOOL)write:(NSError **)error;

@end

/** Builders for the on-disk custom icon payload. */
@interface FinderInfoIconBuilder : NSObject
/** icns container with PNG elements ic07/ic08/ic09. */
+ (NSData *)icnsDataFromImage:(NSImage *)image;
@end
