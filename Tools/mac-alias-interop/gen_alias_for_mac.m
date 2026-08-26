/* gen_alias_for_mac.m - emit the three pieces of a classic Mac alias file
 * (empty data fork, resource fork, Finder Info) for a Mac-only target path,
 * so they can be reassembled on a real Mac and tested for recognition +
 * resolution.  Headless: it only uses FSNAlias, never the network.
 *
 * Usage: gen_alias_for_mac <targetPath> <volumeName> <outDir>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#include "FSNAlias.m"

int main(int argc, char **argv)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  if (argc < 4)
    {
      fprintf(stderr, "usage: %s <targetPath> <volumeName> <outDir>\n",
	      argv[0]);
      return 2;
    }
  NSString *target = [NSString stringWithUTF8String: argv[1]];
  NSString *volume = [NSString stringWithUTF8String: argv[2]];
  NSString *outDir = [NSString stringWithUTF8String: argv[3]];

  FSNAlias *a = [FSNAlias aliasWithTargetPath: target volumeName: volume];
  if (a == nil)
    {
      fprintf(stderr, "failed to build alias for %s\n",
	      [target UTF8String]);
      return 1;
    }

  NSData *rf = [a aliasResourceForkData];
  NSData *fi = [a aliasFinderInfoData];

  NSFileManager *fm = [NSFileManager defaultManager];
  [fm createDirectoryAtPath: outDir withIntermediateDirectories: YES
		 attributes: nil error: NULL];

  /* Empty data fork. */
  [@"" writeToFile: [outDir stringByAppendingPathComponent: @"alias.dat"]
	 atomically: NO encoding: NSUTF8StringEncoding error: NULL];
  /* Resource fork ("alis" record + handle-size prefix + map). */
  [rf writeToFile: [outDir stringByAppendingPathComponent: @"alias.rsrc"]
       atomically: NO];
  /* Finder Info (kIsAlias flag). */
  [fi writeToFile: [outDir stringByAppendingPathComponent: @"alias.finfo"]
       atomically: NO];

  printf("target = %s\n", [target UTF8String]);
  printf("volume = %s\n", [volume UTF8String]);
  printf("resource fork = %lu bytes\n", (unsigned long)[rf length]);
  printf("finder info  = %lu bytes\n", (unsigned long)[fi length]);
  printf("posix path TLV = %s\n", [[a posixPath] UTF8String]);
  [arp release];
  return 0;
}
