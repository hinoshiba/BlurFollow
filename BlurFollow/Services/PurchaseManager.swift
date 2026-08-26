import Foundation
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let productID = "com.hinoshiba.blurfollow.unlimited-masks"

    enum EntitlementState: Equatable {
        case checking
        case free
        case purchased
        case grandfathered
        case sourceBuild
    }

    enum OperationState: Equatable {
        case idle
        case loadingProduct
        case purchasing
        case pending
        case restoring
        case failed
    }

    @Published private(set) var entitlementState: EntitlementState
    @Published private(set) var operationState: OperationState = .idle
    @Published private(set) var product: Product?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isPurchaseViewPresented = false

    private var transactionUpdatesTask: Task<Void, Never>?
    private var entitlementRefreshGeneration: UInt = 0
    private var hasVerifiedGrandfatherAccess = false
    private var purchaseViewPresentationCount = 0

    var hasUnlimitedAccess: Bool {
        switch entitlementState {
        case .purchased, .grandfathered, .sourceBuild:
            true
        case .checking, .free:
            false
        }
    }

    var isStoreCommerceEnabled: Bool {
#if BLURFOLLOW_APP_STORE
        true
#else
        false
#endif
    }

    var isBusy: Bool {
        switch operationState {
        case .loadingProduct, .purchasing, .restoring:
            true
        case .idle, .pending, .failed:
            false
        }
    }

    var canPurchase: Bool {
        product != nil &&
            AppStore.canMakePayments &&
            !hasUnlimitedAccess &&
            !isBusy &&
            operationState != .pending
    }

    init() {
#if BLURFOLLOW_APP_STORE
        entitlementState = .checking
        operationState = .loadingProduct
        transactionUpdatesTask = observeTransactionUpdates()
        Task { [weak self] in
            await self?.prepare()
        }
#else
        // Apache-licensed source builds stay fully functional. The plan boundary applies to the
        // official Mac App Store target, where StoreKit can verify the signed app transaction.
        entitlementState = .sourceBuild
#endif
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func canCreateMask(currentCount: Int) -> Bool {
        MaskAccessPolicy.canCreateMask(
            currentCount: currentCount,
            hasUnlimitedAccess: hasUnlimitedAccess
        )
    }

    func purchaseViewDidAppear() {
        purchaseViewPresentationCount += 1
        isPurchaseViewPresented = true
    }

    func purchaseViewDidDisappear() {
        purchaseViewPresentationCount = max(0, purchaseViewPresentationCount - 1)
        isPurchaseViewPresented = purchaseViewPresentationCount > 0
    }

    func retryLoadingProduct() async {
        guard isStoreCommerceEnabled,
              !hasUnlimitedAccess,
              !isBusy,
              operationState != .pending else { return }
        operationState = .loadingProduct
        statusMessage = nil
        await refreshEntitlement()
        guard !hasUnlimitedAccess else {
            operationState = .idle
            statusMessage = String(localized: "Unlimited Masks is active.")
            return
        }
        await loadProduct()
    }

    func purchase() async {
        guard isStoreCommerceEnabled,
              !hasUnlimitedAccess,
              !isBusy,
              operationState != .pending else { return }
        guard AppStore.canMakePayments else {
            operationState = .failed
            statusMessage = String(localized: "In-App Purchases are not allowed for this Mac or Apple Account. Check Screen Time or device-management settings.")
            return
        }
        guard let product else {
            operationState = .failed
            statusMessage = String(localized: "The price is unavailable. Reload the purchase information and try again.")
            return
        }
        guard product.type == .nonConsumable else {
            operationState = .failed
            statusMessage = String(localized: "The purchase product is not configured correctly.")
            return
        }

        operationState = .purchasing
        statusMessage = nil

        do {
            switch try await product.purchase() {
            case .success(let result):
                switch result {
                case .verified(let transaction):
                    guard transaction.productID == Self.productID else {
                        operationState = .failed
                        statusMessage = String(localized: "The purchased product could not be verified.")
                        return
                    }
                    await transaction.finish()
                    await refreshEntitlement()
                    operationState = .idle
                    statusMessage = hasUnlimitedAccess
                        ? String(localized: "Unlimited Masks is now active. Thank you for supporting BlurFollow.")
                        : String(localized: "The purchase completed, but access is not available yet. Try Restore Purchases.")
                case .unverified:
                    operationState = .failed
                    statusMessage = String(localized: "The App Store could not verify the purchase, so Unlimited Masks was not unlocked.")
                }
            case .pending:
                operationState = .pending
                statusMessage = String(localized: "The purchase is awaiting approval. Unlimited Masks will unlock automatically after approval.")
            case .userCancelled:
                operationState = .idle
            @unknown default:
                operationState = .failed
                statusMessage = String(localized: "The purchase could not be completed. Please try again later.")
            }
        } catch StoreKitError.userCancelled {
            operationState = .idle
            statusMessage = nil
        } catch StoreKitError.networkError {
            operationState = .failed
            statusMessage = String(localized: "The purchase could not be completed. Check your App Store connection and try again.")
        } catch StoreKitError.notAvailableInStorefront {
            operationState = .failed
            statusMessage = String(localized: "Unlimited Masks is not available in the current App Store storefront.")
        } catch {
            operationState = .failed
            statusMessage = String(localized: "The purchase could not be completed. Check your App Store purchase settings and try again.")
        }
    }

    func restorePurchases() async {
        guard isStoreCommerceEnabled,
              !isBusy,
              operationState != .pending else { return }
        operationState = .restoring
        statusMessage = nil

        do {
            // AppStore.sync() can show Apple Account authentication, so call it only after the
            // person explicitly chooses Restore Purchases.
            try await AppStore.sync()
            await refreshEntitlement()
            operationState = .idle
            statusMessage = hasUnlimitedAccess
                ? String(localized: "Your Unlimited Masks access was restored.")
                : String(localized: "No restorable purchase was found for this Apple Account.")
        } catch StoreKitError.userCancelled {
            operationState = .idle
            statusMessage = nil
        } catch StoreKitError.networkError {
            operationState = .failed
            statusMessage = String(localized: "Purchases could not be restored. Check your App Store connection.")
        } catch {
            operationState = .failed
            statusMessage = String(localized: "Purchases could not be restored. Check the purchase settings for your Apple Account.")
        }
    }

    private func prepare() async {
        guard isStoreCommerceEnabled,
              operationState == .loadingProduct else { return }
        await refreshEntitlement()
        guard !hasUnlimitedAccess else {
            operationState = .idle
            statusMessage = nil
            return
        }
        await loadProduct()
    }

    private func loadProduct() async {
        guard isStoreCommerceEnabled else { return }

        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first {
                $0.id == Self.productID && $0.type == .nonConsumable
            }
            if hasUnlimitedAccess {
                operationState = .idle
                statusMessage = nil
            } else if product == nil {
                operationState = .failed
                statusMessage = String(localized: "Unlimited Masks could not be loaded from the App Store.")
            } else if !AppStore.canMakePayments {
                operationState = .failed
                statusMessage = String(localized: "In-App Purchases are not allowed for this Mac or Apple Account. Restore Purchases remains available.")
            } else {
                operationState = .idle
            }
        } catch {
            product = nil
            if hasUnlimitedAccess {
                operationState = .idle
                statusMessage = nil
            } else {
                operationState = .failed
                statusMessage = String(localized: "The price could not be loaded from the App Store.")
            }
        }
    }

    private func refreshEntitlement() async {
        guard isStoreCommerceEnabled else { return }
        entitlementRefreshGeneration &+= 1
        let generation = entitlementRefreshGeneration
        var hasVerifiedPurchase = false
        var isGrandfathered = hasVerifiedGrandfatherAccess

        do {
            switch try await AppTransaction.shared {
            case .verified(let appTransaction):
                if appTransaction.bundleID == Bundle.main.bundleIdentifier,
                   MaskAccessPolicy.isGrandfathered(
                       originalAppVersion: appTransaction.originalAppVersion
                   ) {
                    // This is a verified, permanent property of the original download. Commit it
                    // immediately so an overlapping newer refresh cannot discard the observation
                    // merely because its own AppTransaction request fails.
                    hasVerifiedGrandfatherAccess = true
                    isGrandfathered = true
                }
            case .unverified:
                break
            }
        } catch {
            // Current IAP entitlement may still be available from StoreKit's signed local history.
        }

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.productType == .nonConsumable,
                  transaction.revocationDate == nil else { continue }
            hasVerifiedPurchase = true
        }

        // Multiple launch/purchase/restore/update scans may overlap. Only the newest full snapshot
        // may publish access, and verified grandfather status never regresses within this process.
        guard generation == entitlementRefreshGeneration else { return }
        isGrandfathered = isGrandfathered || hasVerifiedGrandfatherAccess
        hasVerifiedGrandfatherAccess = isGrandfathered
        if hasVerifiedPurchase {
            entitlementState = .purchased
        } else if isGrandfathered {
            entitlementState = .grandfathered
        } else {
            entitlementState = .free
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                switch result {
                case .verified(let transaction):
                    guard transaction.productID == Self.productID,
                          transaction.productType == .nonConsumable else { continue }
                    await self?.handleTransactionUpdate(transaction)
                case .unverified(let transaction, _):
                    guard transaction.productID == Self.productID else { continue }
                    await self?.handleUnverifiedTransactionUpdate()
                }
            }
        }
    }

    private func handleUnverifiedTransactionUpdate() async {
        let wasPending = operationState == .pending
        let previouslyHadUnlimitedAccess = hasUnlimitedAccess

        // Never grant or finish the unverified update. It is still a useful signal to rescan the
        // verified current snapshot, which can reflect a refund or revocation without trusting the
        // unverifiable payload itself.
        await refreshEntitlement()

        if hasUnlimitedAccess {
            if wasPending {
                operationState = .idle
                statusMessage = String(localized: "Unlimited Masks is active.")
            }
        } else if wasPending {
            operationState = .failed
            statusMessage = String(localized: "The App Store could not verify the purchase, so Unlimited Masks was not unlocked.")
        } else if previouslyHadUnlimitedAccess {
            statusMessage = String(localized: "Unlimited Masks is no longer active. Your existing masks remain available.")
        }
    }

    private func handleTransactionUpdate(_ transaction: Transaction) async {
        let previouslyHadUnlimitedAccess = hasUnlimitedAccess
        await transaction.finish()
        await refreshEntitlement()

        if hasUnlimitedAccess {
            statusMessage = String(localized: "Unlimited Masks is active.")
            switch operationState {
            case .pending, .idle, .failed:
                operationState = .idle
            case .loadingProduct, .purchasing, .restoring:
                break
            }
        } else if previouslyHadUnlimitedAccess || transaction.revocationDate != nil {
            // Never remove or disable an existing mask. Only later creation requests use the new
            // free-plan state, which keeps active sharing setups intact.
            statusMessage = String(localized: "Unlimited Masks is no longer active. Your existing masks remain available.")
            if operationState == .pending { operationState = .idle }
        }
    }
}
