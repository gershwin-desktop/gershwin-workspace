/* NBNSProbe.m
 *
 * Legacy NetBIOS Name Service (UDP 137) and LLMNR (UDP 5355) name queries.
 * The wire formats follow RFC 1002 (NetBIOS) and RFC 4795 (LLMNR).
 *
 * Packet shapes were verified on the wire against a Windows host with
 * tcpdump and compared byte-by-byte with Samba's nmblookup output; see the
 * unit tests in Tests/Network, which parse captured packets.
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "NBNSProbe.h"

#ifndef _WIN32
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <unistd.h>
#import <string.h>
#import <stdlib.h>
#endif
#import <stdlib.h>
#import <time.h>

/* The UDP ports */
#define NBNS_UDP_PORT       137
#define LLMNR_UDP_PORT      5355
#define LLMNR_MCAST_V4      "224.0.0.252"

@implementation NBNSProbe

+ (void)initialize
{
  if (self == [NBNSProbe class]) {
    srand((unsigned int)time(NULL));
  }
}

#pragma mark - RFC 1002 name encoding

+ (NSString *)firstLevelEncodedName:(NSString *)name suffix:(uint8_t)suffix
{
  /* First-level name: 15 name characters plus the suffix byte, each byte
     split into two characters "A" + nibble.  The real maximum NetBIOS name
     is 15 characters in the 16-byte first-level name; the 16th is the
     service type byte. */
  unsigned char firstLevel[16];
  memset(firstLevel, 0, sizeof(firstLevel));

  if ([name isEqualToString:@"*"]) {
    /* Samba encodes the wildcard request name with NUL padding and suffix
       0x00 (verified on the wire: "CK" followed by 15 "AA" pairs). */
    firstLevel[0] = '*';
  } else {
    /* Every other name is uppercased and blank padded (RFC 1002). */
    NSString *upper = [name uppercaseString];
    const char *utf8 = [upper UTF8String];
    size_t len = strlen(utf8);
    if (len > 15) {
      len = 15;
    }
    memcpy(firstLevel, utf8, len);
    memset(firstLevel + len, ' ', 15 - len);
  }
  firstLevel[15] = suffix;

  /* Base-32 style nibble encoding: two printable characters per byte. */
  char encoded[33];
  for (int i = 0; i < 16; i++) {
    encoded[2 * i]     = 'A' + (firstLevel[i] >> 4);
    encoded[2 * i + 1] = 'A' + (firstLevel[i] & 0x0F);
  }
  encoded[32] = '\0';
  return [NSString stringWithUTF8String:encoded];
}

/* Builds a complete name-service question packet: 12-byte header, the
   encoded 32-character name, question type and class 1 (IN). */
+ (NSData *)nmbQuestionPacket:(NSString *)name
                       suffix:(uint8_t)suffix
                        qtype:(uint16_t)qtype
                        flags:(uint16_t)flags
{
  uint16_t txid = (uint16_t)(rand() & 0xFFFF);  /* any opaque value */
  NSMutableData *packet = [NSMutableData dataWithCapacity:64];

  unsigned char header[12];
  header[0] = txid >> 8; header[1] = txid & 0xFF;
  header[2] = flags >> 8; header[3] = flags & 0xFF;
  header[4] = 0; header[5] = 1;   /* QDCOUNT = 1 */
  header[6] = 0; header[7] = 0;   /* ANCOUNT, NSCOUNT, ARCOUNT = 0 */
  header[8] = 0; header[9] = 0;
  header[10] = 0; header[11] = 0;
  [packet appendBytes:header length:12];

  NSString *encoded = [self firstLevelEncodedName:name suffix:suffix];
  unsigned char nameByte = (unsigned char)[encoded length];  /* always 32 */
  [packet appendBytes:&nameByte length:1];
  [packet appendBytes:[encoded UTF8String] length:[encoded length]];
  unsigned char zero = 0;                    /* first-level name terminator */
  [packet appendBytes:&zero length:1];

  unsigned char type[4];
  type[0] = qtype >> 8; type[1] = qtype & 0xFF;
  type[2] = 0; type[3] = 1;                  /* class IN */
  [packet appendBytes:type length:4];

  return packet;
}

#pragma mark - Answer parsing

/* Skips a label sequence; handles the length-prefixed RFC 1035 labels and
   16-bit compression pointers.  Returns the position after the name. */
static size_t skipName(const unsigned char *data, size_t len, size_t pos)
{
  while (pos < len) {
    unsigned char b = data[pos];
    if (b == 0) {
      return pos + 1;
    }
    if ((b & 0xC0) == 0xC0) {
      return pos + 2;
    }
    pos += 1 + b;
  }
  return pos;
}

+ (NSDictionary *)parseNodeStatusData:(NSData *)packetData
{
  if (!packetData) {
    return nil;
  }
  const unsigned char *data = (const unsigned char *)[packetData bytes];
  size_t len = [packetData length];
  if (len < 12 + 33) {
    return nil;
  }

  /* Must be a response to a question (R bit set, OPCODE 0), 1 answer. */
  unsigned int flags = (data[2] << 8) | data[3];
  if ((flags & 0x8000) == 0) {
    return nil;
  }
  unsigned int answers = (data[6] << 8) | data[7];
  if (answers == 0) {
    return nil;
  }

  size_t pos = skipName(data, len, 12);
  if (pos + 10 > len) {
    return nil;
  }
  unsigned int rtype = (data[pos] << 8) | data[pos + 1];
  unsigned int rdlength = (data[pos + 8] << 8) | data[pos + 9];
  pos += 10;

  if (rtype != 0x21 || pos + rdlength > len) {
    return nil;
  }

  /* NBSTAT data: number of names, then 18-byte records
     (15-byte name, 1-byte type, 2-byte flags), then the 6-byte MAC. */
  const unsigned char *r = data + pos;
  unsigned int nameCount = r[0];
  if (1 + nameCount * 18 + 6 > rdlength) {
    return nil;
  }

  NSMutableArray *names = [NSMutableArray array];
  size_t off = 1;
  for (unsigned int i = 0; i < nameCount; i++) {
    const unsigned char *entry = r + off;
    char clean[16];
    memcpy(clean, entry, 15);
    clean[15] = '\0';
    /* Trailing blanks and the padding are not part of the name. */
    for (int c = 14; c >= 0; c--) {
      if (clean[c] == ' ') {
        clean[c] = '\0';
      } else {
        break;
      }
    }
    uint8_t type = entry[15];
    unsigned int entryFlags = (entry[16] << 8) | entry[17];
    BOOL group = (entryFlags & 0x8000) != 0;

    [names addObject:[NSDictionary
        dictionaryWithObjectsAndKeys:
          [NSString stringWithUTF8String:clean], @"name",
          [NSNumber numberWithUnsignedInt:type], @"type",
          [NSNumber numberWithBool:group], @"group",
          nil]];
    off += 18;
  }

  const unsigned char *mac = r + off;
  if (mac[0] == 0 && mac[1] == 0 && mac[2] == 0 && mac[3] == 0
      && mac[4] == 0 && mac[5] == 0) {
    return [NSDictionary dictionaryWithObject:names forKey:@"names"];
  }

  return [NSDictionary
      dictionaryWithObjectsAndKeys:
        names, @"names",
        [NSString stringWithFormat:@"%02x:%02x:%02x:%02x:%02x:%02x",
                                   mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]],
          @"mac",
        nil];
}

/* Parses the resource data of a positive NB (name query) answer: pairs of
   2-byte flags and 4-byte IPv4 addresses. */
static NSMutableArray *parseNBAddresses(const unsigned char *r, unsigned int rdlength)
{
  NSMutableArray *addresses = [NSMutableArray array];
  if (rdlength < 1) {
    return nil;
  }
  unsigned int pairs = r[0];
  for (unsigned int i = 0; i < pairs && (unsigned int)(2 + i * 6 + 6) <= rdlength + 1; i++) {
    /* The address pairs follow the "number of addresses" byte directly. */
    const unsigned char *pair = r + 1 + i * 6;
    char ip[16];
    snprintf(ip, sizeof(ip), "%u.%u.%u.%u",
             (unsigned)pair[2], (unsigned)pair[3],
             (unsigned)pair[4], (unsigned)pair[5]);
    [addresses addObject:[NSString stringWithUTF8String:ip]];
  }
  return addresses;
}

#pragma mark - UDP send/receive

/* Opens a UDP socket with a receive timeout.  Returns -1 on error. */
#ifndef _WIN32

static int openUDPSocket(NSTimeInterval timeout)
{
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) {
    return -1;
  }
  int msec = (int)(timeout * 1000.0);
  if (msec > 0) {
    struct timeval tv;
    tv.tv_sec = msec / 1000;
    tv.tv_usec = (msec % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  }
  return fd;
}

static struct sockaddr_in sockaddrForIP(const char *ip, int port)
{
  struct sockaddr_in sa;
  memset(&sa, 0, sizeof(sa));
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);
  sa.sin_addr.s_addr = inet_addr(ip);
  return sa;
}

/* Sends one packet and collects unicast replies until the deadline passes. */
static void sendUDPAndCollect(int fd,
                              struct sockaddr_in *dst,
                              const void *packet,
                              size_t packetLen,
                              NSTimeInterval timeout,
                              void (^handler)(NSData *reply,
                                              NSString *senderIP))
{
  if (sendto(fd, packet, packetLen, 0, (struct sockaddr *)dst, sizeof(*dst)) < 0) {
    return;
  }

  time_t deadline = time(NULL) + (time_t)timeout + 1;
  while (time(NULL) < deadline) {
    unsigned char buffer[65535];
    struct sockaddr_in from;
    socklen_t fromLen = sizeof(from);
    ssize_t got = recvfrom(fd, buffer, sizeof(buffer), 0,
                           (struct sockaddr *)&from, &fromLen);
    if (got < 0) {
      break;  /* receive timeout (SO_RCVTIMEO) or error */
    }

    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &from.sin_addr, ip, sizeof(ip));
    handler([NSData dataWithBytes:buffer length:(NSUInteger)got],
            [NSString stringWithUTF8String:ip]);
  }
}

#pragma mark - Discovery primitives

+ (NSDictionary *)nodeStatusOfHost:(NSString *)ip
                            timeout:(NSTimeInterval)seconds
{
  if (!ip || [ip length] == 0) {
    return nil;
  }

  const char *ipCString = [ip UTF8String];
  if (inet_addr(ipCString) == INADDR_NONE) {
    return nil;
  }

  /* Node status requests go to the queried host and use a wildcard question
     name "*" with suffix 0x00, exactly like Samba's nmblookup -A.  Windows
     hosts answer regardless of the question name, so we cannot send the
     name to look up here (we don't know it yet). */
  NSData *packet = [self nmbQuestionPacket:@"*"
                                    suffix:0x00
                                     qtype:0x21   /* NBSTAT */
                                     flags:0x0000];

  int fd = openUDPSocket(seconds);
  if (fd < 0) {
    return nil;
  }

  struct sockaddr_in dst = sockaddrForIP(ipCString, NBNS_UDP_PORT);
  __block NSDictionary *result = nil;
  sendUDPAndCollect(fd, &dst, [packet bytes], [packet length], seconds,
                    ^(NSData *reply, NSString *senderIP) {
    if (result == nil && [senderIP isEqualToString:ip]) {
      result = [self parseNodeStatusData:reply];
    }
  });
  close(fd);
  return result;
}

+ (NSArray *)localIPv4Addresses
{
  NSMutableArray *addresses = [NSMutableArray array];
#ifndef _WIN32
  struct ifaddrs *ifaces = NULL;
  if (getifaddrs(&ifaces) < 0) {
    return addresses;
  }
  for (struct ifaddrs *ifa = ifaces; ifa != NULL; ifa = ifa->ifa_next) {
    if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET) {
      continue;
    }
    if (ifa->ifa_flags & IFF_LOOPBACK) {
      continue;
    }
    struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_addr;
    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));
    [addresses addObject:[NSString stringWithUTF8String:ip]];
  }
  freeifaddrs(ifaces);
#endif
  return addresses;
}

+ (BOOL)isLocalIPv4Address:(NSString *)ip
{
  if (!ip) {
    return NO;
  }
  for (NSString *local in [self localIPv4Addresses]) {
    if ([local isEqual:ip]) {
      return YES;
    }
  }
  return NO;
}

/* Collects the IPv4 broadcast addresses of every non-loopback interface. */
static NSArray *broadcastAddresses(void)
{
  NSMutableArray *broadcasts = [NSMutableArray array];
  struct ifaddrs *ifaces = NULL;
  if (getifaddrs(&ifaces) < 0) {
    return broadcasts;
  }
  for (struct ifaddrs *ifa = ifaces; ifa != NULL; ifa = ifa->ifa_next) {
    if (ifa->ifa_addr == NULL || ifa->ifa_addr->sa_family != AF_INET) {
      continue;
    }
    if ((ifa->ifa_flags & IFF_LOOPBACK) || !(ifa->ifa_flags & IFF_BROADCAST)
        || ifa->ifa_dstaddr == NULL) {
      continue;
    }
    struct sockaddr_in *sa = (struct sockaddr_in *)ifa->ifa_dstaddr;
    char ip[INET_ADDRSTRLEN];
    inet_ntop(AF_INET, &sa->sin_addr, ip, sizeof(ip));
    [broadcasts addObject:[NSString stringWithUTF8String:ip]];
  }
  freeifaddrs(ifaces);
  return broadcasts;
}

+ (NSArray *)broadcastQueriedHostsWithTimeout:(NSTimeInterval)seconds
{
  NSMutableArray *hosts = [NSMutableArray array];

  /* A positive wildcard NB query answer contains the addresses the host
     registered the wildcard name under - one answer per host.  The name of
     the host is not in the answer; the caller resolves names afterwards
     with nodeStatusOfHost: (like nmblookup -A). */
  NSData *packet = [self nmbQuestionPacket:@"*"
                                    suffix:0x00
                                     qtype:0x20   /* NB (name query) */
                                     flags:0x0110 /* broadcast + desired */];

  int fd = openUDPSocket(seconds);
  if (fd < 0) {
    return hosts;
  }
  int broadcast = 1;
  setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast));

  for (NSString *broadcastIP in broadcastAddresses()) {
    struct sockaddr_in dst = sockaddrForIP([broadcastIP UTF8String], NBNS_UDP_PORT);
    sendUDPAndCollect(fd, &dst, [packet bytes], [packet length], seconds,
                      ^(NSData *reply, NSString *senderIP) {
      /* Every responder: add its IP (deduplicated below). */
      if (![hosts containsObject:senderIP]) {
        [hosts addObject:senderIP];
      }
    });
  }
  close(fd);
  return hosts;
}

+ (NSArray *)broadcastAddressesForName:(NSString *)name
                                suffix:(uint8_t)suffix
                                timeout:(NSTimeInterval)seconds
{
  NSMutableArray *addresses = [NSMutableArray array];
  if (!name || [name length] == 0) {
    return addresses;
  }

  /* Plain broadcast NB name query: only hosts that registered the exact
     NAME<suffix> answer.  The answer carries their addresses (flags + IPv4
     pairs in the resource data). */
  NSData *packet = [self nmbQuestionPacket:name
                                    suffix:suffix
                                     qtype:0x20
                                     flags:0x0110];

  int fd = openUDPSocket(seconds);
  if (fd < 0) {
    return addresses;
  }
  int broadcast = 1;
  setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast));

  const unsigned char *bytes = (const unsigned char *)[packet bytes];
  size_t packetLen = [packet length];
  for (NSString *broadcastIP in broadcastAddresses()) {
    struct sockaddr_in dst = sockaddrForIP([broadcastIP UTF8String], NBNS_UDP_PORT);
    if (sendto(fd, bytes, packetLen, 0, (struct sockaddr *)&dst, sizeof(dst)) < 0) {
      continue;
    }
  }

  time_t deadline = time(NULL) + (time_t)seconds + 1;
  while (time(NULL) < deadline) {
    unsigned char buffer[65535];
    struct sockaddr_in from;
    socklen_t fromLen = sizeof(from);
    ssize_t got = recvfrom(fd, buffer, sizeof(buffer), 0,
                           (struct sockaddr *)&from, &fromLen);
    if (got < 0) {
      break;
    }

    const unsigned char *data = buffer;
    unsigned int answers = (data[6] << 8) | data[7];
    if (answers == 0) {
      continue;
    }

    size_t pos = skipName(data, (size_t)got, 12);
    if (pos + 10 > (size_t)got) {
      continue;
    }
    unsigned int rtype = (data[pos] << 8) | data[pos + 1];
    unsigned int rdlength = (data[pos + 8] << 8) | data[pos + 9];
    pos += 10;
    if (rtype != 0x20 || pos + rdlength > (size_t)got) {
      continue;
    }

    for (NSString *ip in parseNBAddresses(data + pos, rdlength)) {
      if (![addresses containsObject:ip]) {
        [addresses addObject:ip];
      }
    }
  }
  close(fd);
  return addresses;
}

+ (NSArray *)llmnrAddressesForName:(NSString *)name
                            timeout:(NSTimeInterval)seconds
{
  NSMutableArray *addresses = [NSMutableArray array];
  if (!name || [name length] == 0 || [name rangeOfString:@"."].location
      != NSNotFound) {
    /* LLMNR only resolves single-label names. */
    return addresses;
  }

  /* LLMNR names are single labels encoded in UTF-16LE (RFC 4795, 4.1). */
  NSData *label = [name dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
  NSMutableData *packet = [NSMutableData dataWithCapacity:64];

  /* DNS-style header: query, recursion not desired, one question. */
  unsigned char header[12];
  unsigned int txid = rand() & 0xFFFF;  header[0] = txid >> 8; header[1] = txid & 0xFF;
  header[2] = 0; header[3] = 0;
  header[4] = 0; header[5] = 1;     /* QDCOUNT */
  header[6] = 0; header[7] = 0;     /* ANCOUNT */
  header[8] = 0; header[9] = 0;     /* NSCOUNT */
  header[10] = 0; header[11] = 0;   /* ARCOUNT */
  [packet appendBytes:header length:12];

  unsigned char labelLen = (unsigned char)[label length];
  [packet appendBytes:&labelLen length:1];
  [packet appendData:label];
  unsigned char zero = 0;
  [packet appendBytes:&zero length:1];
  unsigned char type[4] = { 0, 1, 0, 1 };   /* A, class IN */
  [packet appendBytes:type length:4];

  int fd = openUDPSocket(seconds);
  if (fd < 0) {
    return addresses;
  }

  /* The response is unicast back to our source port; responders expect the
     query on the well-known port, so bind 5355 when it is free. */
  {
    struct sockaddr_in local;
    memset(&local, 0, sizeof(local));
    local.sin_family = AF_INET;
    local.sin_port = htons(LLMNR_UDP_PORT);
    if (bind(fd, (struct sockaddr *)&local, sizeof(local)) < 0) {
      /* A busy port (another resolver) does not prevent the query itself. */
    }
  }

  struct sockaddr_in dst = sockaddrForIP(LLMNR_MCAST_V4, LLMNR_UDP_PORT);
  if (sendto(fd, [packet bytes], [packet length], 0,
             (struct sockaddr *)&dst, sizeof(dst)) < 0) {
    close(fd);
    return addresses;
  }

  time_t deadline = time(NULL) + (time_t)seconds + 1;
  while (time(NULL) < deadline && [addresses count] == 0) {
    unsigned char buffer[65535];
    ssize_t got = recvfrom(fd, buffer, sizeof(buffer), 0, NULL, NULL);
    if (got < 0) {
      break;
    }

    const unsigned char *data = buffer;
    unsigned int flags = (data[2] << 8) | data[3];
    unsigned int answers = (data[6] << 8) | data[7];
    if ((flags & 0x8000) == 0 || answers == 0) {
      continue;
    }

    size_t pos = skipName(data, (size_t)got, 12);
    pos += 4;  /* question type + class */
    for (unsigned int i = 0; i < answers && pos + 10 <= (size_t)got; i++) {
      pos = skipName(data, (size_t)got, pos);
      unsigned int rtype = (data[pos] << 8) | data[pos + 1];
      unsigned int rdlength = (data[pos + 8] << 8) | data[pos + 9];
      pos += 10;
      if (pos + rdlength > (size_t)got) {
        break;
      }
      if (rtype == 1 && rdlength == 4) {
        char ip[INET_ADDRSTRLEN];
        snprintf(ip, sizeof(ip), "%u.%u.%u.%u",
                 (unsigned)data[pos], (unsigned)data[pos + 1],
                 (unsigned)data[pos + 2], (unsigned)data[pos + 3]);
        [addresses addObject:[NSString stringWithUTF8String:ip]];
      }
      pos += rdlength;
    }
  }
  close(fd);
  return addresses;
}

#else /* _WIN32 */

/* The probes talk BSD sockets; there is no Winsock implementation, so on
   Windows they find nothing and the Network folder relies on mDNS only. */

+ (NSDictionary *)nodeStatusOfHost:(NSString *)ip
                            timeout:(NSTimeInterval)seconds
{
  return nil;
}

+ (NSArray *)broadcastQueriedHostsWithTimeout:(NSTimeInterval)seconds
{
  return [NSArray array];
}

+ (NSArray *)broadcastAddressesForName:(NSString *)name
                                suffix:(uint8_t)suffix
                                timeout:(NSTimeInterval)seconds
{
  return [NSArray array];
}

+ (NSArray *)llmnrAddressesForName:(NSString *)name
                            timeout:(NSTimeInterval)seconds
{
  return [NSArray array];
}

+ (NSArray *)localIPv4Addresses
{
  return [NSArray array];
}

+ (BOOL)isLocalIPv4Address:(NSString *)ip
{
  return NO;
}

#endif /* _WIN32 */

@end
