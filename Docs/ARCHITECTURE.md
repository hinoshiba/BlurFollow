# BlurFollow Architecture

> Status: architecture of the 0.2.0 implementation<br>
> Platform: macOS 14.0+, Swift tools 5.10, SwiftUI, AppKit, ScreenCaptureKit, Vision, Core Image

## 1. System goal and boundary

BlurFollow places visual masks in two coordinate spaces:

- **Display Pin:** a normalized rectangle inside one display.
- **Window Pin:** a normalized rectangle inside one selected application window.

It also has a separate semantic tracking path:

- **Text Follow (Beta):** exact, prefix, contains, or regular-expression rules are evaluated
  against text blocks recognized in one picker-selected window. Every block
  matched by one saved rule gets a transient Mosaic overlay; the detected
  rectangles are never persisted as `MaskRegion` values.

“Beta” is a user-facing product-maturity label. It does not change or weaken the
capture, fail-closed, persistence, privacy, or verification contract.

The normal mask is rendered by a separate floating AppKit panel. A full-display capture can include that panel, but a single-window capture or browser-tab capture takes content from the source application and excludes another app's overlay.

Share Preview handles that boundary by capturing one user-selected window,
compositing matching Window Pins plus completed Text Follow results for that same
source into each frame, and showing the result in a normal BlurFollow window.

    Display sharing
      Source apps + BlurFollow overlay panels
                    |
                    v
              Meeting application

    Single-window / tab workflow
      Selected source window
                    |
             ScreenCaptureKit
                    |
      Window Pin + Text Follow composition
                    |
          BlurFollow Share Preview
                    |
              Meeting application

BlurFollow is a visual aid, not a security control. A frame being available, a window position being known, or a mask being composited does not prove that the intended information is hidden. The user must inspect Share Preview and the meeting application's preview before every share.

## 2. Module boundaries

The names below describe the post-rename architecture. Source paths should be kept aligned with the generated Xcode project.

| Layer | Main responsibilities |
|---|---|
| App composition | Dependency construction, main window, Share Preview window, menu bar, Settings |
| Domain | MaskRegion, TextFollowRule, TextPatternMatcher, UnitRect, WindowAnchor, TrackingState |
| Persistence | Main-actor store, validation, atomic JSON write, backup recovery, export of saved definitions only |
| Permissions | Screen Recording status and System Settings links |
| Content picker | Apple picker presentation and selected-window identity |
| Window tracking | CGWindow metadata snapshots, identity continuity, coordinate conversion |
| Overlay | Floating panels, frame updates, AppKit rendering |
| Text recognition | Picker-scoped ScreenCaptureKit streams, on-device Vision OCR, transient match geometry, and separate Mosaic panels |
| Share Preview | Single-window capture, Window Pin and completed Text Follow resolution, fail-closed frame validation, Core Image composition, preview lifecycle |
| UI | Onboarding, Dashboard, Masks, Share Guide, Settings, Share Preview |
| Commerce | StoreKit product loading, verified entitlement/grandfather checks, purchase/restore, and independent free creation limits (10 Display, 5 Window, 2 Text Follow (Beta) rules) |
| Engagement | Local-only neutral review-prompt eligibility after repeated successful Share Preview checks |

The implementation should use product-neutral type names such as SharePreviewSession, SharePreviewCompositor, MaskOverlayPanel, and BlurFollowTheme. User-facing state terms and internal state names should not imply that a technical condition certifies the content.

## 3. Coordinate systems

### Normalized mask rectangle

Each mask stores a UnitRect:

    x = (selection.minX - container.minX) / container.width
    y = (selection.minY - container.minY) / container.height
    width = selection.width / container.width
    height = selection.height / container.height

The rectangle is clamped to 0...1 and requires positive finite dimensions.

To render:

    rect.x = container.minX + unit.x * container.width
    rect.y = container.minY + unit.y * container.height
    rect.width = unit.width * container.width
    rect.height = unit.height * container.height

For Display Pin, the container is NSScreen.frame. For Window Pin, it is the current tracked window frame. Resizing a window therefore scales mask position and size by the same proportions. This is geometric tracking, not semantic element tracking.

### Quartz to AppKit conversion

CGWindow metadata uses Quartz coordinates with a top-left origin. AppKit uses a bottom-left origin. Conversion reflects the Quartz Y coordinate around the reference display space:

    appKitY = referenceMaxY - quartzY - quartzHeight

The implementation currently uses the main display reference expected by the tested standard arrangements. Different display origins, vertically stacked displays, mixed scale factors, and main-display changes require integration tests before release. Geometry is never used as evidence that two windows have the same identity.

### Share Preview pixels

Window Pin rectangles and transient Text Follow rectangles are transformed from
normalized selected-window coordinates into the captured content rect. The
processor validates:

- finite scale and bounds
- non-empty content rect
- non-empty intersection after clipping
- more than one output pixel in width and height
- current source generation and mask revision

Coordinates are resolved against the captured content, not the visible BlurFollow preview size.

## 4. Data model

### MaskRegion

Persisted fields include:

- stable UUID and user label
- mode: display or window
- normalized rectangle
- style: frost, mosaic, or redact
- effect strength, granularity, tint, border visibility, and corner radius
- enabled flag
- display UUID or WindowAnchor

### WindowAnchor

WindowAnchor stores:

- session window ID
- process ID for continuity checks
- bundle ID, with application name fallback
- saved window title
- initial Quartz frame

Window ID and process ID are not stable across process restarts or window recreation. They are continuity evidence only while the source remains alive.

### TrackingState

Recommended state names:

- tracking / positionKnown
- reconnecting
- needsReview
- unavailable

The former content-certifying label must not be used. positionKnown means only that current geometry is available.

### TextFollowRule and detected text geometry

`TextFollowRule` persists a stable UUID and label, exact/prefix/contains/regex mode,
case-sensitive pattern, WindowAnchor, Mosaic appearance and padding, enabled
state, and creation date. One saved rule consumes one plan slot even when it
matches many text blocks in a frame.

Recognized strings, capture buffers, and current rectangles are runtime state.
They are not written to the snapshot or exported. A successful match produces
zero or more normalized rectangles inside the captured content. Contains is a
case-sensitive substring search, but every mode retains the entire matching
Vision observation rather than substring geometry. All matching observations
are retained; multiple contains or regex hits in one recognized block still
produce one block overlay. Runtime generations prevent results from an
older frame, rule revision, or capture from restoring stale panels.

Regex execution is bounded with ICU progress callbacks and one absolute 50 ms
deadline shared by every rule, block, and candidate in an OCR frame. Exceeding
that deadline fails the scan, clears transient placements, and keeps a relevant
Share Preview source fully covered; it is never published as a completed
zero-match frame.

## 5. Overlay runtime

### Display Pin path

1. Resolve the saved display UUID.
2. Convert UnitRect into the current NSScreen frame.
3. Create or update a borderless, nonactivating mask panel.
4. Render Frost, Mosaic, or Redact.
5. Hide the panel if the display no longer exists.

### Window Pin path

1. Poll on-screen layer-0 windows at approximately 60 Hz, batching the required window IDs.
2. Resolve the current source identity.
3. Convert the CGWindow frame to AppKit coordinates.
4. Convert UnitRect into the current window frame.
5. Update the mask panel and tracking state.

Panels are normally click-through, have no shadow, and join all Spaces and full-screen auxiliary windows. Move mode is initiated in the main app and temporarily makes only the selected mask panel draggable.

The initial Window Pin range selector is also a nonactivating panel. It accepts the first drag while the selected source application remains active, so the BlurFollow main window cannot rise over the content being marked. Completing or cancelling the range selection restores the initiating BlurFollow window; a successful creation also opens the Masks editor.

### Identity continuity and reconnect

For a bound window, continuity requires:

- same live window ID
- same process
- layer 0
- same bundle ID, or the saved application-name fallback

Within that live binding, a changed title and geometry down to one point remain
valid because the window ID/process tuple is continuous. A persisted anchor has
no such process-lifetime proof, so it still requires its saved title; automatic
rebind candidates also require normal picker-sized geometry.

If continuity breaks, the implementation does not silently accept a recycled window ID. Automatic rebind is attempted only when the saved application and title produce exactly one eligible on-screen candidate. Zero or multiple candidates yield no binding and are retried as the window set changes. If the exact persisted ID still exists but its saved title differs, it remains unavailable instead of moving to a different title-matching window, and can recover if the title returns. A positively rejected process/layer/application identity is held unavailable for the rest of the process until an explicit picker selection binds it again; later metadata cannot resurrect it automatically.

The Masks screen provides Reconnect, which opens Apple's picker. On selection, WindowAnchor is updated and explicitly rebound while UnitRect is retained. Retaining UnitRect is convenient, but the content layout may differ; the user must inspect and adjust the mask.

Chrome title changes, same-title windows, untitled windows, hidden windows, and process restarts can prevent automatic rebind. The app does not claim persistent semantic identity across recreated windows.

### Last-position cover

If tracking metadata becomes unavailable and the setting is enabled, the overlay coordinator replaces the small masks with an opaque cover over the most recent in-memory window frame. If the current session has no tracked frame, it can fall back to the saved anchor frame captured when the Window Pin was created.

If the source is known to be off-screen or in another Space, the panel is hidden to avoid covering unrelated content in the current Space. If neither an in-memory frame nor a saved anchor frame exists, there is no position to cover.

Last-position cover is a visual fallback with strict limits:

- it covers the latest location available to the app, not a predicted current location
- after relaunch, the available fallback may be the older frame saved when the Window Pin was created
- it cannot run without an in-memory or saved anchor frame
- it does not know whether the hidden information moved inside the source
- it does not validate the output selected by a meeting app

### Text Follow (Beta) path

Text Follow is deliberately not another `PinMode` and does not alter the
Window Pin geometry contract:

1. The user defines and validates a case-sensitive exact, prefix, contains, or
   regular-expression rule. Contains searches anywhere within the recognized
   block string.
2. Apple's content-sharing picker authorizes one selected window and supplies
   an `SCContentFilter`.
3. ScreenCaptureKit supplies damage-aware, video-only frames from the selected
   source at up to 15 Hz with child windows excluded. Cursor and audio are
   disabled. Text Follow requests the best independent-window source resolution
   and uses a bounded surface of at most 3840 × 2160 pixels. If a selected window
   grows materially after connection, the stream raises its output resolution
   without accepting a frame from the undersized surface as authoritative.
   Every reported/malformed change is checked against an exact, transient
   content-pixel fingerprint, so unchanged browser redraw reports do not restart
   Vision. After a real change, empty-dirty complete frames are hashed until the
   pixels settle, and a one-second exact audit also self-heals after an omitted
   damage notification. Only the newest pending changed frame matters.
4. Vision Revision 3 recognizes text locally at accurate quality. Japanese and
   English remain enabled, and automatic language detection is applied to every
   observed block. Literal rules that identify one script only prioritize that
   language in the enabled order; they do not force a single primary model because
   the literal can appear inside a block written mostly in the other language.
   Mixed-script rules, regular expressions, and script-free patterns use the
   person's preferred-language order. If a candidate
   block matches the rule, the entire recognized block bounds are retained. All
   matching observations in the frame are returned; current match count never
   affects the plan limit. A successful result superseded by newer pixels may
   update only the provisional desktop rectangles while runtime state remains
   scanning; it never qualifies as a completed Share Preview result.
5. Capture-content pixels are converted to normalized content rectangles, then
   projected into the current AppKit frame resolved through `WindowTracker`.
6. A separate coordinator maintains one source-window-sized, click-through
   Mosaic panel per active rule, reusing child effect views for every current
   match and removing views or panels superseded by navigation, disabling,
   deletion, invalid capture state, or a newer generation.

The stream observes changes inside the selected window, so navigation and
scrolling can replace match geometry without editing a saved mask. OCR is
probabilistic and asynchronous: it can miss, misread, lag, or briefly retain a
previous result. Status text and match counts describe observed runtime state;
they do not certify that sensitive content is covered.

Picker-scoped capture authorization is not treated as a persistent credential.
After app relaunch, saved Text Follow rules can require Reconnect before a
stream is active. Rules sharing a live source should reuse capture/OCR work
where practical, and the implementation must not persist recognized text just
to reconstruct a session.

The UI therefore says “Last-position cover” and “Reconnect and check position,” never that this state certifies the share.

### Effect rendering

Normal overlay panels use:

- Frost: NSVisualEffectView material plus independently controlled effect strength, a public Core Image background-filter granularity, foreground tint, and border
- Mosaic: a public Core Image `CIPixellate` background filter that transforms the
  actual backdrop, plus independently controlled cell-size granularity, tint,
  and border; if the filter cannot be created, an opaque grid is drawn as a
  fail-closed fallback instead of leaving readable backdrop pixels
- Redact: an opaque rounded rectangle

Frost and Mosaic reduce visual readability but do not erase or transform the underlying source application data. Redact draws an opaque rectangle in BlurFollow's own output path. None of these styles detects incorrect placement.

The desktop overlay and Share Preview use the same saved appearance controls but different renderers and coordinate spaces: AppKit points for the overlay and capture pixels for the preview. Their output is intentionally not claimed to be pixel-identical, especially on Retina displays or downscaled capture. Every sharing path must be checked independently.

Text Follow has a persisted, safety-first scan-cover preference. It defaults to
enabled, including migration from older snapshots. While a reported changed
frame is being recognized, while the runtime is connecting, failed, or otherwise
lacks a coherent current result, and after a coherent OCR result contains zero
matches, enabled mode replaces the prior desktop per-match placements with a
square-cornered full-window Mosaic while its current/last trusted window frame
remains locatable. A transient
WindowServer metadata failure uses that last trusted frame; confirmed source
loss, another Space, or identity mismatch hides the old-position panel instead
of later resurrecting it after another uncertain lookup. Disabled mode keeps
the latest successfully completed nonempty placements and conservatively adds
nonempty provisional geometry while newer pixels are still being recognized.
No superseded result can remove a retained mask. This avoids a
full-window flash but can leave moved or newly appearing matches visible until a
newer OCR result; a coherent current zero-match result can remove those desktop
placements. Share Preview continues to fail closed for every unready or
in-flight state regardless of this preference. For a coherent completed
zero-match result only, it uses a full cover when the preference is enabled and
can render the current source when the preference is disabled.

## 6. Share Preview

### Source selection

The user selects exactly one window through SCContentSharingPicker.

- macOS 15.2+: includedWindows provides the selected-window identity under per-selection authorization.
- macOS 14–15.1: identity resolution depends on broad SCShareableContent enumeration and therefore requires Screen Recording access before the picker flow continues.

The session records source window ID, process ID, application identity, source generation, and current mask revision.

### Matching Window Pins and Text Follow results

A Window Pin is eligible only when:

- it is enabled
- its source window is currently resolved
- resolved window ID and process ID match the selected source
- application identity matches
- normalized geometry validates

Same-application candidates are resolved with the tracker's three-state result.
When both records have bundle identifiers they are compared directly; otherwise
their application names are the legacy fallback. Missing cross-representation
evidence is treated as uncertain rather than unrelated, so it reaches the
fail-closed cover path instead of being removed by the candidate prefilter.
An exact resolved window/process is included; a positively resolved different
window/process is unrelated. An uncertain or unavailable candidate is not
silently omitted: Share Preview stays fully covered until its membership can be
resolved or the saved pin is reconnected/removed.

Saved title assists non-ambiguous reconnect. Title alone is never enough to apply a mask to a source frame. Display Pins are not inputs to Share Preview.

Text Follow's desktop panels remain external overlays and are not captured as
windows. Instead, Share Preview resolves the transient normalized rectangles for
every enabled rule relevant to the picker-selected source and creates temporary
Mosaic `MaskRegion` inputs with that rule's current appearance. A rule is ready
only when its picker-authorized runtime identity matches the source, its latest
scan is complete, and that completion has a comparable WindowServer display
time:

- `following` requires one or more finite current rectangles;
- `noMatches` requires an empty rectangle set and is a valid completed scan;
- unconnected/reconnect-required, connecting, scanning, source-unavailable,
  failed, missing-runtime, stale-identity, disabled-by-global-state, and torn
  state/rectangle pairs require a full cover.

Disabled or unrelated rules are not inputs. A plausible stale rule for the same
application/title is treated as relevant but unsafe rather than silently
omitted. This conservative identity test is not persistent capture authority;
the user must reconnect the rule through Apple's picker.

### Frame processing

For each valid ScreenCaptureKit sample:

1. Validate sample status and attachments.
2. Resolve the content pixel rect, classify damage metadata, and compare an
   exact transient fingerprint whenever pixels are reported changed or metadata
   cannot be classified. Identical pixels do not advance the damage barrier.
3. Compare WindowServer display times in both directions: every relevant rule's
   oldest completion must reach the latest Preview damage, and Preview's latest
   observed time must reach the newest relevant OCR completion.
4. Snapshot eligible Window Pins, completed Text Follow rectangles, readiness
   state, and the current revision.
5. Transform each UnitRect into capture pixels.
6. Apply Frost, Mosaic, and Redact effects to the cumulative image.
7. Recheck source generation, session object identity, combined mask/Text Follow
   revision, persistence issue state, and the dynamic-content time barrier.
8. Deliver the frame on the main actor.

The first complete source frame requests a fresh Text Follow frame for the same
picker-authorized source. Complete and idle samples advance the Preview-side
time. Once both time bounds are satisfied, the newest retained complete source
sample can be rerendered even when a static page produces no later damage. A
cached sample is never rebased if its display time predates damage already
observed by the barrier.

Effects are ordered Frost, then Mosaic, then Redact. Redact is last so later effects do not reconstruct source pixels inside an opaque region.

### Paused preview behavior

The processor does not present a normal source frame when any required condition cannot be evaluated. It emits a full opaque frame or clears the preview for conditions including:

- neither an eligible Window Pin nor a relevant completed Text Follow rule
- a same-application Window Pin whose selected-source membership is uncertain
  or unavailable
- a relevant enabled Text Follow rule is unconnected, reconnect-required,
  connecting, scanning, source-unavailable, failed, missing, stale, or internally
  inconsistent
- invalid or subpixel mask
- invalid sample metadata
- changed preview content newer than the oldest completed Text Follow frame,
  Preview observation older than the newest completed Text Follow frame, or
  changed content whose damage/display-time metadata cannot be ordered safely
- blank, suspended, or stopped source status
- unusable or clipped content rect
- image-generation failure
- stale source generation or mask revision
- unresolved persistence recovery issue
- frame freshness timeout

A completed Text Follow scan with zero matches is coherent but does not prove
that OCR found every intended string. With the strict safety-cover preference
enabled, it selects the full cover. With the preference disabled, it is a
renderable configuration even though it produces no dynamic regions, so the
current source frame can be displayed with zero Text Follow mosaics (plus any
Window Pins). If there is neither an eligible Window Pin nor a relevant completed
Text Follow rule, the historical empty-configuration cover still applies.

For a transition into any blocked state, the session increments the combined
revision, cancels pending render work, clears the previously presented image
immediately, and renders a full opaque cover when frame extent is available.
This behavior reduces the chance of showing an unexpected raw or stale frame
inside BlurFollow, but it is not a content guarantee. The visible state is
“Preview paused,” accompanied by the reason and a recovery action.

An idle heartbeat indicates that ScreenCaptureKit considers the source unchanged. The last composited frame may remain during current idle heartbeats. If neither a valid frame nor idle heartbeat arrives for 1.25 seconds, the preview is cleared.

### User confirmation

Technical readiness and user confirmation are separate:

1. **Preview active:** capture is running, a current composited frame exists, and no current processor issue is reported.
2. **Check every mask:** the UI asks the user to inspect source, mask bounds,
   scroll position, Text Follow matches, and the absence of separately captured
   child windows and menus.
3. **Confirmed by user:** an explicit per-session acknowledgement enables the “Share this preview” instruction.

Changing source, changing a Window Pin or Text Follow revision/state,
reconnecting a window, receiving a persistence issue, pausing capture, or losing
frame freshness invalidates the acknowledgement.

The meeting application's own picker and preview remain outside this state machine. The user repeats the check there.

### Lifecycle

    User opens Share Preview
            |
       Apple picker
            |
       Source selected
            |
       Session starts
            |
      Current frame composed
            |
      Preview active
            |
      User checks every mask
            |
      User confirms current session
            |
      Meeting app shares BlurFollow Share Preview

Stop or window close performs all of the following:

- invalidate picker request generation
- cancel a picker still in progress
- stop SCStream
- cancel freshness monitoring
- clear the displayed frame
- reset current user confirmation

Picker callbacks and capture startup recheck generation so a closed, invisible preview does not restart capture.

## 7. Persistence and data boundary

The store is a main-actor ObservableObject. Each valid change becomes a pretty-printed JSON snapshot written atomically. If the existing primary file validates, its prior snapshot is promoted to the backup before the new primary is written.

Persisted structure:

    regions
      id, name, mode, unitRect
      style, strength, granularity, tint, border, cornerRadius, enabled
      displayID
      windowAnchor
        windowID, processID, bundleID
        applicationName, windowTitle
        initialQuartzFrame
    textRules
      id, name, matchMode, pattern
      strength, granularity, tint, border, cornerRadius, padding, enabled
      windowAnchor
    coverLastPositionEnabled
    onboardingComplete

If primary decoding or validation fails, a validated backup may be restored. A recovery issue remains visible until the user reviews all masks and rules. If neither file can be restored, definitions must be recreated. “Delete All Masks and Rules” writes empty collections to the primary and removes the backup.

No screen pixels or recognized strings are included in persistence or export.
Mask/rule names, Text Follow patterns, application names, bundle IDs, and
window titles can themselves contain personal or internal information. Debug
reports must remove or review those values before publication.

Share Preview keeps only the latest in-memory source sample needed to release a
static frame after OCR catches up and the latest `CGImage` needed by its
layer-backed pixel surface. It does not encode frames to a file, capture audio,
or send frames over the network. Source-sample caches are cleared on source or
invalid-capture changes. A same-source semantic or mask update preserves only
the newest short-lived complete sample, rebases it onto the current revision,
and rerenders it only while source activity and both display-time bounds remain
current. Once another application captures the BlurFollow window, that
application's processing is outside the BlurFollow boundary.

See [PRIVACY.md](../PRIVACY.md) for the user-facing data statement.

## 8. Concurrency and performance

- UI, store, overlay coordinator, window tracker, and Share Preview session are main-actor isolated.
- Window metadata polling follows the overlay refresh at about 60 Hz. In steady state, the required window IDs are batched into one WindowServer description request per refresh; uncertain identity can additionally trigger the existing all-window reconnect lookup.
- ScreenCaptureKit sample handling uses dedicated serial queues. Text Follow
  observes source damage at up to 15 Hz, compares every reported/unclassified
  change, immediate post-change settling frames, and a one-second recovery audit
  with an optimized transient SHA-256
  fingerprint, skips identical pixels, keeps at most current/in-flight work plus
  the newest pending changed frame, and evaluates all rules for a shared source
  from one OCR result where practical. Its capture surface is bounded at 3840 ×
  2160 and increases only when a resize or DPI transition would otherwise lower
  source detail materially. This ceiling avoids deterministic loss of available
  source pixels but is not an accuracy guarantee: Vision recall can vary
  non-monotonically with input dimensions and text layout. Share Preview applies
  the same per-stream equality check. Neither path persists pixels or digests.
- Core Image context is reused by the frame processor.
- Preview pixels are assigned directly to a CALayer; frame delivery does not publish an observable SwiftUI image.
- Delivery is gated by source generation, session object identity, combined
  Window Pin/Text Follow revision, and current issue state.
- The first Preview source frame requests a fresh OCR frame. Timestamp-only OCR
  completion plus a sufficiently new complete/idle Preview time can rerender
  the one cached current source sample so a static window does not remain
  covered waiting for another damage callback.
- Current Share Preview target is 30 fps and at most 2560 × 1440 pixels.

Release measurements should cover 10 / 25 / 50 manual masks, multiple Text
Follow rules and simultaneous matches, mixed-DPI displays, 2560 px Share
Preview, 1440p/2160p Text Follow, resize-driven resolution updates, and 60-minute
sessions. Record CPU, GPU, memory, energy, dropped frames, OCR latency, frame
delay, and freshness clears. OCR release gates should use the same captured
pixel snapshots at every tested scale and record block recall, false positives,
coverage, and segmentation changes; independently re-rendered browser viewports
are not a valid substitute for a same-frame scale comparison. Multi-scale or
tiled recognition remains experimental until it improves that corpus without
crossing the recognition watchdog budget.

## 9. Permissions and sandbox

### Screen Recording

- Display Pin does not require Screen Recording access.
- macOS 15.2+ uses the system picker selection for Window Pin, Text Follow, and Share Preview.
- macOS 14–15.1 requires broad Screen Recording access for selected-window identity resolution and Text Follow frame processing, plus an app restart after approval.

Denial stops the affected flow and shows the reason, System Settings link, and restart instruction where applicable.

### App Sandbox

Release settings include:

- App Sandbox enabled
- user-selected read/write file access for JSON export
- Hardened Runtime

The application does not request Full Disk Access, Accessibility, camera, microphone, contacts, or network client access for its current feature set.

The checked-in project, generated project, built app signature, and archive entitlements must be compared during every release.

## 10. Limits and misuse boundaries

The official Mac App Store target applies independent plan boundaries only
when a saved definition is added: 10 Display Pins, 5 Window Pins, and 2 Text
Follow rules are free. A verified Non-Consumable, or a verified pre-0.2.0 app
transaction, removes all app-imposed creation limits. `MaskStore.add` and
`addTextRule` are the final atomic checks. One rule always counts once; its
current number of detected blocks never enters the plan usage. Existing masks
and rules are never removed or disabled when StoreKit state changes. Source
builds compile without `BLURFOLLOW_APP_STORE` and retain unlimited access. See
[MONETIZATION.md](MONETIZATION.md).

BlurFollow does not address:

- a mask placed over the wrong content
- page layout, zoom, scroll, or toolbar changes
- selecting the original source instead of Share Preview
- a meeting application showing or recording a different target
- another capture tool with different window filtering
- a physical camera or another device
- malicious modification of the app or operating system
- reconstruction or inference from a weak Frost / Mosaic result
- OCR false positives, false negatives, stale detections, or recognition delay
- DRM and OS capture restrictions
- identity ambiguity after source recreation

Accordingly, product UI and documentation describe position following, preview composition, and user verification. They do not claim leak prevention, secrecy, certification, or universal compatibility.

For coordinated vulnerability reporting and security engineering scope, see [SECURITY.md](../SECURITY.md) and [THREAT_MODEL.md](THREAT_MODEL.md).

## 11. Test strategy

### Automated tests

- UnitRect clamp, normalization, and display/window transforms
- Quartz/AppKit conversion for representative arrangements
- Window identity continuity and ambiguous rebind rejection
- atomic persistence, validated backup, restore warning, backup deletion
- export contents and error handling
- Frost / Mosaic / Redact composition
- invalid, clipped, and subpixel mask handling
- effect ordering and overlap
- source generation and mask revision stale-frame rejection
- Text Follow Share Preview resolution for following, completed zero-match with
  the strict safety preference both enabled and disabled,
  reconnect-required, connecting, scanning, unavailable, failed, stale-identity,
  and inconsistent state/rectangle pairs
- immediate previous-frame clear and full-cover delivery on every dynamic-rule
  transition into a blocked state
- paused preview frame generation
- lifecycle cancellation and state reset where testable

### Required manual matrix

- macOS 14.0, 14.2, 15.0, 15.1, 15.2 and current release
- fresh Screen Recording consent, allow, deny, revoke, restart
- Intel and Apple Silicon
- Retina / non-Retina / mixed scale factors
- displays left, right, above, below; main-display switch
- Spaces, full-screen, Stage Manager, sleep / wake
- Chrome, Safari, Firefox, Slack, Terminal, Xcode
- Zoom, Google Meet, Teams
- full display, single window, browser tab
- source close / recreate / rename / minimize
- child-window exclusion shared by Text Follow OCR and Share Preview; menu,
  sheet, popover, notification, and DRM content boundaries
- VoiceOver, keyboard only, Reduce Motion, increased contrast

The acceptance check always includes visual inspection in both BlurFollow Share Preview and the meeting application's preview.

## 12. Build and release evidence

Development checks:

    swift test
    ./build.sh
    ./Scripts/check-release.sh

When project.yml changes:

    xcodegen generate
    open BlurFollow.xcodeproj

Before distribution:

- clean archive in the supported Xcode version
- inspect signed entitlements
- validate Privacy Manifest and data statement
- run the full permission and sharing matrix
- review LICENSE, NOTICE, third-party notices, trademark policy, and brand provenance
- push an immutable semantic-version tag and preserve the Xcode Cloud record
- complete Xcode Cloud and App Store Connect validation

Passing unit tests and local app-bundle checks is not evidence that every meeting workflow renders as expected.

## 13. Evolution constraints

Future semantic anchoring, automatic sensitive-data detection, team policy, telemetry, or network features require a new data-flow and permission review before implementation.

Any state-machine change must preserve this distinction:

    Technical condition observed
              is not
    User has checked the intended content

That distinction is part of the architecture, not only product copy.
