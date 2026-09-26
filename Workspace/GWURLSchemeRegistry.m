/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWURLSchemeRegistry.h"

NSString * const GWURLSchemeRegistryErrorDomain = @"GWURLSchemeRegistryErrorDomain";

@implementation GWURLHandler
- (NSString *)applicationPath { return applicationPath; }
- (NSArray *)arguments { return arguments; }
- (NSString *)desktopFilePath { return desktopFilePath; }
@end

@implementation GWURLSchemeRegistry

- (instancetype)initWithEnvironment:(NSDictionary *)env
                  applicationSource:(id<GWSchemeApplicationSource>)source
{
  self = [super init];
  return self;
}

- (GWURLHandler *)handlerForURL:(NSURL *)url error:(NSError **)error
{
  return nil;
}

@end
