import SwiftUI

private enum AppSection: String, CaseIterable, Identifiable {
    case home
    case masks
    case shareGuide
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .masks: return String(localized: "Masks")
        case .shareGuide: return String(localized: "Share Guide")
        case .settings: return String(localized: "Settings")
        }
    }

    var icon: String {
        switch self {
        case .home: return "sparkles.rectangle.stack"
        case .masks: return "rectangle.3.group"
        case .shareGuide: return "list.bullet.rectangle"
        case .settings: return "gearshape"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: MaskStore
    @State private var selection: AppSection? = .home

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                brandHeader
                List(AppSection.allCases, selection: $selection) { section in
                    Label(section.title, systemImage: section.icon)
                        .tag(section)
                        .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)

                maskFooter
            }
            .background(Color.white.opacity(0.52))
            .navigationSplitViewColumnWidth(min: 188, ideal: 210, max: 235)
        } detail: {
            VStack(spacing: 0) {
                if let issue = store.recoveryIssue {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(issue).lineLimit(2)
                        Spacer()
                        Button("Review") { selection = .settings }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BlurFollowTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BlurFollowTheme.amber.opacity(0.88))
                }
                ZStack {
                    BlurFollowTheme.background
                    switch selection ?? .home {
                    case .home: DashboardView()
                    case .masks: MasksView()
                    case .shareGuide: ShareGuideView()
                    case .settings: SettingsView()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                maskToolbarMenu
            }
        }
        .sheet(isPresented: Binding(
            get: { !store.hasCompletedOnboarding },
            set: { _ in }
        )) {
            OnboardingView()
                .environmentObject(store)
                .interactiveDismissDisabled()
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("BlurFollow")
                    .font(.title3.weight(.bold))
                Text("Blur that follows your window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var maskFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Toggle(isOn: $store.masksEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(maskFooterTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(activeMaskCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .tint(BlurFollowTheme.mint)
            .disabled(store.recoveryIssue != nil)
        }
        .padding(16)
    }

    private var maskToolbarMenu: some View {
        Menu {
            Toggle(isOn: $store.masksEnabled) {
                Label("Show Masks", systemImage: store.masksEnabled ? "eye" : "eye.slash")
            }
            .disabled(store.recoveryIssue != nil)

            Text(activeMaskCountText)

            Divider()

            Section("Masks") {
                if store.regions.isEmpty {
                    Text("No masks yet")
                } else {
                    ForEach(store.regions) { region in
                        Toggle(isOn: enabledBinding(for: region.id)) {
                            Label(maskToolbarTitle(for: region), systemImage: region.mode.systemImage)
                        }
                        .accessibilityLabel(Text(region.name))
                        .accessibilityHint("Turns only this mask on or off.")
                    }
                }
            }

            Divider()

            Button {
                selection = .masks
            } label: {
                Label("Manage Masks…", systemImage: "slider.horizontal.3")
            }
            .accessibilityHint("Opens the mask management screen.")
        } label: {
            Label("Mask Controls", systemImage: maskToolbarSystemImage)
        }
        .help("Turn masks on or off individually.")
        .accessibilityLabel("Mask Controls")
        .accessibilityHint("Turn masks on or off individually.")
    }

    private var maskToolbarSystemImage: String {
        guard store.masksEnabled else { return "eye.slash" }
        return store.regions.contains(where: \.isEnabled) ? "eye.fill" : "eye"
    }

    private func enabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.regions.first(where: { $0.id == id })?.isEnabled ?? false },
            set: { store.setEnabled($0, for: id) }
        )
    }

    private func maskToolbarTitle(for region: MaskRegion) -> String {
        String.localizedStringWithFormat(
            String(localized: "%@ · %@"),
            region.name,
            region.mode.title
        )
    }

    private var maskFooterTitle: String {
        guard store.masksEnabled else { return String(localized: "Masks paused") }
        guard store.recoveryIssue == nil else { return String(localized: "Review masks") }
        let enabled = store.regions.filter(\.isEnabled)
        guard !enabled.isEmpty else { return String(localized: "No masks") }
        return enabled.allSatisfy({ store.trackingStates[$0.id] == .positionKnown })
            ? String(localized: "Positions found")
            : String(localized: "Check placement")
    }

    private var activeMaskCountText: String {
        let count = store.regions.filter(\.isEnabled).count
        let format = count == 1
            ? String(localized: "%lld active mask")
            : String(localized: "%lld active masks")
        return String.localizedStringWithFormat(format, Int64(count))
    }
}
