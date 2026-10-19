#!/bin/bash
# Copies the app icon and the 66ideas logo from the brand kit into Resources/Brand.
# The files in the repository keep stable names, so the app code never changes when
# the kit is regenerated.
#
# Usage: ./sync-brand.sh [path to the brand kit]
set -euo pipefail
cd "$(dirname "$0")"

KIT="${1:-/Users/alexanderilg/dev/git/66ideas/03-brand/kit}"
ICONS="$KIT/app-icons/tile32"
ICNS="$ICONS/TILE32.icns"
if [ ! -f "$ICNS" ]; then
    # The first kit used the folder name tiles32; kept as a fallback until it is regenerated.
    ICONS="$KIT/app-icons/tiles32"
    ICNS="$ICONS/TILES32.icns"
fi
[ -f "$ICNS" ] || { echo "No app icon found in $KIT/app-icons" >&2; exit 1; }

mkdir -p Resources/Brand
cp "$ICNS" Resources/Brand/AppIcon.icns
cp "$KIT/logos/66ideas/66ideas-lockup-light.svg" Resources/Brand/66ideas-lockup-light.svg
cp "$KIT/logos/66ideas/66ideas-lockup-dark.svg" Resources/Brand/66ideas-lockup-dark.svg
echo "Copied the app icon from $ICNS and the 66ideas logo into Resources/Brand"
