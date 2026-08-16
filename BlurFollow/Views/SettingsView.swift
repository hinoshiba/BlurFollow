import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var permission: ScreenCapturePermission
    @State private var exportMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Mask behavior and local data controls.")
                        .foregroundStyle(.secondary)
                }

                if let issue = store.recoveryIssue {
                    GlassCard {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(BlurFollowTheme.amber)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Saved data needs review")
                                    .font(.headline)
                                Text(issue)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Inspect every mask first. Continuing only acknowledges the warning; it does not prove the masks are correctly placed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("I reviewed the masks — continue") {
                                    store.acknowledgeRecoveryIssue()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(BlurFollowTheme.amber)
                            }
                            Spacer()
                        }
                    }
                }

                GlassCard {
                    VStack(spacing: 16) {
                        Toggle(isOn: $store.coverLastPositionEnabled) {
                            SettingLabel(
                                icon: "rectangle.on.rectangle.angled",
                                title: String(localized: "Cover Last Position"),
                                detail: String(localized: "If tracking pauses, cover only the last known window position. This cover does not follow a missing window."),
                                color: BlurFollowTheme.amber
                            )
                        }
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                        Divider()
                        Toggle(isOn: $store.masksEnabled) {
                            SettingLabel(
                                icon: "rectangle.inset.filled",
                                title: String(localized: "Show Masks"),
                                detail: String(localized: "Display all enabled Display Pins and Window Pins."),
                                color: BlurFollowTheme.iris
                            )
                        }
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingLabel(
                            icon: permission.isAuthorized ? "checkmark.circle.fill" : "record.circle",
                            title: String(localized: "Capture Access"),
                            detail: captureAccessDetail,
                            color: permission.isAuthorized ? BlurFollowTheme.mint : BlurFollowTheme.amber
                        )
                        HStack {
                            Text(captureAccessStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") { permission.refresh() }
                            Button("Open System Settings") { permission.openSystemSettings() }
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Local Data")
                            .font(.headline)
                        Text("Mask geometry and window identity are stored in Application Support. Screen pixels are never persisted.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Export Mask Settings…") { exportSettings() }
                            Button("Delete All Masks", role: .destructive) { store.removeAll() }
                            Spacer()
                            if let exportMessage {
                                Text(exportMessage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GlassCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(versionLabel)
                                .font(.headline)
                            Text("Open source under Apache-2.0. No third-party runtime SDKs are bundled.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("BlurFollow name and logo are governed by the trademark policy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .background(BlurFollowTheme.background)
    }

    private var captureAccessDetail: String {
        if #available(macOS 15.2, *) {
            return String(localized: "Share Preview uses Apple's per-selection system picker. Frames stay in memory and are never uploaded.")
        }
        return String(localized: "macOS 14 through 15.1 requires Screen Recording access for window identity. Frames stay local.")
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return String.localizedStringWithFormat(String(localized: "BlurFollow %@"), version)
    }

    private var captureAccessStatus: String {
        if #available(macOS 15.2, *) { return String(localized: "Access granted per picker selection") }
        return permission.isAuthorized
            ? String(localized: "Broad access granted")
            : String(localized: "Broad access required")
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "BlurFollow-Masks.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            exportMessage = String(localized: "Exported")
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}

private struct SettingLabel: View {
    let icon: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
