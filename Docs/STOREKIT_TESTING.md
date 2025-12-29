# StoreKit Testing Guide

## Overview

Life Wrapped uses StoreKit 2 for in-app purchases. This guide covers how to test the purchase flow using Xcode's StoreKit Configuration file.

---

## Setup (One-Time)

1. **Open Xcode** → Product → Scheme → Edit Scheme (⌘<)
2. Select **Run** on the left sidebar
3. Click the **Options** tab
4. Set **StoreKit Configuration** to `Config/StoreKitConfiguration.storekit`
5. Click **Close**

---

## Testing Purchase Flow

### Normal Purchase

1. Run the app in Simulator or device
2. Navigate to Year Wrap or AI Settings
3. Tap "Smartest AI" (shows 🔒 lock icon)
4. Tap "Unlock for $4.99"
5. Confirm in the simulated App Store sheet
6. ✅ Purchase completes instantly

### Reset Purchases (Test Again)

**Method 1: Xcode Debug Menu**

1. With app running, go to Xcode menu bar
2. **Debug → StoreKit → Manage Transactions**
3. Select the transaction you want to delete
4. Click **Delete** (trash icon) or right-click → Delete
5. Return to app - feature should be locked again

**Method 2: Clear All Purchase History**

1. **Debug → StoreKit → Clear Purchase History**
2. This removes ALL test purchases
3. App resets to "not purchased" state

**Method 3: Delete App & Reinstall**

- Delete the app from Simulator/device
- Run again from Xcode
- All StoreKit test data is cleared

---

## Testing Error Scenarios

### Interrupted Purchases

Simulates user closing the purchase sheet mid-transaction:

1. **Debug → StoreKit → Enable Interrupted Purchases**
2. Attempt a purchase in the app
3. The purchase will be "interrupted" (pending)
4. **Debug → StoreKit → Manage Transactions**
5. You'll see a pending transaction
6. Click **Approve** or **Decline** to complete/cancel

This tests your app's handling of:

- `Transaction.updates` listener receiving delayed transactions
- UI state when purchase is pending
- Recovery from interrupted purchases

### Failed Purchases

Test how the app handles purchase failures:

1. Open `Config/StoreKitConfiguration.storekit` in Xcode
2. In the left sidebar, click the **⚙️ Editor** tab (gear icon)
3. Under **StoreKit Errors**, enable errors for specific operations:

| Error Type         | What It Tests              |
| ------------------ | -------------------------- |
| **Load Products**  | Product info fails to load |
| **Purchase**       | Purchase transaction fails |
| **Verification**   | Receipt verification fails |
| **App Store Sync** | Sync with App Store fails  |

4. Run the app and trigger the operation
5. **Remember to disable errors** after testing!

### Specific Error Codes

You can also simulate specific StoreKit errors:

1. In StoreKitConfiguration.storekit → Editor tab
2. Under a specific error type, click the dropdown
3. Choose an error like:
   - `userCancelled` - User taps Cancel
   - `paymentNotAllowed` - Payments restricted
   - `networkError` - No internet
   - `unknown` - Generic failure

---

## Testing Restore Purchases

1. Complete a purchase (follow Normal Purchase steps)
2. Clear app data or reinstall app
3. Go to **Settings → Purchases → Restore Purchases**
4. The Smartest AI feature should unlock again

To test restore when nothing was purchased:

1. Clear all purchase history (Debug → StoreKit → Clear Purchase History)
2. Tap Restore Purchases
3. App should show "Nothing to restore" or similar message

---

## Testing on Real Device (Sandbox)

For testing with real App Store Connect (before release):

### Setup Sandbox Tester

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Users and Access → Sandbox → Testers
3. Create a new sandbox tester account
4. Use a unique email (can be fake, e.g., `test@example.com`)

### Test on Device

1. On your iOS device: Settings → App Store → Sign Out
2. Run the app from Xcode
3. When prompted to purchase, sign in with sandbox account
4. Complete purchase (no real charges in sandbox)

**Note:** Don't sign into the main Settings with sandbox account - only use it when the App Store prompt appears.

---

## Debugging Tips

### View Transaction Logs

1. **Debug → StoreKit → Manage Transactions**
2. Shows all test transactions with:
   - Transaction ID
   - Product ID
   - Purchase date
   - Status (purchased, refunded, etc.)

### Print Debug Info

The `StoreManager` logs purchase events:

```
🛒 [StoreManager] Checking entitlements...
✅ [StoreManager] Smartest AI is unlocked
🛒 [StoreManager] Purchase successful for smartestAI
```

### Common Issues

| Issue                         | Solution                                                  |
| ----------------------------- | --------------------------------------------------------- |
| Product not loading           | Check Product ID matches exactly                          |
| Purchase button does nothing  | Check StoreKit Configuration is set in scheme             |
| Purchased but still locked    | Call `checkEntitlements()` or check `Transaction.updates` |
| "Cannot connect to App Store" | Using real device without sandbox? Use StoreKit config    |

---

## Quick Reference

| Action              | How To                                          |
| ------------------- | ----------------------------------------------- |
| Reset one purchase  | Debug → StoreKit → Manage Transactions → Delete |
| Reset all purchases | Debug → StoreKit → Clear Purchase History       |
| Simulate failure    | StoreKitConfiguration.storekit → Enable error   |
| Test interrupted    | Debug → StoreKit → Enable Interrupted Purchases |
| View transactions   | Debug → StoreKit → Manage Transactions          |

---

## Files

- **StoreKit Configuration**: `Config/StoreKitConfiguration.storekit`
- **Store Manager**: `App/Store/StoreManager.swift`
- **IAP Documentation**: `Docs/IN_APP_PURCHASES.md`

---

## App Store Submission Guide

When you're ready to submit to the App Store, follow these detailed steps to configure your In-App Purchase in App Store Connect.

### Prerequisites

Before starting, ensure you have:

- [ ] An active Apple Developer Program membership ($99/year)
- [ ] Your app created in App Store Connect
- [ ] A Privacy Policy URL (required for apps with IAP)
- [ ] A Support URL for your app
- [ ] Bank and tax information set up in App Store Connect (Agreements, Tax, and Banking)

---

### Step 1: Create the In-App Purchase Product

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Click **My Apps** → Select **Life Wrapped**
3. In the left sidebar, click **Monetization** → **In-App Purchases**
4. Click the **+** button (or "Create" if first IAP)
5. Select **Non-Consumable** as the type
6. Fill in the details:

| Field              | Value                                |
| ------------------ | ------------------------------------ |
| **Reference Name** | Smartest AI                          |
| **Product ID**     | `com.jsayram.lifewrapped.smartestai` |

> ⚠️ **CRITICAL**: The Product ID must match EXACTLY what's in `StoreManager.swift`. This cannot be changed after creation!

7. Click **Create**

---

### Step 2: Configure Pricing

1. After creating the product, you'll be on the product detail page
2. Click **Add Pricing** (or the pricing section)
3. Select your **Price Tier**:
   - Tier 1 = $0.99
   - Tier 2 = $1.99 ← (Current test price)
   - Tier 3 = $2.99
   - Tier 5 = $4.99
   - etc.
4. Choose **Start Date**: Select when the price takes effect (usually "Today")
5. Optional: Set different prices for different countries
6. Click **Save**

---

### Step 3: Add Localization

At least one localization is **required** for review.

1. Scroll to **App Store Localization** section
2. Click **Add Localization** (or the + button)
3. Select **English (U.S.)** (or your primary language)
4. Fill in:

| Field            | Value                                                                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Display Name** | Smartest AI                                                                                                                                        |
| **Description**  | Unlock GPT-4, Claude, and other premium AI providers for the highest quality summaries and insights. Bring your own API keys for complete control. |

5. Click **Save**

**Optional**: Add more languages if your app is localized:

- Spanish: "IA Más Inteligente" / "Desbloquea GPT-4, Claude y otros proveedores de IA premium..."
- etc.

---

### Step 4: Add Review Information

This is **required** for Apple's review team to test your IAP.

1. Scroll to **Review Information** section
2. Add a **Review Screenshot**:
   - Take a screenshot of the purchase screen in your app
   - Should show the "Unlock Smartest AI" button or purchase confirmation
   - Resolution: At least 640x920 pixels
   - Format: PNG or JPEG
3. Add **Review Notes** (explain to Apple what this IAP does):

```
This in-app purchase unlocks the "Smartest AI" feature, which allows users to configure their own API keys for external AI providers (OpenAI GPT-4 or Anthropic Claude).

How it works:
1. User purchases "Smartest AI"
2. User goes to Settings → AI Settings → Smartest Configuration
3. User enters their own API key from OpenAI or Anthropic
4. AI summaries are now generated using the external provider

Note: The app is fully functional without this purchase using on-device AI. This is a premium upgrade for users who want the highest quality summaries.

To test:
1. Navigate to any Year Wrap or the AI Settings screen
2. Tap "Smartest AI" or the locked sparkle icon
3. Complete the purchase
4. The API configuration section will unlock
```

4. Click **Save**

---

### Step 5: Submit the IAP for Review

1. At the top of the IAP page, check the **Status** (should show "Missing Metadata" initially)
2. Once all required fields are filled, status changes to **Ready to Submit**
3. Click **Save** if you haven't already

**Two submission options:**

**Option A: Submit with App** (Recommended for first release)

- The IAP will be reviewed when you submit your app update
- Go to your app version → Submit for Review
- The IAP is automatically included

**Option B: Submit IAP Separately** (For adding IAP to existing app)

- In the IAP list, select the IAP
- Click **Submit for Review** at the top
- Can be approved before app update

---

### Step 6: App-Level Requirements

Ensure these are configured in your app's App Store listing:

#### Privacy Policy (Required)

1. Go to **App Information** in App Store Connect
2. Scroll to **Privacy Policy URL**
3. Enter your privacy policy URL (e.g., `https://yourwebsite.com/privacy`)

Your privacy policy should mention:

- What data the app collects (audio recordings, transcripts)
- That transcription is on-device
- That API keys are stored securely on-device
- That external AI (if used) sends transcript data to the provider

#### Support URL (Required)

1. In **App Information**
2. Enter your support URL (e.g., `https://yourwebsite.com/support` or a GitHub issues page)

---

### Step 7: App Privacy Labels

In App Store Connect → Your App → **App Privacy**:

For Life Wrapped with IAP, you'll likely need to declare:

| Data Type                        | Purpose                                   | Linked to User? |
| -------------------------------- | ----------------------------------------- | --------------- |
| **Purchases** → Purchase History | App Functionality                         | No              |
| **Audio Data** → Audio Data      | App Functionality                         | No              |
| **Identifiers** → Device ID      | App Functionality (if using for StoreKit) | No              |

**How to fill out:**

1. Click **Get Started** or **Edit**
2. Answer "Yes" to "Do you or your third-party partners collect data?"
3. Select applicable data types
4. For each type:
   - Select how it's used (App Functionality)
   - Indicate if it's linked to user identity (No, for privacy-first app)
   - Indicate if used for tracking (No)
5. Click **Publish**

---

### Step 8: Testing in Sandbox (Before Release)

Before submitting, test with real App Store Connect (not just Xcode StoreKit):

#### Create Sandbox Tester

1. In App Store Connect, go to **Users and Access**
2. Click **Sandbox** in the left sidebar
3. Click **Testers** → **+**
4. Fill in:
   - First Name: Test
   - Last Name: User
   - Email: `test-lifewrapped@example.com` (can be fake, but must be unique)
   - Password: Choose a secure password
   - Country: United States (or your primary market)
5. Click **Create**

#### Test on Real Device

1. On your iPhone/iPad: **Settings → App Store → Sign Out**
2. Run the app from Xcode (on device, not simulator)
3. Trigger a purchase in the app
4. When prompted, sign in with sandbox account credentials
5. Complete the purchase (no real charge)
6. Verify the feature unlocks correctly

> **Tip**: Don't sign into the main Settings app with the sandbox account - only use it when the App Store purchase sheet appears.

---

### Checklist Summary

```
□ Create IAP in App Store Connect
  □ Type: Non-Consumable
  □ Product ID: com.jsayram.lifewrapped.smartestai
  □ Reference Name: Smartest AI

□ Configure Pricing
  □ Select price tier
  □ Set start date

□ Add Localization (at least English)
  □ Display Name
  □ Description

□ Add Review Information
  □ Upload screenshot of purchase screen
  □ Write review notes explaining the feature

□ App-Level Setup
  □ Privacy Policy URL
  □ Support URL
  □ App Privacy labels configured

□ Testing
  □ Create sandbox tester account
  □ Test purchase on real device
  □ Test restore purchases
  □ Verify feature unlocks correctly

□ Submit
  □ IAP status shows "Ready to Submit"
  □ Submit with app or separately
```

---

### Common Rejection Reasons

| Reason                        | Solution                                                     |
| ----------------------------- | ------------------------------------------------------------ |
| **Missing restore purchases** | Ensure "Restore Purchases" button exists in Settings         |
| **IAP not clearly explained** | Add clear description of what user gets before purchase      |
| **No way to use without IAP** | Ensure free tier (On-Device AI) is fully functional          |
| **Price not displayed**       | Show price in the purchase button (e.g., "Unlock for $1.99") |
| **Missing privacy policy**    | Add privacy policy URL in App Store Connect                  |

---

### After Approval

Once your IAP is approved:

1. **Status** changes to "Approved" or "Ready for Sale"
2. It will be available when your app update goes live
3. Monitor **Sales and Trends** in App Store Connect for purchases
4. Check **App Analytics** for conversion rates

---

### Reference Links

- [App Store Connect](https://appstoreconnect.apple.com)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit/in-app_purchase)
- [In-App Purchase Configuration](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases)
- [App Store Review Guidelines - IAP](https://developer.apple.com/app-store/review/guidelines/#in-app-purchase)
