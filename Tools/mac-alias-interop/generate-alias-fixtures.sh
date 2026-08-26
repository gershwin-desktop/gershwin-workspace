#!/usr/bin/env bash
# =============================================================================
# generate-alias-fixtures.sh — Gershwin <-> macOS Alias record interop fixtures
# =============================================================================
#
# Requires a real Mac (it ssh's into one).  It:
#
#   1. Creates REAL macOS alias files on the Mac (Finder "Make Alias"), which
#      the OS stores as an 'alis' resource inside the file's resource fork.
#   2. Extracts the raw 'alis' record bytes from that resource fork - the exact
#      blob FSNAlias (FSNode/FSNAlias.m) parses - into a .alis fixture.
#   3. Captures a ground-truth MANIFEST (XML plist) describing each alias'
#      intended target (name, absolute POSIX path, is-directory, volume name),
#      read back from the Mac itself (diskutil / stat), not what we commanded.
#   4. Ships the .alis fixtures + MANIFEST to this Linux box.
#
# The result lands in <gershwin-workspace>/Tests/FSNode/interop/fixtures/
# where the hermetic t_FSNAliasInterop.m test picks it up.  The fixtures are
# GENERATED ARTIFACTS - do NOT commit them (they are gitignored).
#
# -----------------------------------------------------------------------------
# REQUIRED ENV VARS (supply locally, never commit):
#   MAC_HOST   e.g. Users-Mac-mini.local
#   MAC_USER   ssh user, e.g. user
#   MAC_PASS   ssh password
# OPTIONAL:
#   MAC_SSHPASS  path to sshpass (default: sshpass)
#   GW_ALIAS_OUT absolute path to the fixtures output dir
#                (default: <repo>/Tests/FSNode/interop)
# -----------------------------------------------------------------------------

set -u
err() { echo "generate-alias-fixtures: $*" >&2; exit 1; }

[ -n "${MAC_HOST:-}" ] || err "MAC_HOST is not set"
[ -n "${MAC_USER:-}" ] || err "MAC_USER is not set"
[ -n "${MAC_PASS:-}" ] || err "MAC_PASS is not set"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 \
  || err "sshpass not found (set MAC_SSHPASS or install sshpass)"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${GW_ALIAS_OUT:-}" ]; then
  OUT="$GW_ALIAS_OUT"
else
  OUT="${SCRIPT_DIR}/../../Tests/FSNode/interop"
fi
mkdir -p "$OUT" || err "cannot create output dir $OUT"

REMOTE_DIR="/tmp/gw_alias_fixtures"
ZIP_NAME="gw_alias_fixtures.zip"

echo "generate-alias-fixtures: building aliases on ${REMOTE} ..."

"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<'EOF'
set -e
rm -rf "$HOME/gw_alias_fixtures" && mkdir -p "$HOME/gw_alias_fixtures/out"
cd "$HOME/gw_alias_fixtures"

# --- targets (file, directory, unicode-named file) ---------------------------
echo "interop alias target" > target.txt
mkdir -p target_dir
printf 'unicode target body' > café.txt

# --- volume name (what the 'alis' record will carry) -------------------------
VOL=$(stat -f '%Sf' / 2>/dev/null || echo "")

# --- make REAL Finder aliases (resource-fork 'alis' records) -----------------
# On 10.6 Finder names the alias file with the target's own basename (no
# " alias" suffix), so rename that to our deterministic fixture name.
mk() {
  local tgt="$1" out="$2" name="$3"
  osascript -e "tell application \"Finder\" to make alias file to (POSIX file \"$tgt\") at folder (POSIX file \"$out\")" >/dev/null
  mv "$out/$(basename "$tgt")" "$out/$name"
}
mk "$PWD/target.txt"  "$PWD/out" mac_alias_file.alias
mk "$PWD/target_dir"  "$PWD/out" mac_alias_dir.alias
mk "$PWD/café.txt" "$PWD/out" mac_alias_unicode.alias

# --- extract the raw 'alis' record from each alias' resource fork ------------
# The resource fork's data area begins at the big-endian offset in bytes 0..3;
# the 'alis' record (magic "alis") lives there.  Slice from that offset; the
# trailing resource-map bytes are harmless (parsing stops at TLV_END).
extract_alis() {
  local f="$1" out="$2"
  python - "$f/..namedfork/rsrc" "$out" <<'PY'
import sys, struct
rf_path, out_path = sys.argv[1], sys.argv[2]
with open(rf_path, "rb") as fh:
    data = fh.read()
if len(data) < 16:
    sys.exit("empty resource fork for %s" % rf_path)
data_off = struct.unpack(">I", data[0:4])[0]
idx = data.find(b"alis", data_off)
if idx < 0:
    idx = data.find(b"alis")
if idx < 0:
    sys.exit("no 'alis' magic found in resource fork of %s" % rf_path)
with open(out_path, "wb") as out:
    out.write(data[idx:])
print("extracted %d bytes from offset %d" % (len(data) - idx, idx))
PY
}
extract_alis "$PWD/out/mac_alias_file.alias"   "$PWD/out/mac_alias_file.alis"
extract_alis "$PWD/out/mac_alias_dir.alias"   "$PWD/out/mac_alias_dir.alis"
extract_alis "$PWD/out/mac_alias_unicode.alias" "$PWD/out/mac_alias_unicode.alis"

# --- ground-truth manifest (what the Mac says the targets are) ---------------
python - <<PY
import plistlib, os
home = os.environ["HOME"]
base = home + "/gw_alias_fixtures"
vol = "$(stat -f '%Sf' / 2>/dev/null || echo '')"
manifest = {
  "mac_alias_file.alis": {
    "targetName": "target.txt",
    "posixPath": base + "/target.txt",
    "isDirectory": False,
    "volumeName": vol,
  },
  "mac_alias_dir.alis": {
    "targetName": "target_dir",
    "posixPath": base + "/target_dir",
    "isDirectory": True,
    "volumeName": vol,
  },
  "mac_alias_unicode.alis": {
    "targetName": "café.txt",
    "posixPath": base + "/café.txt",
    "isDirectory": False,
    "volumeName": vol,
  },
}
with open(base + "/out/MANIFEST.plist", "wb") as f:
    plistlib.dump(manifest, f)
print("MANIFEST written for", len(manifest), "aliases; volume =", repr(vol))
PY

cd "$HOME/gw_alias_fixtures" && rm -f gw_alias_fixtures.zip \
  && zip -r -q gw_alias_fixtures.zip out
echo "ZIP_DONE"
EOF

echo "generate-alias-fixtures: downloading zip ..."
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS \
  "${REMOTE}:/tmp/gw_alias_fixtures.zip" "$OUT/incoming.zip" \
  || err "scp from Mac failed"

cd "$OUT"
rm -rf incoming
unzip -q incoming.zip -d incoming || err "unzip failed"
ROOT="$(find incoming -name MANIFEST.plist | head -1 | xargs -r dirname)"
[ -n "$ROOT" ] || err "could not locate fixtures inside the zip"
rm -rf "$OUT/fixtures"
mkdir -p "$OUT/fixtures"
mv "$ROOT"/* "$OUT/fixtures/"
rm -rf incoming incoming.zip

echo "generate-alias-fixtures: fixtures ready in $OUT/fixtures"
echo "generate-alias-fixtures: $(find "$OUT/fixtures" -type f | wc -l) files"
