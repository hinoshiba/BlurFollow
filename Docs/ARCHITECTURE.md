# BlurFollow Architecture

> Status: architecture of the 0.1.0 implementation<br>
> Platform: macOS 14.0+, Swift tools 5.10, SwiftUI, AppKit, ScreenCaptureKit, Core Image

## 1. System goal and boundary

BlurFollow places visual masks in two coordinate spaces:

- **Display Pin:** a normalized rectangle inside one display.
- **Window Pin:** a normalized rectangle inside one selected application window.

The normal mask is rendered by a separate floating AppKit panel. A full-display capture can include that panel, but a single-window capture or browser-tab capture takes content from the source application and excludes another app's overlay.

Share Preview handles that boundary by capturing one user-selected window, compositing the matching Window Pins into each frame, and showing the result in a normal BlurFollow window.

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
          Window Pin composition
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
| Domain | MaskRegion, UnitRect, WindowAnchor, TrackingState |
| Persistence | Main-actor store, validation, atomic JSON write, backup recovery, export |
| Permissions | Screen Recording status and System Settings links |
| Content picker | Apple picker presentation and selected-window identity |
| Window tracking | CGWindow metadata snapshots, identity continuity, coordinate conversion |
| Overlay | Floating panels, frame updates, AppKit rendering |
| Share Preview | Single-window capture, frame validation, Core Image composition, preview lifecycle |
| UI | Onboarding, Dashboard, Masks, Share Guide, Settings, Share Preview |

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

Window Pin rectangles are transformed from normalized window coordinates into the captured content rect. The processor validates:

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
- intensity and corner radius
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

### Identity continuity and reconnect

For a bound window, continuity requires:

- same live window ID
- same process
- layer 0
- same bundle ID, or the saved application-name fallback

If continuity breaks, the implementation does not silently accept a recycled window ID. Automatic rebind is attempted only when the saved application and title produce exactly one eligible on-screen candidate. Zero or multiple candidates yield no binding.

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

The UI therefore says “Last-position cover” and “Reconnect and check position,” never that this state certifies the share.

### Effect rendering

Normal overlay panels use:

- Frost: NSVisualEffectView material plus a strength-controlled public Core Image content filter and foreground tint
- Mosaic: a strength-controlled cell grid
- Redact: an opaque rounded rectangle

Frost and Mosaic reduce visual readability but do not erase or transform the underlying source application data. Redact draws an opaque rectangle in BlurFollow's own output path. None of these styles detects incorrect placement.

## 6. Share Preview

### Source selection

The user selects exactly one window through SCContentSharingPicker.

- macOS 15.2+: includedWindows provides the selected-window identity under per-selection authorization.
- macOS 14–15.1: identity resolution depends on broad SCShareableContent enumeration and therefore requires Screen Recording access before the picker flow continues.

The session records source window ID, process ID, application identity, source generation, and current mask revision.

### Matching Window Pins

A Window Pin is eligible only when:

- it is enabled
- its source window is currently resolved
- resolved window ID and process ID match the selected source
- application identity matches
- normalized geometry validates

Saved title assists non-ambiguous reconnect. Title alone is never enough to apply a mask to a source frame. Display Pins are not inputs to Share Preview.

### Frame processing

For each valid ScreenCaptureKit sample:

1. Validate sample status and attachments.
2. Resolve the content pixel rect.
3. Snapshot eligible Window Pins and the current revision.
4. Transform each UnitRect into capture pixels.
5. Apply Frost, Mosaic, and Redact effects to the cumulative image.
6. Recheck source generation, session object identity, mask revision, and persistence issue state.
7. Deliver the frame on the main actor.

Effects are ordered Frost, then Mosaic, then Redact. Redact is last so later effects do not reconstruct source pixels inside an opaque region.

### Paused preview behavior

The processor does not present a normal source frame when any required condition cannot be evaluated. It emits a full opaque frame or clears the preview for conditions including:

- no eligible Window Pin
- invalid or subpixel mask
- invalid sample metadata
- blank, suspended, or stopped source status
- unusable or clipped content rect
- image-generation failure
- stale source generation or mask revision
- unresolved persistence recovery issue
- frame freshness timeout

This behavior reduces the chance of showing an unexpected raw frame inside BlurFollow, but it is not a content guarantee. The visible state is “Preview paused,” accompanied by the reason and a recovery action.

An idle heartbeat indicates that ScreenCaptureKit considers the source unchanged. The last composited frame may remain during current idle heartbeats. If neither a valid frame nor idle heartbeat arrives for 1.25 seconds, the preview is cleared.

### User confirmation

Technical readiness and user confirmation are separate:

1. **Preview active:** capture is running, a current composited frame exists, and no current processor issue is reported.
2. **Check every mask:** the UI asks the user to inspect source, mask bounds, scroll position, child windows, and menus.
3. **Confirmed by user:** an explicit per-session acknowledgement enables the “Share this preview” instruction.

Changing source, changing mask revision, reconnecting a window, receiving a persistence issue, pausing capture, or losing frame freshness invalidates the acknowledgement.

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

    schemaVersion
    masks
      id, name, mode, unitRect
      style, intensity, cornerRadius, enabled
      displayID
      windowAnchor
        windowID, processID, bundleID
        applicationName, windowTitle
        initialQuartzFrame
    coverLastPositionEnabled
    onboardingComplete

If primary decoding or validation fails, a validated backup may be restored. A recovery issue remains visible until the user reviews all masks. If neither file can be restored, masks must be recreated. “Delete All Masks” writes an empty primary and removes the backup.

No screen pixels are included in persistence or export. Mask names, application names, bundle IDs, and window titles can themselves contain personal or internal information. Debug reports must remove or review those values before publication.

Share Preview keeps only the latest CGImage needed by its layer-backed pixel surface. It does not encode frames to a file, capture audio, or send frames over the network. Once another application captures the BlurFollow window, that application's processing is outside the BlurFollow boundary.

See [PRIVACY.md](../PRIVACY.md) for the user-facing data statement.

## 8. Concurrency and performance

- UI, store, overlay coordinator, window tracker, and Share Preview session are main-actor isolated.
- Window metadata polling follows the overlay refresh at about 60 Hz. In steady state, the required window IDs are batched into one WindowServer description request per refresh; uncertain identity can additionally trigger the existing all-window reconnect lookup.
- ScreenCaptureKit sample handling uses a dedicated serial user-interactive queue.
- Core Image context is reused by the frame processor.
- Preview pixels are assigned directly to a CALayer; frame delivery does not publish an observable SwiftUI image.
- Delivery is gated by source generation, session object identity, mask revision, and current issue state.
- Current Share Preview target is 30 fps and at most 2560 × 1440 pixels.

Release measurements should cover 10 / 25 / 50 masks, mixed-DPI displays, 2560 px Share Preview, and 60-minute sessions. Record CPU, GPU, memory, energy, dropped frames, frame delay, and freshness clears.

## 9. Permissions and sandbox

### Screen Recording

- Display Pin does not require Screen Recording access.
- macOS 15.2+ uses the system picker selection for Window Pin and Share Preview.
- macOS 14–15.1 requires broad Screen Recording access for selected-window identity resolution and an app restart after approval.

Denial stops the affected flow and shows the reason, System Settings link, and restart instruction where applicable.

### App Sandbox

Release settings include:

- App Sandbox enabled
- user-selected read/write file access for JSON export
- Hardened Runtime

The application does not request Full Disk Access, Accessibility, camera, microphone, contacts, or network client access for its current feature set.

The checked-in project, generated project, built app signature, and archive entitlements must be compared during every release.

## 10. Limits and misuse boundaries

BlurFollow does not address:

- a mask placed over the wrong content
- page layout, zoom, scroll, or toolbar changes
- selecting the original source instead of Share Preview
- a meeting application showing or recording a different target
- another capture tool with different window filtering
- a physical camera or another device
- malicious modification of the app or operating system
- reconstruction or inference from a weak Frost / Mosaic result
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
- child window, menu, sheet, DRM content
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
