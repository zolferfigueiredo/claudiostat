#!/bin/bash
# Runs the tests, builds ClaudioStat.app and writes dist/ClaudioStat-<version>.dmg.
# `./build.sh app` stops at the unsigned dist/dmg/ClaudioStat.app, and `./build.sh dmg` signs that app and makes the DMG.
# Every intermediate (SwiftPM build, caches, module cache, TMPDIR) lives in one /tmp dir deleted on exit.
set -euo pipefail
cd "$(dirname "$0")"
MODE=${1:-all}
# Finder finds the volume to lay out by name, so every mounted ClaudioStat volume ("ClaudioStat 1"...) is ejected first.
mount | { grep -i " on /Volumes/ClaudioStat" || true; } | sed 's|^.* on \(/Volumes/[^(]*\) (.*|\1|' |
    while IFS= read -r volume; do hdiutil detach -quiet -force "$volume"; done

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG="dist/ClaudioStat-$VERSION.dmg"
WORK=$(mktemp -d /tmp/claudiostat.XXXXXX)
trap 'if [ -n "${MNT:-}" ]; then hdiutil detach -quiet -force "$MNT"; fi; rm -rf "$WORK"' EXIT
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
cp "$BIN/ClaudioStat" "$APP/Contents/MacOS/"
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

# Finder lays out the window (background, icon spots) and saves it in the volume's .DS_Store.
# Icon positions must match the arrow in Icon/make-dmg-background.swift.
hdiutil create -quiet -volname ClaudioStat -srcfolder dist/dmg -format UDRW "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
MNT=/Volumes/ClaudioStat
osascript <<'EOF'
tell application "Finder" to tell disk "ClaudioStat"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 120, 840, 520}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file "ClaudioStat.app:Contents:Resources:dmg-background.tiff"
    set position of item "ClaudioStat.app" to {160, 190}
    set position of item "Applications" to {480, 190}
    update without registering applications
    close
end tell
EOF
# A Finder that can't be scripted would leave this waiting for ever.
for i in $(seq 61); do
    [ ! -f "$MNT/.DS_Store" ] || break
    [ "$i" -le 60 ] || { echo "Finder didn't lay out the DMG within a minute." >&2; exit 1; }
    sleep 1
done
rm -rf "$MNT/.fseventsd" "$MNT/.Trashes"
sync
hdiutil detach -quiet "$MNT"
MNT=

hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -ov -o "$DMG"
echo "Built $(pwd)/$DMG"
