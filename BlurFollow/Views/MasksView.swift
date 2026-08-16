import SwiftUI

struct MasksView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var overlay: OverlayCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Masks")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Adjust the look and tracking behavior of every blur area.")
                        .foregroundStyle(.secondary)
                }

                if store.regions.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "No Masks",
                            systemImage: "rectangle.dashed",
                            description: Text("Create one from Home by dragging over an area to blur.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else {
                    ForEach(store.regions) { region in
                        MaskEditorCard(region: region)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .onDisappear {
            overlay.endEditing()
            store.flushPersistence()
        }
    }
}

private struct MaskEditorCard: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var tracker: WindowTracker
    @EnvironmentObject private var picker: ContentPickerService
    @EnvironmentObject private var overlay: OverlayCoordinator
    @State private var reconnectMessage: String?
    let region: MaskRegion

    private func binding<Value>(_ keyPath: WritableKeyPath<MaskRegion, Value>) -> Binding<Value> {
        Binding(
            get: { store.regions.first(where: { $0.id == region.id })?[keyPath: keyPath] ?? region[keyPath: keyPath] },
            set: { newValue in
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current[keyPath: keyPath] = newValue
                store.update(current)
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { store.regions.first(where: { $0.id == region.id })?.strength ?? region.strength },
            set: { newValue in
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current.strength = newValue
                store.updateLive(current)
            }
        )
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 13) {
                    Image(systemName: region.mode.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(
                            (region.mode == .window ? BlurFollowTheme.cyan : BlurFollowTheme.iris).gradient,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("Mask Name", text: binding(\.name))
                            .textFieldStyle(.plain)
                            .font(.headline)
                        Text(targetDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        title: maskStatus.title,
                        state: maskStatus.state
                    )
                    Toggle("", isOn: binding(\.isEnabled))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                }

                Divider()

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mask Style")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Mask Style", selection: binding(\.style)) {
                            ForEach(MaskStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        Text(region.style.detail)
                            .font(.caption)
                            .foregroundStyle(region.style == .frost ? BlurFollowTheme.amber : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strength")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Slider(
                            value: strengthBinding,
                            in: 0.2...1,
                            onEditingChanged: { isEditing in
                                if !isEditing { store.flushPersistence() }
                            }
                        )
                            .tint(BlurFollowTheme.iris)
                        Text(String.localizedStringWithFormat(
                            String(localized: "%lld%%"),
                            Int64(region.strength * 100)
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 170)
                }

                HStack {
                    if region.mode == .window {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(
                                String.localizedStringWithFormat(
                                    String(localized: "Moves and resizes with %@"),
                                    region.windowAnchor?.applicationName ?? String(localized: "selected window")
                                ),
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let reconnectMessage {
                                Text(reconnectMessage)
                                    .font(.caption)
                                    .foregroundStyle(BlurFollowTheme.coral)
                            }
                        }
                    } else {
                        Label("Pinned to this display", systemImage: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if isMoving {
                            overlay.endEditing()
                        } else {
                            overlay.beginEditing(regionID: region.id)
                        }
                    } label: {
                        Label(
                            isMoving ? String(localized: "Cancel Move") : String(localized: "Move…"),
                            systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                        )
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isMoving && !canMove)
                    if region.mode == .window {
                        Button("Reconnect…", action: reconnectWindow)
                            .buttonStyle(.borderless)
                            .disabled(picker.isPicking)
                    }
                    Button(role: .destructive) {
                        store.remove(id: region.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }

                if isMoving {
                    Label(
                        "Drag the mask itself to move it. Release to save; press Esc to cancel.",
                        systemImage: "hand.draw"
                    )
                    .font(.caption)
                    .foregroundStyle(BlurFollowTheme.iris)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var isMoving: Bool {
        overlay.editingRegionID == region.id
    }

    private var canMove: Bool {
        store.masksEnabled && region.isEnabled && maskStatus.state == .positionKnown
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

    private var targetDescription: String {
        switch region.mode {
        case .display:
            return String(localized: "Display Pin")
        case .window:
            let app = region.windowAnchor?.applicationName ?? String(localized: "Unknown App")
            return String.localizedStringWithFormat(
                String(localized: "%@ · %@"),
                app,
                String(localized: "Window-following")
            )
        }
    }

    private func reconnectWindow() {
        reconnectMessage = nil
        picker.pickWindow { result in
            switch result {
            case .success(let selection):
                guard var current = store.regions.first(where: { $0.id == region.id }) else { return }
                current.windowAnchor = selection.candidate.anchor
                tracker.bind(selection.candidate, to: current.id)
                store.update(current)
            case .failure(let error):
                if case .cancelled = error { return }
                reconnectMessage = error.localizedDescription
            }
        }
    }
}
