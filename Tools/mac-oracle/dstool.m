/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "DSStore.h"
#import "DSStoreEntry.h"

/* Oracle-side helper: turns a .DS_Store into stable, diffable text (so two
 * dumps can be compared with diff) and writes plist records the way our own
 * DSStore code does, so the Mac can be asked how it reads them. It links the
 * repo's DSStore library on purpose: the dump must show what our decoder sees. */

static void emit(NSString *s)
{
  fputs([s UTF8String], stdout);
  fputc('\n', stdout);
}

static NSString *render(id v, NSString *indent);

static NSString *hexOf(NSData *d)
{
  NSMutableString *h = [NSMutableString string];
  const unsigned char *b = [d bytes];
  for (NSUInteger i = 0; i < [d length]; i++) {
    [h appendFormat:@"%02x", b[i]];
  }
  return h;
}

static NSString *renderDict(NSDictionary *d, NSString *indent)
{
  NSMutableString *out = [NSMutableString string];
  for (NSString *k in [[d allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
    id v = [d objectForKey:k];
    if ([v isKindOfClass:[NSDictionary class]] || [v isKindOfClass:[NSArray class]]) {
      [out appendFormat:@"\n%@%@ =%@", indent, k,
       render(v, [indent stringByAppendingString:@"  "])];
    } else {
      [out appendFormat:@"\n%@%@ = %@", indent, k, render(v, indent)];
    }
  }
  return out;
}

static NSString *render(id v, NSString *indent)
{
  if ([v isKindOfClass:[NSDictionary class]]) {
    return renderDict(v, indent);
  }
  if ([v isKindOfClass:[NSArray class]]) {
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0;
    for (id e in v) {
      [out appendFormat:@"\n%@[%lu] = %@", indent, (unsigned long)i++,
       render(e, [indent stringByAppendingString:@"  "])];
    }
    return out;
  }
  if ([v isKindOfClass:[NSData class]]) {
    return [@"data:" stringByAppendingString:hexOf(v)];
  }
  if ([v isKindOfClass:[NSNumber class]]) {
    /* Booleans and integers must not print differently between hosts. */
    const char *t = [v objCType];
    if (strcmp(t, "c") == 0 || strcmp(t, "B") == 0) {
      return [v boolValue] ? @"true" : @"false";
    }
    if (strcmp(t, "d") == 0 || strcmp(t, "f") == 0) {
      NSString *g = [NSString stringWithFormat:@"%g", [v doubleValue]];
      /* Keep reals visibly distinct from integers: Finder is picky about the type. */
      return ([g rangeOfString:@"."].location == NSNotFound
              && [g rangeOfString:@"e"].location == NSNotFound)
             ? [g stringByAppendingString:@".0"] : g;
    }
    return [NSString stringWithFormat:@"%lld", [v longLongValue]];
  }
  return [v description];
}

static NSString *renderEntry(DSStoreEntry *e)
{
  id v = [e value];
  if ([v isKindOfClass:[NSData class]]) {
    NSData *d = v;
    if ([[e code] isEqualToString:@"Iloc"] && [d length] >= 8) {
      const unsigned char *b = [d bytes];
      unsigned x = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
      unsigned y = (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7];
      return [NSString stringWithFormat:@"x=%u y=%u rest=%@", x, y,
              hexOf([d subdataWithRange:NSMakeRange(8, [d length] - 8)])];
    }
    if ([d length] > 8 && memcmp([d bytes], "bplist00", 8) == 0) {
      id pl = [NSPropertyListSerialization propertyListWithData:d
                                                        options:0
                                                         format:NULL
                                                          error:NULL];
      if (pl) {
        return render(pl, @"    ");
      }
    }
  }
  return render(v, @"    ");
}

static int cmdDump(NSString *path, NSString *only)
{
  DSStore *store = [DSStore storeWithPath:path];
  if (![store load]) {
    fprintf(stderr, "dstool: cannot load %s\n", [path UTF8String]);
    return 1;
  }
  NSArray *names = [[store allFilenames] sortedArrayUsingSelector:@selector(compare:)];
  for (NSString *n in names) {
    if (only != nil && ![n isEqualToString:only]) {
      continue;
    }
    NSArray *codes = [[store allCodesForFilename:n] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *c in codes) {
      DSStoreEntry *e = [store entryForFilename:n code:c];
      NSString *r = renderEntry(e);
      emit([NSString stringWithFormat:@"%@ %@ %@:%@%@", n, c, [e type],
            [r hasPrefix:@"\n"] ? @"" : @" ", r]);
    }
  }
  return 0;
}

/* put <ds> <record> <code> key=value ...  creates or extends a store with a
 * binary-plist record (vstl: value=<icnv|clmv|Nlsv|Flwv>). Values: plain integers become integers, numbers with a
 * decimal point reals, true/false booleans, anything else strings. */
static int cmdPut(NSArray *a)
{
  NSString *path = [a objectAtIndex:0];
  NSString *rec = [a objectAtIndex:1];
  NSString *code = [a objectAtIndex:2];
  DSStore *store = [DSStore storeWithPath:path];
  if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
    if (![store load]) {
      fprintf(stderr, "dstool: cannot load %s\n", [path UTF8String]);
      return 1;
    }
  } else {
    store = [DSStore createStoreAtPath:path withEntries:nil];
  }
  NSMutableDictionary *d = [NSMutableDictionary dictionary];
  for (NSUInteger i = 3; i < [a count]; i++) {
    NSString *kv = [a objectAtIndex:i];
    NSRange r = [kv rangeOfString:@"="];
    if (r.location == NSNotFound) {
      fprintf(stderr, "dstool: bad pair %s\n", [kv UTF8String]);
      return 1;
    }
    NSString *k = [kv substringToIndex:r.location];
    NSString *v = [kv substringFromIndex:r.location + 1];
    id val = v;
    if ([v isEqualToString:@"true"] || [v isEqualToString:@"false"]) {
      val = [NSNumber numberWithBool:[v isEqualToString:@"true"]];
    } else if ([[v stringByTrimmingCharactersInSet:
                [NSCharacterSet characterSetWithCharactersInString:@"0123456789."]] length] == 0
               && [v length] > 0 && [v rangeOfString:@"."].location != NSNotFound) {
      /* Finder writes sizes and colours as reals; ints and reals differ in the plist. */
      val = [NSNumber numberWithDouble:[v doubleValue]];
    } else if ([[v stringByTrimmingCharactersInSet:
                 [NSCharacterSet decimalDigitCharacterSet]] length] == 0 && [v length] > 0) {
      val = [NSNumber numberWithLongLong:[v longLongValue]];
    }
    [d setObject:val forKey:k];
  }
  DSStoreEntry *e;
  if ([code isEqualToString:@"vstl"]) {
    /* The only per-folder view style record: a four character code, no plist. */
    e = [DSStoreEntry viewStyleEntryForFile:rec style:[d objectForKey:@"value"]];
  } else {
    e = [DSStoreEntry plistEntryForFile:rec code:code dictionary:d];
  }
  if (e == nil) {
    fprintf(stderr, "dstool: cannot build record\n");
    return 1;
  }
  [store setEntry:e];
  if (![store save]) {
    fprintf(stderr, "dstool: cannot save %s\n", [path UTF8String]);
    return 1;
  }
  return 0;
}

/* copyrec <src> <srcrec> <dst> <dstrec>: Finder keeps a folder's window and view
 * records in its PARENT's .DS_Store, named after the folder, so a case built
 * locally has to be renamed into the record of whatever name it gets on the Mac. */
static int cmdCopyRec(NSArray *a)
{
  DSStore *src = [DSStore storeWithPath:[a objectAtIndex:0]];
  if (![src load]) {
    fprintf(stderr, "dstool: cannot load %s\n", [[a objectAtIndex:0] UTF8String]);
    return 1;
  }
  NSString *dstPath = [a objectAtIndex:2];
  NSString *dstRec = [a objectAtIndex:3];
  DSStore *dst;
  if ([[NSFileManager defaultManager] fileExistsAtPath:dstPath]) {
    dst = [DSStore storeWithPath:dstPath];
    if (![dst load]) {
      fprintf(stderr, "dstool: cannot load %s\n", [dstPath UTF8String]);
      return 1;
    }
  } else {
    dst = [DSStore createStoreAtPath:dstPath withEntries:nil];
  }
  [dst removeAllEntriesForFilename:dstRec];
  for (NSString *c in [src allCodesForFilename:[a objectAtIndex:1]]) {
    DSStoreEntry *e = [src entryForFilename:[a objectAtIndex:1] code:c];
    [dst setEntry:[[[DSStoreEntry alloc] initWithFilename:dstRec code:c
                                                     type:[e type]
                                                    value:[e value]] autorelease]];
  }
  if (![dst save]) {
    fprintf(stderr, "dstool: cannot save %s\n", [dstPath UTF8String]);
    return 1;
  }
  return 0;
}

static DSStore *openOrCreate(NSString *path)
{
  if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return [DSStore createStoreAtPath:path withEntries:nil];
  }
  DSStore *store = [DSStore storeWithPath:path];
  if (![store load]) {
    fprintf(stderr, "dstool: cannot load %s\n", [path UTF8String]);
    return nil;
  }
  return store;
}

static int saveWith(DSStore *store, DSStoreEntry *e, NSString *path)
{
  if (e == nil) {
    fprintf(stderr, "dstool: cannot build record\n");
    return 1;
  }
  [store setEntry:e];
  if (![store save]) {
    fprintf(stderr, "dstool: cannot save %s\n", [path UTF8String]);
    return 1;
  }
  return 0;
}

/* putplist <ds> <record> <code> <plistfile>: records with nested values (lsvp
 * columns) cannot be spelled as key=value pairs, so they come from a plist file
 * in any format and are stored as the binary plist Finder writes. */
static int cmdPutPlist(NSArray *a)
{
  NSString *path = [a objectAtIndex:0];
  NSData *src = [NSData dataWithContentsOfFile:[a objectAtIndex:3]];
  id pl = src ? [NSPropertyListSerialization propertyListWithData:src options:0
                                                           format:NULL error:NULL] : nil;
  if (![pl isKindOfClass:[NSDictionary class]]) {
    fprintf(stderr, "dstool: %s is not a plist dictionary\n", [[a objectAtIndex:3] UTF8String]);
    return 1;
  }
  DSStore *store = openOrCreate(path);
  if (store == nil) {
    return 1;
  }
  return saveWith(store, [DSStoreEntry plistEntryForFile:[a objectAtIndex:1]
                                                    code:[a objectAtIndex:2]
                                              dictionary:pl], path);
}

/* putraw <ds> <record> <code> <type> <value>: the legacy records (lsvo, BKGD,
 * pict, ...) are raw blobs and scalars; blob values are hex or @file. */
static int cmdPutRaw(NSArray *a)
{
  NSString *path = [a objectAtIndex:0];
  NSString *type = [a objectAtIndex:3];
  NSString *v = [a objectAtIndex:4];
  id val = v;
  if ([type isEqualToString:@"blob"]) {
    if ([v hasPrefix:@"@"]) {
      val = [NSData dataWithContentsOfFile:[v substringFromIndex:1]];
    } else {
      NSMutableData *d = [NSMutableData data];
      const char *h = [v UTF8String];
      size_t n = strlen(h);
      if (n % 2) {
        fprintf(stderr, "dstool: odd hex length\n");
        return 1;
      }
      for (size_t i = 0; i < n; i += 2) {
        unsigned b;
        if (sscanf(h + i, "%2x", &b) != 1) {
          fprintf(stderr, "dstool: bad hex\n");
          return 1;
        }
        unsigned char c = b;
        [d appendBytes:&c length:1];
      }
      val = d;
    }
    if (val == nil) {
      fprintf(stderr, "dstool: cannot read %s\n", [v UTF8String]);
      return 1;
    }
  } else if ([type isEqualToString:@"bool"] || [type isEqualToString:@"long"]
             || [type isEqualToString:@"shor"]) {
    val = [NSNumber numberWithLongLong:[v longLongValue]];
  } else if (![type isEqualToString:@"ustr"] && ![type isEqualToString:@"type"]) {
    fprintf(stderr, "dstool: unsupported type %s\n", [type UTF8String]);
    return 1;
  }
  DSStore *store = openOrCreate(path);
  if (store == nil) {
    return 1;
  }
  return saveWith(store, [[[DSStoreEntry alloc] initWithFilename:[a objectAtIndex:1]
                                                            code:[a objectAtIndex:2]
                                                            type:type
                                                           value:val] autorelease], path);
}

/* rm <ds> <record> [code]: lets one experiment drop the plist record and keep
 * the legacy one (or the other way round) to see which Finder reads. */
static int cmdRm(NSArray *a)
{
  NSString *path = [a objectAtIndex:0];
  DSStore *store = [DSStore storeWithPath:path];
  if (![store load]) {
    fprintf(stderr, "dstool: cannot load %s\n", [path UTF8String]);
    return 1;
  }
  if ([a count] > 2) {
    [store removeEntryForFilename:[a objectAtIndex:1] code:[a objectAtIndex:2]];
  } else {
    [store removeAllEntriesForFilename:[a objectAtIndex:1]];
  }
  if (![store save]) {
    fprintf(stderr, "dstool: cannot save %s\n", [path UTF8String]);
    return 1;
  }
  return 0;
}

int main(int argc, char **argv)
{
  int rc = 2;
  @autoreleasepool {
    NSMutableArray *a = [NSMutableArray array];
    for (int i = 2; i < argc; i++) {
      [a addObject:[NSString stringWithUTF8String:argv[i]]];
    }
    if (argc >= 3 && strcmp(argv[1], "dump") == 0) {
      rc = cmdDump([a objectAtIndex:0], [a count] > 1 ? [a objectAtIndex:1] : nil);
    } else if (argc >= 6 && strcmp(argv[1], "put") == 0) {
      rc = cmdPut(a);
    } else if (argc == 6 && strcmp(argv[1], "copyrec") == 0) {
      rc = cmdCopyRec(a);
    } else if (argc == 6 && strcmp(argv[1], "putplist") == 0) {
      rc = cmdPutPlist(a);
    } else if (argc == 7 && strcmp(argv[1], "putraw") == 0) {
      rc = cmdPutRaw(a);
    } else if ((argc == 4 || argc == 5) && strcmp(argv[1], "rm") == 0) {
      rc = cmdRm(a);
    } else {
      fprintf(stderr, "usage: dstool copyrec <src> <srcrec> <dst> <dstrec>\n"
                      "       dstool dump <.DS_Store> [record]\n"
                      "       dstool put <.DS_Store> <record> <code> key=value...\n"
                      "       dstool putplist <.DS_Store> <record> <code> <plistfile>\n"
                      "       dstool putraw <.DS_Store> <record> <code> <type> <hex|@file|value>\n"
                      "       dstool rm <.DS_Store> <record> [code]\n");
    }
  }
  return rc;
}
