#!/usr/bin/env bash
# =============================================================================
# verify-alias-reverse.sh — prove macOS resolves a Gershwin-written alias.
# =============================================================================
#
# The FORWARD interop (Mac alias -> FSNAlias parse) is exercised by the
# hermetic t_FSNAliasInterop.m.  This script proves the REVERSE: that an alias
# record FSNAlias writes is understood by a real Mac.
#
# Steps:
#   1. On Linux, build gw-alias-writer (links -lFSNode) and write a Gershwin
#      alias for <targetPath> (a file that must exist on BOTH boxes).
#   2. Ship the data-fork 'alis' record to the Mac.
#   3. On the Mac, wrap those bytes into a real resource-fork 'alis' resource
#      (pure-Python, no third-party deps) and let macOS resolve it.
#   4. Assert the resolved path equals <targetPath>.
#
# Usage:
#   MAC_HOST=... MAC_USER=... MAC_PASS=... ./verify-alias-reverse.sh [targetPath]
#
# -----------------------------------------------------------------------------
# REQUIRED ENV (never commit): MAC_HOST, MAC_USER, MAC_PASS
# -----------------------------------------------------------------------------

set -u
err() { echo "verify-alias-reverse: $*" >&2; exit 1; }

[ -n "${MAC_HOST:-}" ]  || err "MAC_HOST is not set"
[ -n "${MAC_USER:-}" ]  || err "MAC_USER is not set"
[ -n "${MAC_PASS:-}" ]  || err "MAC_PASS is not set"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 || err "sshpass not found"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-/tmp/gw_alias_reverse_target.txt}"

# --- 1. Build the writer and produce a Gershwin alias ------------------------
[ -f /System/Library/Makefiles/GNUstep.sh ] \
  || err "GNUstep.sh not found - run on the Gershwin build host"
# shellcheck disable=SC1091
source /System/Library/Makefiles/GNUstep.sh
echo "verify-alias-reverse: building gw-alias-writer ..."
make -C "$SCRIPT_DIR" >/tmp/gw-alias-writer.build.log 2>&1 \
  || { cat /tmp/gw-alias-writer.build.log; err "build failed"; }
WRITER="$SCRIPT_DIR/obj/gw-alias-writer"
[ -x "$WRITER" ] || err "gw-alias-writer not built"

# The target must exist locally (FSNAlias reads it to capture the path/kind).
mkdir -p "$(dirname "$TARGET")" || err "cannot create local target dir"
[ -e "$TARGET" ] || printf 'reverse interop target\n' > "$TARGET"

echo "verify-alias-reverse: writing Gershwin alias for $TARGET ..."
ALIAS_PATH="$("$WRITER" "$TARGET" /tmp)" || err "gw-alias-writer failed"
[ -f "$ALIAS_PATH" ] || err "alias file not produced"
ALIAS_DIR="$(dirname "$ALIAS_PATH")"
ALIAS_NAME="$(basename "$ALIAS_PATH")"
SIDECAR_PATH="$ALIAS_DIR/._$ALIAS_NAME"
[ -f "$SIDECAR_PATH" ] || err "AppleDouble sidecar not produced"

# --- 2. Make the target exist on the Mac too ---------------------------------
"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" \
  "mkdir -p \"$(dirname "$TARGET")\" && printf 'reverse interop target\n' > \"$TARGET\"" \
  || err "cannot create target on Mac"

# --- 3+4. Ship the alias + its AppleDouble sidecar, merge and resolve ---------
echo "verify-alias-reverse: shipping alias + sidecar to Mac and resolving ..."
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS "$ALIAS_PATH" \
  "${REMOTE}:/tmp/gw_alias_rev.alias" || err "scp failed"
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS "$SIDECAR_PATH" \
  "${REMOTE}:/tmp/._gw_alias_rev.alias" || err "scp sidecar failed"

RESULT="$("$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<EOF
set -e
ALIAS="/tmp/gw_alias_rev.alias"
SIDECAR="/tmp/._gw_alias_rev.alias"
python - "\$ALIAS" "\$SIDECAR" <<'PY'
import sys, struct, xattr
alias, sidecar = sys.argv[1], sys.argv[2]
with open(sidecar, "rb") as fh:
    blob = fh.read()
assert blob[:4] == b"\x00\x05\x16\x07", "not AppleDouble: %r" % blob[:4]
count = struct.unpack(">H", blob[24:26])[0]
off = 26
entries = {}
for i in range(count):
    eid = struct.unpack(">I", blob[off:off+4])[0]
    eoff = struct.unpack(">I", blob[off+4:off+8])[0]
    elen = struct.unpack(">I", blob[off+8:off+12])[0]
    entries[eid] = blob[eoff:eoff+elen]
    off += 12
fi = entries.get(9)
rf = entries.get(2)
assert fi is not None and rf is not None, "missing entries"
xattr.setxattr(alias, "com.apple.FinderInfo", fi)
xattr.setxattr(alias, "com.apple.ResourceFork", rf)
print("applied rsrc %d, finderinfo %d" % (len(rf), len(fi)))
PY
# Let macOS resolve the freshly built alias file natively.
osascript -e "POSIX path of (original item of (alias file (POSIX file \"\$ALIAS\")))"
EOF
)" || err "Mac-side resolution failed"

# --- Assert ------------------------------------------------------------------
RESOLVED="$(echo "$RESULT" | tail -1 | tr -d '\r')"
if [ "$RESOLVED" = "$TARGET" ]; then
  echo "verify-alias-reverse: PASS - macOS resolved Gershwin alias to $TARGET"
  exit 0
else
  echo "verify-alias-reverse: FAIL - resolved '$RESOLVED' != expected '$TARGET'"
  exit 1
fi
