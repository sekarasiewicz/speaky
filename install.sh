#!/usr/bin/env bash
#
# Builds Speaky in Release and installs it to /Applications.
#
# With --prebuilt, skips the build and installs the app zipped in dist/ instead,
# so no Xcode is needed. The zip is signed with a development certificate and
# not notarized, so the quarantine attribute is removed before launch; without
# that Gatekeeper reports the app as damaged.
#
# A copy in /Applications is what makes "Launch at login" durable: SMAppService
# registers whichever bundle is running, and a build started from Xcode lives in
# DerivedData, which disappears on the next clean.
#
# The code signature stays the same across reinstalls, so the Accessibility grant
# and the login item survive an upgrade.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/speaky-release"
APP="/Applications/Speaky.app"

if [ "${1:-}" = "--prebuilt" ]; then
  ZIP="$PROJECT_DIR/dist/Speaky.zip"
  [ -f "$ZIP" ] || { echo "No prebuilt app at $ZIP" >&2; exit 1; }
  echo "==> Unpacking $ZIP"
  rm -rf "$BUILD_DIR/prebuilt" && mkdir -p "$BUILD_DIR/prebuilt"
  ditto -x -k "$ZIP" "$BUILD_DIR/prebuilt"
  BUILT="$BUILD_DIR/prebuilt/Speaky.app"
  xattr -dr com.apple.quarantine "$BUILT" 2>/dev/null || true
  codesign --verify --deep --strict "$BUILT"
else
echo "==> Building Release"
# -quiet still prints warnings and errors; on failure the log is replayed in
# full, so a broken build is not hidden behind the quiet flag.
LOG="$BUILD_DIR/build.log"
mkdir -p "$BUILD_DIR"
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

BUILT="$BUILD_DIR/Build/Products/Release/Speaky.app"
[ -d "$BUILT" ] || { echo "Build produced no app at $BUILT" >&2; exit 1; }
fi

if pgrep -f "$APP/Contents/MacOS/Speaky" >/dev/null 2>&1; then
  echo "==> Quitting the running copy"
  osascript -e 'tell application "Speaky" to quit' 2>/dev/null || true
  sleep 1
fi

echo "==> Installing to $APP"
rm -rf "$APP"
cp -R "$BUILT" "$APP"

echo "==> Launching"
open "$APP"

cat <<'NOTE'

Installed.

If this is a first install, Speaky needs Accessibility permission:
  System Settings → Privacy & Security → Accessibility

The permission is read at process start, so relaunch Speaky after granting it.
NOTE
