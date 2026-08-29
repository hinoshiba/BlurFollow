import SwiftUI

struct ShareGuideView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var permission: ScreenCapturePermission
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var sharePreview: SharePreviewSession
    @EnvironmentObject private var textFollow: TextFollowCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var pickerMessage: String?
    @State private var isPreparingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Share Guide")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Choose a preview path and check every mask position before presenting.")
                        .foregroundStyle(.secondary)
                }

                placementCard
                sharingModes
                permissionCard
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private var placementCard: some View {
        GlassCard {
            HStack(spacing: 18) {
                Image(systemName: placementIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(placementColor)
                    .frame(width: 58, height: 58)
                    .background(placementColor.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(placementTitle)
                        .font(.title3.weight(.bold))
                    Text(placementDetail)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var sharingModes: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you sharing?")
                .font(.headline)

            ShareModeRow(
                icon: "display",
                title: String(localized: "Entire Display"),
                detail: String(localized: "Overlays can appear in many full-display shares. Confirm them in the meeting preview."),
                status: String(localized: "Check meeting preview"),
                color: BlurFollowTheme.cyan
            )
            ShareModeRow(
                icon: "macwindow",
                title: String(localized: "One App or Window"),
                detail: String(localized: "Other-app overlays are usually excluded. Use BlurFollow Share Preview and inspect the result."),
                status: String(localized: "Use Share Preview"),
                color: BlurFollowTheme.iris
            )
            ShareModeRow(
                icon: "rectangle.on.rectangle.slash",
                title: String(localized: "Browser Tab"),
                detail: String(localized: "A tab share does not include desktop overlays. Select the browser window in Share Preview."),
                status: String(localized: "Switch sharing method"),
                color: BlurFollowTheme.amber
            )

            Button {
                guard !picker.isPicking, !isPreparingPicker else { return }
                isPreparingPicker = true
                Task {
                    if sharePreview.isRunning { await sharePreview.stop() }
                    picker.pickWindow { result in
                        switch result {
                        case .success(let selection):
                            pickerMessage = nil
                            Task {
                                await sharePreview.start(selection)
                                openWindow(id: "share-preview")
                            }
                        case .failure(let error):
                            if case .cancelled = error { return }
                            pickerMessage = error.localizedDescription
                        }
                    }
                    isPreparingPicker = false
                }
            } label: {
                Label("Open Share Preview", systemImage: "play.rectangle.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(BlurFollowTheme.ink)
            .disabled(store.recoveryIssue != nil || picker.isPicking || isPreparingPicker)
            if let pickerMessage {
                Label(pickerMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(BlurFollowTheme.coral)
            }
        }
    }

    private var permissionCard: some View {
        GlassCard {
            HStack(spacing: 15) {
                Image(systemName: captureAccessIcon)
                    .font(.title2)
                    .foregroundStyle(captureAccessColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Capture Access")
                        .font(.headline)
                    Text(captureAccessDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if permission.shouldOfferSystemSettings {
                    Button("Open Settings") { permission.openSystemSettings() }
                } else if #available(macOS 15.2, *) {
                    Text("Requested per selection")
                        .foregroundStyle(.secondary)
                } else if permission.isAuthorized {
                    Text("Broad access allowed").foregroundStyle(BlurFollowTheme.mint)
                } else {
                    Text("Requested when needed")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var captureAccessDetail: String {
        if #available(macOS 15.2, *) {
            return String(localized: "Apple's system picker grants access to the window you choose. Frames stay on this Mac and are never saved.")
        }
        return String(localized: "macOS 14 through 15.1 needs Screen Recording access to identify a selected window. Frames remain local and are never saved.")
    }

    private var captureAccessIcon: String {
        if permission.shouldOfferSystemSettings { return "exclamationmark.circle.fill" }
        if #available(macOS 15.2, *) { return "hand.raised.fill" }
        return permission.isAuthorized ? "checkmark.circle.fill" : "record.circle"
    }

    private var captureAccessColor: Color {
        if permission.shouldOfferSystemSettings { return BlurFollowTheme.amber }
        if #available(macOS 15.2, *) { return BlurFollowTheme.iris }
        return permission.isAuthorized ? BlurFollowTheme.mint : BlurFollowTheme.iris
    }

    private var enabledMasks: [MaskRegion] { store.regions.filter(\.isEnabled) }
    private var enabledTextRules: [TextFollowRule] { store.textRules.filter(\.isEnabled) }
    private var textRulesNeedingAttention: Int {
        enabledTextRules.filter {
            let state = textFollow.state(for: $0.id)
            return state != .following && state != .noMatches
        }.count
    }
    private var unavailableCount: Int {
        enabledMasks.filter { store.trackingStates[$0.id] == .unavailable }.count
    }
    private var reconnectingCount: Int {
        enabledMasks.filter { store.trackingStates[$0.id] == .reconnecting }.count
    }
    private var unverifiedCount: Int {
        enabledMasks.filter { store.trackingStates[$0.id] == nil }.count
    }
    private var positionsLocated: Bool {
        store.recoveryIssue == nil && store.masksEnabled
            && (!enabledMasks.isEmpty || !enabledTextRules.isEmpty)
            && unavailableCount == 0 && reconnectingCount == 0 && unverifiedCount == 0
            && textRulesNeedingAttention == 0
    }

    private var placementIcon: String { positionsLocated ? "scope" : "questionmark.circle" }
    private var placementColor: Color { positionsLocated ? BlurFollowTheme.cyan : BlurFollowTheme.amber }
    private var placementTitle: String { positionsLocated ? String(localized: "Mask positions found") : String(localized: "Check mask positions") }
    private var placementDetail: String {
        if store.recoveryIssue != nil { return String(localized: "Review saved masks and their positions before presenting.") }
        if !store.masksEnabled { return String(localized: "Masks are paused.") }
        if enabledMasks.isEmpty && enabledTextRules.isEmpty {
            return String(localized: "Add at least one manual mask or Text Follow rule, then inspect the result.")
        }
        if textRulesNeedingAttention > 0 {
            let format = textRulesNeedingAttention == 1
                ? String(localized: "%lld Text Follow rule needs reconnection or a completed scan.")
                : String(localized: "%lld Text Follow rules need reconnection or a completed scan.")
            return String.localizedStringWithFormat(format, Int64(textRulesNeedingAttention))
        }
        if unavailableCount > 0 {
            let format = unavailableCount == 1
                ? String(localized: "%lld mask position is unavailable. Select its window again and check the result.")
                : String(localized: "%lld mask positions are unavailable. Select their windows again and check the result.")
            return String.localizedStringWithFormat(
                format,
                Int64(unavailableCount)
            )
        }
        if reconnectingCount > 0 {
            let format = reconnectingCount == 1
                ? String(localized: "%lld mask is finding its window. The optional cover stays only at the last position.")
                : String(localized: "%lld masks are finding their windows. The optional cover stays only at the last position.")
            return String.localizedStringWithFormat(
                format,
                Int64(reconnectingCount)
            )
        }
        if unverifiedCount > 0 {
            let format = unverifiedCount == 1
                ? String(localized: "%lld mask position has not been checked yet.")
                : String(localized: "%lld mask positions have not been checked yet.")
            return String.localizedStringWithFormat(
                format,
                Int64(unverifiedCount)
            )
        }
        return String(localized: "All enabled manual mask positions and Text Follow scans are active. Inspect the visible result and meeting preview.")
    }
}

private struct ShareModeRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(color.opacity(0.11), in: Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 14))
    }
}
