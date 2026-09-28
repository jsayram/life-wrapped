# Life Wrapped - App Review Guide

**Version:** 1.1  
**Date:** September 27, 2026  
**Developer:** Jose Ramirez-Villa  
**Contact:** jsayram@Gmail.com

---

## Quick Overview

**Life Wrapped** is a privacy-first audio journaling app that records voice memos, transcribes them on-device, and provides AI-powered summaries and insights.

**Key Differentiator:** All transcription happens on the device using Apple's Speech framework. Audio never leaves the device, and journal text leaves it only if the user sets up the optional Cloud AI feature with their own API key.

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

The app offers 4 summary engines, chosen in Settings, then AI & Summaries:

| Engine                 | Internet Required | Notes                                    |
| ---------------------- | ----------------- | ---------------------------------------- |
| **Key Sentences**      | No                | Built-in NLP, always works               |
| **Offline AI**         | Download only     | Qwen3 4B (~2.3 GB), or Qwen3 1.7B (~1.0 GB) on 4 GB devices, one-time download |
| **Apple Intelligence** | No                | iOS 26 or later on a device with Apple Intelligence turned on |
| **Cloud AI**           | Yes               | One-time in-app purchase; the user provides their own OpenAI or Anthropic API key |

### 4. History, Overview & Year Wrap

- View all past recordings in the History tab (on iPad, the list and the recording sit side by side)
- Search titles, notes and transcripts
- On the Overview tab, see each recording's summary for today and yesterday, a summary of each month, and the Year Wrap
- Year Wrap: a year in review built from the month summaries, with any summary engine (Key Sentences needs no model)

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

### Cloud AI (Bring Your Own Key)

- Unlocked with a one-time, non-consumable in-app purchase ($2.99, product ID `com.jsayram.lifewrapped.smartestai`). There is no subscription
- Users then add their own OpenAI or Anthropic API key; keys are stored in the iOS Keychain
- This is the **only feature** that sends journal text to external servers, and only to the provider the user connects
- Users must explicitly configure this in Settings, then AI & Summaries

### Offline AI Model Download

- Users can download an AI model (~2.3 GB, or ~1.0 GB on 4 GB devices) for on-device summaries
- One-time download from Hugging Face; no journal data is sent
- After download, works completely offline

---

## App Flow Walkthrough

1. **Launch App** → Recording tab appears
2. **Tap Record** → Microphone permission requested (first time)
3. **Speak** → Audio is recorded and chunked automatically
4. **Stop Recording** → Transcription begins automatically
5. **View Transcript** → Full text by part, with playback
6. **AI Summary** → Automatic summary generation (using selected engine)
7. **History Tab** → Browse all past recordings
8. **Overview Tab** → Today's and yesterday's recording summaries, month summaries and the Year Wrap
9. **Settings** → Choose the summary engine, see Statistics, export data

---

## Privacy Highlights

- ✅ **No tracking or analytics**
- ✅ **No third-party analytics or ad SDKs.** The only third-party libraries are MLX and Hugging Face swift-transformers, which run the optional Offline AI model on the device
- ✅ **No data collection** — we don't have servers
- ✅ **All data stored locally** in a SQLite database protected by iOS file protection
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
3. Try editing a transcript and adding notes
4. Mark a recording as favorite
5. Export data (Settings, then Data)
6. Check the Overview tab and Settings, then Statistics
7. Review Settings options. Under Purchases, Cloud AI opens the purchase sheet, which also has Restore purchases and Redeem code

---

## Known Behaviors (Not Bugs)

| Behavior                             | Explanation                                |
| ------------------------------------ | ------------------------------------------ |
| First transcription is slower        | Speech model downloads on first use        |
| "Processing" shows for a few seconds | Normal transcription time                  |
| Offline AI download is large         | ~2.3 GB model file, optional feature       |
| Some features grayed out             | Depend on iOS version or device capability |

---

## Device Requirements

- **iOS / iPadOS:** 18.0+
- **Devices:** iPhone and iPad (all iOS 18 compatible devices)
- **Storage:** ~100MB app + optional 2.3 GB for Offline AI
- **Apple Intelligence:** Requires iOS 26 or later on a device that supports it, with Apple Intelligence turned on

---

## Support Information

- **Support URL:** https://jsayram.github.io/life-wrapped/support
- **Privacy Policy:** https://jsayram.github.io/life-wrapped/privacy
- **Contact:** jsayram@Gmail.com

---

## Additional Notes for Reviewers

1. **No backend servers** — This is a fully client-side app
2. **No account system** — All data is local to the device
3. **One optional in-app purchase** — Cloud AI, a one-time $2.99 unlock; everything else is free
4. **Privacy is the core feature** — On-device processing is intentional

Thank you for reviewing Life Wrapped! Please reach out if you have any questions.

---

_Document prepared for Apple App Review Team_
