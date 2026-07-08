/* GWArchiveOperation.h
 *
 * Background archive operation with progress UI.
 *
 * Models the same pattern as FileOpInfo: work runs on a background
 * queue, progress is reported to the main thread which updates a
 * simple progress panel.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface GWArchiveOperation : NSObject
{
  /* Operation parameters */
  NSString      *operationType;   /* "compress" or "extract"    */
  NSArray       *paths;           /* source paths               */
  NSString      *outputPath;      /* dest zip / dest directory  */

  /* Progress window */
  NSWindow      *progressWindow;
  NSProgressIndicator *progressBar;
  NSTextField   *statusField;
  NSButton      *cancelButton;

  /* State */
  BOOL           running;
  BOOL           cancelled;
  NSError       *error;
}

/**
 * Convenience: compress file paths into a zip archive with progress.
 * @param paths      Files/directories to compress.
 * @param outputPath Path for the output .zip file.
 * @return YES on success.
 */
+ (BOOL)compressPaths:(NSArray *)paths toArchive:(NSString *)outputPath;

/**
 * Convenience: extract a zip archive with progress.
 * @param archivePath Path to the .zip file.
 * @param destDir     Directory to extract into.
 * @return YES on success.
 */
+ (BOOL)extractArchive:(NSString *)archivePath toDirectory:(NSString *)destDir;

@end
