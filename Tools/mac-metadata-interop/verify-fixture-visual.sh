#!/usr/bin/env bash
# =============================================================================
# verify-fixture-visual.sh - ship the real Mac-produced fixtures back to the
# Mac, merge their ._ sidecars with dot_clean -m, open them in Finder, and
# capture the LOCAL TigerVNC window (which shows the Mac's screen) so we can
# eyeball labels/tags/comments.
# =============================================================================
#
# Companion to verify-visual.sh (which tests Gershwin-written sidecars).  This
# one tests the fixtures themselves (file01..file07 from Tests/GWMetadata/
# interop/fixtures), i.e. the bytes macOS produced that the hermetic tests
# parse.  If Finder renders them the way MANIFEST.plist claims, the parser's
# ground truth is trustworthy.
#
# NOTES / gotchas learned 2026-08-24:
#   * `scp -r dir/.` SILENTLY SKIPS dotfiles (the ._ sidecars), so the
#     metadata never arrives.  We ship a tar instead.
#   * Mac-side `screencapture` returns 0 but writes nothing when driven over
#     SSH (Screen Sharing capture protection blocks window-server access from
#     a non-Aqua session).  We therefore capture the LOCAL TigerVNC viewer
#     window with ImageMagick `import` instead - that is the real eyeball.
#   * `dot_clean -m` STRIPS com.apple.quarantine, so file07 will appear
#     un-quarantined.  That is itself a finding (see INTEROP_VLC_TESTING.md).
#
# Requires: MAC_HOST / MAC_USER / MAC_PASS env vars (fall back to the
# documented Mac mini user/user).  A TigerVNC viewer for the Mac must be open
# on the LOCAL DISPLAY (:0) for the screenshot to be meaningful.
# =============================================================================

set -u
err() { echo "verify-fixture-visual: $*" >&2; exit 1; }

MAC_HOST="${MAC_HOST:-Users-Mac-mini.local}"
MAC_USER="${MAC_USER:-user}"
MAC_PASS="${MAC_PASS:-user}"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 || err "sshpass not found"
command -v import       >/dev/null 2>&1 || err "ImageMagick 'import' not found (needed for local VNC capture)"
command -v xdotool      >/dev/null 2>&1 || true   # optional, for window capture

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$ROOT_DIR/Tests/GWMetadata/interop/fixtures"
[ -d "$FIXTURES" ] || err "fixtures dir not found: $FIXTURES"
OUT="$ROOT_DIR/fixture-visual.png"

FILES="file01_finderinfo.txt file02_resourcefork.txt file03_tags.txt \
file04_comment.txt file05_combined.txt file06_control.txt file07_quarantine.txt \
MANIFEST.plist"

# --- assemble data files + their ._ sidecars into a tar (preserves dotfiles) ---
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SEND="$WORK/mac-fix"
mkdir -p "$SEND"
for f in $FILES; do
  [ -f "$FIXTURES/$f" ] || err "missing fixture $f"
  cp "$FIXTURES/$f" "$SEND/"
  [ -f "$FIXTURES/._$f" ] && cp "$FIXTURES/._$f" "$SEND/"
done
tar czf "$WORK/mac-fix.tar.gz" -C "$SEND" .

echo "verify-fixture-visual: shipping tar to $MAC_HOST ..."
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS "$WORK/mac-fix.tar.gz" \
  "${REMOTE}:/tmp/gw_fix.tar.gz" || err "scp failed"

echo "verify-fixture-visual: merging sidecars and opening in Finder ..."
"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<'REMOTE'
set -e
cd /tmp && rm -rf gw_fix && mkdir gw_fix && tar xzf gw_fix.tar.gz -C gw_fix
# dot_clean -m (copyfile) STRIPS com.apple.quarantine, and the tar step does not
# carry xattrs either, so the captured-on-Mac value would be empty.  The
# canonical quarantine string is recorded in MANIFEST.plist by generate-fixtures,
# so read it from there and re-apply after the merge.
Q=$(python -c "import plistlib; print plistlib.readPlist('/tmp/gw_fix/MANIFEST.plist')['file07_quarantine.txt'].get('quarantine','')" 2>/dev/null || true)
dot_clean -m /tmp/gw_fix
DEST="$HOME/Desktop/gw-fixture-check"
rm -rf "$DEST"
mv /tmp/gw_fix "$DEST"
rm -f "$DEST/MANIFEST.plist"
# Re-apply quarantine so file07 shows the Gatekeeper badge on the real Mac.
if [ -n "$Q" ]; then
  xattr -w com.apple.quarantine "$Q" "$DEST/file07_quarantine.txt"
fi
defaults write com.apple.finder AppleShowAllFiles -bool true
killall Finder 2>/dev/null || true
sleep 2
open "$DEST"
rm -f /tmp/gw_fix.tar.gz
REMOTE

echo "verify-fixture-visual: capturing local TigerVNC window ..."
WIN="$(xdotool search --class xtigervncviewer 2>/dev/null | head -1)"
if [ -n "$WIN" ]; then
  import -window "$WIN" "$OUT" && echo "verify-fixture-visual: saved $OUT (window)"
else
  import -window root "$OUT" && echo "verify-fixture-visual: saved $OUT (root)"
fi
echo "verify-fixture-visual: open $OUT and compare labels/tags/comments to MANIFEST.plist"
