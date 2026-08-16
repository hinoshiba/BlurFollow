# App Store release and commercial-distribution runbook

BlurFollow is distributed through the Mac App Store. Official binaries are
built and uploaded by Xcode Cloud from immutable semantic-version tags. There
is no local signing, notarization, DMG, archive, or upload procedure.

`./build.sh` remains available only for local development. Its ad-hoc-signed
`dist/BlurFollow.app` must never be published.

## 1. Ownership and legal gate

Before submitting or selling an official branded build, the release owner must
record approval for all of the following:

- the publishing legal person/entity, Apple Developer team, merchant of record,
  tax/banking owner, support owner, and security contact;
- Apache-2.0 compliance, Apple agreements and current store rules, consumer and
  refund terms, privacy/recording law, export compliance, sanctions, and target
  territories;
- name/logo clearance and ownership or written commercial-use permission for
  every brand asset, reconciled with `Brand/PROVENANCE.md`;
- DCO sign-offs and provenance for code, translations, screenshots, fonts,
  marketing claims, and generated artwork;
- the exact dependency, license, NOTICE, privacy, security, and threat-model
  inventory for the tagged source and binary;
- public privacy/support URLs and accurate App Store metadata, privacy answers,
  export compliance, pricing, and review notes; and
- claims that describe observable app behavior without promising
  confidentiality, certified protection, or guaranteed redaction.

Record reviewer, date, scope, evidence, and every approved exception in a
private release record. An unresolved ownership, privacy, signing, or legal item
blocks submission.

Protect `main` and release tags, require passing CI and review, enable
multifactor authentication, keep release access away from fork workflows, and
restrict who may administer Xcode Cloud or submit an App Store version.

Create an **Active** tag ruleset in GitHub **Settings > Rules > Rulesets** for
the `v*` target pattern. Enable **Restrict creations**, **Restrict updates**,
and **Restrict deletions**, and allow bypass only for the designated release
manager. Create a release tag only on a reviewed `main` commit. Never move,
replace, or reuse it; a permitted tag creation authorizes Xcode Cloud to build
and upload a signed candidate.

## 2. Xcode Cloud workflow

Complete the app's initial Xcode Cloud setup from Xcode. Edit the suggested
workflow to use a non-Archive **Build** action and run it once from `main`;
the release guard intentionally rejects an Archive without a release tag.
After that setup build, edit the workflow in Xcode or App Store Connect:

- **Name:** `App Store Release`
- **General:** enable **Restrict Editing** and limit workflow administrators to
  the designated release managers
- **Product:** BlurFollow (`com.hinoshiba.blurfollow`), Team `94HVVWXLK3`
- **Repository:** `hinoshiba/BlurFollow`
- **Start condition:** Tag Changes; include `v*`
  and add no branch, pull-request, or schedule start condition; in this tag
  condition's **Options**, set **Auto-cancel Builds** to **Off** so a later tag
  cannot cancel an in-progress release archive
- **Environment:** the latest released macOS and Xcode; enable **Clean**
- **Action 1:** Test, macOS, scheme `BlurFollow`, **Required to Pass**
- **Action 2:** Archive, macOS, scheme `BlurFollow`
- **Deployment Preparation:** `TestFlight and App Store`
- **Post-actions:** none by default. Add TestFlight distribution only after an
  intended tester group exists and the release owner approves automatic
  distribution to that exact group.

Keep automatic signing enabled. Xcode Cloud manages distribution signing for
Team `94HVVWXLK3`; do not store certificates, profiles, App Store Connect keys,
or Apple Account credentials in this repository or in non-secret variables.

After the non-Archive setup build succeeds, remove the generated branch/PR
start conditions from this release workflow and retain only the tag condition
above.

Xcode Cloud assigns the build number used by App Store Connect. Because this is
a macOS app, the build number must increase across all marketing versions. For
an existing app, open **App Store Connect > BlurFollow > Xcode Cloud > Settings
> Build Number** and set **Next Build Number** to an integer greater than the
largest build already uploaded for BlurFollow before the first tagged build.

## 3. Prepare a release pull request

Choose a semantic marketing version and update it consistently in:

- `project.yml` and the checked-in `BlurFollow.xcodeproj`;
- `StoreAssets/metadata/common/version.txt` and any version-specific listing
  copy;
- privacy, security, compatibility, architecture, dependency, notice, and
  threat-model documents when behavior or inventory changed; and
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
xcodebuild \
  -project BlurFollow.xcodeproj \
  -scheme BlurFollow \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build test
```

Complete the manual matrix in `Docs/COMPATIBILITY.md` against the candidate:
permission allow/deny/revoke/reopen flows, Display Pin and Window Pin,
Reconnect, Share Guide, Share Preview and stop/error paths, multiple
displays/Spaces/full-screen/mixed DPI, supported sharing products,
accessibility, localization, and a sustained performance run. Use synthetic
content and record the exact commit, app hash, hardware, OS/app versions,
results, and exceptions.

## 4. Start the cloud build

Only tag the reviewed commit after GitHub CI and manual acceptance pass. The tag
must be exactly `v<major>.<minor>.<patch>` and its version must equal
`MARKETING_VERSION`:

```sh
git tag -s v0.1.0 -m "BlurFollow 0.1.0"
git push origin v0.1.0
```

`ci_scripts/ci_pre_xcodebuild.sh` rejects an Archive without Xcode Cloud, a
release tag, or a positive Cloud build number, as well as malformed tags,
tag/version mismatches,
or a cloud action configured with the wrong platform, scheme, bundle ID, or
team. It applies the Cloud build number to the temporary Xcode project. A
passing workflow tests and archives the Release configuration and makes the
build available in App Store Connect for TestFlight/App Store use.

Never move or reuse a release tag. Correct a failed candidate with a new build
and, when source or marketing version changes, a new tag.

## 5. Verify the cloud artifact

In the completed Xcode Cloud build and App Store Connect, verify:

- source tag and commit, Xcode/macOS versions, version/build, and action logs;
- bundle ID `com.hinoshiba.blurfollow`, Team `94HVVWXLK3`, App Sandbox,
  Hardened Runtime, user-selected-file entitlement, and absence of unrelated
  entitlements;
- both advertised architectures, privacy manifest, localized resources, icon,
  license/NOTICE/provenance files, and no unexpected embedded executable,
  framework, non-system library, updater, analytics, audio, recording, or
  network path;
- metadata, screenshots, privacy answers, export compliance, category, age
  rating, pricing, territories, support URLs, review notes, and release mode
  against the exact build; and
- first-launch and permission behavior from a clean account using the
  TestFlight/App Store-signed candidate, including receiver-side preview.

Xcode Cloud artifacts are retained for a limited period. Preserve the archive,
logs, test results, App Store Connect build record, source commit, SBOM, and
approval evidence in the private release record.

## 6. App Store Connect handoff

Wait for build processing to finish before selecting it. Choose the exact
version/build, save, and confirm it remains selected. Resolve every required
metadata or compliance item named by App Store Connect.

Tagging authorizes the Xcode Cloud build and upload only. Distributing to
testers, selecting the build for an App Store version, adding it for review,
submitting for review, and releasing it are separate App Store Connect actions.
Do not perform any of them without the release owner's explicit approval.

After release, monitor support and security channels. Do not replace a published
binary or retarget a tag; ship a new version and retain the prior release
evidence.

## Primary operational references

- [Apple: Setting up a project to use Xcode Cloud](https://developer.apple.com/documentation/xcode/setting-up-your-project-to-use-xcode-cloud)
- [Apple: Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)
- [Apple: Configuring workflow actions](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)
- [Apple: Setting the next Xcode Cloud build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds/)
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

External requirements change. The release record must capture the rules,
agreements, and App Store Connect state reviewed for the submitted version.
