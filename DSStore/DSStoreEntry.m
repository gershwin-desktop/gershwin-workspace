/*
 * Copyright (c) 2025-26 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DSStoreEntry.h"
#include <arpa/inet.h>  // For htonl, ntohl, htons, ntohs

// Byte swapping functions for portability
static inline uint32_t swapInt32HostToBig(uint32_t x) {
    return htonl(x);
}

static inline uint32_t swapInt32BigToHost(uint32_t x) {
    return ntohl(x);
}

static inline uint16_t swapInt16HostToBig(uint16_t x) {
    return htons(x);
}

static inline uint16_t swapInt16BigToHost(uint16_t x) {
    return ntohs(x);
}

@implementation DSStoreEntry

@synthesize filename = _filename;
@synthesize code = _code;
@synthesize type = _type;
@synthesize value = _value;

- (id)initWithFilename:(NSString *)filename code:(NSString *)code type:(NSString *)type value:(id)value {
    self = [super init];
    if (self) {
        self.filename = filename;
        self.code = code;
        self.type = type;
        self.value = value;
    }
    return self;
}

- (void)dealloc {
    [_filename release];
    [_code release];
    [_type release];
    [_value release];
    [super dealloc];
}

- (NSUInteger)byteLength {
    NSData *utf16Data = [self.filename dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    NSUInteger length = 4 + [utf16Data length] + 8; // 4 bytes for length + filename + 4 bytes code + 4 bytes type
    
    NSString *entryType = self.type;
    
    if ([entryType isEqualToString:@"bool"]) {
        length += 1;
    } else if ([entryType isEqualToString:@"long"] || [entryType isEqualToString:@"shor"]) {
        length += 4;
    } else if ([entryType isEqualToString:@"blob"]) {
        if ([self.value isKindOfClass:[NSData class]]) {
            length += 4 + [(NSData *)self.value length];
        }
    } else if ([entryType isEqualToString:@"ustr"]) {
        if ([self.value isKindOfClass:[NSString class]]) {
            NSData *valueUtf16 = [(NSString *)self.value dataUsingEncoding:NSUTF16BigEndianStringEncoding];
            length += 4 + [valueUtf16 length];
        }
    } else if ([entryType isEqualToString:@"type"]) {
        length += 4;
    } else if ([entryType isEqualToString:@"comp"] || [entryType isEqualToString:@"dutc"]) {
        length += 8;
    }
    
    return length;
}

static uint32_t swapBytes32(uint32_t value) {
    return ((value & 0xFF000000) >> 24) |
           ((value & 0x00FF0000) >> 8) |
           ((value & 0x0000FF00) << 8) |
           ((value & 0x000000FF) << 24);
}

static uint64_t swapBytes64(uint64_t value) {
    return ((value & 0xFF00000000000000ULL) >> 56) |
           ((value & 0x00FF000000000000ULL) >> 40) |
           ((value & 0x0000FF0000000000ULL) >> 24) |
           ((value & 0x000000FF00000000ULL) >> 8) |
           ((value & 0x00000000FF000000ULL) << 8) |
           ((value & 0x0000000000FF0000ULL) << 24) |
           ((value & 0x000000000000FF00ULL) << 40) |
           ((value & 0x00000000000000FFULL) << 56);
}

- (NSData *)encode {
    NSMutableData *data = [NSMutableData data];
    
    // Write filename length and filename in UTF-16BE
    NSData *utf16Data = [self.filename dataUsingEncoding:NSUTF16BigEndianStringEncoding];
    uint32_t filenameLength = swapBytes32([utf16Data length] / 2);
    [data appendBytes:&filenameLength length:4];
    [data appendData:utf16Data];
    
    // Write code (4 bytes)
    NSData *codeData = [self.code dataUsingEncoding:NSASCIIStringEncoding];
    if ([codeData length] >= 4) {
        [data appendBytes:[codeData bytes] length:4];
    } else {
        // Pad with zeros if code is shorter than 4 bytes
        char codeBuf[4] = {0};
        memcpy(codeBuf, [codeData bytes], [codeData length]);
        [data appendBytes:codeBuf length:4];
    }
    
    // Write type (4 bytes)  
    NSData *typeData = [self.type dataUsingEncoding:NSASCIIStringEncoding];
    if ([typeData length] >= 4) {
        [data appendBytes:[typeData bytes] length:4];
    } else {
        // Pad with zeros if type is shorter than 4 bytes
        char typeBuf[4] = {0};
        memcpy(typeBuf, [typeData bytes], [typeData length]);
        [data appendBytes:typeBuf length:4];
    }
    
    // Write value based on type
    if ([self.type isEqualToString:@"bool"]) {
        BOOL boolValue = [self.value boolValue];
        uint8_t byteValue = boolValue ? 1 : 0;
        [data appendBytes:&byteValue length:1];
    } else if ([self.type isEqualToString:@"long"] || [self.type isEqualToString:@"shor"]) {
        uint32_t longValue = swapBytes32([self.value unsignedIntValue]);
        [data appendBytes:&longValue length:4];
    } else if ([self.type isEqualToString:@"blob"]) {
        if ([self.value isKindOfClass:[NSData class]]) {
            NSData *blobData = (NSData *)self.value;
            uint32_t blobLength = swapBytes32([blobData length]);
            [data appendBytes:&blobLength length:4];
            [data appendData:blobData];
        }
    } else if ([self.type isEqualToString:@"ustr"]) {
        if ([self.value isKindOfClass:[NSString class]]) {
            NSData *valueUtf16 = [(NSString *)self.value dataUsingEncoding:NSUTF16BigEndianStringEncoding];
            uint32_t stringLength = swapBytes32([valueUtf16 length] / 2);
            [data appendBytes:&stringLength length:4];
            [data appendData:valueUtf16];
        }
    } else if ([self.type isEqualToString:@"type"]) {
        if ([self.value isKindOfClass:[NSString class]]) {
            NSData *typeValue = [(NSString *)self.value dataUsingEncoding:NSASCIIStringEncoding];
            if ([typeValue length] >= 4) {
                [data appendBytes:[typeValue bytes] length:4];
            } else {
                char typeBuf[4] = {0};
                memcpy(typeBuf, [typeValue bytes], [typeValue length]);
                [data appendBytes:typeBuf length:4];
            }
        }
    } else if ([self.type isEqualToString:@"comp"] || [self.type isEqualToString:@"dutc"]) {
        uint64_t longLongValue = swapBytes64([self.value unsignedLongLongValue]);
        [data appendBytes:&longLongValue length:8];
    }
    
    return data;
}

- (NSComparisonResult)compare:(DSStoreEntry *)other {
    NSString *selfLower = [self.filename lowercaseString];
    NSString *otherLower = [other.filename lowercaseString];
    
    NSComparisonResult result = [selfLower compare:otherLower];
    if (result == NSOrderedSame) {
        return [self.code compare:other.code];
    }
    return result;
}

// CRUD convenience methods for all DS_Store field types

+ (DSStoreEntry *)iconLocationEntryForFile:(NSString *)filename x:(int)x y:(int)y {
    NSMutableData *locationData = [NSMutableData dataWithCapacity:16];
    uint32_t xBig = swapInt32HostToBig(x);
    uint32_t yBig = swapInt32HostToBig(y);
    uint64_t unknown = 0xFFFFFFFFFFFF0000; // Standard unknown bytes
    
    [locationData appendBytes:&xBig length:4];
    [locationData appendBytes:&yBig length:4];
    [locationData appendBytes:&unknown length:8];
    
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"Iloc" type:@"blob" value:locationData] autorelease];
}

+ (DSStoreEntry *)backgroundColorEntryForFile:(NSString *)filename red:(int)red green:(int)green blue:(int)blue {
    NSMutableData *backgroundData = [NSMutableData dataWithCapacity:12];
    char colorType[] = "ClrB";
    [backgroundData appendBytes:colorType length:4];
    
    uint16_t redBig = swapInt16HostToBig(red);
    uint16_t greenBig = swapInt16HostToBig(green);
    uint16_t blueBig = swapInt16HostToBig(blue);
    uint16_t reserved = 0;
    
    [backgroundData appendBytes:&redBig length:2];
    [backgroundData appendBytes:&greenBig length:2];
    [backgroundData appendBytes:&blueBig length:2];
    [backgroundData appendBytes:&reserved length:2];
    
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"BKGD" type:@"blob" value:backgroundData] autorelease];
}

+ (DSStoreEntry *)backgroundImageEntryForFile:(NSString *)filename imagePath:(NSString *)imagePath {
    // Store BKGD entry with PctB type
    NSMutableData *backgroundData = [NSMutableData dataWithCapacity:12];
    char pictureType[] = "PctB";
    [backgroundData appendBytes:pictureType length:4];
    // Add placeholder data (8 bytes) - native .DS_Store has more complex data here
    uint64_t placeholder = 0;
    [backgroundData appendBytes:&placeholder length:8];
    
    DSStoreEntry *bkgdEntry = [[[DSStoreEntry alloc] initWithFilename:filename code:@"BKGD" type:@"blob" value:backgroundData] autorelease];
    
    // Note: The image path should also be stored in a "pict" entry
    // For simplicity, we store it as a ustr (UTF-16 string) type
    // For interoperability, native systems use Alias records (blob) which are more complex
    
    return bkgdEntry;
}

+ (DSStoreEntry *)viewStyleEntryForFile:(NSString *)filename style:(NSString *)style {
    // Validate style
    NSArray *validStyles = [NSArray arrayWithObjects:@"icnv", @"clmv", @"glyv", @"Nlsv", @"Flwv", nil];
    if (![validStyles containsObject:style]) {
        style = @"icnv"; // Default to icon view
    }
    
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"vstl" type:@"type" value:style] autorelease];
}

+ (DSStoreEntry *)iconSizeEntryForFile:(NSString *)filename size:(int)size {
    NSMutableData *iconData = [NSMutableData dataWithCapacity:18];
    char iconType[] = "icvo";
    [iconData appendBytes:iconType length:4];
    
    uint64_t flags = 0; // Unknown flags
    uint16_t sizeBig = swapInt16HostToBig(size);
    char arrangement[] = "none";
    
    [iconData appendBytes:&flags length:8];
    [iconData appendBytes:&sizeBig length:2];
    [iconData appendBytes:arrangement length:4];
    
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"icvo" type:@"blob" value:iconData] autorelease];
}

+ (DSStoreEntry *)commentsEntryForFile:(NSString *)filename comments:(NSString *)comments {
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"cmmt" type:@"ustr" value:comments] autorelease];
}

+ (DSStoreEntry *)logicalSizeEntryForFile:(NSString *)filename size:(long long)size {
    NSNumber *sizeNumber = [NSNumber numberWithLongLong:size];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"lg1S" type:@"long" value:sizeNumber] autorelease];
}

+ (DSStoreEntry *)physicalSizeEntryForFile:(NSString *)filename size:(long long)size {
    NSNumber *sizeNumber = [NSNumber numberWithLongLong:size];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"ph1S" type:@"long" value:sizeNumber] autorelease];
}

+ (DSStoreEntry *)modificationDateEntryForFile:(NSString *)filename date:(NSDate *)date {
    // Convert to 1904-based timestamp with 1/65536 second precision
    NSTimeInterval secondsSince1970 = [date timeIntervalSince1970];
    NSTimeInterval secondsSince1904 = secondsSince1970 + (66 * 365.25 * 24 * 3600); // Approximate
    uint64_t dutcValue = (uint64_t)(secondsSince1904 * 65536);
    NSNumber *timestampNumber = [NSNumber numberWithUnsignedLongLong:dutcValue];
    
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"modD" type:@"dutc" value:timestampNumber] autorelease];
}

+ (DSStoreEntry *)booleanEntryForFile:(NSString *)filename code:(NSString *)code value:(BOOL)value {
    NSNumber *boolNumber = [NSNumber numberWithBool:value];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:code type:@"bool" value:boolNumber] autorelease];
}

+ (DSStoreEntry *)longEntryForFile:(NSString *)filename code:(NSString *)code value:(int32_t)value {
    NSNumber *longNumber = [NSNumber numberWithInt:value];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:code type:@"long" value:longNumber] autorelease];
}

// Icon view options

+ (DSStoreEntry *)gridSpacingEntryForFile:(NSString *)filename spacing:(int)spacing {
    NSNumber *spacingNumber = [NSNumber numberWithInt:spacing];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"icsp" type:@"long" value:spacingNumber] autorelease];
}

+ (DSStoreEntry *)textSizeEntryForFile:(NSString *)filename size:(int)size {
    NSNumber *sizeNumber = [NSNumber numberWithInt:size];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"lsvt" type:@"long" value:sizeNumber] autorelease];
}

+ (DSStoreEntry *)labelPositionEntryForFile:(NSString *)filename position:(int)position {
    // Position is encoded in icvo blob - for simplicity use a long field
    NSNumber *posNumber = [NSNumber numberWithInt:position];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"lblp" type:@"long" value:posNumber] autorelease];
}

+ (DSStoreEntry *)showItemInfoEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"info" value:show];
}

+ (DSStoreEntry *)showIconPreviewEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"prvw" value:show];
}

+ (DSStoreEntry *)iconArrangementEntryForFile:(NSString *)filename arrangement:(int)arrangement {
    NSNumber *arrNumber = [NSNumber numberWithInt:arrangement];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"iarr" type:@"long" value:arrNumber] autorelease];
}

+ (DSStoreEntry *)sortByEntryForFile:(NSString *)filename sortBy:(NSString *)sortBy {
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"GRP0" type:@"ustr" value:sortBy] autorelease];
}

// Window chrome

+ (DSStoreEntry *)sidebarWidthEntryForFile:(NSString *)filename width:(int)width {
    NSNumber *widthNumber = [NSNumber numberWithInt:width];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"fwsw" type:@"long" value:widthNumber] autorelease];
}

+ (DSStoreEntry *)showToolbarEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"stbr" value:show];
}

+ (DSStoreEntry *)showSidebarEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"ssbr" value:show];
}

+ (DSStoreEntry *)showPathBarEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"pbar" value:show];
}

+ (DSStoreEntry *)showStatusBarEntryForFile:(NSString *)filename show:(BOOL)show {
    return [DSStoreEntry booleanEntryForFile:filename code:@"sbar" value:show];
}

// Label colors

+ (DSStoreEntry *)labelColorEntryForFile:(NSString *)filename color:(int)colorIndex {
    // Color index: 0=none, 1=red, 2=orange, 3=yellow, 4=green, 5=blue, 6=purple, 7=grey
    NSNumber *colorNumber = [NSNumber numberWithInt:colorIndex];
    return [[[DSStoreEntry alloc] initWithFilename:filename code:@"lclr" type:@"long" value:colorNumber] autorelease];
}

// Value extraction methods

- (NSPoint)iconLocation {
    if (![_code isEqualToString:@"Iloc"] || ![_type isEqualToString:@"blob"]) {
        return NSMakePoint(0, 0);
    }
    
    NSData *data = (NSData *)_value;
    if ([data length] < 8) return NSMakePoint(0, 0);
    
    uint32_t x, y;
    [data getBytes:&x range:NSMakeRange(0, 4)];
    [data getBytes:&y range:NSMakeRange(4, 4)];
    
    return NSMakePoint(swapInt32BigToHost(x), swapInt32BigToHost(y));
}

- (SimpleColor *)backgroundColor {
    if (![[self code] isEqualToString:@"BKGD"] || ![[self type] isEqualToString:@"blob"]) {
        return nil;
    }
    
    NSData *data = [self value];
    if ([data length] < 12) {
        return nil;
    }
    
    char type[5] = {0};
    [data getBytes:type range:NSMakeRange(0, 4)];
    
    if (strcmp(type, "ClrB") != 0) {
        return nil;
    }
    
    uint16_t red, green, blue;
    [data getBytes:&red range:NSMakeRange(4, 2)];
    [data getBytes:&green range:NSMakeRange(6, 2)];
    [data getBytes:&blue range:NSMakeRange(8, 2)];
    
    return [SimpleColor colorWithRed:swapInt16BigToHost(red)/65535.0
                               green:swapInt16BigToHost(green)/65535.0
                                blue:swapInt16BigToHost(blue)/65535.0
                               alpha:1.0];
}

- (NSString *)backgroundImagePath {
    if (![_code isEqualToString:@"BKGD"] || ![_type isEqualToString:@"blob"]) {
        return nil;
    }
    
    NSData *data = (NSData *)_value;
    if ([data length] < 4) return nil;
    
    char type[5] = {0};
    [data getBytes:type range:NSMakeRange(0, 4)];
    
    if (strcmp(type, "PctB") != 0) return nil;
    
    // TODO: Parse alias data to extract image path
    return @"<background image alias data>";
}

- (NSString *)viewStyle {
    if (![_code isEqualToString:@"vstl"] || ![_type isEqualToString:@"type"]) {
        return nil;
    }
    
    return (NSString *)_value;
}

- (int)iconSize {
    if (![_code isEqualToString:@"icvo"] || ![_type isEqualToString:@"blob"]) {
        return 0;
    }
    
    NSData *data = (NSData *)_value;
    if ([data length] < 14) return 0;
    
    char type[5] = {0};
    [data getBytes:type range:NSMakeRange(0, 4)];
    
    if (strcmp(type, "icvo") != 0) return 0;
    
    uint16_t size;
    [data getBytes:&size range:NSMakeRange(12, 2)];
    
    return swapInt16BigToHost(size);
}

- (NSString *)comments {
    if (![_code isEqualToString:@"cmmt"] || ![_type isEqualToString:@"ustr"]) {
        return nil;
    }
    
    return (NSString *)_value;
}

- (long long)logicalSize {
    if (![_code isEqualToString:@"lg1S"] && ![_code isEqualToString:@"logS"]) {
        return 0;
    }
    
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value longLongValue];
    }
    
    return 0;
}

- (long long)physicalSize {
    if (![_code isEqualToString:@"ph1S"] && ![_code isEqualToString:@"phyS"]) {
        return 0;
    }
    
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value longLongValue];
    }
    
    return 0;
}

- (NSDate *)modificationDate {
    if (![_code isEqualToString:@"modD"] && ![_code isEqualToString:@"moDD"]) {
        return nil;
    }
    
    if ([_type isEqualToString:@"dutc"]) {
        uint64_t dutcValue = [(NSNumber *)_value unsignedLongLongValue];
        NSTimeInterval secondsSince1904 = dutcValue / 65536.0;
        NSTimeInterval secondsSince1970 = secondsSince1904 - (66 * 365.25 * 24 * 3600);
        return [NSDate dateWithTimeIntervalSince1970:secondsSince1970];
    }
    
    return nil;
}

- (BOOL)booleanValue {
    if (![_type isEqualToString:@"bool"]) {
        return NO;
    }
    
    return [(NSNumber *)_value boolValue];
}

- (int32_t)longValue {
    if (![_type isEqualToString:@"long"] && ![_type isEqualToString:@"shor"]) {
        return 0;
    }
    
    return [(NSNumber *)_value intValue];
}

// Icon view options extraction

- (int)gridSpacing {
    if (![_code isEqualToString:@"icsp"]) {
        return 0;
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

- (int)textSize {
    if (![_code isEqualToString:@"lsvt"]) {
        return 0;
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

- (int)labelPosition {
    if (![_code isEqualToString:@"lblp"]) {
        return 0; // bottom
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

- (BOOL)showItemInfo {
    if (![_code isEqualToString:@"info"]) {
        return NO;
    }
    return [self booleanValue];
}

- (BOOL)showIconPreview {
    if (![_code isEqualToString:@"prvw"]) {
        return NO;
    }
    return [self booleanValue];
}

- (int)iconArrangement {
    if (![_code isEqualToString:@"iarr"]) {
        return 0;
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

- (NSString *)sortBy {
    if (![_code isEqualToString:@"GRP0"]) {
        return nil;
    }
    if ([_type isEqualToString:@"ustr"]) {
        return (NSString *)_value;
    }
    return nil;
}

// Window chrome extraction

- (int)sidebarWidth {
    if (![_code isEqualToString:@"fwsw"]) {
        return 0;
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

// Label color extraction

- (int)labelColor {
    if (![_code isEqualToString:@"lclr"]) {
        return 0;
    }
    if ([_type isEqualToString:@"long"]) {
        return [(NSNumber *)_value intValue];
    }
    return 0;
}

@end
