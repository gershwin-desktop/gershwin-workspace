/*
 * isowrite-helper - Privileged helper tool for ISO writing
 * 
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * This helper tool must be run with root privileges to write directly to block devices.
 * It is invoked by the Workspace application via sudo -A -E.
 */

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>

#ifndef O_DIRECT
#define O_DIRECT 0
#endif

#define BUFFER_SIZE (1024 * 1024)  /* 1MB buffer */

static void print_usage(const char *progname) {
  fprintf(stderr, "Usage: %s <iso-file> <device-path>\n", progname);
  fprintf(stderr, "Write an ISO image directly to a block device.\n");
  fprintf(stderr, "This tool requires root privileges.\n");
  exit(1);
}

static void print_error(const char *message) {
  fprintf(stderr, "ERROR: %s\n", message);
  exit(1);
}

int main(int argc, const char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  /* Check arguments */
  if (argc != 3) {
    print_usage(argv[0]);
  }
  
  const char *iso_path = argv[1];
  const char *device_path = argv[2];
  
  /* Check if running as root */
  if (geteuid() != 0) {
    print_error("This tool must be run as root");
  }
  
  /* Validate ISO file exists and is readable */
  struct stat iso_stat;
  if (stat(iso_path, &iso_stat) != 0) {
    fprintf(stderr, "ERROR: Cannot stat ISO file: %s\n", strerror(errno));
    exit(1);
  }
  
  if (!S_ISREG(iso_stat.st_mode)) {
    print_error("ISO path is not a regular file");
  }
  
  /* Validate device is a block device */
  struct stat dev_stat;
  if (stat(device_path, &dev_stat) != 0) {
    fprintf(stderr, "ERROR: Cannot stat device: %s\n", strerror(errno));
    exit(1);
  }
  
  if (!S_ISBLK(dev_stat.st_mode)) {
    print_error("Device path is not a block device");
  }
  
  /* Open ISO file for reading */
  int iso_fd = open(iso_path, O_RDONLY);
  if (iso_fd < 0) {
    fprintf(stderr, "ERROR: Cannot open ISO file: %s\n", strerror(errno));
    exit(1);
  }
  
  /* Open device for writing with O_SYNC */
  int device_fd = open(device_path, O_WRONLY | O_SYNC | O_DIRECT);
  if (device_fd < 0) {
    /* Try without O_DIRECT */
    device_fd = open(device_path, O_WRONLY | O_SYNC);
  }
  
  if (device_fd < 0) {
    fprintf(stderr, "ERROR: Cannot open device for writing: %s\n", strerror(errno));
    close(iso_fd);
    exit(1);
  }
  
  /* Allocate aligned buffer */
  void *buffer = NULL;
  if (posix_memalign(&buffer, 4096, BUFFER_SIZE) != 0) {
    buffer = malloc(BUFFER_SIZE);
  }
  
  if (!buffer) {
    print_error("Cannot allocate buffer");
  }
  
  /* Copy data */
  unsigned long long total_written = 0;
  unsigned long long last_report = 0;
  ssize_t bytes_read;
  
  fprintf(stderr, "INFO: Writing image to device...\n");
  fprintf(stderr, "INFO: ISO size: %lld bytes\n", (long long)iso_stat.st_size);
  
  while ((bytes_read = read(iso_fd, buffer, BUFFER_SIZE)) > 0) {
    ssize_t bytes_written = write(device_fd, buffer, bytes_read);
    
    if (bytes_written < 0) {
      fprintf(stderr, "ERROR: Write failed: %s\n", strerror(errno));
      free(buffer);
      close(device_fd);
      close(iso_fd);
      exit(1);
    }
    
    if (bytes_written != bytes_read) {
      fprintf(stderr, "ERROR: Incomplete write (%zd of %zd bytes)\n", 
              bytes_written, bytes_read);
      free(buffer);
      close(device_fd);
      close(iso_fd);
      exit(1);
    }
    
    total_written += bytes_written;
    
    /* Report progress every 5MB for responsive UI updates */
    if (total_written - last_report >= 5 * 1024 * 1024 || bytes_read == 0) {
      double percent = (double)total_written / (double)iso_stat.st_size * 100.0;
      fprintf(stderr, "PROGRESS: %.1f%% (%llu / %lld bytes)\n", 
              percent, total_written, (long long)iso_stat.st_size);
      last_report = total_written;
    }
  }
  
  if (bytes_read < 0) {
    fprintf(stderr, "ERROR: Read failed: %s\n", strerror(errno));
    free(buffer);
    close(device_fd);
    close(iso_fd);
    exit(1);
  }
  
  /* Sync to ensure all data is written */
  fprintf(stderr, "INFO: Syncing device...\n");
  fsync(device_fd);
  
  /* Clean up */
  free(buffer);
  close(device_fd);
  close(iso_fd);
  
  fprintf(stderr, "SUCCESS: Wrote %llu bytes to %s\n", total_written, device_path);
  
  [pool release];
  return 0;
}
