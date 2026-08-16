#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP="$ROOT_DIR/dist/BlurFollow.app"

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

if [[ "${1:-}" == "--distribution" ]]; then
    spctl --assess --type execute --verbose=4 "$APP"
fi

print "Release checks passed."
