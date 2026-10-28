#!/bin/bash
# Runs the tests, builds ClaudioStat.app and writes dist/ClaudioStat-<version>.dmg.
# `./build.sh app` stops at the unsigned dist/dmg/ClaudioStat.app, and `./build.sh dmg` signs that app and makes the DMG.
# Every intermediate (SwiftPM build, caches, module cache, TMPDIR) lives in one /tmp dir deleted on exit.
set -euo pipefail
cd "$(dirname "$0")"
MODE=${1:-all}

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG="dist/ClaudioStat-$VERSION.dmg"
WORK=$(mktemp -d /tmp/claudiostat.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR"
SWIFT_OPTS=(--scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config"
            --security-path "$WORK/security" --manifest-cache none)
# Swift Build writes the constants widget.sh makes the widget's App Intents file from.
RELEASE_OPTS=(-c release --arch arm64 --arch x86_64 --build-system swiftbuild)
APP=dist/dmg/ClaudioStat.app
WIDGET="$APP/Contents/PlugIns/ClaudioStatWidget.appex"

if [ "$MODE" != dmg ]; then
swift test "${SWIFT_OPTS[@]}"
swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}"
BIN=$(swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}" --show-bin-path)

rm -rf dist/dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# SwiftPM marks the app as built with the macOS 15 SDK, so macOS 26 and later draw it in their old look: smaller
# switches, older buttons. Marked with the SDK it was built with, it gets System Settings' look.
vtool -set-build-version macos "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Info.plist)" "$(xcrun --show-sdk-version)" \
    -replace -output "$APP/Contents/MacOS/ClaudioStat" "$BIN/ClaudioStat"
cp Info.plist "$APP/Contents/"
swift -module-cache-path "$WORK/modules" Icon/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
./widget.sh "$APP" "$BIN" "$WORK/build"
# The DMG window's background lives inside the app, so the DMG shows nothing but the app and Applications.
swift -module-cache-path "$WORK/modules" Icon/make-dmg-background.swift "$WORK/bg"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" \
    -out "$APP/Contents/Resources/dmg-background.tiff"
fi
[ "$MODE" != app ] || exit 0
[ -d "$APP" ] || { echo "$APP is missing: run ./build.sh app first." >&2; exit 1; }

# Notarization requires the hardened runtime and a secure timestamp. Without SIGN_ID the app is signed ad hoc.
# The widget first, inside out; each gets the group it shares with the other.
codesign --force --options runtime ${SIGN_ID:+--timestamp} --entitlements Sources/ClaudioStatWidget/Widget.entitlements \
    --sign "${SIGN_ID:--}" "$WIDGET"
codesign --force --options runtime ${SIGN_ID:+--timestamp} --entitlements ClaudioStat.entitlements --sign "${SIGN_ID:--}" "$APP"
codesign --verify --strict "$APP"
ln -sfn /Applications dist/dmg/Applications

# The window's layout (background, icon spots) as Finder saved it, so no Finder window opens while a release builds.
# dmg/layout.sh makes it again when the background or the icon spots change.
cp dmg/layout.DS_Store dist/dmg/.DS_Store
hdiutil create -quiet -volname ClaudioStat -srcfolder dist/dmg -format UDZO -ov "$DMG"
echo "Built $(pwd)/$DMG"
