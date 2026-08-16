#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP="$ROOT_DIR/dist/BlurFollow.app"
VERSION=${BLURFOLLOW_VERSION:-0.1.0}
DMG="$ROOT_DIR/dist/BlurFollow-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
    print -u2 "Run ./build.sh --dist first."
    exit 1
fi

STAGING=$(mktemp -d /tmp/blurfollow-dmg.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/BlurFollow.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create -volname "BlurFollow" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [[ -n "${BLURFOLLOW_SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$BLURFOLLOW_SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${BLURFOLLOW_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$BLURFOLLOW_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi

shasum -a 256 "$DMG" > "$DMG.sha256"
print "Created $DMG"
