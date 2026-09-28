#!/bin/bash
# Runs the tests, builds Claudiostat.app and writes dist/Claudiostat.dmg.
# Every intermediate (SwiftPM build, caches, module cache, TMPDIR) lives in one /tmp dir deleted on exit.
set -euo pipefail
cd "$(dirname "$0")"

WORK=$(mktemp -d /tmp/claudiostat.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR"
SWIFT_OPTS=(--scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config"
            --security-path "$WORK/security" --manifest-cache none)
RELEASE_OPTS=(-c release --arch arm64 --arch x86_64)

swift test "${SWIFT_OPTS[@]}"
swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}"
BIN=$(swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}" --show-bin-path)

APP="$WORK/dmg/Claudiostat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Claudiostat" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
swift -module-cache-path "$WORK/modules" Icon/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
ln -s /Applications "$WORK/dmg/Applications"

mkdir -p dist
hdiutil create -quiet -volname Claudiostat -srcfolder "$WORK/dmg" -format UDZO -ov dist/Claudiostat.dmg
echo "Built $(pwd)/dist/Claudiostat.dmg"
