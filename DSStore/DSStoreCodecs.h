/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// Codec protocol for encoding/decoding data types
@protocol DSStoreCodec <NSObject>
+ (NSData *)encodeValue:(id)value;
+ (id)decodeData:(NSData *)data;
@end

// Icon location codec (Iloc)
@interface DSILocCodec : NSObject <DSStoreCodec>
@end

// Property list codec (bwsp, lsvp, lsvP, etc.)
@interface DSPlistCodec : NSObject <DSStoreCodec>
@end

// Boolean codec (bool)
@interface DSBoolCodec : NSObject <DSStoreCodec>
@end

// Integer codec (long, shor)
@interface DSIntegerCodec : NSObject <DSStoreCodec>
@end

// String codec (ustr)
@interface DSStringCodec : NSObject <DSStoreCodec>
@end

// Blob codec (blob)
@interface DSBlobCodec : NSObject <DSStoreCodec>
@end

// Type codec (type)
@interface DSTypeCodec : NSObject <DSStoreCodec>
@end

// Codec registry
@interface DSStoreCodecRegistry : NSObject
{
    NSMutableDictionary *_codecs;
}

+ (DSStoreCodecRegistry *)sharedRegistry;

- (void)registerCodec:(Class)codecClass forType:(NSString *)typeCode;
- (Class)codecForType:(NSString *)typeCode;
- (NSData *)encodeValue:(id)value forType:(NSString *)typeCode;
- (id)decodeData:(NSData *)data forType:(NSString *)typeCode;

@end
