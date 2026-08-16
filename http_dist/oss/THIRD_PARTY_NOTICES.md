# Third-party notices

Last reviewed: 2026-08-17<br>
Applies to: BlurFollow 0.1.1 source and the current macOS application target

## Shipped third-party components

The current audit identified no vendored or bundled third-party runtime
library, SDK, package, executable, model, font, media file, analytics component,
advertising component, or updater.

The app links only to frameworks and Swift runtime libraries supplied by the
user's macOS installation. Those operating-system components are not copied
into this repository or the release bundle. They remain governed by the terms
that apply to macOS, Xcode, and the Apple SDK; they are not relicensed under
BlurFollow's Apache-2.0 license. See [DEPENDENCIES.md](DEPENDENCIES.md) for the
audited framework and tool list.

The current application artifact therefore has no third-party attribution text
to reproduce here. Project Brand Assets are governed separately by
[TRADEMARKS.md](TRADEMARKS.md).

## Non-shipped automation component

The CI workflow invokes
[`actions/checkout`](https://github.com/actions/checkout) at immutable commit
`11bd71901bbe5b1630ceea73d27597364c9af683` (upstream release v4.2.2). It is
top-level MIT-licensed, executes only on the CI runner, and is not copied into
BlurFollow's source or application artifact. Its upstream license and vendored
Node dependency notices remain available at the pinned revision.

## Apple names

Apple, macOS, Mac, App Store, Xcode, Swift, SwiftUI, AppKit, and
ScreenCaptureKit may be trademarks of Apple Inc. Their descriptive use does
not imply sponsorship or endorsement. See [TRADEMARKS.md](TRADEMARKS.md).

## Maintenance rule

This is an inventory result, not a promise that future versions will remain
dependency-free. Every release must:

1. audit package manifests, lockfiles, linked binaries, embedded frameworks,
   resources, fonts, generated assets, CI actions, and build/release tools;
2. reconcile the results with this file, `DEPENDENCIES.md`, `NOTICE`, and the
   release SBOM;
3. include all license texts and attribution notices required by anything
   actually shipped; and
4. stop the release when a component's provenance, license, patent terms,
   privacy behavior, export status, or commercial-use permission is unclear.

This file is informational and is not legal advice. The release owner remains
responsible for obtaining qualified legal review before commercial sale.
