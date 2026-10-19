#!/bin/bash
# Builds, bundles and signs TILE32.app or FakeWindows.app (architecture TA-22).
#
# Usage: ./build-app.sh [TILE32|FakeWindows] [dev|release]
#   dev      debug configuration, signed with the Apple Development certificate (default)
#   release  release configuration in build/release/, Developer ID with a secure timestamp,
#            then notarization and stapling (needs the keychain profile TILE32, see below)
#
# The dev output path is fixed (build/<product>.app) and the signing identity is stable,
# so the Accessibility permission survives rebuilds (spike S5).
set -euo pipefail
cd "$(dirname "$0")"

PRODUCT="${1:-TILE32}"
MODE="${2:-dev}"
# Contributors set TILE32_DEV_IDENTITY to their own signing identity.
DEV_IDENTITY="${TILE32_DEV_IDENTITY:-Apple Development: Alexander Ilg}"

case "$PRODUCT" in
    TILE32)      PLIST="Resources/Info.plist" ;;
    FakeWindows) PLIST="Resources/FakeWindows-Info.plist" ;;
    *) echo "Unknown product: $PRODUCT (use TILE32 or FakeWindows)" >&2; exit 1 ;;
esac

RELEASE_IDENTITY="Developer ID Application: Alexander Ilg (AHBM4Y6VPX)"
# Notarization credentials live in the keychain under this profile, created once by the owner:
#   xcrun notarytool store-credentials TILE32 --apple-id <Apple ID> --team-id AHBM4Y6VPX
NOTARY_PROFILE="TILE32"

case "$MODE" in
    dev)     CONFIG="debug"; IDENTITY="$DEV_IDENTITY"; OUT="build" ;;
    release) CONFIG="release"; IDENTITY="$RELEASE_IDENTITY"; OUT="build/release" ;;
    *) echo "Unknown mode: $MODE (use dev or release)" >&2; exit 1 ;;
esac

swift build -c "$CONFIG" --product "$PRODUCT"
BIN_DIR="$(swift build -c "$CONFIG" --product "$PRODUCT" --show-bin-path)"

APP="$OUT/$PRODUCT.app"
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$APP/Contents/Info.plist"
# Every build gets its own build number, so two builds are never identical.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ "$PRODUCT" = "TILE32" ]; then
    # App icon, 66ideas logo (from sync-brand.sh) and the help page.
    cp Resources/Brand/* Resources/Help/* "$APP/Contents/Resources/"
fi

if [ "$MODE" = "release" ]; then
    # A secure timestamp is required for notarization.
    codesign --force --options runtime --timestamp \
        --entitlements Resources/TILE32.entitlements \
        --sign "$IDENTITY" "$APP"
else
    codesign --force --options runtime --timestamp=none \
        --entitlements Resources/TILE32.entitlements \
        --sign "$IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built and signed $APP ($CONFIG, $IDENTITY)"

if [ "$MODE" = "release" ]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "No notarization credentials found (keychain profile $NOTARY_PROFILE). Create them once with:"
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <Apple ID> --team-id AHBM4Y6VPX"
        exit 2
    fi
    ZIP="$OUT/$PRODUCT.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    spctl --assess --type execute --verbose "$APP"
    echo "Notarized and stapled $APP"
fi
