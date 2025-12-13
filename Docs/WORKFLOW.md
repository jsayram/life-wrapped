# Life Wrapped — Development Workflow

> **Privacy-first, on-device audio journaling for iOS, watchOS, and (later) macOS.**

---

## Toolchain Assumptions

| Tool                   | Version                                         | Verify                                       |
| ---------------------- | ----------------------------------------------- | -------------------------------------------- |
| **Xcode**              | 26.1.1 (Build 17B100)                           | `xcodebuild -version` or Xcode → About Xcode |
| **Swift**              | 6.2.1                                           | `swift --version`                            |
| **macOS**              | Tahoe 26.x                                      | `sw_vers`                                    |
| **Deployment Targets** | iOS 18.0+, watchOS 11.0+, macOS 15.0+ (Phase 2) | Set in Xcode project settings                |

### Key Swift 6.x Features Used

- Strict concurrency checking (`Sendable`, actors, `@MainActor`)
- Typed throws (where beneficial)
- `@Observable` macro for state management
- Modern `async`/`await` throughout
- `#Preview` macros for SwiftUI previews

---

## Non-Negotiable Principles

1. **Privacy-First**: No network calls by default. All speech recognition and (future) LLM run on-device.
2. **Modular Design**: Core logic lives in local Swift Packages (`/Packages`). UI shells are thin.
3. **Single Responsibility**: Small, testable components with clean protocols.
4. **Reliable Persistence**: SQLite is the source of truth per-device (via GRDB or SQLite.swift).
5. **Cross-Device Ready**: Sync via CloudKit records OR encrypted export/import — **never** sync live SQLite via iCloud Drive.
6. **VS Code + Xcode Workflow**: Write code in VS Code, build/test in Xcode and CLI.

---

## Repository Structure

```
life-wrapped/
├── App/                          # iOS app target (SwiftUI shell)
│   ├── LifeWrappedApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   ├── ViewModels/
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── Entitlements/
├── Extensions/
│   ├── Widgets/                  # WidgetKit extension
│   │   ├── WidgetsBundle.swift
│   │   └── ...
│   └── AppIntents/               # Siri Shortcuts intents
│       └── ...
├── WatchApp/                     # watchOS app target
│   ├── LifeWrappedWatchApp.swift
│   ├── Views/
│   └── WatchConnectivity/
├── MacApp/                       # Phase 2: macOS app target
│   └── (placeholder)
├── Packages/                     # Local Swift Packages (SPM)
│   ├── SharedModels/             # Data models, enums, protocols
│   ├── Storage/                  # SQLite, migrations, CRUD
│   ├── AudioCapture/             # Recording, chunking, VAD
│   ├── Transcription/            # On-device speech recognition
│   ├── Insights/                 # Stats, rollups, charts
│   ├── Backup/                   # Export/import, encryption
│   ├── Summarization/            # LLM adapter (protocol + mock)
│   └── Sync/                     # CloudKit sync interface (Phase 2)
├── Config/
│   ├── Secrets.example.xcconfig  # Template (committed)
│   ├── Secrets.xcconfig          # Actual secrets (git-ignored)
│   ├── Debug.xcconfig
│   └── Release.xcconfig
├── Scripts/
│   ├── build.sh                  # Build all targets
│   ├── test.sh                   # Run all tests
│   ├── lint.sh                   # SwiftLint / SwiftFormat
│   ├── format.sh                 # Auto-format code
│   ├── verify-privacy.sh         # Network call verification
│   └── export-backup.sh          # Manual backup helper
├── Docs/
│   ├── WORKFLOW.md               # This file
│   ├── ARCHITECTURE.md           # Deep dive on architecture
│   ├── DATA_MODEL.md             # SQLite schema reference
│   ├── PRIVACY.md                # Privacy implementation details
│   └── TESTING.md                # Test strategy & evidence
├── Tests/
│   ├── UnitTests/                # Package unit tests
│   ├── IntegrationTests/         # Cross-package tests
│   ├── UITests/                  # Xcode UI tests
│   └── PerformanceTests/         # XCTest performance tests
├── .gitignore
├── .swiftlint.yml
├── .swiftformat
├── Package.swift                 # Root package (for CLI tools if needed)
├── LifeWrapped.xcworkspace       # Xcode workspace
└── README.md
```

---

## Data Model Overview

### SQLite Tables

| Table                 | Purpose                                    |
| --------------------- | ------------------------------------------ |
| `audio_chunks`        | Metadata for recorded audio files          |
| `transcript_segments` | Transcribed text with timestamps           |
| `summaries`           | AI-generated summaries by period           |
| `insights_rollups`    | Pre-aggregated stats (hour/day/week/month) |
| `control_events`      | User actions log (start/stop/mode/marker)  |

### Time Bucketing Strategy

- **Persist**: Hour, Day, Week, Month rollups
- **Compute on-demand**: Minute/Second zoom from `transcript_segments`
- **Rationale**: Minimize storage while enabling drill-down

---

## Development Workflow

### Daily Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                      VS Code                                │
│  • Edit Swift files                                         │
│  • Swift LSP provides autocomplete, diagnostics             │
│  • SwiftLint/SwiftFormat on save                            │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   Terminal / Scripts                        │
│  • ./Scripts/build.sh         # Quick verification          │
│  • ./Scripts/test.sh          # Run unit tests              │
│  • ./Scripts/lint.sh          # Check style                 │
└─────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                        Xcode                                │
│  • Run on Simulator/Device                                  │
│  • Debug with breakpoints                                   │
│  • Profile with Instruments                                 │
│  • UI Tests                                                 │
└─────────────────────────────────────────────────────────────┘
```

### VS Code Setup

**Required Extensions:**

- `sswg.swift-lang` — Swift Language Support (official)
- `vknabel.vscode-apple-swift-format` — SwiftFormat integration
- `realm.vscode-swift` — Enhanced Swift support (optional)

**Workspace Settings** (`.vscode/settings.json`):

```json
{
  "editor.formatOnSave": true,
  "swift.path": "/usr/bin/swift",
  "swift.buildPath": ".build",
  "[swift]": {
    "editor.defaultFormatter": "vknabel.vscode-apple-swift-format",
    "editor.tabSize": 4,
    "editor.insertSpaces": true
  },
  "files.exclude": {
    "**/.build": true,
    "**/DerivedData": true,
    "**/*.xcuserstate": true
  }
}
```

### Key CLI Commands

```bash
# Build iOS app
xcodebuild -workspace LifeWrapped.xcworkspace \
  -scheme LifeWrapped \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  build

# Run unit tests
xcodebuild -workspace LifeWrapped.xcworkspace \
  -scheme LifeWrappedTests \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test

# Build packages only (faster iteration)
swift build --package-path Packages/Storage

# Run package tests
swift test --package-path Packages/Storage
```

---

## Security & Secrets Management

### Config File Pattern

```
Config/
├── Secrets.example.xcconfig   # Template (committed)
├── Secrets.xcconfig           # Actual values (git-ignored)
├── Debug.xcconfig             # Debug settings
└── Release.xcconfig           # Release settings
```

**Secrets.example.xcconfig:**

```xcconfig
// Copy to Secrets.xcconfig and fill in values
// NEVER commit Secrets.xcconfig

// CloudKit Container (if using sync)
CLOUDKIT_CONTAINER = iCloud.com.yourcompany.lifewrapped

// Any future API keys go here
// SOME_API_KEY =
```

### At-Rest Protection

1. **SQLite Database**: Stored in App Group container with `FileProtectionType.completeUntilFirstUserAuthentication`
2. **Audio Files**: Same container, same protection
3. **Export Files**: Optional AES-256-GCM encryption via CryptoKit
4. **Runtime Secrets**: Keychain (not Info.plist, not source)

---

## Testing Strategy

### Test Pyramid

```
         ╱╲
        ╱  ╲         UI Tests (Xcode)
       ╱────╲        - Toggle listening
      ╱      ╲       - View stats
     ╱        ╲      - Export flow
    ╱──────────╲
   ╱            ╲    Integration Tests
  ╱              ╲   - Audio → Transcribe → Persist
 ╱                ╲  - Backup → Restore round-trip
╱──────────────────╲
         │           Unit Tests (per package)
         │           - Storage CRUD
         │           - Insights calculations
         │           - Backup serialization
```

### Privacy Verification

**Reproducible "No Network Calls" Proof:**

1. **Instruments Network Template**: Record app session, verify zero network activity
2. **Charles Proxy**: Run app through proxy, confirm no HTTP/S traffic
3. **Network Link Conditioner**: Set to 100% loss, app must function normally
4. **Code Audit**: Script to grep for URL/network APIs (allowed: CloudKit when user-enabled)

```bash
# Scripts/verify-privacy.sh
# Searches for unauthorized network usage
grep -r "URLSession\|URLRequest\|Alamofire\|AF\." --include="*.swift" \
  Packages/ App/ WatchApp/ Extensions/ \
  | grep -v "// PRIVACY-ALLOWED:" \
  | grep -v "Tests/"
```

---

## Step-by-Step Implementation Plan

| Step   | Title              | Scope                                                  |
| ------ | ------------------ | ------------------------------------------------------ |
| **0**  | Repo Setup         | .gitignore, secrets config, VS Code workspace, scripts |
| **1**  | Xcode Project Init | iOS SwiftUI app, local packages, xcodebuild baseline   |
| **2**  | Storage Package    | SQLite, migrations, CRUD, App Group, time queries      |
| **3**  | Insights Package   | Rollups, charts, period views, on-demand zoom          |
| **4**  | Audio Capture      | Chunking, state machine, Active/Passive, background    |
| **5**  | Transcription      | Streaming + batch, timestamps, persistence             |
| **6**  | Backup Package     | JSON export/import, encryption, merge strategy         |
| **7**  | iCloud Backup      | User-triggered encrypted artifact backup               |
| **8**  | Widgets            | Status, stats, snippet, summary; App Group reads       |
| **9**  | Siri Shortcuts     | App Intents for all actions                            |
| **10** | Watch App          | WatchConnectivity, glance UI, complication             |
| **11** | Summarization      | Protocol + mock; on-device LLM placeholder             |
| **12** | Testing & Proof    | Full test suite + privacy verification                 |
| **13** | macOS Phase 2      | Add target, reuse packages, sync strategy              |

---

## Feature Flags & Progressive Rollout

```swift
// SharedModels/Sources/FeatureFlags.swift
public enum FeatureFlag: String, CaseIterable {
    case passiveListening = "passive_listening"
    case onDeviceSummarization = "on_device_summarization"
    case cloudKitSync = "cloudkit_sync"
    case watchApp = "watch_app"
    case speakerDiarization = "speaker_diarization"  // Future
}
```

---

## Appendix: GitHub Repository Setup

### Option A: GitHub UI

1. Go to https://github.com/new
2. Repository name: `life-wrapped`
3. Description: "Privacy-first on-device audio journaling for iOS/watchOS/macOS"
4. Visibility: Private (or Public)
5. **Do NOT** initialize with README (we'll add our own)
6. Click "Create repository"
7. Follow the "push an existing repository" instructions

### Option B: GitHub CLI

```bash
cd /Users/username/Git/life-wrapped

# Create remote repo
gh repo create life-wrapped --private --source=. --remote=origin

# Or if repo exists, just set remote
git remote add origin https://github.com/jsayram/life-wrapped.git
git branch -M main
git push -u origin main
```

---

## Quick Reference

| Task          | Command                        |
| ------------- | ------------------------------ |
| Build iOS     | `./Scripts/build.sh ios`       |
| Build Watch   | `./Scripts/build.sh watch`     |
| Run Tests     | `./Scripts/test.sh`            |
| Lint          | `./Scripts/lint.sh`            |
| Format        | `./Scripts/format.sh`          |
| Privacy Check | `./Scripts/verify-privacy.sh`  |
| Open Xcode    | `open LifeWrapped.xcworkspace` |

---

**Next Step**: Proceed to Step 0 — Repo creation + .gitignore + secrets/config + VS Code workspace + scripts
