#!/usr/bin/env bash
#
# Builds Speaky in Release and installs it to /Applications.
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

echo "==> Building Release"
xcodebuild \
  -project "$PROJECT_DIR/Speaky.xcodeproj" \
  -scheme Speaky \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  build

BUILT="$BUILD_DIR/Build/Products/Release/Speaky.app"
[ -d "$BUILT" ] || { echo "Build produced no app at $BUILT" >&2; exit 1; }

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
