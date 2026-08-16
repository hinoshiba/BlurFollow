import AppKit
import Combine

@MainActor
final class OverlayCoordinator: ObservableObject {
    @Published private(set) var editingRegionID: UUID?

    private let store: MaskStore
    private let tracker: WindowTracker
    private var panels: [UUID: MaskOverlayPanel] = [:]
    private var lastKnownWindowFrames: [UUID: CGRect] = [:]
    private var timer: Timer?
    private var escapeMonitor: Any?
    private weak var keyWindowBeforeEditing: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    init(store: MaskStore, tracker: WindowTracker) {
        self.store = store
        self.tracker = tracker

        store.$regions
            .combineLatest(store.$masksEnabled, store.$coverLastPositionEnabled)
            .sink { [weak self] regions, masksEnabled, coverLastPositionEnabled in
                self?.refresh(
                    regions: regions,
                    masksEnabled: masksEnabled,
                    coverLastPositionEnabled: coverLastPositionEnabled
                )
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.endEditing() }
            .store(in: &cancellables)
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            // This timer is installed only on RunLoop.main. Running synchronously avoids a queue of
            // MainActor tasks building up behind pointer or window-drag events and then "catching up".
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        endEditing()
        panels.values.forEach { $0.hideIfNeeded() }
    }

    func beginEditing(regionID: UUID) {
        guard store.masksEnabled,
              let region = store.regions.first(where: { $0.id == regionID }),
              region.isEnabled else { return }

        endEditing()
        keyWindowBeforeEditing = NSApp.keyWindow
        editingRegionID = regionID
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in self?.endEditing() }
            return nil
        }
        refresh()
    }

    func endEditing() {
        finishEditing(restoreInitialFrame: true)
    }

    private func finishEditing(restoreInitialFrame: Bool) {
        guard editingRegionID != nil || escapeMonitor != nil else { return }
        editingRegionID = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panels.values.forEach {
            $0.setEditing(false, restoreInitialFrame: restoreInitialFrame)
        }
        if let keyWindowBeforeEditing, keyWindowBeforeEditing.canBecomeKey {
            keyWindowBeforeEditing.makeKey()
        }
        keyWindowBeforeEditing = nil
    }

    func refresh() {
        refresh(
            regions: store.regions,
            masksEnabled: store.masksEnabled,
            coverLastPositionEnabled: store.coverLastPositionEnabled
        )
    }

    private func refresh(
        regions: [MaskRegion],
        masksEnabled: Bool,
        coverLastPositionEnabled: Bool
    ) {
        let desiredIDs = Set(regions.map(\.id))
        if let editingRegionID, !desiredIDs.contains(editingRegionID) {
            endEditing()
        }
        for (id, panel) in panels where !desiredIDs.contains(id) {
            panel.close()
            panels[id] = nil
            lastKnownWindowFrames[id] = nil
            tracker.unbind(regionID: id)
        }

        guard masksEnabled else {
            endEditing()
            panels.values.forEach { $0.hideIfNeeded() }
            return
        }

        // Query each distinct WindowServer ID at most once per tick, even when several masks follow
        // the same source window. Display Pins do not need WindowServer metadata at all.
        let trackedWindowFrames = tracker.frames(for: regions.filter {
            $0.isEnabled && $0.mode == .window
        })

        for region in regions {
            guard region.isEnabled else {
                if editingRegionID == region.id { endEditing() }
                panels[region.id]?.hideIfNeeded()
                continue
            }

            let panel = panels[region.id] ?? {
                let panel = MaskOverlayPanel(region: region)
                panel.onMoveEnded = { [weak self] frame in
                    self?.commitMove(regionID: region.id, proposedFrame: frame)
                }
                panels[region.id] = panel
                return panel
            }()

            switch region.mode {
            case .display:
                guard
                    let screen = NSScreen.blurFollowScreen(identifier: region.displayIdentifier),
                    screen.blurFollowIdentifier == region.displayIdentifier || region.displayIdentifier == nil
                else {
                    if editingRegionID == region.id { endEditing() }
                    panel.hideIfNeeded()
                    store.setTrackingState(.unavailable, for: region.id)
                    continue
                }
                panel.update(
                    region: region,
                    frame: region.normalizedRect.rect(in: screen.frame),
                    isEditing: editingRegionID == region.id,
                    movementBounds: screen.frame
                )
                panel.showIfNeeded()
                store.setTrackingState(.positionKnown, for: region.id)

            case .window:
                if let tracked = trackedWindowFrames[region.id] {
                    if tracked.isOnScreen {
                        let frame = region.normalizedRect.rect(in: tracked.appKitFrame)
                        lastKnownWindowFrames[region.id] = tracked.appKitFrame
                        panel.update(
                            region: region,
                            frame: frame,
                            isEditing: editingRegionID == region.id,
                            movementBounds: tracked.appKitFrame
                        )
                        panel.showIfNeeded()
                        store.setTrackingState(.positionKnown, for: region.id)
                    } else {
                        // The source is minimized or on another Space. Leaving a mask on the
                        // current Space would cover unrelated content.
                        if editingRegionID == region.id { endEditing() }
                        panel.hideIfNeeded()
                        store.setTrackingState(.unavailable, for: region.id)
                    }
                } else if coverLastPositionEnabled,
                          let savedFrame = lastKnownWindowFrames[region.id]
                            ?? region.windowAnchor.map({
                                ScreenCoordinates.appKitRect(fromQuartz: $0.initialFrame.cgRect)
                            }) {
                    // Tracking has paused. Cover the entire last-known source-window position
                    // instead of leaving a small stale mask. This does not locate a moved window.
                    if editingRegionID == region.id { endEditing() }
                    panel.update(region: region, frame: savedFrame.insetBy(dx: -2, dy: -2), forceRedact: true)
                    panel.showIfNeeded()
                    store.setTrackingState(.reconnecting, for: region.id)
                } else {
                    if editingRegionID == region.id { endEditing() }
                    panel.hideIfNeeded()
                    store.setTrackingState(.unavailable, for: region.id)
                }
            }
        }
    }

    private func commitMove(regionID: UUID, proposedFrame: CGRect) {
        guard editingRegionID == regionID,
              var region = store.regions.first(where: { $0.id == regionID }),
              let container = currentContainer(for: region),
              let normalizedRect = MaskDragGeometry.normalizedRect(
                for: proposedFrame,
                inside: container
              ) else {
            endEditing()
            refresh()
            return
        }

        // End input capture before publishing the persisted geometry. The synchronous store
        // refresh must never leave the overlay interactive after the drag completes.
        finishEditing(restoreInitialFrame: false)
        region.normalizedRect = normalizedRect
        store.update(region)
    }

    private func currentContainer(for region: MaskRegion) -> CGRect? {
        switch region.mode {
        case .display:
            guard
                let screen = NSScreen.blurFollowScreen(identifier: region.displayIdentifier),
                screen.blurFollowIdentifier == region.displayIdentifier || region.displayIdentifier == nil
            else { return nil }
            return screen.frame
        case .window:
            guard let tracked = tracker.frame(for: region), tracked.isOnScreen else { return nil }
            return tracked.appKitFrame
        }
    }
}
