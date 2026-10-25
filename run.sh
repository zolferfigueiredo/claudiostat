#!/bin/bash
# Builds a debug ClaudioStat.app in /tmp/claudiostat-run and opens it, quitting any running copy first.
set -euo pipefail
cd "$(dirname "$0")"

WORK=/tmp/claudiostat-run
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR"
# Swift Build writes the constants widget.sh makes the widget's App Intents file from.
SWIFT_OPTS=(--scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config"
            --security-path "$WORK/security" --manifest-cache none --build-system swiftbuild)

swift build "${SWIFT_OPTS[@]}"
BIN=$(swift build "${SWIFT_OPTS[@]}" --show-bin-path)

APP="$WORK/ClaudioStat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/ClaudioStat" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
swift -module-cache-path "$WORK/modules" Icon/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
./widget.sh "$APP" "$BIN" "$WORK/build"
WIDGET="$APP/Contents/PlugIns/ClaudioStatWidget.appex"
# The widget reads its numbers from a group only a team's signature opens, so the Developer ID signs when it's here.
SIGN_ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"$/\1/p' | sed -n 1p)
codesign --force --entitlements Sources/ClaudioStatWidget/Widget.entitlements --sign "${SIGN_ID:--}" "$WIDGET"
codesign --force --entitlements ClaudioStat.entitlements --sign "${SIGN_ID:--}" "$APP"

# Same bundle id as the installed copy: while it runs, open would just bring that one forward.
# -i: builds before 0.2.0 run as Claudiostat. -U: another user's copy is theirs, and can't be quit from here.
pkill -ix -U "$(id -u)" claudiostat || true
while pgrep -ix -U "$(id -u)" claudiostat >/dev/null; do sleep 0.2; done
# A widget still running from the last build would keep answering for the new one.
pkill -x -U "$(id -u)" ClaudioStatWidget || true
open "$APP" --args "$@"
echo "Running $APP"
