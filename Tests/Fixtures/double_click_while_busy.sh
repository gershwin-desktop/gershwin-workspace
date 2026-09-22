#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# Double-clicks an icon of a Workspace window while Workspace is stopped, so
# that both clicks are already queued when it handles the first press - what
# a loaded machine does to a quick double click.  Only the tools every CI
# system has (pgrep, xdpyinfo, drive_ui) are used; there is no xdotool there.
#
# usage: double_click_while_busy.sh <icon name> <window title>

set -e

name=$1
window=$2

pid=$(pgrep -u "$(id -u)" -x Workspace)

# drive_ui reports AppKit screen frames (origin bottom left); click_at takes
# X coordinates (origin top left).
height=$(xdpyinfo | awk '/dimensions:/ { split($2, d, "x"); print d[2] }')

icon_point() {
  drive_ui --pid "$pid" get_full_tree | awk -F '\t' \
    -v n="$name" -v w="$window" -v h="$height" '
    $2 == "FSNIcon" && $3 == n && $10 == w {
      gsub(/[^0-9. ]/, " ", $6)
      split($6, f, " ")
      printf "%d %d\n", f[1] + f[3] / 2, h - (f[2] + f[4] / 2)
      exit
    }'
}

# The window manager frames the window and the viewer restores its saved size
# after the icon is first there, so the icon moves for a moment after the test
# may go on.  Clicking at a position it has already left would prove nothing,
# so wait until two readings agree.
point=""
i=0
while [ $i -lt 40 ]; do
  previous=$point
  point=$(icon_point)
  if [ -n "$point" ] && [ "$point" = "$previous" ]; then
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [ -z "$point" ]; then
  echo "no icon '$name' in window '$window'" >&2
  exit 1
fi
if [ "$point" != "$previous" ]; then
  echo "icon '$name' kept moving, last at $point" >&2
  exit 1
fi

kill -STOP "$pid"
# Whatever happens to the clicks, Workspace has to run again or every later
# test hangs on it.
trap 'kill -CONT "$pid"' EXIT
# click_at ends with XSync, so both clicks are in Workspace's X queue when it
# returns and the app is continued.
drive_ui click_at $point 1 2
