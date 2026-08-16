#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h}
cd "$ROOT_DIR"

if [[ $# -ne 0 ]]; then
    print -u2 "Usage: ./build.sh"
    print -u2 "Official releases are built from v<version> tags by Xcode Cloud."
    exit 64
fi

swift build -c debug
BIN_PATH=$(swift build -c debug --show-bin-path)
BIN="$BIN_PATH/BlurFollow"
VERSION=$(awk '$1 == "MARKETING_VERSION:" { gsub(/"/, "", $2); print $2; exit }' project.yml)
BUILD_NUMBER=$(awk '$1 == "CURRENT_PROJECT_VERSION:" { gsub(/"/, "", $2); print $2; exit }' project.yml)

APP="$ROOT_DIR/dist/BlurFollow.app"
CONTENTS="$APP/Contents"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$CONTENTS/Resources/Brand" "$CONTENTS/Resources/Docs"

cp "$BIN" "$CONTENTS/MacOS/BlurFollow"
cp "$ROOT_DIR/BlurFollow/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable BlurFollow" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.hinoshiba.blurfollow" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName BlurFollow" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
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

codesign --force \
    --entitlements "$ROOT_DIR/BlurFollow/Resources/BlurFollow.entitlements" \
    --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
print "Built development app $APP"
print -u2 "DEVELOPMENT ONLY — dist/BlurFollow.app must not be published."
