# In-App Purchases Setup

## Overview

Life Wrapped uses StoreKit 2 to offer a **non-consumable** in-app purchase that unlocks the "Smartest AI" feature for Year Wrap generation.

### Product Details

| Property   | Value                                |
| ---------- | ------------------------------------ |
| Product ID | `com.jsayram.lifewrapped.smartestai` |
| Type       | Non-Consumable                       |
| Feature    | Smartest AI Year Wrap                |

### What It Unlocks

- Access to use external AI APIs (OpenAI GPT-4.1, Anthropic Claude 3.5 Sonnet) for Year Wrap generation
- **BYOK Model**: Users still provide their own API keys — the purchase only unlocks the ability to use them
- One-time purchase, permanent unlock
- Syncs across devices via App Store

---

## Architecture

### Files

| File                                                                              | Purpose                                              |
| --------------------------------------------------------------------------------- | ---------------------------------------------------- |
| [App/Store/StoreManager.swift](../App/Store/StoreManager.swift)                   | StoreKit 2 manager - purchase, restore, entitlements |
| [App/Coordinators/AppCoordinator.swift](../App/Coordinators/AppCoordinator.swift) | Exposes `storeManager` to views                      |
| [App/Views/Tabs/SettingsTab.swift](../App/Views/Tabs/SettingsTab.swift)           | Restore Purchases button                             |
| [App/Views/Tabs/OverviewTab.swift](../App/Views/Tabs/OverviewTab.swift)           | Year Wrap purchase gating                            |

> **Note:** StoreKit 2 does not require any special entitlements. The `com.apple.developer.in-app-payments` entitlement is for Apple Pay, not In-App Purchases.

### StoreManager API

```swift
@MainActor
public final class StoreManager: ObservableObject {
    // Published state
    @Published public private(set) var isSmartestAIUnlocked: Bool
    @Published public private(set) var products: [Product]
    @Published public private(set) var purchaseState: PurchaseState

    // Methods
    func purchaseSmartestAI() async -> Bool
    func restorePurchases() async
    func checkEntitlements() async

    // Helpers
    var smartestAIProduct: Product?  // Get product with price
}
```

### User Flow

1. **Year Wrap Sheet Opens**

   - If Smartest AI unlocked + API configured → Show "Recommended" option
   - If Smartest AI NOT unlocked + API configured → Show purchase button with price
   - If no API configured → Show Local AI as primary + Setup API option

2. **Purchase Flow**

   - User taps purchase button → StoreKit payment sheet
   - On success → `isSmartestAIUnlocked = true`, dismiss sheet
   - On cancel → Return to sheet
   - On error → Show error message

3. **Restore Purchases**
   - Settings → Purchases → Restore Purchases
   - Syncs with App Store to restore previous purchases

---

## App Store Connect Setup

### Step 1: Create the Product

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app → **Monetization** → **In-App Purchases**
3. Click **Create** (+ button)
4. Select **Non-Consumable**
5. Fill in details:
   - **Reference Name**: Smartest AI Year Wrap
   - **Product ID**: `com.jsayram.lifewrapped.smartestai`
   - **Price**: Select your price tier (e.g., Tier 1 = $0.99, Tier 3 = $2.99)

### Step 2: Add Localization

1. In the product details, click **App Store Localization**
2. Add for each language:
   - **Display Name**: Smartest AI Year Wrap
   - **Description**: Unlock the ability to use premium AI (OpenAI, Anthropic) for generating your personalized Year Wrap with the most detailed insights.

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
