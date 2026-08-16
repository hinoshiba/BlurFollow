#!/bin/sh
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    exit 0
fi

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    echo "error: App Store archives must run in Xcode Cloud" >&2
    exit 1
fi

: "${CI_TAG:?Xcode Cloud release archives require a Git tag}"
: "${CI_BUILD_NUMBER:?Xcode Cloud did not provide a build number}"
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud did not provide the repository path}"

if ! printf '%s\n' "$CI_TAG" | /usr/bin/grep -Eq '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'; then
    echo "error: release tags must use v<major>.<minor>.<patch>: $CI_TAG" >&2
    exit 1
fi
if ! printf '%s\n' "$CI_BUILD_NUMBER" | /usr/bin/grep -Eq '^[1-9][0-9]*$'; then
    echo "error: CI_BUILD_NUMBER must be a positive integer: $CI_BUILD_NUMBER" >&2
    exit 1
fi

ROOT=$CI_PRIMARY_REPOSITORY_PATH
PROJECT_VERSION=$(/usr/bin/awk '$1 == "MARKETING_VERSION:" { gsub(/"/, "", $2); print $2; exit }' "$ROOT/project.yml")
TAG_VERSION=${CI_TAG#v}

if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/BlurFollow/Resources/Info.plist")" != '$(MARKETING_VERSION)' ] || \
   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/BlurFollow/Resources/Info.plist")" != '$(CURRENT_PROJECT_VERSION)' ]; then
    echo "error: BlurFollow Info.plist must inherit its version and build from Xcode settings" >&2
    exit 1
fi

if [ -z "$PROJECT_VERSION" ] || [ "$TAG_VERSION" != "$PROJECT_VERSION" ]; then
    echo "error: tag $CI_TAG does not match MARKETING_VERSION ${PROJECT_VERSION:-<missing>}" >&2
    exit 1
fi

PBX_PROJECT_VERSION=$(/usr/bin/sed -n \
    's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' \
    "$ROOT/BlurFollow.xcodeproj/project.pbxproj" | /usr/bin/sort -u)
if [ "$PBX_PROJECT_VERSION" != "$PROJECT_VERSION" ]; then
    echo "error: checked-in Xcode project does not match project.yml MARKETING_VERSION" >&2
    exit 1
fi

if [ "${CI_PRODUCT_PLATFORM:-}" != "macOS" ] || \
   [ "${CI_XCODE_SCHEME:-}" != "BlurFollow" ] || \
   [ "${CI_BUNDLE_ID:-}" != "com.hinoshiba.blurfollow" ] || \
   [ "${CI_TEAM_ID:-}" != "94HVVWXLK3" ]; then
    echo "error: Xcode Cloud release product, scheme, bundle ID, platform, or team is misconfigured" >&2
    exit 1
fi

PROJECT_FILE="$ROOT/BlurFollow.xcodeproj/project.pbxproj"
/usr/bin/sed -i '' -E \
    "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\\1${CI_BUILD_NUMBER};/g" "$PROJECT_FILE"
APPLIED_BUILD=$(/usr/bin/sed -n \
    's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' \
    "$PROJECT_FILE" | /usr/bin/sort -u)
if [ "$APPLIED_BUILD" != "$CI_BUILD_NUMBER" ]; then
    echo "error: failed to apply Xcode Cloud build number $CI_BUILD_NUMBER" >&2
    exit 1
fi

echo "Prepared BlurFollow App Store release tag $CI_TAG (build $CI_BUILD_NUMBER)."
