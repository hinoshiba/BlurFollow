# Compatibility and verification matrix

Last reviewed: 2026-08-16<br>
Declared minimum: macOS 14.0

This file distinguishes a declared target from recorded test evidence. A
release is not “compatible” merely because it compiles. Results must be recorded for the
exact signed artifact and current versions of macOS and sharing products.

## Platform contract

| Area | Current contract |
| --- | --- |
| macOS | 14.0 or later (`Package.swift`, Xcode settings, and direct build agree). |
| CPU | Development builds target the current host architecture; the direct distribution script produces a universal `arm64` + `x86_64` binary. |
| UI | Native AppKit/SwiftUI; no browser engine or third-party UI runtime. |
| Capture | ScreenCaptureKit with Apple's single-window content picker. macOS 14–15.1 first requires broad Screen Recording permission for exact identity resolution without guessing; macOS 15.2+ uses the picker's selected-window identity without proactively requesting that broader grant. |
| Overlay tracking | Public `CGWindowList` metadata; no Accessibility permission or private window API. |
| Network | None in the audited 0.1.0 app target. |
| Audio | Not captured by Share Preview. |
| Storage | Local mask JSON in Application Support; sandboxed builds use their app container. |

`SCStreamConfiguration.includeChildWindows` is enabled on macOS 14.2 and later.
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
| Entire display | Display Pins and visible Window Pin overlay panels | A capture product may filter windows or capture below overlays. Confirm inclusion in the receiver-side preview every time. |
| One source app/window in another product | Do not rely on desktop overlays | Other-app overlay panels are normally excluded. Create Share Preview and share its window. |
| Browser tab | Do not rely on desktop overlays | A tab stream contains browser-rendered content, not unrelated desktop windows. Share the BlurFollow Share Preview window instead. |
| BlurFollow Share Preview window | Processed selected-window frames with matching enabled Window Pins | Display Pins are not applied. `Preview active` describes BlurFollow's own current frame only. Confirm source, every mask, the chosen sharing target, and receiver-side output. |

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
- Menus, sheets, tooltips, popovers, child windows, notifications, and cursors
  can appear outside a saved region. Share Preview includes child windows only
  where the OS path supports it; the cursor is intentionally shown.
- DRM/protected video or security-sensitive apps may return blank or restricted
  capture through ScreenCaptureKit. BlurFollow must not work around that behavior.
- Blur and mosaic can preserve recognizable structure. Use opaque Redact when
  the intent is to visually replace configured pixels, remove secrets from the
  source whenever possible, and still check placement receiver-side.
- Performance depends on source size, frame rate, GPU/WindowServer load, number
  and strength of effects, and the capture product. A stalled preview is not
  evidence of current output.
- macOS 14 through 15.1 require a persistent broad Screen Recording grant for
  BlurFollow's identity-resolution path. macOS 15.2+ normally uses picker-scoped
  authorization instead. Grants are tied to macOS privacy controls and code
  identity; moving between unsigned development, Developer ID, and App Store
  builds can change behavior or require separate consent/relaunch.
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
- the current macOS release on an Intel Mac for a universal direct artifact;
- the Developer ID artifact from a clean standard user account; and
- the sandboxed/App Store archive independently when that channel is offered.

If hardware or an OS version cannot be tested, narrow the published support
claim or document the exception and risk approval in the release record.

### Permissions and lifecycle

- macOS 14 through 15.1 first launch with no Screen Recording decision, denial,
  grant, the required reopen before retry, later revocation, and re-grant;
- macOS 15.2+ picker cancel/deny/select/end with no pre-existing broad grant,
  plus behavior when a broad grant already exists;
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
  replace, and retarget the last applicable Window Pin; no frame from the prior
  mask revision may restore visible source pixels or `Preview active`;
- induce a `nil` → error settings-persistence/recovery transition during
  capture and confirm the emitted error immediately gives the processor an
  empty applicable-region set, selects the opaque fallback, and clears
  `Preview active` without waiting for another frame;
- sleep/wake, lock/unlock, fast user switching, and display reconnect; and
- delete/export settings in both sandboxed and unsandboxed data locations;
- corrupt primary with a valid backup, corrupt primary and backup, recovery
  acknowledgement, and confirmation that `Preview active` remains unavailable
  before review; and
- “Delete All Masks” leaves an empty primary region list, removes
  `Masks.json.backup`, and cannot resurrect prior masks after relaunch.

### Geometry and identity

- display-relative region on every connected display;
- window move, resize from every edge, maximize, minimize, zoom, and full screen;
- move across displays with equal and mixed scale factors and negative desktop
  coordinates;
- Spaces, Stage Manager, Mission Control, display rotation/mirroring, and hot-plug;
- close/reopen and app relaunch with one matching window;
- two or more same-app windows with the same title and similar geometry;
- dynamic title change, untitled window, modal sheet, popover, menu, tooltip,
  notification, and child window; and
- source disappearing while Last-position cover is on and off;
- imported/corrupted settings with zero, negative, non-finite (where decoding
  permits), or wholly out-of-bounds mask geometry; output must block rather than
  report the invalid mask as applied.

Measure not only final alignment but transient divergence during motion. The
`Following`/`Position known` label and Last-position cover must match what is
actually shown. These labels describe observed app state; they are not a
confidentiality or capture-inclusion guarantee.

### Sharing outputs

For at least one supported conferencing product and one recording/production
product per release:

1. share the entire display and confirm overlay inclusion;
2. share the original source window and confirm the product warning explains
   that BlurFollow's separate overlay may be absent;
3. share a browser tab and confirm the warning;
4. create Share Preview via the Apple picker, then share the BlurFollow Share
   Preview window and inspect the receiver-side output;
5. verify each effect, especially fully opaque Redact, at edges and corners;
6. confirm Share Preview captures no audio and no application-created frame/video
   file appears during or after the session; and
7. stop or force an error and confirm the last frame is immediately absent and
   the receiver sees no stale content presented as live.

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
- sandbox/Developer ID/development channel and permission state;
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
