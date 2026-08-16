# Contributing to BlurFollow

Thank you for helping make blur placement easier to follow and verify before
screen sharing. Contributions of code, tests, documentation, accessibility
improvements, translations, design review,
and reproducible bug reports are welcome.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Before opening a change

- Search existing issues and pull requests. For a large feature, security
  boundary change, new entitlement, network feature, persistence change, or
  dependency, open a design issue first.
- Do not attach screenshots, window titles, exported settings, or logs that
  contain someone else's private information. Create a minimal synthetic
  reproduction instead.
- Confirm that every submitted file is your work or that you have documented
  permission to contribute it under Apache-2.0. Do not copy code, prose,
  icons, screenshots, fonts, datasets, or generated output with unclear terms.
- Keep the code path local-first. A change that transmits screen content or
  window metadata, records frames, captures audio, adds analytics, or adds ads
  requires explicit maintainer approval plus updates to the privacy policy and
  threat model before it can be considered.

## Build and test

Requirements are macOS 14 or later and a current Swift/Xcode toolchain that
supports Swift 5.10.

```sh
swift test
./build.sh
open dist/BlurFollow.app
```

For the Xcode project:

```sh
xcodebuild \
  -project BlurFollow.xcodeproj \
  -scheme BlurFollow \
  -configuration Debug \
  build test
```

System-picker authorization, any OS-specific Screen Recording setting, and
window behavior cannot be completely covered by unit tests. For changes in
capture, overlays, or tracking, manually exercise the relevant matrix in
[Docs/COMPATIBILITY.md](Docs/COMPATIBILITY.md), including cancel/deny/end paths
and Last-position cover behavior. Technical tests may call the underlying
reject/block rule “fail closed,” but user-facing copy must use the factual
state names in this document.

## Change guidelines

1. Keep a pull request focused and explain the user-visible outcome.
2. Add or update tests for behavior that can be tested deterministically.
3. Preserve accessibility labels, keyboard operation, localization, reduced
   motion behavior, and readable contrast.
4. Do not use private Apple APIs or infer approval from behavior on one macOS
   version.
5. Treat blur and mosaic as presentation effects, not guaranteed redaction.
   Opaque Redact must remain available when the user's goal is to visually
   replace configured pixels, but even Redact does not guarantee capture
   inclusion or correct
   placement. Use `Following`, `Position known`, `Preview active`, and
   `Last-position cover` only for the observable conditions they describe.
   Never label output “protected” or “safe”; instruct the user to inspect the
   receiver-side meeting/recording preview before sharing.
6. Update architecture, compatibility, privacy, dependency, threat-model, and
   release documents when their statements would otherwise become stale.
7. Do not commit signing identities, notarization credentials, App Store API
   keys, provisioning profiles, private crash data, or real captured content.

## Developer Certificate of Origin

BlurFollow uses the [Developer Certificate of Origin
1.1](https://developercertificate.org/) rather than a copyright assignment.
The exact verbatim certificate is in [DCO](DCO). Sign off every commit:

```sh
git commit -s
```

This appends a line of the form:

```text
Signed-off-by: Your Name <you@example.com>
```

Use a name and email address that identify the contributor and that you are
authorized to use. The sign-off certifies provenance; it is not a claim that
the project reviewed your employer agreement. If contributing for a company,
you are responsible for having the necessary authority. Maintainers should not
merge unsigned commits; a contributor may add a missing sign-off by amending
or rebasing their own commits.

Unless explicitly marked `Not a Contribution`, material intentionally
submitted for inclusion is handled under Apache License 2.0 section 5. No
additional terms may be attached to a pull request without prior written
agreement from the maintainers.

## Pull request checklist

- [ ] Every commit has a valid DCO sign-off.
- [ ] I documented provenance and licensing for all non-original material.
- [ ] Tests pass and I included relevant manual verification.
- [ ] The change uses only public Apple APIs.
- [ ] Privacy, permissions, persistence, networking, and failure behavior were
      reviewed.
- [ ] Dependency/notice/SBOM documents are updated or the change adds no
      dependency.
- [ ] User-facing strings are localized or deliberately tracked for follow-up.
- [ ] No secret, personal data, or real captured frame is present in the diff.

## Review and release

Approval is not guaranteed. Maintainers may request a smaller change, threat
analysis, design revision, or independent legal/security review. Only release
managers may sign, notarize, submit, publish, or claim an artifact is official.
Contributors must not use the BlurFollow marks to imply endorsement; see
[TRADEMARKS.md](TRADEMARKS.md).
