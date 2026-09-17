#!/usr/bin/env bash
# =============================================================================
# generate-fixtures.sh — Gershwin <-> macOS metadata interoperability fixtures
# =============================================================================
#
# This script REQUIRES a real Mac (it ssh's into one), so it lives in its own
# directory separate from the hermetic gnustep-tests.  It:
#
#   1. Creates fixture files on the Mac carrying REAL macOS metadata
#      (FinderInfo type/creator/flags/label, resource fork + custom icon,
#      Finder tags (_kMDItemUserTags), Finder comment (kMDItemFinderComment)),
#      using only native macOS tools (xattr, ..namedfork/rsrc, python, plutil).
#   2. Captures a ground-truth MANIFEST (XML plist) by reading the metadata
#      back from the Mac (mdls / xattr / plutil) — i.e. what macOS itself
#      reports, not what we commanded.
#   3. Packages the files with `ditto --sequesterRsrc`, which embeds the
#      metadata into real AppleDouble `._` sidecars inside the zip.
#   4. Ships the zip to this Linux box and unzips it, relocating the
#      `__MACOSX/._*` AppleDouble sidecars into plain `._*` files next to
#      each data file (the form GSFileMetadata expects).
#
# The result lands in <gershwin-workspace>/Tests/GWMetadata/interop/fixtures/
# where the hermetic test tools pick it up.  No secrets are stored here:
# connection details come from the environment (see REQUIRED ENV VARS).
#
# IMPORTANT: the resulting fixtures are generated artifacts.  Do NOT commit
# them (they are gitignored).  Re-run this script whenever macOS behavior
# changes or you add a fixture.
#
# -----------------------------------------------------------------------------
# REQUIRED ENV VARS (supply locally, never commit):
#   MAC_HOST   e.g. Users-Mac-mini.local   (no IP addresses in this script)
#   MAC_USER   ssh user, e.g. user
#   MAC_PASS   ssh password
# OPTIONAL:
#   MAC_SSHPASS path to sshpass binary (default: sshpass)
#   GW_INTEROP_OUT  absolute path to the fixtures output dir
#                    (default: <repo>/Tests/GWMetadata/interop/fixtures)
# -----------------------------------------------------------------------------

set -u
err() { echo "generate-fixtures: $*" >&2; exit 1; }

[ -n "${MAC_HOST:-}" ] || err "MAC_HOST is not set"
[ -n "${MAC_USER:-}" ] || err "MAC_USER is not set"
[ -n "${MAC_PASS:-}" ] || err "MAC_PASS is not set"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 \
  || err "sshpass not found (set MAC_SSHPASS or install sshpass)"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"

# Resolve output dir (default: the interop test dir in the repo tree; the
# script writes MANIFEST.plist and a fixtures/ subdir beneath it).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${GW_INTEROP_OUT:-}" ]; then
  OUT="$GW_INTEROP_OUT"
else
  OUT="${SCRIPT_DIR}/../../Tests/GWMetadata/interop"
fi
mkdir -p "$OUT" || err "cannot create output dir $OUT"

REMOTE_DIR="/tmp/gw_interop_fixtures"
ZIP_NAME="gw_interop_fixtures.zip"

# Spotlight only reports metadata for indexed locations, so build the
# fixtures inside the Mac user's home ($HOME is resolved on the remote
# side by its own shell), not in /tmp.
echo "generate-fixtures: building fixtures on ${REMOTE} ..."

# -----------------------------------------------------------------------------
# Step 1+2: build fixtures + manifest on the Mac.
# -----------------------------------------------------------------------------
"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<'EOF'
set -e
# Kill any stale zip first: if a later step fails, scp must not ship a
# leftover archive from a previous run.
rm -f /tmp/gw_interop_fixtures.zip
REMOTE_DIR="$HOME/gw_interop_fixtures"
rm -rf "$REMOTE_DIR" && mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"

# --- file01: classic FinderInfo (type/creator, red label, invisible) ---------
echo "fixture one" > file01_finderinfo.txt
python - <<'PY'
import xattr
fi = bytearray(32)
fi[0:4] = b"TEXT"
fi[4:8] = b"ttxt"
# kColor label is fdFlags bits 1-3 (label position n stored as n<<1).
# The *colour* assigned to each position depends on the OS label palette:
# Snow Leopard (10.6) uses the classic palette
#   1=Grey 2=Green 3=Purple 4=Blue 5=Orange 6=Red 7=Yellow,
# while modern macOS/Linux use 1=Red 2=Orange 3=Yellow 4=Green ...
# The label NUMBER is the portable interop unit; we pin the position that
# yields the intended colour on the reference 10.6 Mac.  "red label" =>
# position 6; kIsInvisible => bit 14 (0x4000).
# FinderInfo is big-endian on disk (TN1150): fdFlags is the 16-bit value at
# bytes 8-9, high byte first.
flags = (1 << 14) | (6 << 1)
fi[8] = (flags >> 8) & 0xFF
fi[9] = flags & 0xFF
xattr.setxattr("file01_finderinfo.txt", "com.apple.FinderInfo", bytes(fi))
PY

# --- file02: resource fork + custom icon flag --------------------------------
echo "fixture two" > file02_resourcefork.txt
python - <<'PY'
import xattr
fi = bytearray(32)
# kHasCustomIcon = bit 10 (0x0400).  FinderInfo is big-endian: fdFlags is the
# 16-bit value at bytes 8-9, high byte first.
flags = (1 << 10)
fi[8] = (flags >> 8) & 0xFF
fi[9] = flags & 0xFF
xattr.setxattr("file02_resourcefork.txt", "com.apple.FinderInfo", bytes(fi))
PY
# resource fork: a tiny but real 'icns'-less payload (8 known bytes)
printf 'CAFEBABE' > file02_resourcefork.txt/..namedfork/rsrc

# --- file03: Finder tags (binary plist _kMDItemUserTags) ---------------------
echo "fixture three" > file03_tags.txt
python - <<'PY'
import xattr, plistlib, subprocess, tempfile, os
tags = ["Red", "ProjectX"]
xml = plistlib.writePlistToString(tags)
# 10.6 plistlib writes XML; convert to the REAL binary plist macOS uses.
with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tf:
    tf.write(xml); path = tf.name
try:
    subprocess.check_call(["plutil", "-convert", "binary1", "-o",
                           path + ".bin", path])
    with open(path + ".bin", "rb") as f:
        blob = f.read()
finally:
    os.unlink(path); os.unlink(path + ".bin")
xattr.setxattr("file03_tags.txt", "com.apple.metadata:_kMDItemUserTags", blob)
PY

# --- file04: Finder comment (kMDItemFinderComment) ---------------------------
echo "fixture four" > file04_comment.txt
xattr -w com.apple.metadata:kMDItemFinderComment "interop test comment" file04_comment.txt

# --- file05: everything combined -------------------------------------------
echo "fixture five" > file05_combined.txt
python - <<'PY'
import xattr, plistlib, subprocess, tempfile, os
fi = bytearray(32)
fi[0:4] = b"TEXT"; fi[4:8] = b"ttxt"
# Label colour must agree with the leading user tag ("Green") so the fixture
# is self-consistent, exactly as Finder enforces on a real Mac.  On the
# reference 10.6 box the classic palette maps "Green" to label position 2, so
# we store (2 << 1); plus kHasCustomIcon (1<<10) + kIsInvisible (1<<14).
flags = (1 << 14) | (1 << 10) | (2 << 1)
fi[8] = (flags >> 8) & 0xFF; fi[9] = flags & 0xFF
xattr.setxattr("file05_combined.txt", "com.apple.FinderInfo", bytes(fi))
tags = ["Green", "Release"]
xml = plistlib.writePlistToString(tags)
with tempfile.NamedTemporaryFile(suffix=".xml", delete=False) as tf:
    tf.write(xml); path = tf.name
try:
    subprocess.check_call(["plutil", "-convert", "binary1", "-o",
                           path + ".bin", path])
    with open(path + ".bin", "rb") as f:
        blob = f.read()
finally:
    os.unlink(path); os.unlink(path + ".bin")
xattr.setxattr("file05_combined.txt", "com.apple.metadata:_kMDItemUserTags", blob)
xattr.setxattr("file05_combined.txt", "com.apple.metadata:kMDItemFinderComment",
               b"combined comment")
PY
printf 'DEADCODE' > file05_combined.txt/..namedfork/rsrc

# --- file07: quarantine record ----------------------------------------------
echo "fixture seven" > file07_quarantine.txt
python - <<'PY2'
import xattr, time
q = "0083;%x;Safari;12345678-90AB-CDEF-1234-567890ABCDEF" % int(time.time())
xattr.setxattr("file07_quarantine.txt", "com.apple.quarantine", q)
PY2

# --- file06: control (no metadata) ------------------------------------------
echo "fixture six (control)" > file06_control.txt

# --- Spotlight: force-import, then wait until the index catches up -----------
# New directories are not crawled instantly; importing each file directly
# works but also takes a cycle or two.  We poll on kMDItemDisplayName
# because it is always populated once indexed.
for f in *.txt; do
  mdimport "$REMOTE_DIR/$f" 2>/dev/null || true
done
for i in 1 2 3 4 5 6 7 8 9 10; do
  v=$(mdls -raw -name kMDItemDisplayName file01_finderinfo.txt 2>/dev/null)
  [ "$v" != "(null)" ] && [ -n "$v" ] && break
  for f in *.txt; do
    mdimport "$REMOTE_DIR/$f" 2>/dev/null || true
  done
  sleep 3
done

# --- capture ground-truth manifest ------------------------------------------
python - <<'PY'
import xattr, plistlib, subprocess, tempfile, os, binascii

def be32(b): return (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]
def be16(b, o): return (b[o] << 8) | b[o+1]

def read_binary_plist_tags(path):
    try:
        raw = xattr.getxattr(path, "com.apple.metadata:_kMDItemUserTags")
    except Exception:
        return None
    if not raw:
        return None
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tf:
        tf.write(raw); bp = tf.name
    try:
        xmlp = bp + ".xml"
        subprocess.check_call(["plutil", "-convert", "xml1", "-o", xmlp, bp])
        with open(xmlp) as f:
            data = plistlib.readPlist(f)
        return data
    except Exception as e:
        return None
    finally:
        for p in (bp, bp + ".xml"):
            try: os.unlink(p)
            except: pass

def rf_hex(path):
    try:
        with open(path + "/..namedfork/rsrc", "rb") as f:
            data = f.read()
            if len(data) == 0:
                return None
            return binascii.hexlify(data)
    except Exception:
        return None

files = ["file01_finderinfo.txt", "file02_resourcefork.txt",
         "file03_tags.txt", "file04_comment.txt",
         "file05_combined.txt", "file06_control.txt",
         "file07_quarantine.txt"]

manifest = {}
for fn in files:
    rec = {"filename": fn, "hasMetadata": False}
    # FinderInfo
    try:
        fi = xattr.getxattr(fn, "com.apple.FinderInfo")
    except Exception:
        fi = None
    if fi and len(fi) >= 32:
        fi = [ord(c) for c in fi]        # py2 xattr returns str
        rec["hasMetadata"] = True
        rec["typeCode"] = be32(fi[0:4])
        rec["creatorCode"] = be32(fi[4:8])
        flags = be16(fi, 8)
        rec["finderFlags"] = flags
        rec["labelNumber"] = (flags >> 1) & 0x7
        rec["invisible"] = bool(flags & (1 << 14))   # kIsInvisible 0x4000
        rec["customIcon"] = bool(flags & (1 << 10))   # kHasCustomIcon 0x0400
    # resource fork
    rfhex = rf_hex(fn)
    if rfhex:
        rec["hasMetadata"] = True
        rec["resourceForkHex"] = rfhex
    # tags
    tags = read_binary_plist_tags(fn)
    if tags:
        rec["hasMetadata"] = True
        rec["userTags"] = list(tags)
    # finder comment
    try:
        fc = xattr.getxattr(fn, "com.apple.metadata:kMDItemFinderComment")
    except Exception:
        fc = None
    if fc:
        rec["hasMetadata"] = True
        rec["finderComment"] = fc.decode("utf-8", "replace")
    # Spotlight (mdls) view of the same file - what a real Mac reports.
    # NOTE: on 10.6 an externally-set com.apple.metadata:kMDItemFinderComment
    # does NOT surface as kMDItemComment in the index (only comments set
    # through Finder itself do), so we record both and let the test assert
    # only what is present.  (no subprocess.check_output: python 2.6)
    # quarantine record (plain string as stored by copyfile)
    try:
        qv = xattr.getxattr(fn, "com.apple.quarantine")
    except Exception:
        qv = None
    if qv:
        rec["hasMetadata"] = True
        rec["quarantine"] = qv.rstrip("\x00")

    md = {}
    p = subprocess.Popen(["mdls", "-raw", "-name", "kMDItemComment",
                          "-name", "kMDItemContentType",
                          "-name", "kMDItemDisplayName", fn],
                         stdout=subprocess.PIPE)
    lines = p.communicate()[0].decode("utf-8").split("\x00")
    if len(lines) >= 3 and lines[0] != "(null)" and lines[0] != "":
        md["kMDItemComment"] = lines[0]
        rec["hasMetadata"] = True
    if len(lines) >= 2 and lines[1] != "(null)":
        md["kMDItemContentType"] = lines[1]
    if len(lines) >= 3 and lines[2] != "(null)":
        md["kMDItemDisplayName"] = lines[2]
    if md:
        rec["mdls"] = md
    manifest[fn] = rec

with open("MANIFEST.plist", "wb") as f:
    plistlib.writePlist(manifest, f)
print("MANIFEST written with", len(manifest), "entries")
PY

# --- package with ditto (real AppleDouble sidecars) -------------------------
cd /tmp && rm -f gw_interop_fixtures.zip
ditto -c -k --sequesterRsrc "$REMOTE_DIR" gw_interop_fixtures.zip
# The zip is self-contained; drop the droppings from the Mac user's home.
rm -rf "$REMOTE_DIR"
echo "ZIP_DONE"
EOF

# -----------------------------------------------------------------------------
# Step 3+4: ship + relocate sidecars on this box.
# -----------------------------------------------------------------------------
echo "generate-fixtures: downloading zip ..."
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS \
  "${REMOTE}:/tmp/gw_interop_fixtures.zip" "$OUT/incoming.zip" \
  || err "scp from Mac failed"

cd "$OUT"
rm -rf incoming __MACOSX
unzip -q incoming.zip -d incoming || err "unzip failed"
# Relocate __MACOSX/._<name> -> ._<name> next to its data file.
find incoming -type f -path '*/__MACOSX/*' | while read -r side; do
  base="$(basename "$side")"            # _.<name>
  # data file lives one level up from __MACOSX, in the same directory.
  datadir="$(dirname "$(dirname "$side")")"
  target="$datadir/$base"               # keep the leading ._ prefix
  mv "$side" "$target"
done
rm -rf incoming/__MACOSX
# The zip may archive the source dir flat or nested; locate the real root
# (the directory that holds the fixture files) and normalise from there.
ROOT="$(find incoming -name file01_finderinfo.txt | head -1 | xargs -r dirname)"
[ -n "$ROOT" ] || err "could not locate fixtures inside the zip"
# Move the manifest + every fixture file (data + ._ sidecar) into place.
[ -f "$ROOT/MANIFEST.plist" ] || err "MANIFEST.plist missing from zip"
rm -rf "$OUT/fixtures"
mkdir -p "$OUT/fixtures"
mv "$ROOT/MANIFEST.plist" "$OUT/fixtures/MANIFEST.plist"
# Remove manifests from older script versions that staged one level up.
rm -f "$OUT/MANIFEST.plist"
# Move every fixture file (data + ._ sidecar) into fixtures/.
# dotglob so the glob also catches the ._ sidecar dotfiles.
shopt -s dotglob nullglob
for f in "$ROOT"/*; do
  [ -e "$f" ] || continue
  mv "$f" "$OUT/fixtures/"
done
shopt -u dotglob nullglob
# Keep the Mac-produced zip itself: the hermetic suite extracts it with
# GWMetaArchive to cover the zip-level path, not just raw sidecars.
mv incoming.zip "$OUT/fixtures/macos-made.zip" 2>/dev/null || true
rm -rf incoming

echo "generate-fixtures: fixtures ready in $OUT"
echo "generate-fixtures: $(find "$OUT/fixtures" -type f | wc -l) files + MANIFEST.plist"
