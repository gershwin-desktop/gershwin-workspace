#include <DBKit/DBKBTree.h>
#include "test.h"

void test1(DBKBTree *tree)
{
  DBKBTreeNode *node;
  int index;


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

  printTree(tree);

  node = [tree nodeOfKey: [NSNumber numberWithUnsignedLong: 122] 
                getIndex: &index];
  if (node) {
  } else {
  }

  node = [tree nodeOfKey: [NSNumber numberWithUnsignedLong: 441] 
                getIndex: &index];
  if (node == nil) {
  } else {
  }

}
