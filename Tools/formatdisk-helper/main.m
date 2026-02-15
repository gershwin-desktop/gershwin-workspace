/*
 * formatdisk-helper - Privileged helper tool to wipe and format a disk as FAT32
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void print_usage(const char *progname)
{
  fprintf(stderr, "Usage: %s <device-path> [label]\n", progname);
  fprintf(stderr, "Completely wipes and formats a block device as FAT32.\n");
  fprintf(stderr, "This tool requires root privileges.\n");
}

static void fail_with_message(const char *message)
{
  fprintf(stderr, "ERROR: %s\n", message);
  exit(1);
}

static const char *file_type_string(mode_t mode)
{
  if (S_ISBLK(mode)) return "block";
  if (S_ISCHR(mode)) return "character";
  if (S_ISDIR(mode)) return "directory";
  if (S_ISREG(mode)) return "regular";
  if (S_ISLNK(mode)) return "symlink";
  if (S_ISFIFO(mode)) return "fifo";
  if (S_ISSOCK(mode)) return "socket";
  return "unknown";
}

static int run_command(const char *command, char *const argv[])
{
  pid_t pid = fork();
  if (pid < 0) {
    fprintf(stderr, "ERROR: fork failed for %s: %s\n", command, strerror(errno));
    return -1;
  }

  if (pid == 0) {
    execvp(command, argv);
    fprintf(stderr, "ERROR: cannot execute %s: %s\n", command, strerror(errno));
    _exit(127);
  }

  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    fprintf(stderr, "ERROR: waitpid failed for %s: %s\n", command, strerror(errno));
    return -1;
  }

  if (!WIFEXITED(status)) {
    fprintf(stderr, "ERROR: %s terminated abnormally\n", command);
    return -1;
  }

  if (WEXITSTATUS(status) != 0) {
    fprintf(stderr, "ERROR: %s failed with status %d\n", command, WEXITSTATUS(status));
    return -1;
  }

  return 0;
}

#if defined(__linux__)
static int run_with_fallback(const char *primary, const char *secondary, char *const argv_primary[], char *const argv_secondary[])
{
  if (run_command(primary, argv_primary) == 0) {
    return 0;
  }

  if (secondary != NULL && argv_secondary != NULL) {
    fprintf(stderr, "INFO: falling back to %s\n", secondary);
    return run_command(secondary, argv_secondary);
  }

  return -1;
}
#endif

static NSString *sanitize_fat_label(NSString *input)
{
  NSString *source = input;
  if (!source || [source length] == 0) {
    source = @"UNTITLED";
  }

  NSMutableString *label = [NSMutableString string];
  NSUInteger i;
  for (i = 0; i < [source length] && [label length] < 11; i++) {
    unichar ch = [source characterAtIndex:i];
    if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) {
      [label appendFormat:@"%C", (unichar)toupper((int)ch)];
    } else if (ch == ' ' || ch == '_' || ch == '-') {
      [label appendString:@"_"];
    }
  }

  if ([label length] == 0) {
    [label appendString:@"UNTITLED"];
  }

  return label;
}

#if defined(__linux__)
static NSString *linux_partition_path(NSString *devicePath)
{
  NSString *name = [devicePath lastPathComponent];
  if ([name hasPrefix:@"nvme"] || [name hasPrefix:@"mmcblk"] || [name hasPrefix:@"loop"]) {
    return [devicePath stringByAppendingString:@"p1"];
  }
  return [devicePath stringByAppendingString:@"1"];
}
#endif

#if defined(__linux__)
static int format_linux(const char *devicePath, const char *label)
{
  char of_arg[1024];
  if (snprintf(of_arg, sizeof(of_arg), "of=%s", devicePath) >= (int)sizeof(of_arg)) {
    fprintf(stderr, "ERROR: device path too long\n");
    return -1;
  }

  fprintf(stderr, "INFO: Linux FAT32 format sequence started\n");

  char *dd_args[] = {"dd", "if=/dev/zero", of_arg, "bs=1M", "count=1", "conv=fsync", NULL};
  if (run_command("dd", dd_args) != 0) {
    return -1;
  }

  char *wipefs_args[] = {"wipefs", "-a", (char *)devicePath, NULL};
  if (run_command("wipefs", wipefs_args) != 0) {
    return -1;
  }

  char *parted_label_args[] = {"parted", "-s", (char *)devicePath, "mklabel", "msdos", NULL};
  if (run_command("parted", parted_label_args) != 0) {
    return -1;
  }

  char *parted_part_args[] = {"parted", "-s", (char *)devicePath, "mkpart", "primary", "fat32", "1MiB", "100%", NULL};
  if (run_command("parted", parted_part_args) != 0) {
    return -1;
  }

  NSString *partitionPathObj = linux_partition_path([NSString stringWithUTF8String:devicePath]);
  const char *partitionPath = [partitionPathObj UTF8String];

  char *mkfs_vfat_args[] = {"mkfs.vfat", "-F", "32", "-n", (char *)label, (char *)partitionPath, NULL};
  char *mkfs_fat_args[] = {"mkfs.fat", "-F", "32", "-n", (char *)label, (char *)partitionPath, NULL};
  if (run_with_fallback("mkfs.vfat", "mkfs.fat", mkfs_vfat_args, mkfs_fat_args) != 0) {
    return -1;
  }

  char *sync_args[] = {"sync", NULL};
  if (run_command("sync", sync_args) != 0) {
    return -1;
  }

  fprintf(stderr, "INFO: Linux FAT32 format sequence completed\n");
  return 0;
}
#endif

#if defined(__FreeBSD__)
static int format_freebsd(const char *devicePath, const char *label)
{
  NSString *device = [NSString stringWithUTF8String:devicePath];
  NSString *deviceName = [device lastPathComponent];

  char of_arg[1024];
  if (snprintf(of_arg, sizeof(of_arg), "of=%s", devicePath) >= (int)sizeof(of_arg)) {
    fprintf(stderr, "ERROR: device path too long\n");
    return -1;
  }

  char partitionPath[1024];
  if (snprintf(partitionPath, sizeof(partitionPath), "/dev/%ss1", [deviceName UTF8String]) >= (int)sizeof(partitionPath)) {
    fprintf(stderr, "ERROR: partition path too long\n");
    return -1;
  }

  fprintf(stderr, "INFO: FreeBSD FAT32 format sequence started\n");

  char *dd_args[] = {"dd", "if=/dev/zero", of_arg, "bs=1m", "count=1", NULL};
  if (run_command("dd", dd_args) != 0) {
    return -1;
  }

  char *gpart_destroy_args[] = {"gpart", "destroy", "-F", (char *)[deviceName UTF8String], NULL};
  (void)run_command("gpart", gpart_destroy_args);

  char *gpart_create_args[] = {"gpart", "create", "-s", "mbr", (char *)[deviceName UTF8String], NULL};
  if (run_command("gpart", gpart_create_args) != 0) {
    return -1;
  }

  char *gpart_add_args[] = {"gpart", "add", "-t", "fat32", (char *)[deviceName UTF8String], NULL};
  if (run_command("gpart", gpart_add_args) != 0) {
    return -1;
  }

  char *newfs_args[] = {"newfs_msdos", "-F", "32", "-L", (char *)label, partitionPath, NULL};
  if (run_command("newfs_msdos", newfs_args) != 0) {
    return -1;
  }

  char *sync_args[] = {"sync", NULL};
  if (run_command("sync", sync_args) != 0) {
    return -1;
  }

  fprintf(stderr, "INFO: FreeBSD FAT32 format sequence completed\n");
  return 0;
}
#endif

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  if (argc < 2 || argc > 3) {
    print_usage(argv[0]);
    [pool release];
    return 1;
  }

  if (geteuid() != 0) {
    fail_with_message("This tool must be run as root");
  }

#if !defined(__linux__) && !defined(__FreeBSD__)
  /* Keep the error message accurate on platforms we don't implement yet. */
  fprintf(stderr, "ERROR: Unsupported platform for formatdisk-helper\n");
  [pool release];
  return 1;
#endif

  const char *devicePath = argv[1];
  NSString *labelInput = (argc == 3) ? [NSString stringWithUTF8String:argv[2]] : @"UNTITLED";
  NSString *safeLabel = sanitize_fat_label(labelInput);

  if (devicePath == NULL || devicePath[0] == '\0') {
    fail_with_message("Missing device path");
  }
  if (strncmp(devicePath, "/dev/", 5) != 0) {
    fprintf(stderr, "ERROR: Device path must be under /dev (got: %s)\n", devicePath);
    [pool release];
    return 1;
  }

  struct stat st;
  if (stat(devicePath, &st) != 0) {
    fprintf(stderr, "ERROR: cannot stat device %s: %s\n", devicePath, strerror(errno));
    [pool release];
    return 1;
  }

#if defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__) || defined(__DragonFly__)
  /* On BSD block devices are often represented as character device nodes; accept both */
  if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
    fprintf(stderr, "ERROR: %s is not a block or character device (type=%s mode=0%o)\n",
            devicePath,
            file_type_string(st.st_mode),
            (unsigned int)(st.st_mode & 07777));
    [pool release];
    return 1;
  }
#else
  if (!S_ISBLK(st.st_mode)) {
    fprintf(stderr, "ERROR: %s is not a block device (type=%s mode=0%o)\n",
            devicePath,
            file_type_string(st.st_mode),
            (unsigned int)(st.st_mode & 07777));
    [pool release];
    return 1;
  }
#endif

  int rc = 1;
#if defined(__linux__)
  rc = (format_linux(devicePath, [safeLabel UTF8String]) == 0) ? 0 : 1;
#elif defined(__FreeBSD__)
  rc = (format_freebsd(devicePath, [safeLabel UTF8String]) == 0) ? 0 : 1;
#endif

  if (rc == 0) {
    fprintf(stderr, "SUCCESS: FAT32 format finished for %s\n", devicePath);
  }

  [pool release];
  return rc;
}
