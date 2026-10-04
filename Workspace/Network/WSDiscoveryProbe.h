/* WSDiscoveryProbe.h
 *
 * WS-Discovery (UDP multicast to 239.255.255.250:3702, SOAP over UDP) -
 * the "Networks" view name discovery that Windows itself uses.  This is
 * fallback SMB host discovery number two beside mDNS (NetworkServiceManager)
 * and the legacy NetBIOS name service (NBNSProbe); Samba ships the wsdd
 * daemon that speaks the same protocol.
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface WSDiscoveryProbe : NSObject

/**
 * One probe round: multicast a Probe for wsdp:Device targets, collect the
 * ProbeMatches, and fetch the friendly host name of each matching computer
 * through the metadata exchange (HTTP POST on the XAddr, usually port
 * 5357).  This blocks while the probe runs - call it from a background
 * thread.
 *
 * Returns an array of NSDictionary entries for matching computers (devices
 * that advertise the pub:Computer type, e.g. Windows hosts and wsdd):
 *   "address":    IPv4 string taken from the XAddr
 *   "name":       host name from the metadata (e.g. "MUSIC"), may be nil
 *                 when the metadata exchange failed
 *   "workgroup":  "WORKGROUP" or the joining domain, may be nil
 *   "endpoint":   the urn:uuid:... endpoint reference
 */
+ (NSArray *)probeComputerDevicesWithTimeout:(NSTimeInterval)seconds;

/**
 * The probe datagram body.  The wsdp:Device types element is required -
 * targets ignore probes without a Types element (verified against Windows:
 * a Types-less probe is silently dropped).
 * Class-level so tests can compare it without sockets.
 */
+ (NSString *)probeXML;

/**
 * The SOAP-on-HTTP request for the metadata exchange.
 */
+ (NSString *)metadataRequestXMLForEndpoint:(NSString *)endpoint;

/**
 * Parses an xml ProbeMatches reply.  Returns an array of NSDictionary
 * entries with the keys "endpoint" (urn:uuid:...), "xaddrs" (the
 * space-separated transport address list of the match) and "types"
 * (e.g. "wsdp:Device pub:Computer"), or an empty array.
 */
+ (NSArray *)parseProbeMatchesXML:(NSString *)xml;

/**
 * Parses the metadata exchange response.  The host relationship section
 * carries the pub:Computer element, whose text is
 * "MUSIC/Workgroup:WORKGROUP" (or "host/Domain:DOMAIN").
 * Returns a dictionary with the keys "name" and "workgroup", or nil when
 * the XML does not carry a host section.
 */
+ (NSDictionary *)parseMetadataXML:(NSString *)xml;

@end
