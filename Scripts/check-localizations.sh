#!/bin/zsh
set -euo pipefail

ROOT_DIR=${0:A:h:h}
RESOURCE_DIR="$ROOT_DIR/BlurFollow/Resources"
TEMP_DIR=$(mktemp -d /tmp/blurfollow-localizations.XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

typeset -a LOCALES=(ja en)
typeset -a TABLES=(Localizable InfoPlist)

fail() {
    print -u2 "Localization check failed: $*"
    exit 1
}

command -v jq >/dev/null || fail "jq is required."
xcrun --find xcstringstool >/dev/null 2>&1 || fail "xcstringstool is required."

print -l $LOCALES | LC_ALL=C sort > "$TEMP_DIR/expected-locales"
find "$RESOURCE_DIR" -maxdepth 1 -type d -name '*.lproj' -exec basename {} .lproj \; \
    | LC_ALL=C sort > "$TEMP_DIR/actual-locales"
if ! diff -u "$TEMP_DIR/expected-locales" "$TEMP_DIR/actual-locales"; then
    fail "Resource localizations must contain exactly ja and en."
fi

for locale in $LOCALES; do
    for table in $TABLES; do
        file="$RESOURCE_DIR/$locale.lproj/$table.strings"
        [[ -f "$file" ]] || fail "Missing $locale.lproj/$table.strings"
        plutil -lint "$file" >/dev/null
        plutil -convert json -o - "$file" \
            | jq -e 'type == "object" and all(.[]; type == "string" and length > 0)' >/dev/null \
            || fail "$locale.lproj/$table.strings contains a non-string or empty value."
        source_entry_count=$(rg -c '^"' "$file")
        parsed_entry_count=$(plutil -convert json -o - "$file" | jq 'length')
        [[ "$source_entry_count" == "$parsed_entry_count" ]] \
            || fail "$locale.lproj/$table.strings contains a duplicate or malformed key."
        plutil -convert json -o - "$file" | jq -r 'keys[]' | LC_ALL=C sort \
            > "$TEMP_DIR/$locale-$table.keys"
    done
done

for table in $TABLES; do
    if ! diff -u "$TEMP_DIR/ja-$table.keys" "$TEMP_DIR/en-$table.keys"; then
        fail "ja/en key parity failed for $table.strings."
    fi
done

typeset -a REQUIRED_INFO_KEYS=(
    CFBundleDisplayName
    CFBundleName
    NSHumanReadableCopyright
    NSScreenCaptureUsageDescription
)
for locale in $LOCALES; do
    info_file="$RESOURCE_DIR/$locale.lproj/InfoPlist.strings"
    for key in $REQUIRED_INFO_KEYS; do
        plutil -extract "$key" raw -o - "$info_file" >/dev/null \
            || fail "$locale InfoPlist.strings is missing $key."
    done
done

[[ "$(plutil -extract CFBundleDevelopmentRegion raw -o - "$RESOURCE_DIR/Info.plist")" == "ja" ]] \
    || fail "CFBundleDevelopmentRegion must be ja."
plutil -extract CFBundleLocalizations json -o - "$RESOURCE_DIR/Info.plist" \
    | jq -e 'sort == ["en", "ja"]' >/dev/null \
    || fail "CFBundleLocalizations must contain exactly ja and en."

typeset -a SOURCE_FILES=("$ROOT_DIR"/BlurFollow/**/*.swift(N))
(( ${#SOURCE_FILES[@]} > 0 )) || fail "No Swift sources found."
mkdir -p "$TEMP_DIR/extracted"
xcrun xcstringstool extract \
    --modern-localizable-strings \
    --SwiftUI \
    --output-format strings \
    --output-directory "$TEMP_DIR/extracted" \
    $SOURCE_FILES

EXTRACTED="$TEMP_DIR/extracted/Localizable.strings"
[[ -f "$EXTRACTED" ]] || fail "Source localization extraction produced no Localizable.strings."
plutil -lint "$EXTRACTED" >/dev/null
plutil -convert json -o - "$EXTRACTED" | jq -r 'keys[] | select(length > 0)' | LC_ALL=C sort \
    > "$TEMP_DIR/source.keys"

if ! diff -u "$TEMP_DIR/source.keys" "$TEMP_DIR/ja-Localizable.keys"; then
    fail "Localizable.strings must exactly match keys extracted from SwiftUI and String(localized:)."
fi

format_signature() {
    print -rn -- "$1" \
        | { LC_ALL=C grep -Eo '%([0-9]+\$)?(lld|ld|d|@|([.][0-9]+)?f|%)' || true } \
        | sed -E 's/%[0-9]+\$/%/' \
        | LC_ALL=C sort \
        | tr '\n' ','
}

for locale in $LOCALES; do
    file="$RESOURCE_DIR/$locale.lproj/Localizable.strings"
    plutil -convert json -o - "$file" | jq -r 'to_entries[] | [.key, .value] | @tsv' \
        | while IFS=$'\t' read -r key value; do
            key_signature=$(format_signature "$key")
            value_signature=$(format_signature "$value")
            [[ "$key_signature" == "$value_signature" ]] \
                || fail "$locale format placeholders differ for key: $key"
        done
done

rg -q '^  developmentLanguage: ja$' "$ROOT_DIR/project.yml" \
    || fail "project.yml developmentLanguage must be ja."
known_regions=$(sed -n '/^  knownRegions:/,/^  [^ -]/p' "$ROOT_DIR/project.yml")
print -r -- "$known_regions" | rg -q '^    - ja$' || fail "project.yml knownRegions is missing ja."
print -r -- "$known_regions" | rg -q '^    - en$' || fail "project.yml knownRegions is missing en."

if [[ -f "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj" ]]; then
    rg -q 'developmentRegion = ja;' "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj" \
        || fail "Generated Xcode project developmentRegion is not ja. Run xcodegen generate."
    project_regions=$(sed -n '/knownRegions = (/,+6p' "$ROOT_DIR/BlurFollow.xcodeproj/project.pbxproj")
    print -r -- "$project_regions" | rg -q '^[[:space:]]+ja,' \
        || fail "Generated Xcode project knownRegions is missing ja."
    print -r -- "$project_regions" | rg -q '^[[:space:]]+en,' \
        || fail "Generated Xcode project knownRegions is missing en."
fi

key_count=$(wc -l < "$TEMP_DIR/source.keys" | tr -d ' ')
print "Localization checks passed ($key_count app keys; ja/en parity)."
