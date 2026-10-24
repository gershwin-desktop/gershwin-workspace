#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
#
# Renders the toolbar glyphs from their SVG sources into the TIFFs the
# app loads from Resources/Icons.  Each TIFF holds the glyph twice, at
# 16 px for 72 dpi and at 32 px for 144 dpi, so both describe the same
# 16 point image and NSImage picks the sharp one at a scale factor of 2.
# Run it after changing an SVG and commit the TIFFs with it; the build does
# not need Inkscape or ImageMagick.

set -e
cd "$(dirname "$0")"
out=../Icons
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

for svg in GW*.svg; do
  name=${svg%.svg}
  inkscape "$svg" --export-type=png --export-width=16 --export-height=16 \
    --export-filename="$tmp/$name-16.png" >/dev/null 2>&1
  inkscape "$svg" --export-type=png --export-width=32 --export-height=32 \
    --export-filename="$tmp/$name-32.png" >/dev/null 2>&1
  magick \( "$tmp/$name-16.png" -set units PixelsPerInch -set density 72 \) \
         \( "$tmp/$name-32.png" -set units PixelsPerInch -set density 144 \) \
         -compress lzw "$out/$name.tiff"
done
