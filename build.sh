#!/bin/bash
# Runs the tests, builds ClaudioStat.app and writes dist/ClaudioStat-<version>.dmg.
# Every intermediate (SwiftPM build, caches, module cache, TMPDIR) lives in one /tmp dir deleted on exit.
set -euo pipefail
cd "$(dirname "$0")"
# Finder finds the volume to lay out by name, so no other ClaudioStat volume (or "ClaudioStat 1"...) may be mounted.
! mount | grep -qi ' on /Volumes/ClaudioStat' || { echo "Eject every mounted ClaudioStat volume first" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG="dist/ClaudioStat-$VERSION.dmg"
WORK=$(mktemp -d /tmp/claudiostat.XXXXXX)
trap 'if [ -n "${MNT:-}" ]; then hdiutil detach -quiet -force "$MNT"; fi; rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR"
SWIFT_OPTS=(--scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config"
            --security-path "$WORK/security" --manifest-cache none)
RELEASE_OPTS=(-c release --arch arm64 --arch x86_64)

swift test "${SWIFT_OPTS[@]}"
swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}"
BIN=$(swift build "${RELEASE_OPTS[@]}" "${SWIFT_OPTS[@]}" --show-bin-path)

APP="$WORK/dmg/ClaudioStat.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Claudiostat" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
swift -module-cache-path "$WORK/modules" Icon/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
# Notarization requires the hardened runtime and a secure timestamp. Without SIGN_ID the app is signed ad hoc.
codesign --force --options runtime ${SIGN_ID:+--timestamp} --sign "${SIGN_ID:--}" "$APP"
codesign --verify --strict "$APP"
ln -s /Applications "$WORK/dmg/Applications"
swift -module-cache-path "$WORK/modules" Icon/make-dmg-background.swift "$WORK/bg"
mkdir "$WORK/dmg/.background"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" -out "$WORK/dmg/.background/background.tiff"

# Finder lays out the window (background, icon spots) and saves it in the volume's .DS_Store.
# Icon positions must match the arrow in Icon/make-dmg-background.swift.
hdiutil create -quiet -volname ClaudioStat -srcfolder "$WORK/dmg" -format UDRW "$WORK/rw.dmg"
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
    set background picture of opts to file ".background:background.tiff"
    set position of item "ClaudioStat.app" to {160, 190}
    set position of item "Applications" to {480, 190}
    update without registering applications
    close
end tell
EOF
until [ -f "$MNT/.DS_Store" ]; do sleep 1; done
rm -rf "$MNT/.fseventsd"
sync
hdiutil detach -quiet "$MNT"
MNT=

mkdir -p dist
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -ov -o "$DMG"
echo "Built $(pwd)/$DMG"
