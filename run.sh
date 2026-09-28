#!/bin/bash
# Builds a debug Claudiostat.app in /tmp/claudiostat-run and opens it, quitting any running copy first.
set -euo pipefail
cd "$(dirname "$0")"

WORK=/tmp/claudiostat-run
export TMPDIR="$WORK/tmp" SWIFTPM_MODULECACHE_OVERRIDE="$WORK/modules" CLANG_MODULE_CACHE_PATH="$WORK/modules"
mkdir -p "$TMPDIR"
SWIFT_OPTS=(--scratch-path "$WORK/build" --cache-path "$WORK/cache" --config-path "$WORK/config"
            --security-path "$WORK/security" --manifest-cache none)

swift build "${SWIFT_OPTS[@]}"
BIN=$(swift build "${SWIFT_OPTS[@]}" --show-bin-path)

APP="$WORK/Claudiostat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Claudiostat" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
swift -module-cache-path "$WORK/modules" Icon/make-icon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# Same bundle id as the installed copy: while it runs, open would just bring that one forward.
pkill -x Claudiostat || true
while pgrep -x Claudiostat >/dev/null; do sleep 0.2; done
open "$APP"
echo "Running $APP"
