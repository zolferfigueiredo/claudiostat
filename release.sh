#!/bin/bash
# Bump both versions in Info.plist first. Builds dist/ClaudioStat-<version>.dmg, signs and notarizes it with Developer ID,
# then publishes it as a GitHub release of the current commit, which must be pushed. The website repo's release script puts it on the site.
# One-time setup: xcrun notarytool store-credentials bihan --key <AuthKey.p8> --key-id <id> --issuer <issuer-id>
set -euo pipefail
cd "$(dirname "$0")"

export SIGN_ID="Developer ID Application: Zolfer Figueiredo (497V6MCDS8)"
NAME=ClaudioStat
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG="dist/$NAME-$VERSION.dmg"

./build.sh
codesign --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile bihan --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
echo "Release ready: $(pwd)/$DMG"
[ "${1:-}" != --url ] || {
  loc=$(curl -fsS -o /dev/null -w '%{redirect_url}' --data-urlencode "url=https://claudiostat.zolfer.com/$NAME-$VERSION.dmg" https://url.zolfer.com/dmg)
  echo "Download link: https://url.zolfer.com/${loc##*c=}"
}
# Casks/claudiostat.rb always installs releases/latest/download/ClaudioStat.dmg, so every release carries a copy under that name.
cp "$DMG" "dist/$NAME.dmg"
gh release view "v$VERSION" -R zolferfigueiredo/claudiostat >/dev/null 2>&1 ||
  gh release create "v$VERSION" "$DMG" "dist/$NAME.dmg" -R zolferfigueiredo/claudiostat --target "$(git rev-parse HEAD)" --title "$NAME $VERSION" --generate-notes
