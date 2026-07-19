#!/bin/sh
# Quick check for untranslated strings before committing.
# Checks all translations against source keys.
# Usage: ./Tools/check-translations.sh [project]
#   project: "FSNode", "Workspace", "Operation" (default: all)

normalize() {
  # Normalize smart-quote escapes so \u201c matches literal UTF-8 "
  # and remove purely numeric keys (label font sizes).
  sed \
    -e 's/\\u201c/\xe2\x80\x9c/g' \
    -e 's/\\u201d/\xe2\x80\x9d/g' \
    -e 's/\\u00fc/\xc3\xbc/g' \
    -e 's/\\u00f6/\xc3\xb6/g' \
    -e 's/\\u00e4/\xc3\xa4/g' \
    -e 's/\\u00df/\xc3\x9f/g' \
    -e 's/\\u00c4/\xc3\x84/g' \
    -e 's/\\u00d6/\xc3\x96/g' \
    -e 's/\\u00dc/\xc3\x9c/g' | grep -v '^[0-9][0-9]*$'
}

check_project() {
  dir="$1"
  res="$2"
  name="$3"
  [ ! -d "$dir" ] && return

  src=$(mktemp)

  grep -roh 'NSLocalizedString(@"\([^"]*\)"' "$dir" --include='*.m' --include='*.h' 2>/dev/null \
    | sed 's/NSLocalizedString(@"//;s/"$//' | normalize >> "$src"
  grep -roh '_(@"\([^"]*\)"' "$dir" --include='*.m' --include='*.h' 2>/dev/null \
    | sed 's/_(@"//;s/"$//' | normalize >> "$src"
  sort -u "$src" -o "$src"

  any=0
  for lproj in "$res"/*.lproj; do
    [ -d "$lproj" ] || continue
    lang=$(basename "$lproj" .lproj)
    [ "$lang" = "English" ] && continue

    gf="$lproj/Localizable.strings"
    [ -f "$gf" ] || { echo "$name ($lang): no Localizable.strings"; any=1; continue; }

    de=$(mktemp)
    # Extract keys: handle multiline values (value on next indented line)
    awk 'BEGIN{key=""} /^[[:space:]]*"/{if(key!="")print key; match($0,/^[[:space:]]*"([^"]*)"/,a); key=a[1]} /^[[:space:]]*=/{next} END{if(key!="")print key}' "$gf" \
      | normalize | sort -u > "$de"

    missing=$(comm -23 "$src" "$de" | wc -l)
    if [ "$missing" -gt 0 ]; then
      echo "$name ($lang): $missing untranslated"
      any=1
    fi
    rm -f "$de"
  done

  rm -f "$src"
  return $any
}

fail=0
[ $# -gt 0 ] && set -- "$@"
[ $# -eq 0 ] && set -- FSNode Operation Workspace

for p in "$@"; do
  case "$p" in
    FSNode)     check_project FSNode     FSNode/Resources     FSNode     || fail=1 ;;
    Operation)  check_project Operation  Operation/Resources   Operation  || fail=1 ;;
    Workspace)  check_project Workspace  Workspace/Resources   Workspace  || fail=1 ;;
  esac
done

exit $fail
