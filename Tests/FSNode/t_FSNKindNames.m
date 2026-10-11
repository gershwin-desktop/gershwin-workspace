/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../FSNode/FSNKindNames.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS_EQUAL([FSNKindNames kindForExtension: @"txt"], @"Plain Text Document", "txt");
  PASS_EQUAL([FSNKindNames kindForExtension: @"PDF"], @"PDF Document", "extension is case-insensitive");
  PASS_EQUAL([FSNKindNames kindForExtension: @"png"], @"PNG Image", "png");
  PASS_EQUAL([FSNKindNames kindForExtension: @"jpg"], [FSNKindNames kindForExtension: @"jpeg"],
             "jpg and jpeg share a kind");
  PASS([FSNKindNames kindForExtension: @"zzunknown"] == nil, "unknown extension has no kind");
  PASS([FSNKindNames kindForExtension: @""] == nil, "empty extension has no kind");
  PASS([FSNKindNames isIdentifierName: @"NSPDFPboardType"], "a pasteboard type is not a kind");
  PASS([FSNKindNames isIdentifierName: @"public.plain-text"], "a UTI is not a kind");
  PASS(![FSNKindNames isIdentifierName: @"Text Document"], "a phrase is a kind");
  PASS(![FSNKindNames isIdentifierName: @"Rich Text"], "another phrase is a kind");

  [arp release];
  return 0;
}
