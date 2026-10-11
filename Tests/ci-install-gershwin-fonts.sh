#!/bin/sh
#
# Copyright (c) 2026 Simon Peter
#
# SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
#
# CI only: put the Gershwin desktop fonts and their fontconfig file where an
# installed Gershwin system has them. The view suites measure text in the
# desktop's own fonts (NSFont is Inter-Medium); a CI image has neither the
# fonts from gershwin-assets nor gershwin-system's fonts.conf, and a fallback
# font ignores the sizes the tests ask for.
#
# Usage: ci-install-gershwin-fonts.sh <gershwin-developer checkout>

set -e
DEV=${1:?usage: $0 <gershwin-developer checkout>}
ASSETS="$DEV/Library/Sources/gershwin-assets/Library/Fonts"
CONF="$DEV/Library/Sources/gershwin-system/Library/Preferences/fonts.conf"

[ -d "$ASSETS" ] || { echo "FATAL: $ASSETS missing (gershwin-assets not checked out)" >&2; exit 1; }
[ -f "$CONF" ] || { echo "FATAL: $CONF missing (gershwin-system not checked out)" >&2; exit 1; }

mkdir -p /System/Library/Fonts /System/Library/Preferences
cp -R "$ASSETS/." /System/Library/Fonts/
cp "$CONF" /System/Library/Preferences/fonts.conf
echo "Installed the Gershwin fonts into /System/Library/Fonts"
