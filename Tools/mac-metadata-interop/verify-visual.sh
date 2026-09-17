#!/usr/bin/env bash
# =============================================================================
# verify-visual.sh — human-visible check of Gershwin-written Finder metadata
# =============================================================================
#
# Writes a set of files whose ONLY metadata is the Finder colour label
# (one file per colour, all visible), ships them to the Mac, ingests with
# dot_clean, drops the folder on the Desktop, opens it in Finder and takes
# a screenshot.  The screenshot lands next to this script as visual.png -
# open it and confirm seven coloured tiles (red..grey).
#
# Requires: MAC_HOST / MAC_USER / MAC_PASS env vars, a logged-in GUI
# session on the Mac (Finder + screencapture target the console session).
# =============================================================================

set -u
err() { echo "verify-visual: $*" >&2; exit 1; }

[ -n "${MAC_HOST:-}" ] || err "MAC_HOST is not set"
[ -n "${MAC_USER:-}" ] || err "MAC_USER is not set"
[ -n "${MAC_PASS:-}" ] || err "MAC_PASS is not set"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 || err "sshpass not found"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "verify-visual: building writer ..."
set +u; . /System/Library/Makefiles/GNUstep.sh; set -u
clang `gnustep-config --objc-flags` -I/System/Library/Headers \
      -I"${SCRIPT_DIR}/../../GWMetadata" \
      "${SCRIPT_DIR}/write-sidecars.m" -o "${SCRIPT_DIR}/write-sidecars" \
      `gnustep-config --base-libs` -lgnustep-gui -larchive -Wno-deprecated \
  || err "build failed"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
"${SCRIPT_DIR}/write-sidecars" "${WORK}/visual" \
  "${WORK}/visual.zip" with-visual || err "writer failed"
(cd "$WORK" && zip -qr visual.zip visual) || err "zip failed"

"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS "${WORK}/visual.zip" \
  "${REMOTE}:/tmp/gw_visual.zip" || err "scp failed"

echo "verify-visual: ingesting on Mac and opening Finder ..."
"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<'REMOTE'
set -e
cd /tmp && rm -rf gw_visual && unzip -q gw_visual.zip -d gw_visual
DEST="$HOME/Desktop/gw-visual-check"
rm -rf "$DEST" && mv /tmp/gw_visual/visual "$DEST"
cd "$DEST" && find . -name "._*" -delete
dot_clean -m "$DEST" >/dev/null 2>&1 || true
sync
open "$DEST"
sleep 6
screencapture -x /tmp/gw_visual_shot.png
rm -rf /tmp/gw_visual /tmp/gw_visual.zip
REMOTE

"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS \
  "${REMOTE}:/tmp/gw_visual_shot.png" "${SCRIPT_DIR}/../../visual.png" \
  || err "could not fetch screenshot"
"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" \
  'rm -f /tmp/gw_visual_shot.png'

echo "verify-visual: screenshot saved to $(cd "${SCRIPT_DIR}/../.." && pwd)/visual.png"
echo "verify-visual: open it and check the seven label colours in Finder."
