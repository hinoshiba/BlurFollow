# Security policy

BlurFollow sits in a sensitive screen-sharing path. A misplaced mask or
misleading status can disclose information, so please report suspected vulnerabilities
privately and avoid testing against data or systems you do not own.

## Supported versions

Before 1.0, only the latest tagged release receives security fixes. The default
branch may contain an unreleased fix but is not a supported binary. After 1.0,
the project will publish an explicit support window here before ending support
for a release line.

Unsigned, locally modified, downstream, or unofficially branded builds are the
responsibility of their distributor, although reports that also affect the
upstream source are welcome.

## Private reporting

Use **Security → Report a vulnerability** in the canonical GitHub repository.
That opens a private vulnerability report. If private reporting is unavailable,
contact the repository owner through the private contact method on their GitHub
profile and request a secure reporting channel. Do not put exploit details,
captured pixels, real window titles, signing data, or personal information in a
public issue.

Include, when possible:

- affected version, macOS version/build, Mac architecture, and distribution
  channel;
- whether the app was sandboxed and the exact relevant entitlements;
- sharing mode (display, app/window, browser tab, or BlurFollow Share Preview);
- minimal steps using synthetic content and the expected versus actual result;
- displayed state (`Following`, `Position known`, `Preview active`, or
  `Last-position cover`), display arrangement, Spaces/full-screen state, and
  source app;
- impact, reproducibility, and any suggested mitigation; and
- logs or diagnostics only after removing private content and secrets.

Never send an actual sensitive screen capture unless a maintainer explicitly
requests it through an agreed secure channel and you have authority from every
affected person.

## Response targets

The project aims to acknowledge a complete report within 3 business days and
provide an initial triage within 7 business days. Remediation and disclosure
timing depend on severity, platform behavior, and release review. These are
targets, not a service-level agreement or a promise of payment.

The reporter and maintainers should coordinate publication. The project will
credit reporters who want credit, issue a new immutable release rather than
replace an existing asset, and publish a security advisory when disclosure is
safe. A release may be delayed to protect users or coordinate with Apple or an
affected vendor.

## High-value report areas

- a mask follows the wrong window, silently stops following, or reports
  `Following`/`Position known` while its displayed position is stale;
- Share Preview reports `Preview active` while a configured mask is absent,
  while raw source pixels are visible, or while the displayed frame belongs to
  an obsolete source/mask revision;
- frames or sensitive window metadata are unexpectedly written, logged, sent
  over a network, or retained after capture stops;
- ScreenCaptureKit begins without the intended user selection or permission;
- an input causes memory corruption, code execution, privilege escalation, or
  sandbox escape; or
- a release artifact, update path, App Store record, SBOM, tag, Xcode Cloud
  configuration, or build credential can be substituted or compromised.

Pure feature requests, known blur/mosaic reversibility, and limitations already
documented in [Docs/THREAT_MODEL.md](Docs/THREAT_MODEL.md) or
[Docs/COMPATIBILITY.md](Docs/COMPATIBILITY.md) can use a public issue if they
contain no sensitive detail. Vulnerabilities in macOS or a conferencing product
should also be reported to its vendor; BlurFollow cannot authorize testing of
third-party systems.

The state labels above report conditions observed by BlurFollow; they are not
certifications of confidentiality. A capture product can omit a desktop
overlay, blur/mosaic can remain interpretable, and the user can select the
wrong sharing target. Reports about misleading state or broken frame rejection
remain security reports because the mismatch can contribute to disclosure,
not because BlurFollow promises that masking prevents disclosure.

## Research expectations

Act in good faith, use your own accounts and synthetic content, minimize access,
stop after demonstrating impact, retain no unnecessary data, avoid denial of
service and social engineering, and give maintainers a reasonable opportunity
to address the issue. This policy does not grant permission on behalf of Apple,
another vendor, another user, or a downstream distributor, and it is not legal
advice or a bug-bounty commitment.

See [Docs/THREAT_MODEL.md](Docs/THREAT_MODEL.md) for security assumptions and
[Docs/RELEASE.md](Docs/RELEASE.md) for release-integrity controls.
