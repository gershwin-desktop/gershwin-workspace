/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BootableFileCopier.h"
#import <sys/stat.h>
#import <sys/types.h>
#import <sys/statvfs.h>
#import <sys/sysmacros.h>
#import <unistd.h>
#import <fcntl.h>
#import <errno.h>
#import <dirent.h>
#import <pwd.h>
#import <grp.h>

// Optional ACL and xattr support (Linux-specific)
#ifdef __linux__
  #if __has_include(<sys/xattr.h>)
    #define HAS_XATTR_SUPPORT 1
    #import <sys/xattr.h>
  #endif
  #if __has_include(<sys/acl.h>)
    #define HAS_ACL_SUPPORT 1
    #import <sys/acl.h>
  #endif
#endif

// Buffer size for file copying
#define COPY_BUFFER_SIZE (1024 * 1024)  // 1MB

#pragma mark - BootableCopyResult Implementation

@implementation BootableCopyResult

@synthesize success = _success;
@synthesize errorMessage = _errorMessage;
@synthesize failedPath = _failedPath;
@synthesize bytesCopied = _bytesCopied;
@synthesize filesCopied = _filesCopied;
@synthesize directoriesCopied = _directoriesCopied;
@synthesize symlinksCopied = _symlinksCopied;
@synthesize hardlinksCopied = _hardlinksCopied;
@synthesize specialFilesCopied = _specialFilesCopied;
@synthesize elapsedTime = _elapsedTime;

+ (instancetype)successWithStats:(NSDictionary *)stats
{
  BootableCopyResult *result = [[self alloc] init];
  result.success = YES;
  result.bytesCopied = [stats[@"bytesCopied"] unsignedLongLongValue];
  result.filesCopied = [stats[@"filesCopied"] unsignedLongLongValue];
  result.directoriesCopied = [stats[@"directoriesCopied"] unsignedLongLongValue];
  result.symlinksCopied = [stats[@"symlinksCopied"] unsignedLongLongValue];
  result.hardlinksCopied = [stats[@"hardlinksCopied"] unsignedLongLongValue];
  result.specialFilesCopied = [stats[@"specialFilesCopied"] unsignedLongLongValue];
  result.elapsedTime = [stats[@"elapsedTime"] doubleValue];
  return [result autorelease];
}

+ (instancetype)failureWithError:(NSString *)error path:(NSString *)path
{
  BootableCopyResult *result = [[self alloc] init];
  result.success = NO;
  result.errorMessage = error;
  result.failedPath = path;
  return [result autorelease];
}

- (void)dealloc
{
  [_errorMessage release];
  [_failedPath release];
  [super dealloc];
}

- (NSString *)summaryString
{
  if (!_success) {
    return [NSString stringWithFormat:@"Copy failed: %@ at %@", 
            _errorMessage, _failedPath];
  }
  
  return [NSString stringWithFormat:
    @"Copied: %.2f GB in %ld files, %ld directories, %ld symlinks, "
    @"%ld hardlinks, %ld special files. Time: %.1f seconds",
    _bytesCopied / 1073741824.0,
    (long)_filesCopied, (long)_directoriesCopied, (long)_symlinksCopied,
    (long)_hardlinksCopied, (long)_specialFilesCopied, _elapsedTime];
}

@end


#pragma mark - BootableFileCopier Implementation

@implementation BootableFileCopier

@synthesize delegate = _delegate;
@synthesize options = _options;
@synthesize currentPath = _currentPath;

- (BOOL)isRunning { return _running; }
- (BOOL)isCancelled { return _cancelled; }

#pragma mark - Class Methods

+ (instancetype)systemCopier
{
  return [self copierWithOptions:BootableCopyOptionSystemCopy];
}

+ (instancetype)copierWithOptions:(BootableCopyOptions)options
{
  return [[[self alloc] initWithOptions:options] autorelease];
}

#pragma mark - Initialization

- (instancetype)init
{
  return [self initWithOptions:BootableCopyOptionSystemCopy];
}

- (instancetype)initWithOptions:(BootableCopyOptions)options
{
  self = [super init];
  if (self) {
    _fm = [[NSFileManager defaultManager] retain];
    _options = options;
    _cancelled = NO;
    _running = NO;
    _hardlinkMap = [[NSMutableDictionary alloc] init];
    
    // Default exclusions - virtual/runtime directories
    _excludedPaths = [[NSSet setWithArray:@[
      @"/proc", @"/sys", @"/dev", @"/run", @"/tmp",
      @"/var/run", @"/var/lock", @"/var/tmp",
      @"/mnt", @"/media", @"/lost+found"
    ]] retain];
    
    _excludedPrefixes = [[NSSet setWithArray:@[
      @"/proc/", @"/sys/", @"/dev/", @"/run/", @"/tmp/",
      @"/var/run/", @"/var/lock/", @"/var/tmp/",
      @"/mnt/", @"/media/"
    ]] retain];
  }
  return self;
}

- (void)dealloc
{
  [_fm release];
  [_hardlinkMap release];
  [_excludedPaths release];
  [_excludedPrefixes release];
  [_currentPath release];
  [_startTime release];
  [super dealloc];
}

#pragma mark - Configuration

- (void)addExcludedPath:(NSString *)path
{
  NSMutableSet *newSet = [NSMutableSet setWithSet:_excludedPaths];
  [newSet addObject:path];
  [_excludedPaths release];
  _excludedPaths = [newSet copy];
}

- (void)addExcludedPrefix:(NSString *)prefix
{
  NSMutableSet *newSet = [NSMutableSet setWithSet:_excludedPrefixes];
  [newSet addObject:prefix];
  [_excludedPrefixes release];
  _excludedPrefixes = [newSet copy];
}

- (void)clearCustomExclusions
{
  [_excludedPaths release];
  _excludedPaths = [[NSSet setWithArray:@[
    @"/proc", @"/sys", @"/dev", @"/run", @"/tmp",
    @"/var/run", @"/var/lock", @"/var/tmp",
    @"/mnt", @"/media", @"/lost+found"
  ]] retain];
  
  [_excludedPrefixes release];
  _excludedPrefixes = [[NSSet setWithArray:@[
    @"/proc/", @"/sys/", @"/dev/", @"/run/", @"/tmp/",
    @"/var/run/", @"/var/lock/", @"/var/tmp/",
    @"/mnt/", @"/media/"
  ]] retain];
}

- (NSArray *)excludedPaths
{
  return [_excludedPaths allObjects];
}

- (BOOL)isExcludedPath:(NSString *)path
{
  // Check exact matches
  if ([_excludedPaths containsObject:path]) {
    return YES;
  }
  
  // Check prefixes
  for (NSString *prefix in _excludedPrefixes) {
    if ([path hasPrefix:prefix]) {
      return YES;
    }
  }
  
  return NO;
}

#pragma mark - Pre-copy Analysis

- (NSDictionary *)calculateSizeForSource:(NSString *)sourcePath
                            excludeHome:(BOOL)excludeHome
{
  unsigned long long totalBytes = 0;
  unsigned long long totalFiles = 0;
  
  // Use du command for efficiency
  NSMutableArray *args = [NSMutableArray arrayWithObjects:
    @"-sb", sourcePath, nil];
  
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  
  @try {
    [task setLaunchPath:@"/usr/bin/du"];
    [task setArguments:args];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data 
                                             encoding:NSUTF8StringEncoding];
    
    // Parse first number from output
    NSScanner *scanner = [NSScanner scannerWithString:output];
    long long bytes = 0;
    if ([scanner scanLongLong:&bytes]) {
      totalBytes = bytes;
    }
    [output release];
  } @catch (NSException *e) {
    // Fallback to manual counting
  }
  [task release];
  
  // Count files
  task = [[NSTask alloc] init];
  pipe = [NSPipe pipe];
  
  @try {
    [task setLaunchPath:@"/usr/bin/find"];
    [task setArguments:@[sourcePath, @"-type", @"f", @"-o", @"-type", @"l"]];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data 
                                             encoding:NSUTF8StringEncoding];
    totalFiles = [[output componentsSeparatedByString:@"\n"] count] - 1;
    [output release];
  } @catch (NSException *e) {
    // Fallback
  }
  [task release];
  
  // Subtract /home if excluded
  if (excludeHome) {
    NSString *homePath = [sourcePath stringByAppendingPathComponent:@"home"];
    NSDictionary *homeStats = [self calculateSizeForSource:homePath 
                                              excludeHome:NO];
    totalBytes -= [homeStats[@"totalBytes"] unsignedLongLongValue];
    totalFiles -= [homeStats[@"totalFiles"] unsignedLongLongValue];
  }
  
  return @{
    @"totalBytes": @(totalBytes),
    @"totalFiles": @(totalFiles)
  };
}

- (BOOL)sourceSupportsFullCopy:(NSString *)sourcePath 
                        reason:(NSString **)reason
{
  // Check filesystem capabilities
  struct statvfs stat;
  if (statvfs([sourcePath fileSystemRepresentation], &stat) != 0) {
    if (reason) *reason = @"Cannot stat source filesystem";
    return NO;
  }
  
  return YES;
}

- (BOOL)targetSupportsFullCopy:(NSString *)targetPath 
                        reason:(NSString **)reason
{
  struct statvfs stat;
  if (statvfs([targetPath fileSystemRepresentation], &stat) != 0) {
    if (reason) *reason = @"Cannot stat target filesystem";
    return NO;
  }
  
  // Check if target is read-only
  if (stat.f_flag & ST_RDONLY) {
    if (reason) *reason = @"Target filesystem is read-only";
    return NO;
  }
  
  return YES;
}

#pragma mark - Main Copy Operation

- (BootableCopyResult *)copyRootFilesystem:(NSString *)sourcePath
                                  toTarget:(NSString *)targetPath
                             excludingHome:(BOOL)excludeHome
{
  if (_running) {
    return [BootableCopyResult failureWithError:@"Copy already in progress" 
                                           path:nil];
  }
  
  _running = YES;
  _cancelled = NO;
  [_startTime release];
  _startTime = [[NSDate date] retain];
  
  // Reset statistics
  _bytesTotal = 0;
  _bytesCopied = 0;
  _filesTotal = 0;
  _filesCopied = 0;
  _directoriesCopied = 0;
  _symlinksCopied = 0;
  _hardlinksCopied = 0;
  _specialFilesCopied = 0;
  [_hardlinkMap removeAllObjects];
  
  // Add /home to exclusions if requested
  if (excludeHome) {
    [self addExcludedPath:@"/home"];
    [self addExcludedPrefix:@"/home/"];
  }
  
  // Calculate totals for progress
  NSDictionary *sizeInfo = [self calculateSizeForSource:sourcePath 
                                           excludeHome:excludeHome];
  _bytesTotal = [sizeInfo[@"totalBytes"] unsignedLongLongValue];
  _filesTotal = [sizeInfo[@"totalFiles"] unsignedLongLongValue];
  
  // Create target directory structure
  NSError *error = nil;
  if (![self createBootableLayoutAtPath:targetPath error:&error]) {
    _running = NO;
    return [BootableCopyResult failureWithError:[error localizedDescription] 
                                           path:targetPath];
  }
  
  // Start recursive copy
  if (![self copyDirectory:sourcePath toPath:targetPath error:&error]) {
    _running = NO;
    if (_cancelled) {
      return [BootableCopyResult failureWithError:@"Copy was cancelled" 
                                             path:_currentPath];
    }
    return [BootableCopyResult failureWithError:[error localizedDescription] 
                                           path:_currentPath];
  }
  
  // Create virtual directories (proc, sys, dev, etc.)
  if (![self createVirtualDirectoriesAtPath:targetPath error:&error]) {
    _running = NO;
    return [BootableCopyResult failureWithError:[error localizedDescription] 
                                           path:targetPath];
  }
  
  // Fix permissions on critical directories
  if (![self fixCriticalPermissionsAtPath:targetPath error:&error]) {
    _running = NO;
    return [BootableCopyResult failureWithError:[error localizedDescription] 
                                           path:targetPath];
  }
  
  _running = NO;
  
  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startTime];
  
  NSDictionary *stats = @{
    @"bytesCopied": @(_bytesCopied),
    @"filesCopied": @(_filesCopied),
    @"directoriesCopied": @(_directoriesCopied),
    @"symlinksCopied": @(_symlinksCopied),
    @"hardlinksCopied": @(_hardlinksCopied),
    @"specialFilesCopied": @(_specialFilesCopied),
    @"elapsedTime": @(elapsed)
  };
  
  return [BootableCopyResult successWithStats:stats];
}

#pragma mark - File Copy Operations

- (BOOL)copyFile:(NSString *)sourcePath 
          toPath:(NSString *)destPath
           error:(NSError **)error
{
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot stat %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Check for hardlink
  if (srcStat.st_nlink > 1 && (_options & BootableCopyOptionPreserveHardlinks)) {
    NSNumber *inodeKey = @(srcStat.st_ino);
    NSString *existingPath = _hardlinkMap[inodeKey];
    
    if (existingPath) {
      // Create hardlink to existing copy
      if (link([existingPath fileSystemRepresentation], 
               [destPath fileSystemRepresentation]) == 0) {
        _hardlinksCopied++;
        return YES;
      }
      // Fall through to regular copy if hardlink fails
    } else {
      // Record this inode for future hardlinks
      _hardlinkMap[inodeKey] = destPath;
    }
  }
  
  // Open source file
  int srcFd = open([sourcePath fileSystemRepresentation], O_RDONLY);
  if (srcFd < 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot open %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Create destination file
  int dstFd = open([destPath fileSystemRepresentation], 
                   O_WRONLY | O_CREAT | O_TRUNC, srcStat.st_mode);
  if (dstFd < 0) {
    close(srcFd);
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot create %@: %s", 
                                  destPath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Copy data
  char *buffer = malloc(COPY_BUFFER_SIZE);
  ssize_t bytesRead;
  BOOL success = YES;
  
  while ((bytesRead = read(srcFd, buffer, COPY_BUFFER_SIZE)) > 0) {
    if (_cancelled) {
      success = NO;
      break;
    }
    
    ssize_t bytesWritten = write(dstFd, buffer, bytesRead);
    if (bytesWritten != bytesRead) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   [NSString stringWithFormat:@"Write error on %@: %s", 
                                    destPath, strerror(errno)]}];
      }
      success = NO;
      break;
    }
    
    _bytesCopied += bytesWritten;
    
    // Update progress periodically
    if (_delegate && (_bytesCopied % (10 * COPY_BUFFER_SIZE) == 0)) {
      [_delegate copier:self 
            didProgress:_bytesCopied 
                ofTotal:_bytesTotal 
                  files:_filesCopied 
             totalFiles:_filesTotal];
    }
  }
  
  if (bytesRead < 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Read error on %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    success = NO;
  }
  
  free(buffer);
  close(srcFd);
  close(dstFd);
  
  if (!success) {
    unlink([destPath fileSystemRepresentation]);
    return NO;
  }
  
  // Copy attributes
  if (_options & BootableCopyOptionPreservePermissions) {
    [self copyPermissions:sourcePath toPath:destPath error:nil];
  }
  if (_options & BootableCopyOptionPreserveOwnership) {
    [self copyOwnership:sourcePath toPath:destPath error:nil];
  }
  if (_options & BootableCopyOptionPreserveTimestamps) {
    [self copyTimestamps:sourcePath toPath:destPath error:nil];
  }
  if (_options & BootableCopyOptionPreserveXattrs) {
    [self copyXattrs:sourcePath toPath:destPath error:nil];
  }
  if (_options & BootableCopyOptionPreserveACLs) {
    [self copyACLs:sourcePath toPath:destPath error:nil];
  }
  
  _filesCopied++;
  return YES;
}

- (BOOL)copyDirectory:(NSString *)sourcePath 
               toPath:(NSString *)destPath
                error:(NSError **)error
{
  if (_cancelled) {
    return NO;
  }
  
  // Check if excluded
  if ([self isExcludedPath:sourcePath]) {
    return YES;
  }
  
  [_currentPath release];
  _currentPath = [sourcePath retain];
  
  if (_delegate && [_delegate respondsToSelector:@selector(copier:willCopyPath:)]) {
    [_delegate copier:self willCopyPath:sourcePath];
  }
  
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot stat %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Create destination directory if needed
  BOOL isDir = NO;
  if (![_fm fileExistsAtPath:destPath isDirectory:&isDir]) {
    if (mkdir([destPath fileSystemRepresentation], srcStat.st_mode) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   [NSString stringWithFormat:@"Cannot create directory %@: %s", 
                                    destPath, strerror(errno)]}];
      }
      return NO;
    }
    _directoriesCopied++;
  }
  
  // Read directory contents
  DIR *dir = opendir([sourcePath fileSystemRepresentation]);
  if (!dir) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot open directory %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  struct dirent *entry;
  BOOL success = YES;
  
  while ((entry = readdir(dir)) != NULL) {
    if (_cancelled) {
      success = NO;
      break;
    }
    
    NSString *name = [NSString stringWithUTF8String:entry->d_name];
    
    // Skip . and ..
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) {
      continue;
    }
    
    NSString *srcChild = [sourcePath stringByAppendingPathComponent:name];
    NSString *dstChild = [destPath stringByAppendingPathComponent:name];
    
    // Check if excluded
    if ([self isExcludedPath:srcChild]) {
      continue;
    }
    
    struct stat childStat;
    if (lstat([srcChild fileSystemRepresentation], &childStat) != 0) {
      continue;  // Skip files we can't stat
    }
    
    // Handle different file types
    if (S_ISDIR(childStat.st_mode)) {
      // Recursively copy directory
      if (![self copyDirectory:srcChild toPath:dstChild error:error]) {
        // Check if we should continue after error
        if (_delegate && 
            [_delegate respondsToSelector:@selector(copier:shouldContinueAfterError:atPath:)]) {
          NSString *errMsg = error ? [*error localizedDescription] : @"Unknown error";
          if (![_delegate copier:self shouldContinueAfterError:errMsg atPath:srcChild]) {
            success = NO;
            break;
          }
        } else {
          success = NO;
          break;
        }
      }
    } else if (S_ISLNK(childStat.st_mode)) {
      // Copy symlink
      if (![self copySymlink:srcChild toPath:dstChild error:error]) {
        if (_delegate && 
            [_delegate respondsToSelector:@selector(copier:shouldContinueAfterError:atPath:)]) {
          NSString *errMsg = error ? [*error localizedDescription] : @"Unknown error";
          if (![_delegate copier:self shouldContinueAfterError:errMsg atPath:srcChild]) {
            success = NO;
            break;
          }
        }
      }
    } else if (S_ISREG(childStat.st_mode)) {
      // Copy regular file
      if (![self copyFile:srcChild toPath:dstChild error:error]) {
        if (_delegate && 
            [_delegate respondsToSelector:@selector(copier:shouldContinueAfterError:atPath:)]) {
          NSString *errMsg = error ? [*error localizedDescription] : @"Unknown error";
          if (![_delegate copier:self shouldContinueAfterError:errMsg atPath:srcChild]) {
            success = NO;
            break;
          }
        }
      }
    } else if (S_ISBLK(childStat.st_mode) || S_ISCHR(childStat.st_mode) ||
               S_ISFIFO(childStat.st_mode) || S_ISSOCK(childStat.st_mode)) {
      // Copy special file
      if (![self copySpecialFile:srcChild toPath:dstChild error:error]) {
        // Non-fatal for special files
      }
    }
  }
  
  closedir(dir);
  
  // Copy directory attributes after contents
  if (success) {
    if (_options & BootableCopyOptionPreservePermissions) {
      [self copyPermissions:sourcePath toPath:destPath error:nil];
    }
    if (_options & BootableCopyOptionPreserveOwnership) {
      [self copyOwnership:sourcePath toPath:destPath error:nil];
    }
    if (_options & BootableCopyOptionPreserveTimestamps) {
      [self copyTimestamps:sourcePath toPath:destPath error:nil];
    }
    if (_options & BootableCopyOptionPreserveXattrs) {
      [self copyXattrs:sourcePath toPath:destPath error:nil];
    }
    if (_options & BootableCopyOptionPreserveACLs) {
      [self copyACLs:sourcePath toPath:destPath error:nil];
    }
    
    if (_delegate && [_delegate respondsToSelector:@selector(copier:didCopyPath:)]) {
      [_delegate copier:self didCopyPath:sourcePath];
    }
  }
  
  return success;
}

- (BOOL)copySymlink:(NSString *)sourcePath 
             toPath:(NSString *)destPath
              error:(NSError **)error
{
  char linkTarget[PATH_MAX];
  ssize_t len = readlink([sourcePath fileSystemRepresentation], 
                         linkTarget, sizeof(linkTarget) - 1);
  
  if (len < 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot read symlink %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  linkTarget[len] = '\0';
  
  // Remove existing symlink if present
  unlink([destPath fileSystemRepresentation]);
  
  if (symlink(linkTarget, [destPath fileSystemRepresentation]) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot create symlink %@: %s", 
                                  destPath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Copy ownership (lchown)
  if (_options & BootableCopyOptionPreserveOwnership) {
    struct stat srcStat;
    if (lstat([sourcePath fileSystemRepresentation], &srcStat) == 0) {
      lchown([destPath fileSystemRepresentation], srcStat.st_uid, srcStat.st_gid);
    }
  }
  
  _symlinksCopied++;
  return YES;
}

- (BOOL)copySpecialFile:(NSString *)sourcePath 
                 toPath:(NSString *)destPath
                  error:(NSError **)error
{
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:@{NSLocalizedDescriptionKey: 
                                 [NSString stringWithFormat:@"Cannot stat %@: %s", 
                                  sourcePath, strerror(errno)]}];
    }
    return NO;
  }
  
  // Create device node, FIFO, or socket
  if (S_ISBLK(srcStat.st_mode) || S_ISCHR(srcStat.st_mode)) {
    // Device node - needs root
    if (mknod([destPath fileSystemRepresentation], 
              srcStat.st_mode, srcStat.st_rdev) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   [NSString stringWithFormat:@"Cannot create device node %@: %s", 
                                    destPath, strerror(errno)]}];
      }
      return NO;
    }
  } else if (S_ISFIFO(srcStat.st_mode)) {
    // FIFO
    if (mkfifo([destPath fileSystemRepresentation], srcStat.st_mode) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:@{NSLocalizedDescriptionKey: 
                                   [NSString stringWithFormat:@"Cannot create FIFO %@: %s", 
                                    destPath, strerror(errno)]}];
      }
      return NO;
    }
  } else if (S_ISSOCK(srcStat.st_mode)) {
    // Socket - skip, can't be copied
    return YES;
  }
  
  // Copy ownership
  if (_options & BootableCopyOptionPreserveOwnership) {
    chown([destPath fileSystemRepresentation], srcStat.st_uid, srcStat.st_gid);
  }
  
  _specialFilesCopied++;
  return YES;
}

#pragma mark - Attribute Preservation

- (BOOL)copyPermissions:(NSString *)sourcePath
                 toPath:(NSString *)destPath
                  error:(NSError **)error
{
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    return NO;
  }
  
  // Don't follow symlinks
  if (S_ISLNK(srcStat.st_mode)) {
    return YES;  // Can't chmod symlinks
  }
  
  if (chmod([destPath fileSystemRepresentation], srcStat.st_mode) != 0) {
    if (error) {
      *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                   code:errno 
                               userInfo:nil];
    }
    return NO;
  }
  
  return YES;
}

- (BOOL)copyOwnership:(NSString *)sourcePath
               toPath:(NSString *)destPath
                error:(NSError **)error
{
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    return NO;
  }
  
  // Use lchown for symlinks
  if (S_ISLNK(srcStat.st_mode)) {
    if (lchown([destPath fileSystemRepresentation], 
               srcStat.st_uid, srcStat.st_gid) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:nil];
      }
      return NO;
    }
  } else {
    if (chown([destPath fileSystemRepresentation], 
              srcStat.st_uid, srcStat.st_gid) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:nil];
      }
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)copyTimestamps:(NSString *)sourcePath
                toPath:(NSString *)destPath
                 error:(NSError **)error
{
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) != 0) {
    return NO;
  }
  
  struct timeval times[2];
  times[0].tv_sec = srcStat.st_atime;
  times[0].tv_usec = 0;
  times[1].tv_sec = srcStat.st_mtime;
  times[1].tv_usec = 0;
  
  // Note: lutimes would be better for symlinks but not always available
  if (!S_ISLNK(srcStat.st_mode)) {
    if (utimes([destPath fileSystemRepresentation], times) != 0) {
      if (error) {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                     code:errno 
                                 userInfo:nil];
      }
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)copyACLs:(NSString *)sourcePath
          toPath:(NSString *)destPath
           error:(NSError **)error
{
#ifdef HAS_ACL_SUPPORT
  // Linux ACL support via libacl
  acl_t acl = acl_get_file([sourcePath fileSystemRepresentation], ACL_TYPE_ACCESS);
  if (acl) {
    acl_set_file([destPath fileSystemRepresentation], ACL_TYPE_ACCESS, acl);
    acl_free(acl);
  }
  
  // Also copy default ACL for directories
  struct stat srcStat;
  if (lstat([sourcePath fileSystemRepresentation], &srcStat) == 0 &&
      S_ISDIR(srcStat.st_mode)) {
    acl = acl_get_file([sourcePath fileSystemRepresentation], ACL_TYPE_DEFAULT);
    if (acl) {
      acl_set_file([destPath fileSystemRepresentation], ACL_TYPE_DEFAULT, acl);
      acl_free(acl);
    }
  }
#endif
  
  return YES;
}

- (BOOL)copyXattrs:(NSString *)sourcePath
            toPath:(NSString *)destPath
             error:(NSError **)error
{
#ifdef HAS_XATTR_SUPPORT
  const char *srcPath = [sourcePath fileSystemRepresentation];
  const char *dstPath = [destPath fileSystemRepresentation];
  
  // Get list of xattrs
  ssize_t listSize = listxattr(srcPath, NULL, 0);
  if (listSize <= 0) {
    return YES;  // No xattrs
  }
  
  char *list = malloc(listSize);
  listSize = listxattr(srcPath, list, listSize);
  if (listSize < 0) {
    free(list);
    return NO;
  }
  
  // Copy each xattr
  char *name = list;
  while (name < list + listSize) {
    ssize_t valueSize = getxattr(srcPath, name, NULL, 0);
    if (valueSize > 0) {
      char *value = malloc(valueSize);
      if (getxattr(srcPath, name, value, valueSize) > 0) {
        setxattr(dstPath, name, value, valueSize, 0);
      }
      free(value);
    }
    name += strlen(name) + 1;
  }
  
  free(list);
#endif
  return YES;
}

#pragma mark - Verification

- (BOOL)verifyTarget:(NSString *)targetPath
          withSource:(NSString *)sourcePath
              reason:(NSString **)reason
{
  // Full verification with checksums would be slow
  // Do quick verification for now
  return [self quickVerifyTarget:targetPath withSource:sourcePath reason:reason];
}

- (BOOL)quickVerifyTarget:(NSString *)targetPath
               withSource:(NSString *)sourcePath
                   reason:(NSString **)reason
{
  // Check that key directories exist
  NSArray *requiredDirs = @[
    @"bin", @"etc", @"lib", @"sbin", @"usr", @"var"
  ];
  
  for (NSString *dir in requiredDirs) {
    NSString *path = [targetPath stringByAppendingPathComponent:dir];
    BOOL isDir = NO;
    if (![_fm fileExistsAtPath:path isDirectory:&isDir] || !isDir) {
      if (reason) {
        *reason = [NSString stringWithFormat:@"Required directory missing: %@", dir];
      }
      return NO;
    }
  }
  
  // Check that /etc/fstab exists or will be created
  // Check that kernel/initramfs exist if Linux
  
  return YES;
}

#pragma mark - Control

- (void)cancel
{
  _cancelled = YES;
  if (_delegate && [_delegate respondsToSelector:@selector(copierWasCancelled:)]) {
    [_delegate copierWasCancelled:self];
  }
}

#pragma mark - Progress Information

- (double)progress
{
  if (_bytesTotal == 0) return 0.0;
  return (double)_bytesCopied / (double)_bytesTotal;
}

- (NSTimeInterval)estimatedTimeRemaining
{
  if (_bytesCopied == 0) return -1;
  
  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startTime];
  double speed = _bytesCopied / elapsed;
  if (speed == 0) return -1;
  
  unsigned long long remaining = _bytesTotal - _bytesCopied;
  return remaining / speed;
}

- (double)currentSpeed
{
  if (!_startTime) return 0;
  NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:_startTime];
  if (elapsed == 0) return 0;
  return _bytesCopied / elapsed;
}

- (NSDictionary *)statistics
{
  return @{
    @"bytesCopied": @(_bytesCopied),
    @"bytesTotal": @(_bytesTotal),
    @"filesCopied": @(_filesCopied),
    @"filesTotal": @(_filesTotal),
    @"directoriesCopied": @(_directoriesCopied),
    @"symlinksCopied": @(_symlinksCopied),
    @"hardlinksCopied": @(_hardlinksCopied),
    @"specialFilesCopied": @(_specialFilesCopied)
  };
}

@end


#pragma mark - Directory Layout Category

@implementation BootableFileCopier (DirectoryLayout)

- (BOOL)createBootableLayoutAtPath:(NSString *)targetPath
                             error:(NSError **)error
{
  // Essential directories for a bootable system
  NSArray *dirs = @[
    @"bin", @"boot", @"dev", @"etc", @"home", @"lib",
    @"mnt", @"opt", @"proc", @"root", @"run", @"sbin",
    @"srv", @"sys", @"tmp", @"usr", @"var",
    @"usr/bin", @"usr/lib", @"usr/sbin", @"usr/share", @"usr/local",
    @"var/cache", @"var/lib", @"var/log", @"var/tmp", @"var/run"
  ];
  
  for (NSString *dir in dirs) {
    NSString *path = [targetPath stringByAppendingPathComponent:dir];
    if (![_fm createDirectoryAtPath:path 
        withIntermediateDirectories:YES 
                         attributes:nil 
                              error:error]) {
      return NO;
    }
  }
  
  return YES;
}

- (BOOL)createVirtualDirectoriesAtPath:(NSString *)targetPath
                                 error:(NSError **)error
{
  // Create mount points for virtual filesystems
  NSArray *virtualDirs = @[
    @{@"path": @"dev", @"mode": @(0755)},
    @{@"path": @"proc", @"mode": @(0555)},
    @{@"path": @"sys", @"mode": @(0555)},
    @{@"path": @"run", @"mode": @(0755)},
    @{@"path": @"tmp", @"mode": @(01777)}
  ];
  
  for (NSDictionary *info in virtualDirs) {
    NSString *path = [targetPath stringByAppendingPathComponent:info[@"path"]];
    
    // Create if doesn't exist
    if (![_fm fileExistsAtPath:path]) {
      mode_t mode = [info[@"mode"] unsignedIntValue];
      if (mkdir([path fileSystemRepresentation], mode) != 0 && errno != EEXIST) {
        if (error) {
          *error = [NSError errorWithDomain:NSPOSIXErrorDomain 
                                       code:errno 
                                   userInfo:@{NSLocalizedDescriptionKey: 
                                     [NSString stringWithFormat:@"Cannot create %@", path]}];
        }
        return NO;
      }
    }
  }
  
  // Create essential device nodes if running as root
  if (geteuid() == 0) {
    NSString *devPath = [targetPath stringByAppendingPathComponent:@"dev"];
    
    // /dev/null
    NSString *nullPath = [devPath stringByAppendingPathComponent:@"null"];
    if (![_fm fileExistsAtPath:nullPath]) {
      mknod([nullPath fileSystemRepresentation], S_IFCHR | 0666, makedev(1, 3));
    }
    
    // /dev/zero
    NSString *zeroPath = [devPath stringByAppendingPathComponent:@"zero"];
    if (![_fm fileExistsAtPath:zeroPath]) {
      mknod([zeroPath fileSystemRepresentation], S_IFCHR | 0666, makedev(1, 5));
    }
    
    // /dev/console
    NSString *consolePath = [devPath stringByAppendingPathComponent:@"console"];
    if (![_fm fileExistsAtPath:consolePath]) {
      mknod([consolePath fileSystemRepresentation], S_IFCHR | 0600, makedev(5, 1));
    }
  }
  
  return YES;
}

- (BOOL)fixCriticalPermissionsAtPath:(NSString *)targetPath
                               error:(NSError **)error
{
  // Fix permissions on directories that need specific modes
  NSDictionary *permissions = @{
    @"tmp": @(01777),
    @"var/tmp": @(01777),
    @"root": @(0700)
  };
  
  for (NSString *path in permissions) {
    NSString *fullPath = [targetPath stringByAppendingPathComponent:path];
    if ([_fm fileExistsAtPath:fullPath]) {
      mode_t mode = [permissions[path] unsignedIntValue];
      chmod([fullPath fileSystemRepresentation], mode);
    }
  }
  
  return YES;
}

@end
