#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
#
# Runs every ObjectTesting suite under Tests/ (each directory holding a
# TestInfo marker) in one gnustep-tests run and exits non-zero when a test,
# file or build failed. CI calls this after "make workspace" has installed
# the frameworks the suites link against.
#
# Many suites create views, images or windows, so they need an X display.
# Without DISPLAY a private Xvfb is started on a display number the server
# picks itself (never a fixed one that could be a user's session).

set -e
cd "$(dirname "$0")"
. "${GNUSTEP_MAKEFILES:-/System/Library/Makefiles}/GNUstep.sh"

if [ -z "$DISPLAY" ]; then
  command -v Xvfb >/dev/null 2>&1 || {
    echo "FATAL: no DISPLAY and no Xvfb; the AppKit suites need an X display" >&2
    exit 1
  }
  dfile=$(mktemp)
  Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp 3>"$dfile" &
  xpid=$!
  trap 'kill $xpid 2>/dev/null; rm -f "$dfile"' EXIT INT TERM
  i=0
  while [ ! -s "$dfile" ]; do
    kill -0 $xpid 2>/dev/null || { echo "FATAL: Xvfb exited" >&2; exit 1; }
    i=$((i + 1))
    [ $i -le 100 ] || { echo "FATAL: Xvfb did not report a display" >&2; exit 1; }
    sleep 0.2
  done
  DISPLAY=":$(head -n 1 "$dfile")"
  export DISPLAY
  echo "Running the suites on Xvfb $DISPLAY"
fi

# Views measure and draw text in the desktop's own fonts (NSFont is
# Inter-Medium). They live in /System/Library/Fonts and fontconfig finds them
# only through the Gershwin fonts.conf, the same setup gershwin-system's
# Gershwin.sh and gershwin-developer's run-uitests.sh use; a stock container
# fontconfig does not look there, and a fallback font ignores the size the
# tests ask for.
export FONTCONFIG_PATH=/System/Library/Preferences
export FONTCONFIG_FILE=$FONTCONFIG_PATH/fonts.conf
if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f /System/Library/Fonts >/dev/null 2>&1
fi
if [ -z "$(fc-list Inter 2>/dev/null | head -n 1)" ]; then
  echo "FATAL: the Gershwin fonts (Inter in /System/Library/Fonts, via $FONTCONFIG_FILE) are not installed; the view suites need them" >&2
  exit 1
fi

# Suite names given as arguments (for example "Desktop") run alone; the
# multi-monitor entry point Tests/run-multihead.sh does that.
suites="$*"
if [ -z "$suites" ]; then
  for marker in */TestInfo; do
    suites="$suites ${marker%/TestInfo}"
  done
fi
[ -n "$suites" ] || { echo "FATAL: no suites found" >&2; exit 1; }

# gnustep-tests exits 1 on any failed test, file or build. Its summary only
# names what failed; the why (exceptions, compiler errors, what the test
# logged) is in tests.log, which CI does not keep, so print the log of every
# test file that failed.
# --sequential: by default gnustep-tests builds all tools of a directory
# with make -j 4, and tools that compile the same shared source (e.g.
# ../../DSStore/DSStore.m) write the same object and dependency file at
# once, which made random tools fail to build on CI.
if gnustep-tests --sequential $suites; then
  exit 0
fi
awk '
  /^Testing .*\.\.\.$/ { flush(); n = 0 }
  { buf[n++] = $0 }
  /^Failed |aborted without|Error [0-9]|error:/ { bad = 1 }
  function flush(  i, from) {
    if (bad) {
      from = (n > 120) ? n - 120 : 0
      print "----- " buf[0]
      for (i = from; i < n; i++) print buf[i]
    }
    bad = 0
  }
  END { flush() }
' tests.log
exit 1
