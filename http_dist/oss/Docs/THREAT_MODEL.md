# Threat model

Last reviewed: 2026-08-17<br>
Baseline: BlurFollow 0.1.1 on macOS 14 and later

BlurFollow is intended to make a visual effect follow a saved window-relative
position and to provide a processed preview the user can check before sharing.
It is not a confidentiality boundary and is not a substitute for closing secret
content. This model distinguishes a visible desktop overlay from Share Preview's
processed output because they use different capture paths and have different
limitations.

## Technical integrity objectives

1. Associate each enabled mask with the display or source-window metadata the
   user selected, while acknowledging that metadata cannot prove user intent.
2. Move and resize a Window Pin with that window; when tracking is lost, show a
   Last-position cover and a factual lost/reconnecting state rather than a
   small stale mask.
3. Mark Share Preview as `Preview active` only after enabled Window Pins have
   been applied to validated geometry for the current selected-source and mask
   revision; otherwise display an opaque fallback frame.
4. Minimize capture: one user-selected window, video only, transient processing,
   no intentional frame persistence or app-initiated upload.
5. Represent only observed state: `Following`, `Position known`,
   `Preview active`, or `Last-position cover`. None certifies confidentiality,
   capture inclusion, correct user selection, or unreadability.
6. Preserve integrity and provenance of official release artifacts.

## Assets

- screen pixels, which may contain credentials, messages, customer data, source
  code, health/financial information, or unreleased work;
- locally stored mask geometry, mask names, display identifiers, application
  names, bundle identifiers, window titles, IDs, and bounds;
- the user's decision about which window and which BlurFollow output to share;
- privacy permission and entitlement state;
- Xcode Cloud/App Store credentials, source tags, binaries, store records,
  SBOMs, and the BlurFollow brand; and
- user trust in mask placement and status indicators.

## Data flows and trust boundaries

### Desktop overlay path

```text
CGWindow metadata ──> WindowTracker ──> normalized mask geometry
                                             │
                                             v
source window ──> macOS compositor <── transparent NSPanel overlay
                                             │
                           entire-display capture by another app
```

Display Pins use normalized coordinates inside a selected display. Window Pins
use normalized coordinates inside a tracked window frame. `WindowTracker`
queries public `CGWindowList` metadata about 60 times per second and batches
the required window IDs for each refresh. It first
requires continuity of the selected `CGWindowID`, process, layer, and app
identity. After loss, it will rebind only when app/title candidates are treated
as unambiguous: exactly one matching visible candidate must remain.

The overlay is another window. It changes what is visibly composited on the
desktop but does not modify the source application's pixels. A third-party
product that captures only the source app/window or browser tab normally omits
the BlurFollow overlay.

### Share Preview path

```text
macOS 14–15.1 ──> broad Screen Recording permission ──┐
                                                     ├──> Apple system content picker
macOS 15.2+ ──> picker-scoped selection ─────────────┘              │
                                                                  v
                                                            SCContentFilter
                                                                  │
source window ──> ScreenCaptureKit frames ──> Core Image mask processor
                                              │
                                    BlurFollow Share Preview window
                                              │
                             user selects that window in meeting app
                                              │
                                conferencing/recording provider
```

Share Preview requests one window, enables the cursor, disables audio, processes
frames locally, and assigns the latest `CGImage` directly to a layer-backed preview. It applies enabled **Window
Pins** only when the tracker resolves that mask to the exact selected window ID,
process, and application identity. If none matches, it replaces the complete
preview with an opaque fallback frame instead of intentionally displaying an
unmasked frame. Display Pins do not apply to Share Preview. This describes
BlurFollow's own window, not what any capture product receives. The user must
inspect the BlurFollow preview, select the BlurFollow Share Preview window, and
then inspect the receiver-side meeting/recording preview; BlurFollow cannot
force or verify another app's sharing target.

The authorization boundary differs by OS version. On macOS 14 through 15.1,
the app requires the broad Screen Recording TCC grant before the picker because
that compatibility path must enumerate windows and resolve one exact geometry
match; denial stops selection, a newly granted permission requires reopening
BlurFollow, and zero or multiple matches fail. On macOS 15.2 and later,
`SCContentFilter.includedWindows` supplies the picker-authorized window identity
and BlurFollow does not proactively request the broad grant.

Frames pass through ScreenCaptureKit, pixel buffers, Core Image, a `CGImage`,
and the preview in process/graphics/system memory. The app has no intended
encoder, recording file, or network sink. Stop/error paths clear preview state;
release tests must guard against a queued late frame repopulating it.

### Persistence and release boundary

`MaskStore` atomically writes configuration JSON to Application Support (inside
the container for a sandboxed build) and can retain a validated
`Masks.json.backup` recovery snapshot. A corrupt primary restores only from a
validated backup and prevents `Preview active` pending user review; an
unrecoverable snapshot starts with Share Preview inactive. “Delete All Masks”
writes an empty primary region list and removes the recovery copy. It never intentionally stores
a captured frame. A user-initiated export copies configuration to a chosen file.

Official source, GitHub CI, Xcode Cloud signing, App Store Connect, and the
user's store receipt form a separate software-supply-chain boundary.

## Actors and assumptions

We consider mistakes by the presenter, ordinary source apps, a misleading or
malfunctioning conferencing app, an untrusted meeting participant, malicious
local software running with user-granted capabilities, a dependency/supply-chain
attacker, and an unauthorized downstream distributor.

We assume macOS public APIs, WindowServer, code signing, TCC, ScreenCaptureKit,
and Core Image behave as documented; the official build is not already
compromised; the user can see status and preview; and the user controls the Mac.
Compromise of macOS, firmware, the administrator account, or release signing
identity defeats important assumptions.

## Threats, controls, and residual risk

| Threat | Current control | Residual risk / required user action |
| --- | --- | --- |
| User shares the original browser tab or window | Share Guide says separate-app overlays are excluded and offers Share Preview. | BlurFollow cannot change another app's selection. Share the BlurFollow Share Preview window and verify the meeting preview. |
| Window moves or resizes | Window-relative normalized geometry and approximately 60 Hz batched frame tracking. | Mask position can lag or diverge during latency, animation, Mission Control, display reconfiguration, or OS/API failure. Check the receiver-side preview. |
| Source window disappears | Last-position cover can cover the entire last-known window in opaque Redact mode and marks tracking lost/reconnecting. | It covers only recorded last-known geometry. The source can reappear elsewhere, so the cover is not proof of current placement. Stop sharing on any warning. |
| Rebind chooses the wrong window | ID/process/layer/app continuity first; later rebind requires exactly one visible owner/title match. | A unique metadata match cannot prove semantic identity. Confirm after reopen or document/title change. |
| Overlay is absent from captured output | Product explicitly separates entire-display overlay and Share Preview paths. | Capture products can exclude overlay windows or use unusual APIs. Compatibility must be tested for each product/version. |
| Blur/mosaic content is inferred or reconstructed | Opaque Redact is available; UI describes effect strength. | Blur and mosaic are visual effects, not secure destruction. Redact visually replaces configured pixels but still does not guarantee capture inclusion or placement. Remove secrets from the source whenever possible. |
| Sensitive popover, child window, menu, notification, cursor, or tooltip appears outside a region | Share Preview requests child-window inclusion where supported and shows a preview. | New/transient UI may not fit saved geometry; cursor is intentionally visible. Disable notifications and rehearse. |
| Wrong Share Preview mask set | A mask applies only when the tracker resolves its ID/process/app to the selected source; an opaque fallback is displayed when no mask matches. | A metadata identity can still differ from user intent; Display Pins never apply. Verify the source and every region locally and receiver-side. |
| Frames are retained or transmitted | No capture audio, encoder, file write, network client, analytics, or third-party SDK; generation checks reject late frames and preview clears on stop/error. | OS swap/buffers, screenshots, crash diagnostics, and other capture software are outside complete control. |
| Configuration reveals private context | Local atomic JSON plus one validated recovery snapshot; no app upload; user-controlled export/delete. | Window titles and mask names are plaintext and may exist in `Masks.json.backup` or enter external backup/sync after export. Use non-sensitive names and protect the Mac. |
| Capture authority is broader than expected | macOS 15.2+ uses picker-authorized window identity and one selected stream. macOS 14–15.1 explicitly requests broad Screen Recording access, then requires one exact candidate match. | The legacy TCC grant is broader than the intended stream and persists until revoked. End sharing, revoke it when not needed, and treat a compromised app process as able to exercise granted authority. |
| Malicious local process reads source | None; BlurFollow is not DRM or an OS security boundary. | Any authorized recorder, admin, injected code, or camera can bypass masks. |
| Recipient records or redistributes output | None beyond masking the pixels BlurFollow displays. | Meeting services and participants control received output. Follow their policy and minimize disclosure. |
| Configuration is corrupted or tampered with | Snapshot schema and geometry are validated; a damaged primary can restore a validated backup, `Preview active` remains unavailable pending review, and unrecoverable data stops preview processing. Frame metadata and mask geometry are revalidated before output. | Recovery may restore an older configuration; local same-user malware can alter files or memory. The user must review recovery state. Invalid geometry must invoke the opaque fallback rather than intentionally display raw pixels. |
| Crafted window causes denial of service or resource exhaustion | Capture width and queue depth are bounded; one picker stream. | GPU/WindowServer pressure or extreme display transitions can drop frames. Stop sharing if preview stalls. |
| Official binary is replaced | Xcode Cloud/App Store signing, hardened runtime, SBOM, signed tags, immutable build records, and store receipts. | Users must obtain it from the App Store and verify the publisher; source-control, cloud-signing, or publisher-account compromise remains high impact. |
| Fork impersonates the official product | Apache code/brand separation and trademark policy. | Trademark controls do not technically prevent impersonation; users must verify publisher and signature. |

## Explicit non-goals

BlurFollow does not promise to:

- prevent a source app, macOS, privileged process, camera, or separate recorder
  from accessing the original pixels;
- redact content in a browser-tab share or source-window share performed by
  another app;
- make blur or mosaic cryptographically irreversible;
- obscure content outside configured regions or content that appears between a
  tracking failure and detection;
- stop a participant or provider from recording displayed output;
- bypass DRM/protected-content restrictions or guarantee such content renders;
- meet a particular legal/regulatory standard without deployment-specific
  assessment; or
- make an unofficial build trustworthy merely because its source is available.

## Technical rejection invariants for future changes

The implementation and tests may describe the following rejection rules as
“fail closed.” That term means a particular invalid or stale state must select
an opaque fallback or stop preview processing; it is not a product claim that
BlurFollow protects information or that a meeting app receives the fallback.

A change must trigger threat-model and privacy review if it adds networking,
recording, audio, OCR, cloud sync, crash uploads, analytics, accounts, licensing,
payments, an updater, a helper/XPC service, Accessibility/automation, a private
API, a new persistence location, or a third-party component.

Release tests must demonstrate:

- no audio output is registered and no frame file/network sink exists;
- every mask counted as “applied” has finite, nonempty geometry inside the
  validated content rectangle; malformed, empty, or out-of-bounds geometry
  blocks output instead of being skipped while raw pixels remain visible;
- macOS 14–15.1 broad-permission denial/revocation and macOS 15.2+ picker
  cancellation/denial/end, stream error, and stop do not leave a stale preview
  presented as live;
- blank, suspended, or stopped source status selects the opaque fallback/clear;
  a following idle heartbeat cannot replace that visual delivery or refresh an
  older frame;
- picker completions are bound to the active request and Share Preview view
  lifetime; closing the view, stopping, cancelling, or starting another request
  invalidates older callbacks so they cannot begin capture later;
- picker ownership is token-scoped: a busy request returns a localized failure,
  one view cannot cancel another view's active request, and the picker slot is
  released only when the owning callback resolves;
- every Share Preview entry point presents permission, restart-required, ambiguous
  selection, and picker failures to the user instead of silently doing nothing;
- a corrupt primary snapshot restores only a validated backup, keeps
  `Preview active` unavailable until acknowledged, and never silently looks
  like a normal empty setup;
- a late queued callback cannot restore a cleared frame;
- each processed frame and UI delivery is bound to the current mask-configuration
  revision, so deleting, disabling, or replacing the last applicable mask
  cannot allow a frame produced with the prior mask set to reappear;
- `Preview active` requires a current-generation, nonblocked frame and at
  least one mask actually applied to validated geometry; an opaque fallback,
  stale frame, or merely matched record is never labeled `Preview active`;
- the emitted value of a `nil` → error persistence/recovery transition during
  capture immediately gives the processor no applicable regions, selects the
  opaque fallback, and invalidates `Preview active`, rather than rereading stale
  store state or waiting for another mask edit/source frame;
- masks follow observed move/resize geometry and switch visibly to
  Last-position cover on tracking loss;
- ambiguous rebind never silently claims the intended window without a usable
  warning/verification path;
- all sharing modes explain their actual capture boundary; and
- the exact shipped artifact matches its App Store record, SBOM, source commit,
  and immutable Xcode Cloud build.

Security reports follow [../SECURITY.md](../SECURITY.md). Compatibility and
manual cases are in [COMPATIBILITY.md](COMPATIBILITY.md).
