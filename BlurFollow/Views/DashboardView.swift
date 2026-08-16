import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var selector: RegionSelectionCoordinator
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var sharePreview: SharePreviewSession
    @Environment(\.openWindow) private var openWindow

    @State private var transientMessage: String?
    @State private var isPreparingSharePicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                actionGrid
                sharePreviewCard
                recentMasks
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusPill(
                    title: dashboardStatus.title,
                    state: dashboardStatus.state
                )
                Spacer()
                if let transientMessage {
                    Text(transientMessage)
                        .font(.caption)
                        .foregroundStyle(BlurFollowTheme.coral)
                }
            }
            Text("Blur that follows your window.")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(BlurFollowTheme.ink)
            Text("Place a blur on the display, or let it follow a selected window as you move and resize it.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 720, alignment: .leading)
        }
    }

    private var dashboardStatus: (title: String, state: TrackingState) {
        guard store.recoveryIssue == nil else { return (String(localized: "Review masks"), .unavailable) }
        guard store.masksEnabled else { return (String(localized: "Masks paused"), .unavailable) }
        let enabled = store.regions.filter(\.isEnabled)
        guard !enabled.isEmpty else { return (String(localized: "No masks"), .unavailable) }
        let states = enabled.map { store.trackingStates[$0.id] }
        if states.allSatisfy({ $0 == .positionKnown }) {
            return (String(localized: "Positions found"), .positionKnown)
        }
        if states.contains(where: { $0 == .reconnecting }) {
            return (String(localized: "Finding window"), .reconnecting)
        }
        return (String(localized: "Check placement"), .unavailable)
    }

    private var actionGrid: some View {
        HStack(spacing: 16) {
            ActionCard(
                title: String(localized: "Display Pin"),
                detail: String(localized: "Keep a mask at one place on a display."),
                icon: "display",
                tint: BlurFollowTheme.iris,
                action: addDisplayPin
            )
            ActionCard(
                title: String(localized: "Window Pin"),
                detail: String(localized: "Keep the selected area aligned as its window moves."),
                icon: "macwindow.badge.plus",
                tint: BlurFollowTheme.cyan,
                action: addWindowPin
            )
            .disabled(picker.isPicking)
        }
    }

    private var sharePreviewCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(BlurFollowTheme.ink)
                        .frame(width: 64, height: 64)
                    Image(systemName: "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(BlurFollowTheme.cyan)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("Share Preview")
                        .font(.title3.weight(.bold))
                    Text("Apply matching Window Pins to a separate preview, then check it before selecting it in your meeting app.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: startSharePreview) {
                    Label(
                        sharePreview.isRunning
                            ? String(localized: "Change Source")
                            : String(localized: "Open Share Preview"),
                        systemImage: "play.rectangle.on.rectangle"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(BlurFollowTheme.ink)
                .disabled(store.recoveryIssue != nil || picker.isPicking || isPreparingSharePicker)
            }
        }
    }

    @ViewBuilder
    private var recentMasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Masks")
                    .font(.headline)
                Spacer()
                Text(String.localizedStringWithFormat(
                    String(localized: "Total: %lld"),
                    Int64(store.regions.count)
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if store.regions.isEmpty {
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: "viewfinder")
                            .font(.title)
                            .foregroundStyle(BlurFollowTheme.iris)
                        VStack(alignment: .leading) {
                            Text("No masks yet")
                                .font(.headline)
                            Text("Create a Display Pin without granting any permission.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(store.regions.prefix(3)) { region in
                    CompactMaskRow(region: region)
                }
            }
        }
    }

    private func addDisplayPin() {
        selector.select(on: NSScreen.screens.map(\.frame)) { rect in
            guard let rect, let screen = NSScreen.bestMatch(for: rect) else { return }
            let region = MaskRegion(
                name: String.localizedStringWithFormat(
                    String(localized: "Display Mask %lld"),
                    Int64(store.regions.filter { $0.mode == .display }.count + 1)
                ),
                mode: .display,
                normalizedRect: UnitRect(rect: rect, in: screen.frame),
                displayIdentifier: screen.blurFollowIdentifier,
                style: .frost
            )
            store.add(region)
        }
    }

    private func addWindowPin() {
        picker.pickWindow { result in
            guard case .success(let selection) = result else {
                if case .failure(let error) = result, case .cancelled = error { return }
                if case .failure(let error) = result {
                    transientMessage = error.localizedDescription
                }
                return
            }
            let windowFrame = selection.candidate.appKitFrame
            selector.select(on: [windowFrame]) { rect in
                guard let rect else { return }
                let region = MaskRegion(
                    name: String.localizedStringWithFormat(
                        String(localized: "%@ Mask"),
                        selection.candidate.applicationName
                    ),
                    mode: .window,
                    normalizedRect: UnitRect(rect: rect, in: windowFrame),
                    windowAnchor: selection.candidate.anchor,
                    style: .frost
                )
                tracker.bind(selection.candidate, to: region.id)
                store.add(region)
            }
        }
    }

    private func startSharePreview() {
        guard !picker.isPicking, !isPreparingSharePicker else { return }
        isPreparingSharePicker = true
        Task {
            // Apple's picker allows one unassociated selection at a time. Stop the current output
            // first so source switching cannot exceed that limit; cancellation leaves the preview covered.
            if sharePreview.isRunning { await sharePreview.stop() }
            let acceptedRequest = picker.pickWindow { result in
                switch result {
                case .success(let selection):
                    // Show the transition immediately. Capture startup can take noticeable time,
                    // and waiting for it before opening the window made the button feel stuck.
                    openWindow(id: "share-preview")
                    NSApp.activate(ignoringOtherApps: true)
                    Task {
                        await sharePreview.start(selection)
                        isPreparingSharePicker = false
                    }
                case .failure(let error):
                    isPreparingSharePicker = false
                    if case .cancelled = error { return }
                    transientMessage = error.localizedDescription
                }
            }
            if acceptedRequest == nil { isPreparingSharePicker = false }
        }
    }
}

private struct ActionCard: View {
    let title: String
    let detail: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 15))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(tint)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CompactMaskRow: View {
    @EnvironmentObject private var store: MaskStore
    let region: MaskRegion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: region.mode.systemImage)
                .foregroundStyle(region.mode == .window ? BlurFollowTheme.cyan : BlurFollowTheme.iris)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(region.name).font(.subheadline.weight(.semibold))
                Text(String.localizedStringWithFormat(
                    String(localized: "%@ · %@"),
                    region.mode.title,
                    region.style.title
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(title: maskStatus.title, state: maskStatus.state)
        }
        .padding(14)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
    }

    private var maskStatus: (title: String, state: TrackingState) {
        guard region.isEnabled else { return (String(localized: "Off"), .unavailable) }
        guard let state = store.trackingStates[region.id] else {
            return (String(localized: "Checking position"), .unavailable)
        }
        if state == .positionKnown {
            let title = region.mode == .window ? String(localized: "Following") : String(localized: "Placed")
            return (title, state)
        }
        return (state.title, state)
    }
}
