# Compatibility and verification matrix

Last reviewed: 2026-08-29<br>
Declared minimum: macOS 14.0

This file distinguishes a declared target from recorded test evidence. A
release is not “compatible” merely because it compiles. Results must be recorded for the
exact signed artifact and current versions of macOS and sharing products.

## Platform contract

| Area | Current contract |
| --- | --- |
| macOS | 14.0 or later (`Package.swift`, Xcode settings, and development build agree). |
| CPU | Development builds target the current host architecture; the Xcode Cloud App Store archive targets `arm64` + `x86_64`. |
| UI | Native AppKit/SwiftUI; no browser engine or third-party UI runtime. |
| Capture | ScreenCaptureKit with Apple's single-window content picker. macOS 14–15.1 first requires broad Screen Recording permission for exact identity resolution without guessing; macOS 15.2+ uses the picker's selected-window identity without proactively requesting that broader grant. |
| Overlay tracking | Public `CGWindowList` metadata; no Accessibility permission or private window API. |
| Text Follow (Beta) | “Beta” is a product-maturity label only. It does not relax capture boundaries, fail-closed behavior, privacy commitments, or this verification matrix. |
| Network | No developer-operated network client or endpoint. The official 0.2.0 App Store target uses Apple StoreKit for optional product, purchase, entitlement, and restore operations. |
| Audio | Not captured by Share Preview. |
| Storage | Local mask JSON in Application Support; sandboxed builds use their app container. |

Text Follow OCR and Share Preview both exclude child windows so recognition
rectangles and the composited source use the same selected-window boundary. On
macOS 14.2 and later each path explicitly sets
`SCStreamConfiguration.includeChildWindows` to false; the earlier compatibility
path likewise captures only the selected source window.
On macOS 14 through 15.1, BlurFollow calls `CGPreflightScreenCaptureAccess` and
`CGRequestScreenCaptureAccess`; refusal stops selection. After authorization,
the current build requires an app reopen, then enumerates on-screen candidates
and accepts only one exact filter-geometry match. On macOS 15.2 and later, it
reads the picker-authorized window directly from
`SCContentFilter.includedWindows` and does not proactively request the broad
grant. These paths require separate testing.

## Sharing-mode compatibility

| User shares | Expected BlurFollow workflow | Important limitation |
| --- | --- | --- |
| Entire display | Display Pins plus visible Window Pin and Text Follow overlay panels | A capture product may filter windows or capture below overlays. Confirm inclusion in the receiver-side preview every time. |
| One source app/window in another product | Do not rely on desktop overlays | Other-app overlay panels are normally excluded. Create Share Preview and share its window. |
| Browser tab | Do not rely on desktop overlays | A tab stream contains browser-rendered content, not unrelated desktop windows. Share the BlurFollow Share Preview window instead. |
| BlurFollow Share Preview window | Processed selected-window frames with matching enabled Window Pins and completed matches from connected, enabled Text Follow rules for that source | Display Pins are not applied. Any relevant dynamic rule that is not ready clears and fully covers the preview. The default strict safety preference also covers a completed zero-match scan; disabling it permits that coherent result to become `Preview active`, but lowers resistance to OCR false negatives. Confirm source, every mask, the chosen sharing target, and receiver-side output. |

BlurFollow does not modify Chrome, Safari, Firefox, Edge, Zoom, Teams, Meet, Slack,
OBS, or any other product. Their capture implementation and updates can change
results without a BlurFollow code change. Product names are descriptive only and
do not imply testing, support, or endorsement.

## Known environmental limitations

- Window IDs last only for the life of a window. Reopen/relaunch rebinds only
  when exactly one visible app/title match exists; multiple similar windows
  remain unavailable and require the user to select again.
- Minimized, hidden, off-Space, full-screen, Stage Manager, Mission Control,
  fast animation, and app relaunch transitions can temporarily remove or alter
  public window metadata.
- Mixed Retina/non-Retina scale, rotation, mirroring, Sidecar/AirPlay, virtual
  displays, display hot-plug, and arrangement changes need explicit testing.
- Text Follow OCR and Share Preview both exclude child windows and source-cursor
  pixels so they share one selected-source coordinate boundary. Menus, sheets,
  tooltips, popovers, notifications, and other separate windows can therefore be
  absent from both; receiver-side capture software can still add its own cursor.
- DRM/protected video or security-sensitive apps may return blank or restricted
  capture through ScreenCaptureKit. BlurFollow must not work around that behavior.
- Blur and mosaic can preserve recognizable structure. Use opaque Redact when
  the intent is to visually replace configured pixels, remove secrets from the
  source whenever possible, and still check placement receiver-side.
- Desktop Mosaic must use `CIPixellate` on the actual backdrop when the public
  filter is available and show an opaque fallback when it is unavailable. Test
  both branches; a decorative translucent grid over readable source is invalid.
- Performance depends on source size, frame rate, GPU/WindowServer load, number
  and strength of effects, and the capture product. A stalled preview is not
  evidence of current output.
- macOS 14 through 15.1 require a persistent broad Screen Recording grant for
  BlurFollow's identity-resolution path. macOS 15.2+ normally uses picker-scoped
  authorization instead. Grants are tied to macOS privacy controls and code
  identity; moving between development and App Store builds can change behavior
  or require separate consent/relaunch.
- Virtual machines and remote-desktop sessions may not expose capture or display
  behavior equivalent to physical hardware; they cannot be the sole release
  evidence.

## Required release matrix

Record pass/fail, tester, date, exact app SHA-256, macOS build, hardware, source
app version, sharing product version, and notes. A blank cell is **not tested**,
not an implicit pass.

### Operating systems and architectures

At minimum test:

- the oldest supported macOS 14.x release environment available to the team;
- the latest security update of every macOS major version still claimed;
- the current macOS release on Apple silicon;
- the current macOS release on an Intel Mac when Intel support is advertised;
  and
- the Xcode Cloud/TestFlight App Store candidate from a clean standard user
  account.

### StoreKit and plan boundary

- Create 10 Display Pins, 5 Window Pins, and 2 Text Follow (Beta) rules without
  purchase; verify each category's next request is stopped before its range
  selector or picker opens, while unused capacity in another category does not
  change that result. Beta status does not change these free allowances or the
  verified Unlimited Masks unlock.
- Match the same Text Follow pattern in zero, one, and several simultaneous
  blocks and verify it remains one saved rule and one plan item.
- Purchase, cancel, fail, defer/Ask to Buy, restore, relaunch, refund, revoke,
  and test with product information unavailable or the Mac offline.
- Verify 0.1.1 original app transactions retain unlimited creation and new
  0.2.0 app transactions do not receive grandfather status.
- Keep every existing mask and Text Follow rule visible and editable when
  entitlement becomes unavailable, including configurations already above a
  category limit.
- Verify StoreKit's localized product name and price in Japanese and English;
  never accept a hardcoded fallback price.
- Exercise the neutral review request only after two successful Share Preview
  checks and seven days, with no picker or commerce UI active.

If hardware or an OS version cannot be tested, narrow the published support
claim or document the exception and risk approval in the release record.

### Permissions and lifecycle

- macOS 14 through 15.1 first launch with no Screen Recording decision, denial,
  grant, the required reopen before retry, later revocation, and re-grant;
- macOS 15.2+ picker cancel/deny/select/end with no pre-existing broad grant,
  plus behavior when a broad grant already exists;
- create, reconnect, disable, re-enable, delete, and relaunch Text Follow rules;
  picker-scoped capture must not be silently treated as persistent after relaunch;
- navigate, scroll, zoom, and rapidly replace content while OCR is in flight;
  a prior generation must never restore superseded match panels;
- exercise exact, prefix, case-sensitive contains, and regular-expression modes;
  for Contains, verify a substring match covers the entire Vision-recognized
  block and that several matching blocks still consume one saved-rule slot;
- place one pattern in multiple blocks, including repeated blocks and several
  matches within one recognized line; every matching block should be covered
  once and runtime panel count must not affect the plan count;
- deliver blank, suspended, stopped, invalid, and stream-error Text Follow
  samples; all current detected panels must clear and recognized text must not
  appear in settings, export, logs, or error UI;
- with Share Preview using the same source, exercise every relevant Text Follow
  state: missing connection/reconnect-required, connecting, scanning,
  source-unavailable, failed, missing runtime, stale identity, and inconsistent
  state/rectangle pairs must immediately clear the old image and select the full
  opaque cover regardless of the strict safety preference; a completed scan with
  zero matches must select full cover with strict safety enabled and remain a
  renderable configuration with it disabled, without claiming OCR completeness;
- combine multiple connected rules and Window Pins for one source; every match
  from every completed rule must be composited once, and a blocked state in any
  one relevant enabled rule must cover the whole preview rather than silently
  omit only that rule;
- trigger permission/restart-required and picker-resolution failures from every
  Share Preview entry point; each must show an actionable error rather than discard
  the failure;
- start, source close, source crash, stream error, stop, app quit, and reopen;
- present “Choose Another Window,” then close or navigate away from Share Preview
  before selecting; a late picker callback must not restart capture or recreate
  a closed sharing view;
- start a picker request from one workflow, then attempt every other picker
  entry point; the active owner must retain its request token, other requests
  must finish with a localized busy error, and an unrelated view disappearance
  must not cancel the active picker;
- cancel or close the picker owner and exercise a late callback; the picker slot
  must remain occupied until that callback resolves, then release exactly once
  without starting capture for the closed owner;
- rapid start/stop and source changes, confirming no late/stale frame returns;
- deliver blank, suspended, or stopped source status followed immediately by an
  idle heartbeat; the opaque fallback/clear delivery must win and idle must not
  restore or refresh the prior visual frame;
- overlapping concurrent start requests and start immediately followed by stop,
  confirming an obsolete stream can never own the current UI/output;
- while the source is idle and while frames are in flight, delete, disable,
  replace, or retarget the last applicable Window Pin, and delete, disable,
  reconnect, or rescan a relevant Text Follow rule; no frame from the prior
  combined revision may restore visible source pixels or `Preview active`;
- induce a `nil` → error settings-persistence/recovery transition during
  capture and confirm the emitted error immediately gives the processor an
  empty applicable-region set, selects the opaque fallback, and clears
  `Preview active` without waiting for another frame;
- sleep/wake, lock/unlock, fast user switching, and display reconnect; and
- delete/export settings in both sandboxed and unsandboxed data locations;
- corrupt primary with a valid backup, corrupt primary and backup, recovery
  acknowledgement, and confirmation that `Preview active` remains unavailable
  before review; and
- “Delete All Masks and Rules” leaves empty primary definition lists, removes
  `Masks.json.backup`, and cannot resurrect prior masks or rules after relaunch.

### Geometry and identity

- display-relative region on every connected display;
- window move, resize from every edge, maximize, minimize, zoom, and full screen;
- move across displays with equal and mixed scale factors and negative desktop
  coordinates;
- Spaces, Stage Manager, Mission Control, display rotation/mirroring, and hot-plug;
- close/reopen and app relaunch with one matching window;
- two or more same-app windows with the same title and similar geometry;
- dynamic title change, untitled window, modal sheet, popover, menu, tooltip,
  notification, and child window; verify the child-window exclusion boundary is
  identical for OCR and Share Preview; and
- source disappearing while Last-position cover is on and off;
- imported/corrupted settings with zero, negative, non-finite (where decoding
  permits), or wholly out-of-bounds mask geometry; output must block rather than
  report the invalid mask as applied; and
- exact, prefix, contains, and regular-expression Text Follow rules in Japanese and
  English, invalid and pathologically long expressions, mixed Retina scale,
  resized windows, and OCR bounding boxes touching capture-content edges.

Measure not only final alignment but transient divergence during motion. The
`Following`/`Position known` label and Last-position cover must match what is
actually shown. These labels describe observed app state; they are not a
confidentiality or capture-inclusion guarantee.

### Sharing outputs

For at least one supported conferencing product and one recording/production
product per release:

1. share the entire display and confirm overlay inclusion;
2. exercise Text Follow through several page/screen transitions, verify every
   simultaneous match in the entire-display receiver output, and record OCR
   latency, false positives, and false negatives;
3. share the original source window and confirm the product warning explains
   that BlurFollow's separate overlay may be absent;
4. share a browser tab and confirm the warning;
5. create Share Preview via the Apple picker, then share the BlurFollow Share
   Preview window; verify matching Window Pins and every completed Text Follow
   result, a completed zero-match scan with strict safety both enabled and
   disabled, and each fail-closed dynamic state in the receiver-side output;
6. verify each effect, especially fully opaque Redact, at edges and corners;
7. confirm Share Preview and Text Follow capture no audio and no application-created frame/video
   file appears during or after the session;
8. stop or force an error and confirm the last frame/detected geometry is immediately absent and
   the receiver sees no stale content presented as live; and
9. verify desktop Mosaic visibly pixelates the live backdrop with `CIPixellate`,
   then inject or simulate filter unavailability and confirm the region becomes
   opaque rather than exposing readable source content.

The receiving participant's view is the authoritative end-to-end check. A local
overlay or Share Preview alone is insufficient. BlurFollow follows coordinates
that public APIs report; the user remains responsible for checking placement
and the chosen sharing target before sharing.

### Quality and accessibility

- VoiceOver names/status, full keyboard operation, focus order, and text at
  larger accessibility sizes;
- light/dark appearance, increased contrast, reduced transparency, and reduced
  motion where applicable;
- Japanese and English UI, long window/app names, and right-to-left stress text;
- multi-hour capture, CPU/GPU/memory pressure, thermal behavior, and dropped
  frames; and
- no secret, real customer content, or personal title in screenshots/logs.

## Reporting a compatibility result

Use a synthetic source and include:

- exact BlurFollow version and artifact hash;
- macOS version/build and Mac model/architecture;
- App Store/development channel and permission state;
- source and sharing product versions;
- display layout/scale, Space/full-screen state, and mask mode/style;
- receiver-side expected and observed behavior; and
- a sanitized reproduction.

Do not file a public report containing sensitive captured content. A mismatch
that can display source pixels the user expected to obscure is a security
report under
[../SECURITY.md](../SECURITY.md).

Do not claim compatibility with a third-party product until its exact tested
version appears in signed release evidence. Compatibility statements are
technical observations, not warranties or legal advice.
