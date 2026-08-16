# BlurFollow App Store submission checklist

Complete every required item against the exact archive submitted to App Store
Connect. Record evidence in the release record; do not mark an item complete
from a source-tree assumption.

## Publisher, rights, and storefront account

- [ ] The accountable seller is a confirmed legal person or entity, with the
  same identity in App Store Connect, contracts, tax, banking, copyright, and
  public contact information.
- [ ] Professional trademark clearance is complete for BlurFollow, the icon,
  the domain, and confusingly similar marks in every launch territory.
- [ ] Ownership or written commercial-use permission is recorded for the icon
  and every brand asset; the final hashes match `Brand/PROVENANCE.md`.
- [ ] Apache-2.0 obligations, `NOTICE`, third-party inventory, patent terms, and
  the separate trademark policy have received qualified release review.
- [ ] Paid or official-branded distribution remains disabled until all rights
  and brand gates are closed.
- [ ] Paid Applications agreement, tax forms, banking, pricing, territories,
  and availability dates are explicitly approved by the seller.

## App record

- [ ] Bundle ID is `com.hinoshiba.blurfollow` and matches the signed archive, App ID,
  provisioning profile, privacy manifest, and App Store Connect record.
- [ ] Primary language is Japanese (`ja-JP`); English (`en-US`) localization is
  enabled.
- [ ] Primary category is Utilities; secondary category is Productivity.
- [ ] Version and build number match the archive. Version `0.1.0` in this folder
  must be updated if a different version is submitted.
- [ ] Age-rating questionnaire is answered from the final behavior and content;
  no rating is assumed from this repository.
- [ ] Encryption/export-compliance answers match the binary and
  `ITSAppUsesNonExemptEncryption` value.
- [ ] The app name is reserved in App Store Connect; reservation is not treated
  as trademark clearance.
- [ ] App Review contact name, email, and phone are real, monitored, and entered
  directly in App Store Connect. No placeholder personal information is used.

## Metadata and public URLs

- [ ] Run `python3 StoreAssets/Scripts/validate_metadata.py` with no errors.
- [ ] Read every localized field in App Store Connect after upload; line breaks,
  punctuation, Japanese glyphs, and URLs match the checked-in text.
- [ ] `https://blurfollow.hinoshiba.com/` and `/en/` resolve over HTTPS without redirects
  to an unrelated host.
- [ ] Privacy, support, and OSS pages resolve for both locales and remain usable
  without an account.
- [ ] `support@hinoshiba.com` is provisioned, receives external mail, and has a
  monitored response workflow before any listing points to the support page.
- [ ] The public privacy page names the accountable publisher and supplies any
  address, representative, rights-request process, or additional contact detail
  required in each launch jurisdiction.
- [ ] `robots.txt` and `sitemap.xml` use the production origin and return the
  intended content type.
- [ ] No customer-facing page says or implies that mask placement, unreadability,
  capture inclusion, confidentiality, or non-disclosure is guaranteed.
- [ ] No listing field contains competitor names, unverifiable rankings,
  incentivized-review language, unavailable features, draft prices, or private
  project planning.

## Privacy and permissions

- [ ] Re-audit the exact archive for networking, embedded SDKs/frameworks,
  analytics, advertising, updater code, frame/audio persistence, and logging.
- [ ] App Privacy answers match that audit. For the current unmodified code, the
  expected answer is no data collected by the developer and no tracking.
- [ ] `PrivacyInfo.xcprivacy` matches the archive and the current Apple required-
  reason API rules.
- [ ] The published policy accurately covers in-memory window-frame processing,
  local mask/window metadata, primary and backup settings, export, deletion,
  meeting-service boundaries, and operating-system memory limitations.
- [ ] Permission copy explains that Display Pin needs no Screen Recording access.
- [ ] Permission copy explains that macOS 14–15.1 needs broader Screen Recording
  access and an app reopen, while macOS 15.2+ uses picker selection.
- [ ] Camera, microphone, Accessibility, Full Disk Access, and unrelated
  entitlements are absent unless behavior and disclosures are deliberately
  updated and reviewed.

## Build and runtime verification

- [ ] Regenerate the Xcode project if required and confirm there is no drift from
  `project.yml`.
- [ ] Push the reviewed semantic-version tag and confirm the `App Store Release`
  Xcode Cloud workflow tests, archives, signs, and uploads the exact commit.
- [ ] Confirm Xcode Cloud's next build number is greater than every previously
  uploaded macOS build number before the first cloud release.
- [ ] Scan the final executable, symbols, archive, and package for local absolute
  paths and usernames. If found, rebuild from a clean path with Swift file/debug
  prefix mapping (or an equivalent toolchain control) before signing.
- [ ] Confirm App Sandbox and only the intended entitlements on the signed app.
- [ ] Confirm both Apple Silicon and Intel support if both are advertised or
  required by the release decision; the development artifact alone is not
  accepted as evidence.
- [ ] Run all automated tests and `Scripts/check-release.sh` from a clean tree.
- [ ] Test first-launch allow, deny, revoke, and post-grant reopen from fresh TCC
  state on macOS 14.0, 14.2, 15.0, 15.1, and at least one macOS 15.2+ release.
- [ ] Test Display Pin, Window Pin, Reconnect, Share Guide, Share Preview, stop,
  close, picker cancellation, app quit, settings recovery, and Delete All.
- [ ] Test multiple displays, displays above/left of the primary display,
  mixed-DPI scaling, Spaces, full screen, sleep/wake, source-window recreation,
  hidden/minimized windows, scrolling, zoom, and child windows.
- [ ] Test full-display, single-window, and browser-tab workflows in the supported
  versions of the conferencing/recording apps named by support material.
- [ ] Confirm the meeting app is given BlurFollow Share Preview, not the original
  source, for single-window capture; inspect its receiver-side preview.
- [ ] Complete accessibility review for keyboard navigation, VoiceOver labels,
  focus order, contrast, text scaling, and reduced motion.
- [ ] Complete a sustained Share Preview performance run and record CPU, GPU,
  energy, memory, frame delay, thermal behavior, and recovery after interruption.

## Screenshots and review package

- [ ] Capture the exact shipping build with fabricated content only.
- [ ] Add all ten files specified by `screenshot_manifest.json` at one accepted
  16:10 Mac size, then run the validator with `--require-screenshots`.
- [ ] Inspect every image at actual storefront size for legibility, clipping,
  personal menu-bar data, notifications, and stale UI terminology.
- [ ] Ensure Japanese and English images have equivalent scenes and accurate
  localized headlines.
- [ ] App Review Notes reproduce from a clean macOS account using only the
  submitted binary and public instructions.
- [ ] Attach a synthetic test fixture and short permission-flow video if needed;
  neither contains private data or access credentials.
- [ ] Explain any review-only setup in Review Notes. Never provide a real user,
  customer, or production account.

## Final release decision

- [ ] Run `python3 StoreAssets/Scripts/validate_metadata.py --require-screenshots`
  immediately before metadata upload.
- [ ] Compare the uploaded metadata, screenshots, privacy answers, agreements,
  binary hash, version, category, territories, and release mode with the signed
  approval record.
- [ ] A named release owner confirms that every unchecked item is either closed
  or blocks submission. Silence, a passing build, or automated validation alone
  is not approval to submit.
