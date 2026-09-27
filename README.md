# Life Wrapped

A private audio journal for iPhone and iPad. Record your day, get it transcribed on your device, read summaries by day, week and month, and look back with a Year Wrap.

[Download on the App Store](https://apps.apple.com/us/app/life-wrapped/id6757250245) · [Website](https://jsayram.github.io/life-wrapped/) · [Privacy policy](https://jsayram.github.io/life-wrapped/privacy) · [Support](https://jsayram.github.io/life-wrapped/support) · [Terms of service](https://jsayram.github.io/life-wrapped/terms)

| | |
| --- | --- |
| Platform | iOS and iPadOS 18.0 or later |
| App version in this repo | 1.1 (build number set by Xcode Cloud) |
| Language | Swift 6 (language mode 6.0, strict concurrency) |
| UI | SwiftUI |
| Toolchain | Xcode 26.1 or later |
| Bundle ID | `com.jsayram.lifewrapped` (widget: `com.jsayram.lifewrapped.widget`) |
| License | [MIT](LICENSE) |

---

## What the app does

### Recording

- One-tap recording on the Record tab, tagged as **Work** or **Personal**
- Recordings are split into parts automatically so they transcribe quickly. The part length is adjustable from 30 to 300 seconds in steps of 30 (default 30 seconds) in Settings, then Recording
- Background audio is enabled, so recording continues when the screen locks
- Deep links: `lifewrapped://record`, `lifewrapped://home`, `lifewrapped://history`, `lifewrapped://overview`, `lifewrapped://settings` (record links accept a `category` query parameter)

### Transcription

- Apple's Speech framework with `requiresOnDeviceRecognition = true`, so audio is never sent off the device
- Up to 3 parts are transcribed at the same time
- Handles pauses by keeping utterances that the recognizer abandons without marking them final
- Language detection is limited to the languages turned on in Settings, then Recording, then Languages. Nine are available: English, Spanish, Hindi, Bangla, French, Vietnamese, Chinese, Korean and Turkish (English and Spanish are on by default)
- Transcripts can be edited, and each recording can have a title, notes, a favorite star and a category

### Summaries

Four summary qualities. The app falls back automatically when the chosen one is not available.

| Quality | Engine | Where it runs | Fallback order |
| --- | --- | --- | --- |
| Basic | `BasicEngine`: extractive summaries with TF-IDF ranking and Apple's NaturalLanguage framework (`NLEmbedding`, `NLTokenizer`, `NLTagger`) | On device | Basic |
| Smart | `LocalEngine`: Qwen3 4B Instruct 2507, 4-bit ([`mlx-community/Qwen3-4B-Instruct-2507-4bit`](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit), pinned to one commit) run with MLX. One-time download of about 2.3 GB from Hugging Face. Devices with 4 GB of memory (iPhone 12, 12 mini, 13, 13 mini, SE 3rd gen) get Qwen3 1.7B, 4-bit ([`mlx-community/Qwen3-1.7B-4bit`](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit), about 1.0 GB, thinking turned off) instead, and devices with 3 GB don't offer Smart. The app checks free memory before loading the model and falls back instead of crashing. Updating from a version that used Phi-3.5, or that downloaded the other Qwen3 size, deletes the old model | On device | Smart, then Basic |
| Smarter | `AppleEngine`: Apple Intelligence through the Foundation Models framework, always `SystemLanguageModel.default` (the on-device model). Needs iOS 26 or later on a device with Apple Intelligence turned on | On device | Smarter, then Smart, then Basic |
| Smartest | `ExternalAPIEngine`: OpenAI (Chat Completions API) or Anthropic (Messages API) with the user's own API key. The model ID is free text; defaults are `gpt-6-luna` and `claude-sonnet-5` | Cloud | Smartest, then Smart, then Basic |

- Smartest is unlocked with a one-time in-app purchase, **Smartest AI** ($2.99 in the US)
- API keys are stored in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`)
- The Test button sends a small request with the typed model ID to confirm the key and model work
- Summaries are made per recording, then rolled up into day, week, month and year summaries shown on the Overview tab

### Year Wrap

- A year in review with a title, a summary, major arcs, wins, losses, challenges, finished and unfinished projects, top topics, valuable actions, missed opportunities, people and places
- Generated with Smart (on device) or Smartest (cloud), as All, Work only or Personal only
- People and places can be redacted before exporting it as a PDF

### Overview, history and statistics

- History with search across titles, notes and transcripts, Work and Personal filters, and favorites
- Overview by yesterday, today, week, month and year
- Statistics: longest session, most active month, sessions by time of day and day of week, most used words (with an editable excluded-words list), mood from on-device sentiment analysis, and languages spoken
- Daily streak

### Data

- Export as JSON (recording metadata, transcripts and summaries; no audio files), Markdown (day, week and month summaries) or PDF (summaries only), for everything or for one year
- Import from a JSON export
- Delete all data, or one year of data
- Storage breakdown for audio, database and the Smart model

### Widgets

- **Quick Record** (small, medium, circular): start a Work or Personal recording, see the streak and today's sessions
- **Today's Sessions** (small, circular, inline): today's session count and streak

### Design

Graphite design language: warm off-white and near-black surfaces, ink as the only accent, serif (New York) titles, SF Symbols, hairline borders and no gradients. Light and dark mode are supported. Colors live in `App/Constants/AppTheme.swift`.

---

## Privacy

- **Audio** never leaves the device.
- **Transcription** always runs on the device.
- **Basic, Smart and Smarter** summaries run on the device.
- **Smartest** sends the text being summarized to OpenAI or Anthropic using the user's own key: for a recording, its transcript and Work or Personal label (plus notes when the user regenerates with notes); for longer periods and Year Wrap, the earlier summaries. Before each Smartest request the app checks connectivity with a request to `https://www.apple.com`.
- **Network use** is limited to: the Smart model download from Hugging Face, App Store purchases, Smartest requests and the connectivity check above.
- **No analytics, crash reporting, advertising or tracking.** No account.
- **Storage**: SQLite database and audio files live in the App Group container `group.com.jsayram.lifewrapped`. The database directory uses `FileProtectionType.completeUntilFirstUserAuthentication`. The widget only receives summary statistics (streak, today's entries, words and minutes).

The full policy is at [jsayram.github.io/life-wrapped/privacy](https://jsayram.github.io/life-wrapped/privacy).

---

## Getting started

### Requirements

- macOS with **Xcode 26.1 or later**
- An iOS 18 simulator or device (an iOS 26 device with Apple Intelligence is needed to try Smarter)

### Setup

```bash
# 1. Clone
git clone https://github.com/jsayram/life-wrapped.git
cd life-wrapped

# 2. Create the local secrets file (required: Config/Debug.xcconfig includes it)
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig

# 3. Open the workspace
open LifeWrapped.xcworkspace
```

Select the **LifeWrapped** scheme and an iPhone simulator, then Run. Swift packages (MLX, swift-transformers and their dependencies) resolve automatically on first open.

The LifeWrapped scheme uses `Config/StoreKitConfiguration.storekit`, so the Smartest AI purchase can be tested in the simulator without a real payment.

### Running tests

Tests use Swift Testing, except LocalLLM, which uses XCTest. Xcode creates a scheme for each local package. Select a package scheme (for example **Summarization** or **Storage**) and choose Product, then Test.

| Package | Test files |
| --- | --- |
| AudioCapture | `AudioCaptureTests.swift` |
| InsightsRollup | `InsightsRollupTests.swift` |
| LocalLLM | `LocalLLMTests.swift` |
| SharedModels | `SharedModelsTests.swift` |
| Storage | `StorageTests.swift`, `PDFExportPreviewTests.swift` (writes sample PDFs to `TestResults/pdf-preview/`, which git ignores) |
| Summarization | `SummarizationTests.swift`, `EngineRoutingTests.swift`, `ExternalModelSettingsTests.swift`, `AppleIntelligenceLiveTests.swift` (skips itself where Apple Intelligence is unavailable) |
| Transcription | `TranscriptionTests.swift` |
| WidgetCore | `WidgetCoreTests.swift` |

---

## Project structure

```
life-wrapped/
├── App/                          # iOS app target (SwiftUI)
│   ├── LifeWrappedApp.swift      # Entry point, deep links, appearance
│   ├── ContentView.swift         # Tab bar: Record, History, Overview, Settings
│   ├── Components/               # Reusable views: AI, Cards, Layouts, Loading, Recording, Rows, Shared
│   ├── Constants/                # AppTheme (design tokens and shared components), StopWords
│   ├── Coordinators/             # AppCoordinator, DataCoordinator, LocalModelCoordinator,
│   │                             # PermissionsCoordinator, RecordingCoordinator, SummaryCoordinator,
│   │                             # TranscriptionCoordinator, WidgetCoordinator
│   ├── Helpers/                  # Extensions, KeychainHelper and other utilities
│   ├── Models/                   # View-level models such as TimeRange
│   ├── Resources/                # Info.plist, entitlements, asset catalog (app icon)
│   ├── Settings/                 # Settings screens (AI & Summaries, Recording, Statistics, Data, Privacy)
│   ├── Store/                    # StoreKit purchase handling
│   ├── Views/                    # Tabs, Details, Overview, Insights, AI, Components, Utility,
│   │                             # onboarding (PermissionsView) and data management
│   └── appDocs/                  # Internal notes (architecture, App Store, Xcode Cloud, testing)
├── WidgetExtension/              # WidgetKit extension (Quick Record, Today's Sessions)
├── Packages/                     # Local Swift packages (swift-tools-version 6.0)
│   ├── SharedModels/             # Data models, constants, feature flags, logging
│   ├── Storage/                  # SQLite (SQLite3) persistence, repositories, migrations,
│   │                             # JSON/Markdown/PDF export, JSON import
│   ├── AudioCapture/             # Recording, part splitting, file management, playback
│   ├── Transcription/            # On-device speech recognition, language detection, sentiment
│   ├── Summarization/            # Basic, Smart, Smarter and Smartest engines, routing and fallback
│   ├── LocalLLM/                 # MLX model loading and Hugging Face download for Smart
│   ├── InsightsRollup/           # Streaks, goals, insights
│   └── WidgetCore/               # Data shared with the widget through the App Group
├── Config/                       # Debug/Release xcconfig, secrets template, StoreKit configuration
├── Scripts/                      # Shell helpers (see below)
├── docs/                         # GitHub Pages site: home, privacy, support, terms
├── Images/                       # App Store and marketing screenshots
├── Logo/                         # Logo source files
├── LifeWrapped.xcodeproj
├── LifeWrapped.xcworkspace       # Open this
└── project.yml                   # XcodeGen spec (out of date: still lists version 1.0; build from the .xcodeproj)
```

### Third-party dependencies

Resolved versions from `LifeWrapped.xcworkspace/xcshareddata/swiftpm/Package.resolved`:

| Package | Version |
| --- | --- |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.29.1 |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | d9f46e3 (pinned) |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 573e5c9 |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 2.2.0 |
| [swift-collections](https://github.com/apple/swift-collections) | 1.3.0 |
| [swift-numerics](https://github.com/apple/swift-numerics) | 1.1.1 |

All are used only by the LocalLLM package for the Smart engine.

### Scripts

| Script | What it does |
| --- | --- |
| `Scripts/build.sh packages` | Runs `swift build` in each local package |
| `Scripts/build.sh ios` | Builds the LifeWrapped scheme with `xcodebuild` |
| `Scripts/build.sh clean` | Removes build output and package `.build` folders |
| `Scripts/lint.sh [--fix]` | SwiftLint and swift-format checks (uses `.swiftlint.yml` and `.swift-format`) |
| `Scripts/format.sh [path]` | Formats Swift files with swift-format |
| `Scripts/verify-privacy.sh` | Lists network and cloud API usage in the source so it can be reviewed |

Some script options (`watch`, `widgets`, and the `integration`, `ui` and `performance` test targets) refer to schemes that do not exist in this project.

---

## Deployment

- `main` is production. Pushing to `main` starts the Xcode Cloud workflow, which builds, archives and uploads to TestFlight and App Store Connect.
- `dev` is the integration branch. Feature branches start from `dev`.
- App Store releases are submitted from App Store Connect.

More detail is in `App/appDocs/XCODE_CLOUD_BUILD.md` and `App/appDocs/WORKFLOW.md`.

---

## Documentation

| Document | Contents |
| --- | --- |
| [`docs/`](docs) | Public website, privacy policy, support and terms (served at [jsayram.github.io/life-wrapped](https://jsayram.github.io/life-wrapped/)) |
| [`App/appDocs/`](App/appDocs) | Internal notes on the AI architecture, local AI, App Store submission, privacy labels, in-app purchases, StoreKit testing, widgets and Xcode Cloud |

---

## Support

Questions, bugs and feature requests: [open an issue](https://github.com/jsayram/life-wrapped/issues).

---

## License

The source code in this repository is released under the [MIT License](LICENSE). Copyright (c) 2025-2026 Jose Ramirez-Villa.

The MIT License covers the code. Use of the Life Wrapped app from the App Store is governed by the [terms of service](https://jsayram.github.io/life-wrapped/terms). The Life Wrapped name and app icon are not licensed for use as your own branding.
