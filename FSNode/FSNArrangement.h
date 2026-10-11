/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Finder's "Arrange By" orders, shared by every view that arranges items so
 * that the icon view and the column view never disagree on an order. */

#ifndef FSN_ARRANGEMENT_H
#define FSN_ARRANGEMENT_H

/* FSNIconsView.h, for the arrangement type, needs AppKit before it. */
#import <AppKit/AppKit.h>
#import "FSNIconsView.h"

@class FSNode;

/* Orders two nodes the way Finder arranges them (E25): name and kind A to Z
 * with folders taking no precedence, dates newest first, sizes smallest
 * first with the folders ahead, labels unlabelled first and then by the
 * label's name.  Ties fall back to the name, so the result does not depend
 * on the order the directory was read in.  The label order asks the
 * metadata provider of FSNodeRep. */
NSComparisonResult FSNCompareNodesForArrangement(FSNode *a, FSNode *b,
                                                 FSNIconsArrangement arrangement);

/* The label order alone, from the label indexes (0 = none) and the label
 * names (nil when unknown) of two items. */
NSComparisonResult FSNCompareLabels(NSInteger indexA, NSString *nameA,
                                    NSInteger indexB, NSString *nameB);

#endif /* FSN_ARRANGEMENT_H */
