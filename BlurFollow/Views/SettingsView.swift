import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: MaskStore
    @EnvironmentObject private var permission: ScreenCapturePermission
    @EnvironmentObject private var purchases: PurchaseManager
    @State private var exportMessage: String?
    @State private var isShowingUnlimitedMasks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Mask behavior, Text Follow, and local data controls.")
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
                                detail: String(localized: "Display all enabled manual masks and Text Follow matches."),
                                color: BlurFollowTheme.iris
                            )
                        }
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                        Divider()
                        Toggle(isOn: $store.textFollowSafetyCoverEnabled) {
                            SettingLabel(
                                icon: "shield.lefthalf.filled",
                                title: String(localized: "Strict Safety: Protect the Whole Window"),
                                detail: String(localized: "While Text Follow is recognizing, window metadata is uncertain, or OCR finds no matches, this protects the current or last trusted window. Turn it off to keep only the last masks and avoid full-window flashes. A confirmed missing or off-screen source hides the old desktop cover; Share Preview remains fail-closed during uncertainty."),
                                color: BlurFollowTheme.amber
                            )
                        }
                        .toggleStyle(.switch)
                        .tint(BlurFollowTheme.mint)
                        .accessibilityLabel(String(localized: "Strict Safety: Protect the Whole Window"))
                        .accessibilityHint(String(localized: "While Text Follow is recognizing, window metadata is uncertain, or OCR finds no matches, this protects the current or last trusted window. Turn it off to keep only the last masks and avoid full-window flashes. A confirmed missing or off-screen source hides the old desktop cover; Share Preview remains fail-closed during uncertainty."))
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SettingLabel(
                            icon: captureAccessIcon,
                            title: String(localized: "Capture Access"),
                            detail: captureAccessDetail,
                            color: captureAccessColor
                        )
                        HStack {
                            Text(captureAccessStatus)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Refresh") { permission.refresh() }
                            if permission.shouldOfferSystemSettings {
                                Button("Open System Settings") { permission.openSystemSettings() }
                            }
                        }
                    }
                }

                GlassCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: purchases.hasUnlimitedAccess ? "checkmark.seal.fill" : "heart.circle.fill")
                            .font(.title2)
                            .foregroundStyle(purchases.hasUnlimitedAccess ? BlurFollowTheme.mint : BlurFollowTheme.iris)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(purchases.hasUnlimitedAccess ? String(localized: "Unlimited Masks") : String(localized: "Support BlurFollow"))
                                .font(.headline)
                            Text(purchaseSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(purchases.hasUnlimitedAccess ? String(localized: "View Access") : String(localized: "View One-Time Unlock…")) {
                            isShowingUnlimitedMasks = true
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Support & Feedback")
                            .font(.headline)
                        Text("Get help or share an App Store rating after you have used BlurFollow.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Link("Contact Support", destination: supportURL)
                            Link("Rate BlurFollow on the App Store", destination: reviewURL)
                        }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Local Data")
                            .font(.headline)
                        Text("Mask geometry, Text Follow patterns, and window identity are stored in Application Support. Screen pixels and recognized text are never persisted.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Export Mask and Rule Settings…") { exportSettings() }
                            Button("Delete All Masks and Rules", role: .destructive) { store.removeAll() }
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
        .sheet(isPresented: $isShowingUnlimitedMasks) {
            UnlimitedMasksView(purchases: purchases, trigger: .settings)
        }
    }

    private var captureAccessDetail: String {
        if #available(macOS 15.2, *) {
            return String(localized: "Text Follow and Share Preview use Apple's per-selection system picker. Frames stay in memory and are never uploaded.")
        }
        return String(localized: "macOS 14 through 15.1 requires Screen Recording access for window identity and on-device text matching. Frames stay local.")
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return String.localizedStringWithFormat(String(localized: "BlurFollow %@"), version)
    }

    private var purchaseSummary: String {
        switch purchases.entitlementState {
        case .checking:
            return String(localized: "Checking your App Store purchase status…")
        case .purchased:
            return String(localized: "Your one-time purchase removes BlurFollow's saved-item plan limits.")
        case .grandfathered:
            return String(localized: "As an early user, you keep the unlimited access included with the version you first downloaded.")
        case .sourceBuild:
            return String(localized: "Source builds include unlimited masks and rules; the official App Store build offers an optional one-time unlock.")
        case .free:
            return String.localizedStringWithFormat(
                String(localized: "%lld Display Pins, %lld Window Pins, and %lld Text Follow rules are included free."),
                Int64(MaskAccessPolicy.freeDisplayMaskLimit),
                Int64(MaskAccessPolicy.freeWindowMaskLimit),
                Int64(MaskAccessPolicy.freeTextFollowRuleLimit)
            )
        }
    }

    private var supportURL: URL {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let path = language == "ja" ? "support/" : "en/support/"
        return URL(string: "https://blurfollow.hinoshiba.com/\(path)")!
    }

    private var reviewURL: URL {
        URL(string: "https://apps.apple.com/app/id6801985073?action=write-review")!
    }

    private var captureAccessStatus: String {
        if permission.shouldOfferSystemSettings { return String(localized: "Access not allowed") }
        if #available(macOS 15.2, *) { return String(localized: "Access is requested for each picker selection") }
        return permission.isAuthorized
            ? String(localized: "Broad access granted")
            : String(localized: "Access is requested when you use a Window Pin, Text Follow, or Share Preview")
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
