/* NBNSProbe.h
 *
 * Legacy NetBIOS Name Service (UDP 137) and LLMNR (UDP 5355) name queries
 * used as an SMB host fallback discovery path beside the mDNS browser in
 * NetworkServiceManager.
 *
 * This is what "Network neighborhood" of Windows XP and 7 used: UDP 137 name
 * tables and master-browser elections.  Only IPv4 is supported - NetBIOS is
 * IPv4-only by definition and LLMNR has an IPv4 multicast address; anything
 * newer is reached through WS-Discovery (WSDiscoveryProbe) or mDNS.
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface NBNSProbe : NSObject

/**
 * Returns the answers of a single NBSTAT (node status) query to a host.
 * This is the packet Samba's nmblookup -A sends.  Returns a dictionary
 * with:
 *   "names":  NSArray of NSDictionary
 *     "name":  NSString - first 15 characters, blanks removed
 *     "type":  NSNumber - service type byte, e.g. 0x20 for the file server
 *     "group": NSNumber - YES when it is a group name (workgroup entries)
 *   "mac":    NSString - hardware address "aa:bb:cc:dd:ee:ff" (Windows hosts
 *             report it), or nil.
 * Returns nil if the host does not answer within the timeout.
 */
+ (NSDictionary *)nodeStatusOfHost:(NSString *)ip
                            timeout:(NSTimeInterval)seconds;

/**
 * Broadcasts a wildcard NB name query on every IPv4 broadcast interface and
 * returns the IP strings of the hosts that answered.  Access points that
 * block broadcast traffic make this return an empty list; use
 * WS-Discovery and mDNS as the enumeration sources in that case.
 */
+ (NSArray *)broadcastQueriedHostsWithTimeout:(NSTimeInterval)seconds;

/**
 * Resolves a NetBIOS name to the IP addresses of the host that owns the
 * given service type via a broadcast NB name query (what Samba's
 * nmblookup NAME sends).  Returns an array of IP strings, possibly empty.
 * Windows 10+ answers unicast queries only; Samba answers also here.
 */
+ (NSArray *)broadcastAddressesForName:(NSString *)name
                                suffix:(uint8_t)suffix
                                timeout:(NSTimeInterval)seconds;

/**
 * RFC 4795 LLMNR A query for a single-label host name, sent to the
 * 224.0.0.252:5355 multicast address.  Returns an array of IPv4 strings.
 * Multicast-restricted networks (some APs) still deliver this when they
 * block plain NetBIOS broadcasts.
 */
+ (NSArray *)llmnrAddressesForName:(NSString *)name
                            timeout:(NSTimeInterval)seconds;

/**
 * Returns the IPv4 addresses configured on this machine, e.g. "192.168.0.2".
 * Used to keep a probe result from listing our own shares.
 */
+ (NSArray *)localIPv4Addresses;

/**
 * YES if the IPv4 address belongs to this machine.
 */
+ (BOOL)isLocalIPv4Address:(NSString *)ip;

/**
 * The RFC 1002 first-level name encoding ("MUSIC" + 0x20 suffix becomes
 * "ENFFDEJEDC..."), exactly what Samba puts on the wire.  The 16-byte
 * first-level name is the 15-character name plus the suffix byte; each byte
 * is split into two characters "A" plus nibble.  The wildcard name "*" is
 * zero padded with suffix 0x00 (Samba's own encoding), every other name is
 * blank padded.  Class-level so tests can check it without sockets.
 */
+ (NSString *)firstLevelEncodedName:(NSString *)name suffix:(uint8_t)suffix;

/**
 * Parses an NBSTAT reply.  Returns the same dictionary shape as
 * nodeStatusOfHost:timeout:, or nil if the packet is not interpretable.
 * These are ALL class methods - the class has no state, and tests parse
 * recorded packets without touching a network.
 */
+ (NSDictionary *)parseNodeStatusData:(NSData *)data;

@end
