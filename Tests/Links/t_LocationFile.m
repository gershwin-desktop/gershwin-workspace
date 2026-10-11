/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import <AppKit/AppKit.h>
#import "FSNLocationFile.h"
#include <unistd.h>

static NSString *root;

/* Answers what NSPasteboard answers, without needing a pasteboard server. */
@interface FakePB : NSObject
{
  NSDictionary *items;
}
- (id)initWithItems:(NSDictionary *)i;
@end

@implementation FakePB
- (id)initWithItems:(NSDictionary *)i
{
  items = [i retain];
  return self;
}
- (NSArray *)types { return [items allKeys]; }
- (id)propertyListForType:(NSString *)t { return [items objectForKey: t]; }
- (NSString *)stringForType:(NSString *)t { return [items objectForKey: t]; }
@end

static FakePB *
pb(NSDictionary *items)
{
  return [[[FakePB alloc] initWithItems: items] autorelease];
}

static NSString *
put(NSString *name, NSString *text)
{
  NSString *p = [root stringByAppendingPathComponent: name];

  [[text dataUsingEncoding: NSUTF8StringEncoding] writeToFile: p atomically: YES];
  return p;
}

static NSString *
plist(NSString *url)
{
  return [NSString stringWithFormat:
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    @"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
    @"\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
    @"<plist version=\"1.0\"><dict><key>URL</key><string>%@</string>"
    @"</dict></plist>\n", url];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  Class L = [FSNLocationFile class];

  root = [NSString stringWithFormat: @"%@/links_loc_%ld",
		   NSTemporaryDirectory(), (long)getpid()];
  [fm removeItemAtPath: root error: NULL];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES
		 attributes: nil error: NULL];

  START_SET("reading")
    {
      PASS_EQUAL([[L URLForLocationFileAtPath:
		       put(@"a.webloc", plist(@"https://example.org/a?b=1"))]
		   absoluteString], @"https://example.org/a?b=1",
		 ".webloc plist");
      PASS_EQUAL([[L URLForLocationFileAtPath:
		       put(@"b.inetloc", plist(@"ftp://ftp.example.org/pub/"))]
		   absoluteString], @"ftp://ftp.example.org/pub/",
		 ".inetloc plist");
      PASS_EQUAL([[L URLForLocationFileAtPath:
		       put(@"c.fileloc", plist(@"file:///usr/share/doc"))]
		   absoluteString], @"file:///usr/share/doc", ".fileloc plist");
      PASS_EQUAL([[L URLForLocationFileAtPath:
		       put(@"D.WEBLOC", plist(@"https://example.org/"))]
		   absoluteString], @"https://example.org/", "extension case");
      PASS_EQUAL([[L URLForLocationFileAtPath:
		       put(@"e.url", @"[InternetShortcut]\r\nURL=https://example.org/e\r\n")]
		   absoluteString], @"https://example.org/e", ".url shortcut");
      PASS([L URLForLocationFileAtPath: put(@"f.webloc", plist(@"no-scheme"))] == nil,
	   "scheme-less string rejected");
      PASS([L URLForLocationFileAtPath: put(@"g.webloc", @"garbage")] == nil,
	   "garbage rejected");
      PASS([L URLForLocationFileAtPath: put(@"h.webloc", @"")] == nil,
	   "empty file without fork rejected");
      PASS([L URLForLocationFileAtPath: put(@"i.txt", plist(@"https://example.org/"))] == nil,
	   "other extension not a location file");
      PASS([L URLForLocationFileAtPath:
		[root stringByAppendingPathComponent: @"missing.webloc"]] == nil,
	   "missing file");
    }
  END_SET("reading")

  START_SET("classic 'url ' resource")
    {
      /* Empty data fork, URL in resource 'url ' of the sidecar fork. */
      NSString *p = put(@"k.webloc", @"");
      NSData *url = [@"https://example.org/classic" dataUsingEncoding:
				      NSUTF8StringEncoding];
      NSUInteger n = [url length];
      uint32_t mapOff = 256 + 4 + (uint32_t)n;
      enum { kMap = 28 + 2 + 8 + 12 };
      uint8_t hdr[16] = {0,0,1,0, 0,0,0,0, 0,0,0,0, 0,0,0,kMap};
      uint8_t map[kMap] = {0};
      NSMutableData *fork = [NSMutableData dataWithLength: 16];
      uint8_t *h;

      hdr[4] = mapOff >> 24; hdr[5] = mapOff >> 16; hdr[6] = mapOff >> 8;
      hdr[7] = mapOff;
      hdr[11] = (uint8_t)(4 + n);
      memcpy([fork mutableBytes], hdr, 16);
      memcpy(map, hdr, 16);
      map[25] = 28; map[27] = kMap;
      memcpy(map + 30, "url ", 4);
      map[37] = 10;
      map[38] = 0x01; map[39] = 0x00;       /* id 256 */
      map[40] = 0xff; map[41] = 0xff;
      [fork increaseLengthBy: 240];
      uint8_t len[4] = {0, 0, 0, (uint8_t)n};
      [fork appendBytes: len length: 4];
      [fork appendData: url];
      [fork appendBytes: map length: kMap];
      (void)h;

      /* AppleDouble wrapper with only a resource fork entry. */
      NSMutableData *ad = [NSMutableData data];
      uint8_t ah[26] = {0x00,0x05,0x16,0x07, 0x00,0x02,0x00,0x00};
      uint8_t d[12] = {0,0,0,2, 0,0,0,38, 0,0,0,0};
      NSUInteger fl = [fork length];

      ah[25] = 1;
      d[8] = fl >> 24; d[9] = fl >> 16; d[10] = fl >> 8; d[11] = fl;
      [ad appendBytes: ah length: 26];
      [ad appendBytes: d length: 12];
      [ad appendData: fork];
      [ad writeToFile: [root stringByAppendingPathComponent: @"._k.webloc"]
	   atomically: YES];
      PASS_EQUAL([[L URLForLocationFileAtPath: p] absoluteString],
		 @"https://example.org/classic", "'url ' resource id 256");
    }
  END_SET("classic 'url ' resource")

  START_SET("writing")
    {
      NSURL *u = [NSURL URLWithString: @"https://example.org/x/y?q=a b"];
      NSURL *ok = [NSURL URLWithString: @"https://example.org/x/y?q=a%20b"];
      NSString *p = [L writeWeblocForURL: ok title: @"My: page/1"
			     inDirectory: root];

      (void)u;
      PASS_EQUAL([p lastPathComponent], @"My- page-1.webloc",
		 "title becomes a safe file name");
      PASS_EQUAL([[L URLForLocationFileAtPath: p] absoluteString],
		 [ok absoluteString], "written file reads back");
      /* What a Finder reads: an XML plist whose URL key holds the string. */
      NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile: p];
      PASS_EQUAL([d objectForKey: @"URL"], [ok absoluteString],
		 "plain property list with URL key");
      NSString *p2 = [L writeWeblocForURL: ok title: @"My: page/1"
			      inDirectory: root];
      PASS_EQUAL([p2 lastPathComponent], @"My- page-1 2.webloc",
		 "name collision gets a number");
      PASS_EQUAL([[L writeWeblocForURL: ok title: nil inDirectory: root]
		   lastPathComponent], @"example.org:x:y?q=a%20b.webloc",
		 "the URL without scheme is the default title (E27)");
      PASS([L writeWeblocForURL: [NSURL URLWithString: @"nonsense"]
			  title: @"x" inDirectory: root] == nil,
	   "relative URL refused");
      PASS_EQUAL([[L writeWeblocForURL: ok title: @".." inDirectory: root]
		   lastPathComponent], @"Internet Location.webloc",
		 "dots-only title does not hide or escape the file");
    }
  END_SET("writing")

  START_SET("URL drops")
    {
      Class L = [FSNLocationFile class];
      NSString *u = @"https://example.org/a";
      NSString *p;

      PASS_EQUAL([[L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	[NSArray arrayWithObjects: u, @"", nil] forKey: NSURLPboardType])]
		   absoluteString], u, "URL pasteboard type, list form");
      PASS_EQUAL([[L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	u forKey: NSURLPboardType])] absoluteString], u,
		 "URL pasteboard type, string form");
      PASS_EQUAL([[L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	u forKey: NSStringPboardType])] absoluteString], u,
		 "absolute URL in a string");
      PASS([L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	@"just some text" forKey: NSStringPboardType])] == nil,
	   "plain text is not a link");
      PASS([L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	@"see https://example.org/a now" forKey: NSStringPboardType])] == nil,
	   "text containing a URL is not a link");
      PASS([L URLForPasteboard: pb([NSDictionary dictionaryWithObject:
	@"not/absolute" forKey: NSStringPboardType])] == nil,
	   "relative string refused");
      PASS([L URLForPasteboard: pb([NSDictionary dictionaryWithObjectsAndKeys:
	u, NSURLPboardType, [NSArray arrayWithObject: @"/tmp/x"],
	NSFilenamesPboardType, nil])] == nil,
	   "a file drop is never a URL drop");

      p = [L writeWeblocFromPasteboard: pb([NSDictionary
	dictionaryWithObject: u forKey: NSURLPboardType]) inDirectory: root];
      PASS_EQUAL([p lastPathComponent], @"example.org:a.webloc",
		 "dropped URL becomes a webloc named as Finder names it");
      PASS_EQUAL([[L URLForLocationFileAtPath: p] absoluteString], u,
		 "and opens to the same URL");
      PASS([L writeWeblocFromPasteboard: pb([NSDictionary
	dictionaryWithObject: @"nope" forKey: NSStringPboardType])
			    inDirectory: root] == nil,
	   "nothing written for a non-URL: the drop is refused");
    }
  END_SET("URL drops")

  [fm removeItemAtPath: root error: NULL];
  [arp release];
  return 0;
}
