/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import "../DSStore.h"

int main(int argc, const char * argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (argc < 2) {
        printf("usage: create_dsstore <path-to-.DS_Store>\n");
        [pool drain];
        return 1;
    }

    NSString *path = [NSString stringWithUTF8String:argv[1]];
    DSStore *store = [DSStore createStoreAtPath:path withEntries:nil];
    if (!store) {
        printf("Error: failed to create DSStore object\n");
        [pool drain];
        return 1;
    }

    if (![store save]) {
        printf("Error: failed to save .DS_Store to %s\n", [path UTF8String]);
        [pool drain];
        return 1;
    }

    printf("Created .DS_Store at %s\n", [path UTF8String]);

    [pool drain];
    return 0;
}
