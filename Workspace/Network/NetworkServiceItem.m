/* NetworkServiceItem.m
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import "NetworkServiceItem.h"

@implementation NetworkServiceItem

@synthesize name;
@synthesize type;
@synthesize domain;
@synthesize hostName;
@synthesize port;
@synthesize addresses;
@synthesize netService;
@synthesize resolved;

+ (instancetype)itemWithNetService:(NSNetService *)service
{
  return [[[self alloc] initWithNetService:service] autorelease];
}

- (instancetype)initWithNetService:(NSNetService *)service
{
  self = [super init];
  if (self) {
    self.netService = service;
    self.name = [service name];
    self.type = [service type];
    self.domain = [service domain];
    self.hostName = [service hostName];
    self.port = [service port];
    self.addresses = [service addresses];
    self.resolved = ([service hostName] != nil && [[service hostName] length] > 0);
  }
  return self;
}

- (void)dealloc
{
  [name release];
  [type release];
  [domain release];
  [hostName release];
  [addresses release];
  [netService release];
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  NetworkServiceItem *copy = [[NetworkServiceItem allocWithZone:zone] init];
  copy.name = self.name;
  copy.type = self.type;
  copy.domain = self.domain;
  copy.hostName = self.hostName;
  copy.port = self.port;
  copy.addresses = [[self.addresses copy] autorelease];
  copy.netService = self.netService;
  copy.resolved = self.resolved;
  return copy;
}

- (NSString *)displayName
{
  return name ? name : @"Unknown Service";
}

- (NSString *)identifier
{
  return [NSString stringWithFormat:@"%@.%@.%@", name, type, domain];
}

- (BOOL)isSFTPService
{
  return [type hasPrefix:@"_sftp-ssh."];
}

- (BOOL)isAFPService
{
  return [type hasPrefix:@"_afpovertcp."];
}

- (NSString *)iconName
{
  if ([self isSFTPService]) {
    return @"Network_SFTP";
  } else if ([self isAFPService]) {
    return @"Network_AFP";
  }
  return @"Network_Generic";
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"<NetworkServiceItem: %@ (%@) at %@:%d>", 
          name, type, hostName, port];
}

- (BOOL)isEqual:(id)object
{
  if (![object isKindOfClass:[NetworkServiceItem class]]) {
    return NO;
  }
  NetworkServiceItem *other = (NetworkServiceItem *)object;
  return [[self identifier] isEqual:[other identifier]];
}

- (NSUInteger)hash
{
  return [[self identifier] hash];
}

@end
