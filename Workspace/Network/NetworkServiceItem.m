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
  NSString *base = name ? name : @"Unknown Service";
  if ([self isSFTPService]) {
    return [base stringByAppendingString:@" (sftp)"];
  } else if ([self isAFPService]) {
    return [base stringByAppendingString:@" (afp)"];
  }
  return base;
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
  /* Use the common Network icon for all network services */
  return @"Network";
}

- (NSString *)remotePath
{
  if (!netService) {
    return nil;
  }
  
  /* Get TXT record data from the service */
  NSData *txtData = [netService TXTRecordData];
  if (!txtData || [txtData length] == 0) {
    return nil;
  }
  
  /* Parse TXT record dictionary */
  NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData:txtData];
  if (!txtDict) {
    return nil;
  }
  
  /* Look for 'path' key in TXT record */
  NSData *pathData = [txtDict objectForKey:@"path"];
  if (pathData && [pathData length] > 0) {
    NSString *path = [[[NSString alloc] initWithData:pathData 
                                             encoding:NSUTF8StringEncoding] autorelease];
    if (path && [path length] > 0) {
      NSLog(@"NetworkServiceItem: Found path in TXT record: %@", path);
      return path;
    }
  }
  
  return nil;
}

- (NSString *)username
{
  if (!netService) {
    return nil;
  }
  
  /* Get TXT record data from the service */
  NSData *txtData = [netService TXTRecordData];
  if (!txtData || [txtData length] == 0) {
    return nil;
  }
  
  /* Parse TXT record dictionary */
  NSDictionary *txtDict = [NSNetService dictionaryFromTXTRecordData:txtData];
  if (!txtDict) {
    return nil;
  }
  
  /* Look for username in TXT record - try 'u' key (common for SSH/SFTP) */
  NSData *userData = [txtDict objectForKey:@"u"];
  if (userData && [userData length] > 0) {
    NSString *username = [[[NSString alloc] initWithData:userData 
                                                 encoding:NSUTF8StringEncoding] autorelease];
    if (username && [username length] > 0) {
      NSLog(@"NetworkServiceItem: Found username in TXT record: %@", username);
      return username;
    }
  }
  
  return nil;
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
