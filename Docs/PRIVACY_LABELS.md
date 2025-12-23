# Privacy Nutrition Labels - App Store

## Data Collection Overview

### Transcription: 100% On-Device ✅

- Audio recordings NEVER leave your device
- Speech recognition uses Apple's on-device framework
- All transcriptions stored locally in SQLite

### AI Summaries: User-Controlled 🔑

- **Optional**: Users can provide their own OpenAI/Anthropic API keys
- **Transparent**: Only external AI API calls use these keys
- **Your Control**: Keys stored securely in Keychain, managed by you
- **Offline Mode**: Basic summaries work without internet or API keys

### Network Activity

- **Without API Keys**: Zero network calls, 100% offline
- **With API Keys**: Only external AI API calls to OpenAI/Anthropic (using YOUR keys)
- **Your Choice**: You control if/when network access occurs

## Data Not Collected By Developer

We do NOT collect ANY of the following:

**Contact Info**

- ❌ Name
- ❌ Email Address
- ❌ Phone Number
- ❌ Physical Address
- ❌ Other User Contact Info

**Health & Fitness**

- ❌ Health
- ❌ Fitness

**Financial Info**

- ❌ Payment Info
- ❌ Credit Info
- ❌ Other Financial Info

**Location**

- ❌ Precise Location
- ❌ Coarse Location

**Sensitive Info**

- ❌ Sensitive Info

**Contacts**

- ❌ Contacts

**User Content**

- ❌ Emails or Text Messages
- ❌ Photos or Videos
- ❌ Audio Data (NOT sent to server - stays on device)
- ❌ Gameplay Content
- ❌ Customer Support
- ❌ Other User Content

**Browsing History**

- ❌ Browsing History

**Search History**

- ❌ Search History

**Identifiers**

- ❌ User ID
- ❌ Device ID

**Purchases**

- ❌ Purchase History

**Usage Data**

- ❌ Product Interaction
- ❌ Advertising Data
- ❌ Other Usage Data

**Diagnostics**

- ❌ Crash Data
- ❌ Performance Data
- ❌ Other Diagnostic Data

**Other Data**

- ❌ Other Data Types

## Data Linked to You: NONE

No data is linked to your identity.

## Data Used to Track You: NONE

No data is used to track you across apps and websites owned by other companies.

## Privacy Policy

Life Wrapped is designed with privacy as the core principle:

### On-Device Processing

- All audio recording happens locally
- Speech recognition uses Apple's on-device Speech framework
- Transcriptions never leave your device
- All data stored in local SQLite database

### AI Summaries (User-Controlled)

- **Transcription**: Always on-device, zero network calls
- **Basic Summaries**: On-device, zero network calls
- **Apple Intelligence**: On-device (iOS 18.1+), zero external network calls
- **External AI**: Optional feature using YOUR API keys
  - You provide OpenAI or Anthropic keys
  - Keys stored securely in Keychain
  - Network calls only to OpenAI/Anthropic APIs (not developer servers)
  - Automatic fallback to Basic summaries when offline

### Your Data, Your Control

- Export data anytime (JSON, Markdown)
- Delete all data with one tap
- No account required
- No sign-up process
- API keys optional and user-managed

### Verification

Users can verify our privacy claims:

1. Without API keys: Enable Airplane Mode → App works perfectly
2. With API keys: Network monitoring shows only OpenAI/Anthropic API calls (YOUR keys)
3. Transcription always works offline

## Permissions Required

### Microphone (Required)

- **Purpose:** Record your voice for journaling
- **When:** Only when actively recording
- **Storage:** Audio files stored locally in App Group container
- **Deletion:** Files deleted with recordings

### Speech Recognition (Required)

- **Purpose:** Transcribe audio to text on-device
- **When:** After recording stops
- **Method:** Apple Speech Framework with requiresOnDeviceRecognition=true
- **Network:** Zero - all transcription happens locally

### App Group (Internal)

- **Purpose:** Share data between main app and widget
- **Scope:** Only within Life Wrapped family
- **Network:** No external sharing

## Security

### Data Protection

- Files encrypted at rest (FileProtectionType.completeUntilFirstUserAuthentication)
- Database uses SQLCipher encryption (planned for v1.1)
- No transmission of sensitive data

### Code Signing

- App signed with Apple Developer certificate
- No third-party SDKs
- No analytics frameworks
- No tracking libraries

## Compliance

- ✅ GDPR Compliant (no personal data collection)
- ✅ CCPA Compliant (no personal data sale)
- ✅ COPPA Compliant (no data collection from children)
- ✅ Apple Privacy Guidelines Compliant

## Contact

For privacy questions: [Your Support Email]

**Last Updated:** December 22, 2025
