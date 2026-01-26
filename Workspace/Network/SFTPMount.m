/*
 * SFTPMount.m
 * 
 * Encapsulates all SFTP mounting functionality
 */

#import "SFTPMount.h"
#import "NetworkServiceItem.h"
#import <GNUstepBase/GNUstep.h>
#include <unistd.h>
#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__) || defined(__APPLE__)
# include <sys/param.h>
# include <sys/mount.h>
#else
# include <sys/statfs.h>
#endif

/* SFTPMountResult implementation */
@implementation SFTPMountResult

@synthesize success;
@synthesize mountPath;
@synthesize errorMessage;
@synthesize pid;

+ (instancetype)successWithPath:(NSString *)path pid:(int)processId
{
  SFTPMountResult *result = [[SFTPMountResult alloc] init];
  result.success = YES;
  result.mountPath = path;
  result.pid = processId;
  return [result autorelease];
}

+ (instancetype)failureWithError:(NSString *)error
{
  SFTPMountResult *result = [[SFTPMountResult alloc] init];
  result.success = NO;
  result.errorMessage = error;
  return [result autorelease];
}

- (id)init
{
  self = [super init];
  if (self) {
    success = NO;
    mountPath = nil;
    errorMessage = nil;
    pid = 0;
  }
  return self;
}

- (void)dealloc
{
  RELEASE(mountPath);
  RELEASE(errorMessage);
  [super dealloc];
}

@end

/* SFTPMount implementation */
@implementation SFTPMount

- (id)init
{
  self = [super init];
  if (self) {
    username = nil;
    password = nil;
    hostname = nil;
    port = 0;
    remotePath = nil;
    mountPoint = nil;
    sshfsTask = nil;
    logHandle = nil;  /* Not owned by us - owned by NSTask */
    sshfsLogPath = nil;
    tempPasswordFile = nil;
  }
  return self;
}

- (void)dealloc
{
  RELEASE(username);
  RELEASE(password);
  RELEASE(hostname);
  RELEASE(remotePath);
  RELEASE(mountPoint);
  RELEASE(sshfsTask);
  /* logHandle is owned by NSTask, do not release it */
  logHandle = nil;
  RELEASE(sshfsLogPath);
  
  /* Clean up temp password file if it exists */
  if (tempPasswordFile) {
    [[NSFileManager defaultManager] removeItemAtPath:tempPasswordFile error:nil];
    RELEASE(tempPasswordFile);
  }
  
  [super dealloc];
}

- (BOOL)isSshfsAvailable
{
  /* Check if sshfs command exists in PATH */
  NSTask *checkTask = [[NSTask alloc] init];
  @try {
    [checkTask setLaunchPath:@"/usr/bin/which"];
    [checkTask setArguments:@[@"sshfs"]];
    [checkTask launch];
    [checkTask waitUntilExit];
    
    if ([checkTask terminationStatus] == 0) {
      NSLog(@"SFTPMount: sshfs is available");
      return YES;
    } else {
      NSLog(@"SFTPMount: sshfs not found in PATH");
      return NO;
    }
  }
  @catch (NSException *exception) {
    NSLog(@"SFTPMount: Error checking for sshfs: %@", exception);
    return NO;
  }
  @finally {
    [checkTask release];
  }
}

- (BOOL)isSshpassAvailable
{
  NSTask *checkTask = [[NSTask alloc] init];
  @try {
    [checkTask setLaunchPath:@"/usr/bin/which"];
    [checkTask setArguments:@[@"sshpass"]];
    [checkTask launch];
    [checkTask waitUntilExit];
    
    BOOL available = ([checkTask terminationStatus] == 0);
    if (available) {
      NSLog(@"SFTPMount: sshpass is available");
    } else {
      NSLog(@"SFTPMount: sshpass not found");
    }
    return available;
  }
  @catch (NSException *exception) {
    NSLog(@"SFTPMount: Error checking for sshpass: %@", exception);
    return NO;
  }
  @finally {
    [checkTask release];
  }
}


- (NSString *)detectHostKeyAlgorithmsForHost:(NSString *)host port:(int)p
{
  if (!host || [host length] == 0) return nil;

  NSString *sshKeyscan = @"/usr/bin/ssh-keyscan";
  NSFileManager *fm = [NSFileManager defaultManager];
  if (![fm isExecutableFileAtPath:sshKeyscan]) {
    NSLog(@"SFTPMount: ssh-keyscan not available at %@, skipping detection", sshKeyscan);
    return nil;
  }

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:sshKeyscan];

  NSMutableArray *args = [NSMutableArray array];
  /* Add timeout to prevent hanging on unreachable hosts */
  [args addObject:@"-T"];
  [args addObject:@"5"];  /* 5 second timeout */
  if (p > 0 && p != 22) {
    [args addObject:@"-p"];
    [args addObject:[NSString stringWithFormat:@"%d", p]];
  }
  /* Ask for a broad set of key types */
  [args addObject:@"-t"];
  [args addObject:@"rsa,dsa,ecdsa,ed25519"]; 
  [args addObject:host];
  [task setArguments:args];

  NSPipe *outPipe = [NSPipe pipe];
  [task setStandardOutput:outPipe];
  [task setStandardError:[NSPipe pipe]];

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
    if (!outData || [outData length] == 0) {
      [task release];
      return nil;
    }

    NSString *outString = [[[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] autorelease];
    NSMutableSet *foundTypes = [NSMutableSet set];
    NSArray *lines = [outString componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line length] == 0) continue;
      NSArray *parts = [line componentsSeparatedByString:@" "];
      if ([parts count] < 2) continue;
      NSString *type = [parts objectAtIndex:1];
      if (type && [type length] > 0) {
        [foundTypes addObject:type];
      }
    }

    if ([foundTypes count] == 0) {
      [task release];
      return nil;
    }

    /* Prefer modern algorithms first when building list */
    NSArray *preferredOrder = @[ @"ssh-ed25519",
                                 @"ecdsa-sha2-nistp521",
                                 @"ecdsa-sha2-nistp384",
                                 @"ecdsa-sha2-nistp256",
                                 @"ssh-rsa",
                                 @"ssh-dss" ];

    NSMutableArray *result = [NSMutableArray array];
    for (NSString *alg in preferredOrder) {
      if ([foundTypes containsObject:alg]) {
        [result addObject:alg];
      }
    }

    /* If none of the preferred names matched (older ssh-keyscan variants), append whatever we found */
    if ([result count] == 0) {
      for (NSString *alg in foundTypes) {
        [result addObject:alg];
      }
    }

    NSString *joined = [result componentsJoinedByString:@","];
    [task release];
    return joined;
  }
  @catch (NSException *e) {
    NSLog(@"SFTPMount: Exception while running ssh-keyscan: %@", e);
    [task release];
    return nil;
  }
}

- (NSString *)improveErrorMessage:(NSString *)rawError 
                        hostname:(NSString *)host 
                        username:(NSString *)user
{
  if (!rawError || [rawError length] == 0) {
    return @"Unknown error occurred during mounting";
  }
  
  NSString *lowerError = [rawError lowercaseString];
  
  /* Authentication errors */
  if ([lowerError containsString:@"permission denied"]) {
    if ([lowerError containsString:@"publickey"]) {
      return [NSString stringWithFormat:
        @"SSH key authentication failed for user '%@' on %@.\n\n"
        @"Make sure:\n"
        @"• Your SSH public key is added to ~/.ssh/authorized_keys on the remote server\n"
        @"• The key permissions are correct (chmod 700 ~/.ssh, chmod 600 authorized_keys)\n"
        @"• SSH agent has your key loaded (ssh-add)", user, host];
    } else {
      return [NSString stringWithFormat:
        @"Password authentication failed for user '%@' on %@.\n\n"
        @"Please verify your username and password are correct.", user, host];
    }
  }
  
  /* Host key errors */
  if ([lowerError containsString:@"host key verification failed"]) {
    return [NSString stringWithFormat:
      @"Host key verification failed for %@.\n\n"
      @"This could be due to:\n"
      @"• First connection to this host (run 'ssh -o StrictHostKeyChecking=accept-new %@@%@' to accept)\n"
      @"• Host key has changed (possible security issue!)\n"
      @"• DNS or IP address mismatch", host, user, host];
  }
  
  if ([lowerError containsString:@"key_type_mismatch"] || 
      [lowerError containsString:@"no matching host key type"]) {
    return [NSString stringWithFormat:
      @"SSH host key algorithm mismatch for %@.\n\n"
      @"The server uses an algorithm your SSH client doesn't support.\n"
      @"This is often because the server uses older RSA keys.\n"
      @"Try updating OpenSSH or configuring supported algorithms in ~/.ssh/config", host];
  }
  
  /* Algorithm/cipher errors */
  if ([lowerError containsString:@"no matching cipher"] ||
      [lowerError containsString:@"no matching key exchange"]) {
    return [NSString stringWithFormat:
      @"SSH cipher/algorithm negotiation failed with %@.\n\n"
      @"The client and server don't support common encryption algorithms.\n"
      @"This often happens with very old or very new servers.\n"
      @"Try adding cipher options to ~/.ssh/config for host %@", host, host];
  }
  
  /* Connection errors */
  if ([lowerError containsString:@"connection refused"] ||
      [lowerError containsString:@"connect_to_host"]) {
    return [NSString stringWithFormat:
      @"Connection refused by %@.\n\n"
      @"Make sure:\n"
      @"• SSH server is running on %@ (default port 22)\n"
      @"• Firewall is not blocking SSH connections\n"
      @"• You have network connectivity to %@", host, host, host];
  }
  
  if ([lowerError containsString:@"name or service not known"] ||
      [lowerError containsString:@"getaddrinfo"] ||
      [lowerError containsString:@"nodename nor servname provided"]) {
    return [NSString stringWithFormat:
      @"Cannot resolve hostname '%@'.\n\n"
      @"Make sure:\n"
      @"• The hostname is spelled correctly\n"
      @"• DNS is working (try 'ping %@')\n"
      @"• Network connectivity is available", host, host];
  }
  
  if ([lowerError containsString:@"timed out"] ||
      [lowerError containsString:@"timeout"]) {
    return [NSString stringWithFormat:
      @"Connection to %@ timed out.\n\n"
      @"Make sure:\n"
      @"• %@ is reachable and online\n"
      @"• No firewall is blocking port 22\n"
      @"• Network connectivity is stable", host, host];
  }
  
  /* Remote filesystem errors */
  if ([lowerError containsString:@"permission denied"] && 
      [lowerError containsString:@"remote"]) {
    return [NSString stringWithFormat:
      @"Permission denied accessing remote path on %@.\n\n"
      @"Make sure user '%@' has read and execute permissions on the remote path.", host, user];
  }
  
  if ([lowerError containsString:@"no such file or directory"]) {
    return [NSString stringWithFormat:
      @"Remote path not found on %@.\n\n"
      @"The path does not exist on the remote server or is not accessible by user '%@'.", host, user];
  }
  
  /* Default: return the original error with some context */
  return [NSString stringWithFormat:
    @"Failed to connect to %@ as user '%@'.\n\n"
    @"SSH error:\n%@", host, user, rawError];
}

- (BOOL)isMountedCorrectly:(NSString *)mpath 
                 toHostname:(NSString *)expectedHostname 
                   username:(NSString *)user
{
  NSFileManager *fm = [NSFileManager defaultManager];
  
  /* Check if mount point exists and is a directory */
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:mpath isDirectory:&isDir] || !isDir) {
    NSLog(@"SFTPMount: Mount point %@ does not exist or is not a directory", mpath);
    return NO;
  }
  
  /* Try to access the mount point - if it's not mounted, this will fail */
  NSError *listError = nil;
  [fm contentsOfDirectoryAtPath:mpath error:&listError];
  if (listError) {
    NSLog(@"SFTPMount: Cannot access mount point %@: %@", mpath, listError);
    return NO;
  }
  
  /* Check /proc/mounts to verify it's actually an sshfs mount */
  NSString *procMounts = @"/proc/mounts";
  NSError *readError = nil;
  NSString *mountsContent = [NSString stringWithContentsOfFile:procMounts 
                                                       encoding:NSUTF8StringEncoding 
                                                          error:&readError];
  if (!mountsContent) {
    NSLog(@"SFTPMount: Could not read /proc/mounts: %@", readError);
    /* If we can access the mount point, assume it's correct even if we can't check /proc/mounts */
    return YES;
  }
  
  /* Look for a line that matches: user@hostname:... on mpath type fuse.sshfs */
  NSArray *lines = [mountsContent componentsSeparatedByString:@"\n"];
  for (NSString *line in lines) {
    if ([line length] == 0) continue;
    
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if ([parts count] < 3) continue;
    
    NSString *source = [parts objectAtIndex:0];  /* e.g., user@hostname:/path */
    NSString *target = [parts objectAtIndex:1];  /* mount point */
    NSString *fstype = [parts objectAtIndex:2];  /* filesystem type */
    
    /* Check if this is the mount point we're looking for */
    if ([target isEqual:mpath]) {
      /* Verify it's an sshfs mount */
      if ([fstype isEqual:@"fuse.sshfs"]) {
        /* Verify the source contains the right hostname and username */
        NSString *expectedSourcePattern = [NSString stringWithFormat:@"%@@%@:", user, expectedHostname];
        if ([source hasPrefix:expectedSourcePattern]) {
          NSLog(@"SFTPMount: Mount point %@ is correctly mounted to %@", mpath, expectedHostname);
          return YES;
        } else {
          NSLog(@"SFTPMount: Mount point %@ is mounted but to different server: %@", mpath, source);
          return NO;
        }
      } else {
        NSLog(@"SFTPMount: Mount point %@ is mounted but not via sshfs (type: %@)", mpath, fstype);
        return NO;
      }
    }
  }
  
  /* Mount point not found in /proc/mounts - it's not actually mounted */
  NSLog(@"SFTPMount: Mount point %@ is not mounted", mpath);
  return NO;
}

- (SFTPMountResult *)mountService:(NetworkServiceItem *)serviceItem
                         username:(NSString *)user
                         password:(NSString *)pass
                        mountPath:(NSString *)mpath
{
  RELEASE(username);
  RELEASE(password);
  RELEASE(hostname);
  RELEASE(remotePath);
  RELEASE(mountPoint);
  RELEASE(sshfsTask);
  /* logHandle is owned by NSTask, we just set it to nil to forget about it */
  logHandle = nil;
  RELEASE(sshfsLogPath);
  RELEASE(tempPasswordFile);
  
  username = [user copy];
  password = [pass copy];
  mountPoint = [mpath copy];
  
  NSFileManager *fm = [NSFileManager defaultManager];
  
  /* Get service details */
  hostname = [[serviceItem hostName] copy];
  port = [serviceItem port];
  remotePath = [[serviceItem remotePath] copy];
  
  if (!hostname) {
    return [SFTPMountResult failureWithError:@"No hostname available"];
  }
  
  /* Check if sshfs is available */
  if (![self isSshfsAvailable]) {
    return [SFTPMountResult failureWithError:@"sshfs is not installed"];
  }
  
  NSLog(@"SFTPMount: Mounting %@:%@ at %@", hostname, remotePath ?: @"~", mountPoint);
  NSLog(@"SFTPMount: Using username: %@, port: %d", username, port);
  
  /* Build sshfs arguments */
  NSMutableArray *args = [NSMutableArray array];
  
  /* Build connection string */
  NSString *connectionHost = [NSString stringWithFormat:@"%@@%@", username, hostname];
  NSString *sshfsSource;
  
  if (remotePath && [remotePath length] > 0) {
    sshfsSource = [NSString stringWithFormat:@"%@:%@", connectionHost, remotePath];
  } else {
    sshfsSource = [NSString stringWithFormat:@"%@:", connectionHost];
  }
  
  [args addObject:sshfsSource];
  [args addObject:mountPoint];
  
  /* Add port if non-standard */
  if (port > 0 && port != 22) {
    [args addObject:@"-p"];
    [args addObject:[NSString stringWithFormat:@"%d", port]];
  }
  
  /* Keep sshfs in foreground mode so NSTask can monitor it */
  [args addObject:@"-f"];
  
  /* Add verbose flags for debugging */
  [args addObject:@"-v"];
  [args addObject:@"-v"];
  [args addObject:@"-v"];
  
  /* Add common sshfs options for better compatibility */
  [args addObject:@"-o"];
  /* Build options string - note: sshfs options differ from ssh options
     - ServerAliveInterval: keep connection alive
     - StrictHostKeyChecking: auto-accept new host keys
     - ConnectTimeout: prevent hanging on unreachable hosts
     - HostKeyAlgorithms: detect server-supported host key algorithms and prefer those
  */
  NSString *detectedAlgs = [self detectHostKeyAlgorithmsForHost:hostname port:port];
  NSString *hostKeyAlgorithmsFragment = nil;
  NSString *pubkeyAcceptedFragment = nil;
  if (detectedAlgs && [detectedAlgs length] > 0) {
    /* Prefer the first detected algorithm to avoid comma-parsing issues with sshfs -o */
    NSArray *parts = [detectedAlgs componentsSeparatedByString:@","];
    NSString *firstAlg = [parts objectAtIndex:0];
    if (!firstAlg || [firstAlg length] == 0) firstAlg = @"ssh-rsa";
    hostKeyAlgorithmsFragment = [NSString stringWithFormat:@"HostKeyAlgorithms=%@", firstAlg];
    pubkeyAcceptedFragment = [NSString stringWithFormat:@"PubkeyAcceptedKeyTypes=+%@", firstAlg];
  } else {
    /* Fallback to a single legacy algorithm */
    hostKeyAlgorithmsFragment = @"HostKeyAlgorithms=ssh-rsa";
    pubkeyAcceptedFragment = @"PubkeyAcceptedKeyTypes=+ssh-rsa";
  }

  /* Build primary options (excluding host key / pubkey options which we pass as separate -o flags) */
  NSString *primaryOptions = @"ServerAliveInterval=15,ServerAliveCountMax=3,StrictHostKeyChecking=no,ConnectTimeout=10";
  [args addObject:primaryOptions];
  /* Add HostKeyAlgorithms and PubkeyAcceptedKeyTypes as separate -o entries to avoid parsing issues */
  [args addObject:@"-o"];
  [args addObject:hostKeyAlgorithmsFragment];
  [args addObject:@"-o"];
  [args addObject:pubkeyAcceptedFragment];
  
  NSLog(@"SFTPMount: sshfs command: sshfs %@", [args componentsJoinedByString:@" "]);
  
  /* Set up task */
  sshfsTask = [[NSTask alloc] init];
  
  /* Create log file for sshfs output */
  NSString *logFileName = [NSString stringWithFormat:@"sshfs_mount_%@.log", 
                                                     [[NSProcessInfo processInfo] globallyUniqueString]];
  sshfsLogPath = [[NSTemporaryDirectory() stringByAppendingPathComponent:logFileName] copy];
  [fm createFileAtPath:sshfsLogPath contents:nil attributes:nil];
  
  logHandle = [NSFileHandle fileHandleForWritingAtPath:sshfsLogPath];
  if (logHandle) {
    /* NSTask will retain the file handle, do not retain it ourselves */
    [sshfsTask setStandardError:logHandle];
    [sshfsTask setStandardOutput:logHandle];
    NSLog(@"SFTPMount: Logging to: %@", sshfsLogPath);
  }
  
  /* Use sshpass if password is provided AND non-empty */
  if (password && [password length] > 0) {
    if (![self isSshpassAvailable]) {
      return [SFTPMountResult failureWithError:@"sshpass is not installed. Cannot use password authentication. Please set up SSH keys instead."];
    }
    
    NSLog(@"SFTPMount: Using sshpass for password authentication");
    
    /* Create temporary password file */
    tempPasswordFile = [[NSTemporaryDirectory() stringByAppendingPathComponent:
                        [[NSProcessInfo processInfo] globallyUniqueString]] copy];
    NSError *writeError = nil;
    [password writeToFile:tempPasswordFile 
               atomically:YES 
                 encoding:NSUTF8StringEncoding 
                    error:&writeError];
    
    if (writeError) {
      NSLog(@"SFTPMount: Failed to write password file: %@", writeError);
      return [SFTPMountResult failureWithError:[NSString stringWithFormat:@"Failed to write password: %@", writeError]];
    }
    
    /* Set permissions on password file */
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
                                     ofItemAtPath:tempPasswordFile
                                            error:nil];
    
    /* Build sshpass command and use /usr/bin/env so sshpass and sshfs are resolved from $PATH */
    [sshfsTask setLaunchPath:@"/usr/bin/env"];
    NSMutableArray *sshpassArgs = [NSMutableArray arrayWithObjects:
                                   @"sshpass", @"-f", tempPasswordFile,
                                   @"sshfs", nil];
    [sshpassArgs addObjectsFromArray:args];
    [sshfsTask setArguments:sshpassArgs];
  } else {
    /* No password - use SSH key authentication */
    NSLog(@"SFTPMount: Using SSH key authentication");
    /* Use /usr/bin/env so sshfs is resolved from $PATH */
    [sshfsTask setLaunchPath:@"/usr/bin/env"];
    NSMutableArray *envArgs = [NSMutableArray arrayWithObject:@"sshfs"];
    [envArgs addObjectsFromArray:args];
    [sshfsTask setArguments:envArgs];
  }
  
  /* Launch and monitor */
  int status = -1;
  NSString *errorString = nil;
  
  NS_DURING
    {
      NSLog(@"SFTPMount: Launching task...");
      
      /* If mount point already has something mounted, unmount it first */
      struct statfs statbuf;
      if (statfs([mountPoint UTF8String], &statbuf) == 0) {
        /* Mount point exists and is accessible - check if something is mounted there */
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *testError = nil;
        /* Try to list - if it works, something might be mounted there */
        [fm contentsOfDirectoryAtPath:mountPoint error:&testError];
        if (!testError) {
          /* Directory is accessible - check /proc/mounts to see if there's a mount */
          NSString *procMounts = @"/proc/mounts";
          NSString *mountsContent = [NSString stringWithContentsOfFile:procMounts 
                                                              encoding:NSUTF8StringEncoding 
                                                                 error:nil];
          if ([mountsContent rangeOfString:mountPoint].location != NSNotFound) {
            NSLog(@"SFTPMount: Mount point %@ is already mounted, attempting to unmount", mountPoint);
            NSTask *umountTask = [[NSTask alloc] init];
            [umountTask setLaunchPath:@"/usr/bin/fusermount"];
            [umountTask setArguments:@[@"-u", mountPoint]];
            @try {
              [umountTask launch];
              [umountTask waitUntilExit];
              if ([umountTask terminationStatus] == 0) {
                NSLog(@"SFTPMount: Successfully unmounted old mount at %@", mountPoint);
              } else {
                NSLog(@"SFTPMount: Failed to unmount old mount at %@", mountPoint);
              }
            } @catch (NSException *e) {
              NSLog(@"SFTPMount: Exception unmounting: %@", e);
            }
            [umountTask release];
            /* Wait a moment for unmount to complete */
            usleep(500000); // 0.5 seconds
          }
        }
      }
      
      [sshfsTask launch];
      int taskPid = [sshfsTask processIdentifier];
      NSLog(@"SFTPMount: Task launched with PID: %d", taskPid);
      
      NSLog(@"SFTPMount: Waiting for mount...");
      
      /* Wait up to 10 seconds for mount to become accessible */
      int maxAttempts = 20;
      int attempt = 0;
      BOOL mounted = NO;
      
      while (attempt < maxAttempts && !mounted) {
        usleep(500000); // 0.5 seconds
        attempt++;
        
        /* Check if process is still running */
        if (![sshfsTask isRunning]) {
          NSLog(@"SFTPMount: Process exited unexpectedly!");
          status = [sshfsTask terminationStatus];
          NSLog(@"SFTPMount: Exit status: %d", status);
          
          /* Close handle to flush output */
          if (logHandle) {
            @try {
              [logHandle closeFile];
            } @catch (NSException *e) {
              NSLog(@"SFTPMount: Exception closing log handle: %@", e);
            }
            logHandle = nil;
          }
          
          /* Read error log */
          NSError *readError = nil;
          errorString = [NSString stringWithContentsOfFile:sshfsLogPath 
                                                  encoding:NSUTF8StringEncoding 
                                                     error:&readError];
          if (!errorString || [errorString length] == 0) {
            errorString = @"sshfs exited unexpectedly with no error output";
          }
          NSLog(@"SFTPMount: Error output:\n%@", errorString);
          break;
        }
        
        /* Try to access mount point */
        NSError *listError = nil;
        [fm contentsOfDirectoryAtPath:mountPoint error:&listError];
        
        if (!listError) {
          NSLog(@"SFTPMount: Mount successful after %d attempts", attempt);
          mounted = YES;
          status = 0;
        } else {
          NSLog(@"SFTPMount: Mount attempt %d/%d - mount not ready", attempt, maxAttempts);
        }
      }
      
      if (!mounted && [sshfsTask isRunning]) {
        NSLog(@"SFTPMount: Mount did not become accessible, but process is running");
        status = 0;
      }
    }
  NS_HANDLER
    {
      NSLog(@"SFTPMount: Exception during launch: %@", localException);
      [fm removeItemAtPath:mountPoint error:nil];
      return [SFTPMountResult failureWithError:[NSString stringWithFormat:@"Failed to launch: %@", 
                                                                           [localException reason]]];
    }
  NS_ENDHANDLER
  
  /* Check result */
  if (status == 0 && [sshfsTask isRunning]) {
    NSLog(@"SFTPMount: Successfully mounted at %@", mountPoint);
    return [SFTPMountResult successWithPath:mountPoint pid:[sshfsTask processIdentifier]];
  } else {
    NSLog(@"SFTPMount: Mount failed - status: %d, running: %d", status, [sshfsTask isRunning]);
    
    if (!errorString) {
      errorString = @"Mount failed - unable to read error details";
    }
    
    /* Terminate sshfs task if it's still running */
    if ([sshfsTask isRunning]) {
      @try {
        [sshfsTask terminate];
        [sshfsTask waitUntilExit];
      } @catch (NSException *e) {
        NSLog(@"SFTPMount: Exception terminating task: %@", e);
      }
    }
    
    /* Cleanup on failure - unmount the mount point */
    NSTask *umountTask = [[NSTask alloc] init];
    [umountTask setLaunchPath:@"/usr/bin/fusermount"];
    [umountTask setArguments:@[@"-u", mountPoint]];
    @try {
      [umountTask launch];
      [umountTask waitUntilExit];
    } @catch (NSException *e) {
      NSLog(@"SFTPMount: Cleanup exception: %@", e);
    }
    [umountTask release];
    
    /* Remove the mount point directory */
    [fm removeItemAtPath:mountPoint error:nil];
    
    /* Make sure we have a valid error string before using it */
    if (!errorString || [errorString length] == 0) {
      errorString = @"Mount failed - sshfs exited without providing error details";
    }
    
    NSString *improvedError = [self improveErrorMessage:errorString 
                                               hostname:hostname 
                                               username:username];
    /* improveErrorMessage returns an autoreleased string, but SFTPMountResult will retain it */
    return [SFTPMountResult failureWithError:improvedError];
  }
}

- (BOOL)unmountPath:(NSString *)path
{
  NSLog(@"SFTPMount: Unmounting %@", path);
  
  NSTask *umountTask = [[NSTask alloc] init];
  @try {
    [umountTask setLaunchPath:@"/usr/bin/fusermount"];
    [umountTask setArguments:@[@"-u", path]];
    [umountTask launch];
    [umountTask waitUntilExit];
    
    if ([umountTask terminationStatus] == 0) {
      NSLog(@"SFTPMount: Successfully unmounted %@", path);
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
      return YES;
    } else {
      NSLog(@"SFTPMount: Unmount failed with status %d", [umountTask terminationStatus]);
      return NO;
    }
  }
  @catch (NSException *exception) {
    NSLog(@"SFTPMount: Unmount exception: %@", exception);
    return NO;
  }
  @finally {
    [umountTask release];
  }
}

@end
