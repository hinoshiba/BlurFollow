# BlurFollow privacy statement

Last updated: 2026-08-29<br>
Applies to: the open-source BlurFollow 0.2.0 macOS code and an unmodified build

BlurFollow places visual effects over screen regions, can follow a saved region
as its source window moves, can find user-configured text patterns in a selected
window, and can create a locally processed Share Preview.
The text-pattern feature is named **Text Follow (Beta)**. “Beta” describes
product maturity only; it does not weaken or change any capture, storage,
transmission, retention, deletion, safety, or user-control commitment below.
It is a convenience and verification aid, not a confidentiality service. This
statement describes the current code. A distributor that adds networking,
accounts, alternative payment providers,
analytics, crash reporting, advertising, cloud sync, or an updater must publish
its own accurate policy before distribution.

## At a glance

- BlurFollow has no account system, advertising, analytics, telemetry, or
  third-party runtime SDK.
- The official Mac App Store build uses Apple's StoreKit for an optional
  one-time Unlimited Masks product, purchase verification, restoration, and the
  system rating prompt. BlurFollow operates no commerce server and does not
  receive Apple Account credentials or payment-card details.
- Text Follow and Share Preview use Apple's ScreenCaptureKit system picker and
  only begin after the user deliberately chooses a window and macOS authorizes
  capture. On
  macOS 14 through 15.1, this build first requires the broader Screen Recording
  permission so it can identify the chosen window without guessing; macOS 15.2
  and later use the picker's selected-window identity directly.
- The app does not intentionally save captured frames, record a video, capture
  audio, or transmit captured frames or window metadata to a BlurFollow server.
- Screen pixels are processed on the Mac. Text Follow uses Apple's on-device
  Vision framework to recognize text blocks and compares them with the saved
  rule. Captured frames and recognized strings exist only transiently in
  process, graphics, and operating-system memory and are cleared from app state
  when their capture stops or fails.
- Share Preview composites matching Window Pins and completed Text Follow
  detections for its selected source. Text Follow OCR and Share Preview exclude
  child windows so both operate on the same selected-window content boundary.
- Mask definitions and limited window-identifying metadata are stored locally
  so masks can be restored.
- Review-prompt eligibility counters and dates stay in local preferences and
  are not sent to the developer.

## Screen content

For Text Follow, ScreenCaptureKit delivers frames from a window deliberately
selected in Apple's system content picker. Apple's Vision framework recognizes
text on the Mac. BlurFollow compares each recognized block with the configured
case-sensitive exact, prefix, contains, or regular-expression rule and keeps
only the temporary geometry needed to place Mosaic overlays. Contains searches
inside a recognized string, but BlurFollow covers the entire Vision-recognized
block rather than retaining or masking only the matched substring. One rule can
cover every matching block visible in a frame. Recognized strings and captured pixels are
not written to the mask configuration, a file, analytics, a network service, or
a training pipeline. OCR can miss, misread, or temporarily lag content; a
visible status or match count is not a confidentiality guarantee.

For Share Preview, ScreenCaptureKit delivers frames from the window selected in
Apple's system content picker. BlurFollow applies matching Window Pins plus the
temporary Mosaic geometry from every connected, enabled Text Follow rule for
that same source after its latest scan completes. The preview clears its prior
frame immediately and displays a full opaque cover while any relevant rule is
unconnected, reconnecting, connecting, scanning, failed, source-unavailable, or
internally inconsistent. With the default strict Text Follow safety preference,
a completed scan with zero matches also keeps the preview fully covered because
zero is not evidence that the source contains no matching or sensitive text.
When that preference is disabled, a coherent completed zero-match scan can
display the current frame; this avoids a full-frame flash but reduces resistance
to OCR false negatives. Audio capture is disabled.
`Preview active` means only that the app is displaying a current processed frame
under these validation rules; it does not certify that OCR was complete, that a
meeting app is receiving that window, or that obscured content is unreadable.

Both Text Follow OCR and Share Preview configure the selected source without
child windows, so their recognition and compositing coordinates describe the
same boundary. A menu, sheet, popover, notification, or other separately captured
child window can therefore be absent from both outputs even when it is visible
near the source on the desktop.

For the desktop overlay path, Mosaic uses the public Core Image `CIPixellate`
filter to transform the actual backdrop. If that filter cannot be created, the
overlay draws an opaque fallback instead of intentionally leaving readable
source pixels visible. This rendering behavior does not make Mosaic an
irreversible redaction method.

The application contains no code path intended to encode or write captured
frames or OCR output to a file, send them over a network, use them for analytics,
or use them to train a model. The last preview image and current Text Follow
detections are removed from application state when their capture stops. “Not
saved” does not mean a forensic guarantee that pixels or recognized text can
never appear in operating-system swap, graphics buffers, crash diagnostics,
screenshots, backups, or another process with screen-capture access; those
systems are outside the app's complete control.

When the user deliberately shares or records the **BlurFollow Share Preview
window** with a conferencing, streaming, or recording product, that other
product receives the displayed processed preview under its own privacy terms.
BlurFollow does not control the recipient, meeting host, conferencing provider, or later
recording. Sharing the original app, original window, or browser tab instead
does not include BlurFollow's Share Preview and may omit its desktop overlay.
The user must review both the BlurFollow preview and the receiver-side
meeting/recording preview before disclosing anything.

## Local configuration data

BlurFollow stores a JSON configuration containing:

- mask name, normalized rectangle, effect, strength, corner radius, enabled
  state, creation date, and display identifier;
- for a Window Pin, the source window ID, source process ID, application name,
  bundle identifier, window title, and initial window bounds;
- for a Text Follow rule, its user-chosen name, exact/prefix/contains/regular-expression
  pattern, Mosaic appearance and padding, enabled state, creation date, and the
  same limited source-window identity metadata; and
- global enable, Last-position cover, strict Text Follow safety-cover, and
  onboarding settings.

Separately, local UserDefaults contain the first-use date, successful Share
Preview check count, and last rating-request version/date. These values only
delay and limit use of Apple's standard rating prompt. They are not used for
analytics, profiling, purchase eligibility, or transmission to the developer.
Purchase and grandfather access are derived from StoreKit-verified signed
transactions, not from the mask JSON or a locally editable entitlement flag.

An unsandboxed build normally stores this at:

```text
~/Library/Application Support/BlurFollow/Masks.json
```

A sandboxed Mac App Store build stores the equivalent file inside the app's
container, normally under:

```text
~/Library/Containers/com.hinoshiba.blurfollow/Data/Library/Application Support/BlurFollow/Masks.json
```

The exact container can vary with bundle identifier and distribution. Window
titles, user-chosen mask names, and Text Follow patterns can themselves be
sensitive. The file is not encrypted by BlurFollow; normal macOS account
permissions and any FileVault protection apply.

BlurFollow may maintain a last-known-valid recovery copy beside that file as
`Masks.json.backup`. It contains the same categories of configuration and
window metadata as the primary snapshot, potentially from the preceding save.
If the primary file is damaged, BlurFollow validates the backup before restoring
it and prevents `Preview active` until the user reviews and acknowledges the
recovery warning. If neither snapshot validates, Share Preview remains inactive
and the user must recreate masks.

“Export Mask Settings” writes the same configuration to a location the user
selects. That exported copy is then managed by the user and may be synced or
backed up by other software.

## Permissions and system metadata

Display and Window Pin overlays do not require BlurFollow to ingest screen
frames. Text Follow and Share Preview require a deliberate selection in Apple's
`SCContentSharingPicker`. Permission behavior in the current implementation is
version-specific:

- On macOS 14 through 15.1, BlurFollow calls the public Screen Recording preflight
  and request APIs before showing the picker. This broader, persistent TCC grant
  is required by this compatibility path to enumerate candidate window metadata
  and resolve one exact selection without guessing. If the user refuses it,
  BlurFollow stops the operation rather than guessing a window. After a newly
  granted permission,
  the current implementation requires the user to reopen BlurFollow before retrying
  selection, so it never treats an incomplete same-process grant as sufficient.
- On macOS 15.2 and later, the content filter exposes the selected window
  directly. BlurFollow does not proactively request the broader grant for this
  path; the system picker authorizes the user-selected capture session.

macOS provides the picker and a menu-bar sharing indicator/control. A broad
Screen Recording grant is more authority than BlurFollow's intended one-window
capture flow, even though the current code constructs only the selected stream.
Users of macOS 14 through 15.1 should revoke it in System Settings when they no
longer need BlurFollow. Permission behavior remains tied to the signed code
identity and must be tested for each distribution channel and OS release.

To follow windows and place recognized text geometry, BlurFollow reads
WindowServer metadata made available through public Apple APIs, including
window identifiers, owner process/application, title, position, size, layer,
and on-screen state. Text recognition uses Vision rather than macOS
Accessibility. BlurFollow does not request Accessibility permission and does
not read keystrokes or clipboard contents.

BlurFollow uses Apple's system content-sharing picker rather than a custom picker.
The picker and permission controls are provided by macOS and are subject to
Apple's platform privacy practices.

## Network activity, StoreKit, and disclosure

The audited 0.2.0 application has no developer-operated network client, remote
endpoint, account service, analytics collector, or commerce server. BlurFollow
does not sell personal information, share it for advertising, or track users
across apps or websites.

In the official Mac App Store build, Apple StoreKit may contact App Store
services to load the localized Unlimited Masks product and price, obtain the
signed app transaction, verify current purchase entitlement, complete a
purchase, listen for transaction changes, restore a purchase after an explicit
user request, or present Apple's rating UI. BlurFollow receives only the
product and verified transaction/app-version state needed to display commerce
and decide whether another mask may be created. It does not provide screen
frames, window metadata, mask names or geometry, review-prompt counters, or
usage analytics to the StoreKit purchase flow. Apple handles Apple Account
authentication, billing, refunds, and its own records under Apple's terms.

The OS, App Store, code-signing services, or a third-party conferencing app may
process information independently under their own terms; that is not a
transmission to a BlurFollow-operated service.

Under Apple's App Privacy definition, data processed only on the device is not
“collected.” On the present implementation, the expected App Store answer is
therefore that the developer collects no data through the app. The accountable
publisher must re-audit the exact submitted binary and current Apple questions;
this statement is not a substitute for that submission review or for legal
definitions in a user's jurisdiction.

The checked-in `PrivacyInfo.xcprivacy` mirrors this baseline with tracking off
and no collected-data declarations. It declares the app-only UserDefaults use
under Apple's `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` for the
local review-prompt dates and counters described above. It is a machine-readable
assertion, not automatic proof: scan the exact archive and update the manifest
before release if code, SDKs, or Apple's requirements change.

## Retention, deletion, and choices

- Stop Share Preview or disable/delete a Text Follow rule to end its active use
  and clear the current preview or detected geometry from application state.
- Disable or delete individual masks in the app. “Delete All Masks” writes an
  empty region list to the primary settings file, retains global settings, and
  deletes BlurFollow's `Masks.json.backup` recovery copy.
- To remove all locally persisted BlurFollow settings for that build, quit BlurFollow
  first and delete both `Masks.json` and `Masks.json.backup` if present, so the
  app cannot restore or rewrite a snapshot during deletion.
- Delete any configuration exports separately, including copies held by backup
  or synchronization products.
- Local review-prompt counters can be removed with the app's container or
  preferences. App Store purchase records are managed by Apple; Restore
  Purchases asks StoreKit to synchronize them and does not delete them.
- End the capture from BlurFollow or macOS's sharing control. On macOS 14 through
  15.1, also revoke the persistent Screen Recording grant in System Settings
  when it is no longer wanted.
- Uninstalling the app may not automatically delete its Application Support or
  sandbox container data; remove it manually if desired.

Because the current app has no BlurFollow account or developer server storage, there is no
server-side profile for the project to access, export, or delete.

## Security and limitations

BlurFollow is intended to make visual-effect placement easier to follow and to
give the user a processed preview to check before sharing. It does not guarantee
confidentiality, capture inclusion, mask placement, OCR accuracy, or
unreadability. Blur and mosaic may leave information inferable, recognition or
tracking can fail or lag, another app can capture the unmodified source, and a
participant can record shared output.
Share Preview's fail-closed cover prevents a known incomplete Text Follow state
from being presented as active. The default strict safety preference also covers
a completed zero-match result; disabling it permits that result to render and
reduces resistance to OCR false negatives. Neither behavior proves that Vision
recognized every intended string.
Use opaque Redact rather than blur/mosaic when the intent is to visually replace
configured pixels, remove secrets from the source whenever possible, enable
Last-position cover for tracking loss, and verify the receiver-side
meeting/recording preview before every share. See
[Docs/THREAT_MODEL.md](Docs/THREAT_MODEL.md).

Report a suspected security or privacy defect through the private process in
[SECURITY.md](SECURITY.md), without attaching real sensitive frames.

## Changes and contact

Material behavior changes require an update to this file and an in-product or
release-note notice appropriate to the change. Repository history retains prior
versions of this statement.

For community/source builds, contact the maintainers through the canonical
repository's private contact method. **Before any official commercial or App
Store release**, the publishing legal person or entity must place its actual
name, jurisdiction-appropriate contact details, public privacy-policy URL,
support URL, and applicable rights-request process in the product and store
listing. A placeholder or repository-only contact does not pass the release
gate.

This project statement is provided for transparency and is not legal advice.
The publisher must obtain qualified review for applicable privacy, consumer,
employment, recording, biometric, export, and data-protection laws before sale
or deployment in regulated environments.

Apple's current platform-specific definition of collection and submission
instructions are available in [App privacy details on the App
Store](https://developer.apple.com/app-store/app-privacy-details/). Recheck the
live page for every submission.
