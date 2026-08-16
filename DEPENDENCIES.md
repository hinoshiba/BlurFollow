# Dependency and license policy

Last audited: 2026-08-16<br>
Baseline: BlurFollow 0.1.0, macOS deployment target 14.0

This document records what the current app uses and the gate for accepting new
dependencies. It is designed to keep an open-source build and paid official
distribution compatible. It is not legal advice.

## Current inventory

`Package.swift` declares no package dependency and there is no checked-in
`Package.resolved`. The application target has no vendored framework or SDK.

| Category | Components | Shipped inside `BlurFollow.app`? | Notes |
| --- | --- | --- | --- |
| Direct Apple application frameworks | AppKit, SwiftUI, Foundation, Combine | No | Resolved from macOS at runtime. |
| Apple graphics and media frameworks | CoreGraphics, CoreImage, CoreMedia, CoreVideo | No | Share Preview processes video frames in memory; audio capture is disabled. |
| Apple capture framework | ScreenCaptureKit | No | Used with Apple's system content picker and Screen Recording consent. |
| Apple system UI assets | SF Symbols referenced by `systemName` | No | Rendered by the OS in the app UI. Apple's applicable SDK/SF Symbols terms govern use; do not repurpose a restricted symbol as product branding or export it as an independently distributed asset. |
| Swift runtime and system libraries | Swift runtime libraries, `libSystem`, `libobjc` | No in the audited build | Resolved from `/usr/lib` and `/usr/lib/swift` on macOS. Recheck every archive. |
| Test-only framework | XCTest | No | Used only by `BlurFollowTests`. |
| Project assets | BlurFollow source and localized resources | Yes | Code is Apache-2.0. Reserved brand assets are identified in [TRADEMARKS.md](TRADEMARKS.md), with the current generation record in [Brand/PROVENANCE.md](Brand/PROVENANCE.md). |

The Apple SDK and toolchain are inputs to the build, not Apache-licensed
project dependencies. A maintainer must use them under the applicable Apple
agreements and must not copy Apple SDK frameworks into a release.

The linker may also record transitive references to additional OS frameworks
(for example ColorSync, Uniform Type Identifiers, AVFoundation, or QuartzCore)
through SwiftUI/AppKit on a particular SDK. They are still supplied by macOS,
but the exact release binary must be captured in the `otool` audit rather than
assumed from the direct Swift imports above.

## Build, CI, and release tooling

The scripts invoke Apple- or OS-supplied tools including `swift`, `xcodebuild`
when using the Xcode project, `codesign`, `iconutil`, `PlistBuddy`, `plutil`,
and `otool`.
`rg` (ripgrep) is used by `Scripts/check-release.sh` as a maintainer-side check.
XcodeGen 2.45.4 regenerates and verifies the checked-in project from
`project.yml` in GitHub CI and may also be used during development. These tools
are not bundled with the app. Their own licenses still apply to the person or
service running them.

| Tool/input | Audited revision or local version | License/terms | Artifact status |
| --- | --- | --- | --- |
| `actions/checkout` | `11bd71901bbe5b1630ceea73d27597364c9af683` (v4.2.2) | Top-level MIT; upstream vendored npm notices also apply | Pinned CI action; not bundled. |
| ripgrep | 15.2.0 with verified architecture-specific SHA-256 downloads in GitHub CI | MIT OR Unlicense upstream | Pinned CI check tool; not bundled. |
| XcodeGen | 2.45.4 with a verified SHA-256 download in GitHub CI | MIT upstream | Pinned CI drift generator and development tool; not bundled. |
| Apple Swift/Xcode | Swift 6.3.3 / Xcode 26.6 in the local audit | Applicable Apple/toolchain terms | Compiler/SDK input; not copied as an SDK into the app. |

Local tool versions above document the audit machine, while GitHub CI downloads
the recorded ripgrep and XcodeGen versions only after verifying their digests.
A release workflow must pin downloadable actions/tools where possible, record
the runner image and digests, and treat the build environment as part of
supply-chain provenance.

## Repeatable audit

Run these checks from a clean release checkout. Investigate every result;
absence from one command is not proof of absence from the artifact.

```sh
swift package show-dependencies --format json
find . -name Package.resolved -not -path './.build/*'

APP=dist/BlurFollow.app
otool -L "$APP/Contents/MacOS/BlurFollow"
find "$APP" -type d -name '*.framework' -print
find "$APP" -type f \( -name '*.dylib' -o -perm -111 \) -print
codesign -d --entitlements :- "$APP"
```

Also review imports, copied source, resources, fonts, icon provenance, build
plugins, generated code, network endpoints, and the complete archive contents.
`Scripts/check-release.sh` rejects a non-system linked dynamic library, but it
does not replace this broader audit.

## Admission gate for a new dependency

A dependency may be merged only after a reviewer records all of the following
in the pull request:

- canonical upstream URL, exact version or immutable commit, and integrity
  hash or lockfile;
- direct and transitive component list, license expression, copyright and
  notice requirements, patent clauses, and source-availability obligations;
- explicit permission for commercial use, modification, and the intended
  distribution channels;
- whether copyleft, network-copyleft, source-available, non-commercial,
  field-of-use, export, media, model, font, or data terms apply;
- runtime network traffic, telemetry, advertising, account, data collection,
  retention, and deletion behavior;
- required Apple privacy manifest, required-reason APIs, SDK signature,
  entitlements, and current App Review compatibility;
- supported macOS and CPU architectures, update policy, vulnerability history,
  and a named owner for security updates; and
- exact changes to the SBOM, `THIRD_PARTY_NOTICES.md`, shipped license bundle,
  privacy disclosures, and threat model.

Unknown or custom terms are a release blocker. Strong-copyleft or
source-available code is not automatically forbidden, but must receive written
legal approval for the concrete linking and distribution design. Never rely on
a package registry label alone; read the authoritative license at the pinned
revision.

## Commercial distribution conclusion for this baseline

Apache License 2.0 permits use, modification, redistribution, sublicensing,
and sale, subject to its conditions, including providing the license,
preserving applicable notices, marking modified files, and respecting its
patent-termination and trademark provisions. The present absence of a bundled
third-party runtime removes an additional license layer; it does not waive
Apple's contracts, App Store rules, privacy law, consumer law, export review,
or trademark clearance.

An official publisher may charge for convenience, support, or an official
signed build while keeping the source under Apache-2.0. A downstream seller
may also sell a compliant fork, but must replace the reserved BlurFollow brand
assets unless separately authorized. See [TRADEMARKS.md](TRADEMARKS.md) and
[Docs/RELEASE.md](Docs/RELEASE.md).

The legal entity responsible for a paid release must complete the legal review
gate in `Docs/RELEASE.md` before accepting payment or submitting to Apple.

## Primary references

- [Apache License 2.0 official text](https://www.apache.org/licenses/LICENSE-2.0.txt)
- [Apple: Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- [Apple: App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)
- [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)
- [Apple: SF Symbols](https://developer.apple.com/sf-symbols/)

References help reviewers locate current authoritative material; they do not
freeze external rules or replace reading the agreements that bind the actual
publisher.
