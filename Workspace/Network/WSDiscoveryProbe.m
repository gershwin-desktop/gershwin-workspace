/* WSDiscoveryProbe.m
 *
 * WS-Discovery client side: Probe over UDP multicast, ProbeMatch parsing
 * and the metadata exchange that yields the friendly host name.
 *
 * The datagrams follow the exact shapes wsdd (the Samba WS-Discovery daemon)
 * sends and Windows answers; a probe without a wsdp:Device Types element or
 * from a source port other than 3702 is ignored by Windows targets.
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "WSDiscoveryProbe.h"

#ifndef _WIN32
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#endif

#define WSD_UDP_MCAST_V4    "239.255.255.250"
#define WSD_UDP_PORT        3702

@implementation WSDiscoveryProbe

+ (void)initialize
{
  if (self == [WSDiscoveryProbe class]) {
    srandom((unsigned int)(time(NULL) ^ getpid()));
  }
}

#pragma mark - Message builders

+ (NSString *)probeXML
{
  return [self probeXMLWithMessageID:nil];
}

+ (NSString *)probeXMLWithMessageID:(NSString *)messageID
{
  if (!messageID) {
    /* UUID v4: the target checks that we send a unique urn:uuid id. */
    NSString *uuidString =
      [[NSUUID UUID] UUIDString];
    messageID = [NSString stringWithFormat:@"urn:uuid:%@", uuidString];
  }

  return [NSString stringWithFormat:
    @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n"
    "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
    "xmlns:a=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
    "xmlns:d=\"http://schemas.xmlsoap.org/ws/2005/04/discovery\" "
    "xmlns:wsdp=\"http://schemas.xmlsoap.org/ws/2006/02/devprof\">"
    "<soap:Header>"
    "<a:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</a:Action>"
    "<a:MessageID>%@</a:MessageID>"
    "<a:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</a:To>"
    "</soap:Header>"
    "<soap:Body><d:Probe>"
    "<d:Types>wsdp:Device</d:Types>"
    "</d:Probe></soap:Body>"
    "</soap:Envelope>", messageID];
}

+ (NSString *)metadataRequestXMLForEndpoint:(NSString *)endpoint
{
  return [NSString stringWithFormat:
    @"<?xml version=\"1.0\" encoding=\"utf-8\"?>\r\n"
    "<soap:Envelope xmlns:soap=\"http://www.w3.org/2003/05/soap-envelope\" "
    "xmlns:a=\"http://schemas.xmlsoap.org/ws/2004/08/addressing\" "
    "xmlns:w=\"http://schemas.xmlsoap.org/ws/2004/09/mex\">"
    "<soap:Header>"
    "<a:Action>http://schemas.xmlsoap.org/ws/2004/09/transfer/Get</a:Action>"
    "<a:MessageID>urn:uuid:%@</a:MessageID>"
    "<a:ReplyTo>"
    "<a:Address>"
    "http://schemas.xmlsoap.org/ws/2004/08/addressing/role/anonymous"
    "</a:Address>"
    "</a:ReplyTo>"
    "<a:To>%@</a:To>"
    "</soap:Header>"
    "<soap:Body/>"
    "</soap:Envelope>",
    [[NSUUID UUID] UUIDString], endpoint];
}

#pragma mark - Minimal XML local-name scanning

/* The WS-Discovery and metadata XML has a small, controlled vocabulary, so
   instead of a full XML parser a local-name scanner suffices: it finds the
   first "start" tag with the given local name in front of any namespace
   prefix and returns the text up to the next "close" tag. */

/* Finds the first "start" tag with the given local name at or after
   aStart; returns the range of the element text or NSNotFound. */
static NSRange elementTextRange(NSString *xml, NSString *localName,
                                NSUInteger start)
{
  NSUInteger length = [xml length];
  NSRange search = NSMakeRange(start, length - start);
  while (search.location != NSNotFound && search.location < length) {
    NSRange open = [xml rangeOfString:@"<"
                              options:0
                                range:search];
    if (open.location == NSNotFound) {
      break;
    }

    /* Read the tag name: optional prefix, local name, then the tag end. */
    NSUInteger nameStart = open.location + 1;
    NSRange prefixColon = [xml rangeOfString:@":"
                                     options:0
                                       range:NSMakeRange(nameStart,
                                              MIN(10, length - nameStart))];
    NSUInteger tagStart = (prefixColon.location != NSNotFound
                           && prefixColon.location < nameStart + 11)
                              ? prefixColon.location + 1
                              : nameStart;

    NSUInteger nameEnd = tagStart;
    while (nameEnd < length) {
      unichar c = [xml characterAtIndex:nameEnd];
      if (c == '>' || c == ' ' || c == '/' || c == '\r' || c == '\n') {
        break;
      }
      nameEnd++;
    }
    NSString *tag =
      [xml substringWithRange:NSMakeRange(tagStart, nameEnd - tagStart)];
    if ([tag isEqualToString:localName]) {
      /* Element text starts after the open tag end; find the close tag. */
      NSRange close = [xml rangeOfString:@">"
                                 options:0
                                   range:NSMakeRange(nameEnd,
                                          length - nameEnd)];
      if (close.location == NSNotFound) {
        break;
      }
      NSRange value = { close.location + 1, 0 };
      NSRange closeTag = [xml rangeOfString:@"</"
                                    options:0
                                      range:NSMakeRange(value.location,
                                             length - value.location)];
      if (closeTag.location == NSNotFound) {
        break;
      }
      value.length = closeTag.location - value.location;
      if (value.length == 0) {
        /* Self-closed or empty element: keep scanning for the next match. */
        search.location = closeTag.location + 2;
        search.length = length - search.location;
        continue;
      }
      return value;
    }

    search.location = nameEnd;
    search.length = length - search.location;
  }
  return NSMakeRange(NSNotFound, 0);
}

+ (NSString *)xmlTextForLocalName:(NSString *)localName
                              inXML:(NSString *)xml
                              from:(NSUInteger)start
{
  NSRange value = elementTextRange(xml, localName, start);
  if (value.location == NSNotFound) {
    return nil;
  }
  return [xml substringWithRange:value];
}

#pragma mark - Response parsing

+ (NSArray *)parseProbeMatchesXML:(NSString *)xml
{
  NSMutableArray *matches = [NSMutableArray array];
  if (!xml) {
    return matches;
  }

  NSUInteger scan = [xml rangeOfString:@"Body"].location;
  if (scan == NSNotFound) {
    return matches;
  }

  while (scan != NSNotFound) {
    NSRange match = elementTextRange(xml, @"ProbeMatch", scan);
    if (match.location == NSNotFound) {
      break;
    }
    NSString *matchXML = [xml substringWithRange:match];
    NSString *endpoint = [self xmlTextForLocalName:@"Address"
                                               inXML:matchXML
                                                from:0];
    NSString *xaddrs = [self xmlTextForLocalName:@"XAddrs"
                                             inXML:matchXML
                                              from:0];
    NSString *types = [self xmlTextForLocalName:@"Types"
                                            inXML:matchXML
                                             from:0];
    if (endpoint || xaddrs) {
      [matches addObject:[NSDictionary
          dictionaryWithObjectsAndKeys:
            endpoint ?: @"", @"endpoint",
            xaddrs ?: @"", @"xaddrs",
            types ?: @"", @"types",
            nil]];
    }
    scan = match.location + match.length;
  }
  return matches;
}

+ (NSDictionary *)parseMetadataXML:(NSString *)xml
{
  if (!xml) {
    return nil;
  }

  /* Only the host relationship section matters; ThisDevice/ThisModel carry
     generic product names. */
  NSUInteger relationship = [xml rangeOfString:@"Relationship"].location;
  if (relationship == NSNotFound) {
    return nil;
  }

  NSString *host = [self xmlTextForLocalName:@"Computer"
                                         inXML:xml
                                          from:relationship];
  if (!host) {
    return nil;
  }

  /* wsdd's and Windows' published form is "MUSIC/Workgroup:WORKGROUP"
     (or "host/Domain:DOMAIN").  Everything before the first slash is the
     host name. */
  NSString *name = host;
  NSString *workgroup = nil;
  NSRange slash = [host rangeOfString:@"/"];
  if (slash.location != NSNotFound) {
    name = [host substringToIndex:slash.location];
    workgroup = [host substringFromIndex:slash.location + 1];
    for (NSString *prefix in [NSArray arrayWithObjects:@"Workgroup:",
                                                       @"Domain:", nil]) {
      NSRange prefixRange = [workgroup rangeOfString:prefix];
      if (prefixRange.location == 0) {
        workgroup =
          [workgroup substringFromIndex:[prefix length]];
        break;
      }
    }
  }

  if ([name length] == 0) {
    return nil;
  }
  return [NSDictionary
      dictionaryWithObjectsAndKeys:
        name, @"name",
        workgroup ?: @"", @"workgroup",
        nil];
}

/* First IPv4 xaddr of the space-separated XAddrs list.  Returns the
   network address and sets wsPort out, or nil. */
static NSString *firstIPv4FromXAddrs(NSString *xaddrs, int *outPort)
{
  for (NSString *candidate in [xaddrs componentsSeparatedByString:@" "]) {
    NSURL *url = [NSURL URLWithString:candidate];
    if (!url) {
      continue;
    }
    /* An IPv6 xaddr would contain a colon inside the brackets and no
       plain IPv4 part; the probes are IPv4-only, so only a dotted quad
       host qualifies. */
    NSString *host = [url host];
    if (host && [host rangeOfString:@"."].location != NSNotFound) {
      *outPort = [url port] ? [[url port] intValue] : 5357;
      return host;
    }
  }
  return nil;
}

#pragma mark - Metadata exchange (HTTP on the XAddr)

/* Plain HTTP POST over a socket - NSURLConnection needs a teasing run loop
   and we want a short hard timeout anyway.  Returns the response body or
   nil. */
static NSString *httpPOST(NSString *hostString,
                          int port,
                          NSString *httpPath,
                          NSString *body)
{
#ifndef _WIN32
  struct hostent *resolved =
    gethostbyname([hostString UTF8String]);
  if (!resolved) {
    return nil;
  }
  struct in_addr target;
  memcpy(&target, resolved->h_addr_list[0], sizeof(target));
  if (inet_addr(inet_ntoa(target)) == INADDR_NONE) {
    return nil;
  }

  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return nil;
  }

  /* Connect non-blocking with a hard select timeout: a target that does
     not answer must not block the discovery thread. */
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons(port);
  addr.sin_addr = target;

  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  connect(fd, (struct sockaddr *)&addr, sizeof(addr));

  fd_set writeSet;
  FD_ZERO(&writeSet);
  FD_SET(fd, &writeSet);
  struct timeval timeout = { 2, 0 };
  if (select(fd + 1, NULL, &writeSet, NULL, &timeout) <= 0) {
    close(fd);
    return nil;
  }
  fcntl(fd, F_SETFL, flags);

  int msec = 5000;
  struct timeval recvTimeout = { msec / 1000, (msec % 1000) * 1000 };
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, sizeof(recvTimeout));

  NSMutableString *request = [NSMutableString
      stringWithFormat:]
    ;
#endif
  return nil;
}

#pragma mark - Probe round

+ (NSArray *)probeComputerDevicesWithTimeout:(NSTimeInterval)seconds
{
  return [self probeDevicesWithTimeout:seconds];
}

@end
