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
#import "NBNSProbe.h"

#ifndef _WIN32
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <sys/select.h>
#import <sys/time.h>
#import <string.h>
#import <stdlib.h>
#endif

#define WSD_UDP_MCAST_V4    "239.255.255.250"
#define WSD_UDP_PORT        3702

@implementation WSDiscoveryProbe

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
   first element with the given local name, whatever its namespace prefix,
   and returns the text up to its matching close tag. */

/* Reads the tag that starts at the '<' at index open.  Returns the index of
   its closing '>' (NSNotFound for a malformed tag) and fills in the local
   name (prefix removed), whether it is an end tag and whether it is
   self-closed. */
static NSUInteger readTag(NSString *xml, NSUInteger open, NSString **localName,
                          BOOL *isEnd, BOOL *isSelfClosed)
{
  NSUInteger length = [xml length];
  NSUInteger pos = open + 1;
  *isEnd = NO;
  *isSelfClosed = NO;
  *localName = nil;

  if (pos < length && [xml characterAtIndex:pos] == '/') {
    *isEnd = YES;
    pos++;
  }
  NSUInteger nameStart = pos;
  NSUInteger localStart = pos;
  while (pos < length) {
    unichar c = [xml characterAtIndex:pos];
    if (c == ':') {
      localStart = pos + 1;
    } else if (c == '>' || c == '/' || c == ' ' || c == '\t'
               || c == '\r' || c == '\n') {
      break;
    }
    pos++;
  }
  if (pos >= length || pos == nameStart) {
    return NSNotFound;
  }
  *localName = [xml substringWithRange:NSMakeRange(localStart, pos - localStart)];

  NSRange end = [xml rangeOfString:@">"
                           options:0
                             range:NSMakeRange(pos, length - pos)];
  if (end.location == NSNotFound) {
    return NSNotFound;
  }
  *isSelfClosed = (end.location > 0
                   && [xml characterAtIndex:end.location - 1] == '/');
  return end.location;
}

/* Finds the first element with the given local name at or after start;
   returns the range of its text, or NSNotFound. */
static NSRange elementTextRange(NSString *xml, NSString *localName,
                                NSUInteger start)
{
  NSUInteger length = [xml length];
  NSUInteger pos = start;

  while (pos < length) {
    NSRange open = [xml rangeOfString:@"<"
                              options:0
                                range:NSMakeRange(pos, length - pos)];
    if (open.location == NSNotFound) {
      break;
    }
    NSString *tag = nil;
    BOOL isEnd, isSelfClosed;
    NSUInteger tagEnd = readTag(xml, open.location, &tag, &isEnd, &isSelfClosed);
    if (tagEnd == NSNotFound) {
      break;
    }
    pos = tagEnd + 1;
    if (isEnd || isSelfClosed || ![tag isEqualToString:localName]) {
      continue;
    }

    /* Found the open tag; walk on to its matching close tag. */
    NSUInteger textStart = pos;
    int depth = 1;
    NSUInteger inner = pos;
    while (inner < length) {
      NSRange next = [xml rangeOfString:@"<"
                                options:0
                                  range:NSMakeRange(inner, length - inner)];
      if (next.location == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
      }
      NSString *innerTag = nil;
      BOOL innerEnd, innerSelfClosed;
      NSUInteger innerTagEnd = readTag(xml, next.location, &innerTag,
                                       &innerEnd, &innerSelfClosed);
      if (innerTagEnd == NSNotFound) {
        return NSMakeRange(NSNotFound, 0);
      }
      inner = innerTagEnd + 1;
      if (![innerTag isEqualToString:localName] || innerSelfClosed) {
        continue;
      }
      depth += innerEnd ? -1 : 1;
      if (depth == 0) {
        return NSMakeRange(textStart, next.location - textStart);
      }
    }
    return NSMakeRange(NSNotFound, 0);
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

/* Plain HTTP POST over a socket: the answering host is on the local network,
   and a short hard timeout matters more than redirects or TLS.  Returns the
   response body or nil. */
static NSString *httpPOST(NSString *ipString,
                          int port,
                          NSString *httpPath,
                          NSString *body)
{
#ifdef _WIN32
  return nil;
#else
  struct sockaddr_in addr;
  memset(&addr, 0, sizeof(addr));
  addr.sin_family = AF_INET;
  addr.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, [ipString UTF8String], &addr.sin_addr) != 1) {
    return nil;
  }

  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) {
    return nil;
  }

  /* Connect non-blocking with a hard select timeout: a target that does
     not answer must not block the discovery thread. */
  int flags = fcntl(fd, F_GETFL, 0);
  fcntl(fd, F_SETFL, flags | O_NONBLOCK);
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0
      && errno != EINPROGRESS) {
    close(fd);
    return nil;
  }

  fd_set writeSet;
  FD_ZERO(&writeSet);
  FD_SET(fd, &writeSet);
  struct timeval connectTimeout = { 2, 0 };
  if (select(fd + 1, NULL, &writeSet, NULL, &connectTimeout) <= 0) {
    close(fd);
    return nil;
  }
  int connectError = 0;
  socklen_t errorLength = sizeof(connectError);
  getsockopt(fd, SOL_SOCKET, SO_ERROR, &connectError, &errorLength);
  if (connectError != 0) {
    close(fd);
    return nil;
  }
  fcntl(fd, F_SETFL, flags);

  struct timeval ioTimeout = { 3, 0 };
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &ioTimeout, sizeof(ioTimeout));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &ioTimeout, sizeof(ioTimeout));

  NSData *bodyData = [body dataUsingEncoding:NSUTF8StringEncoding];
  NSString *head = [NSString stringWithFormat:
    @"POST %@ HTTP/1.1\r\n"
    "Host: %@:%d\r\n"
    "Content-Type: application/soap+xml; charset=utf-8\r\n"
    "Content-Length: %lu\r\n"
    "Connection: close\r\n"
    "\r\n",
    httpPath, ipString, port, (unsigned long)[bodyData length]];
  NSMutableData *request = [NSMutableData
      dataWithData:[head dataUsingEncoding:NSUTF8StringEncoding]];
  [request appendData:bodyData];

  const unsigned char *out = [request bytes];
  size_t sent = 0;
  while (sent < [request length]) {
    ssize_t n = send(fd, out + sent, [request length] - sent, 0);
    if (n <= 0) {
      close(fd);
      return nil;
    }
    sent += (size_t)n;
  }

  /* Connection: close, so the end of the response is the end of the stream
     (or the receive timeout, which is why the cap below also bounds it). */
  NSMutableData *response = [NSMutableData data];
  unsigned char buffer[4096];
  while ([response length] < 256 * 1024) {
    ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
    if (n <= 0) {
      break;
    }
    [response appendBytes:buffer length:(NSUInteger)n];
  }
  close(fd);

  NSString *text = [[[NSString alloc] initWithData:response
                                          encoding:NSUTF8StringEncoding]
                     autorelease];
  if (!text || ![text hasPrefix:@"HTTP/1."]) {
    return nil;
  }
  NSRange headerEnd = [text rangeOfString:@"\r\n\r\n"];
  if (headerEnd.location == NSNotFound) {
    return nil;
  }
  NSString *status = [text substringToIndex:
    [text rangeOfString:@"\r\n"].location];
  if ([status rangeOfString:@" 200"].location == NSNotFound) {
    return nil;
  }
  return [text substringFromIndex:NSMaxRange(headerEnd)];
#endif
}

#pragma mark - Probe round

#ifndef _WIN32
static void addComputerMatches(NSArray *matches, NSMutableDictionary *found)
{
  for (NSDictionary *match in matches) {
    NSString *types = [match objectForKey:@"types"];
    if ([types rangeOfString:@"Computer"].location == NSNotFound) {
      continue;
    }
    int port = 5357;
    NSString *xaddrs = [match objectForKey:@"xaddrs"];
    NSString *ip = firstIPv4FromXAddrs(xaddrs, &port);
    if (!ip || [found objectForKey:ip]) {
      continue;
    }

    NSString *xaddrPath = @"/";
    for (NSString *candidate in [xaddrs componentsSeparatedByString:@" "]) {
      NSURL *url = [NSURL URLWithString:candidate];
      if ([[url host] isEqualToString:ip] && [[url path] length] > 0) {
        xaddrPath = [url path];
        break;
      }
    }

    [found setObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
                       ip, @"address",
                       [match objectForKey:@"endpoint"], @"endpoint",
                       [NSNumber numberWithInt:port], @"port",
                       xaddrPath, @"path",
                       nil]
              forKey:ip];
  }
}
#endif

+ (NSArray *)probeComputerDevicesWithTimeout:(NSTimeInterval)seconds
{
#ifdef _WIN32
  return [NSArray array];
#else
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) {
    return [NSArray array];
  }

  /* Windows only answers probes that come from UDP port 3702.  Another
     WS-Discovery client on this machine may own it, hence REUSEADDR and a
     fallback to an ephemeral port (answers from non-Windows targets still
     arrive then). */
  int reuse = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
  struct sockaddr_in local;
  memset(&local, 0, sizeof(local));
  local.sin_family = AF_INET;
  local.sin_addr.s_addr = htonl(INADDR_ANY);
  local.sin_port = htons(WSD_UDP_PORT);
  if (bind(fd, (struct sockaddr *)&local, sizeof(local)) < 0) {
    local.sin_port = 0;
    bind(fd, (struct sockaddr *)&local, sizeof(local));
  }
  unsigned char ttl = 1;
  setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, sizeof(ttl));

  struct sockaddr_in group;
  memset(&group, 0, sizeof(group));
  group.sin_family = AF_INET;
  group.sin_port = htons(WSD_UDP_PORT);
  inet_pton(AF_INET, WSD_UDP_MCAST_V4, &group.sin_addr);

  NSMutableDictionary *found = [NSMutableDictionary dictionary];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
  NSDate *nextProbe = [NSDate date];
  int probesSent = 0;

  while ([deadline timeIntervalSinceNow] > 0) {
    /* UDP is lossy and the targets' replies are staggered by a random delay
       of up to 500 ms (WS-Discovery APP_MAX_DELAY): several spaced probes,
       as wsdd sends them. */
    if (probesSent < 4 && [nextProbe timeIntervalSinceNow] <= 0) {
      NSData *probe = [[self probeXML] dataUsingEncoding:NSUTF8StringEncoding];
      /* A multicast datagram leaves through one interface only; a machine
         with Ethernet and WLAN would otherwise probe just the one the
         routing table prefers. */
      for (NSString *local in [NBNSProbe localIPv4Addresses]) {
        struct in_addr outgoing;
        if (inet_pton(AF_INET, [local UTF8String], &outgoing) != 1) {
          continue;
        }
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &outgoing, sizeof(outgoing));
        sendto(fd, [probe bytes], [probe length], 0,
               (struct sockaddr *)&group, sizeof(group));
      }
      probesSent++;
      nextProbe = [NSDate dateWithTimeIntervalSinceNow:0.3];
    }

    fd_set readSet;
    FD_ZERO(&readSet);
    FD_SET(fd, &readSet);
    struct timeval wait = { 0, 100000 };
    if (select(fd + 1, &readSet, NULL, NULL, &wait) > 0) {
      unsigned char packet[65536];
      ssize_t n = recvfrom(fd, packet, sizeof(packet), 0, NULL, NULL);
      if (n > 0) {
        NSString *xml = [[[NSString alloc] initWithBytes:packet
                                                  length:(NSUInteger)n
                                                encoding:NSUTF8StringEncoding]
                          autorelease];
        addComputerMatches([self parseProbeMatchesXML:xml], found);
      }
    }
  }
  close(fd);

  NSMutableArray *devices = [NSMutableArray array];
  for (NSString *ip in found) {
    NSMutableDictionary *device = [found objectForKey:ip];
    NSString *endpoint = [device objectForKey:@"endpoint"];
    NSString *reply = httpPOST(ip,
                               [[device objectForKey:@"port"] intValue],
                               [device objectForKey:@"path"],
                               [self metadataRequestXMLForEndpoint:endpoint]);
    NSDictionary *host = [self parseMetadataXML:reply];
    if ([host objectForKey:@"name"]) {
      [device setObject:[host objectForKey:@"name"] forKey:@"name"];
    }
    if ([[host objectForKey:@"workgroup"] length] > 0) {
      [device setObject:[host objectForKey:@"workgroup"] forKey:@"workgroup"];
    }
    [device removeObjectForKey:@"port"];
    [device removeObjectForKey:@"path"];
    [devices addObject:device];
  }
  return devices;
#endif
}

@end
