# Threat model

Last reviewed: 2026-08-29<br>
Baseline: BlurFollow 0.2.0 on macOS 14 and later

BlurFollow is intended to make a visual effect follow a saved window-relative
position or a locally recognized text block through Text Follow (Beta), and to
provide a processed preview the user can check before sharing. “Beta” describes
product maturity only; it does not relax any technical integrity objective,
fail-closed behavior, privacy boundary, or release test in this model.
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
3. Evaluate each Text Follow rule against on-device OCR, display every matching
   recognized block from the current generation, and remove superseded results
   without treating OCR as proof that all intended content was found.
4. Mark Share Preview as `Preview active` only after enabled Window Pins and all
   relevant enabled Text Follow rules are coherent for the current selected
   source and combined revision. A completed zero-match scan is coherent but not
   proof of OCR completeness: the default strict safety preference keeps it
   covered, while disabling that preference permits it to render. Every
   unresolved/in-flight/failed/inconsistent relevant rule selects an immediate
   clear and opaque fallback frame regardless of that preference.
5. Minimize capture: user-selected windows, video only, transient processing,
   no intentional frame persistence or app-initiated upload.
6. Represent only observed state: `Following`, `Position known`,
   `Preview active`, or `Last-position cover`. None certifies confidentiality,
   OCR completeness, capture inclusion, correct user selection, or unreadability.
7. Preserve integrity and provenance of official release artifacts.

## Assets

- screen pixels, which may contain credentials, messages, customer data, source
  code, health/financial information, or unreleased work;
- transient OCR output and detected text geometry;
- locally stored mask geometry, mask/rule names, Text Follow match patterns,
  display identifiers, application names, bundle identifiers, window titles,
  IDs, and bounds;
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
identity. A continuously bound tuple may change title or shrink, while a saved
anchor without runtime continuity still requires its saved title. After loss,
it will rebind only when app/title candidates are treated as unambiguous:
exactly one matching visible candidate must remain. Zero or ambiguous candidate
sets are retried. An exact saved ID with a changed title stays unavailable rather
than moving to a different title match. Once process/layer/application identity
is positively rejected, later metadata cannot revive that tracking ID until the
user explicitly reconnects it through the picker.

The overlay is another window. It changes what is visibly composited on the
desktop but does not modify the source application's pixels. A third-party
product that captures only the source app/window or browser tab normally omits
the BlurFollow overlay.

Desktop Mosaic transforms the actual compositor backdrop with the public Core
Image `CIPixellate` filter. If the filter cannot be created, the overlay uses an
opaque grid rather than intentionally leaving readable source pixels. This is a
render-path fallback, not a claim that mosaic is irreversible redaction.

### Text Follow (Beta) path

```text
Apple picker ──> selected-window SCContentFilter ──> ScreenCaptureKit frames
                                                       │
                                                       v
                                              on-device Vision OCR
                                                       │
saved exact/prefix/contains/regex rule ────────────────┤
                                                       v
                                       transient normalized block rectangles
                                                       │
WindowTracker current frame ──────────────────────────┤
                                                       v
                                          separate Mosaic NSPanel overlays
```

Text Follow captures only a window the user selected. It disables audio and
cursor capture, performs Vision recognition in process, compares recognized
blocks with a saved case-sensitive exact, prefix, contains, or regular-expression
rule, and retains transient geometry for every matching observation. Contains
searches inside the recognized string but still covers the entire Vision block,
not only the matching substring. A rule may match many blocks but remains one
saved definition and one plan item. Pixels and recognized candidate strings are not
persisted or exported. Child windows are excluded from its selected-source
stream. The capture requests the best independent-window source resolution in
a surface bounded at 3840 × 2160 pixels. A material resize/DPI increase retires
the old OCR generation until the configured surface size is observed, and a
post-change empty-dirty frames are audited until their exact pixels settle, and a
one-second exact-pixel audit can recover from an omitted damage notification.
The larger surface preserves available input pixels but does not prove better
recognition: Vision detection and block segmentation can change non-monotonically
with input dimensions, layout, font size, and contrast.

The source app, ScreenCaptureKit, Vision recognition, capture-to-window
coordinate conversion, and WindowServer position metadata are separate trust
boundaries. OCR can return false positives or false negatives, and an older
recognition result can be wrong after navigation unless generation and mailbox
ordering reject it. BlurFollow covers the entire recognized block after any
rule match to reduce character-boundary error, but that does not prove every
intended string was recognized. Text Follow panels are desktop overlays and are
normally omitted by another app's single-window or browser-tab capture. Share
Preview does not capture those panels; it independently consumes their current
normalized rule geometry and draws completed matches into its own frame.

### Share Preview path

```text
macOS 14–15.1 ──> broad Screen Recording permission ──┐
                                                     ├──> Apple system content picker
macOS 15.2+ ──> picker-scoped selection ─────────────┘              │
                                                                  v
                                                            SCContentFilter
                                                                  │
source window ──> ScreenCaptureKit frames ──> Core Image mask processor
                                              ▲                 ▲
                             matching Window Pins   completed Text Follow geometry
                                              │
                                    BlurFollow Share Preview window
                                              │
                             user selects that window in meeting app
                                              │
                                conferencing/recording provider
```

Share Preview requests one window with child windows and cursor pixels excluded,
disables audio, processes frames locally, and assigns the latest
`CGImage` directly to a layer-backed preview. It applies enabled **Window Pins**
only when the tracker resolves them to the exact selected window identity. A
same-application candidate that is uncertain or unavailable keeps the entire
preview covered; only a positively resolved different window/process is omitted.
Bundle IDs are compared when both records have one; otherwise application name
is the legacy fallback, and incomparable metadata remains a fail-closed
candidate. It
also applies every current rectangle from connected, enabled Text Follow rules
relevant to the same source after their scan completes. A completed scan with
zero matches is coherent but is not evidence that Vision found every intended
string. The default strict safety preference keeps that result fully covered;
when the preference is disabled, it may display the current source frame without
a dynamic Mosaic.

If any relevant enabled Text Follow rule is unconnected/reconnect-required,
connecting, scanning, source-unavailable, failed, missing its runtime, stale for
a plausible same source, or inconsistent with its rectangle set, Share Preview
increments its combined revision, clears the previously displayed image
immediately, and replaces the complete preview with an opaque fallback. The
same fail-closed path applies to invalid mask or capture state. If there is
neither an eligible Window Pin nor a relevant completed Text Follow rule, the
empty-configuration fallback remains. Display Pins do not apply to Share
Preview. This describes BlurFollow's own window, not what any capture product
receives. The user must inspect both it and the receiver-side preview.

Text Follow and Share Preview use separate ScreenCaptureKit streams. To keep a
new Share Preview frame from outrunning older OCR geometry, both paths retain
WindowServer display times and the preview remains fully covered whenever its
latest changed frame is newer than the oldest completed scan among relevant
rules, or its latest observed time is older than the newest completed scan. The
first Preview source frame requests a fresh scan for the same selected source;
complete and idle samples can then prove that a short-lived cached source frame
is current enough to rerender, but a cache older than already observed damage is
rejected. Each stream compares an exact transient SHA fingerprint when damage is
reported or dirty-rectangle metadata is missing/malformed. Identical pixels do
not advance the damage barrier; a changed or unavailable fingerprint remains
fail-closed. Missing display time still cannot be ordered safely and keeps the
fallback closed until the preview stream is reset.

The authorization boundary differs by OS version. On macOS 14 through 15.1,
the app requires the broad Screen Recording TCC grant before the picker because
that compatibility path must enumerate windows and resolve one exact geometry
match; denial stops selection, a newly granted permission requires reopening
BlurFollow, and zero or multiple matches fail. On macOS 15.2 and later,
`SCContentFilter.includedWindows` supplies the picker-authorized window identity
and BlurFollow does not proactively request the broad grant.

Frames pass through ScreenCaptureKit and pixel buffers; Text Follow additionally
passes them to Vision, while Share Preview passes them through Core Image and a
`CGImage`. This occurs in process/graphics/system memory. The app has no intended
encoder, recording file, OCR log, or network sink. Stop/error paths clear
preview and detected-geometry state; release tests must guard against queued
late work repopulating either.

### Persistence and release boundary

`MaskStore` atomically writes configuration JSON to Application Support (inside
the container for a sandboxed build) and can retain a validated
`Masks.json.backup` recovery snapshot. A corrupt primary restores only from a
validated backup and prevents `Preview active` pending user review; an
unrecoverable snapshot starts with masking paused. “Delete All Masks and Rules”
writes empty saved-definition lists and removes the recovery copy. It never
intentionally stores a captured frame or recognized string. A user-initiated
export copies configuration, including Text Follow patterns, to a chosen file.

Official source, GitHub CI, Xcode Cloud signing, App Store Connect, and the
user's store receipt form a separate software-supply-chain boundary.

## Actors and assumptions

We consider mistakes by the presenter, ordinary source apps, a misleading or
malfunctioning conferencing app, an untrusted meeting participant, malicious
local software running with user-granted capabilities, a dependency/supply-chain
attacker, and an unauthorized downstream distributor.

We assume macOS public APIs, WindowServer, code signing, TCC, ScreenCaptureKit,
Vision, and Core Image behave as documented; the official build is not already
compromised; the user can see status and preview; and the user controls the Mac.
Compromise of macOS, firmware, the administrator account, or release signing
identity defeats important assumptions.

## Threats, controls, and residual risk

| Threat | Current control | Residual risk / required user action |
| --- | --- | --- |
| User shares the original browser tab or window | Share Guide says separate-app overlays are excluded and offers Share Preview. | BlurFollow cannot change another app's selection. Share the BlurFollow Share Preview window and verify the meeting preview. |
| Window moves or resizes | Window-relative normalized geometry and approximately 60 Hz batched frame tracking. | Mask position can lag or diverge during latency, animation, Mission Control, display reconfiguration, or OS/API failure. Check the receiver-side preview. |
| Text appears, moves, or disappears after navigation | Damage-aware selected-window capture at up to 15 Hz, on-device Vision recognition, current-generation replacement, one overlay for every match, and a default strict safety preference that uses a square full-window desktop cover while recognizing changed content, while capture metadata is transiently uncertain, and after OCR completes with zero matches. The same preference covers a completed zero-match Share Preview result. A two-sided WindowServer display-time barrier keeps Share Preview fully covered until every relevant rule reaches its latest damage and Preview reaches the newest relevant OCR completion; cached Preview pixels older than known damage cannot receive newer OCR geometry. | OCR can miss, misread, or lag; capture and OCR remain asynchronous, and zero matches do not prove absence. Turning off strict safety avoids full-window desktop flashes by retaining old matches during uncertainty and permits a completed zero-match Preview to render, but this leaves moved, newly appearing, or OCR-missed targets more exposed. Confirmed source loss, another Space, or identity mismatch hides the old-position desktop panel rather than guessing a new location. Continuously changing content can keep the enabled desktop cover or Share Preview fallback active. Share Preview remains fail-closed for every unready/in-flight state regardless of the preference. Recheck after every transition and remove secrets from the source whenever possible. |
| One Text Follow pattern appears many times | Every matching OCR block is retained and rendered while one saved rule consumes one plan slot. | Large result sets cost CPU/GPU and may update at different times; count is not proof of completeness. Stop sharing if scanning stalls. |
| Source window disappears | Last-position cover can cover the entire last-known window in opaque Redact mode and marks tracking lost/reconnecting. | It covers only recorded last-known geometry. The source can reappear elsewhere, so the cover is not proof of current placement. Stop sharing on any warning. |
| Rebind chooses the wrong window | ID/process/layer/app continuity first; persisted anchors and later rebind require a saved title match, a changed title on the exact saved ID does not redirect to another window, later rebind requires exactly one visible candidate, and positive process/layer/app rejection stays unavailable until explicit picker reconnection. Zero or ambiguous candidate sets remain eligible for later retry. | A unique metadata match cannot prove semantic identity. Confirm after reopen or document/title change. |
| Overlay is absent from captured output | Product explicitly separates entire-display overlay and Share Preview paths. | Capture products can exclude overlay windows or use unusual APIs. Compatibility must be tested for each product/version. |
| Blur/mosaic content is inferred or reconstructed | Opaque Redact is available; desktop Mosaic transforms the actual backdrop with `CIPixellate` and uses an opaque fallback if the filter is unavailable. | Blur and mosaic are visual effects, not secure destruction. Redact visually replaces configured pixels but still does not guarantee capture inclusion or placement. Remove secrets from the source whenever possible. |
| Sensitive popover, child window, menu, notification, cursor, or tooltip appears outside the selected source boundary | Text Follow OCR and Share Preview both exclude child windows and source-cursor pixels so recognition and composition use the same top-level source boundary. | A separate child window may be absent from both outputs while still visible on the desktop, and a receiver can apply its own cursor-capture behavior. Disable notifications, rehearse, and inspect the exact receiver output. |
| Wrong or incomplete Share Preview mask set | Window Pins require exact tracked identity; an unresolved same-application Window Pin covers rather than silently disappearing, and only a positively resolved other window is omitted. Bundle IDs are compared only when available on both records, with application-name fallback for legacy anchors; incomparable identity remains fail-closed. Completed Text Follow geometry is included for the same source. Every unresolved, in-flight, failed, stale, inconsistent, or regex-timeout dynamic rule clears the old frame and selects a full opaque cover. The default strict preference also covers a completed zero-match result; disabling it permits that coherent result to render. Regex work has one bounded deadline shared across the complete OCR frame. | A stale same-application pin can pause Preview even when it belongs to another window; reconnect or remove it after checking. A completed zero-match OCR result can be a false negative, especially when strict safety is disabled, and metadata identity can still differ from user intent. Display Pins never apply. Verify the source and every region locally and receiver-side. |
| Frames are retained or transmitted | No capture audio, encoder, file write, network client, analytics, or third-party SDK; generation checks reject late frames and preview clears on stop/error. | OS swap/buffers, screenshots, crash diagnostics, and other capture software are outside complete control. |
| Configuration reveals private context | Local atomic JSON plus one validated recovery snapshot; no app upload; user-controlled export/delete. | Window titles, mask/rule names, and exact/prefix/contains/regex patterns are plaintext and may exist in `Masks.json.backup` or enter external backup/sync after export. Avoid literal secrets in patterns where practical and protect the Mac. |
| Capture authority is broader than expected | macOS 15.2+ uses picker-authorized window identity and one selected stream. macOS 14–15.1 explicitly requests broad Screen Recording access, then requires one exact candidate match. | The legacy TCC grant is broader than the intended stream and persists until revoked. End sharing, revoke it when not needed, and treat a compromised app process as able to exercise granted authority. |
| Malicious local process reads source | None; BlurFollow is not DRM or an OS security boundary. | Any authorized recorder, admin, injected code, or camera can bypass masks. |
| Recipient records or redistributes output | None beyond masking the pixels BlurFollow displays. | Meeting services and participants control received output. Follow their policy and minimize disclosure. |
| Configuration is corrupted or tampered with | Snapshot schema and geometry are validated; a damaged primary can restore a validated backup, `Preview active` remains unavailable pending review, and unrecoverable data stops preview processing. Frame metadata and mask geometry are revalidated before output. | Recovery may restore an older configuration; local same-user malware can alter files or memory. The user must review recovery state. Invalid geometry must invoke the opaque fallback rather than intentionally display raw pixels. |
| Crafted window causes denial of service or resource exhaustion | Capture dimensions (Text Follow at most 3840 × 2160), rate, and queue depth are bounded; Text Follow keeps only current work and the newest pending frame and shares recognition per source where possible. Configuration and first-frame watchdogs retire a stuck resized stream through bounded recovery. | A 4K BGRA surface and Vision working memory remain substantial; OCR, GPU, or WindowServer pressure and extreme display transitions can drop frames. Stop sharing if recognition or preview stalls. |
| Official binary is replaced | Xcode Cloud/App Store signing, hardened runtime, SBOM, signed tags, immutable build records, and store receipts. | Users must obtain it from the App Store and verify the publisher; source-control, cloud-signing, or publisher-account compromise remains high impact. |
| Fork impersonates the official product | Apache code/brand separation and trademark policy. | Trademark controls do not technically prevent impersonation; users must verify publisher and signature. |
| Local plan state is forged or a purchase is refunded | Unlimited access comes only from StoreKit-verified current entitlement, a verified pre-0.2.0 AppTransaction, or the explicit source-build condition. No mutable local Boolean grants paid access. | A modified local/source build can bypass plan logic by design; this is not a security boundary. Existing masks and rules remain available after entitlement loss. |

## Explicit non-goals

BlurFollow does not promise to:

- prevent a source app, macOS, privileged process, camera, or separate recorder
  from accessing the original pixels;
- redact content in a browser-tab share or source-window share performed by
  another app;
- make blur or mosaic cryptographically irreversible;
- obscure content outside configured regions or content that appears between a
  tracking failure and detection;
- recognize every visible string, interpret semantic UI/DOM identity, or update
  with zero latency after navigation;
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

A change must trigger threat-model and privacy review if it adds
developer-operated networking, recording, audio, a new OCR provider/model or
persistence of OCR output, cloud sync, crash uploads, analytics, accounts,
licensing, new payment products or payment providers, an updater, a helper/XPC
service, Accessibility/automation, a private API, a new persistence location,
or a third-party component.

Release tests must demonstrate:

- no audio output is registered and no frame file/network sink exists;
- Text Follow returns every matching observation for one rule while counting
  only the saved rule, rejects stale capture/rule generations, and clears all
  detected panels on disable, delete, blank/suspended/stopped capture, error,
  or disconnect;
- recognized candidate strings and captured Text Follow frames never enter the
  settings snapshot, export, log, analytics, or network path;
- Share Preview composites all completed matches from every connected, enabled
  Text Follow rule relevant to its selected source together with matching Window
  Pins, without capturing the desktop overlay panels themselves;
- an unconnected/reconnect-required, connecting, scanning, source-unavailable,
  failed, missing-runtime, stale-identity, or internally inconsistent relevant
  rule increments the combined revision, clears the prior preview immediately,
  and selects the full opaque fallback; no older frame may return;
- a completed Text Follow scan with an empty rectangle set selects a full cover
  when strict safety is enabled and remains renderable when it is disabled,
  while UI and documentation never treat zero matches as proof of OCR completeness;
- Text Follow OCR and Share Preview both exclude child windows and test the same
  selected-source content boundary;
- desktop Mosaic uses `CIPixellate` to transform the backdrop when available and
  an opaque fallback when unavailable; a readable translucent-grid fallback is
  rejected;
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
- each processed frame and UI delivery is bound to the current combined Window
  Pin/Text Follow revision, so deleting, disabling, reconnecting, rescanning, or
  replacing an applicable definition cannot restore a prior frame;
- `Preview active` requires a current-generation, nonblocked frame and either an
  applied Window Pin or a relevant completed Text Follow rule; the latter may
  have zero matches only when strict safety is disabled, while an opaque
  fallback, stale frame, or unready rule is never labeled `Preview active`;
- the emitted value of a `nil` → error persistence/recovery transition during
  capture immediately gives the processor no applicable regions, selects the
  opaque fallback, and invalidates `Preview active`, rather than rereading stale
  store state or waiting for another mask edit/source frame;
- masks follow observed move/resize geometry and switch visibly to
  Last-position cover on tracking loss;
- ambiguous rebind never silently claims the intended window without a usable
  warning/verification path;
- all sharing modes explain their actual capture boundary;
- the exact shipped artifact matches its App Store record, SBOM, source commit,
  and immutable Xcode Cloud build; and
- StoreKit grants unlimited creation only for a verified matching transaction
  or verified grandfathered app version, while cancellation, pending,
  unverified, refund, and revocation paths never remove existing masks or rules.

Security reports follow [../SECURITY.md](../SECURITY.md). Compatibility and
manual cases are in [COMPATIBILITY.md](COMPATIBILITY.md).
