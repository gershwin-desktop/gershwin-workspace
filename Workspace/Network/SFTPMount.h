/*
 * SFTPMount.h
 * 
 * Encapsulates all SFTP mounting functionality
 */

#ifndef SFTPMOUNT_H
#define SFTPMOUNT_H

#import <Foundation/Foundation.h>

@class NetworkServiceItem;

/**
 * Result object returned from SFTP mount attempts
 */
@interface SFTPMountResult : NSObject
{
  BOOL success;
  NSString *mountPath;
  NSString *errorMessage;
  int pid;
}

@property(nonatomic, assign) BOOL success;
@property(nonatomic, retain) NSString *mountPath;
@property(nonatomic, retain) NSString *errorMessage;
@property(nonatomic, assign) int pid;

+ (instancetype)successWithPath:(NSString *)path pid:(int)processId;
+ (instancetype)failureWithError:(NSString *)error;

@end

/**
 * Handles all SFTP mounting operations
 */
@interface SFTPMount : NSObject
{
  NSString *username;
  NSString *password;
  NSString *hostname;
  int port;
  NSString *remotePath;
  NSString *mountPoint;
  NSTask *sshfsTask;
  NSFileHandle *logHandle;
  NSString *sshfsLogPath;
  NSString *tempPasswordFile;
}

/**
 * Mount an SFTP service with the given credentials
 * Returns SFTPMountResult with success status and mount path or error
 */
- (SFTPMountResult *)mountService:(NetworkServiceItem *)serviceItem
                         username:(NSString *)user
                         password:(NSString *)pass
                        mountPath:(NSString *)mpath;

/**
 * Check if a mount point is mounted to the correct server
 * Returns YES if the path is mounted and appears to be the correct remote server
 */
- (BOOL)isMountedCorrectly:(NSString *)mpath 
                 toHostname:(NSString *)expectedHostname 
                   username:(NSString *)user;

/**
 * Unmount an SFTP mount point
 */
- (BOOL)unmountPath:(NSString *)path;

@end

#endif
