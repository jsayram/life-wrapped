# Life Wrapped

> **Privacy-focused audio journaling for iOS, watchOS, and macOS.**

[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![Xcode 26](https://img.shields.io/badge/Xcode-26-blue.svg)](https://developer.apple.com/xcode/)
[![Platform](https://img.shields.io/badge/Platform-iOS%2018%20%7C%20watchOS%2011%20%7C%20macOS%2015-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 🎯 What is Life Wrapped?

Life Wrapped records audio throughout your day, transcribes it **locally on your device**, and helps you discover insights about how you spend your time. AI summaries are powered by your own API keys (OpenAI or Anthropic), with automatic offline fallback to Basic summaries when no connection is available.

### Key Features

- 🎙️ **Continuous Audio Capture** — Record throughout the day with chunked files
- 🗣️ **On-Device Transcription** — Apple's Speech framework, no cloud required
- 🤖 **Smart AI Summaries** — Bring your own OpenAI/Anthropic API keys for best quality
- 📴 **Offline Fallback** — Basic summaries work without internet
- 📊 **Rich Insights** — See your day/week/month in words and time
- ⌚ **Apple Watch Support** — Control and glance from your wrist
- 🔒 **Privacy-First** — Transcription on-device; you control AI keys
- 📱 **Widgets & Siri** — Quick stats and voice control

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
├── Extensions/
│   ├── Widgets/         # WidgetKit extension
│   └── AppIntents/      # Siri Shortcuts
├── WatchApp/            # watchOS app
├── MacApp/              # macOS app (Phase 2)
├── Packages/            # Local Swift Packages
│   ├── SharedModels/    # Data models & protocols
│   ├── Storage/         # SQLite persistence
│   ├── AudioCapture/    # Recording pipeline
│   ├── Transcription/   # Speech recognition
│   ├── Insights/        # Stats & charts
│   ├── Backup/          # Export/import
│   ├── Summarization/   # LLM adapter
│   └── Sync/            # CloudKit (Phase 2)
├── Config/              # Build configurations
├── Scripts/             # Build/test scripts
├── Docs/                # Documentation
└── Tests/               # Test suites
```

---

## 🔒 Privacy & Security

### Our Commitments

1. **On-Device Transcription** — All speech-to-text processing happens locally
2. **No Cloud Speech** — Uses `requiresOnDeviceRecognition = true`
3. **Your API Keys** — AI summaries use your own OpenAI/Anthropic keys (you control)
4. **Offline Fallback** — Basic summaries work without internet or API keys
5. **No Analytics** — No tracking, no telemetry
6. **Encrypted Storage** — Data protected at rest
7. **Your Data, Your Control** — Export anytime, delete anytime

### Verification

```bash
# Run privacy audit (checks for unauthorized network calls)
./Scripts/verify-privacy.sh

# Manual verification:
# 1. Without API keys configured — app functions normally with Basic summaries
# 2. Network offline — transcription and Basic summaries still work
# 3. With API keys — only external AI API calls are made (your keys, your control)
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

### V1 (Current)

- [x] Project setup & architecture
- [ ] SQLite storage with migrations
- [ ] Audio capture pipeline
- [ ] On-device transcription
- [ ] Insights & stats
- [ ] iOS widgets
- [ ] Siri Shortcuts
- [ ] Apple Watch app

### V2

- [ ] On-device summarization (Core ML / local LLM)
- [ ] macOS companion app
- [ ] CloudKit sync (opt-in)
- [ ] Speaker diarization
- [ ] Entity extraction

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
