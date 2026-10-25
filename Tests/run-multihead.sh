#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
#
# CI entry point for the multi-monitor checks of the Workspace (gershwin
# components issue #135).  It starts a private Xorg with the "dummy" video
# driver (16 RandR outputs; Xvfb has one) on a free display from :200 up and
# runs, on it, the Desktop unit suites (primary monitor rule, icon grid
# geometry) and a live check: the Desktop window covers both monitors, and
# follows the screen when the second monitor is unplugged.  Prints a summary
# and exits non-zero when anything failed.
#
#   sh Tests/run-multihead.sh
#
# Environment:
#   MULTIHEAD_DISPLAY   display number to use, 200 or higher (default: the
#                       first free one from 200 up)
#   MULTIHEAD_REQUIRE   1 = a missing dummy driver or tool is a failure (CI
#                       sets it where the packages are installable);
#                       otherwise the checks are skipped with a message
#   MULTIHEAD_KEEP      directory for the logs (default: a fresh temp dir)
#   MULTIHEAD_WS        Workspace executable (default: the installed one)
#   MULTIHEAD_USER      run the Workspace as this user (via sudo); for a
#                       developer machine, where it must not run as the
#                       user who owns the live desktop
#
# It never uses an inherited DISPLAY and never touches a display below 200;
# the Xorg and Workspace it starts are stopped on exit, nothing else is
# killed.  The Workspace runs with a private HOME.  The suites need the
# Gershwin fonts (see run-suites.sh).

here=$(cd "$(dirname "$0")" && pwd)

# An inherited DISPLAY may be a user's desktop; every command below gets its
# own explicit one.
unset DISPLAY

[ -r "${GNUSTEP_MAKEFILES:-/System/Library/Makefiles}/GNUstep.sh" ] || {
  echo "FATAL: GNUstep.sh not found; install the Gershwin stack first" >&2
  exit 1
}
. "${GNUSTEP_MAKEFILES:-/System/Library/Makefiles}/GNUstep.sh"

# GNUstep.sh reads unset variables, so -u only starts here.
set -u

passes=0
fails=0
skips=0
started=""
wspid=""

say() { echo "== $*"; }
ok() { passes=$((passes + 1)); echo "PASS: $1"; }
bad() { fails=$((fails + 1)); echo "FAIL: $1"; }

work=$(mktemp -d "${TMPDIR:-/tmp}/multihead.XXXXXX") || exit 1
logs=${MULTIHEAD_KEEP:-$work/logs}
mkdir -p "$logs" "$work/home" "$work/xorg"
chmod a+rwx "$work" "$work/home" "$logs"

SUDO=sudo
[ "$(id -u)" = 0 ] && SUDO=
wsuser=${MULTIHEAD_USER:-}

cleanup() {
  stop_ws
  stop_server
  # The Workspace starts a GNUstep notification daemon that outlives it; the
  # dedicated test user owns nothing else.
  if [ -n "$wsuser" ]; then
    # Its leftovers (gdnc, dbus) are owned by that user, so are its files.
    sudo pkill -u "$wsuser"
    sleep 1
    sudo rm -rf "$work"
  fi
  # Only the private temp dir made above.
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ------------------------------------------------------------- dummy Xorg

driver_installed() {
  for d in /usr/lib/xorg/modules/drivers /usr/lib64/xorg/modules/drivers \
           /usr/lib/x86_64-linux-gnu/xorg/modules/drivers \
           /usr/local/lib/xorg/modules/drivers /usr/X11R6/lib/modules/drivers; do
    [ -e "$d/dummy_drv.so" ] && return 0
  done
  return 1
}

display_in_use() {
  [ -e "/tmp/.X11-unix/X$1" ] || [ -e "/tmp/.X$1-lock" ] && return 0
  # Linux abstract sockets leave no file.
  grep -q "@/tmp/.X11-unix/X$1\$" /proc/net/unix 2>/dev/null
}

pick_display() {
  if [ -n "${MULTIHEAD_DISPLAY:-}" ]; then
    n=$MULTIHEAD_DISPLAY
    case $n in ''|*[!0-9]*) echo "FATAL: MULTIHEAD_DISPLAY must be a number" >&2; exit 2;; esac
    [ "$n" -ge 200 ] || { echo "FATAL: refusing display :$n, use 200 or higher" >&2; exit 2; }
    display_in_use "$n" && { echo "FATAL: display :$n is in use" >&2; exit 2; }
    echo "$n"; return
  fi
  n=200
  while [ $n -lt 400 ]; do
    display_in_use "$n" || { echo "$n"; return; }
    n=$((n + 1))
  done
  echo "FATAL: no free display from 200 to 399" >&2
  exit 2
}

start_server() {
  # Debian's /usr/bin/Xorg is a wrapper that wants a console; the server
  # binary itself runs without one.
  xorg=/usr/lib/xorg/Xorg
  [ -x "$xorg" ] || xorg=$(command -v Xorg)
  conf=$work/xorg/xorg-dummy-$num.conf
  cat > "$conf" <<'EOF'
Section "ServerFlags"
    Option "AutoAddDevices" "false"
    Option "AutoAddGPU" "false"
    Option "DontVTSwitch" "true"
EndSection
Section "Device"
    Identifier "dummy"
    Driver "dummy"
    VideoRam 256000
EndSection
Section "Monitor"
    Identifier "mon"
    HorizSync 5.0-1000.0
    VertRefresh 5.0-200.0
EndSection
Section "Screen"
    Identifier "screen"
    Device "dummy"
    Monitor "mon"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Virtual 8192 4096
    EndSubSection
EndSection
EOF
  chmod a+r "$conf"
  # Root, like the uitest session's Xvfb.
  $SUDO "$xorg" ":$num" -noreset -nolisten tcp -ac -config "$conf" \
    -logfile "$logs/xorg-dummy-$num.log" >/dev/null 2>&1 &
  i=0
  while [ $i -lt 50 ] && ! DISPLAY=:$num xrandr >/dev/null 2>&1; do sleep 0.2; i=$((i + 1)); done
  DISPLAY=:$num xrandr | grep -q '^DUMMY0 connected' || {
    bad "dummy Xorg did not start on :$num"
    tail -n 30 "$logs/xorg-dummy-$num.log" 2>/dev/null
    return 1
  }
  started=$num
}

stop_server() {
  [ -n "$started" ] || return 0
  # Only the server we started: its lock file names a process of Xorg :N.
  pid=$(tr -d ' ' < "/tmp/.X$started-lock" 2>/dev/null)
  if [ -n "$pid" ] && ps -o args= -p "$pid" | grep -q "Xorg :$started "; then
    $SUDO kill "$pid"
  fi
  started=""
}

xr() { DISPLAY=:$num xrandr "$@"; }

# An output becomes "connected" once a mode has been set on it, and stays
# connected after it is switched off: a monitor plugged in after X started.
plug() {
  xr --addmode "$1" 1024x768 2>/dev/null
  xr --output "$1" --mode 1024x768 --right-of DUMMY0 &&
  xr --output "$1" --off
  xr | grep -q "^$1 connected"
}

# ------------------------------------------------------------- unit tests

unit_tests() {
  say "unit tests: Desktop suites on :$num"
  if DISPLAY=:$num sh "$here/run-suites.sh" Desktop > "$logs/unit.log" 2>&1; then
    ok "Desktop suites ($(grep -c '^Passed test:' "$here/tests.log" 2>/dev/null) tests)"
  else
    bad "Desktop suites (log $logs/unit.log)"
    tail -n 40 "$logs/unit.log"
  fi
  cp "$here/tests.log" "$logs/unit-tests.log" 2>/dev/null
}

# ------------------------------------------------------------- live check

stop_ws() {
  [ -n "$wspid" ] || return 0
  if [ -n "$wsuser" ]; then sudo kill "$wspid" 2>/dev/null; else kill "$wspid" 2>/dev/null; fi
  i=0
  while [ $i -lt 20 ] && kill -0 "$wspid" 2>/dev/null; do sleep 0.2; i=$((i + 1)); done
  # A TERM'd process can hang; this is our own pid, so KILL is safe.
  if kill -0 "$wspid" 2>/dev/null; then
    if [ -n "$wsuser" ]; then sudo kill -9 "$wspid" 2>/dev/null; else kill -9 "$wspid" 2>/dev/null; fi
  fi
  wspid=""
}

desktop_geom() {  # WxH+X+Y of the Desktop window
  DISPLAY=:$num xwininfo -root -tree | awk '$2 == "\"Desktop\":" { print $(NF-1); exit }'
}

root_size() { DISPLAY=:$num xdpyinfo | awk '/dimensions/ { print $2 }'; }

wait_for() {  # wait_for SECONDS COMMAND...
  t=$(($1 * 5)); shift
  i=0
  while [ $i -lt $t ]; do "$@" && return 0; sleep 0.2; i=$((i + 1)); done
  return 1
}

live_tests() {
  ws=${MULTIHEAD_WS:-/System/Applications/Workspace.app/Workspace}
  [ -x "$ws" ] || { bad "no Workspace executable at $ws"; return; }

  say "live: the Desktop window follows an unplugged monitor"
  plug DUMMY1 || { bad "cannot plug DUMMY1"; return; }
  xr --addmode DUMMY0 1280x800 2>/dev/null
  xr --fb 2304x800 --output DUMMY0 --mode 1280x800 --pos 0x0 --primary \
     --output DUMMY1 --mode 1024x768 --pos 1280x0
  [ "$(root_size)" = 2304x800 ] && ok "two monitors, screen 2304x800" ||
    bad "two monitors, screen 2304x800 (is $(root_size))"

  # Started directly (no shell function) so that $! is the Workspace.
  if [ -n "$wsuser" ]; then
    sudo -u "$wsuser" env DISPLAY=:$num HOME="$work/home" \
      FONTCONFIG_FILE=/System/Library/Preferences/fonts.conf \
      sh -c ". '$GNUSTEP_MAKEFILES/GNUstep.sh'; exec '$ws'" > "$logs/workspace.log" 2>&1 &
  else
    env DISPLAY=:$num HOME="$work/home" \
      FONTCONFIG_FILE=/System/Library/Preferences/fonts.conf \
      sh -c ". '$GNUSTEP_MAKEFILES/GNUstep.sh'; exec '$ws'" > "$logs/workspace.log" 2>&1 &
  fi
  wspid=$!
  have_desktop() { [ -n "$(desktop_geom)" ]; }
  wait_for 40 have_desktop ||
    { bad "the Workspace has no Desktop window (log $logs/workspace.log)"; tail -n 20 "$logs/workspace.log"; return; }
  covers_both() { case $(desktop_geom) in 2304x800+0+0) return 0;; esac; return 1; }
  wait_for 10 covers_both && ok "the Desktop window covers both monitors ($(desktop_geom))" ||
    bad "the Desktop window covers both monitors (is $(desktop_geom))"

  xr --output DUMMY1 --set non-desktop 1
  # Real hardware loses the CRTC with the monitor; the server leaves it
  # running until a client switches it off.
  xr --output DUMMY1 --off --fb 1280x800
  covers_one() { case $(desktop_geom) in 1280x800+0+0) return 0;; esac; return 1; }
  wait_for 15 covers_one && ok "the Desktop window shrank with the screen ($(desktop_geom))" ||
    bad "the Desktop window shrank with the screen (is $(desktop_geom), root $(root_size))"
  kill -0 "$wspid" 2>/dev/null && ok "the Workspace survived the unplug" ||
    bad "the Workspace survived the unplug"
}

# --------------------------------------------------------------------- main

echo "gershwin-workspace multi-monitor checks, $(uname -s)"

missing=""
for tool in xrandr xwininfo xdpyinfo; do
  command -v $tool >/dev/null 2>&1 || missing="$missing $tool"
done
driver_installed || missing="$missing the-Xorg-dummy-video-driver"
if [ -n "$missing" ]; then
  if [ "${MULTIHEAD_REQUIRE:-}" = 1 ]; then bad "not installed:$missing"
  else skips=$((skips + 1)); echo "SKIP: multi-monitor checks, not installed:$missing"; fi
else
  num=$(pick_display) || exit 2
  echo "private Xorg on :$num"
  if start_server; then
    unit_tests
    live_tests
  fi
fi

echo
echo "multihead summary: $passes passed, $fails failed, $skips skipped"
[ $fails -eq 0 ]
