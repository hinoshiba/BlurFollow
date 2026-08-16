# Release and commercial-distribution runbook

This runbook covers two separate macOS channels:

1. a Developer ID-signed, notarized DMG distributed directly; and
2. a sandboxed build submitted to the Mac App Store.

Do not reuse one channel's signed artifact for the other. Apple requirements,
contracts, and review rules change; verify the current official requirements at
release time. This document is an engineering control, not legal advice.

## 0. Mandatory ownership and legal gate

The release manager must mark every item complete **before publishing an
official branded artifact, accepting payment or preorders, or submitting a
branded build to a store**:

- [ ] Identify the publishing legal person/entity, Apple Developer team,
      merchant of record, tax owner, support owner, and security contact.
- [ ] Obtain qualified legal review for Apache-2.0 compliance, Apple agreements
      and current store rules, consumer/refund and warranty terms, privacy and
      recording law, export compliance, sanctions, and target countries.
- [ ] Complete name/logo clearance and record ownership or written permission
      for all Brand Assets as required by `TRADEMARKS.md`; reconcile the
      generation record and source digest in
      [Brand/PROVENANCE.md](../Brand/PROVENANCE.md) with the final artwork.
- [ ] Record a professional exact, phonetic, and confusing-similarity clearance
      search for **BlurFollow** in every target territory and relevant class.
      Repository, App Store, web, and domain searches are preliminary collision
      checks only and do not establish trademark availability.
- [ ] Confirm DCO sign-offs and provenance for code, translations, screenshots,
      fonts, marketing claims, and generated artwork.
- [ ] Confirm root-license scope and any file-level SPDX/license headers agree
      with the Apache code/documentation grant and the explicit Brand Asset and
      verbatim-legal-text exclusions; ambiguous or missing file provenance
      blocks publication.
- [ ] Audit the exact source revision and artifact against `DEPENDENCIES.md`;
      resolve every license and notice. Unknown provenance blocks release.
- [ ] Replace all placeholder contacts with the publisher's real legal identity,
      public privacy-policy URL, support URL, and rights-request contact.
- [ ] Verify that store copy and pricing explain what is sold: an official
      signed build/support experience, not exclusive rights to Apache code.
- [ ] Remove claims or visuals that imply confidentiality, certified protection,
      or guaranteed redaction. `Following`, `Position known`, `Preview active`,
      and `Last-position cover` must describe only observed app state, and every
      sharing workflow must tell the user to inspect receiver-side output.
- [ ] Approve a channel-specific App Store privacy disclosure and review notes
      based on the exact binary, not this repository in the abstract.

Record the reviewer, date, scope, and decision in a private release record.
“No external dependency” is not a legal opinion and does not waive this gate.

### Repository controls before the first release

The repository owner explicitly authorized the initial source import to
`git@github.com:hinoshiba/BlurFollow.git` on 2026-08-16. The canonical history
begins with the complete reviewed source snapshot, excluding ignored local
build products, and the import commit carries the importer identity and DCO
`Signed-off-by` trailer. That commit establishes a reviewable source baseline;
it does not close the separate brand, trademark, seller, signing, notarization,
storefront, or commercial-release gates in this document.

- Preserve the initial import and its DCO sign-off as the source provenance
  baseline. A DCO trailer records the importer's certification but does not
  cure missing rights, unidentified AI/media inputs, or an absent assignment.
- Protect the default branch and release environment; block force-push and tag
  deletion, require passing CI and independent review, and restrict who can
  approve or publish a release.
- Require multifactor authentication for maintainers and protect recovery codes,
  signing keys, Apple roles, domains, and merchant accounts separately.
- Enable GitHub private vulnerability reporting and monitor the contact route in
  `SECURITY.md` before directing reporters to it.
- Keep release credentials unavailable to fork/pull-request workflows. Use
  least-privilege, short-lived tokens and pin third-party actions to reviewed
  commit SHAs.
- Review dependency/runner updates; do not auto-merge a toolchain or action into
  a release solely because automation opened the pull request.

## 1. Freeze a release candidate

1. Start from a clean, protected branch and record the full commit SHA.
2. Choose an immutable semantic version and monotonically increasing build
   number. The tag, app metadata, DMG, SBOM, release notes, and store record must
   agree.
3. Record macOS, Xcode, Swift, and SDK versions plus the build runner image.
4. Run CI and the manual matrix in `COMPATIBILITY.md` on both Apple silicon and
   Intel hardware (or record an explicitly approved exception).
5. Re-read `PRIVACY.md`, `SECURITY.md`, `THREAT_MODEL.md`, `DEPENDENCIES.md`,
   `THIRD_PARTY_NOTICES.md`, `NOTICE`, and `TRADEMARKS.md` against the candidate.
6. Scan the repository and build logs for secrets and real captured content.
7. Scan the final executable, symbols, archive, and package for local absolute
   workspace paths and usernames. Build from a clean, reproducible path and use
   Swift file/debug prefix mapping (or an equivalent toolchain control) before
   signing if any local path remains.

Suggested source checks:

```sh
test -z "$(git status --porcelain)"
git rev-parse HEAD
git log --show-signature -1
swift test
swift package show-dependencies --format json
```

Review all commits for `Signed-off-by` trailers. A script can assist, but a
human must resolve merge commits, bots, and contributor identity exceptions.

## 2. Produce the SBOM and provenance record

Every binary release requires an SBOM even when the dependency list is empty.
Use SPDX 2.3 JSON (preferred) or CycloneDX JSON and a version-pinned, reviewed
generator. Record the generator name, version, source, and digest. The SBOM must
identify:

- BlurFollow, its version, source commit, Apache-2.0 license, and artifact digest;
- every source or binary component actually packaged in the app/DMG;
- direct and transitive relationships and concluded licenses;
- reserved Brand Assets as not Apache-licensed; and
- the fact that Apple system frameworks are external operating-system
  requirements rather than bundled packages.

Reconcile the SBOM with a manual bundle inspection and
`THIRD_PARTY_NOTICES.md`. A repository dependency-graph export alone is not
enough because it may omit copied code, resources, generated artifacts, and
embedded binaries.

Name release files unambiguously, for example:

```text
BlurFollow-1.2.3.dmg
BlurFollow-1.2.3.dmg.sha256
BlurFollow-1.2.3.spdx.json
BlurFollow-1.2.3-provenance.json
```

Where supported, generate signed artifact provenance and an SBOM attestation
from the protected release workflow. Pin CI actions to reviewed full commit
SHAs. Preserve an offline copy of the workflow, logs, attestations, notarization
submission ID/log, signing-certificate identity, source SHA, SBOM, and hashes.
An attestation links an artifact to an identity and build record; it does not
prove that the source or artifact is secure, and it provides value only when
consumers verify it against an explicit policy.

## 3. Developer ID direct distribution

### Prerequisites

- an Apple Developer Program team and a valid **Developer ID Application**
  identity;
- hardened runtime enabled with the minimum entitlements;
- a `notarytool` keychain profile created interactively on the trusted release
  Mac; and
- no secret placed in the repository, shell history, CI output, or artifact.

The current entitlements file contains App Sandbox plus user-selected
read/write access for settings export; the direct build intentionally keeps
that sandbox baseline too. Do not add network, automation, Accessibility,
microphone, camera, or broader file-system exceptions merely to make a failing
test pass. Document and review any entitlement change.

### Build, sign, and inspect

```sh
export BLURFOLLOW_VERSION=1.2.3
export BLURFOLLOW_BUILD_NUMBER=123
export BLURFOLLOW_SIGN_IDENTITY='Developer ID Application: Legal Name (TEAMID)'

./build.sh --dist
./Scripts/check-release.sh

codesign --verify --strict --verbose=2 dist/BlurFollow.app
codesign -dvvv --entitlements :- dist/BlurFollow.app
lipo -archs dist/BlurFollow.app/Contents/MacOS/BlurFollow
otool -L dist/BlurFollow.app/Contents/MacOS/BlurFollow
```

Expected architecture output is `arm64 x86_64`. Confirm that `LICENSE`,
`NOTICE`, `THIRD_PARTY_NOTICES.md`, `DEPENDENCIES.md`, `PRIVACY.md`,
`TRADEMARKS.md`, `SECURITY.md`, `Brand/PROVENANCE.md`, and
`Docs/{RELEASE,THREAT_MODEL,COMPATIBILITY}.md` are readable inside
`Contents/Resources` with their relative links intact. Confirm that
`PrivacyInfo.xcprivacy` is present and matches the binary, the purpose string
accurately describes ScreenCaptureKit, the version is correct,
`com.apple.security.get-task-allow` is absent/false, and no unexpected helper or
framework is embedded. Confirm the expected App Sandbox and user-selected-file
entitlements are present and that no network entitlement was introduced.

`codesign --deep` must not be used as a substitute for signing each nested code
object correctly. If nested code is added later, sign inside-out and audit each
designated requirement.

### Package, notarize, staple, and verify

Create the keychain profile once using Apple's `notarytool store-credentials`
workflow, then run:

```sh
export BLURFOLLOW_NOTARY_PROFILE='blurfollow-notary'
./Scripts/make-dmg.sh

xcrun stapler validate "dist/BlurFollow-$BLURFOLLOW_VERSION.dmg"
shasum -a 256 -c "dist/BlurFollow-$BLURFOLLOW_VERSION.dmg.sha256"
./Scripts/check-release.sh --distribution
```

Archive the notarization submission ID and retrieve its full log. A successful
notarization is necessary release evidence; it is not an Apple endorsement,
privacy audit, or proof that the app is vulnerability-free.

Mount the final DMG read-only and test the exact copied app from a clean standard
user account with Gatekeeper enabled. Test first launch, picker cancel/deny/end,
any OS-specific Screen Recording setting and relaunch behavior, masks, Share
Preview start/stop, and uninstall documentation. Do not tell users to bypass
Gatekeeper.

## 4. Mac App Store distribution

The direct-distribution script does not create an App Store artifact. Use an
Xcode Archive and the Organizer/App Store Connect workflow with signing managed
for the publisher's team.

### Required App Store variant

- Enable App Sandbox (`com.apple.security.app-sandbox = true`). Apple requires
  it for Mac App Store distribution.
- Add only entitlements demonstrated to be necessary. The current export
  feature needs user-selected read/write access
  (`com.apple.security.files.user-selected.read-write = true`) in a sandboxed
  build. No network entitlement is needed by the current app.
- Retain a clear `NSScreenCaptureUsageDescription`; test system-picker session
  authorization and any OS-specific Screen Recording/TCC behavior in the
  archived sandboxed build.
- Verify Application Support storage moves to the sandbox container and define
  migration/channel-switch behavior. Never silently read another channel's
  data or weaken sandboxing to share it.
- Confirm hardened runtime, bundle identifier, App ID, provisioning profile,
  version/build, category, copyright, icon, localized metadata, and export
  compliance on the archive.
- Validate the archive's privacy manifest and scan required-reason API use;
  an empty declaration is valid only while the exact code and embedded SDKs
  support it.
- Validate the archive and upload through the current Xcode/App Store Connect
  path. Apple performs the store signing/distribution flow; do not notarize or
  Developer ID-sign the uploaded archive as though it were the direct build.

The checked-in minimal sandbox entitlement set is **not itself proof of App
Store readiness**. Release cannot proceed until the separate sandboxed archive
passes runtime tests and Xcode/App Store validation.

### Privacy and review preparation

For the current local-only implementation, screen pixels processed only on the
device are not “collected” under Apple's App Privacy definition. Re-audit the
submitted binary and all SDKs at submission time. Update App Store Connect
answers before adding any telemetry, crash reporter, licensing server, payment
SDK, updater, support upload, or other transmission.

Review Notes should give App Review a short, reproducible path:

1. explain Display Pin versus Window Pin and why a separate overlay may be
   omitted from an app/window or browser-tab share;
2. open Share Guide, choose a synthetic source using Apple's picker, and open
   Share Preview;
3. point out the factual `Preview active`/stopped indicator, no-audio behavior,
   local processing, and how to end system-authorized sharing;
4. instruct the reviewer to inspect the BlurFollow preview, share the
   **BlurFollow Share Preview window** rather than the original source, and
   inspect receiver-side output; and
5. provide a support contact and any needed demo configuration without real
   personal data.

Confirm compliance with the current recording-consent/indication rule, current
privacy-policy rule, and accurate-metadata rule. Paid functionality must use the
payment mechanism allowed for the chosen storefront model under current rules.

## 5. Publish an immutable release

Create and sign the annotated tag only after the release commit is approved:

```sh
git tag -s "v$BLURFOLLOW_VERSION" -m "BlurFollow $BLURFOLLOW_VERSION"
git tag -v "v$BLURFOLLOW_VERSION"
git push origin "v$BLURFOLLOW_VERSION"
```

Enable the hosting platform's immutable-release protection before the first
public release. On GitHub, prepare a **draft**, attach the DMG, checksum, SBOM,
provenance/attestation information, license notices, and final release notes,
then publish once. GitHub immutable releases lock the tag and assets after
publication and generate a release attestation.

After publication:

- never replace, delete, or silently rebuild an asset under the same version;
- do not move or reuse the tag;
- correct a defect with a new version and document the superseded release;
- publish a security advisory/revocation notice when appropriate; and
- verify the public asset against the locally archived digest and attestation.

When using GitHub's immutable-release verification:

```sh
gh release verify "v$BLURFOLLOW_VERSION"
gh release verify-asset "v$BLURFOLLOW_VERSION" \
  "dist/BlurFollow-$BLURFOLLOW_VERSION.dmg"
```

Source archives generated on demand by the hosting platform are distinct from
uploaded, attested release assets; document which artifact users should verify.

## 6. Final two-person release checklist

One release manager performs the build; a second authorized reviewer verifies
the evidence and public draft.

- [ ] Legal/ownership gate in section 0 is signed off.
- [ ] Clean source SHA, signed tag, toolchain, tests, manual matrix, and DCO
      evidence are archived.
- [ ] Exact binary behavior matches product, privacy, compatibility, and store
      claims; no placeholder remains.
- [ ] Permissions and entitlements are minimal and correct for this channel.
- [ ] Apache license, NOTICE, third-party notices, trademark separation, and
      source link are present and readable.
- [ ] SBOM matches the bundle; checksum and provenance bind to exact assets.
- [ ] Developer ID artifact passes signature, hardened-runtime, notarization,
      staple, Gatekeeper, and clean-machine tests; **or** the App Store archive
      passes sandbox, validation, upload, and TestFlight/reviewer tests.
- [ ] Privacy/support URLs and seller identity are public and monitored.
- [ ] Release is published once with immutability enabled and verified from the
      public channel.

Stop on any mismatch. Schedule pressure is never an exception to the license,
privacy, signing, user-facing claim, or receiver-verification gate.

## Primary operational references

- [Apple: Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Preparing an app for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Apple: Configuring the macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)
- [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple: App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [GitHub: Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
- [GitHub: Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)

External documentation is not immutable. The release record must capture the
rules and agreements actually reviewed for that version and publisher.
