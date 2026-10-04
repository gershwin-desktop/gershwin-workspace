/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* WS-Discovery is how Windows 10 and 11 announce themselves; they rarely use
 * mDNS.  The probe must read the ProbeMatches a Windows host sends and the
 * host name out of its metadata, without a network. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "WSDiscoveryProbe.h"

static NSString *probeMatches =
  @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n"
  "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
  "xmlns:wsa=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
  "xmlns:wsd=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\" "
  "xmlns:pub=\"http://schemas.microsoft.com/windows/pub/2005/07\">"
  "<soap:Header><wsa:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/ProbeMatches</wsa:Action></soap:Header>"
  "<soap:Body><wsd:ProbeMatches><wsd:ProbeMatch>"
  "<wsa:EndpointReference><wsa:Address>urn:uuid:11111111-2222-3333-4444-555555555555</wsa:Address></wsa:EndpointReference>"
  "<wsd:Types>wsdp:Device pub:Computer</wsd:Types>"
  "<wsd:XAddrs>http://192.168.0.52:5357/11111111-2222-3333-4444-555555555555</wsd:XAddrs>"
  "<wsd:MetadataVersion>2</wsd:MetadataVersion>"
  "</wsd:ProbeMatch></wsd:ProbeMatches></soap:Body></soap:Envelope>";

static NSString *metadata =
  @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n"
  "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
  "xmlns:wsx=\"http://schemas.xmlsoap.org/ws/2004/09/mex\" "
  "xmlns:wsdp=\"http://schemas.xmlsoap.org/ws/2006/02/devprof\" "
  "xmlns:pub=\"http://schemas.microsoft.com/windows/pub/2005/07\">"
  "<soap:Body><wsx:Metadata>"
  "<wsx:MetadataSection Dialect=\"http://schemas.xmlsoap.org/ws/2006/02/devprof/ThisDevice\">"
  "<wsdp:ThisDevice><wsdp:FriendlyName>Some Device</wsdp:FriendlyName></wsdp:ThisDevice></wsx:MetadataSection>"
  "<wsx:MetadataSection Dialect=\"http://schemas.xmlsoap.org/ws/2006/02/devprof/Relationship\">"
  "<wsdp:Relationship Type=\"http://schemas.xmlsoap.org/ws/2006/02/devprof/host\"><wsdp:Host>"
  "<wsdp:Types>pub:Computer</wsdp:Types>"
  "<pub:Computer>MUSIC/Workgroup:WORKGROUP</pub:Computer>"
  "</wsdp:Host></wsdp:Relationship></wsx:MetadataSection>"
  "</wsx:Metadata></soap:Body></soap:Envelope>";

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("probe request")
    {
      NSString *probe = [WSDiscoveryProbe probeXML];
      PASS([probe rangeOfString: @"<d:Types>wsdp:Device</d:Types>"].location
             != NSNotFound,
           "the probe asks for wsdp:Device, which Windows requires");
      PASS([[WSDiscoveryProbe probeXML] isEqual: probe] == NO,
           "every probe carries its own message id");
    }
  END_SET("probe request")

  START_SET("probe matches")
    {
      NSArray *matches = [WSDiscoveryProbe parseProbeMatchesXML: probeMatches];
      NSDictionary *match = [matches firstObject];

      PASS([matches count] == 1, "one ProbeMatch is found");
      PASS([[match objectForKey: @"endpoint"]
             isEqual: @"urn:uuid:11111111-2222-3333-4444-555555555555"],
           "the endpoint reference is the whole urn:uuid");
      PASS([[match objectForKey: @"xaddrs"]
             isEqual: @"http://192.168.0.52:5357/11111111-2222-3333-4444-555555555555"],
           "the transport address is read in full, not cut at a nested tag");
      PASS([[match objectForKey: @"types"] rangeOfString: @"Computer"].location
             != NSNotFound,
           "the device types name it a computer");
      PASS([[WSDiscoveryProbe parseProbeMatchesXML: @"<a/>"] count] == 0,
           "a reply without ProbeMatches yields nothing");
      PASS([[WSDiscoveryProbe parseProbeMatchesXML: nil] count] == 0,
           "nil yields nothing");
    }
  END_SET("probe matches")

  START_SET("metadata")
    {
      NSDictionary *host = [WSDiscoveryProbe parseMetadataXML: metadata];

      PASS([[host objectForKey: @"name"] isEqual: @"MUSIC"],
           "the host name comes from the host relationship section");
      PASS([[host objectForKey: @"workgroup"] isEqual: @"WORKGROUP"],
           "the Workgroup: prefix is removed");
      PASS([WSDiscoveryProbe parseMetadataXML: probeMatches] == nil,
           "XML without a host section yields nil");
    }
  END_SET("metadata")

  [arp release];
  return 0;
}
