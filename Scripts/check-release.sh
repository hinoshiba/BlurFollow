#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP="$ROOT_DIR/dist/BlurFollow.app"

if [[ $# -ne 0 ]]; then
    print -u2 "Usage: $0"
    exit 64
fi

/bin/zsh -n "$ROOT_DIR/build.sh" "$ROOT_DIR"/Scripts/*.sh
/bin/sh -n "$ROOT_DIR"/ci_scripts/*.sh
for cloud_script in "$ROOT_DIR"/ci_scripts/*.sh; do
    if [[ ! -x "$cloud_script" ]]; then
        print -u2 "Xcode Cloud script is not executable: $cloud_script"
        exit 1
    fi
done
plutil -lint "$ROOT_DIR/BlurFollow/Resources/Info.plist" \
    "$ROOT_DIR/BlurFollow/Resources/BlurFollow.entitlements" \
    "$ROOT_DIR/BlurFollow/Resources/PrivacyInfo.xcprivacy"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/BlurFollow/Resources/Info.plist")" != '$(MARKETING_VERSION)' || \
      "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/BlurFollow/Resources/Info.plist")" != '$(CURRENT_PROJECT_VERSION)' ]]; then
    print -u2 'BlurFollow Info.plist must inherit version/build from Xcode settings.'
    exit 1
fi

"$ROOT_DIR/Scripts/check-localizations.sh"

if [[ ! -d "$APP" ]]; then
    print -u2 "Missing dist/BlurFollow.app"
    exit 1
fi

codesign --verify --strict --verbose=2 "$APP"
plutil -lint "$APP/Contents/Info.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" != "com.hinoshiba.blurfollow" ]]; then
    print -u2 "Unexpected bundle identifier."
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP/Contents/Info.plist")" != "BlurFollow" ]]; then
    print -u2 "Unexpected display name."
    exit 1
fi
PROJECT_VERSION=$(awk '$1 == "MARKETING_VERSION:" { gsub(/"/, "", $2); print $2; exit }' "$ROOT_DIR/project.yml")
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
if [[ "$APP_VERSION" != "$PROJECT_VERSION" ]] || \
   ! grep -F -q "MARKETING_VERSION = $PROJECT_VERSION;" "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj"; then
    print -u2 "Development app, project.yml, and checked-in Xcode project versions differ."
    exit 1
fi
if ! grep -F -q 'DEVELOPMENT_TEAM = 94HVVWXLK3;' "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj" || \
   ! grep -F -q 'PRODUCT_BUNDLE_IDENTIFIER = com.hinoshiba.blurfollow;' "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj"; then
    print -u2 "Checked-in Xcode project has an unexpected Team or bundle identifier."
    exit 1
fi
test -f "$APP/Contents/Resources/LICENSE"
test -f "$APP/Contents/Resources/NOTICE"
test -f "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
test -f "$APP/Contents/Resources/TRADEMARKS.md"
test -f "$APP/Contents/Resources/PRIVACY.md"
test -f "$APP/Contents/Resources/DEPENDENCIES.md"
test -f "$APP/Contents/Resources/Brand/PROVENANCE.md"
test -f "$APP/Contents/Resources/SECURITY.md"
test -f "$APP/Contents/Resources/Docs/RELEASE.md"
test -f "$APP/Contents/Resources/Docs/THREAT_MODEL.md"
test -f "$APP/Contents/Resources/Docs/COMPATIBILITY.md"
test -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
test -f "$APP/Contents/Resources/ja.lproj/Localizable.strings"
test -f "$APP/Contents/Resources/en.lproj/Localizable.strings"
test -f "$APP/Contents/Resources/ja.lproj/InfoPlist.strings"
test -f "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
for locale in ja en; do
    cmp "$ROOT_DIR/BlurFollow/Resources/$locale.lproj/Localizable.strings" \
        "$APP/Contents/Resources/$locale.lproj/Localizable.strings"
    cmp "$ROOT_DIR/BlurFollow/Resources/$locale.lproj/InfoPlist.strings" \
        "$APP/Contents/Resources/$locale.lproj/InfoPlist.strings"
done

LEGACY_PATTERN='veilpin|safe[ -]?share|share[ -]?check|protected output|protection on|protection paused|share this window|not ready to share|privacy that stays|privacy that moves'
if rg -i "$LEGACY_PATTERN" "$APP/Contents" -g '!*.png' >/dev/null; then
    print -u2 "Legacy brand or product copy remains in the app bundle."
    exit 1
fi
if strings "$APP/Contents/MacOS/BlurFollow" | rg -i "$LEGACY_PATTERN" >/dev/null; then
    print -u2 "Legacy brand or product copy remains in the executable."
    exit 1
fi
if find "$APP" \( -iname '*veilpin*' -o -iname '*safeshare*' -o -iname '*sharecheck*' \) -print | rg -q .; then
    print -u2 "Legacy brand filename remains in the app bundle."
    exit 1
fi

ENTITLEMENTS_FILE=$(mktemp /tmp/blurfollow-entitlements.XXXXXX)
trap 'rm -f "$ENTITLEMENTS_FILE"' EXIT
codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS_FILE" 2>/dev/null
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS_FILE")" != "true" ]]; then
    print -u2 "App Sandbox entitlement is missing."
    exit 1
fi
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$ENTITLEMENTS_FILE")" != "true" ]]; then
    print -u2 "User-selected file entitlement is missing."
    exit 1
fi

if otool -L "$APP/Contents/MacOS/BlurFollow" | tail -n +2 | rg -v '^\s+(/System/Library|/usr/lib)' >/dev/null; then
    print -u2 "Unexpected non-system dynamic library detected:"
    otool -L "$APP/Contents/MacOS/BlurFollow"
    exit 1
fi

print "Release checks passed."
