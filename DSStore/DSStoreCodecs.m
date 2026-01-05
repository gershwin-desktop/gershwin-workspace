/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSStoreCodecs.h"

// Byte swapping functions
static uint32_t swap32(uint32_t x) {
    return ((x & 0xFF000000) >> 24) | ((x & 0x00FF0000) >> 8) |
           ((x & 0x0000FF00) << 8)  | ((x & 0x000000FF) << 24);
}

static uint64_t swap64(uint64_t x) {
    return ((x & 0xFF00000000000000ULL) >> 56) | ((x & 0x00FF000000000000ULL) >> 40) |
           ((x & 0x0000FF0000000000ULL) >> 24) | ((x & 0x000000FF00000000ULL) >> 8) |
           ((x & 0x00000000FF000000ULL) << 8)  | ((x & 0x0000000000FF0000ULL) << 24) |
           ((x & 0x000000000000FF00ULL) << 40) | ((x & 0x00000000000000FFULL) << 56);
}

// Icon location codec
@implementation DSILocCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    
    NSDictionary *point = (NSDictionary *)value;
    NSNumber *xNum = [point objectForKey:@"x"];
    NSNumber *yNum = [point objectForKey:@"y"];
    
    if (!xNum || !yNum) {
        return nil;
    }
    
    uint32_t x = [xNum unsignedIntValue];
    uint32_t y = [yNum unsignedIntValue];
    uint32_t padding1 = 0xFFFFFFFF;
    uint32_t padding2 = 0xFFFF0000;
    
    // Convert to big-endian
    x = swap32(x);
    y = swap32(y);
    padding1 = swap32(padding1);
    padding2 = swap32(padding2);
    
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:&x length:4];
    [data appendBytes:&y length:4];
    [data appendBytes:&padding1 length:4];
    [data appendBytes:&padding2 length:4];
    
    return data;
}

+ (id)decodeData:(NSData *)data {
    if ([data length] < 8) {
        return nil;
    }
    
    const uint8_t *bytes = [data bytes];
    uint32_t x = swap32(*(uint32_t *)bytes);
    uint32_t y = swap32(*(uint32_t *)(bytes + 4));
    
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInt:x], @"x",
            [NSNumber numberWithUnsignedInt:y], @"y",
            nil];
}

@end

// Property list codec
@implementation DSPlistCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSDictionary class]] && ![value isKindOfClass:[NSArray class]]) {
        return nil;
    }
    
    NSError *error = nil;
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:value
                                                                    format:NSPropertyListBinaryFormat_v1_0
                                                                   options:0
                                                                     error:&error];
    if (error) {
        NSLog(@"Error encoding plist: %@", [error localizedDescription]);
        return nil;
    }
    
    return plistData;
}

+ (id)decodeData:(NSData *)data {
    NSError *error = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:data
                                                         options:0
                                                          format:NULL
                                                           error:&error];
    if (error) {
        NSLog(@"Error decoding plist: %@", [error localizedDescription]);
        return nil;
    }
    
    return plist;
}

@end

// Boolean codec implementation
@implementation DSBoolCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    
    uint8_t boolValue = [(NSNumber *)value boolValue] ? 1 : 0;
    return [NSData dataWithBytes:&boolValue length:1];
}

+ (id)decodeData:(NSData *)data {
    if ([data length] < 1) {
        return [NSNumber numberWithBool:NO];
    }
    
    uint8_t value;
    [data getBytes:&value length:1];
    return [NSNumber numberWithBool:(value != 0)];
}

@end

// Integer codec implementation
@implementation DSIntegerCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    
    uint64_t intValue = [(NSNumber *)value unsignedLongLongValue];
    uint64_t bigEndianValue = swap64(intValue);
    
    return [NSData dataWithBytes:&bigEndianValue length:8];
}

+ (id)decodeData:(NSData *)data {
    if ([data length] < 4) {
        return [NSNumber numberWithInt:0];
    }
    
    if ([data length] >= 8) {
        uint64_t value;
        [data getBytes:&value length:8];
        return [NSNumber numberWithUnsignedLongLong:swap64(value)];
    } else {
        uint32_t value;
        [data getBytes:&value length:4];
        return [NSNumber numberWithUnsignedInt:swap32(value)];
    }
}

@end

// String codec implementation
@implementation DSStringCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    NSString *string = (NSString *)value;
    return [string dataUsingEncoding:NSUTF16BigEndianStringEncoding];
}

+ (id)decodeData:(NSData *)data {
    return [[[NSString alloc] initWithData:data 
                                  encoding:NSUTF16BigEndianStringEncoding] autorelease];
}

@end

// Blob codec implementation
@implementation DSBlobCodec

+ (NSData *)encodeValue:(id)value {
    if ([value isKindOfClass:[NSData class]]) {
        return (NSData *)value;
    }
    return nil;
}

+ (id)decodeData:(NSData *)data {
    return data;
}

@end

// Type codec implementation
@implementation DSTypeCodec

+ (NSData *)encodeValue:(id)value {
    if (![value isKindOfClass:[NSString class]] && ![value isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    
    uint32_t typeValue;
    if ([value isKindOfClass:[NSString class]]) {
        NSString *typeString = (NSString *)value;
        if ([typeString length] == 4) {
            const char *cString = [typeString UTF8String];
            typeValue = *(uint32_t *)cString;
        } else {
            typeValue = 0;
        }
    } else {
        typeValue = [(NSNumber *)value unsignedIntValue];
    }
    
    uint32_t bigEndianValue = swap32(typeValue);
    return [NSData dataWithBytes:&bigEndianValue length:4];
}

+ (id)decodeData:(NSData *)data {
    if ([data length] < 4) {
        return [NSNumber numberWithInt:0];
    }
    
    uint32_t value;
    [data getBytes:&value length:4];
    return [NSNumber numberWithUnsignedInt:swap32(value)];
}

@end

// Codec registry implementation
@implementation DSStoreCodecRegistry

static DSStoreCodecRegistry *sharedInstance = nil;

+ (DSStoreCodecRegistry *)sharedRegistry {
    if (!sharedInstance) {
        sharedInstance = [[DSStoreCodecRegistry alloc] init];
    }
    return sharedInstance;
}

- (id)init {
    if ((self = [super init])) {
        _codecs = [[NSMutableDictionary alloc] init];
        
        // Register default codecs
        [self registerCodec:[DSILocCodec class] forType:@"Iloc"];
        [self registerCodec:[DSPlistCodec class] forType:@"bwsp"];
        [self registerCodec:[DSPlistCodec class] forType:@"lsvp"];
        [self registerCodec:[DSPlistCodec class] forType:@"lsvP"];
        [self registerCodec:[DSPlistCodec class] forType:@"icvp"];
        [self registerCodec:[DSPlistCodec class] forType:@"icvP"];
        [self registerCodec:[DSBoolCodec class] forType:@"bool"];
        [self registerCodec:[DSIntegerCodec class] forType:@"long"];
        [self registerCodec:[DSIntegerCodec class] forType:@"shor"];
        [self registerCodec:[DSStringCodec class] forType:@"ustr"];
        [self registerCodec:[DSBlobCodec class] forType:@"blob"];
        [self registerCodec:[DSTypeCodec class] forType:@"type"];
    }
    return self;
}

- (void)dealloc {
    [_codecs release];
    [super dealloc];
}

- (void)registerCodec:(Class)codecClass forType:(NSString *)typeCode {
    [_codecs setObject:codecClass forKey:typeCode];
}

- (Class)codecForType:(NSString *)typeCode {
    return [_codecs objectForKey:typeCode];
}

- (NSData *)encodeValue:(id)value forType:(NSString *)typeCode {
    Class codecClass = [self codecForType:typeCode];
    if (codecClass && [codecClass respondsToSelector:@selector(encodeValue:)]) {
        return [codecClass encodeValue:value];
    }
    
    // Default to blob codec
    return [DSBlobCodec encodeValue:value];
}

- (id)decodeData:(NSData *)data forType:(NSString *)typeCode {
    Class codecClass = [self codecForType:typeCode];
    if (codecClass && [codecClass respondsToSelector:@selector(decodeData:)]) {
        return [codecClass decodeData:data];
    }
    
    // Default to blob codec
    return [DSBlobCodec decodeData:data];
}

@end
