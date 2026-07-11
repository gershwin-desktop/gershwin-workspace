/* GWMetaArchive.h
 *
 * libarchive wrapper for zip read/write with Mac metadata.
 *
 * Uses libarchive's built-in AppleDouble support (archive_entry_mac_metadata)
 * to round-trip macOS metadata through zip's __MACOSX directory entries.
 *
 * The caller provides a list of file paths and an output path. For each
 * file the compressor reads its AppleDouble metadata via GSFileMetadata
 * and attaches it to the archive entry. On extraction each entry's
 * AppleDouble is written back as xattrs (or sidecar).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWMETAARCHIVE_H
#define GWMETAARCHIVE_H

#import <Foundation/Foundation.h>

@interface GWMetaArchive : NSObject

/**
 * Compress an array of file paths into a zip archive, preserving
 * macOS metadata (FinderInfo, ResourceFork, etc.) as AppleDouble
 * entries inside __MACOSX.
 *
 * @param filePaths  Array of absolute paths (NSString) to compress.
 * @param outputPath Absolute path for the output .zip file.
 * @param error      Optional output error.
 * @return YES on success.
 */
+ (BOOL)compressPaths:(NSArray *)filePaths
          toArchiveAt:(NSString *)outputPath
                error:(NSError **)error;

/**
 * Compress a single directory tree preserving relative structure
 * and macOS metadata.
 */
+ (BOOL)compressDirectory:(NSString *)dirPath
              toArchiveAt:(NSString *)outputPath
                    error:(NSError **)error;

/**
 * Extract a zip/archive to a destination directory, restoring
 * macOS metadata (xattrs) for every entry that carries AppleDouble.
 * Supports all formats that libarchive can read (tar, 7z, rar, iso, ...).
 *
 * @param archivePath  Path to the archive file.
 * @param destDir      Directory to extract into (created if needed).
 * @param error        Optional output error.
 * @return YES on success.
 */
+ (BOOL)extractArchive:(NSString *)archivePath
                  toDir:(NSString *)destDir
                 error:(NSError **)error;

/**
 * Returns YES if the given file extension corresponds to an archive
 * format that libarchive can read (zip, tar, 7z, rar, iso, ...).
 */
+ (BOOL)isArchiveExtension:(NSString *)ext;

@end

#endif /* GWMETAARCHIVE_H */
