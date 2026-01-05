/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface SimpleColor : NSObject
{
    float _red;
    float _green;
    float _blue;
    float _alpha;
}

+ (SimpleColor *)colorWithRed:(float)red green:(float)green blue:(float)blue alpha:(float)alpha;
- (void)getRed:(float *)red green:(float *)green blue:(float *)blue alpha:(float *)alpha;

@end
