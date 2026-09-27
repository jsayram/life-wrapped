# In-App Purchases Setup

## Overview

Life Wrapped uses StoreKit 2 to offer a **non-consumable** in-app purchase that unlocks **Cloud AI** (called "Smartest AI" before September 2026) for summaries and Year Wrap.

### Product Details

| Property   | Value                                |
| ---------- | ------------------------------------ |
| Product ID | `com.jsayram.lifewrapped.smartestai` |
| Type       | Non-Consumable                       |
| Feature    | Cloud AI (summaries and Year Wrap)   |
| Price      | $2.99, one time                      |

### What It Unlocks

- The Cloud AI engine: OpenAI or Anthropic models (any current model ID) for recording, month and Year Wrap summaries
- **BYOK Model**: Users still provide their own API keys — the purchase only unlocks the ability to use them
- One-time purchase, permanent unlock
- Syncs across devices via App Store

---

## Architecture

### Files

| File                                                                              | Purpose                                              |
| --------------------------------------------------------------------------------- | ---------------------------------------------------- |
| [App/Store/StoreManager.swift](../App/Store/StoreManager.swift)                   | StoreKit 2 manager - purchase, restore, entitlements |
| [App/Coordinators/AppCoordinator.swift](../App/Coordinators/AppCoordinator.swift) | Exposes `storeManager` to views and forwards its changes |
| [App/Settings/AISettingsView.swift](../App/Settings/AISettingsView.swift)         | `SmartestPurchaseSheet`: buy, restore and redeem     |
| [App/Views/Tabs/SettingsTab.swift](../App/Views/Tabs/SettingsTab.swift)           | Cloud AI row (opens the sheet) and Restore purchases |
| [App/Views/Tabs/OverviewTab.swift](../App/Views/Tabs/OverviewTab.swift)           | Year Wrap purchase gating                            |

> **Note:** StoreKit 2 does not require any special entitlements. The `com.apple.developer.in-app-payments` entitlement is for Apple Pay, not In-App Purchases.

### StoreManager API

```swift
@MainActor
public final class StoreManager: ObservableObject {
    // Published state
    @Published public private(set) var isSmartestAIUnlocked: Bool
    @Published public private(set) var products: [Product]
    @Published public private(set) var purchaseState: PurchaseState  // idle, purchasing, restoring
    @Published public private(set) var notice: Notice?               // what to tell the person, if anything

    // Methods
    func purchaseSmartestAI(using purchase: (Product) async throws -> Product.PurchaseResult) async
    func restorePurchases() async
    func codeRedemptionFinished(_ result: Result<Void, Error>) async
    func checkEntitlements() async

    // Helpers
    var smartestAIProduct: Product?  // Get product with price
    var isBusy: Bool                 // a purchase or restore is running
}
```

`SmartestPurchaseSheet` passes SwiftUI's `@Environment(\.purchase)` action, so the App Store sheet shows in the window the person is using. It presents Apple's code sheet with `.offerCodeRedemption(isPresented:)`, which works on top of the purchase sheet.

### User Flow

The sheet watches `isSmartestAIUnlocked` and closes itself when it turns true, whatever caused it: a purchase, a restore, a redeemed code, or an Ask to Buy approval that arrives through `Transaction.updates` while the sheet is open.

1. **Where the sheet opens**

   - AI & Summaries: tapping Cloud AI while locked. After unlocking, the key setup opens (or Cloud AI turns on if a key is already saved).
   - Settings: tapping the Cloud AI row. After unlocking, the app goes to the key setup.
   - Year Wrap: tapping the locked Cloud AI option. After unlocking, the Year Wrap choices open again.

2. **Purchase**

   - Success: the sheet closes with a "Cloud AI unlocked" toast
   - Cancel: nothing changes
   - Ask to Buy or other pending payment: the sheet says it's waiting for approval
   - Failure: a plain-language message under the button (no connection, purchases turned off in Screen Time, and so on)
   - If the price didn't load at launch, the sheet tries again when it opens, and the button tries once more before giving up

3. **Restore**

   - In the sheet, or Settings → Purchases → Restore purchases (which reports the result as a toast)
   - Already unlocked: says so without asking the App Store
   - Nothing found: "No Cloud AI purchase was found for the Apple Account signed in to the App Store."
   - Cancelled sign-in: nothing is shown

4. **Redeem code**

   - Offer codes work for non-consumables on iOS 16.3 and later, so they cover this product
   - Create codes in App Store Connect under the in-app purchase's Offer Codes
   - A redeemed code's transaction arrives through `Transaction.updates`, which unlocks Cloud AI and closes the sheet

### Testing notes

Running from Xcode uses `Config/StoreKitConfiguration.storekit`, so purchases, restores and Ask to Buy work without an Apple Account. Launching another way (for example `xcrun simctl launch`) talks to the real App Store, which asks for sign-in; use a Sandbox account there.

---

## App Store Connect Setup

### Step 1: Create the Product

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app → **Monetization** → **In-App Purchases**
3. Click **Create** (+ button)
4. Select **Non-Consumable**
5. Fill in details:
   - **Reference Name**: Cloud AI
   - **Product ID**: `com.jsayram.lifewrapped.smartestai`
   - **Price**: Select your price tier (e.g., Tier 1 = $0.99, Tier 3 = $2.99)

### Step 2: Add Localization

1. In the product details, click **App Store Localization**
2. Add for each language:
   - **Display Name**: Cloud AI
   - **Description**: Detailed summaries with your own AI key
   - Limits: display name 30 characters, description 45 characters

### Step 3: Review Information

1. Add a **Review Screenshot** (screenshot of the feature)
2. Add **Review Notes** explaining the feature for App Review

### Step 4: Submit for Review

1. IAPs are reviewed with your app submission
2. Can also submit IAP separately for review before app update

---

## Testing

### Sandbox Testing

1. **Create Sandbox Tester**

   - App Store Connect → Users and Access → Sandbox → Testers
   - Create a test account (use a unique email)

2. **Test on Device**

   - Sign out of App Store on device
   - Run app from Xcode
   - When purchasing, sign in with sandbox account
   - Transactions are free in sandbox

3. **Clear Purchase History**
   - Settings app → App Store → Sandbox Account → Manage
   - Clear purchase history to test fresh

### StoreKit Configuration (Local Testing)

For local testing without App Store Connect:

1. Create `StoreKitConfiguration.storekit` file in Xcode
2. Add product with matching Product ID
3. In scheme settings, set StoreKit Configuration
4. Test purchases locally without sandbox account

---

## Troubleshooting

### Products Not Loading

- Verify Product ID matches exactly: `com.jsayram.lifewrapped.smartestai`
- Ensure Paid Apps agreement is signed in App Store Connect
- Wait 15-30 minutes after creating product (propagation delay)
- Check device is signed into App Store

### Purchases Not Restoring

- `Transaction.currentEntitlements` only returns verified transactions
- User must be signed into same Apple ID that made purchase
- Non-consumables sync automatically via iCloud

### Entitlement Issues

- **StoreKit 2 does NOT require special entitlements** — no capability needed in Xcode
- The `com.apple.developer.in-app-payments` entitlement is for Apple Pay, not IAPs
- If you see provisioning errors about Apple Pay, remove that entitlement
- Ensure your Apple Developer account has the Paid Apps agreement signed

---

## Price Tiers Reference

| Tier    | US Price | Suggested Use   |
| ------- | -------- | --------------- |
| Tier 1  | $0.99    | Entry-level     |
| Tier 2  | $1.99    | Low             |
| Tier 3  | $2.99    | **Recommended** |
| Tier 5  | $4.99    | Premium         |
| Tier 10 | $9.99    | High-value      |

---

## Privacy Considerations

- **BYOK Model**: Life Wrapped never stores or transmits API keys to our servers
- API keys are stored locally in device Keychain
- Purchase only unlocks the feature — user controls their own API access
- No analytics or tracking related to purchases

---

## Checklist

Before App Store submission:

- [ ] Product created in App Store Connect
- [ ] Product ID matches code: `com.jsayram.lifewrapped.smartestai`
- [ ] Price tier set
- [ ] Localizations added (at minimum: English)
- [ ] Review screenshot uploaded
- [ ] Review notes written
- [ ] Tested in Sandbox environment
- [ ] Restore Purchases works correctly
- [ ] Paid Apps agreement signed in App Store Connect
