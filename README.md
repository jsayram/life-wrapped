# Life Wrapped

> **Privacy-focused audio journaling for iOS, watchOS, and macOS.**

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Xcode 26](https://img.shields.io/badge/Xcode-26-blue.svg)](https://developer.apple.com/xcode/)
[![Platform](https://img.shields.io/badge/Platform-iOS%2018%20%7C%20watchOS%2011%20%7C%20macOS%2015-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎯 What is Life Wrapped?

Life Wrapped records audio throughout your day, transcribes it **locally on your device**, and helps you discover insights about how you spend your time.

### Key Features

- 🎙️ **Auto-Chunking Recording** — Automatically splits recordings into 30-300s chunks for efficient processing
- 🗣️ **On-Device Transcription** — Apple's Speech framework with abandoned utterance detection, no cloud required
- 🤖 **Multi-Tier AI Summaries** — Intelligent fallback system with 4 engines:
  - **External API** (Best Quality) — GPT-4, Claude Sonnet 3.5 with your API keys
  - **Local AI** (Privacy-First) — Phi-3.5 Mini on-device via MLX, ~2.1GB model
  - **Apple Intelligence** (iOS 18.1+) — Foundation Models when available
  - **Basic** (Always Available) — Fast extractive summarization with NLP
- 🔄 **Smart Fallback** — Automatically downgrades: External → Local → Apple → Basic
- 📴 **Fully Offline Capable** — All features work without internet (Basic + Local AI)
- 📊 **Rich Insights** — Session summaries, topics, entities, sentiment, key moments
- ⌚ **Apple Watch Support** — Control and glance from your wrist
- 🔒 **Privacy-First** — Transcription always on-device; you control AI provider
- 📱 **Widgets & Siri** — Quick stats and voice control

### How It Works

```
Record Audio → Auto-Chunk (30-300s) → Transcribe (On-Device) → AI Summary
    ↓              ↓                       ↓                      ↓
Session ID    Chunk 0,1,2...        Apple Speech API      External/Local/Basic
    ↓              ↓                       ↓                      ↓
Database      Parallel Processing    Word-perfect text    Structured insights
```

**Audio Processing:**

- Recording automatically splits into configurable chunks (default 180s)
- Each chunk processes independently with parallel transcription (max 3 concurrent)
- Abandoned utterance detection captures pauses of any length
- Real-time UI updates show transcription progress per chunk

**AI Summarization (4-Tier System):**

1. **External API** (Cloud) — OpenAI GPT-4.1, Anthropic Claude 3.5 Sonnet
2. **Local AI** (On-Device) — Phi-3.5 Mini 4-bit quantized (~2.1GB via MLX)
3. **Apple Intelligence** (On-Device) — Foundation Models (iOS 18.1+, A17 Pro/M1+)
4. **Basic** (On-Device) — TF-IDF + semantic embeddings + NLP (always works)

---

## 🚀 Quick Start

### Prerequisites

- **Xcode 26.1+** (verify: `xcodebuild -version`)
- **Swift 6.2+** (verify: `swift --version`)
- **macOS Tahoe 26.0+** (verify: `sw_vers`)
- **Optional**: SwiftLint, swift-format (`brew install swiftlint swift-format`)

### Setup

```bash
# 1. Clone the repository
git clone https://github.com/jsayram/life-wrapped.git
cd life-wrapped

# 2. Copy secrets template
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
# Edit Config/Secrets.xcconfig with your values

# 3. Make scripts executable
chmod +x Scripts/*.sh

# 4. Build packages (verify setup)
./Scripts/build.sh packages

# 5. Open in Xcode
open LifeWrapped.xcworkspace
```

---

## 🛠️ Development Workflow

### VS Code + Xcode Hybrid

1. **Edit code in VS Code** — Swift LSP provides autocomplete
2. **Build/test via CLI** — `./Scripts/build.sh` and `./Scripts/test.sh`
3. **Run/debug in Xcode** — For device testing and Instruments

### Recommended VS Code Extensions

```bash
# Install recommended extensions
code --install-extension sswg.swift-lang
code --install-extension vknabel.vscode-apple-swift-format
```

### Scripts

| Script                        | Purpose                                 |
| ----------------------------- | --------------------------------------- |
| `./Scripts/build.sh [target]` | Build iOS, Watch, Widgets, or all       |
| `./Scripts/test.sh [target]`  | Run unit, integration, UI, or all tests |
| `./Scripts/lint.sh`           | Check code style                        |
| `./Scripts/format.sh`         | Auto-format Swift code                  |
| `./Scripts/verify-privacy.sh` | Verify no unauthorized network calls    |

---

## 📁 Project Structure

```
life-wrapped/
├── App/                 # iOS SwiftUI app
│   ├── LifeWrappedApp.swift         # App entry point
│   ├── ContentView.swift            # Main tab container
│   ├── Coordinators/                # Business logic coordinators
│   │   ├── AppCoordinator.swift           # Central app coordinator
│   │   ├── RecordingCoordinator.swift     # Recording lifecycle
│   │   ├── TranscriptionCoordinator.swift # Transcription orchestration
│   │   ├── SummaryCoordinator.swift       # AI summary generation
│   │   ├── DataCoordinator.swift          # Data management operations
│   │   ├── WidgetCoordinator.swift        # Widget data updates
│   │   ├── PermissionsCoordinator.swift   # System permissions
│   │   └── LocalModelCoordinator.swift    # Local LLM management
│   ├── Views/                       # SwiftUI views
│   │   ├── Tabs/                    # Main tab views
│   │   ├── Overview/                # Overview & summaries
│   │   ├── Details/                 # Session detail views
│   │   ├── Insights/                # Analytics & charts
│   │   ├── AI/                      # AI settings & management
│   │   ├── Components/              # Reusable UI components
│   │   └── Utility/                 # Helper views
│   ├── Constants/                   # App-wide constants
│   ├── Helpers/                     # Utility functions
│   ├── Models/                      # View models
│   └── Resources/                   # Assets & entitlements
├── Extensions/
│   └── Widgets/         # WidgetKit extension
├── WatchApp/            # watchOS app
├── Packages/            # Local Swift Packages
│   ├── SharedModels/    # Data models & protocols
│   ├── Storage/         # SQLite persistence with repository pattern
│   │   ├── DatabaseManager.swift          # Facade coordinating repositories
│   │   ├── DatabaseConnection.swift       # SQLite connection management
│   │   ├── SchemaManager.swift            # Schema versioning & migrations
│   │   └── Repositories/
│   │       ├── AudioChunkRepository.swift      # Audio chunk CRUD
│   │       ├── SessionRepository.swift         # Recording session operations
│   │       ├── TranscriptRepository.swift      # Transcript segment storage
│   │       ├── SummaryRepository.swift         # AI summary management
│   │       ├── InsightsRepository.swift        # Stats & rollup queries
│   │       └── ControlEventRepository.swift    # App control events
│   ├── AudioCapture/    # AVAudioEngine recording & playback
│   ├── Transcription/   # Apple Speech framework integration
│   ├── InsightsRollup/  # Time-based aggregations & statistics
│   ├── Summarization/   # External AI API adapter (OpenAI/Anthropic)
│   ├── LocalLLM/        # On-device MLX-based language models
│   └── WidgetCore/      # Shared widget data models
├── Config/              # Build configurations (.xcconfig)
├── Scripts/             # Build/test automation scripts
├── Docs/                # Documentation
└── Tests/               # Test suites
└── Tests/               # Test suites
```

---

## 🔒 Privacy & Security

### Our Commitments

1. **On-Device Transcription** — All speech-to-text processing happens locally using `requiresOnDeviceRecognition = true`
2. **No Cloud Speech** — Apple Speech Recognition with strict on-device enforcement
3. **Privacy-First AI Options** — Multiple on-device engines available:
   - **Basic Engine** — NaturalLanguage framework, no data leaves device
   - **Local AI** — Phi-3.5 Mini runs entirely on your device via MLX (~2.1GB)
   - **Apple Intelligence** — On-device Foundation Models (iOS 18.1+, when available)
4. **Optional External AI** — Use your own API keys (OpenAI/Anthropic) only if you choose
5. **Smart Fallback Chain** — Automatic downgrade: External → Local → Apple → Basic
6. **No Analytics** — No tracking, no telemetry, no third-party SDKs
7. **Encrypted Storage** — SQLite with file protection, App Group sandboxing
8. **Your Data, Your Control** — Export anytime, delete anytime

### AI Engine Details

**External API (Optional):**

- Providers: OpenAI (GPT-4.1, GPT-4o-mini) or Anthropic (Claude 3.5 Sonnet/Haiku)
- Requires: Your API key stored securely in Keychain
- Privacy: Sends transcript text to provider's servers (your keys, your control)
- Quality: Highest quality summaries with structured insights

**Local AI (On-Device):**

- Model: Phi-3.5 Mini 4-bit quantized (Microsoft)
- Size: ~2.1 GB download via HuggingFace
- Framework: MLX (Apple's ML framework for Apple Silicon)
- Privacy: 100% on-device, no internet required
- Performance: Smart caching, chunk-by-chunk processing

**Apple Intelligence (On-Device, iOS 18.1+):**

- Availability: A17 Pro+ / M1+ with Apple Intelligence enabled
- Privacy: On-device Foundation Models
- Status: Placeholder for future integration

**Basic Engine (Always Available):**

- Framework: Apple's NaturalLanguage with TF-IDF + embeddings
- Features: Extractive summarization, keyword extraction, sentiment analysis
- Privacy: 100% on-device, instant processing
- Use Case: Fallback when other engines unavailable

### Verification

```bash
# Run privacy audit (checks for unauthorized network calls)
./Scripts/verify-privacy.sh

# Manual verification:
# 1. Without API keys — app uses Local AI or Basic engine (fully offline)
# 2. Network offline — Local AI and Basic engines work perfectly
# 3. With API keys — only external AI API calls are made (optional, you control)
```

---

## 🧪 Testing

```bash
# Run all tests
./Scripts/test.sh all

# Package tests only (fast)
./Scripts/test.sh packages

# With coverage
xcodebuild test \
  -workspace LifeWrapped.xcworkspace \
  -scheme LifeWrappedTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -enableCodeCoverage YES
```

### Test Categories

- **Unit Tests** — Package-level logic (Storage, Insights, Backup)
- **Integration Tests** — Cross-package flows (Audio → Transcribe → Store)
- **UI Tests** — User interaction flows
- **Performance Tests** — XCTest metrics + Instruments

---

## 📚 Documentation

- [WORKFLOW.md](Docs/WORKFLOW.md) — Complete development workflow
- [ARCHITECTURE.md](Docs/ARCHITECTURE.md) — System design (coming)
- [DATA_MODEL.md](Docs/DATA_MODEL.md) — SQLite schema (coming)
- [PRIVACY.md](Docs/PRIVACY.md) — Privacy implementation (coming)
- [TESTING.md](Docs/TESTING.md) — Test strategy (coming)

---

## 🗺️ Roadmap

### V1 (Current) ✅

- [x] Project setup & architecture
- [x] SQLite storage with repository pattern
- [x] Auto-chunking audio capture pipeline
- [x] On-device transcription (Apple Speech)
- [x] Multi-tier AI summarization (4 engines)
- [x] Local LLM (Phi-3.5 Mini via MLX)
- [x] Insights & time-based rollups
- [x] iOS widgets
- [x] Apple Watch app (in progress)

### V2 (Future)

- [ ] CloudKit sync (opt-in)
- [ ] Siri Shortcuts integration
- [ ] macOS companion app
- [ ] Speaker diarization
- [ ] Advanced entity extraction
- [ ] Export/backup system

---

## 🤝 Contributing

This is a personal project, but suggestions are welcome! Please open an issue to discuss changes.

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- Apple's Speech framework for on-device transcription
- GRDB.swift for SQLite (if used)
- The Swift community for excellent tooling

---

**Built with ❤️ and 🔒 privacy in mind.**
