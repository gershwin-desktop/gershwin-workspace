/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/* Assertions E19 (assertions-p-links.md): the alias and Internet location
 * files we write have the structure the Mac OS X 10.6 Finder writes, judged
 * against the captured fixtures - types, resource ids, Finder Info, tags -
 * not against content that legitimately differs (dates, CNIDs, icon art). */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNAliasFile.h"
#import "FSNLocationFile.h"
#import "GSFileMetadata.h"
#include <unistd.h>

static NSString *fixtures;
static NSString *root;

static NSString *
fixture(NSString *name)
{
  return [fixtures stringByAppendingPathComponent: name];
}

static GSOType
code(NSString *s)
{
  return [GSFileMetadata osTypeFromString: s];
}

/* The "type/id" of every resource of a fork, sorted, read from the map
 * with the layout of Inside Macintosh so the writer is not judged by itself. */
static NSArray *
resourceKeys(NSData *fork)
{
  const uint8_t *b = [fork bytes];
  NSMutableArray *keys = [NSMutableArray array];
  uint32_t mapOff;
  uint32_t tl;
  unsigned n;
  unsigned i;

  if ([fork length] < 32)
    {
      return keys;
    }
  mapOff = (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7];
  tl = mapOff + ((b[mapOff + 24] << 8) | b[mapOff + 25]);
  n = ((b[tl] << 8) | b[tl + 1]) + 1;
  for (i = 0; i < n; i++)
    {
      const uint8_t *e = b + tl + 2 + 8 * i;
      unsigned count = ((e[4] << 8) | e[5]) + 1;
      unsigned off = (e[6] << 8) | e[7];
      unsigned j;

      for (j = 0; j < count; j++)
	{
	  const uint8_t *r = b + tl + off + 12 * j;

	  [keys addObject: [NSString stringWithFormat: @"%.4s/%d",
				     (const char *)e, (int)(int16_t)((r[0] << 8) | r[1])]];
	}
    }
  return [keys sortedArrayUsingSelector: @selector(compare:)];
}

/* The set of tags of an alias record. */
static NSArray *
recordTags(NSData *rec, NSString **posix)
{
  const uint8_t *b = [rec bytes];
  NSMutableArray *tags = [NSMutableArray array];
  NSUInteger p = 150;

  while (p + 4 <= [rec length])
    {
      int16_t t = (int16_t)((b[p] << 8) | b[p + 1]);
      unsigned l = (b[p + 2] << 8) | b[p + 3];

      if (t == -1)
	{
	  break;
	}
      [tags addObject: [NSNumber numberWithInt: t]];
      if (t == 18 && posix != NULL)
	{
	  *posix = [[[NSString alloc] initWithBytes: b + p + 4 length: l
					   encoding: NSUTF8StringEncoding]
		     autorelease];
	}
      p += 4 + l + (l & 1);
    }
  return tags;
}

static NSData *
alisRecord(NSString *path)
{
  return [GSFileMetadata dataForResourceType: code(@"alis") resourceID: 0
				      inFork: [[GSFileMetadata
					metadataForFileAtPath: path]
					resourceFork]];
}

static void
checkAlias(NSString *path, NSString *finderPath, NSString *type, NSString *label)
{
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  GSFileMetadata *ref = [GSFileMetadata metadataForFileAtPath: finderPath];
  NSArray *tags = recordTags(alisRecord(path), NULL);

  PASS(md != nil, "%s: metadata present", [label UTF8String]);
  PASS([md typeCode] == code(type), "%s: type %s", [label UTF8String],
       [type UTF8String]);
  PASS([md creatorCode] == code(@"MACS"), "%s: creator MACS",
       [label UTF8String]);
  PASS([md finderFlags] == 0x8400, "%s: fdFlags kIsAlias + kHasCustomIcon",
       [label UTF8String]);
  PASS([md finderFlags] == [ref finderFlags], "%s: fdFlags as Finder's",
       [label UTF8String]);
  PASS_EQUAL(resourceKeys([md resourceFork]), resourceKeys([ref resourceFork]),
	     "%s: resource types and ids as Finder's", [label UTF8String]);
  PASS([tags containsObject: [NSNumber numberWithInt: 18]]
       && [tags containsObject: [NSNumber numberWithInt: 19]]
       && [tags containsObject: [NSNumber numberWithInt: 14]]
       && [tags containsObject: [NSNumber numberWithInt: 15]],
       "%s: record carries tags 14 15 18 19", [label UTF8String]);
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir;

  fixtures = [[fm currentDirectoryPath] stringByAppendingPathComponent:
    @"../GWMetadata/interop/fixtures/finder106/E19-links/finder"];
  root = [NSString stringWithFormat: @"/tmp/t_FinderLinks.%d", getpid()];
  [fm removeItemAtPath: root error: NULL];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES
		 attributes: nil error: NULL];
  dir = [root stringByAppendingPathComponent: @"d"];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES
		 attributes: nil error: NULL];
  PASS([fm fileExistsAtPath: fixture(@"alias-file")], "Finder fixtures found");

  /* --- classic writer, file target --- */
  {
    NSString *p = [FSNAlias writeAliasFileForTargetPath:
		     @"/Users/user/Desktop/mi/al/a.txt"
					    inDirectory: root
					     volumeName: @"Macintosh HD"];
    NSString *posix = nil;
    NSData *icns;

    checkAlias(p, fixture(@"alias-file"), @"alis", @"classic file");
    recordTags(alisRecord(p), &posix);
    PASS_EQUAL(posix, @"Users/user/Desktop/mi/al/a.txt",
	       "tag 18 of the boot volume has no leading slash");
    PASS([[NSData dataWithContentsOfFile: p] length] == 0,
	 "classic alias keeps an empty data fork");
    icns = [GSFileMetadata dataForResourceType: code(@"icns")
				    resourceID: -16496
					inFork: [[GSFileMetadata
					   metadataForFileAtPath: p]
					   resourceFork]];
    PASS([icns length] > 8 && memcmp([icns bytes], "icns", 4) == 0
	 && ((const uint8_t *)[icns bytes])[7] == ([icns length] & 0xff),
	 "badge resource is an icns container");
    PASS([icns isEqual: [GSFileMetadata dataForResourceType: code(@"icns")
						 resourceID: -16496
						     inFork: [[GSFileMetadata
							metadataForFileAtPath:
							  fixture(@"alias-file")]
							resourceFork]]] == NO,
	 "badge is our artwork, not the bytes of Apple's");
    PASS([FSNAlias aliasWithContentsOfFile: p] != nil
	 && [FSNAlias isAliasFileAtPath: p], "the file is read back as alias");
  }

  /* --- classic writer, folder target --- */
  {
    NSString *p = [FSNAlias writeAliasFileForTargetPath: dir inDirectory: root
					     volumeName: @"Macintosh HD"];

    checkAlias(p, fixture(@"alias-folder"), @"fdrp", @"classic folder");
    PASS([[FSNAlias aliasWithContentsOfFile: p] isDirectory],
	 "the folder alias records a directory");
  }

  /* --- bookmark writer --- */
  {
    NSString *p = [FSNAlias writeAliasBookmarkForTargetPath:
		     @"/Users/user/Desktop/mi/al/b.txt" inDirectory: root
						 volumeName: @"Macintosh HD"];
    NSData *d = [NSData dataWithContentsOfFile: p];

    checkAlias(p, fixture(@"alias-file"), @"alis", @"bookmark");
    PASS([d length] > 8 && memcmp([d bytes], "book", 4) == 0,
	 "bookmark writer keeps its bookmark in the data fork");
  }

  /* --- reading and re-writing the record of an alias on another volume --- */
  {
    FSNAlias *a = [FSNAlias aliasWithContentsOfFile: fixture(@"alias-remote")];
    NSString *posix = nil;

    PASS_EQUAL([a posixPath], @"/Volumes/ALVOL/remote.txt",
	       "Finder's mount-relative path on another volume is joined");
    recordTags([a aliasData], &posix);
    PASS_EQUAL(posix, @"/remote.txt",
	       "tag 18 on another volume is relative to the mount point");
  }

  /* --- Internet location files --- */
  {
    struct { NSString *fix; NSString *ext; NSString *type; } cases[] = {
      { @"ex.webloc", @"webloc", @"ilht" },
      { @"ftp.ftploc", @"ftploc", @"ilft" },
      { @"mail.mailtoloc", @"mailtoloc", @"ilma" },
    };
    int i;

    for (i = 0; i < 3; i++)
      {
	GSFileMetadata *ref = [GSFileMetadata metadataForFileAtPath:
				  fixture(cases[i].fix)];
	NSData *refURL = [GSFileMetadata
			   dataForResourceType: code(@"TEXT") resourceID: 256
				       inFork: [ref resourceFork]];
	NSString *urlString = [[[NSString alloc] initWithData: refURL
					       encoding: NSUTF8StringEncoding]
				autorelease];
	NSString *p = [FSNLocationFile writeWeblocForURL:
			 [NSURL URLWithString: urlString]
						   title: @"t"
					     inDirectory: root];
	GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: p];
	NSString *l = cases[i].ext;

	PASS_EQUAL([p pathExtension], cases[i].ext, "%s: file extension",
		   [l UTF8String]);
	PASS([md typeCode] == code(cases[i].type), "%s: type %s",
	     [l UTF8String], [cases[i].type UTF8String]);
	PASS([md creatorCode] == code(@"MACS"), "%s: creator MACS",
	     [l UTF8String]);
	PASS([md finderFlags] == [ref finderFlags] && [md finderFlags] == 0x0010,
	     "%s: fdFlags kExtensionIsHidden", [l UTF8String]);
	PASS_EQUAL(resourceKeys([md resourceFork]),
		   resourceKeys([ref resourceFork]),
		   "%s: resource types and ids as Finder's", [l UTF8String]);
	PASS_EQUAL([GSFileMetadata dataForResourceType: code(@"TEXT")
					    resourceID: 256
					       inFork: [md resourceFork]], refURL,
		   "%s: TEXT 256 holds the URL", [l UTF8String]);
	PASS_EQUAL([GSFileMetadata dataForResourceType: code(@"url ")
					    resourceID: 256
					       inFork: [md resourceFork]], refURL,
		   "%s: url  256 holds the URL", [l UTF8String]);
	PASS_EQUAL([GSFileMetadata dataForResourceType: code(@"drag")
					    resourceID: 128
					       inFork: [md resourceFork]],
		   [GSFileMetadata dataForResourceType: code(@"drag")
					    resourceID: 128
					       inFork: [ref resourceFork]],
		   "%s: drag 128 as Finder's", [l UTF8String]);
	PASS_EQUAL([NSData dataWithContentsOfFile: p],
		   [NSData dataWithContentsOfFile: fixture(cases[i].fix)],
		   "%s: data fork is the same XML plist", [l UTF8String]);
	PASS_EQUAL([[FSNLocationFile URLForLocationFileAtPath: p] absoluteString],
		   urlString, "%s: read back", [l UTF8String]);
      }
  }

  /* --- E27: the name Finder gives a dragged URL: the URL without scheme
   * and "//", its "/" stored as ":" (shown as "/" by Finder) --- */
  {
    NSString *e27 = [[fm currentDirectoryPath] stringByAppendingPathComponent:
      @"../GWMetadata/interop/fixtures/finder106/E27-dragged-locations"];
    NSString *out = [root stringByAppendingPathComponent: @"e27"];
    NSArray *names = [NSArray arrayWithObjects: @"a@example.com.mailtoloc",
      @"ftp.example.org:.ftploc", @"example.com:x.webloc", nil];
    NSString *name;

    [fm createDirectoryAtPath: out withIntermediateDirectories: YES
		   attributes: nil error: NULL];
    for (name in names)
      {
	/* The fixtures store ":" as "%3A": a ":" in a checked-in path breaks
	 * every git checkout on Windows. */
	NSString *stored = [name stringByReplacingOccurrencesOfString: @":"
							    withString: @"%3A"];
	NSURL *u = [FSNLocationFile URLForLocationFileAtPath:
		      [e27 stringByAppendingPathComponent: stored]];
	NSString *p = [FSNLocationFile writeWeblocForURL: u title: nil
					     inDirectory: out];

	PASS(u != nil, "E27 %s: fixture URL read", [name UTF8String]);
	PASS_EQUAL([p lastPathComponent], name,
		   "E27: dragged %s gets Finder's name",
		   [[u absoluteString] UTF8String]);
      }
  }

  [fm removeItemAtPath: root error: NULL];
  [arp release];
  return 0;
}
