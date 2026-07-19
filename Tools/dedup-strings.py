#!/usr/bin/env python3
"""Deduplicate a Localizable.strings file.
Keeps the LAST value for each key (matching NSBundle behaviour).
Strips location/flag comments. Sorts keys alphabetically.
"""
import re, sys

STR = r'"((?:[^"\\]|\\.)*)"'

def parse_strings(path):
    entries = {}
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    # Strip block comments
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.DOTALL)
    # Normalize continuation lines: join "key\n  = value;\n" into one line
    text = re.sub(r'(")\s*\n\s*=\s*', r'\1 = ', text)
    # Find all key = value;
    pat = re.compile(r'^\s*' + STR + r'\s*=\s*' + STR + r'\s*;\s*$', re.MULTILINE)
    for m in pat.finditer(text):
        key, value = m.group(1), m.group(2)
        entries[key] = value
    return entries

def write_strings(entries, path):
    keys = sorted(entries.keys())
    with open(path, 'w', encoding='utf-8') as f:
        f.write("/*** deduplicated by dedup-strings.py ***/\n\n")
        for key in keys:
            val = entries[key]
            # Use multi-line format if value contains \n escape
            if '\\n' in val:
                f.write(f'"{key}"\n  = "{val}";\n\n')
            else:
                f.write(f'"{key}" = "{val}";\n\n')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: dedup-strings.py <file.strings> [file2.strings ...]")
        sys.exit(1)
    for path in sys.argv[1:]:
        orig = parse_strings(path)
        write_strings(orig, path)
        print(f"{path}: {len(orig)} unique keys")
