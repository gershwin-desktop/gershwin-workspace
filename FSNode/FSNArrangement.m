/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "FSNArrangement.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"

NSComparisonResult
FSNCompareLabels(NSInteger indexA, NSString *nameA,
                 NSInteger indexB, NSString *nameB)
{
  if (indexA == 0 || indexB == 0)
    {
      return (indexA == indexB) ? NSOrderedSame
        : (indexA == 0 ? NSOrderedAscending : NSOrderedDescending);
    }
  /* Finder sorts by the label's localized name, which is not the order of
   * the label numbers; the numbers only stand in when a name is missing. */
  if (nameA && nameB)
    {
      return [nameA caseInsensitiveCompare: nameB];
    }
  return (indexA < indexB) ? NSOrderedAscending
    : (indexA > indexB ? NSOrderedDescending : NSOrderedSame);
}

static void
labelOfNode(FSNode *node, NSInteger *index, NSString **name)
{
  id<FSNMetadataProvider> provider = [[FSNodeRep sharedInstance] metadataProvider];

  *index = 0;
  *name = nil;
  if ([provider respondsToSelector: @selector(labelIndexForPath:)])
    {
      *index = [provider labelIndexForPath: [node path]];
    }
  if (*index != 0 && [provider respondsToSelector: @selector(labelNameForPath:)])
    {
      *name = [provider labelNameForPath: [node path]];
    }
}

NSComparisonResult
FSNCompareNodesForArrangement(FSNode *a, FSNode *b,
                              FSNIconsArrangement arrangement)
{
  NSComparisonResult result = NSOrderedSame;

  switch (arrangement)
    {
      case FSNIconsArrangeKind:
        result = [[a typeDescription] caseInsensitiveCompare: [b typeDescription]];
        break;
      case FSNIconsArrangeDateModified:
        result = [[b modificationDate] compare: [a modificationDate]];
        break;
      case FSNIconsArrangeDateCreated:
        result = [[b creationDate] compare: [a creationDate]];
        break;
      case FSNIconsArrangeSize:
        {
          unsigned long long sa = [a isDirectory] ? 0 : [a fileSize];
          unsigned long long sb = [b isDirectory] ? 0 : [b fileSize];

          result = (sa == sb) ? NSOrderedSame
            : ((sa < sb) ? NSOrderedAscending : NSOrderedDescending);
        }
        break;
      case FSNIconsArrangeLabel:
        {
          NSInteger ia, ib;
          NSString *na, *nb;

          labelOfNode (a, &ia, &na);
          labelOfNode (b, &ib, &nb);
          result = FSNCompareLabels (ia, na, ib, nb);
        }
        break;
      default:
        break;
    }

  return (result != NSOrderedSame) ? result
    : [[a name] caseInsensitiveCompare: [b name]];
}
