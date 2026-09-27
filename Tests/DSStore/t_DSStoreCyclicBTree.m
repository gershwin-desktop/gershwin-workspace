/* t_DSStoreCyclicBTree.m - ObjectTesting coverage for -[DSStore load]
 * against a B-tree whose root node points to itself as a child.
 *
 * -readBTreeNode: recursed on file-supplied child/sibling block numbers
 * with no cycle check, so a corrupt or hostile .DS_Store whose tree loops
 * back on itself recurses forever - a stack overflow, not a clean load
 * failure.
 *
 * The fixture is built directly with DSBuddyAllocator's writer API (the
 * same primitives -[DSStore save] uses) rather than a full save/corrupt
 * round trip: allocate one internal B-tree node whose nextNode AND single
 * child pointer are both its own block number, and point the DSDB
 * superblock's root at it.
 *
 * A stack overflow crashes the process, so the load runs in a forked
 * child: the parent asserts the child exited normally (no crash) and
 * that -load returned NO, rather than asserting anything in-process that
 * an actual overflow would never let run.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DSStore.h"
#import "DSBuddyAllocator.h"
#import "DSStoreEntry.h"

#include <sys/wait.h>
#include <unistd.h>

/* Writes a minimal but structurally valid .DS_Store at `path' whose sole
 * B-tree node is internal (nextNode != 0) and whose only child pointer -
 * and its nextNode/rightmost-child word - is the node's OWN block number. */
static void
writeCyclicFixture(NSString *path)
{
  DSBuddyAllocator *alloc = [[DSBuddyAllocator alloc] initWithFile:path];
  BOOL opened = [alloc openForWriting];
  NSCAssert(opened, @"openForWriting failed for fixture");

  int superblk = [alloc allocate:20];
  [alloc setTOCName:@"DSDB" blockNumber:superblk];

  int node = [alloc allocate:256];
  DSStoreEntry *entry = [DSStoreEntry iconLocationEntryForFile:@"a" x:40 y:40];

  DSBuddyBlock *b = [alloc getBlock:node];
  [b writeUInt32:(uint32_t)node];   /* nextNode = self: marks the node
                                      internal AND is the cycle itself */
  [b writeUInt32:1];                /* one pivot record */
  [b writeUInt32:(uint32_t)node];   /* childNum for that pivot = self */
  [b writeBytes:[entry encode]];
  [b zeroFill];
  [b close];

  DSBuddyBlock *s = [alloc getBlock:superblk];
  [s writeUInt32:(uint32_t)node];   /* rootNode */
  [s writeUInt32:1];                /* levels */
  [s writeUInt32:1];                /* records */
  [s writeUInt32:1];                /* nodes */
  [s writeUInt32:4096];             /* pageSize */
  [s zeroFill];
  [s close];

  [alloc setRootBlockAddress:0x100b];
  [alloc flush];
  [alloc release];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat:@"t_dsstore_cyclic_%d.DS_Store", (int)getpid()]];
  [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];

  writeCyclicFixture(path);
  PASS([[NSFileManager defaultManager] fileExistsAtPath:path],
       "cyclic fixture file was written");

  pid_t pid = fork();
  if (pid == 0)
    {
      NSAutoreleasePool *childPool = [NSAutoreleasePool new];
      DSStore *store = [DSStore storeWithPath:path];
      BOOL loaded = [store load];
      [childPool release];
      _exit(loaded ? 0 : 1);
    }

  int status = 0;
  PASS(waitpid(pid, &status, 0) == pid, "forked load() child was reaped");

  BOOL crashed = WIFSIGNALED(status);
  if (crashed)
    {
      NSLog(@"child terminated by signal %d (unbounded recursion on the "
            @"self-referencing B-tree)", WTERMSIG(status));
    }
  PASS(!crashed, "loading a self-referencing B-tree does not overflow the stack");
  PASS(WIFEXITED(status) && WEXITSTATUS(status) == 1,
       "load() returns NO on a cyclic B-tree instead of recursing forever");

  [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
  [arp release];
  return 0;
}
