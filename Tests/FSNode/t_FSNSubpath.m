/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Headless coverage for the path containment helpers in FSNFunctions.m.
 * File operations, locking and viewer invalidation all decide "is this
 * node inside that folder" with them, so a sibling whose name merely
 * starts the same way must never count as inside. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNFunctions.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS(isSubpathOfPath(@"/Users/foo", @"/Users/foo/bar") == YES,
       "a child is inside its parent");
  PASS(isSubpathOfPath(@"/Users/foo", @"/Users/foo/bar/baz.txt") == YES,
       "a grandchild is inside its grandparent");
  PASS(isSubpathOfPath(@"/", @"/etc") == YES,
       "everything is inside the root");
  PASS(isSubpathOfPath(@"/Users/foo", @"/Users/foo") == NO,
       "a path is not inside itself");
  PASS(isSubpathOfPath(@"/Users/foo", @"/Users/foobar") == NO,
       "a sibling sharing a prefix is not inside");
  PASS(isSubpathOfPath(@"/Users/foo", @"/Users/foobar/foo/notes.txt") == NO,
       "a same-named folder under a sibling is not inside");
  PASS(isSubpathOfPath(@"/Users/foo/bar", @"/Users/foo") == NO,
       "a parent is not inside its child");

  PASS_EQUAL(subtractFirstPartFromPath(@"/Users/foo/bar/baz", @"/Users/foo"),
	     @"bar/baz", "the remainder after the parent");
  PASS_EQUAL(subtractFirstPartFromPath(@"/Users/foo", @"/Users/foo"),
	     @"/", "no remainder for the parent itself");
  PASS_EQUAL(subtractFirstPartFromPath(@"/etc/hosts", @"/"),
	     @"etc/hosts", "the remainder under the root");

  [arp release];
  return 0;
}
