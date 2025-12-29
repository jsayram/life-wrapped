import Foundation
import StoreKit

// MARK: - Store Products

/// Available in-app purchase products
public enum StoreProduct: String, CaseIterable {
    case smartestAI = "com.jsayram.lifewrapped.smartestai"
    
    var displayName: String {
        switch self {
        case .smartestAI:
            return "Smartest AI Year Wrap"
        }
    }
}

// MARK: - Store Manager

/// Manages in-app purchases using StoreKit 2
@MainActor
public final class StoreManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Whether the Smartest AI feature is unlocked
    @Published public private(set) var isSmartestAIUnlocked: Bool = false
    
    /// Available products from App Store
    @Published public private(set) var products: [Product] = []
    
    /// Current purchase state
    @Published public private(set) var purchaseState: PurchaseState = .idle
    
    /// Error message if any
    @Published public private(set) var errorMessage: String?
    
    // MARK: - Purchase State
    
    public enum PurchaseState: Equatable {
        case idle
        case loading
        case purchasing
        case restoring
        case success
        case failed
    }
    
    // MARK: - Private Properties
    
    private var transactionListener: Task<Void, Error>?
    
    // MARK: - Initialization
    
    public init() {
        // Start listening for transactions
        transactionListener = listenForTransactions()
        
        // Load products and check entitlements on init
        Task {
            await loadProducts()
            await checkEntitlements()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load available products from App Store
    public func loadProducts() async {
        purchaseState = .loading
        errorMessage = nil
        
        do {
            let productIds = StoreProduct.allCases.map { $0.rawValue }
            products = try await Product.products(for: productIds)
            purchaseState = .idle
            print("📦 [StoreManager] Loaded \(products.count) products")
        } catch {
            purchaseState = .failed
            errorMessage = "Failed to load products: \(error.localizedDescription)"
            print("❌ [StoreManager] Failed to load products: \(error)")
        }
    }
    
    // MARK: - Purchasing
    
    /// Purchase the Smartest AI product
    public func purchaseSmartestAI() async -> Bool {
        guard let product = products.first(where: { $0.id == StoreProduct.smartestAI.rawValue }) else {
            errorMessage = "Product not available"
            return false
        }
        
        return await purchase(product)
    }
    
    /// Purchase a specific product
    public func purchase(_ product: Product) async -> Bool {
        purchaseState = .purchasing
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                switch verification {
                case .verified(let transaction):
                    // Finish the transaction
                    await transaction.finish()
                    await checkEntitlements()
                    purchaseState = .success
                    print("✅ [StoreManager] Purchase successful: \(product.id)")
                    return true
                    
                case .unverified(_, let error):
                    purchaseState = .failed
                    errorMessage = "Purchase verification failed: \(error.localizedDescription)"
                    print("❌ [StoreManager] Unverified purchase: \(error)")
                    return false
                }
                
            case .userCancelled:
                purchaseState = .idle
                print("ℹ️ [StoreManager] User cancelled purchase")
                return false
                
            case .pending:
                purchaseState = .idle
                errorMessage = "Purchase is pending approval"
                print("⏳ [StoreManager] Purchase pending")
                return false
                
            @unknown default:
                purchaseState = .failed
                errorMessage = "Unknown purchase result"
                return false
            }
        } catch {
            purchaseState = .failed
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            print("❌ [StoreManager] Purchase error: \(error)")
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    /// Restore previously purchased products
    public func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil
        
        do {
            // Sync with App Store
            try await AppStore.sync()
            await checkEntitlements()
            purchaseState = .success
            print("✅ [StoreManager] Purchases restored")
        } catch {
            purchaseState = .failed
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
            print("❌ [StoreManager] Restore failed: \(error)")
        }
    }
    
    // MARK: - Entitlements
    
    /// Check current entitlements
    public func checkEntitlements() async {
        var hasSmartestAI = false
        
        // Check for current entitlements
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == StoreProduct.smartestAI.rawValue {
                    hasSmartestAI = true
                }
            case .unverified:
                continue
            }
        }
        
        isSmartestAIUnlocked = hasSmartestAI
        print("🔓 [StoreManager] Smartest AI unlocked: \(hasSmartestAI)")
    }
    
    // MARK: - Transaction Listener
    
    /// Listen for transaction updates (renewals, refunds, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                switch result {
                case .verified(let transaction):
                    await transaction.finish()
                    await self?.checkEntitlements()
                case .unverified:
                    continue
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    /// Get the Smartest AI product
    public var smartestAIProduct: Product? {
        products.first { $0.id == StoreProduct.smartestAI.rawValue }
    }
    
    /// Reset purchase state to idle
    public func resetState() {
        purchaseState = .idle
        errorMessage = nil
    }
}
