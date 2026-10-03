/* t_FModuleContentsSearch.m - ObjectTesting coverage for FModuleContents'
 * "contents" search predicate.
 *
 * checkPath:withAttributes: reads a candidate file into an NSData and
 * scans its raw bytes for the user's search term.  NSData's bytes are NOT
 * NUL-terminated, so scanning them with strstr() (which has no length
 * parameter and keeps going until it finds a NUL) can walk past the end of
 * the buffer for any text file that has no embedded NUL - true of nearly
 * every real text file, since searchtool.m calls this per candidate file
 * during an ordinary Finder search.
 *
 * This tool is built with AddressSanitizer (see GNUmakefile.preamble) so
 * the over-read is caught deterministically as a heap-buffer-overflow
 * abort instead of depending on what happens to sit past the allocation -
 * a plain "did checkPath: return the right BOOL" assertion cannot tell
 * strstr()'s unsafe scan apart from memmem()'s bounded one, because both
 * agree on the answer whenever heap noise beyond the buffer does not
 * happen to contain the needle or run out before a stray NUL byte.  RED
 * (unpatched strstr) aborts this whole test binary; GREEN (memmem, bounded
 * by the real buffer length) completes normally.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include "../../Workspace/Finder/Modules/FModuleContents/FModuleContents.m"

static NSString *
writeFixture(NSString *content)
{
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
      [NSString stringWithFormat: @"t_FModuleContentsSearch_%d.txt",
                                   (int)getpid()]];
  [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
  [content writeToFile: path atomically: NO];
  return path;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *needle = @"XYZZY_PLUGH_NEEDLE";

  FModuleContents *module = [[FModuleContents alloc]
      initWithSearchCriteria:
          [NSDictionary dictionaryWithObject: needle forKey: @"what"]
                   searchTool: nil];

  /* --- no real match anywhere in the file: this is the common case
   * (most candidate files during a search do not contain the term), and
   * the one that forces the scan to run past the real content looking
   * for either a match or a terminator that is not there. --- */
  {
    NSMutableString *filler = [NSMutableString string];
    NSUInteger i;
    for (i = 0; i < 512; i++) {
      [filler appendString: @"B"];
    }
    NSString *path = writeFixture(filler);
    NSDictionary *attrs = [fm attributesOfItemAtPath: path error: NULL];

    PASS([module checkPath: path withAttributes: attrs] == NO,
         "a file without the search term does not match, and the scan "
         "does not run past the end of the buffer (no ASan abort)");

    [fm removeFileAtPath: path handler: nil];
  }

  /* --- a real match still needs to be found correctly with the fix --- */
  {
    NSString *content = [NSString stringWithFormat:
        @"leading filler text with no nul...%@...trailing filler", needle];
    NSString *path = writeFixture(content);
    NSDictionary *attrs = [fm attributesOfItemAtPath: path error: NULL];

    PASS([module checkPath: path withAttributes: attrs] == YES,
         "a file that really contains the search term still matches");

    [fm removeFileAtPath: path handler: nil];
  }

  RELEASE (module);
  [arp release];
  return 0;
}
