#!/bin/bash
# Puts the desktop widget (Sources/ClaudioStatWidget) into an app that build.sh or run.sh made, as Xcode would: the
# binary, its Info.plist with the app's versions, the app's strings, and the App Intents file. They sign it afterwards.
#   ./widget.sh <app> <swift build's bin folder> <swift build's scratch folder>
set -euo pipefail
cd "$(dirname "$0")"
APP=$1 BIN=$2 BUILD=$3
WIDGET="$APP/Contents/PlugIns/ClaudioStatWidget.appex"

rm -rf "$WIDGET"
mkdir -p "$WIDGET/Contents/MacOS" "$WIDGET/Contents/Resources"
cp "$BIN/ClaudioStatWidget" "$WIDGET/Contents/MacOS/"
cp Sources/ClaudioStatWidget/Info.plist "$WIDGET/Contents/"
for key in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Set $key $(/usr/libexec/PlistBuddy -c "Print $key" Info.plist)" "$WIDGET/Contents/Info.plist"
done
# The widget speaks the app's Strings/ itself; macOS needs them as files for Edit Widget's names.
"$BIN/WidgetStrings" "$WIDGET/Contents/Resources"

# Edit Widget's choices: without this file macOS has none to give the widget, and the widget gets no numbers.
# It is made from constants the compiler writes under the Swift Build engine (--build-system swiftbuild); one
# architecture's are enough.
LISTS=$(mktemp -d)
trap 'rm -rf "$LISTS"' EXIT
ls "$PWD"/Sources/ClaudioStatWidget/*.swift > "$LISTS/sources"
find "$BUILD" -path "*/$(basename "$BIN")/ClaudioStatWidget*.build/Objects-normal/arm64/*.swiftconstvalues" > "$LISTS/constants"
if [ ! -s "$LISTS/constants" ]; then
  echo "No App Intents constants under $BUILD: build with swift build --build-system swiftbuild." >&2
  exit 1
fi
xcrun appintentsmetadataprocessor --output "$WIDGET/Contents/Resources" --module-name ClaudioStatWidget \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swift)")")")" --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | sed -n 's/^Build version //p')" --platform-family macOS \
  --deployment-target 15.0 --target-triple arm64-apple-macos15.0 \
  --source-file-list "$LISTS/sources" --swift-const-vals-list "$LISTS/constants" >/dev/null
if [ ! -f "$WIDGET/Contents/Resources/Metadata.appintents/extract.actionsdata" ]; then
  echo "appintentsmetadataprocessor made no App Intents file." >&2
  exit 1
fi
