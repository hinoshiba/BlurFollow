import SwiftUI

enum UnlimitedMasksTrigger: String, Identifiable {
    case displayPin
    case windowPin
    case settings

    var id: String { rawValue }
}

struct UnlimitedMasksView: View {
    @ObservedObject var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @State private var didResumeCreation = false
    @State private var didRegisterPresentation = false

    let trigger: UnlimitedMasksTrigger
    var onUnlocked: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: purchases.hasUnlimitedAccess ? "checkmark.seal.fill" : "rectangle.stack.badge.plus")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(purchases.hasUnlimitedAccess ? BlurFollowTheme.mint : BlurFollowTheme.iris)
                    .frame(width: 68, height: 68)
                    .background(
                        (purchases.hasUnlimitedAccess ? BlurFollowTheme.mint : BlurFollowTheme.iris).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 18)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if purchases.hasUnlimitedAccess {
                accessCard
            } else {
                benefitCard
                purchaseControls
            }

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(BlurFollowTheme.cyan)
                Text("Apple handles the purchase. BlurFollow has no account, advertising, or analytics SDK.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                if purchases.isStoreCommerceEnabled {
                    Button("Restore Purchases") {
                        Task { await purchases.restorePurchases() }
                    }
                    .disabled(purchases.isBusy || purchases.operationState == .pending)
                }
                Spacer()
                Button(trigger == .settings ? String(localized: "Done") : String(localized: "Not Now")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .onAppear {
            if !didRegisterPresentation {
                purchases.purchaseViewDidAppear()
                didRegisterPresentation = true
            }
            resumeCreationIfNeeded()
        }
        .onDisappear {
            if didRegisterPresentation {
                purchases.purchaseViewDidDisappear()
                didRegisterPresentation = false
            }
        }
        .onChange(of: purchases.hasUnlimitedAccess) { _, _ in
            resumeCreationIfNeeded()
        }
    }

    private var accessCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "infinity")
                .font(.title2.weight(.semibold))
                .foregroundStyle(BlurFollowTheme.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(accessTitle)
                    .font(.headline)
                Text("BlurFollow does not impose a mask-count plan limit. Practical capacity depends on your Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(BlurFollowTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var benefitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Create more than 5 masks", systemImage: "infinity")
            Label("One-time purchase — no subscription", systemImage: "checkmark.circle")
            Label("Keep every existing mask available", systemImage: "rectangle.stack")
            Label("Support continued BlurFollow development", systemImage: "heart")
        }
        .font(.subheadline.weight(.medium))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
    }

    private var purchaseControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await purchases.purchase() }
            } label: {
                HStack {
                    if purchases.operationState == .purchasing {
                        ProgressView().controlSize(.small)
                    }
                    Text(purchaseButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(BlurFollowTheme.ink)
            .disabled(!purchases.canPurchase)

            if purchases.operationState == .loadingProduct || purchases.operationState == .restoring {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(operationDetail)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let message = purchases.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(purchases.operationState == .failed ? BlurFollowTheme.coral : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if purchases.operationState == .failed {
                Button("Reload Purchase Information") {
                    Task { await purchases.retryLoadingProduct() }
                }
                .buttonStyle(.borderless)
                .disabled(purchases.isBusy)
            }
        }
    }

    private var title: String {
        if purchases.hasUnlimitedAccess { return String(localized: "Unlimited Masks") }
        return trigger == .settings
            ? String(localized: "Support BlurFollow")
            : String(localized: "Add More Masks")
    }

    private var detail: String {
        if purchases.hasUnlimitedAccess {
            return String(localized: "You can create as many masks as your Mac can comfortably handle.")
        }
        if trigger == .settings {
            return String(localized: "Five masks are included free. A one-time purchase removes the plan limit and supports continued development.")
        }
        return String(localized: "Your five masks stay active. A one-time purchase lets you create the next one and removes the plan limit.")
    }

    private var accessTitle: String {
        switch purchases.entitlementState {
        case .grandfathered:
            return String(localized: "Early-user access is active")
        case .sourceBuild:
            return String(localized: "Unlimited access is included in this source build")
        case .purchased, .checking, .free:
            return String(localized: "Unlimited Masks is active")
        }
    }

    private var purchaseButtonTitle: String {
        switch purchases.operationState {
        case .purchasing:
            return String(localized: "Completing Purchase…")
        case .pending:
            return String(localized: "Awaiting Approval")
        default:
            if let price = purchases.product?.displayPrice {
                return String.localizedStringWithFormat(
                    String(localized: "Unlock Unlimited Masks — %@"),
                    price
                )
            }
            return String(localized: "Loading Price…")
        }
    }

    private var operationDetail: String {
        purchases.operationState == .restoring
            ? String(localized: "Restoring purchases…")
            : String(localized: "Loading purchase information…")
    }

    private func resumeCreationIfNeeded() {
        guard trigger != .settings,
              purchases.hasUnlimitedAccess,
              !didResumeCreation else { return }
        didResumeCreation = true
        onUnlocked?()
    }
}
