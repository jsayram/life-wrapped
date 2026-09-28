# App Store Listing

Paste-ready copy for App Store Connect and TestFlight, checked against the app (version 1.3, build 3) as of September 28, 2026. Each field is within Apple's limit (shown in brackets). The version 1.0 launch checklist that used to live here described a different app (purple design, no network use, weekly insights) and has been replaced; it's still in git history.

The live listing needs these updates:

- The in-app purchase was renamed from **Smartest AI** to **Cloud AI** on September 28, 2026 (reference name, display name, description and review notes). The new name needs App Review, so add the purchase to the same submission as 1.3. The product ID stays `com.jsayram.lifewrapped.smartestai`.
- The description mentions tracking sentiment. The app no longer does that.
- The screenshots show the old purple design. Replace them with the 10-per-device sets listed under Screenshots below.

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

## Screenshots

Ten per device, uploaded in this order. iPhone: `Images/Iphone/Life-Wrapped-APp/image1.png` to `image10.png` (1290 × 2796, the 6.7" size). iPad: `Images/IPad/App-Store/ipad1.png` to `ipad10.png` (2064 × 2752, the 13" size). The website uses JPEG copies of the same screens in `docs/assets/screens/` (`iphone-1.jpg` to `iphone-10.jpg`, `ipad-1.jpg` to `ipad-10.jpg`).

| # | Screen |
| --- | --- |
| 1 | Record tab |
| 2 | History |
| 3 | A recording with its summary and transcript |
| 4 | Overview, today and yesterday |
| 5 | A month summary |
| 6 | Year Wrap |
| 7 | Earlier versions sheet |
| 8 | AI & Summaries settings: summary options and the upgrade for earlier recordings |
| 9 | Statistics |
| 10 | Data: export and backup |

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
• A summary written by a better option is never replaced by a plainer one without asking you. Earlier versions are kept, so you can bring one back, and older recordings can be upgraded when you switch to a stronger option.

LOOK BACK
• Overview shows today, yesterday and a summary of each month, for work, personal or both.
• Year Wrap tells the story of your year: wins, challenges, projects, people, places and the topics you kept coming back to. Every summary option can make one; Apple Intelligence and Cloud AI write the fullest story.
• Statistics show your streak, when you record most and the words you use most.
• Search titles, notes and transcripts.

MADE FOR IPAD TOO
On iPad, History shows your recordings and the one you pick side by side, and recordings and Year Wrap spread into two columns.

EXPORT
Export JSON, Markdown or PDF, for one year or everything, and import a JSON backup.

Cloud AI sends text from your journal, never audio, to the provider you choose. The privacy policy lists exactly what is sent: https://jsayram.github.io/life-wrapped/privacy
```

## What's New in this version [4000]

Version 1.3, as entered in App Store Connect on September 28, 2026. 1.2 never shipped (the store still has 1.0), so this text covers the 1.2 changes as well:

```
• A calmer design with serif titles and clear cards, in light and dark mode, and iPad layouts that use the whole screen.
• Work and Personal are separate journals, each with its own summaries and Year Wrap.
• Every recording gets a short title, and editing notes and transcripts is simpler.
• Month summaries in Overview, and a reworked Year Wrap.
• Every summary option can now make your Year Wrap. Key Sentences builds one instantly, Offline AI writes one on your device, and Apple Intelligence and Cloud AI write the fullest story.
• Summary options have clearer names: Key Sentences, Offline AI, Apple Intelligence and Cloud AI. Offline AI now runs Qwen3, and Cloud AI works with the OpenAI or Anthropic model you choose.
• Nothing you already have gets worse. A summary, month or Year Wrap written by a better option is never rewritten by a plainer one without asking you first.
• Earlier versions: when a summary, month or Year Wrap is rewritten, the old text is kept so you can bring it back.
• Switch to a stronger summary option and upgrade your earlier recordings in one go.
• Months that have ended are finished in the background while your iPhone or iPad charges.
• Key Sentences always writes a summary and a title, even for a few-second recording.
• A warning when the microphone can't hear you, and a message when playback fails.
• Backups include each summary's engine and its earlier versions.
• Fixes for streaks, purchases, restoring and redeeming codes.
```

Version 1.3 on its own, for TestFlight or if 1.2 had shipped:

```
• Every summary option can now make your Year Wrap. Key Sentences builds one instantly from your months, Offline AI writes one on your device, and Apple Intelligence and Cloud AI write the fullest story.
• Nothing you already have gets worse. A summary, month or Year Wrap written by a better option is never rewritten by a plainer one without asking you first.
• Earlier versions: when a summary, month or Year Wrap is rewritten, the old text is kept, so you can bring it back.
• Switch to a stronger summary option and upgrade your earlier recordings in one go. Settings shows which recordings it will rewrite before it starts.
• Months that have ended can now be finished in the background while your iPhone or iPad charges.
• Key Sentences always writes a summary and a title, even for a few-second recording, and picks better topics.
• You'll see a message when your chosen summary option wasn't available and another one wrote the summary.
• Backups now include each summary's engine and its earlier versions.
• If playback fails, you now see a message instead of nothing happening.
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

## TestFlight: What to Test (1.3) [4000]

```
Thanks for testing Life Wrapped 1.3. Please try the items below, and send feedback from TestFlight with a screenshot when something looks wrong.

UPDATING FROM 1.2
• Install 1.3 over 1.2 without deleting the app. Your recordings, transcripts, summaries, months and Year Wrap should all still be there.
• On a spare device, try a fresh install too: record something and check it gets a transcript, a title and a summary.

YEAR WRAP WITH EVERY SUMMARY OPTION
• In Overview, switch to Year and generate a wrap. Then use the button on the wrap to make it again with each other option you have.
• Key Sentences needs no model and no purchase. It should finish almost at once, with your numbers, people, places and topics but no written story.
• Offline AI needs the model downloaded first and takes a few minutes with the app open.
• Apple Intelligence and Cloud AI should write the fullest story.

EARLIER VERSIONS
• Edit a recording's transcript and tap Update on its summary (or regenerate it with a model option), then open Earlier versions from the summary's menu and restore the old one. Regenerating with Key Sentences on an unchanged transcript gives the same text, so no version is added.
• Try the same with the clock button on a month and on the Year Wrap.
• Restoring keeps the text it replaced, so you can switch back again.

UPGRADING EARLIER RECORDINGS
• With a few recordings summarized by Key Sentences, choose a stronger option in Settings, then AI & Summaries.
• An Earlier summaries section should appear. Open it and check the list of recordings before you tap Upgrade.
• Each row shows its progress. Afterwards the list stays, showing which recordings were upgraded and which kept their summary.

A WEAKER OPTION SHOULDN'T REPLACE A BETTER SUMMARY
• Summarize a recording with Apple Intelligence or Cloud AI, then switch to Key Sentences.
• Tap Regenerate summary. The app should ask first, and choosing Keep should leave the summary alone.
• Rebuilding a month or making a Year Wrap with a weaker option should also ask first.
• Edit that recording's transcript. It should keep the better summary and tell you the transcript changed, instead of rewriting it.

VERY SHORT RECORDINGS
• With Key Sentences selected, record just a few seconds. You should get a summary and a sensible title, never a blank one.

BACKUP
• In Settings, then Data, then Export & backup, export a JSON backup and import it on another device or a fresh install. Transcripts, summaries and their earlier versions should come back. Audio, titles and notes aren't part of the backup.
• Importing the same file twice should skip the duplicates.
• A JSON backup made with 1.2 should still import.

MONTHS FINISHED WHILE CHARGING
• After a month ends, plug in your iPhone or iPad and leave Life Wrapped in the background without force-quitting it. iOS decides when the task runs, often overnight. The next time you open Overview, last month should already be finished.

IPAD
• Check History side by side, a recording and the Year Wrap in two columns, the Earlier versions sheet and the upgrade screen, in portrait and landscape.
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
