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
  NSLog(@"Connecting to fswatcher...");
  
  fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher"
                                                                 host: @""];
  
  if (fswatcher == nil) {
    NSLog(@"ERROR: Could not connect to fswatcher!");
    NSLog(@"Make sure fswatcher is running: ps aux | grep fswatcher");
    return NO;
  }
  
  RETAIN(fswatcher);
  [fswatcher setProtocolForProxy: @protocol(FSWatcherProtocol)];
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(fswatcherConnectionDidDie:)
                                               name: NSConnectionDidDieNotification
                                             object: [fswatcher connectionForProxy]];
  
  [fswatcher registerClient: (id <FSWClientProtocol>)self isGlobalWatcher: NO];
  
  NSLog(@"✓ Successfully connected to fswatcher");
  return YES;
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  NSLog(@"ERROR: fswatcher connection died!");
  exit(1);
}

- (void)addWatcherForPath:(NSString *)path
{
  if (fswatcher == nil) {
    NSLog(@"ERROR: Not connected to fswatcher");
    return;
  }
  
  NSLog(@"Adding watcher for path: %@", path);
  [watchedPaths addObject: path];
  [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
  NSLog(@"✓ Watcher added for: %@", path);
}

- (oneway void)watchedPathDidChange:(NSData *)dirinfo
{
  NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
  NSString *event = [info objectForKey: @"event"];
  NSString *path = [info objectForKey: @"path"];
  NSArray *files = [info objectForKey: @"files"];
  
  NSLog(@"");
  NSLog(@"═══════════════════════════════════════");
  NSLog(@"NOTIFICATION RECEIVED!");
  NSLog(@"Event: %@", event);
  NSLog(@"Path:  %@", path);
  if (files) {
    NSLog(@"Files: %@", [files componentsJoinedByString: @", "]);
  }
  NSLog(@"═══════════════════════════════════════");
  NSLog(@"");
}

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo
{
  NSLog(@"Global watcher notification: %@", dirinfo);
}

- (void)run
{
  NSLog(@"");
  NSLog(@"Test client is now listening for filesystem changes...");
  NSLog(@"Watching paths:");
  for (NSString *path in watchedPaths) {
    NSLog(@"  - %@", path);
  }
  NSLog(@"");
  NSLog(@"Make changes to these paths to test!");
  NSLog(@"Press Ctrl+C to exit");
  NSLog(@"");
  
  [[NSRunLoop currentRunLoop] run];
}

@end


int main(int argc, const char *argv[])
{
  CREATE_AUTORELEASE_POOL(pool);
  
  NSLog(@"");
  NSLog(@"╔════════════════════════════════════════════╗");
  NSLog(@"║  FSWatcher Test Client                     ║");
  NSLog(@"╚════════════════════════════════════════════╝");
  NSLog(@"");
  
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
      NSLog(@"WARNING: Path does not exist: %@", path);
      continue;
    }
    
    [client addWatcherForPath: path];
  }
  
  NSLog(@"");
  
  [client run];
  
  RELEASE(pool);
  return 0;
}
