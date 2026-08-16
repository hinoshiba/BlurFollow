# BlurFollow privacy statement

Last updated: 2026-08-16<br>
Applies to: the open-source BlurFollow 0.1.0 macOS code and an unmodified build

BlurFollow places visual effects over screen regions, can follow a saved region
as its source window moves, and can create a locally processed Share Preview.
It is a convenience and verification aid, not a confidentiality service. This
statement describes the current code. A distributor that adds networking,
accounts, licensing, payments,
analytics, crash reporting, advertising, cloud sync, or an updater must publish
its own accurate policy before distribution.

## At a glance

- BlurFollow has no account system, advertising, analytics, telemetry, or
  third-party runtime SDK.
- Share Preview uses Apple's ScreenCaptureKit system picker and only begins after
  the user deliberately chooses a window and macOS authorizes capture. On
  macOS 14 through 15.1, this build first requires the broader Screen Recording
  permission so it can identify the chosen window without guessing; macOS 15.2
  and later use the picker's selected-window identity directly.
- The app does not intentionally save captured frames, record a video, capture
  audio, or transmit captured frames or window metadata to a BlurFollow server.
- Screen pixels are processed on the Mac. A current preview frame exists
  transiently in process, graphics, and operating-system memory and is cleared
  from the app's preview state when capture stops or fails.
- Mask definitions and limited window-identifying metadata are stored locally
  so masks can be restored.

## Screen content

For Share Preview, ScreenCaptureKit delivers frames from the window selected in
Apple's system content picker. BlurFollow applies the configured visual effects
in memory and displays the resulting frame in its Share Preview window. Audio
capture is disabled. `Preview active` means only that the app is displaying a
current processed frame under its validation rules; it does not certify that a
meeting app is receiving that window or that obscured content is unreadable.

The application contains no code path intended to encode or write those frames
to a file, send them over a network, use them for analytics, or use them to
train a model. The last preview image is removed from application state when
capture stops. “Not saved” does not mean a forensic guarantee that pixels can
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
  bundle identifier, window title, and initial window bounds; and
- global enable, Last-position cover, and onboarding settings.

An unsandboxed build normally stores this at:

```text
~/Library/Application Support/BlurFollow/Masks.json
```

A sandboxed Mac App Store build stores the equivalent file inside the app's
container, normally under:

```text
~/Library/Containers/blurfollow.hinoshiba.com/Data/Library/Application Support/BlurFollow/Masks.json
```

The exact container can vary with bundle identifier and distribution. Window
titles and user-chosen mask names can themselves be sensitive. The file is not
encrypted by BlurFollow; normal macOS account permissions and any FileVault
protection apply.

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

Display overlays do not require BlurFollow to ingest screen frames. Share Preview
requires a deliberate selection in Apple's `SCContentSharingPicker`. Permission
behavior in the current implementation is version-specific:

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

To follow windows, BlurFollow reads WindowServer metadata made available through
public Apple APIs, including window identifiers, owner process/application,
title, position, size, layer, and on-screen state. It does not request macOS
Accessibility permission and does not read keystrokes or clipboard contents.

BlurFollow uses Apple's system content-sharing picker rather than a custom picker.
The picker and permission controls are provided by macOS and are subject to
Apple's platform privacy practices.

## Network activity and disclosure

The audited 0.1.0 application target has no network client and no remote
endpoint. BlurFollow does not sell personal information, share it for advertising,
or track users across apps or websites. The OS, App Store, notarization and
code-signing services, a download host, or a third-party conferencing app may
process information independently under their own terms; that is not an app
runtime transmission to a BlurFollow service.

Under Apple's App Privacy definition, data processed only on the device is not
“collected.” On the present implementation, the expected App Store answer is
therefore that the developer collects no data through the app. The accountable
publisher must re-audit the exact submitted binary and current Apple questions;
this statement is not a substitute for that submission review or for legal
definitions in a user's jurisdiction.

The checked-in `PrivacyInfo.xcprivacy` mirrors this baseline with tracking off
and no collected-data or required-reason API declarations. It is a machine-
readable assertion, not automatic proof: scan the exact archive and update the
manifest before release if code, SDKs, or Apple's requirements change.

## Retention, deletion, and choices

- Stop Share Preview to end the capture stream and clear the current preview from
  application state.
- Disable or delete individual masks in the app. “Delete All Masks” writes an
  empty region list to the primary settings file, retains global settings, and
  deletes BlurFollow's `Masks.json.backup` recovery copy.
- To remove all locally persisted BlurFollow settings for that build, quit BlurFollow
  first and delete both `Masks.json` and `Masks.json.backup` if present, so the
  app cannot restore or rewrite a snapshot during deletion.
- Delete any configuration exports separately, including copies held by backup
  or synchronization products.
- End the capture from BlurFollow or macOS's sharing control. On macOS 14 through
  15.1, also revoke the persistent Screen Recording grant in System Settings
  when it is no longer wanted.
- Uninstalling the app may not automatically delete its Application Support or
  sandbox container data; remove it manually if desired.

Because the current app has no BlurFollow account or server storage, there is no
server-side profile for the project to access, export, or delete.

## Security and limitations

BlurFollow is intended to make visual-effect placement easier to follow and to
give the user a processed preview to check before sharing. It does not guarantee
confidentiality, capture inclusion, mask placement, or unreadability. Blur and
mosaic may leave information inferable, tracking can fail, another app can
capture the unmodified source, and a participant can record shared output.
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
