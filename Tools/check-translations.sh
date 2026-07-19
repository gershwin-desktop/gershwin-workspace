#!/bin/sh
# Quick check for untranslated strings before committing.
# Checks all translations against source keys.
# Usage: ./Tools/check-translations.sh [project]
#   project: "FSNode", "Workspace", "Operation" (default: all)

check_project() {
  dir="$1"
  res="$2"
  name="$3"
  [ ! -d "$dir" ] && return

  src=$(mktemp)

  grep -roh 'NSLocalizedString(@"\([^"]*\)"' "$dir" --include='*.m' --include='*.h' 2>/dev/null \
    | sed 's/NSLocalizedString(@"//;s/"$//' >> "$src"
  grep -roh '_(@"\([^"]*\)"' "$dir" --include='*.m' --include='*.h' 2>/dev/null \
    | sed 's/_(@"//;s/"$//' >> "$src"
  sort -u "$src" -o "$src"

  any=0
  for lproj in "$res"/*.lproj; do
    [ -d "$lproj" ] || continue
    lang=$(basename "$lproj" .lproj)

    # Skip English — keys = values, no translation needed
    [ "$lang" = "English" ] && continue

    gf="$lproj/Localizable.strings"
    if [ ! -f "$gf" ]; then
      echo "$name ($lang): no Localizable.strings"
      any=1
      continue
    fi

    de=$(mktemp)
    grep '"' "$gf" | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u > "$de"

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
