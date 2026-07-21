#!/usr/bin/env python3
"""Clean up Localizable.strings files:
1. Remove short-fragment keys that are prefixes of longer real keys
   (leftovers from multiline ObjC string concatenation).
2. Remove entries with \u201c/\u201d escapes when literal UTF-8
   smart-quote versions exist (source uses UTF-8 quotes).
"""
import re, sys, glob

def clean_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()
    orig = text

    # 1. Remove entries with literal newline inside the key (malformed)
    text = re.sub(
        r'^"[^"]*\n[^"]*"\s*=\s*"[^"]*"\s*;\s*\n?',
        '', text, flags=re.MULTILINE
    )

    # 2. Find all single-line key=value entries and remove short \n-ending
    #    fragments where a longer version of the same key exists.
    pat = re.compile(
        r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$',
        re.MULTILINE
    )
    singles = [(m.start(), m.end(), m.group(1), m.group(2)) for m in pat.finditer(text)]
    to_remove = set()
    for pos_s, pos_e, k, v in singles:
        if not k.endswith('\\n'):
            continue
        for _, _, ok, ov in singles:
            if k != ok and ok.startswith(k) and len(ok) > len(k):
                to_remove.add((pos_s, pos_e))
                break

    # 3. Remove short multi-line entries with \u201c escapes where
    #    longer UTF-8-quoted version exists.
    ml_pat = re.compile(
        r'^"((?:[^"\\]|\\.)*)"\s*\n\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*\n?',
        re.MULTILINE
    )
    multi = [(m.start(), m.end(), m.group(1), m.group(2)) for m in ml_pat.finditer(text)]
    for pos_s, pos_e, k, v in multi:
        if not k.endswith('\\n'):
            continue
        # Check for longer version (in singles or multi)
        all_entries = singles + [(s, e, kk, vv) for s, e, kk, vv in multi]
        for _, _, ok, ov in all_entries:
            if k != ok and ok.startswith(k) and len(ok) > len(k):
                to_remove.add((pos_s, pos_e))
                break
        # Also check if key has \u201c and same key with literal quote exists
        if '\\u201c' in k:
            lit_key = k.replace('\\u201c', '\u201c').replace('\\u201d', '\u201d')
            for _, _, ok, ov in all_entries:
                if ok == lit_key:
                    to_remove.add((pos_s, pos_e))
                    break

    # Remove in reverse position order
    for pos_s, pos_e in sorted(to_remove, key=lambda x: -x[0]):
        # Absorb preceding blank line
        start = pos_s
        while start > 0 and text[start-1] in '\n\r ':
            start -= 1
        text = text[:start] + text[pos_e:]

    if text != orig:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
        return True
    return False

if __name__ == '__main__':
    paths = sys.argv[1:] if len(sys.argv) > 1 else glob.glob('Workspace/Resources/*.lproj/Localizable.strings')
    for path in paths:
        if clean_file(path):
            print(f"cleaned: {path}")
