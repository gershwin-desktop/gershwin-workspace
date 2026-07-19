#!/bin/sh
# Fill all missing source keys into every .lproj/Localizable.strings.
# New keys get English values as placeholder for translators.
# Run from repo root: ./Tools/fill-translations.sh

set -e
cd "$(git rev-parse --show-toplevel)"

# -- 1. Collect all source keys (NSLocalizedString + _())
tmp=$(mktemp -d)
src_all="$tmp/src_all.txt"
> "$src_all"

grep -roh 'NSLocalizedString(@"\([^"]*\)"' Workspace --include='*.m' --include='*.h' 2>/dev/null \
  | sed 's/NSLocalizedString(@"//;s/"$//' >> "$src_all"
grep -roh '_(@"\([^"]*\)"' Workspace --include='*.m' --include='*.h' 2>/dev/null \
  | sed 's/_(@"//;s/"$//' >> "$src_all"
sort -u "$src_all" -o "$src_all"

total=$(wc -l < "$src_all")
echo "Source keys: $total"

# -- 2. For each language, merge missing keys
for lproj in Workspace/Resources/*.lproj; do
  lang=$(basename "$lproj" .lproj)
  [ "$lang" = "English" ] && continue

  f="$lproj/Localizable.strings"
  [ ! -f "$f" ] && continue

  de="$tmp/$lang.txt"
  grep '"' "$f" | sed -n 's/^[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u > "$de"

  missing=$(comm -23 "$src_all" "$de" | grep -v '^[0-9][0-9]*$' | grep -c . || true)
  [ "$missing" -eq 0 ] && echo "$lang: ok" && continue

  echo "$lang: adding $missing missing keys"

  # Append to file - one section per run
  echo "" >> "$f"
  echo "/* ---- missing keys added by fill-translations.sh ---- */" >> "$f"

  comm -23 "$src_all" "$de" | grep -v '^[0-9][0-9]*$' | while IFS= read -r key; do
    [ -z "$key" ] && continue
    escaped=$(printf '%s' "$key" | sed 's/"/\\"/g')
    echo "\"$escaped\" = \"$escaped\";" >> "$f"
  done
done

rm -rf "$tmp"
echo "Done."
