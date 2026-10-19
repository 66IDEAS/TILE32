#!/bin/bash
# Packages a notarized release of TILE32 for GitHub (task T-3.8).
#
# Usage: ./package-release.sh
#   1. builds, signs and notarizes the app with ./build-app.sh TILE32 release
#   2. puts it into a DMG with a link to Applications, the license and the notices
#   3. signs, notarizes and staples the DMG, and checks it with Gatekeeper
#   4. writes a ZIP of the app and SHA256SUMS beside the DMG
#
# Output: build/release/dist/TILE32-<version>-arm64.dmg, .zip and SHA256SUMS.
# Existing files are never overwritten: a corrected release needs a new version.
# Needs the keychain profile TILE32 (see build-app.sh); credentials never go into the repository.
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Developer ID Application: Alexander Ilg (AHBM4Y6VPX)"
NOTARY_PROFILE="${TILE32_NOTARY_PROFILE:-TILE32}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DIST="build/release/dist"
NAME="TILE32-$VERSION-arm64"
DMG="$DIST/$NAME.dmg"
ZIP="$DIST/$NAME.zip"

if [ -e "$DMG" ] || [ -e "$ZIP" ]; then
    echo "$DIST already holds a release $VERSION. Raise the version instead of overwriting it." >&2
    exit 1
fi

./build-app.sh TILE32 release
APP="build/release/TILE32.app"
lipo -archs "$APP/Contents/MacOS/TILE32" | grep -qx "arm64" || { echo "Expected an arm64 binary" >&2; exit 1; }

mkdir -p "$DIST"
STAGE="$(mktemp -d build/release/dmg-stage.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/TILE32.app"
ln -s /Applications "$STAGE/Applications"
cp ../LICENSE "$STAGE/LICENSE.txt"
cp ../THIRD_PARTY_NOTICES.md "$STAGE/THIRD_PARTY_NOTICES.md"

hdiutil create -volname "TILE32 $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

ditto -c -k --keepParent "$APP" "$ZIP"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS)
echo "Release $VERSION packaged in $DIST:"
ls -l "$DIST"
