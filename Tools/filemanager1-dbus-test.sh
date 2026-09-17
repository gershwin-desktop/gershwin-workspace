#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Test the org.freedesktop.FileManager1 D-Bus interface of Workspace - the
# interface browsers use for "Show in folder" on a download, and that other
# desktop apps use to reveal a file in the file manager.
#
# Usage: ./filemanager1-dbus-test.sh [self-test|monitor|show <path>]
#   self-test   run the assertion suite against the running Workspace
#   monitor     print every FileManager1 call on the session bus; use it to
#               find out whether an app (Chrome, Firefox, ...) asks the file
#               manager at all when you click "Show in folder"
#   show <path> send a single ShowItems for <path>
#
# The D-Bus reply proves nothing on its own: Workspace answers every call with
# an empty method return no matter what the UI did.  So window presence is
# read from the window manager's _NET_CLIENT_LIST and the selection from the
# live widget tree via DriveUI.  The suite therefore needs a running Workspace
# on $DISPLAY with DriveUI.bundle loaded.
#
# Run it in the isolated uitest session, not on a desktop someone is using:
# closing a viewer makes it the focused window, and any keystroke typed
# meanwhile selects icons by name prefix and breaks the selection checks.
# The selection checks read the icon view, the default for a new folder.
#   sudo -u uitest env DISPLAY=:99 HOME=/home/uitest \
#     DBUS_SESSION_BUS_ADDRESS="$(cat /tmp/uitest_dbus.txt)" \
#     sh Tools/filemanager1-dbus-test.sh self-test

SERVICE="org.freedesktop.FileManager1"
OPATH="/org/freedesktop/FileManager1"
IFACE="org.freedesktop.FileManager1"

DBUS_SEND="dbus-send"
DBUS_MONITOR="dbus-monitor"
DRIVE_UI="/System/Library/Tools/drive_ui"
XDOTOOL="xdotool"
XPROP="xprop"

TESTDIR="${TMPDIR:-/tmp}/fm1-dbus-test.$$"
PLAIN="plain.txt"
FANCY="my file (1) & co.txt"
SUBDIR="subfolder"

ret=0
WSPID=""

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; ret=1; }

# The interface belongs to whichever Workspace owns the bus name; a second
# Workspace (an isolated uitest session, say) must not be inspected instead.
resolve_workspace_pid() {
  WSPID=$($DBUS_SEND --session --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID \
    string:"$SERVICE" 2>/dev/null | tail -1 | awk '{print $NF}' | tr -dc '0-9')
  [ -n "$WSPID" ]
}

# Ground truth for "a viewer is really on screen".  The DriveUI tree keeps
# listing an NSWindow after its viewer was closed, so it cannot answer this.
window_id_for() {
  $XPROP -root _NET_CLIENT_LIST 2>/dev/null | sed 's/.*# //' | tr ',' '\n' | \
  while read -r wid; do
    wid=$(echo $wid)
    [ -z "$wid" ] && continue
    name=$($XPROP -id "$wid" _NET_WM_NAME 2>/dev/null | sed 's/^_NET_WM_NAME[^=]*= //')
    [ "$name" = "\"$1\"" ] && { echo "$wid"; break; }
  done
}

# Selection is read from each file icon's own -isSelected (DriveUI "props"
# state) rather than from the label editor: resizing a viewer - which the
# window manager does right after mapping a new one - tears the editor down
# while the icon stays selected.  Icons in the path bar are skipped, they
# mirror the selection instead of holding it.  Several selected names are
# joined with "|".
selected_name_in_window() {
  $DRIVE_UI --pid "$WSPID" get_full_tree 2>/dev/null | \
    awk -F'\t' -v w="$1" '
      { cls[$1] = $2 }
      $10==w && $2=="FSNIcon" && cls[$1 - 1]=="GWViewerIconsView" { print $9 "\t" $3 }' | \
  while IFS="$(printf '\t')" read -r id name; do
    case "$($DRIVE_UI --pid "$WSPID" props "$id" 2>/dev/null)" in
      *state=1*) printf '%s\n' "$name" ;;
    esac
  done | paste -sd '|' -
}

# Top edge (GNUstep y-up) of a widget's on-screen rect, as one number.
screen_top_of() {
  $DRIVE_UI --pid "$WSPID" get_full_tree 2>/dev/null | \
    awk -F'\t' -v w="$1" -v c="$2" '$10==w && $2==c {
      split($6, f, "[=;]")
      printf "%d\n", f[4] + f[8]
      exit
    }'
}

# The scrolled content of a viewer, whichever view type it is showing.
content_top() {
  t=$(screen_top_of "$1" GWViewerListView)
  [ -n "$t" ] || t=$(screen_top_of "$1" GWViewerIconsView)
  echo "$t"
}

viewport_top() { screen_top_of "$1" GWViewerScrollView; }

wait_for_content_scrolled() {
  i=0
  while [ $i -lt 40 ]; do
    c=$(content_top "$1")
    v=$(viewport_top "$1")
    [ -n "$c" ] && [ -n "$v" ] && [ $((c - v)) -gt 8 ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

wait_for_content_at_top() {
  i=0
  while [ $i -lt 40 ]; do
    c=$(content_top "$1")
    v=$(viewport_top "$1")
    [ -n "$c" ] && [ -n "$v" ] && [ $((c - v)) -le 8 ] && [ $((c - v)) -ge -8 ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

wait_for_window() {
  i=0
  while [ $i -lt 40 ]; do
    [ -n "$(window_id_for "$1")" ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

wait_for_no_window() {
  i=0
  while [ $i -lt 40 ]; do
    [ -z "$(window_id_for "$1")" ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

wait_for_selection() {
  i=0
  while [ $i -lt 40 ]; do
    [ "$(selected_name_in_window "$1")" = "$2" ] && return 0
    sleep 0.5
    i=$((i + 1))
  done
  return 1
}

# Percent-encode every byte outside the unreserved set, the way a browser
# builds the file: URI it hands to ShowItems.
uri_for() {
  printf '%s' "$1" | od -An -tx1 -v | tr -s ' ' '\n' | grep -v '^$' | \
  while read -r byte; do
    c=$(printf "\\$(printf '%03o' "0x$byte")")
    case "$c" in
      [-A-Za-z0-9._~/]) printf '%s' "$c" ;;
      *) printf '%%%s' "$byte" ;;
    esac
  done
  echo ""
}

call() {
  method="$1"
  shift
  $DBUS_SEND --session --print-reply --dest="$SERVICE" --type=method_call \
    "$OPATH" "$IFACE.$method" "$@" >/dev/null 2>&1
}

show_items() { call ShowItems array:string:"file://$(uri_for "$1")" string:""; }
show_folders() { call ShowFolders array:string:"file://$(uri_for "$1")" string:""; }

# A viewer must be closed through the app's own File/Close Window: destroying
# the X window behind Workspace's back (xdotool windowclose) leaves the
# NSWindow alive and the manager still holding the viewer, which is a state no
# real close ever produces and would make the next test lie.
close_viewer() {
  wid=$(window_id_for "$1")
  [ -n "$wid" ] || return 0
  $XDOTOOL windowactivate "$wid" 2>/dev/null
  sleep 1
  $DRIVE_UI --pid "$WSPID" menu_select "File/Close Window" >/dev/null 2>&1
  wait_for_no_window "$1" || return 1
  # The X window is gone before Workspace has finished tearing the viewer
  # down; revealing into the folder during that window would race the close.
  sleep 2
}

cleanup() {
  [ -n "$WSPID" ] && {
    close_viewer "$BASE"
    close_viewer "$SUBDIR"
    close_viewer many
  }
  rm -rf "$TESTDIR"
}

CMD="${1:-self-test}"

case "$CMD" in
  monitor)
    echo "Watching for $IFACE calls - now click \"Show in folder\" in the app."
    echo "Nothing printed means the app never asks the file manager at all."
    exec $DBUS_MONITOR --session "interface='$IFACE'"
    ;;

  show)
    [ -n "$2" ] || { echo "usage: $0 show <path>"; exit 2; }
    P=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
    echo "ShowItems file://$(uri_for "$P")"
    show_items "$P"
    echo "exit=$?"
    exit 0
    ;;

  self-test) ;;
  *) echo "usage: $0 [self-test|monitor|show <path>]"; exit 2 ;;
esac

echo "=== org.freedesktop.FileManager1 self-test ==="

echo ""
echo "[PREREQ] Bus name $SERVICE is owned"
if resolve_workspace_pid; then
  pass "owned by PID $WSPID ($(ps -o comm= -p "$WSPID" 2>/dev/null))"
else
  fail "$SERVICE has no owner - is Workspace running on this session bus?"
  exit 1
fi

echo ""
echo "[PREREQ] DriveUI snapshot of PID $WSPID"
if [ -S "/tmp/driveui.$WSPID.sock" ] &&
   [ "$($DRIVE_UI --pid "$WSPID" get_full_tree 2>/dev/null | wc -l)" -gt 1 ]; then
  pass "widget tree readable"
else
  fail "no DriveUI socket for PID $WSPID - the UI cannot be verified"
  exit 1
fi

trap cleanup EXIT INT TERM
mkdir -p "$TESTDIR/$SUBDIR" || exit 1
echo plain > "$TESTDIR/$PLAIN"
echo fancy > "$TESTDIR/$FANCY"
echo sub > "$TESTDIR/$SUBDIR/nested.txt"
BASE=$(basename "$TESTDIR")

echo ""
echo "[TEST 1] ShowItems opens the parent folder and selects the item"
show_items "$TESTDIR/$PLAIN"
if wait_for_window "$BASE"; then
  pass "viewer window '$BASE' is on screen"
  if wait_for_selection "$BASE" "$PLAIN"; then
    pass "'$PLAIN' is selected"
  else
    fail "'$PLAIN' not selected (selection is '$(selected_name_in_window "$BASE")')"
  fi
else
  fail "no viewer window '$BASE' appeared"
fi

echo ""
echo "[TEST 2] ShowItems on an already-open viewer moves the selection"
show_items "$TESTDIR/$FANCY"
if wait_for_selection "$BASE" "$FANCY"; then
  pass "percent-encoded name '$FANCY' is selected"
else
  fail "'$FANCY' not selected (selection is '$(selected_name_in_window "$BASE")')"
fi

echo ""
echo "[TEST 3] ShowItems on a folder selects it in its parent"
show_items "$TESTDIR/$SUBDIR"
if wait_for_selection "$BASE" "$SUBDIR"; then
  pass "'$SUBDIR' is selected in '$BASE'"
else
  fail "'$SUBDIR' not selected (selection is '$(selected_name_in_window "$BASE")')"
fi

echo ""
echo "[TEST 4] ShowItems reopens the viewer after it was closed"
if close_viewer "$BASE"; then
  show_items "$TESTDIR/$PLAIN"
  if ! wait_for_window "$BASE"; then
    fail "viewer window '$BASE' did not reopen"
  elif wait_for_selection "$BASE" "$PLAIN"; then
    pass "viewer reopened with '$PLAIN' selected"
  else
    fail "viewer reopened but '$PLAIN' is not selected (selection is '$(selected_name_in_window "$BASE")')"
  fi
else
  fail "could not close viewer window '$BASE' to test the reopen"
fi

echo ""
echo "[TEST 5] ShowFolders opens the folder itself"
show_folders "$TESTDIR/$SUBDIR"
if wait_for_window "$SUBDIR"; then
  pass "viewer window '$SUBDIR' is on screen"
else
  fail "no viewer window '$SUBDIR' appeared"
fi

echo ""
echo "[TEST 6] ShowItems for a nonexistent file is a no-op, not a crash"
before="$WSPID"
show_items "$TESTDIR/does-not-exist.txt"
sleep 1
if resolve_workspace_pid && [ "$WSPID" = "$before" ]; then
  pass "Workspace survived and still owns $SERVICE (PID $WSPID)"
else
  fail "Workspace died or lost $SERVICE"
fi

echo ""
echo "[TEST 7] ShowItems scrolls the item into view in an already-open viewer"
MANY="$TESTDIR/many"
mkdir -p "$MANY"
i=1
while [ $i -le 200 ]; do
  printf '%s\n' x > "$MANY/$(printf 'file-%03d.txt' $i)"
  i=$((i + 1))
done
echo first > "$MANY/aaa-first.txt"
echo last > "$MANY/zzz-last.txt"
# Revealing an item far down the list must scroll the content away from the
# top; revealing the first one must bring it back.  Comparing the content's
# top edge with the viewport's works for the icon view and the list view
# alike, so the check does not depend on which one the folder opens in.
show_items "$MANY/zzz-last.txt"
if ! wait_for_window many; then
  fail "no viewer window 'many' appeared"
elif wait_for_content_scrolled many; then
  pass "'zzz-last.txt' was scrolled into view"
  # The case a browser's "Show in folder" hits in practice: the viewer is
  # already open, and showing at the wrong end of a long folder.
  show_items "$MANY/aaa-first.txt"
  if wait_for_content_at_top many; then
    pass "'aaa-first.txt' was scrolled into view"
  else
    fail "'aaa-first.txt' was not scrolled into view (content top $(content_top many), viewport top $(viewport_top many))"
  fi
else
  fail "'zzz-last.txt' was not scrolled into view (content top $(content_top many), viewport top $(viewport_top many))"
fi

echo ""
if [ $ret -eq 0 ]; then
  echo "=== all checks passed ==="
else
  echo "=== FAILURES ==="
fi
exit $ret
