# Privacy Nutrition Labels - App Store

## Data Collection Overview

The App Store label is **Data Not Collected**. The developer has no servers and receives nothing. The one feature that sends data off the device, Cloud AI, sends it straight from the device to the user's own OpenAI or Anthropic account under the user's own API key.

### Transcription: on-device

- Audio recordings never leave the device
- Speech recognition uses Apple's Speech framework with `requiresOnDeviceRecognition = true`
- Transcripts are stored locally in SQLite

### Summaries: user-controlled

- **Key Sentences, Offline AI and Apple Intelligence** make summaries on the device and send nothing
- **Cloud AI** (optional one-time purchase) sends text, never audio, to the provider the user connects: a recording's transcript and Work or Personal label, the first 400 characters of a summary for its title, and recording summaries, dates, labels and notes for month summaries and Year Wrap
- API keys are stored in the Keychain and only used to authenticate the user's own requests

### Network activity

- **Without an API key:** no network use except the optional Offline AI model download (Hugging Face) and App Store purchases
- **With an API key and Cloud AI chosen:** requests to api.openai.com or api.anthropic.com, plus a connectivity check to www.apple.com before using Cloud AI (no journal data)
- **Background processing (1.3):** a `BGProcessingTask` finishes ended months while the device charges. It uses the chosen engine and sends the same month text as the foreground path, and only when Cloud AI is chosen. No new data types or destinations
- The full list is on the [privacy policy](https://jsayram.github.io/life-wrapped/privacy)

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

The published policy is at [jsayram.github.io/life-wrapped/privacy](https://jsayram.github.io/life-wrapped/privacy), and a short version is in the app under Settings, then Privacy policy. Keep both in step with this page.

### Your data, your control

- Export anytime as JSON, Markdown or PDF (no audio)
- Delete one year or everything from Settings, then Data
- No account and no sign-up
- API keys are optional and managed by the user

### Verification

1. Without an API key, turn on Airplane Mode: recording, transcription, on-device summaries, History, Overview and export all work
2. With Cloud AI set up, a network monitor shows requests only to the chosen provider and the www.apple.com connectivity check
3. Transcription always works offline

## Permissions Required

### Microphone (required)

- **Purpose:** Record the user's voice for journaling
- **When:** Only while recording
- **Storage:** Audio files stored locally in the App Group container
- **Deletion:** Files are deleted with their recordings

### Speech Recognition (required)

- **Purpose:** Transcribe audio to text on the device
- **When:** Part by part, while recording and right after
- **Method:** Apple Speech framework with `requiresOnDeviceRecognition = true`
- **Network:** None; iOS may download on-device speech assets for a language once

### App Group (internal)

- **Purpose:** Share a few numbers with the widget (streak, today's recording count, minutes, words, last recording time)
- **Scope:** Only Life Wrapped and its widget
- **Network:** None

## Security

### Data protection

- The database folder uses iOS file protection (`FileProtectionType.completeUntilFirstUserAuthentication`)
- The database is not encrypted beyond iOS file protection
- API keys are stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`)

### Code

- No analytics, crash reporting, advertising or tracking SDKs
- The only third-party libraries are MLX (ml-explore) and Hugging Face swift-transformers, used to run the optional Offline AI model on the device

## Compliance

- ✅ GDPR: no personal data is collected by the developer
- ✅ CCPA: no personal data is sold or shared by the developer
- ✅ COPPA: no data is collected from children
- ✅ App Store privacy label: Data Not Collected

## Contact

Privacy questions: [open an issue](https://github.com/jsayram/life-wrapped/issues)

**Last Updated:** September 27, 2026
