---
title: Privacy policy
---

<p class="overline">Privacy</p>

# Privacy policy

**Last updated: September 28, 2026**

Life Wrapped is an audio journal, so privacy comes first. Your recordings stay on your iPhone or iPad, and nothing is sent to us.

---

## Data collection

### What we collect

**Nothing.** We don't collect, receive or store any of your data. There's no account to create and no server of ours for the app to talk to.

### What stays on your device

- **Audio recordings**, in the app's protected storage
- **Transcripts**, made on your device with Apple's Speech framework
- **Summaries, titles, month digests and Year Wraps**, made on your device (Key Sentences, Offline AI, Apple Intelligence) or by the provider you connect (Cloud AI), along with the earlier versions the app keeps when one is rewritten
- **Your notes, favorites and Work or Personal labels**
- **App settings**, in UserDefaults, and **API keys**, in the iOS Keychain

---

## Permissions

- **Microphone**, to record
- **Speech recognition**, to transcribe on your device

The app doesn't ask for your location, contacts, photos or notifications.

---

## On-device processing

### Transcription (always on your device)

All speech-to-text happens on your device using Apple's Speech framework with `requiresOnDeviceRecognition = true`. Your audio is never sent to Apple, to us or to anyone else.

### Summaries (your choice)

| Summary quality | Engine | Where it runs | Data sent |
| --- | --- | --- | --- |
| **Key Sentences** | Apple's NaturalLanguage framework picks out key sentences | On your device | None |
| **Offline AI** | Qwen3 4B (Qwen3 1.7B on devices with 4 GB of memory), downloaded once | On your device | None |
| **Apple Intelligence** | Apple's on-device model (iOS or iPadOS 26 or later, on supported devices) | On your device | None |
| **Cloud AI** | OpenAI or Anthropic, with your own API key | The provider's servers | Text only, see below |

Year Wrap can be made with any of the four. You pick one when you create it, and only Cloud AI sends anything off your device.

---

## Network connections

Life Wrapped only goes online in these cases:

- **Downloading the Offline AI model.** If you choose to download it, the model files come from Hugging Face (huggingface.co). No journal data is sent.
- **Purchases.** Unlocking Cloud AI, restoring a purchase and redeeming a code go through Apple's App Store.
- **Cloud AI.** Once you've saved an API key and chosen Cloud AI, text is sent to OpenAI (api.openai.com) or Anthropic (api.anthropic.com) as described below. Before using Cloud AI, the app checks the connection by loading apple.com, which sends no journal data. Without a saved key, the app makes neither request.
- **Testing your API key.** The Test button sends the word "Hi" to the provider you picked, not your journal.

Everything else works offline. Links in the app, such as "Get API key" and "View models", open in your web browser.

---

## Third-party services (bring your own key)

### What is sent

When Cloud AI is your summary quality, the app sends text, never audio, to **OpenAI** or **Anthropic**, whichever you connect:

- **A recording's summary:** its transcript and its Work or Personal label. This includes upgrading earlier recordings to Cloud AI in Settings, which first lists the recordings it will send
- **A recording's title:** the first 400 characters of its summary. Recordings that don't have a title yet are titled in the background when you open the app
- **A month summary:** that month's recording summaries, their dates and Work or Personal labels, and any notes you added to those recordings. A month that has ended is finished in the background when you open the app, or while your device is charging
- **Year Wrap, if you choose Cloud AI for it:** your month summaries, and for any month that needs rebuilding first, that month's recording summaries and notes

The request uses the model you enter in Settings, then AI & Summaries. It's made with **your API key**, not ours, and the provider bills you directly.

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

If you'd rather not share anything with an AI provider, use **Key Sentences**, **Offline AI** or **Apple Intelligence**. All three make summaries on your device, and nothing is sent. Offline AI needs a one-time model download; after that it works offline. Removing your API key in Settings, then AI & Summaries, stops all Cloud AI requests.

---

## Data storage and security

### Local storage

- Recordings and the database are stored in the app's private App Group container on your device
- The database uses SQLite in a folder protected with iOS file protection (`completeUntilFirstUserAuthentication`)
- API keys are stored in the iOS Keychain and never leave your device, except to authenticate your own requests to your provider

### Device backups

Life Wrapped doesn't sync to any cloud. If you back up your iPhone or iPad with iCloud Backup or to a computer, iOS includes the app's data in that backup, as it does for other apps.

### Widgets

The Home Screen and Lock Screen widgets read a few numbers from the shared App Group container: your streak, and today's recording count, minutes, words and last recording time. Audio, transcripts and summaries are never shared with the widget.

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

- **Export**: export anytime from Settings, then Data, then Export & backup
- **Delete**: on the same screen, delete one year or everything. Deleting everything removes your recordings, transcripts, summaries and notes, your saved API keys and the downloaded Offline AI model
- **No account required**: use the app without creating any account

### Data portability

Exports are available as JSON (transcripts and summaries, with the earlier versions of each summary), Markdown (summaries) or PDF (summaries). Exports don't include audio.

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
| Summaries (Key Sentences, Offline AI, Apple Intelligence) | On your device only |
| Summaries (Cloud AI) | Your choice, your key, text only |
| Analytics | None |
| Tracking | None |
| Cloud sync | None |
| Data collection | None |

**Your journal. Your device. Your privacy.**
