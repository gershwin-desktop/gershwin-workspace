#include <DBKit/DBKBTree.h>
#include "test.h"

void test1(DBKBTree *tree)
{
  DBKBTreeNode *node;
  int index;

  NSDebugLLog(@"gwspace", @"test 1");

  NSDebugLLog(@"gwspace", @"insert 10 items");
  [tree insertKey: [NSNumber numberWithUnsignedLong: 372]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 245]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 491]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 474]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 440]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 122]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 418]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 125]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 934]];
  [tree insertKey: [NSNumber numberWithUnsignedLong: 752]];

  NSDebugLLog(@"gwspace", @"Show tree structure");
  printTree(tree);

  NSDebugLLog(@"gwspace", @"search for item 122 in tree");
  node = [tree nodeOfKey: [NSNumber numberWithUnsignedLong: 122] 
                getIndex: &index];
  if (node) {
    NSDebugLLog(@"gwspace", @"found 122");
  } else {
    NSDebugLLog(@"gwspace", @"************* ERROR 122 not found *****************");
  }

  NSDebugLLog(@"gwspace", @"search for item 441 not in tree");
  node = [tree nodeOfKey: [NSNumber numberWithUnsignedLong: 441] 
                getIndex: &index];
  if (node == nil) {
    NSDebugLLog(@"gwspace", @"441 not found");
  } else {
    NSDebugLLog(@"gwspace", @"************* ERROR found 441 *****************");
  }

  NSDebugLLog(@"gwspace", @"test 1 passed\n\n");
}
