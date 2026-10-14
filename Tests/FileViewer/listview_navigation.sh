#!/bin/sh
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# A file viewer window in List View, and in Icon View, must follow the folder
# the user opened inside it: window title, Go > Enclosing Folder and
# Go > Back all refer to the folder that is shown, not to the one the window
# was first opened on.
#
# Drives a Workspace that already runs in an isolated uitest slot; nothing
# here ever touches the display of the logged-in user.
#
#   sh Tests/FileViewer/listview_navigation.sh <slot>
#
# Needs: sudo, drive_ui, xdotool, a Workspace running as uitest<slot> on
# display :<slot> (see the gershwin-wm-headless-testing skill).  The window
# menu items are addressed by index because the menu is localized.

N=${1:?usage: listview_navigation.sh <slot>}
U=uitest$N
export DISPLAY=:$N
DUI=/System/Library/Tools/drive_ui
FIXTURE=/home/$U/lvnav
fails=0

P=$(pgrep -u "$U" -x Workspace) || { echo "no Workspace of $U"; exit 2; }
dui() { sudo -u "$U" env DISPLAY=:$N $DUI --pid "$P" "$@"; }

check() { # description, expected, actual
  if [ "$2" = "$3" ]; then echo "Passed test: $1"
  else echo "Failed test: $1 (expected '$2', got '$3')"; fails=$((fails + 1)); fi
}

titles() { dui get_full_tree | awk -F'\t' '$2 == "GWViewerWindow" { print $3 }'; }

# the viewer window opened on the fixture, whatever it is titled right now
viewer_title() { titles | head -1; }

menu_item() { dui menu_invoke "$@" >/dev/null; sleep 2; }

# Double click the first entry of the shown folder.  An icon view lists its
# icons in the tree; a list view does not list its rows, so the first row is
# found from the view's frame.
open_first_entry() { # view kind: list | icons
  sh_=$(xdotool getdisplaygeometry | cut -d' ' -f2)
  if [ "$1" = list ]; then
    frame=$(dui get_full_tree | awk -F'\t' '$2 == "GWViewerListView" { print $6; exit }')
  else
    frame=$(dui get_full_tree | awk -F'\t' '
      $2 == "GWViewerIconsView" { d = $1; seen = 1; next }
      seen && $1 <= d { seen = 0 }
      seen && $2 == "FSNIcon" { print $6; exit }')
  fi
  # {x = 199.2; y = 206.4; width = 900; height = 321.2}, bottom-up
  set -- $(echo "$frame" | sed 's/[a-z]* =//g; s/[{};]//g')
  if [ -z "$1" ]; then return; fi
  if [ "$kind" = list ]; then
    x=$(awk -v x="$1" 'BEGIN { printf "%d", x + 45 }')
    y=$(awk -v s="$sh_" -v y="$2" -v h="$4" 'BEGIN { printf "%d", s - (y + h) + 20 }')
  else
    x=$(awk -v x="$1" -v w="$3" 'BEGIN { printf "%d", x + w / 2 }')
    y=$(awk -v s="$sh_" -v y="$2" -v h="$4" 'BEGIN { printf "%d", s - (y + h / 2) }')
  fi
  xdotool mousemove "$x" "$y" click --repeat 2 --delay 80 1
  sleep 2
}

open_fixture() {
  # Open A through Go > Go To Folder (Cmd-Shift-G)
  xdotool mousemove 400 300 click 1; sleep 1
  xdotool keydown alt; xdotool key shift+g; xdotool keyup alt; sleep 2
  F=$(dui get_full_tree | awk -F'\t' '$2 == "CompletionField" { print $9; exit }')
  dui click "$F" >/dev/null
  dui type "$F" "$FIXTURE/A" >/dev/null
  dui press >/dev/null
  sleep 3
}

close_key_window() { menu_item 1 7; }

sudo -u "$U" sh -c "rm -rf $FIXTURE; mkdir -p $FIXTURE/A/B/C"

for kind in list icons; do
  open_fixture
  check "$kind view: window opens titled with the folder" "A" "$(viewer_title)"

  # View menu: "as Icons" is item 0, "as List" item 1
  if [ "$kind" = list ]; then menu_item 3 1; else menu_item 3 0; fi

  open_first_entry "$kind"
  check "$kind view: title follows the folder opened in place (B)" "B" "$(viewer_title)"

  open_first_entry "$kind"
  check "$kind view: title follows the next folder (C)" "C" "$(viewer_title)"

  # Go > Back (item 4/0) returns to B, Go > Forward (4/1) to C again
  menu_item 4 0
  check "$kind view: Back shows the previous folder (B)" "B" "$(viewer_title)"
  menu_item 4 1
  check "$kind view: Forward shows the next folder (C)" "C" "$(viewer_title)"

  # Go > Enclosing Folder (4/3) of the shown C: a browsing window goes up in
  # place - one window, retitled B - and Back returns to C
  menu_item 4 3
  check "$kind view: Enclosing Folder keeps one window" "1" "$(titles | wc -l)"
  check "$kind view: Enclosing Folder shows the parent of the shown folder (B)" \
        "B" "$(viewer_title)"
  menu_item 4 0
  check "$kind view: Back after Enclosing Folder returns to C" "C" \
        "$(viewer_title)"

  # Cmd-Up is the same action
  xdotool keydown alt; xdotool key Up; xdotool keyup alt; sleep 2
  check "$kind view: Cmd-Up keeps one window" "1" "$(titles | wc -l)"
  check "$kind view: Cmd-Up shows the parent (B)" "B" "$(viewer_title)"
  close_key_window
done

sudo -u "$U" rm -rf "$FIXTURE"
echo "failures: $fails"
[ "$fails" -eq 0 ]
