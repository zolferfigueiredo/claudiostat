#!/bin/bash
# Builds dist/ClaudioStat-<version>.dmg, then signs and notarizes it with Developer ID.
# One-time setup, shared with TheeJ: xcrun notarytool store-credentials bihan --key <AuthKey.p8> --key-id <id> --issuer <issuer-id>
set -euo pipefail
cd "$(dirname "$0")"

export SIGN_ID="Developer ID Application: Zolfer Figueiredo (497V6MCDS8)"
DMG="dist/ClaudioStat-$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist).dmg"

./build.sh
codesign --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile bihan --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
echo "Release ready: $(pwd)/$DMG"
