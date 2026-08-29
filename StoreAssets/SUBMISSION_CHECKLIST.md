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
- [ ] `com.hinoshiba.blurfollow.unlimited_masks` exists as a Non-Consumable,
  its localized name/description and price are approved, and Family Sharing
  remains off unless separately approved with its irreversible consequence.
- [ ] The explicit App ID, Xcode target capability, signed App Store archive,
  and final provisioning profile all include In-App Purchase support. Do not
  substitute the Apple Pay entitlement or a Developer ID profile.

## App record

- [ ] Bundle ID is `com.hinoshiba.blurfollow` and matches the signed archive, App ID,
  provisioning profile, privacy manifest, and App Store Connect record.
- [ ] Primary language is Japanese (`ja-JP`); English (`en-US`) localization is
  enabled.
- [ ] Primary category is Utilities; secondary category is Productivity.
- [ ] Version and build number match the archive. Version `0.2.0` in this folder
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
- [ ] Every localized metadata field and screenshot that names the OCR feature
  uses `Text Follow (Beta)` in English and `Text Follow（ベータ）` in Japanese.
  The Beta label is attached only to that feature, never to BlurFollow as a
  whole or to the submitted distribution.
- [ ] Description and screenshots clearly disclose the three independent free
  creation allowances: 10 Display Pins, 5 Window Pins, and 2 Text Follow rules.
  They also state that one rule remains one plan item when it matches several
  simultaneous text blocks, and that the one-time In-App Purchase removes all
  three limits.
- [ ] The localized What's New fields describe Text Follow, the independent free
  allowances, optional one-time unlock, 0.1.1 grandfather treatment, restore
  path, and neutral rating behavior without a hardcoded price or ranking claim.
- [ ] App Store copy distinguishes Text Follow from Window Pin and accurately
  states exact/prefix/contains/regular-expression matching, case-sensitive
  Contains behavior, whole-Vision-block masking, every matching OCR block,
  on-device Vision processing, OCR limitations, and capture-path limitations.
  It also describes Share Preview's independent use of completed dynamic
  geometry, its fail-closed states, strict-safety zero-match behavior, the lower
  leak resistance when strict safety is disabled, and the shared child-window
  exclusion boundary.

## Privacy and permissions

- [ ] Re-audit the exact archive for networking, embedded SDKs/frameworks,
  analytics, advertising, updater code, frame/audio persistence, and logging.
- [ ] Confirm StoreKit is the only commerce path; it receives no screen frame,
  window metadata, mask content, or usage analytics from BlurFollow.
- [ ] App Privacy answers match that audit. For the current unmodified code, the
  expected answer is no data collected by the developer and no tracking.
- [ ] `PrivacyInfo.xcprivacy` matches the archive and the current Apple required-
  reason API rules, including `NSPrivacyAccessedAPICategoryUserDefaults` reason
  `CA92.1` for app-only review-prompt preferences.
- [ ] The published policy accurately covers in-memory window-frame and Vision
  processing, non-persistence of frames and recognized candidate strings, local
  mask/rule/window metadata (including saved patterns), primary and backup
  settings, export, deletion, meeting-service boundaries, and operating-system
  memory limitations.
- [ ] Permission copy explains that Display Pin needs no Screen Recording access.
- [ ] Permission copy explains that macOS 14–15.1 needs broader Screen Recording
  access and an app reopen, while macOS 15.2+ uses picker selection for Window
  Pin, Text Follow, and Share Preview.
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
- [ ] Test Display Pin, Window Pin, Text Follow, Reconnect, Share Guide, Share
  Preview, stop, close, picker cancellation, app quit, settings recovery,
  export/import, and Delete All Masks and Rules.
- [ ] Independently test 10 free Display Pins and the 11th request, 5 free Window
  Pins and the 6th request, and 2 free Text Follow rules and the 3rd request.
  Confirm each gate appears before its selector/picker and another category's
  count does not consume or extend the category under test.
- [ ] For plan counting, confirm disabled items still count, while one Text Follow
  rule matching zero, one, or several blocks always counts as exactly one rule.
- [ ] Test purchase success/cancel/failure/pending, relaunch, explicit restore
  with and without entitlement, product-load failure, offline behavior, refund,
  revocation, and the 0.1.1 grandfather path.
- [ ] Confirm purchase or entitlement loss never deletes, disables, hides, or
  changes an existing mask or Text Follow rule, including configurations already
  above any category limit.
- [ ] Confirm the rating request is independent of purchase and appears only
  through Apple's system UI after the documented engagement/cooldown policy.
- [ ] Test multiple displays, displays above/left of the primary display,
  mixed-DPI scaling, Spaces, full screen, sleep/wake, source-window recreation,
  hidden/minimized windows, scrolling, zoom, and child windows.
- [ ] Test Text Follow exact, prefix, contains, and regular-expression rules with Japanese
  and English text, repeated matches, multiple matches in one recognized line,
  navigation, scrolling, resizing, rapid content changes, invalid expressions,
  OCR misses/false matches/delay, disable/delete, stop/error, and relaunch.
- [ ] Confirm Contains is case-sensitive and masks the entire Vision-recognized
  block rather than only the matching substring. Multiple matching blocks must
  still consume exactly one saved-rule slot.
- [ ] Confirm all matching current-generation blocks receive Mosaic panels,
  superseded or blank results clear every panel, and frames and recognized
  candidate strings never enter settings, backup, export, logs, or network I/O.
- [ ] With Share Preview on the same source, confirm every connected, enabled
  Text Follow rule's completed matches are composed with matching Window Pins.
  Confirm a completed zero-match scan selects a full cover with strict safety on,
  remains renderable with strict safety off, and is never described as proof that
  OCR found everything.
- [ ] For every relevant dynamic rule, inject reconnect-required/unconnected,
  connecting, scanning, source-unavailable, failed, missing-runtime,
  stale-identity, and inconsistent state/rectangle pairs. Each must immediately
  clear the prior image, invalidate confirmation, and select a full opaque cover;
  no older revision may restore the frame.
- [ ] Confirm Text Follow OCR and Share Preview both exclude child windows and
  use the same selected-source content boundary. Check separate menus, sheets,
  popovers, notifications, and child windows receiver-side.
- [ ] Confirm desktop Mosaic transforms the actual backdrop with `CIPixellate`.
  Simulate filter unavailability and verify an opaque fallback, never a readable
  source under a translucent decorative grid.
- [ ] Test full-display, single-window, and browser-tab workflows in the supported
  versions of the conferencing/recording apps named by support material.
- [ ] Confirm the meeting app is given BlurFollow Share Preview, not the original
  source, for single-window capture; inspect its receiver-side preview.
- [ ] Confirm Text Follow desktop panels appear in verified full-display output
  and remain absent from direct single-window/tab capture. Then confirm Share
  Preview independently draws completed Text Follow geometry for its selected
  source together with matching Window Pins.
- [ ] Complete accessibility review for keyboard navigation, VoiceOver labels,
  focus order, contrast, text scaling, and reduced motion.
- [ ] Complete a sustained Share Preview performance run and record CPU, GPU,
  energy, memory, frame delay, OCR latency, thermal behavior, and recovery after
  dynamic-rule interruption.

## Screenshots and review package

- [ ] Capture the exact shipping build with fabricated content only.
- [ ] Discard the pre-Text-Follow/legacy-allowance screenshot set. Recapture all
  five scenes from the current shipping UI after the new feature and independent
  allowance copy are final; changing captions alone is not acceptable evidence.
- [ ] Add all ten files specified by `screenshot_manifest.json` at one accepted
  16:10 Mac size, then run the validator with `--require-screenshots`.
- [ ] Inspect every image at actual storefront size for legibility, clipping,
  personal menu-bar data, notifications, and stale UI terminology.
- [ ] Ensure Japanese and English images have equivalent scenes and accurate
  localized headlines.
- [ ] App Review Notes reproduce from a clean macOS account using only the
  submitted binary and public instructions.
- [ ] The first Non-Consumable is attached to the app-version submission, is in
  Ready to Submit state, and includes an accurate In-App Purchase review
  screenshot from the submitted UI.
- [ ] Review Notes identify the Product ID and reproduce the 11th Display Pin,
  6th Window Pin, and 3rd Text Follow rule gates before one purchase, plus the
  resumed picker/creator and Restore Purchases paths with StoreKit's localized
  price.
- [ ] Review Notes include a fabricated repeated-text fixture and exact steps to
  exercise the Text Follow picker, exact/prefix/contains/regex modes,
  case-sensitive whole-block Contains behavior, every-block Mosaic, Share
  Preview dynamic composition, both strict-safety zero-match behaviors, immediate
  clear/full cover while a relevant rule is not ready, child-window exclusion,
  desktop Mosaic fallback, and remaining OCR limitations.
- [ ] Attach a synthetic test fixture and short permission-flow video if needed;
  neither contains private data or access credentials.
- [ ] Explain any review-only setup in Review Notes. Never provide a real user,
  customer, or production account.

## Final release decision

- [ ] The release owner has checked the exact binary, metadata, screenshots,
  purchase flow, and Review Notes against the current App Review Guideline 2.2.
  The submission is a complete app, not a beta, demonstration, or trial build;
  `Text Follow (Beta)` is an optional, non-expiring OCR feature whose label
  describes only its maturity. Any unresolved 2.2 concern blocks submission.
- [ ] Run `python3 StoreAssets/Scripts/validate_metadata.py --require-screenshots`
  immediately before metadata upload.
- [ ] Compare the uploaded metadata, screenshots, privacy answers, agreements,
  binary hash, version, category, territories, and release mode with the signed
  approval record.
- [ ] A named release owner confirms that every unchecked item is either closed
  or blocks submission. Silence, a passing build, or automated validation alone
  is not approval to submit.
