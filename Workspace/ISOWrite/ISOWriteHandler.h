/* ISOWriteHandler.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Handler for detecting and processing ISO file drops onto physical devices.
 * This class provides the integration point between the Workspace UI and
 * the ISOWriteOperation.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#ifndef ISOWRITEHANDLER_H
#define ISOWRITEHANDLER_H

#import <Foundation/Foundation.h>

@class ISOWriteOperation;
@class FSNode;

/**
 * ISOWriteHandler detects ISO file drops onto physical device mount points
 * and coordinates the ISO write operation.
 *
 * Usage:
 * 1. Call +canHandleISODrop:ontoNode: to check if the drop should be handled
 * 2. Call +handleISODrop:ontoNode: to process the drop
 */
@interface ISOWriteHandler : NSObject

/**
 * Check if a file path is an ISO image
 */
+ (BOOL)isISOFile:(NSString *)path;

/**
 * Check if a node represents a physical block device mount point
 * suitable for ISO writing (e.g., USB drive, SD card)
 */
+ (BOOL)isPhysicalDeviceNode:(FSNode *)node;

/**
 * Check if an ISO file drop onto a node should trigger the ISO write flow.
 * Returns YES if:
 *   - The dropped file is an ISO image (.iso, .img)
 *   - The target node is a mount point for a physical device
 *   - The device is not the system disk
 */
+ (BOOL)canHandleISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode;

/**
 * Return nil if the drop is valid and will be handled, otherwise an explanatory
 * message describing why the ISO drop would be rejected. This is intended for
 * diagnostics and more informative logging from callers such as UI drag code.
 */
+ (NSString *)validationMessageForISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode;

/**
 * Handle an ISO drop by starting the confirmation and write flow.
 * This method runs asynchronously and will show the confirmation dialog.
 *
 * @param isoPath Path to the ISO file being dropped
 * @param targetNode The mount point node where the ISO was dropped
 * @return YES if the operation was started, NO if validation failed
 */
+ (BOOL)handleISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode;

/**
 * Check if any ISO write operation is currently in progress
 */
+ (BOOL)isOperationInProgress;

/**
 * Get the shared list of active operations
 */
+ (NSArray *)activeOperations;

@end

#endif /* ISOWRITEHANDLER_H */
