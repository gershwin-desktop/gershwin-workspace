/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The Windows build has no X server and no POSIX signals, and main()
   only claims the display on other systems. */
#ifndef _WIN32

#include "GWSingleInstance.h"

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

const char *GWSingleInstanceSelectionName(int screen)
{
  static char names[16][40];

  if (screen < 0 || screen >= 16)
    {
      return NULL;
    }
  snprintf(names[screen], sizeof(names[screen]),
           "_WORKSPACE_S%d", screen);
  return names[screen];
}

pid_t GWSingleInstanceVictim(pid_t ownerPID, pid_t ownPID)
{
  if (ownerPID <= 0 || ownerPID == ownPID)
    {
      return 0;
    }
  return ownerPID;
}

static pid_t windowPID(Display *dpy, Window window)
{
  Atom pidAtom = XInternAtom(dpy, "_NET_WM_PID", False);
  Atom type = None;
  int format = 0;
  unsigned long count = 0;
  unsigned long after = 0;
  unsigned char *data = NULL;
  pid_t pid = 0;

  if (XGetWindowProperty(dpy, window, pidAtom, 0, 1, False, XA_CARDINAL,
                         &type, &format, &count, &after, &data) == Success
      && data != NULL)
    {
      if (type == XA_CARDINAL && format == 32 && count == 1)
        {
          pid = (pid_t)*(unsigned long *)data;
        }
      XFree(data);
    }
  return pid;
}

/* A hung Workspace would keep its windows and the selection, so it is
 * ended: politely first, forcibly after two seconds. */
static void terminate(pid_t pid)
{
  int waitedMs;

  fprintf(stderr, "Workspace: replacing the Workspace of this display (PID %d)\n",
          (int)pid);
  kill(pid, SIGTERM);
  for (waitedMs = 0; waitedMs < 2000; waitedMs += 100)
    {
      usleep(100000);
      if (kill(pid, 0) != 0)
        {
          return;
        }
    }
  kill(pid, SIGKILL);
  usleep(500000);
}

int GWSingleInstanceClaimDisplay(void)
{
  /* Kept open on purpose: the selection is released when the connection
   * closes, which is how a dead Workspace stops being the owner. */
  static Display *dpy = NULL;
  int screens;
  int screen;
  Window owner;
  pid_t ownPID = getpid();
  pid_t ownerPID;
  pid_t victim;

  dpy = XOpenDisplay(NULL);
  if (dpy == NULL)
    {
      fprintf(stderr, "Workspace: cannot open the X display\n");
      return 0;
    }
  screens = ScreenCount(dpy);
  if (GWSingleInstanceSelectionName(screens - 1) == NULL)
    {
      fprintf(stderr, "Workspace: too many X screens (%d)\n", screens);
      return 0;
    }

  owner = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), -10, -10, 1, 1,
                              0, 0, 0);
  {
    unsigned long pid = (unsigned long)ownPID;

    XChangeProperty(dpy, owner, XInternAtom(dpy, "_NET_WM_PID", False),
                    XA_CARDINAL, 32, PropModeReplace,
                    (unsigned char *)&pid, 1);
  }

  for (screen = 0; screen < screens; screen++)
    {
      Atom selection = XInternAtom(dpy, GWSingleInstanceSelectionName(screen),
                                   False);
      Window previous = XGetSelectionOwner(dpy, selection);

      ownerPID = (previous != None) ? windowPID(dpy, previous) : 0;
      victim = GWSingleInstanceVictim(ownerPID, ownPID);
      if (victim > 0)
        {
          terminate(victim);
        }
      XSetSelectionOwner(dpy, selection, owner, CurrentTime);
      if (XGetSelectionOwner(dpy, selection) != owner)
        {
          fprintf(stderr, "Workspace: cannot own selection %s\n",
                  GWSingleInstanceSelectionName(screen));
          return 0;
        }
    }
  XFlush(dpy);
  return 1;
}

#endif /* !_WIN32 */
