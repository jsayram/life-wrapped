import Foundation
import StoreKit

// MARK: - Store Products

/// Available in-app purchase products
public enum StoreProduct: String, CaseIterable {
    case smartestAI = "com.jsayram.lifewrapped.smartestai"

    var displayName: String {
        switch self {
        case .smartestAI:
            return "Cloud AI"
        }
    }
}

// MARK: - Store Manager

/// Manages in-app purchases using StoreKit 2
@MainActor
public final class StoreManager: ObservableObject {

    // MARK: - Published Properties

    /// Whether Cloud AI is unlocked
    @Published public private(set) var isSmartestAIUnlocked: Bool = false

    /// Available products from App Store
    @Published public private(set) var products: [Product] = []

    /// What the store is doing right now
    @Published public private(set) var purchaseState: PurchaseState = .idle

    /// What the last purchase, restore or code redemption needs the person to know.
    /// Nil after a success or a cancel, since those speak for themselves.
    @Published public private(set) var notice: Notice?

    // MARK: - Types

    public enum PurchaseState: Equatable {
        case idle
        case purchasing
        case restoring
    }

    public struct Notice: Equatable {
        public let text: String
        public let isError: Bool

        static func info(_ text: String) -> Notice { Notice(text: text, isError: false) }
        static func error(_ text: String) -> Notice { Notice(text: text, isError: true) }
    }

    /// A purchase or restore is running, so the buttons that start one should wait
    public var isBusy: Bool { purchaseState != .idle }

    // MARK: - Private Properties

    private var transactionListener: Task<Void, Error>?

    // MARK: - Initialization

    public init() {
        // Start listening for transactions
        transactionListener = listenForTransactions()

        // Load products and check entitlements on init
        Task {
            await checkEntitlements()
            await loadProducts()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    /// Load available products from App Store. An unknown product ID comes back as an empty list,
    /// not an error, so callers check `smartestAIProduct` afterwards.
    public func loadProducts() async {
        do {
            let productIds = StoreProduct.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIds)
            print("📦 [StoreManager] Loaded \(products.count) products")
        } catch {
            print("❌ [StoreManager] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchasing

    /// Buy Cloud AI. `purchase` is SwiftUI's purchase action, which shows the App Store sheet in
    /// the window the person is using. The unlock itself shows up in `isSmartestAIUnlocked`.
    public func purchaseSmartestAI(using purchase: (Product) async throws -> Product.PurchaseResult) async {
        guard !isBusy else { return }
        purchaseState = .purchasing
        notice = nil
        defer { purchaseState = .idle }

        // Products may not have loaded at launch, for example when the device was offline
        if smartestAIProduct == nil {
            await loadProducts()
        }
        guard let product = smartestAIProduct else {
            notice = .error("Cloud AI isn't available from the App Store right now. Check your connection and try again.")
            return
        }

        do {
            switch try await purchase(product) {
            case .success(.verified(let transaction)):
                await transaction.finish()
                await checkEntitlements()
                print("✅ [StoreManager] Purchase successful: \(product.id)")

            case .success(.unverified(_, let error)):
                notice = .error("The App Store couldn't confirm this purchase. Try Restore purchases in a moment.")
                print("❌ [StoreManager] Unverified purchase: \(error)")

            case .pending:
                // Ask to Buy or a payment that needs attention. The transaction arrives later
                // through Transaction.updates and unlocks Cloud AI then.
                notice = .info("Waiting for approval. Cloud AI unlocks as soon as the purchase is approved.")
                print("⏳ [StoreManager] Purchase pending")

            case .userCancelled:
                print("ℹ️ [StoreManager] User cancelled purchase")

            @unknown default:
                notice = .error("The purchase didn't go through. Please try again.")
            }
        } catch {
            if !Self.isCancellation(error) {
                notice = .error(Self.message(for: error, doing: "The purchase"))
            }
            print("❌ [StoreManager] Purchase error: \(error)")
        }
    }

    // MARK: - Restore Purchases

    /// Restore a purchase made on another device or before a reinstall
    public func restorePurchases() async {
        guard !isBusy else { return }
        purchaseState = .restoring
        notice = nil
        defer { purchaseState = .idle }

        // Nothing to ask the App Store for when this device already has it
        await checkEntitlements()
        if isSmartestAIUnlocked {
            notice = .info("Cloud AI is already unlocked.")
            return
        }

        var syncError: Error?
        do {
            // Asks the person to sign in to the App Store if needed
            try await AppStore.sync()
        } catch {
            syncError = error
            print("❌ [StoreManager] Restore failed: \(error)")
        }
        await checkEntitlements()

        if isSmartestAIUnlocked {
            print("✅ [StoreManager] Purchases restored")
        } else if let syncError {
            if !Self.isCancellation(syncError) {
                notice = .error(Self.message(for: syncError, doing: "Restoring"))
            }
        } else {
            notice = .info("No Cloud AI purchase was found for the Apple Account signed in to the App Store.")
        }
    }

    // MARK: - Redeem Code

    /// Called when the offer code sheet closes. A redeemed code's transaction arrives through
    /// Transaction.updates, which unlocks Cloud AI; this check covers it arriving first.
    public func codeRedemptionFinished(_ result: Result<Void, Error>) async {
        switch result {
        case .success:
            await checkEntitlements()
        case .failure(let error):
            if !Self.isCancellation(error) {
                notice = .error(Self.message(for: error, doing: "Redeeming the code"))
            }
            print("❌ [StoreManager] Code redemption failed: \(error)")
        }
    }

    /// Clear the last notice, so a new sheet doesn't show an old message
    public func clearNotice() {
        notice = nil
    }

    // MARK: - Entitlements

    /// Check current entitlements
    public func checkEntitlements() async {
        var hasSmartestAI = false

        // Check for current entitlements
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == StoreProduct.smartestAI.rawValue && transaction.revocationDate == nil {
                    hasSmartestAI = true
                }
            case .unverified:
                continue
            }
        }

        isSmartestAIUnlocked = hasSmartestAI
        print("🔓 [StoreManager] Cloud AI unlocked: \(hasSmartestAI)")
    }

    // MARK: - Transaction Listener

    /// Listen for transactions made outside a purchase call: Ask to Buy approvals, redeemed codes,
    /// purchases on other devices and refunds
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self?.checkEntitlements()
                    await self?.clearPendingNotice()
                case .unverified:
                    continue
                }
            }
        }
    }

    /// A waiting purchase was approved or declined, so "waiting for approval" no longer applies
    private func clearPendingNotice() {
        if notice?.isError == false { notice = nil }
    }

    // MARK: - Helpers

    /// Get the Cloud AI product
    public var smartestAIProduct: Product? {
        products.first { $0.id == StoreProduct.smartestAI.rawValue }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if case StoreKitError.userCancelled = error { return true }
        return error is CancellationError
    }

    /// Plain words for what went wrong. StoreKit's own descriptions are written for developers.
    private static func message(for error: Error, doing action: String) -> String {
        switch error {
        case StoreKitError.networkError:
            return "Couldn't reach the App Store. Check your connection and try again."
        case StoreKitError.notEntitled:
            return "This Apple Account can't make purchases right now."
        case Product.PurchaseError.purchaseNotAllowed:
            return "Purchases are turned off on this device. You can allow them in Screen Time settings."
        case Product.PurchaseError.productUnavailable:
            return "Cloud AI isn't available in your App Store region right now."
        default:
            return "\(action) didn't work. Please try again."
        }
    }
}
