# Privacy Policy for Life Wrapped

**Last Updated: December 29, 2025**

## Overview

Life Wrapped is designed with privacy as a core principle. We believe your personal audio journal should remain truly personal.

---

## Data Collection

### What We Collect

**Nothing.** We do not collect, transmit, or store any of your personal data on our servers.

### What Stays on Your Device

- **Audio recordings** – Stored locally in your device's protected storage
- **Transcripts** – Generated on-device using Apple's Speech framework
- **AI summaries** – Processed on-device (Basic/Local AI) or via your own API keys
- **App settings** – Stored locally in UserDefaults and Keychain

---

## On-Device Processing

### Transcription (100% Local)

All speech-to-text transcription happens **entirely on your device** using Apple's Speech Recognition framework with `requiresOnDeviceRecognition = true`. No audio or transcript data is ever sent to Apple's servers or our servers.

### AI Summaries (Your Choice)

Life Wrapped offers multiple AI summarization options:

| Engine                  | Processing Location   | Data Sent |
| ----------------------- | --------------------- | --------- |
| **Basic**               | 100% On-Device        | None      |
| **Local AI**            | 100% On-Device        | None      |
| **Apple Intelligence**  | On-Device (iOS 18.1+) | None      |
| **External API (BYOK)** | Cloud                 | See below |

---

## Third-Party Services (Bring Your Own Key)

If you choose to use the **External API** option with your own API keys:

### What Happens

- Your transcript text is sent to **OpenAI** (api.openai.com) or **Anthropic** (api.anthropic.com)
- The connection uses **YOUR API keys**, not ours
- You are billed directly by the API provider

### Your Responsibility

By using the BYOK (Bring Your Own Key) feature, **you acknowledge and accept that**:

1. **You are solely responsible** for any costs incurred through your API provider
2. **You are solely responsible** for the personal data you send to these services
3. **You must review and agree to** OpenAI's or Anthropic's terms of service and privacy policies
4. **We have no control over** how these third-party providers handle your data

### Third-Party Privacy Policies

- [OpenAI Privacy Policy](https://openai.com/privacy)
- [Anthropic Privacy Policy](https://www.anthropic.com/privacy)

### Opting Out

If you prefer not to share data with external AI providers:

- Use the **Local AI** option (runs Phi-3.5 Mini entirely on-device)
- Use the **Basic** option (uses Apple's NaturalLanguage framework)
- Both options process data 100% locally with no network calls

---

## Data Storage & Security

### Local Storage

- All data is stored in your device's app sandbox
- Database uses SQLite with iOS file protection (`completeUntilFirstUserAuthentication`)
- API keys are stored in the iOS Keychain (hardware-encrypted)

### App Group (Widgets)

- Widget data is shared via a secure App Group container
- Only summary statistics are shared (no audio or full transcripts)

---

## Analytics & Tracking

**We do not use:**

- Analytics SDKs
- Crash reporting services
- Advertising networks
- User tracking
- Telemetry collection

---

## Your Rights

### Data Control

- **Export**: Export all your data anytime via Settings → Data
- **Delete**: Delete all recordings and transcripts with one tap
- **No Account Required**: Use the app without creating any account

### Data Portability

Your data is stored in standard formats (SQLite, audio files) and can be exported at any time.

---

## Children's Privacy

Life Wrapped does not knowingly collect information from children under 13. The app is rated 4+ and is intended for general audiences.

---

## Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by posting the new Privacy Policy on this page and updating the "Last Updated" date.

---

## Contact Us

If you have questions about this Privacy Policy, please:

- Open an issue on our [GitHub repository](https://github.com/jsayram/life-wrapped/issues)
- Review our [Terms of Service](terms)

---

## Summary

| Aspect                     | Status                    |
| -------------------------- | ------------------------- |
| Audio Recording            | 🟢 Local only             |
| Transcription              | 🟢 On-device only         |
| AI Summaries (Basic/Local) | 🟢 On-device only         |
| AI Summaries (BYOK)        | 🟡 Your choice, your keys |
| Analytics                  | 🟢 None                   |
| Tracking                   | 🟢 None                   |
| Cloud Sync                 | 🟢 None                   |
| Data Collection            | 🟢 None                   |

**Your journal. Your device. Your privacy.**
