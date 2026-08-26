/* gen_bookmark_for_mac.m - emit OS X 10.6-style macOS bookmark data
 * (the "book....mark...." blob found in the data fork of 10.6 Finder
 * aliases) for interop experiments.
 *
 * The purpose is to determine, by varying identity classes one at a time,
 * the minimum field set the 10.6 resolver (CFURLCreateByResolvingBookmarkData)
 * accepts for a path/URL-only, GNUstep-generable alias.
 *
 * Usage variants (identity classes toggled by args):
 *   <targetPath> <volumeName> <volumeUUID> <outDir> [targetCNID]
 *     volumeUUID=""        -> omit 0x2011 Volume UUID
 *     targetCNID absent    -> omit 0x1030 Target CNID + 0x1005 CNID path
 *     targetCNID present   -> include 0x1030 (value, even if 0) + 0x1005 [cnid]
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>

static void putU32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { (uint8_t)(v & 0xff), (uint8_t)((v >> 8) & 0xff),
		   (uint8_t)((v >> 16) & 0xff), (uint8_t)((v >> 24) & 0xff) };
  [d appendBytes: b length: 4];
}
static void putU64(NSMutableData *d, uint64_t v)
{
  uint8_t b[8];
  for (int i = 0; i < 8; i++) b[i] = (uint8_t)((v >> (8 * i)) & 0xff);
  [d appendBytes: b length: 8];
}
static void putDouble(NSMutableData *d, double v)
{
  uint64_t bits;
  memcpy(&bits, &v, 8);
  putU64(d, bits);
}

static uint32_t
addRecord(NSMutableData *records, uint32_t base, uint32_t type, NSData *payload)
{
  uint32_t off = base + (uint32_t)[records length];
  putU32(records, (uint32_t)[payload length]);
  putU32(records, type);
  [records appendData: payload];
  NSUInteger pad = (4 - ([payload length] % 4)) % 4;
  if (pad) { uint8_t z = 0; [records appendBytes: &z length: pad]; }
  return off;
}
static uint32_t addString(NSMutableData *r, uint32_t base, uint32_t type, NSString *s)
{ return addRecord(r, base, type, [s dataUsingEncoding: NSUTF8StringEncoding]); }
static uint32_t addU32val(NSMutableData *r, uint32_t base, uint32_t type, uint32_t v)
{ NSMutableData *p = [NSMutableData data]; putU32(p, v); return addRecord(r, base, type, p); }
static uint32_t addDoubleVal(NSMutableData *r, uint32_t base, uint32_t type, double v)
{ NSMutableData *p = [NSMutableData data]; putDouble(p, v); return addRecord(r, base, type, p); }
static uint32_t addEmpty(NSMutableData *r, uint32_t base, uint32_t type)
{ return addRecord(r, base, type, [NSData data]); }

int main(int argc, char **argv)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  if (argc < 5)
    {
      fprintf(stderr, "usage: %s <targetPath> <volumeName> <volumeUUID> <outDir> [targetCNID]\n",
	      argv[0]);
      return 2;
    }
  NSString *target = [NSString stringWithUTF8String: argv[1]];
  NSString *volume = [NSString stringWithUTF8String: argv[2]];
  NSString *volUUID = [NSString stringWithUTF8String: argv[3]];
  NSString *outDir  = [NSString stringWithUTF8String: argv[4]];
  BOOL hasVolUUID = ([volUUID length] > 0);
  BOOL hasCNID = (argc > 5);
  uint32_t cnidVal = hasCNID ? (uint32_t)strtoul(argv[5], NULL, 0) : 0;

  enum {
    K_TARGET_URL=0x1003, K_TARGET_PATH=0x1004, K_TARGET_FILENAME=0x1020,
    K_TARGET_FLAGS=0x1010, K_TARGET_CREATION=0x1040, K_TARGET_CNIDPATH=0x1005,
    K_TARGET_CNID=0x1030,
    K_VOL_NAME=0x2010, K_VOL_PATH=0x2002, K_VOL_URL=0x2005, K_VOL_UUID=0x2011,
    K_VOL_CREATION=0x2013, K_VOL_MOUNTPOINT=0x2050, K_DISPLAY_NAME=0xf017,
    K_FOLDER_INDEX=0xc001, K_FILE_REF_FLAG=0xd001, K_BOOKMARK_CTIME=0xf030
  };
  enum {
    T_UTF8=0x0101, T_URL=0x0901, T_ARRAY=0x0601, T_RAW=0x0201,
    T_I32=0x0303, T_FALSE=0x0500, T_DOUBLE=0x0306, T_DATE=0x0400
  };

  NSArray *pathComps = [target pathComponents];
  NSMutableArray *comps = [NSMutableArray array];
  for (NSString *c in pathComps)
    if ([c length] && [c isEqualToString: @"/"] == NO) [comps addObject: c];

  /* entry count: 14 base + volume UUID + (CNID + CNID-path) */
  int nEntries = 14 + (hasVolUUID ? 1 : 0) + (hasCNID ? 2 : 0);
  uint32_t tocSize = 20 + (uint32_t)nEntries * 12;
  uint32_t base = 4 + tocSize;

  NSMutableData *records = [NSMutableData data];

  NSMutableArray *compOffs = [NSMutableArray array];
  for (NSString *c in comps)
    [compOffs addObject: @(addString(records, base, T_UTF8, c))];
  NSMutableData *arr;
  arr = [NSMutableData data];
  putU32(arr, (uint32_t)[compOffs count]);
  for (NSNumber *n in compOffs) putU32(arr, [n unsignedIntValue]);
  uint32_t pathArrOff = addRecord(records, base, T_ARRAY, arr);

  uint32_t cnidPathOff = 0;
  if (hasCNID)
    {
      NSMutableData *cp = [NSMutableData data];
      putU32(cp, 1); putU32(cp, cnidVal);
      cnidPathOff = addRecord(records, base, T_ARRAY, cp);
    }

  NSString *url = [@"file://" stringByAppendingString: target];
  uint32_t urlOff = addString(records, base, T_URL, url);
  uint32_t fnOff  = addString(records, base, T_UTF8, [target lastPathComponent]);
  uint32_t dispOff= addString(records, base, T_UTF8, [target lastPathComponent]);
  uint32_t volOff = addString(records, base, T_UTF8, volume);
  uint32_t volPathOff = addString(records, base, T_UTF8, @"/");
  uint32_t mntOff = addString(records, base, T_UTF8, @"/");
  uint32_t volUrlOff = addString(records, base, T_URL, @"file:///");
  uint32_t volUuidOff = hasVolUUID ? addString(records, base, T_UTF8, volUUID) : 0;

  NSMutableData *flags = [NSMutableData data];
  putU64(flags, 1); putU64(flags, 0); putU64(flags, 0);
  uint32_t flagsOff = addRecord(records, base, T_RAW, flags);

  double t0 = 0.0;
  uint32_t bctimeOff = addDoubleVal(records, base, T_DOUBLE, t0);
  uint32_t tctimeOff = addDoubleVal(records, base, T_DATE, t0);
  uint32_t vctimeOff = addDoubleVal(records, base, T_DATE, t0);
  uint32_t folderIdxOff = addU32val(records, base, T_I32,
				    (uint32_t)([comps count] > 1 ? [comps count] - 2 : 0));
  uint32_t frefOff = addEmpty(records, base, T_FALSE);
  uint32_t cnidOff = hasCNID ? addU32val(records, base, T_I32, cnidVal) : 0;

  struct { uint32_t key; uint32_t off; } raw[24];
  int n = 0;
#define ADD(k,o) do { raw[n].key=(k); raw[n].off=(o); n++; } while (0)
  ADD(K_TARGET_URL, urlOff);
  ADD(K_TARGET_PATH, pathArrOff);
  ADD(K_TARGET_FILENAME, fnOff);
  ADD(K_TARGET_FLAGS, flagsOff);
  ADD(K_TARGET_CREATION, tctimeOff);
  if (hasCNID) ADD(K_TARGET_CNIDPATH, cnidPathOff);
  ADD(K_VOL_NAME, volOff);
  ADD(K_VOL_PATH, volPathOff);
  ADD(K_VOL_URL, volUrlOff);
  if (hasVolUUID) ADD(K_VOL_UUID, volUuidOff);
  ADD(K_VOL_CREATION, vctimeOff);
  ADD(K_VOL_MOUNTPOINT, mntOff);
  ADD(K_DISPLAY_NAME, dispOff);
  ADD(K_FOLDER_INDEX, folderIdxOff);
  ADD(K_FILE_REF_FLAG, frefOff);
  ADD(K_BOOKMARK_CTIME, bctimeOff);
  if (hasCNID) ADD(K_TARGET_CNID, cnidOff);
#undef ADD
  for (int i = 1; i < n; i++)
    for (int j = i; j > 0 && raw[j].key < raw[j - 1].key; j--)
      { uint32_t k = raw[j].key, o = raw[j].off;
	raw[j].key = raw[j - 1].key; raw[j].off = raw[j - 1].off;
	raw[j - 1].key = k; raw[j - 1].off = o; }

  NSMutableData *toc = [NSMutableData data];
  putU32(toc, tocSize - 8);
  putU32(toc, 0xFFFFFFFE);
  putU32(toc, 1);
  putU32(toc, 0);
  putU32(toc, (uint32_t)n);
  for (int i = 0; i < n; i++) { putU32(toc, raw[i].key); putU32(toc, raw[i].off); putU32(toc, 0); }

  NSMutableData *rest = [NSMutableData data];
  putU32(rest, 4);
  [rest appendData: toc];
  [rest appendData: records];

  uint32_t total = 48 + (uint32_t)[rest length];
  NSMutableData *bm = [NSMutableData dataWithLength: 48];
  uint8_t *h = [bm mutableBytes];
  memcpy(h, "book", 4);
  h[4] = total & 0xff; h[5] = (total >> 8) & 0xff;
  h[6] = (total >> 16) & 0xff; h[7] = (total >> 24) & 0xff;
  h[8] = 0x00; h[9] = 0x00; h[10] = 0x04; h[11] = 0x10;
  h[12] = 0x30; h[13] = 0x00; h[14] = 0x00; h[15] = 0x00;
  [bm appendData: rest];

  [[NSFileManager defaultManager] createDirectoryAtPath: outDir
				withIntermediateDirectories: YES attributes: nil error: NULL];
  [bm writeToFile: [outDir stringByAppendingPathComponent: @"bookmark.dat"] atomically: NO];

  printf("bytes=%u entries=%d hasVolUUID=%d hasCNID=%d cnid=%u\n",
	 total, n, hasVolUUID, hasCNID, cnidVal);
  [arp release];
  return 0;
}
