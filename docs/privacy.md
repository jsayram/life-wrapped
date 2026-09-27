---
title: Privacy policy
---

<p class="overline">Privacy</p>

# Privacy policy

**Last updated: September 26, 2026**

Life Wrapped is designed with privacy as a core principle. Your personal audio journal should stay personal.

---

## Data collection

### What we collect

**Nothing.** We do not collect, transmit or store any of your personal data on our servers. There is no account to create.

### What stays on your device

- **Audio recordings**, stored in your device's protected app storage
- **Transcripts**, generated on-device with Apple's Speech framework
- **AI summaries**, made on-device (Basic, Smart, Smarter) or through your own API key (Smartest)
- **App settings**, stored locally in UserDefaults and the Keychain

---

## On-device processing

### Transcription (always on-device)

All speech-to-text happens on your device using Apple's Speech framework with `requiresOnDeviceRecognition = true`. Your audio is never sent to Apple, to us or to anyone else.

### AI summaries (your choice)

| Summary quality | Engine | Where it runs | Data sent |
| --- | --- | --- | --- |
| **Basic** | Key sentences with Apple's NaturalLanguage framework | On your device | None |
| **Smart** | Qwen3 4B (Qwen3 1.7B on devices with 4 GB of memory), downloaded once | On your device | None |
| **Smarter** | Apple Intelligence (iOS 26 or later, supported devices) | On your device | None |
| **Smartest** | OpenAI or Anthropic, with your own API key | Cloud | The text being summarized, see below |

---

## Network connections

Life Wrapped only goes online in these cases:

- **Downloading the Smart model.** If you choose to download it, the model files come from Hugging Face (huggingface.co). No journal data is sent.
- **Purchases.** Unlocking Smartest AI and restoring purchases go through Apple's App Store.
- **Smartest summaries.** If you choose Smartest, the text being summarized is sent to OpenAI (api.openai.com) or Anthropic (api.anthropic.com) using your own API key. Before each summary request the app makes a quick connection check to apple.com, which sends no journal data.
- **Testing your API key.** The Test button sends a short test message, not your journal, to the provider you picked.

Everything else works offline. Links in the app such as "Get API key" and "View models" open in your web browser.

---

## Third-party services (bring your own key)

If you choose **Smartest** with your own API key:

### What happens

- The text being summarized is sent to **OpenAI** or **Anthropic**, whichever you connect. For a single recording this is its transcript, its Work or Personal label, and your notes if you choose to include them when regenerating. For longer periods and for Year Wrap, it is your earlier summaries for that period
- The request goes to the model you enter in Settings, then AI & Summaries
- The connection uses **your API key**, not ours
- You are billed directly by the API provider
- Your audio is never sent

### Your responsibility

By using the bring-your-own-key feature, **you acknowledge and accept that**:

1. **You are solely responsible** for any costs incurred through your API provider
2. **You are solely responsible** for the personal data you send to these services
3. **You must review and agree to** OpenAI's or Anthropic's terms of service and privacy policies
4. **We have no control over** how these third-party providers handle your data

### Third-party privacy policies

- [OpenAI privacy policy](https://openai.com/policies/privacy-policy/) and [OpenAI services agreement](https://openai.com/policies/services-agreement/) (covers API use)
- [Anthropic privacy policy](https://www.anthropic.com/legal/privacy) and [Anthropic commercial terms](https://www.anthropic.com/legal/commercial-terms) (covers API use)

### Opting out

If you prefer not to share data with external AI providers, use **Basic**, **Smart** or **Smarter**. All three create summaries on your device. Smart needs a one-time model download; after that it works offline.

---

## Data storage and security

### Local storage

- Recordings and the database are stored in the app's private App Group container on your device
- The database uses SQLite in a folder protected with iOS file protection (`completeUntilFirstUserAuthentication`)
- API keys are stored in the iOS Keychain

### Device backups

Life Wrapped does not sync to any cloud. If you back up your iPhone with iCloud Backup or to a computer, iOS includes the app's data in that backup, as it does for other apps.

### App Group (widgets)

- Widget data is shared through a secure App Group container
- Only summary statistics are shared, never audio or full transcripts

---

## Analytics and tracking

**We do not use:**

- Analytics SDKs
- Crash reporting services
- Advertising networks
- User tracking
- Telemetry collection

---

## Your rights

### Data control

- **Export**: export your data anytime from Settings, then Data, then Export & backup
- **Delete**: delete all recordings, transcripts and summaries from the same screen
- **No account required**: use the app without creating any account

### Data portability

Exports are available as JSON, Markdown or PDF.

---

## Children's privacy

Life Wrapped does not knowingly collect information from children under 13. The app is rated 4+ and is intended for general audiences.

---

## Changes to this policy

We may update this privacy policy from time to time. Changes are posted on this page with a new "Last updated" date.

---

## Contact us

If you have questions about this privacy policy:

- Open an issue on our [GitHub repository](https://github.com/jsayram/life-wrapped/issues)
- Review our [terms of service](terms)

---

## Summary

| Aspect | Status |
| --- | --- |
| Audio recording | On your device only |
| Transcription | On your device only |
| Summaries (Basic, Smart, Smarter) | On your device only |
| Summaries (Smartest) | Your choice, your key |
| Analytics | None |
| Tracking | None |
| Cloud sync | None |
| Data collection | None |

**Your journal. Your device. Your privacy.**
