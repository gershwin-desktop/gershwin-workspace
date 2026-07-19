#!/usr/bin/env python3
"""Remove English placeholder entries (key=key) from .strings files,
keeping only real translations (key!=value). Handles multiline entries.
Skips German (which has real translations) and English (reference).
"""
import re, sys, glob

def clean_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        text = f.read()

    # Normalize continuation lines for parsing: "key\n  = value;\n" -> single line
    normalized = re.sub(r'(")\s*\n\s*=\s*', r'\1 = ', text)

    # Find all key=value pairs and collect keys with real translations
    pat = re.compile(
        r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$',
        re.MULTILINE
    )
    keep = {m.group(1) for m in pat.finditer(normalized) if m.group(1) != m.group(2)}

    # Process original lines: keep only entries whose key is in `keep`
    lines = text.split('\n')
    result = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith('"'):
            km = re.match(r'^"((?:[^"\\]|\\.)*)"', line)
            if km:
                key = km.group(1)
                if i + 1 < len(lines) and re.match(r'^\s*=', lines[i+1]):
                    if key in keep:
                        result.append(line)
                        result.append(lines[i+1])
                    i += 2
                else:
                    if key in keep:
                        result.append(line)
                    i += 1
            else:
                result.append(line)
                i += 1
        else:
            # Drop orphaned continuation lines (from removed entries)
            if not re.match(r'^\s*=', line):
                result.append(line)
            i += 1

    # Remove trailing blank lines
    while result and result[-1].strip() == '':
        result.pop()

    out = '\n'.join(result) + '\n'
    if out != text:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(out)
        return True
    return False

if __name__ == '__main__':
    paths = sys.argv[1:] if len(sys.argv) > 1 else glob.glob('Workspace/Resources/*.lproj/Localizable.strings')
    for path in paths:
        lang = path.split('/')[-2].replace('.lproj', '')
        if lang in ('English', 'German'):
            continue
        if clean_file(path):
            print(f"cleaned: {path}")
