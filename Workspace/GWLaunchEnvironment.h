/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWLAUNCHENVIRONMENT_H
#define GWLAUNCHENVIRONMENT_H

#import <Foundation/Foundation.h>

/* The table of the toolkit integration variables: the GTK/Qt modules that
 * put an application's menus into Menu, and the preload that gives GTK 3
 * header-bar windows the window manager's title bar.  Installed by
 * gershwin-system; an array of groups, each with an "Environment"
 * dictionary and an optional "Requires" path that has to exist for the
 * group to apply (the component it names is optional). */
#define GW_TOOLKIT_INTEGRATION_TABLE \
  @"/System/Library/Preferences/ToolkitIntegration.plist"

/* Whether the executable at `path` is a binary of another operating system
 * than the one Workspace runs on: on NextBSD, FreeBSD, NetBSD and OpenBSD an
 * ELF file that carries neither the system's EI_OSABI nor its ABI-tag note
 * (a Linux program, run by the system's Linux compatibility), or one of
 * another ELF class or byte order.  The kernel tells native binaries from
 * the others by the same marks.  Scripts, unreadable files and every file
 * on a Linux host count as native, so nothing changes for them. */
extern BOOL GWIsForeignExecutable(NSString *path);

/* A copy of `environment` (nil: this process' own) for launching `path`.
 * For a native executable, each value of the integration table is added to
 * its colon-separated variable unless it is already there; for a foreign
 * one, every variable of the table and LD_PRELOAD and LD_LIBRARY_PATH are
 * removed: native libraries and plugins cannot load into it, and its
 * run-time linker only complains about them. */
extern NSDictionary *GWEnvironmentForExecutable(NSString *path,
                                                NSDictionary *environment);

#endif
