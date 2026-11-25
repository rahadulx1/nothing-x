#!/bin/bash
# Packages build/Nothing X Mac.app into a drag-to-Applications DMG and a zip,
# plus SHA256SUMS.txt, in dist/. Run scripts/build-app.sh first.
#
#   scripts/make-dmg.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/make-dmg.sh <version>}"
APP="build/Nothing X Mac.app"
NAME="Nothing-X-Mac-$VERSION"
[ -d "$APP" ] || { echo "missing $APP: run scripts/build-app.sh first" >&2; exit 1; }

rm -rf dist && mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/Nothing X Mac.app"
ln -s /Applications "$STAGE/Applications"
# hdiutil sometimes fails with "Resource busy" on CI runners; retry a few times.
for attempt in 1 2 3 4 5; do
  if hdiutil create -volname "Nothing X Mac" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "dist/$NAME.dmg" >/dev/null 2>&1; then
    break
  fi
  [ "$attempt" = 5 ] && { echo "hdiutil failed" >&2; exit 1; }
  sleep $((attempt * 3))
done
ditto -c -k --keepParent "$APP" "dist/$NAME.zip"

(cd dist && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
ls -lh dist
cat dist/SHA256SUMS.txt
