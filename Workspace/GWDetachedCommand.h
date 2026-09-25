/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWDETACHEDCOMMAND_H
#define GWDETACHEDCOMMAND_H

#import <Foundation/Foundation.h>

/**
 * Runs a user supplied shell command (a global shortcut) as a process that
 * is not tied to Workspace: it gets its own session, is reparented to init
 * and inherits no descriptor but /dev/null on stdin, stdout and stderr.
 *
 * Such commands often start long-lived programs.  A descriptor they
 * inherited from Workspace (its X connection, its NSMessagePort sockets to
 * gdnc, Menu, the WindowManager, its own DO listeners) would stay open after
 * Workspace exits; the peers then keep writing to a socket nobody reads.
 */
@interface GWDetachedCommand : NSObject

/** Starts `$SHELL -c command` (/bin/sh without SHELL).  Returns NO when the
 * process could not be started. */
+ (BOOL)launchShellCommand:(NSString *)command;

@end

#endif
