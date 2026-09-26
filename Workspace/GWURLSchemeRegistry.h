/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef GWURLSCHEMEREGISTRY_H
#define GWURLSCHEMEREGISTRY_H

#import <Foundation/Foundation.h>

/** Domain of the errors for a handler whose desktop file is malformed. */
extern NSString * const GWURLSchemeRegistryErrorDomain;

/**
 * The GNUstep application registry as the scheme lookup sees it.  Kept
 * behind a protocol so the lookup stays Foundation-only: Workspace answers
 * it from NSWorkspace, tests from fixture bundles.
 */
@protocol GWSchemeApplicationSource <NSObject>
/** Full paths of the application bundles registered for scheme, the
 * preferred one first. */
- (NSArray *)applicationPathsForScheme:(NSString *)scheme;
@end

/** What opens a URL: either a GNUstep application or a command line. */
@interface GWURLHandler : NSObject
{
  NSString *applicationPath;
  NSArray *arguments;
  NSString *desktopFilePath;
}
/** The GNUstep application bundle, nil for a freedesktop handler. */
- (NSString *)applicationPath;
/** The complete argument vector for a freedesktop handler, the absolute
 * program path first; nil for a GNUstep application. */
- (NSArray *)arguments;
/** The desktop file the arguments come from. */
- (NSString *)desktopFilePath;
@end

/**
 * Finds what opens a URL of a given scheme.  A GNUstep application that
 * declares the scheme in its Info.plist (GSSchemes, NSURLTypes or
 * CFBundleURLTypes) wins; otherwise the freedesktop x-scheme-handler/<scheme>
 * association decides, as the mime-apps specification orders it.
 */
@interface GWURLSchemeRegistry : NSObject
{
  NSDictionary *environment;
  id<GWSchemeApplicationSource> applicationSource;
}

/** env supplies HOME, PATH, XDG_CONFIG_HOME, XDG_CONFIG_DIRS,
 * XDG_DATA_HOME, XDG_DATA_DIRS and XDG_CURRENT_DESKTOP; source may be nil. */
- (instancetype)initWithEnvironment:(NSDictionary *)env
                  applicationSource:(id<GWSchemeApplicationSource>)source;

/** Returns nil without an error when nothing usable is registered, and nil
 * with an error when the chosen desktop file is malformed. */
- (GWURLHandler *)handlerForURL:(NSURL *)url error:(NSError **)error;

@end

#endif
