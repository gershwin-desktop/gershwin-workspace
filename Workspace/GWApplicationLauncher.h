/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/**
 * GWApplicationLauncher provides centralized error handling for launching
 * both raw ELF executables and .app bundles. It monitors launched processes
 * for early failures and displays user-friendly error dialogs with stderr output.
 */
@interface GWApplicationLauncher : NSObject

/**
 * Launch an executable with error monitoring.
 * Monitors the process for 10 seconds and shows an error alert if it exits
 * with non-zero status during that time.
 * 
 * @param path The full path to the executable to launch
 * @param args Array of arguments to pass (can be nil or empty)
 */
+ (void)launchAndMonitor:(NSString *)path withArguments:(NSArray *)args;

/**
 * Launch an NSTask with error monitoring.
 * Monitors the task for 10 seconds and shows an error alert if it exits
 * with non-zero status during that time.
 * 
 * @param task A configured NSTask (already set launch path and arguments)
 */
+ (void)launchAndMonitorTask:(NSTask *)task;

@end
