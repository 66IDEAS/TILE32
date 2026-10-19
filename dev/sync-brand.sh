#!/bin/bash
# Copies the app icon, the TILE32 wordmark and the 66ideas logo from the brand kit into
# Resources/Brand.
# The files in the repository keep stable names, so the app code never changes when
# the kit is regenerated.
#
# Usage: ./sync-brand.sh [path to the brand kit]
# The path can also come from TILE32_BRAND_KIT. The kit itself is not part of this repository.
set -euo pipefail
cd "$(dirname "$0")"

KIT="${1:-${TILE32_BRAND_KIT:-$HOME/dev/git/66ideas/03-brand/kit}}"
ICNS="$KIT/app-icons/tile32/TILE32.icns"
[ -f "$ICNS" ] || { echo "No app icon found at $ICNS" >&2; exit 1; }

mkdir -p Resources/Brand
cp "$ICNS" Resources/Brand/AppIcon.icns
cp "$KIT/logos/66ideas/66ideas-lockup-light.svg" Resources/Brand/66ideas-lockup-light.svg
cp "$KIT/logos/66ideas/66ideas-lockup-dark.svg" Resources/Brand/66ideas-lockup-dark.svg
cp "$KIT/logos/tile32/tile32-light.svg" Resources/Brand/tile32-light.svg
cp "$KIT/logos/tile32/tile32-dark.svg" Resources/Brand/tile32-dark.svg
echo "Copied the app icon, the TILE32 wordmark and the 66ideas logo into Resources/Brand"
