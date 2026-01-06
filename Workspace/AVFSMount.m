/* AVFSMount.m
 *
 * Implementation of AVFS virtual filesystem support for Workspace
 */

#import "AVFSMount.h"
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import <unistd.h>
#import <sys/stat.h>

static AVFSMount *sharedInstance = nil;

/* AVFSMountResult implementation */
@implementation AVFSMountResult

@synthesize success;
@synthesize virtualPath;
@synthesize errorMessage;

+ (instancetype)successWithPath:(NSString *)path
{
  AVFSMountResult *result = [[AVFSMountResult alloc] init];
  result.success = YES;
  result.virtualPath = path;
  return [result autorelease];
}

+ (instancetype)failureWithError:(NSString *)error
{
  AVFSMountResult *result = [[AVFSMountResult alloc] init];
  result.success = NO;
  result.errorMessage = error;
  return [result autorelease];
}

- (id)init
{
  self = [super init];
  if (self) {
    success = NO;
    virtualPath = nil;
    errorMessage = nil;
  }
  return self;
}

- (void)dealloc
{
  RELEASE(virtualPath);
  RELEASE(errorMessage);
  [super dealloc];
}

@end


/* AVFSMount implementation */
@implementation AVFSMount

+ (AVFSMount *)sharedInstance
{
  if (sharedInstance == nil) {
    sharedInstance = [[AVFSMount alloc] init];
  }
  return sharedInstance;
}

- (id)init
{
  self = [super init];
  if (self) {
    /* Set default AVFS base path to ~/.avfs */
    NSString *home = NSHomeDirectory();
    avfsBasePath = [[home stringByAppendingPathComponent:@".avfs"] retain];
    avfsDaemonRunning = NO;
  }
  return self;
}

- (void)dealloc
{
  RELEASE(avfsBasePath);
  [super dealloc];
}

- (NSString *)avfsBasePath
{
  return avfsBasePath;
}

#pragma mark - Tool Detection

- (NSString *)findToolInPath:(NSString *)toolName
{
  /* Try using 'which' to find the tool */
  NSTask *whichTask = [[NSTask alloc] init];
  @try {
    [whichTask setLaunchPath:@"/usr/bin/which"];
    [whichTask setArguments:@[toolName]];
    
    NSPipe *outPipe = [NSPipe pipe];
    [whichTask setStandardOutput:outPipe];
    [whichTask setStandardError:[NSPipe pipe]];
    
    [whichTask launch];
    [whichTask waitUntilExit];
    
    if ([whichTask terminationStatus] == 0) {
      NSData *data = [[outPipe fileHandleForReading] availableData];
      NSString *result = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
      result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      [whichTask release];
      
      NSFileManager *fm = [NSFileManager defaultManager];
      if ([result length] > 0 && [fm fileExistsAtPath:result]) {
        return result;
      }
    }
    [whichTask release];
  } @catch (NSException *e) {
    NSLog(@"AVFSMount: Exception searching for %@: %@", toolName, e);
    [whichTask release];
  }
  
  /* Fallback: try standard locations */
  NSArray *searchPaths = @[@"/usr/bin", @"/bin", @"/usr/local/bin", @"/opt/local/bin"];
  NSFileManager *fm = [NSFileManager defaultManager];
  
  for (NSString *path in searchPaths) {
    NSString *toolPath = [path stringByAppendingPathComponent:toolName];
    if ([fm fileExistsAtPath:toolPath]) {
      return toolPath;
    }
  }
  
  return nil;
}

- (BOOL)isAvfsAvailable
{
  return [self findToolInPath:@"avfsd"] != nil;
}

#pragma mark - Daemon Management

- (BOOL)isAvfsDaemonRunning
{
  /* Check if ~/.avfs is mounted by looking at /proc/mounts */
  NSString *procMounts = @"/proc/mounts";
  NSFileManager *fm = [NSFileManager defaultManager];
  
  if (![fm fileExistsAtPath:procMounts]) {
    /* Not on Linux, try checking if the special avfsstat file exists */
    NSString *avfsstatPath = [avfsBasePath stringByAppendingPathComponent:@"#avfsstat/version"];
    return [fm fileExistsAtPath:avfsstatPath];
  }
  
  NSError *readError = nil;
  NSString *mountsContent = [NSString stringWithContentsOfFile:procMounts 
                                                      encoding:NSUTF8StringEncoding 
                                                         error:&readError];
  if (!mountsContent) {
    NSLog(@"AVFSMount: Could not read /proc/mounts: %@", readError);
    return NO;
  }
  
  /* Look for a line containing "avfsd" and our mount path */
  NSArray *lines = [mountsContent componentsSeparatedByString:@"\n"];
  for (NSString *line in lines) {
    if ([line containsString:@"avfsd"] && [line containsString:avfsBasePath]) {
      avfsDaemonRunning = YES;
      return YES;
    }
  }
  
  avfsDaemonRunning = NO;
  return NO;
}

- (BOOL)ensureAvfsDaemonRunning
{
  /* Check if already running */
  if ([self isAvfsDaemonRunning]) {
    NSLog(@"AVFSMount: AVFS daemon already running at %@", avfsBasePath);
    return YES;
  }
  
  /* Check if avfsd is available */
  NSString *avfsdPath = [self findToolInPath:@"avfsd"];
  if (!avfsdPath) {
    NSLog(@"AVFSMount: avfsd not found in PATH");
    return NO;
  }
  
  NSFileManager *fm = [NSFileManager defaultManager];
  
  /* Create the mount point directory if it doesn't exist */
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:avfsBasePath isDirectory:&isDir]) {
    NSError *error = nil;
    if (![fm createDirectoryAtPath:avfsBasePath 
       withIntermediateDirectories:YES 
                        attributes:nil 
                             error:&error]) {
      NSLog(@"AVFSMount: Failed to create AVFS base directory: %@", error);
      return NO;
    }
    NSLog(@"AVFSMount: Created AVFS base directory at %@", avfsBasePath);
  } else if (!isDir) {
    NSLog(@"AVFSMount: %@ exists but is not a directory", avfsBasePath);
    return NO;
  }
  
  /* Start the avfsd daemon */
  NSLog(@"AVFSMount: Starting AVFS daemon at %@", avfsBasePath);
  
  NSTask *avfsTask = [[NSTask alloc] init];
  [avfsTask setLaunchPath:avfsdPath];
  [avfsTask setArguments:@[avfsBasePath]];
  
  NSPipe *errPipe = [NSPipe pipe];
  [avfsTask setStandardOutput:[NSPipe pipe]];
  [avfsTask setStandardError:errPipe];
  
  @try {
    [avfsTask launch];
    
    /* Wait for the daemon to start (check for #avfsstat to appear) */
    int waitCount = 0;
    int maxWait = 50; /* 5 seconds max */
    NSString *avfsstatPath = [avfsBasePath stringByAppendingPathComponent:@"#avfsstat"];
    
    while (waitCount < maxWait) {
      usleep(100000); /* 100ms */
      waitCount++;
      
      if ([fm fileExistsAtPath:avfsstatPath]) {
        NSLog(@"AVFSMount: AVFS daemon started successfully");
        avfsDaemonRunning = YES;
        
        /* Enable symlink rewriting for better compatibility */
        NSString *symlinkRewritePath = [avfsstatPath stringByAppendingPathComponent:@"symlink_rewrite"];
        [@"1" writeToFile:symlinkRewritePath atomically:NO encoding:NSUTF8StringEncoding error:nil];
        
        [avfsTask release];
        return YES;
      }
    }
    
    /* Daemon didn't start in time */
    NSData *errData = [[errPipe fileHandleForReading] availableData];
    NSString *errString = @"";
    if (errData && [errData length] > 0) {
      errString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] autorelease];
    }
    
    NSLog(@"AVFSMount: Failed to start AVFS daemon: %@", errString);
    [avfsTask release];
    return NO;
    
  } @catch (NSException *exception) {
    NSLog(@"AVFSMount: Exception starting daemon: %@", exception);
    [avfsTask release];
    return NO;
  }
}

- (BOOL)stopAvfsDaemon
{
  if (![self isAvfsDaemonRunning]) {
    NSLog(@"AVFSMount: AVFS daemon not running");
    return YES;
  }
  
  /* Try fusermount -u first */
  NSString *fusermountPath = [self findToolInPath:@"fusermount"];
  if (fusermountPath) {
    NSTask *unmountTask = [[NSTask alloc] init];
    [unmountTask setLaunchPath:fusermountPath];
    [unmountTask setArguments:@[@"-u", avfsBasePath]];
    [unmountTask setStandardOutput:[NSPipe pipe]];
    [unmountTask setStandardError:[NSPipe pipe]];
    
    @try {
      [unmountTask launch];
      [unmountTask waitUntilExit];
      
      if ([unmountTask terminationStatus] == 0) {
        NSLog(@"AVFSMount: AVFS daemon stopped successfully");
        avfsDaemonRunning = NO;
        [unmountTask release];
        return YES;
      }
    } @catch (NSException *e) {
      NSLog(@"AVFSMount: Exception stopping daemon: %@", e);
    }
    [unmountTask release];
  }
  
  /* Try umountavfs script as fallback */
  NSString *umountavfsPath = [self findToolInPath:@"umountavfs"];
  if (umountavfsPath) {
    NSTask *unmountTask = [[NSTask alloc] init];
    [unmountTask setLaunchPath:umountavfsPath];
    [unmountTask setStandardOutput:[NSPipe pipe]];
    [unmountTask setStandardError:[NSPipe pipe]];
    
    @try {
      [unmountTask launch];
      [unmountTask waitUntilExit];
      
      if ([unmountTask terminationStatus] == 0) {
        NSLog(@"AVFSMount: AVFS daemon stopped via umountavfs");
        avfsDaemonRunning = NO;
        [unmountTask release];
        return YES;
      }
    } @catch (NSException *e) {
      NSLog(@"AVFSMount: Exception with umountavfs: %@", e);
    }
    [unmountTask release];
  }
  
  NSLog(@"AVFSMount: Failed to stop AVFS daemon");
  return NO;
}

#pragma mark - File Type Detection

- (NSArray *)archiveExtensions
{
  /* Archive formats that contain multiple files */
  return @[
    @"tar",     /* tar archives */
    @"zip",     /* zip archives */
    @"rar",     /* rar archives */
    @"7z",      /* 7-zip archives */
    @"ar",      /* ar archives */
    @"cpio",    /* cpio archives */
    @"lha",     /* lha archives */
    @"lzh",     /* lzh archives (same as lha) */
    @"zoo",     /* zoo archives */
    @"rpm",     /* RPM packages */
    @"deb",     /* Debian packages */
    @"jar",     /* Java archives (zip-based) */
    @"war",     /* Web application archives (zip-based) */
    @"ear",     /* Enterprise archives (zip-based) */
    @"apk",     /* Android packages (zip-based) */
    @"xpi"      /* Firefox extensions (zip-based) */
  ];
}

- (NSArray *)compressionExtensions
{
  /* Single-file compression formats */
  return @[
    @"gz",      /* gzip */
    @"gzip",    /* gzip */
    @"bz2",     /* bzip2 */
    @"bzip2",   /* bzip2 */
    @"xz",      /* xz/lzma */
    @"lzma",    /* lzma */
    @"lz",      /* lzip */
    @"zst",     /* zstd */
    @"zstd",    /* zstd */
    @"Z"        /* compress */
  ];
}

- (NSArray *)compressedArchivePatterns
{
  /* Double extensions for compressed archives */
  return @[
    @"tar.gz",
    @"tar.bz2",
    @"tar.xz",
    @"tar.lzma",
    @"tar.lz",
    @"tar.zst",
    @"tar.Z",
    @"tgz",     /* tar.gz shorthand */
    @"tbz2",    /* tar.bz2 shorthand */
    @"tbz",     /* tar.bz2 shorthand */
    @"txz",     /* tar.xz shorthand */
    @"tlz"      /* tar.lzma shorthand */
  ];
}

- (NSArray *)supportedExtensions
{
  NSMutableArray *all = [NSMutableArray array];
  [all addObjectsFromArray:[self archiveExtensions]];
  [all addObjectsFromArray:[self compressionExtensions]];
  /* Note: We don't add iso9660 here as fuseiso handles ISOs better */
  /* Note: We don't add ssh/sftp as sshfs handles those */
  return all;
}

- (AVFSFileType)fileTypeForExtension:(NSString *)extension
{
  if (!extension || [extension length] == 0) {
    return AVFSFileTypeUnknown;
  }
  
  NSString *ext = [extension lowercaseString];
  
  /* Check for archive types */
  if ([[self archiveExtensions] containsObject:ext]) {
    return AVFSFileTypeArchive;
  }
  
  /* Check for compression types */
  if ([[self compressionExtensions] containsObject:ext]) {
    return AVFSFileTypeCompressed;
  }
  
  /* Note: Disk images (iso, dmg, bin, nrg, img, mdf) are NOT handled by AVFS.
   * They are handled by fuseiso and darling-dmg instead. */
  
  /* Check for patch files */
  if ([ext isEqualToString:@"patch"] || [ext isEqualToString:@"diff"]) {
    return AVFSFileTypePatch;
  }
  
  return AVFSFileTypeUnknown;
}

- (BOOL)isCompressedArchive:(NSString *)path
{
  /* Check if file has a double extension like .tar.gz */
  NSString *filename = [[path lastPathComponent] lowercaseString];
  
  for (NSString *pattern in [self compressedArchivePatterns]) {
    if ([filename hasSuffix:pattern]) {
      return YES;
    }
  }
  
  return NO;
}

- (BOOL)canHandleFile:(NSString *)path
{
  if (!path || [path length] == 0) {
    return NO;
  }
  
  /* Check for compressed archives first (e.g., .tar.gz) */
  if ([self isCompressedArchive:path]) {
    return YES;
  }
  
  /* Check single extension */
  NSString *ext = [[path pathExtension] lowercaseString];
  return [self fileTypeForExtension:ext] != AVFSFileTypeUnknown;
}

#pragma mark - Virtual Path Construction

- (AVFSMountResult *)virtualPathForFile:(NSString *)path
{
  if (!path || [path length] == 0) {
    return [AVFSMountResult failureWithError:@"No file path provided"];
  }
  
  /* Check if file exists */
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm fileExistsAtPath:path]) {
    return [AVFSMountResult failureWithError:
      [NSString stringWithFormat:@"File not found: %@", path]];
  }
  
  /* Check if AVFS is available */
  if (![self isAvfsAvailable]) {
    [self showAvfsNotInstalledAlert];
    return [AVFSMountResult failureWithError:@"AVFS is not installed"];
  }
  
  /* Ensure daemon is running */
  if (![self ensureAvfsDaemonRunning]) {
    return [AVFSMountResult failureWithError:@"Failed to start AVFS daemon"];
  }
  
  /* Convert absolute path to AVFS virtual path
   * For /path/to/file.tar.gz, the AVFS path is:
   * ~/.avfs/path/to/file.tar.gz#
   * 
   * The # suffix tells AVFS to use automatic handler detection based on extension
   */
  
  /* Ensure path is absolute */
  NSString *absolutePath = path;
  if (![path isAbsolutePath]) {
    absolutePath = [[fm currentDirectoryPath] stringByAppendingPathComponent:path];
  }
  absolutePath = [absolutePath stringByStandardizingPath];
  
  /* Construct the AVFS virtual path */
  NSString *virtualPath = [avfsBasePath stringByAppendingPathComponent:absolutePath];
  virtualPath = [virtualPath stringByAppendingString:@"#"];
  
  /* Verify the virtual path is accessible */
  BOOL isDir = NO;
  if ([fm fileExistsAtPath:virtualPath isDirectory:&isDir]) {
    NSLog(@"AVFSMount: Virtual path accessible: %@", virtualPath);
    return [AVFSMountResult successWithPath:virtualPath];
  }
  
  /* If not immediately accessible, give AVFS a moment to process */
  usleep(200000); /* 200ms */
  
  if ([fm fileExistsAtPath:virtualPath isDirectory:&isDir]) {
    NSLog(@"AVFSMount: Virtual path accessible after delay: %@", virtualPath);
    return [AVFSMountResult successWithPath:virtualPath];
  }
  
  /* Try to access it anyway - AVFS may create it on-demand */
  NSError *listError = nil;
  NSArray *contents = [fm contentsOfDirectoryAtPath:virtualPath error:&listError];
  if (contents) {
    NSLog(@"AVFSMount: Virtual path accessible (contents listed): %@", virtualPath);
    return [AVFSMountResult successWithPath:virtualPath];
  }
  
  /* Check if it's a single-file decompression (not an archive) */
  if ([self fileTypeForExtension:[[path pathExtension] lowercaseString]] == AVFSFileTypeCompressed) {
    /* For compressed files like .gz, AVFS may return a single decompressed file */
    NSLog(@"AVFSMount: Compressed file, virtual path: %@", virtualPath);
    return [AVFSMountResult successWithPath:virtualPath];
  }
  
  NSLog(@"AVFSMount: Could not access virtual path: %@, error: %@", virtualPath, listError);
  return [AVFSMountResult failureWithError:
    [NSString stringWithFormat:@"Could not access archive: %@", 
      listError ? [listError localizedDescription] : @"Unknown error"]];
}

#pragma mark - User Interface

- (void)showAvfsNotInstalledAlert
{
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:NSLocalizedString(@"AVFS Not Installed", @"")];
  [alert setInformativeText:NSLocalizedString(
    @"AVFS (A Virtual File System) is required to browse archive contents but is not installed on your system.\n\n"
    @"To install it:\n"
    @"• On Debian/Ubuntu: sudo apt-get install avfs\n"
    @"• On Fedora/RHEL: sudo dnf install avfs\n"
    @"• On Arch: sudo pacman -S avfs\n"
    @"• From source: https://avf.sourceforge.net/", @"")];
  [alert setAlertStyle:NSWarningAlertStyle];
  [alert addButtonWithTitle:NSLocalizedString(@"OK", @"")];
  [alert runModal];
  [alert release];
}

@end
