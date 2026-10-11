/* t_CommentRecord.m - ObjectTesting coverage for the cmmt record that
 * Finder 10.6 needs in the destination folder's .DS_Store before it shows
 * the comment of a copied, duplicated or moved item (referee finding M2).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWMetadataCopier.h"
#import "GSFileMetadata.h"
#import "DSStore.h"

#include <unistd.h>

@interface CrossFSCopier : GWMetadataCopier
@end
@implementation CrossFSCopier
- (BOOL)isRenameFromPath:(NSString *)s toPath:(NSString *)d { return NO; }
@end

static NSFileManager *fm;
static NSString *root;

static NSString *
folder(NSString *name)
{
  NSString *p = [root stringByAppendingPathComponent: name];
  [fm createDirectoryAtPath: p attributes: nil];
  return p;
}

static NSString *
commented(NSString *dir, NSString *name, NSString *comment)
{
  NSString *p = [dir stringByAppendingPathComponent: name];
  GSFileMetadata *md;

  [fm createFileAtPath: p contents: [@"x" dataUsingEncoding: NSUTF8StringEncoding]
            attributes: nil];
  if (comment == nil)
    return p;
  md = [[[GSFileMetadata alloc] init] autorelease];
  md.finderComment = comment;
  [md writeToFileAtPath: p error: NULL];
  return p;
}

static NSString *
cmmt(NSString *dir, NSString *name)
{
  DSStore *s = [DSStore storeWithPath:
    [dir stringByAppendingPathComponent: @".DS_Store"]];
  return [s load] ? [s commentsForFilename: name] : nil;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_cmmtrec_%d", (int)getpid()]] retain];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];

  GWMetadataCopier *copier = [[GWMetadataCopier new] autorelease];
  NSError *err = nil;
  NSString *text = @"Zurück zum Kunden";

  {
    /* MI-PRS-24 */
    NSString *a = folder(@"a"), *b = folder(@"b");
    NSString *src = commented(a, @"doc.txt", text);
    err = nil;
    PASS([copier copyItemAtPath: src
                         toPath: [b stringByAppendingPathComponent: @"doc.txt"]
                        handler: nil metadataError: &err] && err == nil,
         "MI-PRS-24 copy into another folder succeeds");
    PASS_EQUAL(cmmt(b, @"doc.txt"), text,
         "MI-PRS-24 the destination folder's .DS_Store gets the cmmt record");
  }

  {
    /* MI-PRS-25: duplicate next to the original, foreign records kept. */
    NSString *c = folder(@"c");
    NSString *src = commented(c, @"doc.txt", text);
    DSStore *s = [DSStore createStoreAtPath:
      [c stringByAppendingPathComponent: @".DS_Store"] withEntries: nil];
    [s setIconLocationForFilename: @"doc.txt" x: 40 y: 50];
    [s setCommentsForFilename: @"other.txt" comments: @"theirs"];
    [s save];
    err = nil;
    [copier copyItemAtPath: src
                    toPath: [c stringByAppendingPathComponent: @"doc_copy.txt"]
                   handler: nil metadataError: &err];
    PASS_EQUAL(cmmt(c, @"doc_copy.txt"), text,
         "MI-PRS-25 a duplicate gets its own cmmt record");
    PASS_EQUAL(cmmt(c, @"other.txt"), @"theirs",
         "MI-PRS-25 records of other items stay");
    s = [DSStore storeWithPath: [c stringByAppendingPathComponent: @".DS_Store"]];
    [s load];
    PASS([s iconLocationForFilename: @"doc.txt"].x == 40,
         "MI-PRS-25 positions in the store stay");
  }

  {
    /* MI-PRS-26 / 27 */
    NSString *d = folder(@"d"), *e = folder(@"e");
    NSString *src = commented(d, @"m.txt", text);
    PASS([copier moveItemAtPath: src
                         toPath: [e stringByAppendingPathComponent: @"m.txt"]
                        handler: nil metadataError: &err],
         "MI-PRS-26 rename into another folder succeeds");
    PASS_EQUAL(cmmt(e, @"m.txt"), text,
         "MI-PRS-26 a move into another folder writes the cmmt record there");

    CrossFSCopier *x = [[CrossFSCopier new] autorelease];
    NSString *src2 = commented(d, @"n.txt", text);
    PASS([x moveItemAtPath: src2
                    toPath: [e stringByAppendingPathComponent: @"n.txt"]
                   handler: nil metadataError: &err],
         "MI-PRS-27 move across filesystems succeeds");
    PASS_EQUAL(cmmt(e, @"n.txt"), text,
         "MI-PRS-27 a move across filesystems writes the cmmt record");
  }

  {
    /* MI-PRS-28 */
    NSString *f = folder(@"f"), *g = folder(@"g");
    NSString *src = commented(f, @"plain.txt", nil);
    [copier copyItemAtPath: src
                    toPath: [g stringByAppendingPathComponent: @"plain.txt"]
                   handler: nil metadataError: &err];
    PASS(![fm fileExistsAtPath: [g stringByAppendingPathComponent: @".DS_Store"]],
         "MI-PRS-28 an item without a comment leaves no .DS_Store behind");
  }

  {
    /* MI-PRS-29: unreadable store is reported, the copy stays. */
    NSString *h = folder(@"h"), *i = folder(@"i");
    NSString *src = commented(h, @"z.txt", text);
    [@"junk" writeToFile: [i stringByAppendingPathComponent: @".DS_Store"]
              atomically: NO];
    err = nil;
    PASS([copier copyItemAtPath: src
                         toPath: [i stringByAppendingPathComponent: @"z.txt"]
                        handler: nil metadataError: &err]
         && err != nil
         && [fm fileExistsAtPath: [i stringByAppendingPathComponent: @"z.txt"]],
         "MI-PRS-29 an unreadable .DS_Store is an error, not silently replaced");
  }

  {
    /* MI-PRS-31: nested items of a copied folder. */
    NSString *j = folder(@"j"), *k = folder(@"k");
    NSString *tree = [j stringByAppendingPathComponent: @"tree"];
    [fm createDirectoryAtPath: tree attributes: nil];
    [fm createDirectoryAtPath: [tree stringByAppendingPathComponent: @"sub"]
                   attributes: nil];
    commented(tree, @"top.txt", text);
    commented([tree stringByAppendingPathComponent: @"sub"], @"deep.txt", text);
    commented(tree, @"none.txt", nil);
    NSString *tcopy = [k stringByAppendingPathComponent: @"tree"];
    err = nil;
    PASS([copier copyItemAtPath: tree toPath: tcopy handler: nil
                  metadataError: &err] && err == nil,
         "MI-PRS-31 copy of a folder tree succeeds");
    PASS_EQUAL(cmmt(tcopy, @"top.txt"), text,
         "MI-PRS-31 an item in the copied folder gets its cmmt record");
    PASS_EQUAL(cmmt([tcopy stringByAppendingPathComponent: @"sub"], @"deep.txt"),
         text, "MI-PRS-31 an item two levels down gets its cmmt record");
    PASS(cmmt(tcopy, @"none.txt") == nil,
         "MI-PRS-31 an item without a comment gets none");
  }

  {
    /* MI-PRS-32: the old name's record goes with a move. */
    NSString *l = folder(@"l"), *n = folder(@"n");
    NSString *src = commented(l, @"gone.txt", text);
    DSStore *s = [DSStore createStoreAtPath:
      [l stringByAppendingPathComponent: @".DS_Store"] withEntries: nil];
    [s setCommentsForFilename: @"gone.txt" comments: text];
    [s setCommentsForFilename: @"stays.txt" comments: @"mine"];
    [s save];
    PASS([copier moveItemAtPath: src
                         toPath: [n stringByAppendingPathComponent: @"gone.txt"]
                        handler: nil metadataError: &err],
         "MI-PRS-32 move out of a folder succeeds");
    PASS(cmmt(l, @"gone.txt") == nil,
         "MI-PRS-32 the source folder loses the moved item's record");
    PASS_EQUAL(cmmt(l, @"stays.txt"), @"mine",
         "MI-PRS-32 records of other items in the source folder stay");

    NSString *src2 = commented(l, @"x.txt", text);
    s = [DSStore storeWithPath: [l stringByAppendingPathComponent: @".DS_Store"]];
    [s load]; [s setCommentsForFilename: @"x.txt" comments: text]; [s save];
    CrossFSCopier *xc = [[CrossFSCopier new] autorelease];
    [xc moveItemAtPath: src2
                toPath: [n stringByAppendingPathComponent: @"x.txt"]
               handler: nil metadataError: &err];
    PASS(cmmt(l, @"x.txt") == nil && [cmmt(n, @"x.txt") isEqual: text],
         "MI-PRS-32 the same across filesystems");

    /* rename inside one folder */
    NSString *src3 = commented(l, @"old.txt", text);
    s = [DSStore storeWithPath: [l stringByAppendingPathComponent: @".DS_Store"]];
    [s load]; [s setCommentsForFilename: @"old.txt" comments: text]; [s save];
    [copier moveItemAtPath: src3
                    toPath: [l stringByAppendingPathComponent: @"new.txt"]
                   handler: nil metadataError: &err];
    PASS(cmmt(l, @"old.txt") == nil && [cmmt(l, @"new.txt") isEqual: text],
         "MI-PRS-32 a rename inside one folder moves the record to the new name");
  }

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
