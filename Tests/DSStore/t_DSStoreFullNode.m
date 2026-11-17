/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_DSStoreFullNode.m - a B-tree node the writer packs up to its last
 * byte must load again.
 *
 * The writer fills a node up to the full 4096-byte page, but the reader
 * read every node 4 bytes short, so a record ending in those bytes ran
 * "past its node" and the whole store failed to load. Workspace then
 * reported "The .DS_Store of the folder could not be read" on every move
 * out of such a folder.
 *
 * DSSTORE_FULL_NODE_FIXTURE may name a real store with such a node; it is
 * checked as well when set (it is not part of the repository).
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DSStore.h"

#include <unistd.h>

/* A ustr cmmt record takes 16 + 2 * (name + comment) bytes, so names and
 * comments of these lengths fill a node to exactly 4096 bytes (8 bytes of
 * node header). */
static NSString *
repeated(unichar c, NSUInteger n)
{
  NSMutableString *s = [NSMutableString stringWithCapacity: n];
  NSUInteger i;

  for (i = 0; i < n; i++)
    {
      [s appendFormat: @"%C", c];
    }
  return s;
}

static BOOL
roundTrips(NSString *path, NSDictionary *comments)
{
  DSStore *s = [DSStore createStoreAtPath: path withEntries: nil];
  NSEnumerator *en = [comments keyEnumerator];
  NSString *name;

  while ((name = [en nextObject]) != nil)
    {
      [s setCommentsForFilename: name comments: [comments objectForKey: name]];
    }
  if ([s save] == NO)
    {
      return NO;
    }
  s = [DSStore storeWithPath: path];
  if ([s load] == NO)
    {
      return NO;
    }
  en = [comments keyEnumerator];
  while ((name = [en nextObject]) != nil)
    {
      if (![[s commentsForFilename: name]
             isEqual: [comments objectForKey: name]])
        {
          return NO;
        }
    }
  return [[s entries] count] == [comments count];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_dsfull_%d", (int)getpid()]];
  NSString *store = [d stringByAppendingPathComponent: @".DS_Store"];
  NSString *fixture = [[[NSProcessInfo processInfo] environment]
    objectForKey: @"DSSTORE_FULL_NODE_FIXTURE"];
  NSMutableDictionary *many = [NSMutableDictionary dictionary];
  int i;

  [fm createDirectoryAtPath: d attributes: nil];

  /* Root leaf: 8 + (16 + 2 * (5 + 1000)) + (16 + 2 * (5 + 1018)) = 4096. */
  PASS(roundTrips(store, [NSDictionary dictionaryWithObjectsAndKeys:
         repeated('a', 1000), @"a.txt", repeated('b', 1018), @"b.txt", nil]),
       "a root node filled to its last byte loads again");

  /* Four records of 1022 bytes fill each leaf exactly, so the tree gets
   * full child nodes below an internal root (twelve records keep the root
   * within one node). */
  for (i = 0; i < 12; i++)
    {
      [many setObject: repeated('c', 496)
               forKey: [NSString stringWithFormat: @"f%02d.txt", i]];
    }
  PASS(roundTrips(store, many),
       "child nodes filled to their last byte load again");

  if (fixture != nil)
    {
      DSStore *s = [DSStore storeWithPath: fixture];

      PASS([s load] && [[s entries] count] > 0,
           "the store from the field with a full node loads");
    }

  [fm removeFileAtPath: d handler: nil];
  [arp release];
  return 0;
}
