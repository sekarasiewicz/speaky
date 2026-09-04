#!/usr/bin/env bash
#
# Builds Speaky, signs it with Developer ID, notarizes it and packages a DMG
# that installs by drag and drop with no Gatekeeper warning.
#
# One-time setup:
#   1. Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application
#   2. xcrun notarytool store-credentials speaky-notary \
#        --apple-id <apple id email> --team-id GM2CG6S626 --password <app-specific password>
#      (app-specific password: https://account.apple.com → Sign-In and Security)
#
# Usage:
#   ./release.sh            builds dist/Speaky-<version>.dmg
#   ./release.sh --publish  also creates a GitHub release with the DMG attached
#
# Both the app and the DMG are notarized and stapled: Gatekeeper assesses the
# image when it is opened and the app when it is launched, and a stapled
# ticket lets each verify without a network round trip.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/speaky-release"
DIST="$PROJECT_DIR/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-speaky-notary}"
IDENTITY="${IDENTITY:-Developer ID Application}"

security find-identity -v -p codesigning | grep -q "$IDENTITY" \
  || { echo "No '$IDENTITY' certificate in the keychain; see the setup notes at the top of this script." >&2; exit 1; }

echo "==> Building Release"
LOG="$BUILD_DIR/build.log"
mkdir -p "$BUILD_DIR" "$DIST"
if ! xcodebuild \
  -project "$PROJECT_DIR/Speaky.xcodeproj" \
  -scheme Speaky \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -quiet \
  build > "$LOG" 2>&1
then
  echo "Build failed:" >&2
  cat "$LOG" >&2
  exit 1
fi

APP="$BUILD_DIR/Build/Products/Release/Speaky.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$DIST/Speaky-$VERSION.dmg"

echo "==> Signing with $IDENTITY"
# The build is signed with the development certificate Xcode picks
# automatically; re-sign with Developer ID so Gatekeeper accepts it outside
# the developer's own machines. Hardened runtime and a secure timestamp are
# both required by notarization.
codesign --force --deep --options runtime --timestamp -s "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Notarizing the app (waits for Apple, usually a minute or two)"
ZIP="$BUILD_DIR/Speaky.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
# Stapling attaches the ticket to the bundle, so the copy the user drags out
# of the image verifies offline.
xcrun stapler staple "$APP"

echo "==> Packaging $DMG"
STAGE="$BUILD_DIR/dmg"
rm -rf "$STAGE" "$DMG" && mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Speaky" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --timestamp -s "$IDENTITY" "$DMG"

echo "==> Notarizing the DMG"
# Gatekeeper assesses the disk image itself when it is opened, so it needs
# its own ticket; the app inside is already covered by its own.
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

if [ "${1:-}" = "--publish" ]; then
  echo "==> Publishing GitHub release v$VERSION"
  gh release create "v$VERSION" "$DMG" --title "Speaky $VERSION" --generate-notes
fi

echo
echo "Done: $DMG"
