/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "../GWThumbnailer.h"

@interface AppImageThumbnailer : NSObject <TMBProtocol>
{
	NSString *_lastExtension;
}

@end
