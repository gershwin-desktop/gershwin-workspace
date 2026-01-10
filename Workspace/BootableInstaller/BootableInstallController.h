/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BOOTABLE_INSTALL_CONTROLLER_H
#define BOOTABLE_INSTALL_CONTROLLER_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "BootEnvironmentDetector.h"
#import "BootPartitionValidator.h"
#import "BootableFileCopier.h"
#import "BootloaderInstaller.h"

@class FSNode;

/**
 * Installation state machine states
 */
typedef NS_ENUM(NSInteger, BootableInstallState) {
  BootableInstallStateIdle = 0,
  BootableInstallStateValidating,
  BootableInstallStateConfirming,
  BootableInstallStateMounting,
  BootableInstallStateCopying,
  BootableInstallStateConfiguring,
  BootableInstallStateBootloader,
  BootableInstallStateVerifying,
  BootableInstallStateUnmounting,
  BootableInstallStateCompleted,
  BootableInstallStateFailed,
  BootableInstallStateCancelled
};

/**
 * Installation log entry
 */
@interface BootableInstallLogEntry : NSObject
{
  NSDate *_timestamp;
  NSString *_level;      // "INFO", "WARNING", "ERROR"
  NSString *_phase;
  NSString *_message;
}

@property (nonatomic, copy) NSDate *timestamp;
@property (nonatomic, copy) NSString *level;
@property (nonatomic, copy) NSString *phase;
@property (nonatomic, copy) NSString *message;

+ (instancetype)infoWithPhase:(NSString *)phase message:(NSString *)msg;
+ (instancetype)warningWithPhase:(NSString *)phase message:(NSString *)msg;
+ (instancetype)errorWithPhase:(NSString *)phase message:(NSString *)msg;

- (NSString *)formattedString;

@end


/**
 * Installation result
 */
@interface BootableInstallResult : NSObject
{
  BOOL _success;
  NSString *_errorMessage;
  NSString *_errorPhase;
  NSArray *_logEntries;
  NSTimeInterval _totalTime;
  NSDictionary *_copyStats;
}

@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *errorPhase;
@property (nonatomic, copy) NSArray *logEntries;
@property (nonatomic, assign) NSTimeInterval totalTime;
@property (nonatomic, copy) NSDictionary *installStats;

+ (instancetype)success;
+ (instancetype)failureWithError:(NSString *)error phase:(NSString *)phase;

- (NSString *)fullLogAsString;
- (BOOL)writeLogToFile:(NSString *)path;

@end


/**
 * BootableInstallController is the main orchestrator for bootable OS installation.
 *
 * Responsibilities:
 * - Manages UI flow and user confirmations
 * - Shows experimental warning dialog
 * - Asks about /home exclusion
 * - Coordinates validation → copy → bootloader sequence
 * - Shows progress window
 * - Handles errors with NSAlert
 * - Performs cleanup on failure
 */
@interface BootableInstallController : NSObject <BootableFileCopierDelegate,
                                                  BootloaderInstallerDelegate>
{
  // Components
  BootPartitionValidator *_validator;
  BootEnvironmentDetector *_detector;
  BootableFileCopier *_copier;
  BootloaderInstaller *_bootloaderInstaller;
  
  // Environment info
  BootEnvironmentInfo *_environment;
  
  // Source and target
  FSNode *_sourceNode;
  FSNode *_targetNode;
  NSString *_sourcePath;
  NSString *_targetPath;
  NSString *_targetDevice;
  NSString *_targetDisk;
  NSString *_espMountPoint;
  NSString *_bootMountPoint;
  
  // Options
  BOOL _excludeHome;
  
  // State
  BootableInstallState _state;
  NSMutableArray *_logEntries;
  NSDate *_startTime;
  
  // Mount tracking for cleanup
  NSMutableArray *_mountedPaths;
  BOOL _targetWasMounted;
  
  // UI
  NSWindow *_progressWindow;
  NSProgressIndicator *_progressIndicator;
  NSTextField *_statusField;
  NSTextField *_phaseField;
  NSTextField *_fileField;
  NSButton *_cancelButton;
  
  NSFileManager *_fm;
}

@property (nonatomic, readonly) BootableInstallState state;
@property (nonatomic, readonly) BOOL isRunning;

#pragma mark - Singleton

/**
 * Shared controller instance
 */
+ (instancetype)sharedController;

#pragma mark - Main Entry Point

/**
 * Perform bootable installation from source to target.
 * This is the main entry point called from drag-and-drop.
 *
 * @param sourceNode The source root filesystem node (must be /)
 * @param targetNode The target partition node
 */
- (void)performInstallFromSource:(FSNode *)sourceNode
                        toTarget:(FSNode *)targetNode;

/**
 * Check if an installation is currently in progress
 */
- (BOOL)isInstallationInProgress;

/**
 * Cancel current installation
 */
- (void)cancelInstallation;

#pragma mark - Drag-and-Drop Support

/**
 * Check if a drag of root filesystem to a target should be accepted.
 * Called from GWDesktopView during draggingEntered/draggingUpdated.
 *
 * @param sourceNode The source node being dragged
 * @param targetNode The potential target node
 * @return YES if the drag should be accepted for potential drop
 */
- (BOOL)canAcceptDragOfSource:(FSNode *)sourceNode
                     toTarget:(FSNode *)targetNode;

/**
 * Get failure reason for last canAcceptDrag check
 */
- (NSString *)lastDragRefusalReason;

#pragma mark - User Confirmation Dialogs

/**
 * Show experimental warning dialog.
 * Cancel is the default button.
 *
 * @return YES if user clicked "Continue at Own Risk", NO if cancelled
 */
- (BOOL)showExperimentalWarning;

/**
 * Ask user whether to exclude /home from the copy.
 *
 * @return YES to exclude /home, NO to include it
 */
- (BOOL)askExcludeHome;

/**
 * Show error alert and return user choice
 */
- (void)showErrorAlert:(NSString *)message title:(NSString *)title;

/**
 * Show success completion dialog
 */
- (void)showSuccessDialog:(NSDictionary *)stats;

#pragma mark - Progress Window

/**
 * Create and show the progress window
 */
- (void)showProgressWindow;

/**
 * Update progress window with current status
 */
- (void)updateProgressWithPhase:(NSString *)phase
                         status:(NSString *)status
                       progress:(double)progress
                    currentFile:(NSString *)file;

/**
 * Close the progress window
 */
- (void)closeProgressWindow;

#pragma mark - Installation Phases

/**
 * Phase 1: Validate target partition
 */
- (BOOL)phaseValidate;

/**
 * Phase 2: Mount target filesystem(s)
 */
- (BOOL)phaseMountTarget;

/**
 * Phase 3: Create directory layout
 */
- (BOOL)phaseCreateLayout;

/**
 * Phase 4: Copy filesystem
 */
- (BOOL)phaseCopyFilesystem;

/**
 * Phase 5: Configure fstab and system files
 */
- (BOOL)phaseConfigureSystem;

/**
 * Phase 6: Install bootloader
 */
- (BOOL)phaseInstallBootloader;

/**
 * Phase 7: Verify installation
 */
- (BOOL)phaseVerify;

/**
 * Phase 8: Cleanup and unmount
 */
- (BOOL)phaseCleanup;

#pragma mark - Mount Operations

/**
 * Mount a partition at a path
 */
- (BOOL)mountDevice:(NSString *)device
            atPath:(NSString *)mountPoint
          readOnly:(BOOL)ro
             error:(NSError **)error;

/**
 * Unmount a path
 */
- (BOOL)unmountPath:(NSString *)path
              error:(NSError **)error;

/**
 * Unmount all paths we mounted (for cleanup)
 */
- (void)unmountAllMounted;

/**
 * Sync filesystem buffers
 */
- (void)syncFilesystems;

#pragma mark - Error Handling

/**
 * Handle a fatal error during installation
 */
- (void)handleFatalError:(NSString *)error inPhase:(NSString *)phase;

/**
 * Perform cleanup after failure
 */
- (void)performFailureCleanup;

#pragma mark - Logging

/**
 * Log an info message
 */
- (void)logInfo:(NSString *)message;

/**
 * Log a warning
 */
- (void)logWarning:(NSString *)message;

/**
 * Log an error
 */
- (void)logError:(NSString *)message;

/**
 * Get all log entries
 */
- (NSArray *)logEntries;

/**
 * Save log to file
 */
- (BOOL)saveLogToPath:(NSString *)path;

#pragma mark - State Machine

/**
 * Transition to a new state
 */
- (void)transitionToState:(BootableInstallState)newState;

/**
 * Get string description of current state
 */
- (NSString *)stateDescription;

@end


#pragma mark - Notifications

/**
 * Posted when bootable installation starts
 * userInfo: @{ @"source": sourcePath, @"target": targetPath }
 */
extern NSString * const BootableInstallDidStartNotification;

/**
 * Posted when installation progress updates
 * userInfo: @{ @"phase": phase, @"progress": @(0.0-1.0), @"status": status }
 */
extern NSString * const BootableInstallProgressNotification;

/**
 * Posted when installation completes successfully
 * userInfo: @{ @"stats": copyStats, @"time": @(elapsedTime) }
 */
extern NSString * const BootableInstallDidCompleteNotification;

/**
 * Posted when installation fails
 * userInfo: @{ @"error": errorMessage, @"phase": failedPhase }
 */
extern NSString * const BootableInstallDidFailNotification;

/**
 * Posted when installation is cancelled
 */
extern NSString * const BootableInstallDidCancelNotification;

#endif /* BOOTABLE_INSTALL_CONTROLLER_H */
