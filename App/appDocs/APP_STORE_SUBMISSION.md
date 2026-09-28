# App Store Submission Guide for Life Wrapped

> Complete step-by-step guide to deploy Life Wrapped to TestFlight and the App Store.

**Last Updated:** September 27, 2026. For paste-ready listing copy (subtitle, description, keywords, What's New, in-app purchase text), see `APP_STORE_READY.md`.

---

## 📋 Table of Contents

1. [Prerequisites](#prerequisites)
2. [Phase 1: Apple Developer Program Setup](#phase-1-apple-developer-program-setup)
3. [Phase 2: App Store Connect Configuration](#phase-2-app-store-connect-configuration)
4. [Phase 3: Xcode Project Preparation](#phase-3-xcode-project-preparation)
5. [Phase 4: Build & Archive](#phase-4-build--archive)
6. [Phase 5: Upload to App Store Connect](#phase-5-upload-to-app-store-connect)
7. [Phase 6: TestFlight Beta Testing](#phase-6-testflight-beta-testing)
8. [Phase 7: App Store Submission](#phase-7-app-store-submission)
9. [Required Assets Checklist](#required-assets-checklist)
10. [Common Issues & Solutions](#common-issues--solutions)

---

## Prerequisites

### Required Tools & Accounts

| Tool/Account                   | Purpose                              | Cost                    |
| ------------------------------ | ------------------------------------ | ----------------------- |
| **Xcode 26+**                  | Building & archiving                 | Free                    |
| **Apple Developer Account**    | Distribution                         | $99/year                |
| **App Store Connect**          | Manage apps, TestFlight, submissions | Free (with Dev Account) |
| **Transporter App** (optional) | Alternative upload method            | Free                    |

### Project Requirements

- [ ] Bundle Identifier configured: `com.jsayram.lifewrapped`
- [ ] App Icons in all required sizes
- [ ] Privacy Policy URL
- [ ] Marketing assets (screenshots, app preview videos)

---

## Phase 1: Apple Developer Program Setup

### Step 1.1: Enroll in Apple Developer Program

1. **Go to:** [developer.apple.com/programs](https://developer.apple.com/programs/)
2. Click **"Enroll"**
3. Sign in with your Apple ID
4. Choose enrollment type:
   - **Individual** — For personal apps ($99/year)
   - **Organization** — For company apps ($99/year, requires D-U-N-S number)
5. Complete payment
6. Wait for enrollment approval (usually 24-48 hours)

### Step 1.2: Accept Agreements

1. **Go to:** [App Store Connect](https://appstoreconnect.apple.com)
2. Navigate to **Agreements, Tax, and Banking**
3. Accept the latest **Paid Applications Agreement** (required even for free apps)
4. Complete tax and banking information if you plan to monetize

---

## Phase 2: App Store Connect Configuration

### Step 2.1: Create App Record

1. **Go to:** [App Store Connect](https://appstoreconnect.apple.com)
2. Click **Apps** in the sidebar
3. Click the **"+"** button → **"New App"**
4. Fill in the required information:

| Field                | Value                     | Notes                                       |
| -------------------- | ------------------------- | ------------------------------------------- |
| **Platforms**        | iOS                       | iPhone and iPad (there is no watchOS app)   |
| **Name**             | Life Wrapped              | Your app's display name (max 30 characters) |
| **Primary Language** | English (US)              | Or your preferred language                  |
| **Bundle ID**        | `com.jsayram.lifewrapped` | Must match Xcode project                    |
| **SKU**              | `lifewrapped-v1`          | Unique identifier (internal use)            |
| **User Access**      | Full Access               | Or Limited if you have team members         |

5. Click **"Create"**

### Step 2.2: Configure App Information

Navigate to your app in App Store Connect and fill in:

#### General Information

- **App Name:** Life Wrapped
- **Subtitle:** Private audio journal (max 30 characters)
- **Category:** Primary: Productivity
- **Content Rights:** Confirm you own or have rights to all content

#### Privacy Policy

- **URL:** `https://jsayram.github.io/life-wrapped/privacy` (REQUIRED)
- Must be publicly accessible

---

## Phase 3: Xcode Project Preparation

### Step 3.1: Configure Signing & Capabilities

1. Open `LifeWrapped.xcworkspace` in Xcode
2. Select the **LifeWrapped** target
3. Go to **Signing & Capabilities** tab
4. Ensure settings are correct:

```
Team: Your Developer Team
Bundle Identifier: com.jsayram.lifewrapped
Signing Certificate: Apple Distribution
Provisioning Profile: Automatic
```

### Step 3.2: Verify Build Settings

1. Select **LifeWrapped** project (not target)
2. Go to **Build Settings**
3. Verify:

| Setting                            | Value            |
| ---------------------------------- | ---------------- |
| **iOS Deployment Target**          | 18.0             |
| **Build Active Architecture Only** | No (for Release) |
| **Swift Language Version**         | 6                |

### Step 3.3: Update Version & Build Number

1. Select **LifeWrapped** target
2. Go to **General** tab
3. Set:
   - **Version:** the marketing version (currently `1.3`)
   - **Build:** set automatically by Xcode Cloud for each upload (see `XCODE_CLOUD_BUILD.md`)

> **Tip:** Build numbers must be unique for each upload. Use integers: 1, 2, 3...

### Step 3.4: Configure App Icons

Verify all required icons exist in `App/Resources/Assets.xcassets/AppIcon.appiconset/`:

| Size      | Scale | Purpose          |
| --------- | ----- | ---------------- |
| 1024×1024 | 1x    | App Store        |
| 180×180   | 3x    | iPhone App       |
| 120×120   | 2x    | iPhone App       |
| 167×167   | 2x    | iPad Pro App     |
| 152×152   | 2x    | iPad App         |
| 76×76     | 1x    | iPad App         |
| 120×120   | 2x    | Spotlight iPhone |
| 80×80     | 2x    | Spotlight iPad   |
| 40×40     | 1x    | Spotlight iPad   |
| 87×87     | 3x    | Settings iPhone  |
| 58×58     | 2x    | Settings         |
| 29×29     | 1x    | Settings         |

### Step 3.5: Privacy Manifest (Required for iOS 17+)

Ensure `App/Resources/PrivacyInfo.xcprivacy` contains accurate privacy declarations for:

- **NSPrivacyTracking:** false
- **NSPrivacyTrackingDomains:** [] (empty if no tracking)
- **NSPrivacyCollectedDataTypes:** Appropriate declarations
- **NSPrivacyAccessedAPITypes:** Required API reason declarations

---

## Phase 4: Build & Archive

### Step 4.1: Select Destination

1. In Xcode, select **Product** → **Destination** → **Any iOS Device (arm64)**
2. Or use the destination picker in the toolbar

### Step 4.2: Create Archive

**Option A: Using Xcode UI**

1. Select **Product** → **Archive**
2. Wait for build to complete (5-15 minutes)
3. Organizer window opens automatically with your archive

**Option B: Using Command Line**

```bash
# Navigate to project directory
cd /Users/jramirez/Git/life-wrapped

# Archive the app
xcodebuild -workspace LifeWrapped.xcworkspace \
  -scheme LifeWrapped \
  -sdk iphoneos \
  -configuration Release \
  -archivePath ./build/LifeWrapped.xcarchive \
  archive
```

### Step 4.3: Validate Archive (Recommended)

1. In the **Organizer** window, select your archive
2. Click **"Validate App"**
3. Choose **"App Store Connect"** distribution
4. Review any warnings or errors
5. Fix issues before proceeding

---

## Phase 5: Upload to App Store Connect

### Step 5.1: Distribute App

1. In **Organizer**, select your validated archive
2. Click **"Distribute App"**
3. Choose distribution method:
   - **TestFlight & App Store** — Standard submission
   - **TestFlight Internal Only** — Restricts to team members only

### Step 5.2: Configure Distribution Options

| Option                               | Recommended Setting               |
| ------------------------------------ | --------------------------------- |
| **Upload your app's symbols**        | ✅ Checked (for crash reports)    |
| **Manage version and build number**  | ✅ Checked (auto-increment)       |
| **Strip Swift symbols**              | ✅ Checked (reduces app size)     |
| **TestFlight internal testing only** | ❌ Unchecked (unless intentional) |

### Step 5.3: Complete Upload

1. Select **"Automatically manage signing"**
2. Review the summary
3. Click **"Upload"**
4. Wait for upload and processing (10-30 minutes)

### Step 5.4: Alternative: Use Transporter App

1. Download **Transporter** from Mac App Store
2. Export your archive as an `.ipa`:
   ```bash
   xcodebuild -exportArchive \
     -archivePath ./build/LifeWrapped.xcarchive \
     -exportPath ./build/export \
     -exportOptionsPlist ExportOptions.plist
   ```
3. Drag the `.ipa` file into Transporter
4. Click **"Deliver"**

---

## Phase 6: TestFlight Beta Testing

### Step 6.1: Wait for Processing

After upload, your build goes through processing:

1. **Upload Complete** → Build appears in App Store Connect
2. **Processing** → Apple validates and processes (15-60 minutes)
3. **Ready to Submit** → Build available for TestFlight

> Check status at: **App Store Connect** → **Your App** → **TestFlight** tab

### Step 6.2: Provide Test Information

1. Go to **App Store Connect** → **Your App** → **TestFlight**
2. Fill in **Test Information**:

| Field                           | Value                                   |
| ------------------------------- | --------------------------------------- |
| **Beta App Description**        | Description of what testers should test |
| **Feedback Email**              | your@email.com                          |
| **Beta App Review Information** | Any notes for Apple reviewers           |
| **What to Test**                | Specific features to focus on           |

### Step 6.3: Export Compliance

For your first build, you must answer:

> "Does your app use encryption?"

**For Life Wrapped:**

- If using **HTTPS only** → Select "Yes" → "Only uses standard encryption"
- Mark as **exempt** from export compliance documentation

### Step 6.4: Add Internal Testers

Internal testers = App Store Connect users with access to your app (up to 100)

1. Go to **TestFlight** → **Internal Testing**
2. Click **"+"** to create a group
3. Name it (e.g., "Core Team")
4. Add testers by email (must have App Store Connect access)
5. Enable **"Automatic Distribution"** to send new builds automatically

### Step 6.5: Add External Testers

External testers = Anyone with an email (up to 10,000)

1. Go to **TestFlight** → **External Testing**
2. Click **"+"** to create a group
3. Name it (e.g., "Beta Testers")
4. Add builds to the group
5. **First external build requires Beta App Review** (24-48 hours)
6. Add testers via email or public link

### Step 6.6: Public Link (Optional)

1. In your external testing group, enable **"Public Link"**
2. Set maximum testers (1-10,000)
3. Share the link: `https://testflight.apple.com/join/XXXXXX`

### Step 6.7: Tester Experience

Testers will:

1. Receive email invitation
2. Download **TestFlight** app from App Store
3. Accept the invitation
4. Install your beta app
5. Provide feedback via screenshots or TestFlight feedback

> **Note:** TestFlight builds expire after **90 days**

---

## Phase 7: App Store Submission

### Step 7.1: Complete App Store Listing

Go to **App Store Connect** → **Your App** → **App Store** tab

#### Required Fields

| Section                    | Field              | Requirements                        |
| -------------------------- | ------------------ | ----------------------------------- |
| **App Information**        | Name               | Max 30 characters                   |
|                            | Subtitle           | Max 30 characters                   |
|                            | Privacy Policy URL | Must be publicly accessible         |
|                            | Category           | Primary + Optional Secondary        |
| **Version Information**    | Description        | Max 4000 characters                 |
|                            | Keywords           | Max 100 characters, comma-separated |
|                            | Support URL        | Must be valid                       |
|                            | Marketing URL      | Optional but recommended            |
| **Pricing & Availability** | Price              | Free or paid tier                   |
|                            | Availability       | Countries/regions                   |
| **App Review**             | Contact Info       | Phone & email for reviewer          |
|                            | Demo Account       | If login required                   |
|                            | Notes              | Any special instructions            |

### Step 7.2: Upload Screenshots

**Required screenshot sizes:**

#### iPhone Screenshots (REQUIRED)

| Device      | Dimensions                 | Required      |
| ----------- | -------------------------- | ------------- |
| iPhone 6.9" | 1320 × 2868 or 2868 × 1320 | Yes           |
| iPhone 6.7" | 1290 × 2796 or 2796 × 1290 | Yes (or 6.5") |
| iPhone 6.5" | 1284 × 2778 or 2778 × 1284 | Yes (or 6.7") |
| iPhone 5.5" | 1242 × 2208 or 2208 × 1242 | Yes           |

#### iPad Screenshots (if iPad support)

| Device         | Dimensions                 |
| -------------- | -------------------------- |
| iPad Pro 13"   | 2064 × 2752 or 2752 × 2064 |
| iPad Pro 12.9" | 2048 × 2732 or 2732 × 2048 |

#### Apple Watch Screenshots (if watchOS support)

| Device         | Dimensions |
| -------------- | ---------- |
| Series 10 46mm | 416 × 496  |
| Ultra 2        | 410 × 502  |

**Tips:**

- Format: JPEG or PNG
- 1-10 screenshots per device size (Life Wrapped uses all 10; the files and their order are in `APP_STORE_READY.md`)
- Can include app preview videos (15-30 seconds)

### Step 7.3: App Privacy (Data Collection)

1. Go to **App Privacy** section
2. Answer questionnaire about data collection:

**For Life Wrapped:** choose **Data Not Collected**. The developer receives no data: audio and transcripts stay on the device, and Cloud AI sends text straight from the device to the user's own OpenAI or Anthropic account with the user's own key. The reasoning and details are in `PRIVACY_LABELS.md`.

### Step 7.4: Age Rating

Complete the questionnaire. Life Wrapped likely qualifies for:

- **4+** — No objectionable content
- Adjust based on your specific content

### Step 7.5: Select Build

1. In **Build** section, click **"+"**
2. Select your processed build from the list
3. If build doesn't appear, check **TestFlight** → **Builds** for processing status

### Step 7.6: Submit for Review

1. Review all sections for completeness (green checkmarks)
2. Click **"Submit for Review"**
3. Answer any final questions:
   - Content rights declaration
   - Export compliance
   - Advertising identifier usage

### Step 7.7: App Review Process

| Status                 | Meaning        | Typical Duration |
| ---------------------- | -------------- | ---------------- |
| **Waiting for Review** | In queue       | 24-48 hours      |
| **In Review**          | Being reviewed | 1-24 hours       |
| **Approved**           | Passed review  | —                |
| **Rejected**           | Issues found   | —                |

**If Rejected:**

1. Read the rejection reason in Resolution Center
2. Fix issues and resubmit
3. Reply to reviewer if clarification needed

### Step 7.8: Release to App Store

After approval, choose release method:

| Method                | Description                          |
| --------------------- | ------------------------------------ |
| **Manual Release**    | You control when app goes live       |
| **Automatic Release** | Goes live immediately after approval |
| **Scheduled Release** | Pick a specific date/time            |

---

## Required Assets Checklist

### Before First Submission

- [ ] **Apple Developer Account** — Enrolled and active
- [ ] **Bundle Identifier** — Registered in Apple Developer Portal
- [ ] **App Icons** — All sizes in Assets.xcassets
- [ ] **Privacy Policy** — Hosted URL
- [ ] **Terms of Service** — Hosted URL (optional but recommended)
- [ ] **Support URL** — Website or email address

### App Store Listing

- [ ] **App Name** — Max 30 characters
- [ ] **Subtitle** — Max 30 characters
- [ ] **Description** — Max 4000 characters
- [ ] **Keywords** — Max 100 characters
- [ ] **Screenshots** — iPhone (required), iPad & Watch (if supported)
- [ ] **App Preview Video** — Optional, 15-30 seconds

### For App Review

- [ ] **Demo Account** — If app requires login
- [ ] **Contact Information** — Phone and email
- [ ] **Notes for Reviewer** — Explain non-obvious features
- [ ] **Privacy Manifest** — iOS 17+ requirement

---

## Common Issues & Solutions

### Build Upload Failures

| Issue                            | Solution                                              |
| -------------------------------- | ----------------------------------------------------- |
| **Invalid binary**               | Check architecture settings, ensure arm64 is included |
| **Missing provisioning profile** | Re-download in Xcode → Preferences → Accounts         |
| **Icon missing**                 | Verify all icon sizes exist without transparency      |
| **Build number duplicate**       | Increment build number in Xcode                       |

### App Review Rejections

| Reason                   | Solution                                         |
| ------------------------ | ------------------------------------------------ |
| **Crashes on launch**    | Test on physical device before submission        |
| **Incomplete metadata**  | Fill all required fields, add demo account       |
| **Placeholder content**  | Remove "Lorem ipsum" or test data                |
| **Privacy concerns**     | Add proper permission descriptions in Info.plist |
| **Guideline 4.3 (Spam)** | Ensure app provides unique value                 |

### TestFlight Issues

| Issue                              | Solution                                   |
| ---------------------------------- | ------------------------------------------ |
| **Testers not receiving invite**   | Check spam folder, verify email            |
| **Build stuck processing**         | Wait up to 1 hour, or delete and re-upload |
| **"Update Available" not showing** | Force close TestFlight app, refresh        |

---

## Quick Reference: Key URLs

| Resource                       | URL                                                                                                                                                                      |
| ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **App Store Connect**          | [appstoreconnect.apple.com](https://appstoreconnect.apple.com)                                                                                                           |
| **Apple Developer Account**    | [developer.apple.com/account](https://developer.apple.com/account)                                                                                                       |
| **Certificates & Profiles**    | [developer.apple.com/account/resources](https://developer.apple.com/account/resources/certificates/list)                                                                 |
| **App Review Guidelines**      | [developer.apple.com/app-store/review/guidelines](https://developer.apple.com/app-store/review/guidelines/)                                                              |
| **Human Interface Guidelines** | [developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines/)                                                  |
| **Screenshot Specs**           | [developer.apple.com/help/app-store-connect/reference/screenshot-specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications) |
| **TestFlight Overview**        | [developer.apple.com/testflight](https://developer.apple.com/testflight/)                                                                                                |

---

## Timeline Estimate

| Phase                        | Duration                |
| ---------------------------- | ----------------------- |
| Developer Program Enrollment | 24-48 hours             |
| App Store Connect Setup      | 1-2 hours               |
| Xcode Preparation            | 30 min - 1 hour         |
| Build & Archive              | 15-30 minutes           |
| Upload & Processing          | 30-60 minutes           |
| TestFlight Testing           | 1-14 days (your choice) |
| App Review                   | 24-48 hours             |
| **Total (first submission)** | **3-5 days minimum**    |

---

## Additional Resources

- [WWDC23: Simplify distribution in Xcode and Xcode Cloud](https://developer.apple.com/videos/play/wwdc2023/10224)
- [Tech Talks: Get started with TestFlight](https://developer.apple.com/videos/play/tech-talks/110343/)
- [Tech Talks: Get started with app discovery](https://developer.apple.com/videos/play/tech-talks/110358/)

---

**Built with ❤️ for Life Wrapped**
