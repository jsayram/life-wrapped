# Life Wrapped - App Review Guide

**Version:** 1.0  
**Date:** December 31, 2025  
**Developer:** Jose Ramirez-Villa  
**Contact:** jsayram@Gmail.com

---

## Quick Overview

**Life Wrapped** is a privacy-first audio journaling app that records voice memos, transcribes them on-device, and provides AI-powered summaries and insights.

**Key Differentiator:** All transcription happens 100% on-device using Apple's Speech framework. No audio or transcript data ever leaves the user's device.

---

## No Sign-In Required

This app does **not require user authentication**. Users can immediately start recording and using all core features without creating an account.

---

## Core Features to Test

### 1. Recording Audio

- Tap the **microphone button** to start recording
- Tap again to stop
- Recordings are automatically chunked for efficient processing

### 2. On-Device Transcription

- After recording, transcription begins automatically
- Uses Apple Speech framework with `requiresOnDeviceRecognition = true`
- **No internet required** for transcription

### 3. AI Summaries (Multiple Options)

The app offers 4 AI summarization engines:

| Engine                 | Internet Required | Notes                                    |
| ---------------------- | ----------------- | ---------------------------------------- |
| **Basic**              | No                | Built-in NLP, always works               |
| **Local AI**           | Download only     | Phi-3.5 model (~2.1GB one-time download) |
| **Apple Intelligence** | No                | iOS 18.1+, A17 Pro/M1+ devices           |
| **External API**       | Yes               | User provides their own API keys         |

### 4. History & Insights

- View all past recordings in the History tab
- See daily/weekly/monthly insights
- Search through transcripts

---

## Permissions Requested

| Permission             | Purpose                 | When Requested          |
| ---------------------- | ----------------------- | ----------------------- |
| **Microphone**         | Record audio            | First recording attempt |
| **Speech Recognition** | On-device transcription | First transcription     |

**Note:** All speech recognition is configured for on-device only. No audio is sent to Apple's servers.

---

## Export Compliance / Encryption

**This app uses only exempt encryption.**

| Encryption Type            | Usage                                                                  |
| -------------------------- | ---------------------------------------------------------------------- |
| **HTTPS/TLS**              | Standard encryption for optional external API calls (OpenAI/Anthropic) |
| **iOS Keychain**           | Secure storage of user-provided API keys                               |
| **SQLite File Protection** | Apple's built-in file encryption                                       |

- ✅ `ITSAppUsesNonExemptEncryption = NO` is set in Info.plist
- ✅ No proprietary encryption algorithms
- ✅ No custom cryptographic implementations
- ✅ All encryption uses Apple's standard frameworks or HTTPS

**Classification:** Standard encryption exempt from export regulations.

---

## Optional Features (Internet Required)

These features are optional and only work if the user chooses to enable them:

### External AI API (Bring Your Own Key)

- Users can optionally add their own OpenAI or Anthropic API keys
- Keys are stored securely in the iOS Keychain
- This is the **only feature** that sends data to external servers
- Users must explicitly configure this in Settings

### Local AI Model Download

- Users can download a local AI model (~2.1GB) for on-device summarization
- One-time download from HuggingFace
- After download, works completely offline

---

## App Flow Walkthrough

1. **Launch App** → Recording tab appears
2. **Tap Record** → Microphone permission requested (first time)
3. **Speak** → Audio is recorded and chunked automatically
4. **Stop Recording** → Transcription begins automatically
5. **View Transcript** → Full text with word-level timing
6. **AI Summary** → Automatic summary generation (using selected engine)
7. **History Tab** → Browse all past recordings
8. **Insights Tab** → View patterns and analytics
9. **Settings** → Configure AI engine, export data

---

## Privacy Highlights

- ✅ **No tracking or analytics**
- ✅ **No third-party SDKs** (except optional user-configured APIs)
- ✅ **No data collection** — we don't have servers
- ✅ **All data stored locally** in encrypted SQLite database
- ✅ **Speech Recognition** uses `requiresOnDeviceRecognition = true`
- ✅ **Users can export and delete all data** anytime

---

## Testing Recommendations

### Quick Test (5 minutes)

1. Open app
2. Record a 30-second voice memo
3. Wait for transcription (10-20 seconds)
4. View the transcript and summary
5. Check History tab

### Full Test (15 minutes)

1. Record 2-3 voice memos
2. Test search in History
3. Try editing a transcript
4. Mark a session as favorite
5. Export a transcript
6. Check Insights tab
7. Review Settings options

---

## Known Behaviors (Not Bugs)

| Behavior                             | Explanation                                |
| ------------------------------------ | ------------------------------------------ |
| First transcription is slower        | Speech model downloads on first use        |
| "Processing" shows for a few seconds | Normal transcription time                  |
| Local AI download is large           | ~2.1GB model file, optional feature        |
| Some features grayed out             | Depend on iOS version or device capability |

---

## Device Requirements

- **iOS:** 18.0+
- **Devices:** iPhone (all iOS 18 compatible devices)
- **Storage:** ~100MB app + optional 2.1GB for Local AI
- **Apple Intelligence:** Requires iOS 18.1+, A17 Pro or M1+ chip

---

## Support Information

- **Support URL:** https://jsayram.github.io/life-wrapped/support
- **Privacy Policy:** https://jsayram.github.io/life-wrapped/privacy
- **Contact:** jsayram@Gmail.com

---

## Additional Notes for Reviewers

1. **No backend servers** — This is a fully client-side app
2. **No account system** — All data is local to the device
3. **No in-app purchases yet** — V1 is completely free
4. **Privacy is the core feature** — On-device processing is intentional

Thank you for reviewing Life Wrapped! Please reach out if you have any questions.

---

_Document prepared for Apple App Review Team_
