/* fswatcher-test-client.m
 * 
 * Simple test client to verify fswatcher is working
 * without needing to run full Workspace
 */

#import <Foundation/Foundation.h>

@protocol FSWClientProtocol

- (oneway void)watchedPathDidChange:(NSData *)dirinfo;
- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo;

@end

@protocol FSWatcherProtocol

- (oneway void)registerClient:(id <FSWClientProtocol>)client
              isGlobalWatcher:(BOOL)global;

- (oneway void)unregisterClient:(id <FSWClientProtocol>)client;

- (oneway void)client:(id <FSWClientProtocol>)client
                                addWatcherForPath:(NSString *)path;

- (oneway void)client:(id <FSWClientProtocol>)client
                                removeWatcherForPath:(NSString *)path;

@end


@interface FSWatcherTestClient : NSObject <FSWClientProtocol>
{
  id <FSWatcherProtocol> fswatcher;
  NSMutableArray *watchedPaths;
}

- (BOOL)connectToFSWatcher;
- (void)addWatcherForPath:(NSString *)path;
- (void)run;

@end

@implementation FSWatcherTestClient

- (id)init
{
  self = [super init];
  if (self) {
    watchedPaths = [[NSMutableArray alloc] init];
    fswatcher = nil;
  }
  return self;
}

- (void)dealloc
{
  if (fswatcher) {
    [fswatcher unregisterClient: (id <FSWClientProtocol>)self];
    [fswatcher release];
  }
  [watchedPaths release];
  [super dealloc];
}

- (BOOL)connectToFSWatcher
{
  
  fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher"
                                                                 host: @""];
  
  if (fswatcher == nil) {
    return NO;
  }
  
  RETAIN(fswatcher);
  [fswatcher setProtocolForProxy: @protocol(FSWatcherProtocol)];
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(fswatcherConnectionDidDie:)
                                               name: NSConnectionDidDieNotification
                                             object: [fswatcher connectionForProxy]];
  
  [fswatcher registerClient: (id <FSWClientProtocol>)self isGlobalWatcher: NO];
  
  return YES;
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  exit(1);
}

- (void)addWatcherForPath:(NSString *)path
{
  if (fswatcher == nil) {
    return;
  }
  
  [watchedPaths addObject: path];
  [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
}

- (oneway void)watchedPathDidChange:(NSData *)dirinfo
{
  NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
  NSString *event = [info objectForKey: @"event"];
  NSString *path = [info objectForKey: @"path"];
  NSArray *files = [info objectForKey: @"files"];
  
  if (files) {
  }
}

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo
{
}

- (void)run
{
  for (NSString *path in watchedPaths) {
  }
  
  [[NSRunLoop currentRunLoop] run];
}

@end


int main(int argc, const char *argv[])
{
  CREATE_AUTORELEASE_POOL(pool);
  
  
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <path1> [path2] [path3] ...\n", argv[0]);
    fprintf(stderr, "\nExample:\n");
    fprintf(stderr, "  %s /tmp/test\n", argv[0]);
    fprintf(stderr, "  %s $HOME/Desktop /tmp/test\n", argv[0]);
    fprintf(stderr, "\n");
    RELEASE(pool);
    return 1;
  }
  
  FSWatcherTestClient *client = [[FSWatcherTestClient alloc] init];
  
  if (![client connectToFSWatcher]) {
    RELEASE(pool);
    return 1;
  }
  
  // Add watchers for all provided paths
  for (int i = 1; i < argc; i++) {
    NSString *path = [NSString stringWithUTF8String: argv[i]];
    path = [path stringByExpandingTildeInPath];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    if (![fm fileExistsAtPath: path isDirectory: &isDir]) {
      continue;
    }
    
    [client addWatcherForPath: path];
  }
  
  
  [client run];
  
  RELEASE(pool);
  return 0;
}
