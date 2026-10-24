#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
#
# Renders the toolbar glyphs from their SVG sources into the TIFFs the
# app loads from Resources/Icons.  Each TIFF holds the glyph twice, at
# 1x for 72 dpi and at 2x for 144 dpi, so both describe the same
# point size and NSImage picks the sharp one at a scale factor of 2.
# Run it after changing an SVG and commit the TIFFs with it; the build does
# not need Inkscape or ImageMagick.

set -e
cd "$(dirname "$0")"
out=../Icons
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

for svg in GW*.svg; do
  name=${svg%.svg}
  # 96 dpi is Inkscape's 1 px per SVG unit, so each glyph keeps the size
  # its SVG gives (16x16, or wider for a glyph with a menu arrow).
  inkscape "$svg" --export-type=png --export-dpi=96 \
    --export-filename="$tmp/$name-16.png" >/dev/null 2>&1
  inkscape "$svg" --export-type=png --export-dpi=192 \
    --export-filename="$tmp/$name-32.png" >/dev/null 2>&1
  magick \( "$tmp/$name-16.png" -set units PixelsPerInch -set density 72 \) \
         \( "$tmp/$name-32.png" -set units PixelsPerInch -set density 144 \) \
         -compress lzw "$out/$name.tiff"
done
