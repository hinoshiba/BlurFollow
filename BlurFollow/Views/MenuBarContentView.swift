import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var sharePreview: SharePreviewSession
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
        Section("Masks") {
            if store.regions.isEmpty {
                Text("No masks yet")
            } else {
                ForEach(store.regions) { region in
                    Toggle(isOn: enabledBinding(for: region.id)) {
                        Label(maskMenuTitle(for: region), systemImage: region.mode.systemImage)
                    }
                    .accessibilityLabel(Text(maskMenuTitle(for: region)))
                    .accessibilityHint("Turns only this mask on or off.")
                }
            }

            Button("Manage Masks…") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .accessibilityHint("Opens the mask management screen.")
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
        let count = store.regions.filter(\.isEnabled).count
        let format = count == 1
            ? String(localized: "%lld active mask")
            : String(localized: "%lld active masks")
        return String.localizedStringWithFormat(format, Int64(count))
    }

    private func enabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.regions.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setEnabled($0, for: id) }
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
}
