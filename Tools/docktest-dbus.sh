#!/bin/sh
# Test Unity LauncherEntry D-Bus protocol against the Workspace Dock
# Usage: ./docktest-dbus.sh [app_id] [command]
#   app_id     default: Brave Origin (must match a Dock icon's appName)
#   command    badge <n> | progress <0.0-1.0> | urgent | clear | all
#              self-test   Launch BadgeTest, set badge+progress+urgent, verify logs

APP="${1:-Brave Origin}"
shift 2>/dev/null || true
CMD="${1:-self-test}"

DBUS_SEND="/bin/dbus-send"
SLEEP="/bin/sleep"
SEQ="/usr/bin/seq"
KILL="/bin/kill"
PGREP="/usr/bin/pgrep"
GREP="/bin/grep"

SERVICE="com.canonical.Unity.LauncherEntry"
OPATH="/com/canonical/unity/launcherentry"
IFACE="com.canonical.Unity.LauncherEntry"

WS_LOG="/tmp/workspace.log"

# Verify D-Bus service is registered
check_service() {
  $DBUS_SEND --session --dest=org.freedesktop.DBus --print-reply \
    /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null \
    | $GREP -q "$SERVICE"
}

# Check workspace log for a pattern
check_log() {
  if [ -f "$WS_LOG" ]; then
    $GREP -q "$1" "$WS_LOG" 2>/dev/null
  else
    return 1
  fi
}

dbsend() {
  $DBUS_SEND --session --dest="$SERVICE" --type=method_call "$OPATH" "$IFACE.Update" "$@"
}

# Locate BadgeTest.app
find_badgetest() {
  for d in \
    "/Developer/Library/Sources/gershwin-workspace/Tools/BadgeTest/BadgeTest.app" \
    "./BadgeTest.app" \
    "../BadgeTest/BadgeTest.app"; do
    if [ -d "$d" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}

init_ret=0

case "$CMD" in
  badge)
    VAL="${2:-5}"
    echo "Setting badge count=$VAL on $APP"
    dbsend string:"$APP" \
      "dict:string:variant:count,int64:$VAL,count-visible,boolean:true"
    echo "exit=$?"
    ;;
  progress)
    VAL="${2:-0.5}"
    echo "Setting progress=$VAL on $APP"
    dbsend string:"$APP" \
      "dict:string:variant:progress,double:$VAL,progress-visible,boolean:true"
    echo "exit=$?"
    ;;
  urgent)
    echo "Making $APP urgent"
    dbsend string:"$APP" \
      "dict:string:variant:urgent,boolean:true"
    echo "exit=$?"
    ;;
  clear)
    echo "Clearing all indicators on $APP"
    dbsend string:"$APP" \
      "dict:string:variant:count-visible,boolean:false,progress-visible,boolean:false,urgent,boolean:false"
    echo "exit=$?"
    ;;
  all)
    echo "Setting all indicators on $APP (count=7, progress=0.75, urgent)"
    dbsend string:"$APP" \
      "dict:string:variant:count,int64:7,count-visible,boolean:true,progress,double:0.75,progress-visible,boolean:true,urgent,boolean:true"
    $SLEEP 3
    echo "Clearing urgent"
    dbsend string:"$APP" "dict:string:variant:urgent,boolean:false"
    $SLEEP 2
    echo "Animating progress 0.0 -> 1.0"
    for p in $($SEQ 0.0 0.05 1.0); do
      dbsend string:"$APP" \
        "dict:string:variant:progress,double:$p,progress-visible,boolean:true"
    done
    $SLEEP 1
    echo "Clearing all"
    dbsend string:"$APP" \
      "dict:string:variant:count-visible,boolean:false,progress-visible,boolean:false,urgent,boolean:false"
    echo "exit=$?"
    ;;
  self-test)
    echo "=== DockService D-Bus Self-Test ==="
    echo ""
    echo "[PREREQ] Checking Workspace D-Bus service..."
    if ! check_service; then
      echo "  FAIL: $SERVICE not found on D-Bus session bus."
      echo "  Is Workspace running? Was it built with --enable-dbus?"
      init_ret=1
    else
      echo "  OK: $SERVICE is registered on the bus."
    fi

    echo ""
    echo "[PREREQ] Checking $WS_LOG..."
    if [ ! -f "$WS_LOG" ]; then
      echo "  WARN: $WS_LOG not found. Log verification will be skipped."
    else
      echo "  OK: $WS_LOG exists."
    fi

    # Locate BadgeTest
    BT=$(find_badgetest)
    if [ -z "$BT" ]; then
      echo ""
      echo "[WARN] BadgeTest.app not found. Skipping app launch (using pinned icons)."
      BT=""
    fi

    # Launch BadgeTest if found
    if [ -n "$BT" ]; then
      echo ""
      echo "[STEP 1] Launching BadgeTest..."
      $KILL -9 $($PGREP BadgeTest) 2>/dev/null || true
      $SLEEP 1
      "$BT/BadgeTest" &
      BT_PID=$!
      $SLEEP 3
      if $PGREP BadgeTest >/dev/null 2>&1; then
        echo "  OK: BadgeTest running (PID $(pgrep BadgeTest 2>/dev/null))."
      else
        echo "  WARN: BadgeTest exited or failed to launch."
      fi
    fi

    # STEP 2: Set badge count via D-Bus
    echo ""
    echo "[STEP 2] Setting badge count=42 on $APP..."
    dbsend string:"$APP" \
      "dict:string:variant:count,int64:42,count-visible,boolean:true"
    RC=$?
    if [ $RC -ne 0 ]; then
      echo "  FAIL: dbus-send exited $RC"
      init_ret=1
    else
      echo "  OK: dbus-send exited 0"
    fi

    # STEP 3: Set progress bar via D-Bus
    echo ""
    echo "[STEP 3] Setting progress=0.66 on $APP..."
    dbsend string:"$APP" \
      "dict:string:variant:progress,double:0.66,progress-visible,boolean:true"
    RC=$?
    if [ $RC -ne 0 ]; then
      echo "  FAIL: dbus-send exited $RC"
      init_ret=1
    else
      echo "  OK: dbus-send exited 0"
    fi

    # STEP 4: Set urgent via D-Bus
    echo ""
    echo "[STEP 4] Setting urgent on $APP..."
    dbsend string:"$APP" "dict:string:variant:urgent,boolean:true"
    RC=$?
    if [ $RC -ne 0 ]; then
      echo "  FAIL: dbus-send exited $RC"
      init_ret=1
    else
      echo "  OK: dbus-send exited 0"
    fi

    # STEP 5: Verify NSWarnMLog in workspace.log
    echo ""
    echo "[STEP 5] Verifying DockIcon NSWarnMLog messages..."
    $SLEEP 1
    found=0
    expected=5
    for pat in \
      "DockIcon\[$APP\] badgeCount -> 42" \
      "DockIcon\[$APP\] countVisible -> 1" \
      "DockIcon\[$APP\] progressValue -> 0.660" \
      "DockIcon\[$APP\] progressVisible -> 1" \
      "DockIcon\[$APP\] urgent -> 1"; do
      if check_log "$pat"; then
        found=$((found + 1))
      fi
    done
    if [ $found -eq $expected ]; then
      echo "  OK: All $expected NSWarnMLog lines found in $WS_LOG."
    else
      echo "  PARTIAL: Found $found/$expected NSWarnMLog lines in $WS_LOG."
      echo "  Expected patterns:"
      for pat in \
        "DockIcon[$APP] badgeCount -> 42" \
        "DockIcon[$APP] countVisible -> 1" \
        "DockIcon[$APP] progressValue -> 0.660" \
        "DockIcon[$APP] progressVisible -> 1" \
        "DockIcon[$APP] urgent -> 1"; do
        if check_log "$pat"; then
          echo "    [FOUND] $pat"
        else
          echo "    [MISS]  $pat"
        fi
      done
      init_ret=1
    fi

    # Verify D-Bus service still visible
    echo ""
    echo "[STEP 6] Re-checking D-Bus service..."
    if check_service; then
      echo "  OK: $SERVICE still registered on the bus."
    else
      echo "  FAIL: $SERVICE lost from bus."
      init_ret=1
    fi

    # Summary
    echo ""
    if [ $init_ret -eq 0 ]; then
      echo "=== SELF-TEST PASSED ==="
    else
      echo "=== SELF-TEST FAILED ==="
      exit $init_ret
    fi
    ;;
  *)
    echo "Usage: $0 [app_id] <command>"
    echo "Commands:"
    echo "  badge <n>         Set badge count (default 5)"
    echo "  progress <0-1>    Set progress (default 0.5)"
    echo "  urgent            Set urgent glow"
    echo "  clear             Clear all indicators"
    echo "  all               Demo all indicators"
    echo "  self-test         Launch BadgeTest, set badge+progress+urgent (default)"
    exit 1
    ;;
esac
