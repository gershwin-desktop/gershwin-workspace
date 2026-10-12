/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-only
 */

#include "config.h"

#import "LowDiskWarn.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#ifndef _WIN32
#include <sys/statvfs.h>
#endif
#if !defined(__linux__) && !defined(_WIN32)
#include <sys/param.h>
#include <sys/mount.h>
#endif

/* Overlay/union filesystem type names recognised across platforms. */
#ifndef _WIN32
static BOOL
FSIsOverlayFSType(NSString *fstype)
{
  return [fstype isEqualToString: @"overlay"]
      || [fstype isEqualToString: @"unionfs"]
      || [fstype isEqualToString: @"aufs"]
      || [fstype hasPrefix: @"fuse.overlay"]
      || [fstype hasPrefix: @"fuse.unionfs"];
}

static BOOL
FSIsOverlayRoot(void)
{
  /* overlay/unionfs merged roots are writable but backed by read-only
   * lower layers (squashfs, iso9660).  statvfs reports the overlay's
   * writable view, so ST_RDONLY is not set.  Detect this by looking
   * up the "/" mount point's filesystem type. */

#ifdef __linux__
  /* Linux: read /proc/mounts for the "/" entry. */
  NSString *mounts = [NSString stringWithContentsOfFile: @"/proc/mounts"
                                              encoding: NSUTF8StringEncoding
                                                 error: NULL];
  if (mounts == nil)
    return NO;

  NSArray *lines = [mounts componentsSeparatedByString: @"\n"];
  for (NSString *line in lines)
    {
      if ([line length] == 0)
        continue;
      NSArray *parts = [line componentsSeparatedByString: @" "];
      if ([parts count] < 3)
        continue;
      NSString *target = [parts objectAtIndex: 1];
      if ([target isEqualToString: @"/"])
        {
          return FSIsOverlayFSType([parts objectAtIndex: 2]);
        }
    }
#elif defined(_WIN32)
  /* Windows: no overlay roots and no mount table to inspect. */
#else
  /* BSDs / other: getmntinfo() populates struct statfs with f_fstypename. */
  struct statfs *mnts = NULL;
  int n = getmntinfo(&mnts, MNT_NOWAIT);
  for (int i = 0; i < n; i++)
    {
      if (strcmp(mnts[i].f_mntonname, "/") == 0)
        {
          NSString *fstype = [NSString stringWithUTF8String: mnts[i].f_fstypename];
          return FSIsOverlayFSType(fstype);
        }
    }
#endif
  return NO;
}
#endif /* !_WIN32 */

@implementation LowDiskWarn

- (void)dealloc
{
  [self stopMonitoring];
  if (panel != nil)
    {
      [self dismissWarning: nil];
    }
  [super dealloc];
}

- (void)startMonitoring
{
  [NSApplication sharedApplication];
  checking = NO;
  [self checkDiskSpace: nil];
  timer = [NSTimer scheduledTimerWithTimeInterval: 120.0
                                           target: self
                                         selector: @selector(checkDiskSpace:)
                                         userInfo: nil
                                          repeats: YES];
}

- (void)dismissWarning:(id)sender
{
  [panel orderOut: self];
  DESTROY(panel);
}

- (void)stopMonitoring
{
  if (timer && [timer isValid])
    {
      [timer invalidate];
    }
  timer = nil;
}

- (void)checkDiskSpace:(NSTimer *)aTimer
{
  if (checking)
    return;
  checking = YES;

#ifdef _WIN32
  /* No statvfs() and no single "/" startup disk on Windows: inert. */
  checking = NO;
  return;
#else
  struct statvfs buf;
  int ret = statvfs("/", &buf);

  if (ret == 0)
    {
      /* Skip read-only volumes (e.g. live/install media). */
      if (buf.f_flag & ST_RDONLY)
        {
          checking = NO;
          return;
        }

      /* Skip overlay/union roots (Live ISOs with writable overlay on
       * read-only lower layers).  The overlay is writable so ST_RDONLY
       * is not set, but free-space warnings are meaningless here. */
      if (FSIsOverlayRoot())
        {
          checking = NO;
          return;
        }

      unsigned long long total = (unsigned long long)buf.f_blocks
                                  * (unsigned long long)buf.f_frsize;
      unsigned long long available = (unsigned long long)buf.f_bavail
                                      * (unsigned long long)buf.f_frsize;

      if (total > 0)
        {
          double freePercent = ((double)available / (double)total) * 100.0;
          NSButton *ok;
          NSInteger tag;

          if (freePercent >= 3.0)
            {
              warned = NO;
            }
          /* Once per shortage, and not modal: a modal alert froze the
           * Dock and the desktop, and came back every two minutes. */
          else if (!warned && panel == nil)
            {
              NSAlert *alert = [[NSAlert alloc] init];

              warned = YES;
              [alert setMessageText: _(@"Low Disk Space")];
              [alert setInformativeText: [NSString stringWithFormat:
                _(@"The startup disk has less than 3%% free space.\n\n"
                  @"Only %.1f%% (%llu MB) available."),
                freePercent, available / (1024 * 1024)]];
              [alert setAlertStyle: NSWarningAlertStyle];
              [alert addButtonWithTitle: _(@"OK")];
              /* -runModal is the only public way to get the panel built,
               * and the theme builds it (with the warning icon) here. */
              [alert performSelector: @selector(_setupPanel)];
              tag = [[[alert buttons] objectAtIndex: 0] tag];
              ASSIGN(panel, [alert window]);
              [alert release];
              /* Its button stops a modal session, and there is none.  The
               * theme may draw buttons of its own, so take the one shown. */
              ok = [[panel contentView] viewWithTag: tag];
              [ok setTarget: self];
              [ok setAction: @selector(dismissWarning:)];
              [panel center];
              [panel orderFrontRegardless];
            }
        }
    }

  checking = NO;
#endif /* _WIN32 */
}

@end
