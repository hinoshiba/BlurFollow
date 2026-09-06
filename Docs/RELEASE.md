# Local Xcode App Store release

Official Mac App Store binaries are archived in local Xcode on the maintainer's authorized Mac and uploaded with Organizer. PR CI uses no Apple account or distribution credentials. `./build.sh` produces an ad-hoc development app in `dist/`; it is not a release artifact. Tags identify reviewed source and do not trigger builds or uploads.

## Prepare the source

Start from an updated `main`, make changes on a branch, and commit and push them for review.

Choose a semantic marketing version and update it consistently in:

- `project.yml` and the checked-in `BlurFollow.xcodeproj`;
- `StoreAssets/metadata/common/version.txt` and any version-specific listing
  copy;
- privacy, security, compatibility, architecture, dependency, notice, and
  threat-model documents when behavior or inventory changed;
- the `Text Follow (Beta)` / `文字追従（ベータ）` label across app UI, README,
  privacy, technical documentation, Store metadata, website, and screenshots,
  plus the intended distribution route against current App Review rules;
- the Non-Consumable product state, localized product metadata/price, In-App
  Purchase review screenshot, Sandbox evidence, and purchase/restore/refund
  matrix described in `MONETIZATION.md`; and
- the private release record, metadata, screenshots, and review notes for the
  exact candidate.

If `project.yml` changes, regenerate the checked-in project with the reviewed
XcodeGen version and inspect the complete diff:

```sh
xcodegen generate
git diff --check
git diff -- project.yml BlurFollow.xcodeproj
```

Run the automated gates:

```sh
swift test
./build.sh
./Scripts/check-release.sh
python3 StoreAssets/Scripts/validate_metadata.py --require-screenshots
# Build the Release app without signing.
xcodebuild \
  -project BlurFollow.xcodeproj \
  -scheme BlurFollow \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

# Run tests in Debug, where testability is enabled.
xcodebuild \
  -project BlurFollow.xcodeproj \
  -scheme BlurFollow \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Complete the manual matrix in `Docs/COMPATIBILITY.md` against the candidate:
permission allow/deny/revoke/reopen flows, Display Pin, Window Pin, and Text
Follow (Beta), Reconnect, Share Guide, Share Preview, and stop/error paths. For
Share Preview, verify completed Text Follow matches are composed with Window Pins,
completed zero-match scans select full cover with strict safety enabled and
remain renderable with it disabled without being treated as proof,
every unready/failed/inconsistent relevant rule clears and fully covers the old
frame, and OCR/preview both exclude child windows. Verify live-backdrop Mosaic
and its opaque filter-unavailable fallback, multiple displays/Spaces/full-screen/
mixed DPI, supported sharing products, accessibility, localization, and a
sustained performance run. Use synthetic content and record the exact commit,
app hash, hardware, OS/app versions, results, and exceptions.

The Beta label is not a test waiver: run every safety, privacy, compatibility,
and performance gate, and verify that two Text Follow rules remain free while
the existing Unlimited Masks purchase removes the same three independent
creation limits.

## Archive with local Xcode

1. Open `BlurFollow.xcodeproj`, select the `BlurFollow` scheme and **Any Mac** destination. Verify the official App Store configuration, `arm64` and `x86_64` architectures, version, and a build number greater than every prior upload.
2. Confirm the intended App Store Connect app and team. Use the existing authorized App Store distribution identity in the local Keychain. Never use Developer ID Application for a Mac App Store archive; do not generate or export an identity as a routine build step.
3. Choose **Product > Archive**. Inspect the archive's bundle identifier, entitlements, architectures, version, and license resources, then use **Distribute App > App Store Connect** in Organizer to validate and upload.
4. Store archives, export options, signing assets, and account credentials outside this public checkout. Verify the processed build in App Store Connect and complete the purchase/restore and compatibility matrix before submitting.
5. Keep a private record of source commit, Xcode version, version/build, review evidence, and the selected candidate. A release tag, if used, must point to that reviewed commit and must not be moved or reused.

Confirm current store agreements, pricing, support/privacy URLs, permissions, and accurate App Privacy answers for each release. Preserve LICENSE, NOTICE, third-party notices, and brand attribution in the distributed app.
