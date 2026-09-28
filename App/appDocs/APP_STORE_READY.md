# App Store Listing

Paste-ready copy for App Store Connect, checked against the app as of September 27, 2026. Each field is within Apple's limit (shown in brackets). The version 1.0 launch checklist that used to live here described a different app (purple design, no network use, weekly insights) and has been replaced; it's still in git history.

The live listing needs these updates:

- The in-app purchase is still named **Smartest AI**. Rename it to **Cloud AI** (see below). The product ID stays `com.jsayram.lifewrapped.smartestai`.
- The description mentions tracking sentiment. The app no longer does that.
- The screenshots show the old purple design. The current sets are in `Images/Iphone/Life-Wrapped-APp/` (1290 × 2796) and `Images/IPad/App-Store/` (2064 × 2752).

---

## App information

| Field | Value |
| --- | --- |
| Name [30] | Life Wrapped |
| Subtitle [30] | Private audio journal |
| Category | Productivity |
| Age rating | 4+ |
| Privacy policy URL | https://jsayram.github.io/life-wrapped/privacy |
| Support URL | https://jsayram.github.io/life-wrapped/support |
| Marketing URL | https://jsayram.github.io/life-wrapped/ |
| Privacy label | Data Not Collected (see `PRIVACY_LABELS.md`) |

## Promotional text [170]

```
Talk through your day. Life Wrapped transcribes it on your iPhone or iPad, summarizes every recording and month, and wraps up your year.
```

## Keywords [100]

```
journal,diary,voice,audio,transcribe,notes,summary,year in review,memo,private,offline,reflection
```

## Description [4000]

```
Life Wrapped is a private audio journal. Tap once and talk about your day, a meeting or a walk home. The app writes it down on your device, gives every recording a title and a summary, and wraps up your year when it ends.

PRIVATE BY DESIGN
• Transcription runs on your iPhone or iPad with Apple's on-device speech recognition. Your audio never leaves your device.
• No account, no analytics, no ads, no tracking.
• Your journal is stored on your device. Export it or delete it whenever you like.

RECORD
• One tap to record, filed under Work or Personal.
• Long entries are split into short parts so they transcribe quickly.
• Add notes, fix a transcript and star your favorites.
• Widgets start a recording from your Home Screen or Lock Screen.

SUMMARIES, YOUR WAY
• Key Sentences picks out your most important sentences. Free, and works offline.
• Offline AI is a model you download once. It then runs on your device for free.
• Apple Intelligence is built into supported devices on iOS 26 or later. Free.
• Cloud AI gives the most detailed summaries, using your own OpenAI or Anthropic API key. It's a one-time purchase with no subscription, and your provider bills you directly for what you use.

LOOK BACK
• Overview shows today, yesterday and a summary of each month, for work, personal or both.
• Year Wrap tells the story of your year: wins, challenges, projects, people, places and the topics you kept coming back to. Every summary option can make one; Apple Intelligence and Cloud AI write the fullest story.
• Statistics show your streak, when you record most and the words you use most.
• Search titles, notes and transcripts.

MADE FOR IPAD TOO
On iPad, History shows your recordings and the one you pick side by side, and recordings and Year Wrap spread into two columns.

EXPORT
Export JSON, Markdown or PDF, for one year or everything.

Cloud AI sends text from your journal, never audio, to the provider you choose. The privacy policy lists exactly what is sent: https://jsayram.github.io/life-wrapped/privacy
```

## What's New in this version [4000]

Version 1.3:

```
• Every summary option can now make your Year Wrap. Key Sentences builds one instantly from your months, Offline AI writes one on your device, and Apple Intelligence and Cloud AI write the fullest story.
• Nothing you already have gets worse. A summary, month or Year Wrap written by a better option is never rewritten by a plainer one without asking you first.
• Earlier versions: every rewrite keeps the text it replaced, so you can bring back an earlier summary, month or Year Wrap.
• Switch to a stronger summary option and upgrade your earlier recordings in one go.
• Month summaries finish in the background while your iPhone charges.
• Key Sentences always writes a summary and a title, even for a few-second recording, and picks better topics.
• Backups now include each summary's engine and its earlier versions.
```

Version 1.2:

```
• A new, calmer design with serif titles and clear cards, in light and dark mode.
• Work and Personal are now separate journals, with their own summaries and Year Wrap.
• Every recording gets a short title, and editing notes and transcripts is simpler.
• New month summaries in Overview, and a reworked Year Wrap for each journal.
• Summary options have clearer names: Key Sentences, Offline AI, Apple Intelligence and Cloud AI.
• Offline AI now runs Qwen3, and Cloud AI works with the OpenAI or Anthropic model you choose.
• iPad layouts that use the whole screen, and a Today card on the Record tab.
• A warning when the microphone can't hear you.
• Fixes for streaks, purchases, restoring and redeeming codes.
```

## In-app purchase

| Field | Value |
| --- | --- |
| Type | Non-consumable |
| Product ID | `com.jsayram.lifewrapped.smartestai` (never change it: existing purchases are tied to it) |
| Reference name [64] | Cloud AI |
| Display name [30] | Cloud AI |
| Description [45] | Detailed summaries with your own AI key |
| Price | $2.99 (US) |
| Review screenshot | `Images/Iphone/inapp-purchase.jpg` |

## App Review notes

Use `APP_REVIEW_GUIDE.md` (also exported as `APP_REVIEW_GUIDE.rtf`). There's no sign-in, so no demo account is needed.

## Before each submission

- [ ] Screenshots match the current design (regenerate them if screens changed)
- [ ] What's New describes this version
- [ ] Privacy policy, support and terms pages on the website match the app
- [ ] The in-app privacy policy and terms (Settings, then Privacy policy) match the website
- [ ] Privacy label still accurate (no new data leaves the device)
