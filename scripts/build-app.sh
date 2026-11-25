#!/bin/bash
# Builds "Nothing X Mac.app" into build/. Needs only the Xcode Command Line Tools.
#
#   scripts/build-app.sh              release build for this Mac's chip
#   scripts/build-app.sh --universal  arm64 + x86_64
#   scripts/build-app.sh --install    also copy to /Applications
#   VERSION=1.2.0 scripts/build-app.sh  stamp a version into Info.plist (CI sets this from the tag)
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install) INSTALL=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [ "$UNIVERSAL" = 1 ]; then
  swift build -c release --product NothingXMac --arch arm64 --arch x86_64
  BIN="$(swift build -c release --product NothingXMac --arch arm64 --arch x86_64 --show-bin-path)/NothingXMac"
else
  swift build -c release --product NothingXMac
  BIN="$(swift build -c release --product NothingXMac --show-bin-path)/NothingXMac"
fi

APP="build/Nothing X Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NothingXMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough for Bluetooth permission and Open at Login on this Mac.
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
  pkill -x NothingXMac 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/Nothing X Mac.app"
  ditto "$APP" "/Applications/Nothing X Mac.app"
  echo "Installed to /Applications/Nothing X Mac.app"
fi
