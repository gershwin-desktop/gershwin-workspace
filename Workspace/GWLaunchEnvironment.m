/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLaunchEnvironment.m - the toolkit integration variables for the
 * applications Workspace starts, only for the ones that can use them.  See
 * GWLaunchEnvironment.h. */

#import "GWLaunchEnvironment.h"

#include <fcntl.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

/* How this system marks its own ELF binaries: EI_OSABI and the owner of the
 * ABI-tag note (type 1).  NextBSD defines __FreeBSD__.  Elsewhere - Linux,
 * whose binaries are the native ones there, Windows, a system not listed -
 * every executable counts as native. */
#if defined(__FreeBSD__)
#define GW_ELF_OSABI 9
#define GW_ELF_NOTE_OWNER "FreeBSD"
#elif defined(__NetBSD__)
#define GW_ELF_OSABI 2
#define GW_ELF_NOTE_OWNER "NetBSD"
#elif defined(__OpenBSD__)
#define GW_ELF_OSABI 12
#define GW_ELF_NOTE_OWNER "OpenBSD"
#endif

#ifdef GW_ELF_OSABI
#define GW_ELF_CLASS (sizeof(void *) == 8 ? 2 : 1)
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
#define GW_ELF_DATA 2
#else
#define GW_ELF_DATA 1
#endif

/* A field of the host's own byte order and size at `off` in `buf`. */
static uint64_t GWField(const unsigned char *buf, size_t off, size_t size)
{
  uint16_t v16;
  uint32_t v32;
  uint64_t v64;

  switch (size) {
    case 2: memcpy(&v16, buf + off, 2); return v16;
    case 4: memcpy(&v32, buf + off, 4); return v32;
    default: memcpy(&v64, buf + off, 8); return v64;
  }
}

/* Whether one PT_NOTE segment holds this system's ABI tag. */
static BOOL GWNotesHaveABITag(int fd, uint64_t off, uint64_t size,
                              uint64_t align)
{
  unsigned char buf[4096];
  size_t len = size < sizeof(buf) ? (size_t)size : sizeof(buf);
  size_t owner = sizeof(GW_ELF_NOTE_OWNER);  /* with its NUL */
  size_t pad = (align == 8) ? 8 : 4;
  size_t pos = 0;

  if (pread(fd, buf, len, (off_t)off) != (ssize_t)len) {
    return NO;
  }
  while (pos + 12 <= len) {
    uint32_t namesz = (uint32_t)GWField(buf, pos, 4);
    uint32_t descsz = (uint32_t)GWField(buf, pos + 4, 4);
    uint32_t type = (uint32_t)GWField(buf, pos + 8, 4);

    if (namesz > len || descsz > len) {
      break;
    }

    if (type == 1 && namesz == owner && pos + 12 + owner <= len
        && memcmp(buf + pos + 12, GW_ELF_NOTE_OWNER, owner) == 0) {
      return YES;
    }
    pos += 12 + ((namesz + pad - 1) & ~(pad - 1))
               + ((descsz + pad - 1) & ~(pad - 1));
  }
  return NO;
}
#endif

BOOL GWIsForeignExecutable(NSString *path)
{
#ifdef GW_ELF_OSABI
  unsigned char eh[64], ph[56];
  BOOL is64 = (GW_ELF_CLASS == 2);
  uint64_t phoff;
  unsigned phentsize, phnum, i;
  BOOL native = NO;
  ssize_t n;
  int fd;

  if (path == nil
      || (fd = open([path fileSystemRepresentation], O_RDONLY)) < 0) {
    return NO;
  }
  n = pread(fd, eh, sizeof(eh), 0);
  if (n < 16 || memcmp(eh, "\177ELF", 4) != 0) {
    close(fd);                      /* a script or no ELF: native */
    return NO;
  }
  if (eh[4] != GW_ELF_CLASS || eh[5] != GW_ELF_DATA) {
    close(fd);
    return YES;
  }
  if (eh[7] == GW_ELF_OSABI || n < (is64 ? 64 : 52)) {
    close(fd);
    return NO;
  }

  /* EI_OSABI 0 (most OpenBSD and NetBSD binaries leave it there, and so do
     Linux ones): only this system's ABI-tag note makes it native.  A static
     Linux runtime such as an AppImage's carries no ABI-tag note at all, and
     the kernel hands it to its Linux compatibility for the same reason. */
  phoff = GWField(eh, is64 ? 32 : 28, is64 ? 8 : 4);
  phentsize = (unsigned)GWField(eh, is64 ? 54 : 42, 2);
  phnum = (unsigned)GWField(eh, is64 ? 56 : 44, 2);
  if (phentsize < (is64 ? 56 : 32) || phnum > 512) {
    phnum = 0;
  }
  for (i = 0; i < phnum && !native; i++) {
    if (pread(fd, ph, is64 ? 56 : 32, (off_t)(phoff + i * phentsize))
        != (is64 ? 56 : 32)) {
      break;
    }
    if (GWField(ph, 0, 4) == 4) {   /* PT_NOTE */
      native = GWNotesHaveABITag(fd,
                                 GWField(ph, is64 ? 8 : 4, is64 ? 8 : 4),
                                 GWField(ph, is64 ? 32 : 16, is64 ? 8 : 4),
                                 GWField(ph, is64 ? 48 : 28, is64 ? 8 : 4));
    }
  }
  close(fd);
  return !native;
#else
  return NO;
#endif
}

/* `value` in front of the colon-separated list `key`, unless it is in it. */
static void GWAddListItem(NSMutableDictionary *env, NSString *key,
                          NSString *value)
{
  NSString *list = [env objectForKey: key];

  if ([list length] == 0) {
    [env setObject: value forKey: key];
  } else if (![[list componentsSeparatedByString: @":"]
                containsObject: value]) {
    [env setObject: [NSString stringWithFormat: @"%@:%@", value, list]
            forKey: key];
  }
}

NSDictionary *GWEnvironmentForExecutable(NSString *path,
                                         NSDictionary *environment)
{
  NSMutableDictionary *env;
  NSArray *table;
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL foreign = GWIsForeignExecutable(path);
  NSUInteger i;

  if (environment == nil) {
    environment = [[NSProcessInfo processInfo] environment];
  }
  env = [[environment mutableCopy] autorelease];

  if (foreign) {
    [env removeObjectForKey: @"LD_PRELOAD"];
    [env removeObjectForKey: @"LD_LIBRARY_PATH"];
  }

  table = [NSArray arrayWithContentsOfFile: GW_TOOLKIT_INTEGRATION_TABLE];
  for (i = 0; i < [table count]; i++) {
    NSDictionary *group = [table objectAtIndex: i];
    NSDictionary *vars;
    NSString *requires;
    NSEnumerator *keys;
    NSString *key;

    if (![group isKindOfClass: [NSDictionary class]]) {
      continue;
    }
    vars = [group objectForKey: @"Environment"];
    requires = [group objectForKey: @"Requires"];
    if (![vars isKindOfClass: [NSDictionary class]]) {
      continue;
    }
    if (!foreign && [requires isKindOfClass: [NSString class]]
        && ![fm fileExistsAtPath: requires]) {
      continue;
    }
    keys = [vars keyEnumerator];
    while ((key = [keys nextObject]) != nil) {
      NSString *value = [vars objectForKey: key];

      if (foreign) {
        [env removeObjectForKey: key];
      } else if ([value isKindOfClass: [NSString class]]
                 && [value length] > 0) {
        GWAddListItem(env, key, value);
      }
    }
  }

  return env;
}
