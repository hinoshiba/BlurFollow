import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var sharePreview: SharePreviewSession
    @EnvironmentObject private var textFollow: TextFollowCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open BlurFollow") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Toggle("Show Masks", isOn: $store.masksEnabled)
        Text(activeMaskCountText)
        Divider()
        Section("Manual Masks") {
            if store.regions.isEmpty {
                Text("No manual masks yet")
            } else {
                ForEach(store.regions) { region in
                    Toggle(isOn: enabledBinding(for: region.id)) {
                        Label(maskMenuTitle(for: region), systemImage: region.mode.systemImage)
                    }
                    .accessibilityLabel(Text(maskMenuTitle(for: region)))
                    .accessibilityHint("Turns only this mask on or off.")
                }
            }
        }
        Divider()
        Section("Text Follow Rules (Beta)") {
            if store.textRules.isEmpty {
                Text("No Text Follow rules yet")
            } else {
                ForEach(store.textRules) { rule in
                    Toggle(isOn: textRuleEnabledBinding(for: rule.id)) {
                        Label(textFollowMenuTitle(for: rule), systemImage: "text.viewfinder")
                    }
                    .accessibilityLabel(Text(rule.name))
                    .accessibilityHint("Turns only this Text Follow rule on or off.")
                }
            }

            Button("Manage Masks and Rules…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .accessibilityHint("Opens manual mask and Text Follow management.")
        }
        Divider()
        Button("Open Share Preview") {
            openWindow(id: "share-preview")
            NSApp.activate(ignoringOtherApps: true)
        }
        .disabled(!sharePreview.isRunning)
        Divider()
        Button("Quit BlurFollow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var activeMaskCountText: String {
        String.localizedStringWithFormat(
            String(localized: "Manual %lld · Text Follow %lld active"),
            Int64(store.regions.filter(\.isEnabled).count),
            Int64(store.textRules.filter(\.isEnabled).count)
        )
    }

    private func enabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.regions.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setEnabled($0, for: id) }
        )
    }

    private func textRuleEnabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.textRules.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setTextRuleEnabled($0, for: id) }
        )
    }

    private func maskMenuTitle(for region: MaskRegion) -> String {
        let modeAndState = String.localizedStringWithFormat(
            String(localized: "%@ · %@"),
            region.mode.title,
            maskStatus(for: region)
        )
        return String.localizedStringWithFormat(
            String(localized: "%@ · %@"),
            region.name,
            modeAndState
        )
    }

    private func maskStatus(for region: MaskRegion) -> String {
        guard region.isEnabled else { return String(localized: "Off") }
        guard let state = store.trackingStates[region.id] else {
            return String(localized: "Checking position")
        }
        if state == .positionKnown {
            return region.mode == .window
                ? String(localized: "Following")
                : String(localized: "Placed")
        }
        return state.title
    }

    private func textFollowMenuTitle(for rule: TextFollowRule) -> String {
        let stateAndCount = String.localizedStringWithFormat(
            String(localized: "%@ · %@"),
            textFollow.state(for: rule.id).localizedTitle,
            textFollowMatchCountText(textFollow.matchedCount(for: rule.id))
        )
        return String.localizedStringWithFormat(
            String(localized: "%@ · %@"),
            rule.name,
            stateAndCount
        )
    }
}
