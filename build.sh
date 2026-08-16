#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
MODE="dev"
if [[ "${1:-}" == "--dist" ]]; then
    MODE="dist"
fi

cd "$ROOT_DIR"

if [[ "$MODE" == "dist" ]]; then
    if [[ -z "${BLURFOLLOW_SIGN_IDENTITY:-}" ]]; then
        print -u2 "BLURFOLLOW_SIGN_IDENTITY must name a Developer ID Application certificate."
        exit 1
    fi
    swift build -c release --arch arm64 --arch x86_64
    BIN="$ROOT_DIR/.build/apple/Products/Release/BlurFollow"
else
    swift build -c debug
    BIN_PATH=$(swift build -c debug --show-bin-path)
    BIN="$BIN_PATH/BlurFollow"
fi

APP="$ROOT_DIR/dist/BlurFollow.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$CONTENTS/Resources/Brand" "$CONTENTS/Resources/Docs"

cp "$BIN" "$CONTENTS/MacOS/BlurFollow"
cp "$ROOT_DIR/BlurFollow/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable BlurFollow" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.blurfollow.app" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName BlurFollow" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${BLURFOLLOW_VERSION:-0.1.0}" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BLURFOLLOW_BUILD_NUMBER:-1}" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$CONTENTS/Info.plist"

ICONSET="$ROOT_DIR/BlurFollow/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_STAGE_ROOT=$(mktemp -d /tmp/blurfollow-icon.XXXXXX)
trap 'rm -rf "$ICON_STAGE_ROOT"' EXIT
mkdir -p "$ICON_STAGE_ROOT/AppIcon.iconset"
cp "$ICONSET"/*.png "$ICON_STAGE_ROOT/AppIcon.iconset/"
iconutil -c icns "$ICON_STAGE_ROOT/AppIcon.iconset" -o "$CONTENTS/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"

cp -R "$ROOT_DIR/BlurFollow/Resources/ja.lproj" "$CONTENTS/Resources/"
cp -R "$ROOT_DIR/BlurFollow/Resources/en.lproj" "$CONTENTS/Resources/"
cp "$ROOT_DIR/BlurFollow/Resources/PrivacyInfo.xcprivacy" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
cp "$ROOT_DIR/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$ROOT_DIR/NOTICE" "$CONTENTS/Resources/NOTICE"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.md"
cp "$ROOT_DIR/TRADEMARKS.md" "$CONTENTS/Resources/TRADEMARKS.md"
cp "$ROOT_DIR/PRIVACY.md" "$CONTENTS/Resources/PRIVACY.md"
cp "$ROOT_DIR/DEPENDENCIES.md" "$CONTENTS/Resources/DEPENDENCIES.md"
cp "$ROOT_DIR/Brand/PROVENANCE.md" "$CONTENTS/Resources/Brand/PROVENANCE.md"
cp "$ROOT_DIR/SECURITY.md" "$CONTENTS/Resources/SECURITY.md"
cp "$ROOT_DIR/Docs/RELEASE.md" "$CONTENTS/Resources/Docs/RELEASE.md"
cp "$ROOT_DIR/Docs/THREAT_MODEL.md" "$CONTENTS/Resources/Docs/THREAT_MODEL.md"
cp "$ROOT_DIR/Docs/COMPATIBILITY.md" "$CONTENTS/Resources/Docs/COMPATIBILITY.md"
printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ "$MODE" == "dist" ]]; then
    codesign --force --options runtime --timestamp \
        --entitlements "$ROOT_DIR/BlurFollow/Resources/BlurFollow.entitlements" \
        --sign "$BLURFOLLOW_SIGN_IDENTITY" "$APP"
else
    codesign --force \
        --entitlements "$ROOT_DIR/BlurFollow/Resources/BlurFollow.entitlements" \
        --sign - "$APP"
fi

codesign --verify --strict --verbose=2 "$APP"
print "Built $APP"
