/* GWMetadataProvider.h
 *
 * Concrete FSNMetadataProvider for the Workspace application: adapts the
 * Finder metadata stack (GSFileMetadata over xattr / AppleDouble) to the
 * generic protocol FSNode reads through.  Registered on FSNodeRep at
 * startup so FSNode never touches the metadata implementation directly.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "FSNMetadataProvider.h"

@interface GWMetadataProvider : NSObject <FSNMetadataProvider>

+ (instancetype)sharedProvider;

@end
