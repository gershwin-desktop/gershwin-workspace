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
  NSDebugLLog(@"gwspace", @"Connecting to fswatcher...");
  
  fswatcher = [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher"
                                                                 host: @""];
  
  if (fswatcher == nil) {
    NSDebugLLog(@"gwspace", @"ERROR: Could not connect to fswatcher!");
    NSDebugLLog(@"gwspace", @"Make sure fswatcher is running: ps aux | grep fswatcher");
    return NO;
  }
  
  RETAIN(fswatcher);
  [fswatcher setProtocolForProxy: @protocol(FSWatcherProtocol)];
  
  [[NSNotificationCenter defaultCenter] addObserver: self
                                           selector: @selector(fswatcherConnectionDidDie:)
                                               name: NSConnectionDidDieNotification
                                             object: [fswatcher connectionForProxy]];
  
  [fswatcher registerClient: (id <FSWClientProtocol>)self isGlobalWatcher: NO];
  
  NSDebugLLog(@"gwspace", @"✓ Successfully connected to fswatcher");
  return YES;
}

- (void)fswatcherConnectionDidDie:(NSNotification *)notif
{
  NSDebugLLog(@"gwspace", @"ERROR: fswatcher connection died!");
  exit(1);
}

- (void)addWatcherForPath:(NSString *)path
{
  if (fswatcher == nil) {
    NSDebugLLog(@"gwspace", @"ERROR: Not connected to fswatcher");
    return;
  }
  
  NSDebugLLog(@"gwspace", @"Adding watcher for path: %@", path);
  [watchedPaths addObject: path];
  [fswatcher client: (id <FSWClientProtocol>)self addWatcherForPath: path];
  NSDebugLLog(@"gwspace", @"✓ Watcher added for: %@", path);
}

- (oneway void)watchedPathDidChange:(NSData *)dirinfo
{
  NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
  NSString *event = [info objectForKey: @"event"];
  NSString *path = [info objectForKey: @"path"];
  NSArray *files = [info objectForKey: @"files"];
  
  NSDebugLLog(@"gwspace", @"");
  NSDebugLLog(@"gwspace", @"═══════════════════════════════════════");
  NSDebugLLog(@"gwspace", @"NOTIFICATION RECEIVED!");
  NSDebugLLog(@"gwspace", @"Event: %@", event);
  NSDebugLLog(@"gwspace", @"Path:  %@", path);
  if (files) {
    NSDebugLLog(@"gwspace", @"Files: %@", [files componentsJoinedByString: @", "]);
  }
  NSDebugLLog(@"gwspace", @"═══════════════════════════════════════");
  NSDebugLLog(@"gwspace", @"");
}

- (oneway void)globalWatchedPathDidChange:(NSDictionary *)dirinfo
{
  NSDebugLLog(@"gwspace", @"Global watcher notification: %@", dirinfo);
}

- (void)run
{
  NSDebugLLog(@"gwspace", @"");
  NSDebugLLog(@"gwspace", @"Test client is now listening for filesystem changes...");
  NSDebugLLog(@"gwspace", @"Watching paths:");
  for (NSString *path in watchedPaths) {
    NSDebugLLog(@"gwspace", @"  - %@", path);
  }
  NSDebugLLog(@"gwspace", @"");
  NSDebugLLog(@"gwspace", @"Make changes to these paths to test!");
  NSDebugLLog(@"gwspace", @"Press Ctrl+C to exit");
  NSDebugLLog(@"gwspace", @"");
  
  [[NSRunLoop currentRunLoop] run];
}

@end


int main(int argc, const char *argv[])
{
  CREATE_AUTORELEASE_POOL(pool);
  
  NSDebugLLog(@"gwspace", @"");
  NSDebugLLog(@"gwspace", @"╔════════════════════════════════════════════╗");
  NSDebugLLog(@"gwspace", @"║  FSWatcher Test Client                     ║");
  NSDebugLLog(@"gwspace", @"╚════════════════════════════════════════════╝");
  NSDebugLLog(@"gwspace", @"");
  
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
      NSDebugLLog(@"gwspace", @"WARNING: Path does not exist: %@", path);
      continue;
    }
    
    [client addWatcherForPath: path];
  }
  
  NSDebugLLog(@"gwspace", @"");
  
  [client run];
  
  RELEASE(pool);
  return 0;
}
