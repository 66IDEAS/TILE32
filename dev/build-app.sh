#!/bin/bash
# Builds, bundles and signs TILE32.app or FakeWindows.app (architecture TA-22).
#
# Usage: ./build-app.sh [TILE32|FakeWindows] [dev|release]
#   dev      debug configuration, signed with the Apple Development certificate (default)
#   release  release configuration, Developer ID and notarization (completed in task T-3.8)
#
# The output path is fixed (build/<product>.app) and the signing identity is stable,
# so the Accessibility permission survives rebuilds (spike S5).
set -euo pipefail
cd "$(dirname "$0")"

PRODUCT="${1:-TILE32}"
MODE="${2:-dev}"
DEV_IDENTITY="Apple Development: Alexander Ilg"

case "$PRODUCT" in
    TILE32)      PLIST="Resources/Info.plist" ;;
    FakeWindows) PLIST="Resources/FakeWindows-Info.plist" ;;
    *) echo "Unknown product: $PRODUCT (use TILE32 or FakeWindows)" >&2; exit 1 ;;
esac

case "$MODE" in
    dev)     CONFIG="debug"; IDENTITY="$DEV_IDENTITY" ;;
    release) echo "Release builds with Developer ID and notarization are added in task T-3.8." >&2; exit 1 ;;
    *) echo "Unknown mode: $MODE (use dev or release)" >&2; exit 1 ;;
esac

swift build -c "$CONFIG" --product "$PRODUCT"
BIN_DIR="$(swift build -c "$CONFIG" --product "$PRODUCT" --show-bin-path)"

APP="build/$PRODUCT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$APP/Contents/Info.plist"
# Every build gets its own build number, so two builds are never identical.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --options runtime --timestamp=none \
    --entitlements Resources/TILE32.entitlements \
    --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "Built and signed $APP ($CONFIG, $IDENTITY)"
