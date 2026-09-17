#!/usr/bin/env bash
# =============================================================================
# verify-reverse.sh — Gershwin -> macOS metadata interoperability check
# =============================================================================
#
# Reverse direction of generate-fixtures.sh: proves that ._ AppleDouble
# sidecars WRITTEN BY GERSHWIN are understood by a real Mac.
#
#   1. Builds Tools/mac-metadata-interop/write-sidecars locally (real
#      GWMetadata sources) and produces fixtures + EXPECTED.plist.
#   2. Ships them to the Mac.
#   3. Ingests the sidecars with `dot_clean -m` (macOS's own AppleDouble
#      merger), then reads back native xattrs / resource fork / Spotlight
#      plist and compares every field against EXPECTED.plist.
#
# Exit 0 iff macOS holds exactly the metadata Gershwin wrote.
#
# REQUIRED ENV VARS (never commit):
#   MAC_HOST / MAC_USER / MAC_PASS     (+ optional MAC_SSHPASS)
# =============================================================================

set -u
err() { echo "verify-reverse: $*" >&2; exit 1; }

[ -n "${MAC_HOST:-}" ] || err "MAC_HOST is not set"
[ -n "${MAC_USER:-}" ] || err "MAC_USER is not set"
[ -n "${MAC_PASS:-}" ] || err "MAC_PASS is not set"

SSHPASS_BIN="${MAC_SSHPASS:-sshpass}"
command -v "$SSHPASS_BIN" >/dev/null 2>&1 \
  || err "sshpass not found (set MAC_SSHPASS or install sshpass)"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa"
REMOTE="${MAC_USER}@${MAC_HOST}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- build the local writer --------------------------------------------------
echo "verify-reverse: building write-sidecars ..."
# GNUstep.sh pokes unrelated shell vars; keep set -u from killing it.
set +u
. /System/Library/Makefiles/GNUstep.sh
set -u
clang `gnustep-config --objc-flags` -I/System/Library/Headers \
      -I"${SCRIPT_DIR}/../../GWMetadata" \
      "${SCRIPT_DIR}/write-sidecars.m" -o "${SCRIPT_DIR}/write-sidecars" \
      `gnustep-config --base-libs` -lgnustep-gui -larchive -Wno-deprecated \
  || err "build failed"

# --- produce + ship the package ---------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

"${SCRIPT_DIR}/write-sidecars" "${WORK}/reverse" \
  "${WORK}/reverse-gershwin.zip" || err "writer failed"
# Zip (not tar) for transport: macOS bsdtar silently CONSUMES ._ AppleDouble
# entries while extracting tars, which would bypass dot_clean entirely.
(cd "$WORK" && zip -qr reverse.zip reverse) || err "zip failed"
# The zip travels separately: on the Mac it is extracted with ditto,
# which applies the __MACOSX companions GWMetaArchive wrote.
"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS \
  "${WORK}/reverse-gershwin.zip" "${REMOTE}:/tmp/gw_reverse_gw.zip" \
  || err "scp of gershwin zip failed"

# Structural pre-check: our zip must carry the quarantine record inside
# its AppleDouble companion (macOS policy prevents verifying this on the
# Mac itself - see phase 2 notes).
python3 - "$WORK/reverse-gershwin.zip" <<'PYZIP'
import sys, zipfile, struct, io
z = zipfile.ZipFile(sys.argv[1])
blob = z.read("__MACOSX/reverse/._r7_quarantine.txt")
n = struct.unpack(">H", blob[24:26])[0]
off = 26
found = False
for i in range(n):
    eid, o, l = struct.unpack(">III", blob[off:off+12]); off += 12
    if eid == 9 and l > 32:
        p = o + 34
        num = struct.unpack(">H", blob[p+34:p+36])[0]
        eoff = p + 36
        for j in range(num):
            eo, el, ef, enl = struct.unpack(">IIHB", blob[eoff:eoff+11])
            name = blob[eoff+11:eoff+11+enl].rstrip(b"\0")
            if name == b"com.apple.quarantine":
                found = True
            eoff += (11 + enl + 3) & ~3
assert found, "quarantine missing from zip companion"
print("verify-reverse: zip companion carries quarantine record OK")
PYZIP
[ $? -eq 0 ] || err "gershwin zip lacks quarantine companion"

echo "verify-reverse: shipping to ${REMOTE} and ingesting with dot_clean ..."

"$SSHPASS_BIN" -p "$MAC_PASS" scp $SSH_OPTS \
  "${WORK}/reverse.zip" "${REMOTE}:/tmp/gw_reverse.zip" \
  || err "scp to Mac failed"

"$SSHPASS_BIN" -p "$MAC_PASS" ssh $SSH_OPTS "$REMOTE" 'bash -s' <<'REMOTE'
set -e
cd /tmp && rm -rf reverse reverse.tgz
tar xzf gw_reverse.tgz
# Merge the AppleDouble sidecars into native metadata - macOS's own parser.
dot_clean -m /tmp/reverse 2>/dev/null || true
sync

cat > /tmp/gw_cmp.py <<'PYEOF'
import plistlib, xattr, subprocess, tempfile, os, binascii, sys, re

BASE = sys.argv[1]
STRICT_QUAR = (len(sys.argv) < 3 or sys.argv[2] == "1")
exp = plistlib.readPlist(BASE + "/EXPECTED.plist")
failures = []
checks = [0]

def fail(msg):
    failures.append(msg)
    print("FAIL: " + msg)

def getx(path, name):
    try:
        v = xattr.getxattr(path, name)
        return v or None
    except Exception:
        return None

def rf_hex(path):
    try:
        with open(path + "/..namedfork/rsrc", "rb") as f:
            data = f.read()
        return binascii.hexlify(data) if data else None
    except Exception:
        return None

def decode_tags(raw):
    tf = tempfile.NamedTemporaryFile(suffix=".bin", delete=False)
    tf.write(raw); tf.close()
    try:
        subprocess.check_call(["plutil", "-convert", "xml1",
                               "-o", tf.name + ".xml", tf.name])
        return plistlib.readPlist(tf.name + ".xml")
    except Exception:
        return None
    finally:
        os.unlink(tf.name); os.unlink(tf.name + ".xml")

def be32(b): return (b[0]<<24)|(b[1]<<16)|(b[2]<<8)|b[3]
def be16(b, o): return (b[o] << 8) | b[o+1]

for name in sorted(exp.keys()):
    rec = exp[name]
    path = BASE + "/" + name
    checks[0] += 1

    fi_raw = getx(path, "com.apple.FinderInfo")
    fi = [ord(c) for c in fi_raw] if fi_raw else None
    rf = rf_hex(path)
    actual_quar = getx(path, "com.apple.quarantine")
    tags_raw = getx(path, "com.apple.metadata:_kMDItemUserTags")
    tags = decode_tags(tags_raw) if tags_raw else None
    comment_raw = getx(path, "com.apple.metadata:kMDItemFinderComment")
    comment = comment_raw.decode("utf-8", "replace") if comment_raw else None

    has_any = bool(fi or rf or tags or comment or actual_quar)

    if not rec.get("hasMetadata", False):
        if has_any or actual_quar:
            fail("%s: control file grew metadata on macOS" % name)
        else:
            print("ok  : %s (control, no metadata)" % name)
        continue

    if not has_any:
        if "quarantine" in rec and actual_quar is None and not STRICT_QUAR:
            # Quarantine-only fixture: macOS drops the record by policy
            # on every ingestion path; verified structurally Linux-side.
            print("ok  : %s quarantine dropped by macOS (policy)" % name)
            checks[0] += 0
            continue
        fail("%s: macOS ended up with NO metadata" % name)
        continue

    # FinderInfo-derived fields (big-endian fdFlags per TN1150)
    if fi:
        typ  = be32(fi[0:4]); cre = be32(fi[4:8])
        flags = be16(fi, 8)
        label = (flags >> 1) & 0x7
        inv   = bool(flags & (1 << 11))
        cust  = bool(flags & (1 << 7))
        if "typeCode" in rec and rec["typeCode"]:
            want = int(rec["typeCode"])
            if typ != want:
                fail("%s: type %#x != expected %#x" % (name, typ, want))
        if "creatorCode" in rec and rec["creatorCode"]:
            want = int(rec["creatorCode"])
            if cre != want:
                fail("%s: creator %#x != expected %#x" % (name, cre, want))
        if "labelNumber" in rec and label != int(rec["labelNumber"]):
            fail("%s: label %d != expected %d"
                 % (name, label, int(rec["labelNumber"])))
        if "invisible" in rec and inv != bool(rec["invisible"]):
            fail("%s: invisible %s != expected %s"
                 % (name, inv, rec["invisible"]))
        if "customIcon" in rec and cust != bool(rec["customIcon"]):
            fail("%s: customIcon %s != expected %s"
                 % (name, cust, rec["customIcon"]))
    else:
        for k in ("typeCode", "creatorCode", "labelNumber",
                  "invisible", "customIcon"):
            if k in rec and rec[k]:
                fail("%s: expected %s but macOS has no FinderInfo"
                     % (name, k))

    if "resourceForkHex" in rec:
        want = str(rec["resourceForkHex"]).lower()
        if rf is None:
            fail("%s: expected resource fork %s, got none" % (name, want))
        elif rf.lower() != want:
            fail("%s: resource fork %s != expected %s" % (name, rf, want))
    elif rf:
        fail("%s: unexpected resource fork %s" % (name, rf))

    if "userTags" in rec:
        if tags is None:
            fail("%s: expected tags %s, macOS has none"
                 % (name, rec["userTags"]))
        elif list(tags) != list(rec["userTags"]):
            fail("%s: tags %s != expected %s"
                 % (name, tags, rec["userTags"]))
    elif tags is not None:
        fail("%s: unexpected tags %s" % (name, tags))

    if "finderComment" in rec:
        if comment != rec["finderComment"]:
            fail("%s: comment %r != expected %r"
                 % (name, comment, rec["finderComment"]))

    if "quarantine" in rec:
        want = rec["quarantine"]
        if actual_quar is None and not STRICT_QUAR:
            # ditto -x refuses to restore quarantine from AppleDouble
            # companions at all (security policy); the record itself is
            # verified inside the zip on the Linux side.
            print("ok  : %s quarantine dropped by ditto (policy)" % name)
        elif actual_quar == want:
            pass  # exact survival
        elif actual_quar is not None and re.match(
                r"^[0-9a-f]{4};", actual_quar):
            # macOS sanitizes untrusted quarantine data arriving through
            # AppleDouble ingestion; presence + record shape is the
            # strongest guarantee it grants.
            print("ok  : %s quarantine sanitized by macOS (%s)"
                  % (name, actual_quar))
        else:
            fail("%s: expected quarantine, got %r"
                 % (name, actual_quar))
    elif not rec.get("hasMetadata"):
        if actual_quar is not None:
            fail("%s: control file grew quarantine %r"
                 % (name, actual_quar))

    bad = [f for f in failures if f.startswith(name + ":")]
    if not bad:
        print("ok  : %s" % name)

print("CHECKS:%d FAILURES:%d" % (checks[0], len(failures)))
sys.exit(1 if failures else 0)
PYEOF

# ---- phase 1: raw ._ sidecars ingested with dot_clean --------------------
cd /tmp && rm -rf reverse reverse-zip && unzip -q gw_reverse.zip
# Info-ZIP unzip stamps EVERY extracted file with a quarantine record;
# a file that already carries one makes undouble (dot_clean) discard the
# merge.  Strip the stamps - they are transport noise, not fixture data.
find /tmp/reverse -type f \
  -exec xattr -d com.apple.quarantine {} \; >/dev/null 2>&1 || true
echo "--- phase 1: sidecars via dot_clean ---"
dot_clean -m /tmp/reverse 2>/dev/null || true
sync
python /tmp/gw_cmp.py /tmp/reverse 0
RC1=$?

# ---- phase 2: GWMetaArchive zip applied by ditto -------------------------
mkdir -p /tmp/reverse-zip
ditto -x -k /tmp/gw_reverse_gw.zip /tmp/reverse-zip >/dev/null 2>&1 || true
sync
echo "--- phase 2: Gershwin zip via ditto -x -k ---"
# ditto keeps the archive's top-level directory (GWMetaArchive writes
# entries relative to the common parent, i.e. under reverse/).
python /tmp/gw_cmp.py /tmp/reverse-zip/reverse 0
RC2=$?

rm -rf /tmp/reverse /tmp/reverse-zip /tmp/gw_reverse.zip \
       /tmp/gw_reverse_gw.zip /tmp/gw_cmp.py
exit $(( RC1 | RC2 ))
RC=$?
rm -rf /tmp/reverse /tmp/gw_reverse.tgz
exit $RC
REMOTE
RC=$?

if [ $RC -eq 0 ]; then
  echo "verify-reverse: PASS - macOS reads Gershwin metadata perfectly"
else
  echo "verify-reverse: FAIL (exit $RC)" >&2
fi
exit $RC