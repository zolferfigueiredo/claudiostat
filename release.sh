#!/bin/bash
# Bump both versions in Info.plist first. Builds dist/ClaudioStat-<version>.dmg, signs and notarizes it with Developer ID,
# then publishes it as a GitHub release of the current commit, which must be pushed.
# .github/workflows/release.yml runs it in two halves on every push to main:
#   ./release.sh build  the tests and the unsigned dist/dmg/ClaudioStat.app, on GitHub's Mac
#   ./release.sh sign   Developer ID, the DMG, notarization and the release, on the self-hosted runner on z's Mac
# With neither it does both, by hand. Both stop early when this version is already released.
# One-time setup: xcrun notarytool store-credentials bihan --key <AuthKey.p8> --key-id <id> --issuer <issuer-id>
set -euo pipefail
cd "$(dirname "$0")"
MODE=all
case "${1:-}" in build | sign) MODE=$1; shift ;; esac

export SIGN_ID="Developer ID Application: Zolfer Figueiredo (497V6MCDS8)"
NAME=ClaudioStat
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
DMG="dist/$NAME-$VERSION.dmg"
if gh release view "v$VERSION" -R zolferfigueiredo/claudiostat >/dev/null 2>&1; then
  echo "v$VERSION is already released."
  exit 0
fi

case $MODE in
  build) exec ./build.sh app ;;
  sign) ./build.sh dmg ;;
  *) ./build.sh ;;
esac
codesign --timestamp --sign "$SIGN_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile bihan --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
echo "Release ready: $(pwd)/$DMG"
[ "${1:-}" != --url ] || {
  loc=$(curl -fsS -o /dev/null -w '%{redirect_url}' --data-urlencode "url=https://claudiostat.zolfer.com/$NAME-$VERSION.dmg" https://url.zolfer.com/dmg)
  echo "Download link: https://url.zolfer.com/${loc##*c=}"
}
# The apps learn the newest version from releases/latest/download/latest.json, the same file the website serves.
printf '{"version": "%s"}\n' "$VERSION" > dist/latest.json
gh release create "v$VERSION" "$DMG" dist/latest.json -R zolferfigueiredo/claudiostat --target "$(git rev-parse HEAD)" --title "$NAME $VERSION" --generate-notes
