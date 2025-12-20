# AI Architecture (Local + External)

Comprehensive guide to how Life Wrapped wires AI summarization engines on iOS with Swift 6.2, covering both on-device (Local AI) and remote (Year Wrapped Pro AI) engines. Use this as a playbook to replicate or extend the setup.

---

## Table of Contents

1. [Prerequisites & Requirements](#prerequisites--requirements)
2. [Goals & Principles](#goals--principles)
3. [Engine Overview](#engine-overview)
4. [Project Setup from Scratch](#project-setup-from-scratch)
5. [Local AI Setup (Phi-3.5 via llama.cpp)](#local-ai-setup-phi-35-via-llamacpp)
6. [External AI Setup (OpenAI/Anthropic)](#external-ai-setup-openai-anthropic)
7. [Core Components](#core-components-swift-packages)
8. [Version Matrix](#version-matrix)
9. [Data Flow](#data-flow-session-summaries)
10. [Engine Selection & Availability](#engine-selection--availability)
11. [Universal Prompt & Schemas](#universal-prompt--schemas)
12. [Troubleshooting & Lessons Learned](#things-we-learned-to-watch-out-for)
13. [Quick Reference](#quick-reference)

---

## Prerequisites & Requirements

### Development Environment

| Requirement | Version     | Notes                                                   |
| ----------- | ----------- | ------------------------------------------------------- |
| macOS       | Tahoe 26.0+ | Required for Xcode 26                                   |
| Xcode       | 26.x        | Swift 6.2 support                                       |
| Swift       | 6.2         | Strict concurrency enabled                              |
| iOS Target  | 18.0+       | For Apple Intelligence; 17.0 minimum for basic features |

### Device Requirements (Local AI)

| Device          | RAM   | Local AI Support | Notes                  |
| --------------- | ----- | ---------------- | ---------------------- |
| iPhone 15 Pro+  | 8GB   | ✅ Full          | Best performance       |
| iPhone 14 Pro   | 6GB   | ✅ Good          | Constrained context    |
| iPhone 13/14    | 4-6GB | ⚠️ Limited       | May need smaller model |
| iPhone SE/older | <4GB  | ❌ No            | Use External AI only   |
| Simulator       | N/A   | ⚠️ Slow          | CPU-only, for testing  |

### Required Capabilities

```xml
<!-- Info.plist additions -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>

<!-- For microphone (if recording) -->
<key>NSMicrophoneUsageDescription</key>
<string>Record audio for transcription and summarization</string>

<!-- For speech recognition (if using) -->
<key>NSSpeechRecognitionUsageDescription</key>
<string>Transcribe your recordings on-device</string>
```

### Entitlements

```xml
<!-- App.entitlements -->
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.yourcompany.yourapp</string>
</array>

<!-- Keychain sharing for API keys -->
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.yourcompany.yourapp</string>
</array>
```

---

## Goals & Principles

- Privacy-first: default to on-device; external calls require explicit API keys.
- Strict concurrency: Swift 6 `actor` isolation for storage; `@MainActor` for UI-bound managers.
- Schema-first prompts: Universal JSON schemas per summary level (session/day/week/month/year).
- Clear fallbacks: graceful degradations when a chosen engine is unavailable.

## Engine Overview

- **Local AI**: Phi-3.5 (instruct) via `llama.cpp` (SwiftLlama patched). Fully offline.
- **External AI (Year Wrapped Pro AI)**: OpenAI `gpt-4o-mini` (default) with Anthropic optional. JSON responses parsed into structured summaries.

## Core Components (Swift packages)

- `SummarizationCoordinator` (actor): orchestrates engine selection, availability checks, preference persistence.
- `UniversalPrompt`: builds schema-specific prompts for all levels.
- `ExternalAPIEngine`: wraps OpenAI/Anthropic chat completion APIs; parses JSON into domain models.
- `LocalEngine` + `LocalLLM`: loads Phi-3.5 GGUF, builds Phi-style prompts, streams tokens locally.
- `DatabaseManager` (actor): stores summaries, transcripts, rollups (SQLite).
- `AppCoordinator` (`@MainActor`): entry point that requests summaries and persists results.

---

## Project Setup from Scratch

### Step 1: Create Swift Package Structure

Your project should have a modular package structure:

```
YourApp/
├── App/                          # Main iOS app target
│   ├── Coordinators/
│   │   └── AppCoordinator.swift  # @MainActor, orchestrates everything
│   └── ContentView.swift
├── Packages/
│   ├── LocalLLM/                 # Local AI package
│   │   ├── Package.swift
│   │   └── Sources/LocalLLM/
│   │       └── LocalLLM.swift
│   ├── Summarization/            # Engine coordination
│   │   ├── Package.swift
│   │   └── Sources/Summarization/
│   │       ├── SummarizationCoordinator.swift
│   │       ├── SummarizationEngine.swift  # Protocol
│   │       ├── LocalEngine.swift
│   │       ├── ExternalAPIEngine.swift
│   │       └── UniversalPrompt.swift
│   ├── SharedModels/             # Shared data types
│   └── Storage/                  # SQLite database
└── Config/
    └── Secrets.xcconfig          # API keys (gitignored)
```

### Step 2: Define the SummarizationEngine Protocol

```swift
// SummarizationEngine.swift
import Foundation

public enum EngineTier: String, Codable, Sendable, CaseIterable {
    case basic = "basic"
    case apple = "apple"
    case local = "local"
    case external = "external"

    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .apple: return "Apple Intelligence"
        case .local: return "Local AI"
        case .external: return "Year Wrapped Pro AI"
        }
    }
}

public protocol SummarizationEngine: Actor {
    var tier: EngineTier { get }

    func isAvailable() async -> Bool

    func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence

    func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) async throws -> PeriodIntelligence
}
```

### Step 3: Add Swift Package Dependencies

#### For Local AI (llama.cpp)

```swift
// Packages/LocalLLM/Package.swift
import PackageDescription

let package = Package(
    name: "LocalLLM",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LocalLLM", targets: ["LocalLLM"]),
    ],
    dependencies: [
        // Option A: Use official llama.cpp Swift bindings
        .package(url: "https://github.com/ggerganov/llama.cpp.git",
                 revision: "b6d6c52"),

        // Option B: Use a Swift wrapper like SwiftLlama (recommended)
        // We use a patched local version for iOS compatibility
        .package(path: "../SwiftLlamaPatched"),
    ],
    targets: [
        .target(
            name: "LocalLLM",
            dependencies: [
                .product(name: "llama", package: "llama.cpp"),
                // OR for SwiftLlama:
                .product(name: "SwiftLlama", package: "SwiftLlamaPatched"),
            ]
        ),
    ]
)
```

#### SwiftLlama Patched Setup

If using SwiftLlama, you need a local patched version for iOS:

```swift
// Packages/SwiftLlamaPatched/Package.swift
import PackageDescription

let package = Package(
    name: "SwiftLlama",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/llama.cpp.git",
                 revision: "b6d6c52"),
    ],
    targets: [
        .target(
            name: "SwiftLlama",
            dependencies: [
                .product(name: "llama", package: "llama.cpp"),
            ]
        ),
    ]
)
```

### Step 4: Configure Build Settings

Add to your Xcode project or xcconfig:

```xcconfig
# For llama.cpp Metal support on device
OTHER_LDFLAGS = $(inherited) -framework Metal -framework MetalKit -framework Accelerate

# Disable GPU layers on simulator (CPU only)
# This is handled in code with #if targetEnvironment(simulator)
```

---

## Local AI Setup (Phi-3.5 via llama.cpp)

### Supported Models

| Model                     | Size    | RAM Required | Quality  | Speed    | Best For                  |
| ------------------------- | ------- | ------------ | -------- | -------- | ------------------------- |
| **Phi-3.5 Mini Instruct** | ~770 MB | 4GB+         | ⭐⭐⭐⭐ | ⭐⭐⭐   | Best quality, recommended |
| **Llama 3.2 1B Instruct** | ~670 MB | 3GB+         | ⭐⭐⭐   | ⭐⭐⭐⭐ | Faster, lower RAM devices |

### Model Configuration Matrix

| Property         | Phi-3.5 Mini                        | Llama 3.2 1B                        |
| ---------------- | ----------------------------------- | ----------------------------------- | ---- | ---- | ------ | ---- |
| GGUF File        | `Phi-3.5-mini-instruct-Q4_K_M.gguf` | `Llama-3.2-1B-Instruct-Q4_K_M.gguf` |
| File Size        | ~770-810 MB                         | ~670-720 MB                         |
| Prompt Type      | `.phi`                              | `.llama3`                           |
| Stop Tokens      | `["<                                | end                                 | >"]` | `["< | eot_id | >"]` |
| Context Window   | 128K (use 1024-4096)                | 128K (use 1024-4096)                |
| Recommended nCTX | 1024                                | 1024                                |
| Recommended Temp | 0.2                                 | 0.3                                 |

---

### Step 1: Download the Models

#### Phi-3.5 Mini Instruct (Recommended)

```bash
# From Hugging Face - Phi-3.5 Mini Instruct Q4_K_M
curl -L -o Phi-3.5-mini-instruct-Q4_K_M.gguf \
  "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf"

# Verify file size (~770-810 MB)
ls -lh Phi-3.5-mini-instruct-Q4_K_M.gguf
```

#### Llama 3.2 1B Instruct (Lightweight Alternative)

```bash
# From Hugging Face - Llama 3.2 1B Instruct Q4_K_M
curl -L -o Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf"

# Verify file size (~670-720 MB)
ls -lh Llama-3.2-1B-Instruct-Q4_K_M.gguf
```

---

### Step 2: Model Enum & Configuration

```swift
// ModelType.swift
import Foundation

public enum LocalModelType: String, Codable, CaseIterable, Sendable {
    case phi35 = "phi-3.5"
    case llama32 = "llama-3.2"

    public var displayName: String {
        switch self {
        case .phi35: return "Phi-3.5 Mini"
        case .llama32: return "Llama 3.2 1B"
        }
    }

    public var filename: String {
        switch self {
        case .phi35: return "Phi-3.5-mini-instruct-Q4_K_M.gguf"
        case .llama32: return "Llama-3.2-1B-Instruct-Q4_K_M.gguf"
        }
    }

    public var downloadURL: URL {
        switch self {
        case .phi35:
            return URL(string: "https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf")!
        case .llama32:
            return URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!
        }
    }

    public var expectedSizeMB: ClosedRange<Int64> {
        switch self {
        case .phi35: return 700...900   // ~770 MB
        case .llama32: return 600...800 // ~670 MB
        }
    }

    /// CRITICAL: Prompt type must match model family
    public var promptType: Prompt.`Type` {
        switch self {
        case .phi35: return .phi      // <|user|>...<|end|><|assistant|>
        case .llama32: return .llama3 // <|start_header_id|>...<|eot_id|>
        }
    }

    /// CRITICAL: Stop tokens must match model family
    public var stopTokens: [String] {
        switch self {
        case .phi35: return StopToken.phi      // ["<|end|>"]
        case .llama32: return StopToken.llama3 // ["<|eot_id|>"]
        }
    }

    public var recommendedConfig: (nCTX: Int32, batch: Int32, maxTokens: Int32, temp: Float) {
        switch self {
        case .phi35:
            return (nCTX: 1024, batch: 128, maxTokens: 512, temp: 0.2)
        case .llama32:
            return (nCTX: 1024, batch: 128, maxTokens: 512, temp: 0.3)
        }
    }
}
```

---

### Step 3: Prompt Formats (CRITICAL - Model Family Specific)

#### Phi-3/3.5 Prompt Format

```
<system prompt here>
<|user|>
<user message here>
<|end|>
<|assistant|>
```

**SwiftLlama Implementation:**

```swift
// Prompt.swift - encodePhiPrompt()
private func encodePhiPrompt() -> String {
    """
    \(systemPrompt)
    \(history.suffix(Configuration.historySize).map { $0.phiPrompt }.joined())
    <|user|>
    \(userMessage)
    <|end|>
    <|assistant|>
    """
}
```

#### Llama 3/3.1/3.2 Prompt Format

```
<|begin_of_text|><|start_header_id|>system<|end_header_id|>

Cutting Knowledge Date: December 2023
Today Date: 20 Dec 2025

<system prompt here><|eot_id|>
<|start_header_id|>user<|end_header_id|>
<user message here><|eot_id|>
<|start_header_id|>assistant<|end_header_id|>
```

**SwiftLlama Implementation:**

```swift
// Prompt.swift - encodeLlama3Prompt()
private func encodeLlama3Prompt() -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.timeZone = TimeZone.current
    df.dateFormat = "d MMM yyyy"
    let today = df.string(from: Date())

    let systemBlock = """
    <|start_header_id|>system<|end_header_id|>

    Cutting Knowledge Date: December 2023
    Today Date: \(today)

    \(systemPrompt)<|eot_id|>
    """

    let historyBlock = history.suffix(Configuration.historySize)
        .map { $0.llama3Prompt }
        .joined(separator: "\n")

    let tail = """
    <|start_header_id|>user<|end_header_id|>
    \(userMessage)<|eot_id|>
    <|start_header_id|>assistant<|end_header_id|>
    """

    return [systemBlock, historyBlock, tail]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
}
```

---

### Step 4: Stop Tokens (CRITICAL - Must Match Model)

```swift
// StopToken.swift
public enum StopToken {}

public extension StopToken {
    /// Phi-3, Phi-3.5 models
    static var phi: [String] {
        ["<|end|>"]
    }

    /// Llama 3, 3.1, 3.2 models
    static var llama3: [String] {
        ["<|eot_id|>"]
    }

    /// Llama 2 models (legacy)
    static var llama: [String] {
        ["[/INST]"]
    }

    /// ChatML format (Mistral, some fine-tunes)
    static var chatML: [String] {
        ["<|im_end|>"]
    }
}
```

**⚠️ CRITICAL WARNING:**
Using the wrong stop tokens causes the model to either:

- Stop after 1 token (if it sees an unknown special token)
- Never stop (if it never sees its expected end token)

---

### Step 5: Multi-Model LlamaContext

```swift
// LlamaContext.swift
import Foundation
import SwiftLlama

public actor LlamaContext {
    private var llama: SwiftLlama?
    private var isLoaded = false
    private var currentModelType: LocalModelType?
    private let modelFileManager: ModelFileManager

    public init(modelFileManager: ModelFileManager = .shared) {
        self.modelFileManager = modelFileManager
    }

    /// Load a specific model
    public func loadModel(_ modelType: LocalModelType) async throws {
        // Unload current model if different
        if currentModelType != modelType {
            await unloadModel()
        }

        guard !isLoaded else { return }

        let modelURL = try await modelFileManager.modelURL(filename: modelType.filename)

        // Verify file size matches expected range
        let attrs = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let sizeMB = ((attrs[.size] as? Int64) ?? 0) / 1_048_576
        guard modelType.expectedSizeMB.contains(sizeMB) else {
            throw LocalLLMError.modelLoadFailed("Invalid model size: \(sizeMB) MB, expected \(modelType.expectedSizeMB)")
        }

        print("⚙️ [LlamaContext] Loading \(modelType.displayName)...")

        let cfg = modelType.recommendedConfig
        let config = Configuration(
            topK: 30,
            topP: 0.9,
            nCTX: cfg.nCTX,
            temperature: cfg.temp,
            batchSize: cfg.batch,
            maxTokenCount: cfg.maxTokens,
            stopTokens: modelType.stopTokens  // CRITICAL: Use model-specific stop tokens
        )

        // Load off main thread
        let modelPath = modelURL.path
        llama = try await Task.detached(priority: .userInitiated) {
            try SwiftLlama(modelPath: modelPath, modelConfiguration: config)
        }.value

        currentModelType = modelType
        isLoaded = true
        print("✅ [LlamaContext] \(modelType.displayName) loaded successfully")
    }

    /// Generate text using the loaded model
    public func generate(prompt: String) async throws -> String {
        guard let llama = llama, let modelType = currentModelType, isLoaded else {
            throw LocalLLMError.modelNotLoaded
        }

        // CRITICAL: Use the correct prompt type for the loaded model
        let promptObj = Prompt(
            type: modelType.promptType,  // .phi for Phi, .llama3 for Llama
            systemPrompt: "You are a helpful AI assistant.",
            userMessage: prompt
        )

        print("🎯 [LlamaContext] Generating with \(modelType.displayName)...")
        print("   Prompt type: \(modelType.promptType)")
        print("   Stop tokens: \(modelType.stopTokens)")

        var result = ""
        var tokenCount = 0

        for try await token in await llama.start(for: promptObj) {
            result += token
            tokenCount += 1
            if tokenCount % 50 == 0 {
                print("   Generated \(tokenCount) tokens...")
            }
        }

        print("✅ [LlamaContext] Generated \(result.count) chars (\(tokenCount) tokens)")
        return result
    }

    /// Unload current model
    public func unloadModel() async {
        guard isLoaded else { return }
        print("📤 [LlamaContext] Unloading \(currentModelType?.displayName ?? "model")")
        llama = nil
        isLoaded = false
        currentModelType = nil
    }

    public func isReady() -> Bool {
        return isLoaded && llama != nil
    }

    public func getLoadedModel() -> LocalModelType? {
        return currentModelType
    }
}
```

---

### Step 6: Model Selection UI

```swift
// LocalAISettingsView.swift
import SwiftUI

struct LocalAISettingsView: View {
    @State private var selectedModel: LocalModelType = .phi35
    @State private var downloadedModels: Set<LocalModelType> = []
    @State private var downloadingModel: LocalModelType?
    @State private var downloadProgress: Double = 0

    var body: some View {
        Form {
            Section("Available Models") {
                ForEach(LocalModelType.allCases, id: \.self) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.displayName)
                                .font(.headline)
                            Text(model.filename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if downloadedModels.contains(model) {
                            if selectedModel == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Button("Select") {
                                    selectedModel = model
                                    // Save preference
                                    UserDefaults.standard.set(model.rawValue, forKey: "selectedLocalModel")
                                }
                                .buttonStyle(.bordered)
                            }
                        } else if downloadingModel == model {
                            ProgressView(value: downloadProgress)
                                .frame(width: 60)
                        } else {
                            Button("Download") {
                                Task { await downloadModel(model) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Model Info") {
                if let model = selectedModel as LocalModelType? {
                    LabeledContent("Prompt Format", value: String(describing: model.promptType))
                    LabeledContent("Stop Token", value: model.stopTokens.joined())
                    LabeledContent("File Size", value: "~\(model.expectedSizeMB.lowerBound) MB")
                }
            }
        }
        .task {
            await checkDownloadedModels()
        }
    }

    private func checkDownloadedModels() async {
        for model in LocalModelType.allCases {
            if await ModelFileManager.shared.modelExists(filename: model.filename) {
                downloadedModels.insert(model)
            }
        }
    }

    private func downloadModel(_ model: LocalModelType) async {
        downloadingModel = model
        downloadProgress = 0

        do {
            _ = try await ModelFileManager.shared.downloadModel(
                from: model.downloadURL,
                filename: model.filename
            )
            downloadedModels.insert(model)
        } catch {
            print("❌ Download failed: \(error)")
        }

        downloadingModel = nil
    }
}
```

---

### Step 7: Model-Aware LocalEngine

```swift
// LocalEngine.swift (updated for multi-model support)
import Foundation
import LocalLLM

public actor LocalEngine: SummarizationEngine {
    private let storage: DatabaseManager
    private let llamaContext: LlamaContext
    private var currentModel: LocalModelType = .phi35

    public nonisolated var tier: EngineTier { .local }

    public init(storage: DatabaseManager) {
        self.storage = storage
        self.llamaContext = LlamaContext()

        // Load saved model preference
        if let saved = UserDefaults.standard.string(forKey: "selectedLocalModel"),
           let model = LocalModelType(rawValue: saved) {
            self.currentModel = model
        }
    }

    public func isAvailable() async -> Bool {
        return await llamaContext.isReady()
    }

    public func loadModel(_ model: LocalModelType? = nil) async throws {
        let modelToLoad = model ?? currentModel
        try await llamaContext.loadModel(modelToLoad)
        currentModel = modelToLoad
    }

    public func switchModel(to model: LocalModelType) async throws {
        currentModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "selectedLocalModel")
        try await llamaContext.loadModel(model)
    }

    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {

        // Ensure model is loaded
        if !await llamaContext.isReady() {
            try await loadModel()
        }

        // Build prompt
        let prompt = UniversalPrompt.build(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )

        // Generate - LlamaContext uses correct prompt type and stop tokens
        // based on the loaded model
        let response = try await llamaContext.generate(prompt: prompt)

        // Parse response...
        return try parseResponse(response, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
    }

    private func parseResponse(_ response: String, sessionId: UUID, duration: TimeInterval, languageCodes: [String]) throws -> SessionIntelligence {
        // JSON parsing logic...
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Fallback
            return createExtractivesFallback(sessionId: sessionId, text: response, duration: duration)
        }

        // Parse from schema fields...
        let summary = buildSummaryFromSessionSchema(json)
        let topics = (json["main_themes"] as? [String]) ?? []

        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: [],
            sentiment: 0.0,
            duration: duration,
            wordCount: response.split(separator: " ").count,
            languageCodes: languageCodes,
            keyMoments: nil
        )
    }
}
```

---

### Model Comparison: Phi-3.5 vs Llama 3.2

| Aspect                    | Phi-3.5 Mini                     | Llama 3.2 1B                      |
| ------------------------- | -------------------------------- | --------------------------------- |
| **Parameters**            | 3.8B                             | 1B                                |
| **Quality**               | Higher quality, better reasoning | Good for simple tasks             |
| **Speed**                 | Slightly slower                  | Faster                            |
| **RAM Usage**             | ~2-3 GB                          | ~1.5-2 GB                         |
| **Best For**              | Complex summarization, JSON      | Simple summaries, low-end devices |
| **JSON Reliability**      | ⭐⭐⭐⭐                         | ⭐⭐⭐                            |
| **Instruction Following** | Excellent                        | Good                              |

**Recommendation:**

- Use **Phi-3.5** as default for best quality
- Offer **Llama 3.2 1B** as fallback for devices with <4GB RAM
- Let users choose based on their device capabilities

---

### Step 2: Model Storage Strategy

```swift
// ModelFileManager.swift
import Foundation

public actor ModelFileManager {
    public static let shared = ModelFileManager()

    private let fileManager = FileManager.default

    /// App's documents directory for downloaded models
    public var modelsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Models", isDirectory: true)
    }

    /// Check if model exists
    public func modelExists(filename: String) -> Bool {
        let url = modelsDirectory.appendingPathComponent(filename)
        return fileManager.fileExists(atPath: url.path)
    }

    /// Get model URL
    public func modelURL(filename: String) throws -> URL {
        let url = modelsDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            throw LocalLLMError.modelNotFound("Model not found: \(filename)")
        }

        // Verify file size (Phi-3.5 Q4_K_M should be ~770-810 MB)
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? Int64) ?? 0
        let sizeMB = size / 1_048_576

        guard sizeMB > 700 && sizeMB < 900 else {
            throw LocalLLMError.modelLoadFailed("Invalid model size: \(sizeMB) MB")
        }

        return url
    }

    /// Download model from URL (implement with URLSession)
    public func downloadModel(from url: URL, filename: String) async throws -> URL {
        // Create directory if needed
        try? fileManager.createDirectory(at: modelsDirectory,
                                         withIntermediateDirectories: true)

        let destination = modelsDirectory.appendingPathComponent(filename)

        // Download with progress tracking
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try fileManager.moveItem(at: tempURL, to: destination)

        return destination
    }
}
```

### Step 3: LlamaContext Implementation

```swift
// LlamaContext.swift
import Foundation
import SwiftLlama  // Or your llama.cpp wrapper

public actor LlamaContext {
    private var llama: SwiftLlama?
    private var isLoaded = false
    private let modelFileManager: ModelFileManager

    public init(modelFileManager: ModelFileManager = .shared) {
        self.modelFileManager = modelFileManager
    }

    /// Load the model with mobile-optimized configuration
    public func loadModel() async throws {
        guard !isLoaded else { return }

        let modelURL = try await modelFileManager.modelURL(filename: "phi-3.5-mini-instruct-q4_k_m.gguf")

        print("⚙️ [LlamaContext] Loading model with constrained config...")

        // CRITICAL: Mobile-optimized configuration
        let config = Configuration(
            topK: 30,
            topP: 0.9,
            nCTX: 1024,           // Context size (reduce for low RAM)
            temperature: 0.2,     // Low temp for consistent JSON
            batchSize: 128,       // Batch size
            maxTokenCount: 512,   // Max output tokens
            stopTokens: StopToken.phi  // ["<|end|>"] for Phi models
        )

        // Load model off main thread
        let modelPath = modelURL.path
        llama = try await Task.detached(priority: .userInitiated) {
            try SwiftLlama(modelPath: modelPath, modelConfiguration: config)
        }.value

        isLoaded = true
        print("✅ [LlamaContext] Model loaded successfully")
    }

    /// Generate text with Phi prompt format
    public func generate(prompt: String) async throws -> String {
        guard let llama = llama, isLoaded else {
            throw LocalLLMError.modelNotLoaded
        }

        // CRITICAL: Use .phi prompt type for Phi-3.5 model
        let promptObj = Prompt(
            type: .phi,  // NOT .llama3 - wrong format causes 1-token output!
            systemPrompt: "You are a helpful AI assistant.",
            userMessage: prompt
        )

        var result = ""
        for try await token in await llama.start(for: promptObj) {
            result += token
        }

        return result
    }

    public func isReady() -> Bool {
        return isLoaded && llama != nil
    }
}
```

### Step 4: Phi Prompt Format (CRITICAL)

The Phi model family uses a specific prompt format. Using the wrong format causes immediate stop:

```swift
// Correct Phi-3 prompt format
"""
<system prompt here>
<|user|>
<user message here>
<|end|>
<|assistant|>
"""

// SwiftLlama's Prompt.swift encodes this as:
private func encodePhiPrompt() -> String {
    """
    \(systemPrompt)
    \(history.suffix(Configuration.historySize).map { $0.phiPrompt }.joined())
    <|user|>
    \(userMessage)
    <|end|>
    <|assistant|>
    """
}
```

### Step 5: Stop Tokens (CRITICAL)

```swift
// StopToken.swift
public enum StopToken {}

public extension StopToken {
    static var phi: [String] {
        ["<|end|>"]  // Phi-3/3.5 end token
    }

    static var llama3: [String] {
        ["<|eot_id|>"]  // Llama 3 end token - DO NOT use for Phi!
    }

    static var chatML: [String] {
        ["<|im_end|>"]  // ChatML format
    }
}
```

### Step 6: LocalEngine Implementation

```swift
// LocalEngine.swift
import Foundation
import LocalLLM

public actor LocalEngine: SummarizationEngine {
    private let storage: DatabaseManager
    private let llamaContext: LlamaContext

    public nonisolated var tier: EngineTier { .local }

    public init(storage: DatabaseManager) {
        self.storage = storage
        self.llamaContext = LlamaContext()
    }

    public func isAvailable() async -> Bool {
        // Check if model is loaded and ready
        return await llamaContext.isReady()
    }

    public func loadModel() async throws {
        try await llamaContext.loadModel()
    }

    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {

        // Build prompt using universal schema
        let prompt = UniversalPrompt.build(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )

        // Generate with local model
        let response = try await llamaContext.generate(prompt: prompt)

        // Parse JSON response
        guard let jsonData = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Fallback to extractive summary if JSON parsing fails
            return createExtractivesFallback(sessionId: sessionId, text: transcriptText, duration: duration)
        }

        return parseSessionJSON(json, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
    }

    private func createExtractivesFallback(sessionId: UUID, text: String, duration: TimeInterval) -> SessionIntelligence {
        // Simple extractive summary when LLM fails
        let words = text.split(separator: " ")
        let summary = words.prefix(50).joined(separator: " ") + "..."

        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: [],
            entities: [],
            sentiment: 0.0,
            duration: duration,
            wordCount: words.count,
            languageCodes: [],
            keyMoments: nil
        )
    }
}
```

---

## External AI Setup (OpenAI/Anthropic)

### Supported Providers & Models

#### OpenAI Models

| Model           | Context | Cost | Speed      | Quality    | Best For                   |
| --------------- | ------- | ---- | ---------- | ---------- | -------------------------- |
| **gpt-4o-mini** | 128K    | $    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   | **Default** - Best balance |
| gpt-4o          | 128K    | $$$  | ⭐⭐⭐⭐   | ⭐⭐⭐⭐⭐ | Highest quality            |
| gpt-4-turbo     | 128K    | $$   | ⭐⭐⭐     | ⭐⭐⭐⭐⭐ | Complex reasoning          |
| gpt-3.5-turbo   | 16K     | $    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐     | Budget option              |

#### Anthropic Models

| Model                          | Context | Cost | Speed      | Quality    | Best For                   |
| ------------------------------ | ------- | ---- | ---------- | ---------- | -------------------------- |
| **claude-3-5-sonnet-20241022** | 200K    | $$   | ⭐⭐⭐⭐   | ⭐⭐⭐⭐⭐ | **Default** - Best quality |
| claude-3-5-haiku-20241022      | 200K    | $    | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐   | Fast & affordable          |
| claude-3-opus-20240229         | 200K    | $$$  | ⭐⭐⭐     | ⭐⭐⭐⭐⭐ | Most capable               |

### Model Configuration

```swift
// ExternalModelType.swift
import Foundation

public enum ExternalProvider: String, Codable, CaseIterable, Sendable {
    case openai = "openai"
    case anthropic = "anthropic"

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    public var baseURL: URL {
        switch self {
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        }
    }

    public var availableModels: [ExternalModel] {
        switch self {
        case .openai: return ExternalModel.openAIModels
        case .anthropic: return ExternalModel.anthropicModels
        }
    }

    public var defaultModel: ExternalModel {
        switch self {
        case .openai: return .gpt4oMini
        case .anthropic: return .claude35Sonnet
        }
    }
}

public enum ExternalModel: String, Codable, CaseIterable, Sendable {
    // OpenAI Models
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o = "gpt-4o"
    case gpt4Turbo = "gpt-4-turbo"
    case gpt35Turbo = "gpt-3.5-turbo"

    // Anthropic Models
    case claude35Sonnet = "claude-3-5-sonnet-20241022"
    case claude35Haiku = "claude-3-5-haiku-20241022"
    case claude3Opus = "claude-3-opus-20240229"

    public var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o Mini"
        case .gpt4o: return "GPT-4o"
        case .gpt4Turbo: return "GPT-4 Turbo"
        case .gpt35Turbo: return "GPT-3.5 Turbo"
        case .claude35Sonnet: return "Claude 3.5 Sonnet"
        case .claude35Haiku: return "Claude 3.5 Haiku"
        case .claude3Opus: return "Claude 3 Opus"
        }
    }

    public var provider: ExternalProvider {
        switch self {
        case .gpt4oMini, .gpt4o, .gpt4Turbo, .gpt35Turbo:
            return .openai
        case .claude35Sonnet, .claude35Haiku, .claude3Opus:
            return .anthropic
        }
    }

    public var contextWindow: Int {
        switch self {
        case .gpt4oMini, .gpt4o, .gpt4Turbo: return 128_000
        case .gpt35Turbo: return 16_385
        case .claude35Sonnet, .claude35Haiku, .claude3Opus: return 200_000
        }
    }

    public var maxOutputTokens: Int {
        switch self {
        case .gpt4oMini, .gpt4o: return 16_384
        case .gpt4Turbo: return 4_096
        case .gpt35Turbo: return 4_096
        case .claude35Sonnet, .claude35Haiku: return 8_192
        case .claude3Opus: return 4_096
        }
    }

    public var costTier: String {
        switch self {
        case .gpt4oMini, .gpt35Turbo, .claude35Haiku: return "$"
        case .gpt4Turbo, .claude35Sonnet: return "$$"
        case .gpt4o, .claude3Opus: return "$$$"
        }
    }

    public var recommendedTemperature: Double {
        switch self {
        case .gpt4oMini, .gpt4o, .gpt4Turbo, .gpt35Turbo: return 0.7
        case .claude35Sonnet, .claude35Haiku, .claude3Opus: return 0.7
        }
    }

    public var recommendedMaxTokens: Int {
        switch self {
        // Session summaries need ~500-2000 tokens
        case .gpt4oMini, .gpt4o: return 2000
        case .gpt4Turbo, .gpt35Turbo: return 2000
        case .claude35Sonnet, .claude35Haiku: return 2000
        case .claude3Opus: return 2000
        }
    }

    public static var openAIModels: [ExternalModel] {
        [.gpt4oMini, .gpt4o, .gpt4Turbo, .gpt35Turbo]
    }

    public static var anthropicModels: [ExternalModel] {
        [.claude35Sonnet, .claude35Haiku, .claude3Opus]
    }
}
```

### API Request Formats

#### OpenAI Chat Completions API

```swift
// Request format
let body: [String: Any] = [
    "model": model.rawValue,  // e.g., "gpt-4o-mini"
    "messages": [
        ["role": "system", "content": systemPrompt],
        ["role": "user", "content": userPrompt]
    ],
    "temperature": model.recommendedTemperature,
    "max_tokens": model.recommendedMaxTokens,
    "response_format": ["type": "json_object"]  // Optional: Force JSON
]

// Headers
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// Response structure
{
    "id": "chatcmpl-xxx",
    "object": "chat.completion",
    "model": "gpt-4o-mini",
    "choices": [{
        "index": 0,
        "message": {
            "role": "assistant",
            "content": "{\"title\": \"...\", \"key_insights\": [...]}"
        },
        "finish_reason": "stop"
    }],
    "usage": {
        "prompt_tokens": 150,
        "completion_tokens": 250,
        "total_tokens": 400
    }
}
```

#### Anthropic Messages API

```swift
// Request format
let body: [String: Any] = [
    "model": model.rawValue,  // e.g., "claude-3-5-sonnet-20241022"
    "max_tokens": model.recommendedMaxTokens,
    "system": systemPrompt,
    "messages": [
        ["role": "user", "content": userPrompt]
    ]
]

// Headers
request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// Response structure
{
    "id": "msg_xxx",
    "type": "message",
    "role": "assistant",
    "model": "claude-3-5-sonnet-20241022",
    "content": [{
        "type": "text",
        "text": "{\"title\": \"...\", \"key_insights\": [...]}"
    }],
    "stop_reason": "end_turn",
    "usage": {
        "input_tokens": 150,
        "output_tokens": 250
    }
}
```

### Multi-Model ExternalAPIEngine

```swift
// ExternalAPIEngine.swift (with multi-model support)
import Foundation

public actor ExternalAPIEngine: SummarizationEngine {
    private let storage: DatabaseManager
    private let keychainManager: KeychainManager

    // Current configuration
    private var selectedProvider: ExternalProvider
    private var selectedModel: ExternalModel

    // Statistics
    private var totalTokensUsed: Int = 0
    private var totalCost: Double = 0.0

    public nonisolated var tier: EngineTier { .external }

    public init(storage: DatabaseManager, keychainManager: KeychainManager = .shared) {
        self.storage = storage
        self.keychainManager = keychainManager

        // Load saved preferences
        if let providerRaw = UserDefaults.standard.string(forKey: "externalAPIProvider"),
           let provider = ExternalProvider(rawValue: providerRaw) {
            self.selectedProvider = provider
        } else {
            self.selectedProvider = .openai
        }

        if let modelRaw = UserDefaults.standard.string(forKey: "externalAPIModel"),
           let model = ExternalModel(rawValue: modelRaw) {
            self.selectedModel = model
        } else {
            self.selectedModel = selectedProvider.defaultModel
        }
    }

    // MARK: - Configuration

    public func setProvider(_ provider: ExternalProvider) {
        selectedProvider = provider
        selectedModel = provider.defaultModel
        UserDefaults.standard.set(provider.rawValue, forKey: "externalAPIProvider")
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "externalAPIModel")
    }

    public func setModel(_ model: ExternalModel) {
        guard model.provider == selectedProvider else {
            print("⚠️ Model \(model.displayName) doesn't match provider \(selectedProvider.displayName)")
            return
        }
        selectedModel = model
        UserDefaults.standard.set(model.rawValue, forKey: "externalAPIModel")
    }

    public func getConfiguration() -> (provider: ExternalProvider, model: ExternalModel) {
        return (selectedProvider, selectedModel)
    }

    public func getAvailableModels() -> [ExternalModel] {
        return selectedProvider.availableModels
    }

    // MARK: - Availability

    public func isAvailable() async -> Bool {
        let hasKey = await keychainManager.hasAPIKey(for: selectedProvider)
        let hasInternet = await checkInternetConnectivity()
        return hasKey && hasInternet
    }

    private func checkInternetConnectivity() async -> Bool {
        let url = selectedProvider.baseURL
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            // OpenAI returns 401/405, Anthropic returns 401 - both mean server is reachable
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode < 500
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - API Calls

    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {

        guard let apiKey = await keychainManager.getAPIKey(for: selectedProvider) else {
            throw SummarizationError.configurationError(
                "No API key configured for \(selectedProvider.displayName). " +
                "Please add your API key in Settings → AI & Intelligence."
            )
        }

        let prompt = UniversalPrompt.build(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )

        print("📊 [ExternalAPIEngine] Request:")
        print("   Provider: \(selectedProvider.displayName)")
        print("   Model: \(selectedModel.displayName)")
        print("   Max Tokens: \(selectedModel.recommendedMaxTokens)")
        print("   Temperature: \(selectedModel.recommendedTemperature)")

        let response = try await callAPI(prompt: prompt, apiKey: apiKey)
        return try parseSessionResponse(response, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
    }

    private func callAPI(prompt: String, apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: selectedProvider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any]

        switch selectedProvider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": selectedModel.rawValue,
                "messages": [
                    ["role": "system", "content": UniversalPrompt.systemInstruction],
                    ["role": "user", "content": prompt]
                ],
                "temperature": selectedModel.recommendedTemperature,
                "max_tokens": selectedModel.recommendedMaxTokens
            ]

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": selectedModel.rawValue,
                "max_tokens": selectedModel.recommendedMaxTokens,
                "system": UniversalPrompt.systemInstruction,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.networkError("Invalid response")
        }

        // Handle errors
        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"

            switch httpResponse.statusCode {
            case 401:
                throw SummarizationError.configurationError("Invalid API key for \(selectedProvider.displayName)")
            case 429:
                throw SummarizationError.apiError("Rate limited. Please wait and try again.")
            case 500...599:
                throw SummarizationError.apiError("\(selectedProvider.displayName) server error. Please try again later.")
            default:
                throw SummarizationError.apiError("API error \(httpResponse.statusCode): \(errorBody)")
            }
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummarizationError.decodingFailed("Invalid JSON response")
        }

        // Track token usage
        if let usage = json["usage"] as? [String: Any],
           let totalTokens = usage["total_tokens"] as? Int {
            totalTokensUsed += totalTokens
        }

        return json
    }

    // ... parseSessionResponse implementation ...
}
```

### Model Selection UI

```swift
// ExternalAISettingsView.swift
import SwiftUI

struct ExternalAISettingsView: View {
    @State private var selectedProvider: ExternalProvider = .openai
    @State private var selectedModel: ExternalModel = .gpt4oMini
    @State private var hasOpenAIKey = false
    @State private var hasAnthropicKey = false
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var isValidating = false

    var body: some View {
        Form {
            // Provider Selection
            Section("Provider") {
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(ExternalProvider.allCases, id: \.self) { provider in
                        HStack {
                            Text(provider.displayName)
                            if hasAPIKey(for: provider) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedProvider) { _, newProvider in
                    selectedModel = newProvider.defaultModel
                    savePreferences()
                }
            }

            // Model Selection
            Section("Model") {
                ForEach(selectedProvider.availableModels, id: \.self) { model in
                    Button {
                        selectedModel = model
                        savePreferences()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 12) {
                                    Label(model.costTier, systemImage: "dollarsign.circle")
                                    Label("\(model.contextWindow / 1000)K ctx", systemImage: "text.alignleft")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedModel == model {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            // API Key Configuration
            Section("API Key") {
                switch selectedProvider {
                case .openai:
                    apiKeyField(
                        key: $openAIKey,
                        hasKey: hasOpenAIKey,
                        provider: .openai,
                        placeholder: "sk-..."
                    )
                case .anthropic:
                    apiKeyField(
                        key: $anthropicKey,
                        hasKey: hasAnthropicKey,
                        provider: .anthropic,
                        placeholder: "sk-ant-..."
                    )
                }
            }

            // Model Info
            Section("Selected Model Info") {
                LabeledContent("Model ID", value: selectedModel.rawValue)
                LabeledContent("Context Window", value: "\(selectedModel.contextWindow.formatted()) tokens")
                LabeledContent("Max Output", value: "\(selectedModel.maxOutputTokens.formatted()) tokens")
                LabeledContent("Cost Tier", value: selectedModel.costTier)
            }
        }
        .navigationTitle("Year Wrapped Pro AI")
        .task {
            await loadPreferences()
        }
    }

    @ViewBuilder
    private func apiKeyField(
        key: Binding<String>,
        hasKey: Bool,
        provider: ExternalProvider,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(placeholder, text: key)
                .textContentType(.password)
                .autocapitalization(.none)

            HStack {
                if hasKey {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Not configured", systemImage: "xmark.circle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Spacer()

                if !key.wrappedValue.isEmpty {
                    Button("Save") {
                        Task { await saveAPIKey(key.wrappedValue, for: provider) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isValidating)
                }

                if hasKey {
                    Button("Remove", role: .destructive) {
                        Task { await removeAPIKey(for: provider) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func hasAPIKey(for provider: ExternalProvider) -> Bool {
        switch provider {
        case .openai: return hasOpenAIKey
        case .anthropic: return hasAnthropicKey
        }
    }

    private func loadPreferences() async {
        hasOpenAIKey = await KeychainManager.shared.hasAPIKey(for: .openai)
        hasAnthropicKey = await KeychainManager.shared.hasAPIKey(for: .anthropic)

        if let providerRaw = UserDefaults.standard.string(forKey: "externalAPIProvider"),
           let provider = ExternalProvider(rawValue: providerRaw) {
            selectedProvider = provider
        }

        if let modelRaw = UserDefaults.standard.string(forKey: "externalAPIModel"),
           let model = ExternalModel(rawValue: modelRaw) {
            selectedModel = model
        }
    }

    private func savePreferences() {
        UserDefaults.standard.set(selectedProvider.rawValue, forKey: "externalAPIProvider")
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "externalAPIModel")
    }

    private func saveAPIKey(_ key: String, for provider: ExternalProvider) async {
        isValidating = true
        defer { isValidating = false }

        await KeychainManager.shared.setAPIKey(key, for: provider)

        switch provider {
        case .openai:
            openAIKey = ""
            hasOpenAIKey = true
        case .anthropic:
            anthropicKey = ""
            hasAnthropicKey = true
        }
    }

    private func removeAPIKey(for provider: ExternalProvider) async {
        await KeychainManager.shared.deleteAPIKey(for: provider)

        switch provider {
        case .openai: hasOpenAIKey = false
        case .anthropic: hasAnthropicKey = false
        }
    }
}
```

### API Key Validation (Optional but Recommended)

```swift
// ExternalAPIEngine+Validation.swift
extension ExternalAPIEngine {

    public enum APIKeyValidationResult {
        case valid(message: String)
        case invalid(reason: String)

        public var isValid: Bool {
            if case .valid = self { return true }
            return false
        }
    }

    public func validateAPIKey(_ apiKey: String, for provider: ExternalProvider) async -> APIKeyValidationResult {
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let testModel = provider.defaultModel
        let body: [String: Any]

        switch provider {
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": testModel.rawValue,
                "messages": [["role": "user", "content": "Hi"]],
                "max_tokens": 1
            ]

        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": testModel.rawValue,
                "max_tokens": 1,
                "messages": [["role": "user", "content": "Hi"]]
            ]
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .invalid(reason: "Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                return .valid(message: "API key verified successfully")
            case 401:
                return .invalid(reason: "Invalid API key")
            case 403:
                return .invalid(reason: "API key lacks required permissions")
            case 429:
                // Rate limited but key is valid
                return .valid(message: "API key valid (rate limited)")
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .invalid(reason: "Error \(httpResponse.statusCode): \(errorBody)")
            }
        } catch {
            return .invalid(reason: "Network error: \(error.localizedDescription)")
        }
    }
}
```

---

```swift
// KeychainManager.swift
import Foundation
import Security

public actor KeychainManager {
    public static let shared = KeychainManager()

    private let service = "com.yourapp.api-keys"

    public enum Provider: String, CaseIterable {
        case openai = "openai"
        case anthropic = "anthropic"

        public var displayName: String {
            switch self {
            case .openai: return "OpenAI"
            case .anthropic: return "Anthropic"
            }
        }

        public var defaultModel: String {
            switch self {
            case .openai: return "gpt-4o-mini"
            case .anthropic: return "claude-3-5-sonnet-20241022"
            }
        }
    }

    private func keychainAccount(for provider: Provider) -> String {
        "\(service).\(provider.rawValue)"
    }

    public func setAPIKey(_ key: String, for provider: Provider) async {
        let account = keychainAccount(for: provider)
        let data = key.data(using: .utf8)!

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    public func getAPIKey(for provider: Provider) async -> String? {
        let account = keychainAccount(for: provider)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    public func hasAPIKey(for provider: Provider) async -> Bool {
        return await getAPIKey(for: provider) != nil
    }

    public func deleteAPIKey(for provider: Provider) async {
        let account = keychainAccount(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
```

### Step 2: ExternalAPIEngine Implementation

```swift
// ExternalAPIEngine.swift
import Foundation

public actor ExternalAPIEngine: SummarizationEngine {
    public typealias Provider = KeychainManager.Provider

    private let storage: DatabaseManager
    private let keychainManager: KeychainManager
    private var selectedProvider: Provider = .openai
    private var selectedModel: String

    public nonisolated var tier: EngineTier { .external }

    public init(storage: DatabaseManager, keychainManager: KeychainManager = .shared) {
        self.storage = storage
        self.keychainManager = keychainManager
        self.selectedModel = Provider.openai.defaultModel
    }

    public func isAvailable() async -> Bool {
        let hasKey = await keychainManager.hasAPIKey(for: selectedProvider)
        let hasInternet = await checkInternetConnectivity()
        return hasKey && hasInternet
    }

    private func checkInternetConnectivity() async -> Bool {
        // Simple connectivity check
        guard let url = URL(string: "https://api.openai.com") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {

        guard let apiKey = await keychainManager.getAPIKey(for: selectedProvider) else {
            throw SummarizationError.configurationError("No API key configured for \(selectedProvider.displayName)")
        }

        // Build prompt using universal schema
        let prompt = UniversalPrompt.build(
            level: .session,
            input: transcriptText,
            metadata: ["duration": Int(duration), "wordCount": transcriptText.split(separator: " ").count]
        )

        // Call API
        let response = try await callAPI(prompt: prompt, apiKey: apiKey)

        // Parse response
        return try parseSessionResponse(response, sessionId: sessionId, duration: duration, languageCodes: languageCodes)
    }

    private func callAPI(prompt: String, apiKey: String) async throws -> [String: Any] {
        let url: URL
        var request: URLRequest
        let body: [String: Any]

        switch selectedProvider {
        case .openai:
            url = URL(string: "https://api.openai.com/v1/chat/completions")!
            request = URLRequest(url: url)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": selectedModel,
                "messages": [
                    ["role": "system", "content": UniversalPrompt.systemInstruction],
                    ["role": "user", "content": prompt]
                ],
                "temperature": 0.7,
                "max_tokens": 2000
            ]

        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/messages")!
            request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": selectedModel,
                "max_tokens": 2000,
                "system": UniversalPrompt.systemInstruction,
                "messages": [
                    ["role": "user", "content": prompt]
                ]
            ]
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummarizationError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummarizationError.apiError("API error \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummarizationError.decodingFailed("Invalid JSON response")
        }

        return json
    }

    private func parseSessionResponse(
        _ response: [String: Any],
        sessionId: UUID,
        duration: TimeInterval,
        languageCodes: [String]
    ) throws -> SessionIntelligence {

        // Extract content based on provider
        let contentText: String
        switch selectedProvider {
        case .openai:
            guard let choices = response["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract OpenAI content")
            }
            contentText = content

        case .anthropic:
            guard let content = response["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw SummarizationError.decodingFailed("Failed to extract Anthropic content")
            }
            contentText = text
        }

        // Parse JSON from content
        guard let jsonData = contentText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            // Use plain text if not JSON
            return SessionIntelligence(
                sessionId: sessionId,
                summary: contentText,
                topics: [],
                entities: [],
                sentiment: 0.0,
                duration: duration,
                wordCount: contentText.split(separator: " ").count,
                languageCodes: languageCodes,
                keyMoments: nil
            )
        }

        // Build summary from schema fields (session schema)
        let summary = buildSummaryFromSessionSchema(json)
        let topics = (json["main_themes"] as? [String]) ?? []

        return SessionIntelligence(
            sessionId: sessionId,
            summary: summary,
            topics: topics,
            entities: [],
            sentiment: json["sentiment"] as? Double ?? 0.0,
            duration: duration,
            wordCount: contentText.split(separator: " ").count,
            languageCodes: languageCodes,
            keyMoments: nil
        )
    }

    private func buildSummaryFromSessionSchema(_ json: [String: Any]) -> String {
        var parts: [String] = []

        // Title as header
        if let title = json["title"] as? String {
            parts.append("**\(title)**")
        }

        // Key insights as bullet points
        if let insights = json["key_insights"] as? [String], !insights.isEmpty {
            parts.append("\n\nKey Insights:")
            for insight in insights {
                parts.append("• \(insight)")
            }
        }

        // Thought process
        if let thoughtProcess = json["thought_process"] as? String, !thoughtProcess.isEmpty {
            parts.append("\n\n\(thoughtProcess)")
        }

        // Themes
        if let themes = json["main_themes"] as? [String], !themes.isEmpty {
            parts.append("\n\nThemes: \(themes.joined(separator: ", "))")
        }

        // Action items
        if let actions = json["action_items"] as? [String], !actions.isEmpty {
            parts.append("\n\nAction Items:")
            for action in actions {
                parts.append("• \(action)")
            }
        }

        return parts.isEmpty ? "No summary available" : parts.joined(separator: "\n")
    }
}
```

### Step 3: API Key Configuration UI

```swift
// APIKeySettingsView.swift
import SwiftUI

struct APIKeySettingsView: View {
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var hasOpenAIKey = false
    @State private var hasAnthropicKey = false
    @State private var isValidating = false

    var body: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key", text: $openAIKey)
                    .textContentType(.password)
                    .autocapitalization(.none)

                HStack {
                    if hasOpenAIKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button("Save") {
                        Task { await saveOpenAIKey() }
                    }
                    .disabled(openAIKey.isEmpty || isValidating)
                }
            }

            Section("Anthropic") {
                SecureField("API Key", text: $anthropicKey)
                    .textContentType(.password)
                    .autocapitalization(.none)

                HStack {
                    if hasAnthropicKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    Button("Save") {
                        Task { await saveAnthropicKey() }
                    }
                    .disabled(anthropicKey.isEmpty || isValidating)
                }
            }
        }
        .task {
            await checkExistingKeys()
        }
    }

    private func checkExistingKeys() async {
        hasOpenAIKey = await KeychainManager.shared.hasAPIKey(for: .openai)
        hasAnthropicKey = await KeychainManager.shared.hasAPIKey(for: .anthropic)
    }

    private func saveOpenAIKey() async {
        await KeychainManager.shared.setAPIKey(openAIKey, for: .openai)
        openAIKey = ""
        hasOpenAIKey = true
    }

    private func saveAnthropicKey() async {
        await KeychainManager.shared.setAPIKey(anthropicKey, for: .anthropic)
        anthropicKey = ""
        hasAnthropicKey = true
    }
}
```

---

## Version Matrix

- Swift: 6.2
- Xcode: 26.x
- Local model: Phi-3.5 (instruct) GGUF (~770–810 MB)
- `llama.cpp` commit: b6d6c52 (via SwiftLlamaPatched)
- External model: OpenAI `gpt-4o-mini` (default); Anthropic supported

## Data Flow (Session Summaries)

1. AppCoordinator fetches transcript segments for a session.
2. SummarizationCoordinator picks active engine based on preference + availability.
3. UniversalPrompt.build(level: .session, input: full transcript text, metadata) creates JSON-instruction prompt.
4. Engine generates:
   - Local: streamed tokens via SwiftLlama; stop tokens enforce completion.
   - External: chat completion API; expects JSON per schema.
5. Response parsed into `SessionIntelligence` → `Summary` and saved to SQLite.
6. Period rollups (day/week/month) update after session save.

## Engine Selection & Availability

- Preference stored in `UserDefaults` key `preferredIntelligenceEngine`.
- `setPreferredEngine()` triggers `selectBestAvailableEngine()` with fallbacks:
  - External → Local → Apple (if available) → Basic.
- External availability: requires API key in Keychain + internet check.
- Local availability: model file present and loadable.

## Local AI Implementation (Phi-3.5)

- **Model loading**: Phi-3.5 GGUF via SwiftLlamaPatched (`llama.cpp`). Constrained config for mobile:
  - nCTX: 1024, batch: 128, max tokens: 512, temp: 0.2, topK: 30, topP: 0.9, stop tokens: `StopToken.phi` (`["<|end|>"]`).
- **Prompt format**: `Prompt(type: .phi, systemPrompt, userMessage)`
  - Structure:
    - System: journaling assistant instructions
    - History: (optional) last `historySize` turns
    - User: `<|user|>...<|end|>\n<|assistant|>`
- **Why Phi format**: Using `.llama3` caused immediate EOG → 1 token output. `.phi` + correct stop tokens fixed truncation.
- **Safety checks**:
  - File size sanity (700–900 MB) before load.
  - Model load wrapped in `Task.detached` to avoid main-actor stalls.
  - `isReady()` ensures model loaded before generation.
- **Fallbacks**: If generation throws/JSON invalid, LocalEngine returns extractive summary.

## External AI (Year Wrapped Pro AI)

- **Providers**: OpenAI (default), Anthropic optional.
- **Models**: `gpt-4o-mini` default; configurable per provider.
- **API key storage**: Keychain per provider; availability check requires key + connectivity.
- **Prompting**: Same `UniversalPrompt` schema as Local; sent as chat completion system/user messages.
- **Response parsing**:
  - Expect JSON following schema. For session level: fields like `title`, `key_insights`[], `main_themes`[], `thought_process`, `action_items`[]
  - Parser now constructs summary from these fields instead of expecting a `summary` string.
  - Topics derived from `main_themes` when present.
- **Errors surfaced**: Missing API key or offline → explicit `configurationError` surfaced to UI.

## Universal Prompt & Schemas

- Levels: chunk, session, day, week, month, year, yearWrap.
- Session schema keys (critical for parsing):
  - `title`: short descriptor
  - `key_insights`: bullet insights (primary content)
  - `main_themes`: topical grouping
  - `thought_process`: 2–3 sentence analysis
  - `action_items`: optional next steps
- Ensure models **return valid JSON** matching these keys; otherwise parser falls back to plain text.

## Message Structure (External API)

- OpenAI Chat:
  - `messages`: `[ {role: "system", content: systemPrompt}, {role: "user", content: userPrompt} ]`
  - `temperature: 0.7`, `max_tokens: 2000` (session), stop not required (JSON enforced by prompt)
- Anthropic: similar content array; parsed via `content[0].text`.

## Workflow to Add Local AI (Checklist)

1. Bundle or download GGUF model (Phi-3.5 instruct). Verify size ~770–810 MB.
2. Load via SwiftLlama with Phi prompt + Phi stop tokens.
3. Constrain context/batch/max tokens for device RAM.
4. Build prompts with `Prompt(type: .phi, ...)`.
5. Stream tokens; concatenate to text; parse JSON if applicable.
6. Handle fallbacks: extractive summary when JSON invalid or generation fails.
7. Surface errors to UI; avoid silent failures.

## Workflow to Add External AI (Checklist)

1. Add provider config (model name, base URL if needed).
2. Store API key in Keychain; validate before use.
3. Build `UniversalPrompt` payload per summary level.
4. Call chat completion API with system + user messages.
5. Parse JSON according to schema; construct human-readable summary (title + bullet insights + thought process + themes + actions).
6. On errors: show configuration/internet issues in UI; do not silently fallback unless user chose fallback.

## Things We Learned to Watch Out For

- **Prompt format mismatch**: Phi model must use `.phi` prompt and `StopToken.phi`; wrong format ends generation after 1 token.
- **JSON parsing**: Do not assume a single `summary` field; build summary from schema fields (`key_insights`, `thought_process`, `main_themes`, `action_items`).
- **Availability checks**: Always gate external engine by API key + connectivity; surface clear errors.
- **Concurrency**: Load models off main thread; use actors for DB and coordination.
- **Resource limits**: Keep context/batch conservative on mobile to avoid OOM; adjust `maxTokenCount` as needed.
- **Fallbacks**: Provide extractive fallback for Local AI; keep UI aware of failures.

## Replication Steps (End-to-End)

1. **Scaffold engines**: Implement `SummarizationEngine` protocol for Local + External; register in `SummarizationCoordinator`.
2. **Prompts**: Use `UniversalPrompt` schemas; ensure provider models are instructed to output strict JSON.
3. **Local model**: Download Phi-3.5 GGUF; load with Phi prompt + stop tokens; test generation length.
4. **External model**: Configure provider/model; add API key UI + Keychain storage; test availability.
5. **Parsing**: Map JSON fields to domain model; compose readable summary from schema parts.
6. **UI surfacing**: Show engine badge, errors, and regeneration controls; respect user-selected engine unless unavailable.
7. **Testing**: Offline mode (Local should work), missing API key (clear error), malformed JSON (fallback), long transcripts (ensure tokens sufficient).

## Quick Reference

### Local Model Quick Reference

| Model        | Prompt Type | Stop Tokens | Download                                                                     |
| ------------ | ----------- | ----------- | ---------------------------------------------------------------------------- | ---- | -------------------------------------------------------------------------- |
| Phi-3.5 Mini | `.phi`      | `["<        | end                                                                          | >"]` | [HuggingFace](https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF) |
| Llama 3.2 1B | `.llama3`   | `["<        | eot_id                                                                       | >"]` | [HuggingFace](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF) |
| Llama 3.2 3B | `.llama3`   | `["<        | eot_id                                                                       | >"]` | [HuggingFace](https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF) |
| Mistral 7B   | `.mistral`  | `["</s>"]`  | [HuggingFace](https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF) |

### External Model Quick Reference

| Provider      | Model             | Model ID                     | Cost | Context | Get API Key                                                          |
| ------------- | ----------------- | ---------------------------- | ---- | ------- | -------------------------------------------------------------------- |
| **OpenAI**    | GPT-4o Mini       | `gpt-4o-mini`                | $    | 128K    | [platform.openai.com](https://platform.openai.com/api-keys)          |
| OpenAI        | GPT-4o            | `gpt-4o`                     | $$$  | 128K    | [platform.openai.com](https://platform.openai.com/api-keys)          |
| OpenAI        | GPT-4 Turbo       | `gpt-4-turbo`                | $$   | 128K    | [platform.openai.com](https://platform.openai.com/api-keys)          |
| OpenAI        | GPT-3.5 Turbo     | `gpt-3.5-turbo`              | $    | 16K     | [platform.openai.com](https://platform.openai.com/api-keys)          |
| **Anthropic** | Claude 3.5 Sonnet | `claude-3-5-sonnet-20241022` | $$   | 200K    | [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| Anthropic     | Claude 3.5 Haiku  | `claude-3-5-haiku-20241022`  | $    | 200K    | [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| Anthropic     | Claude 3 Opus     | `claude-3-opus-20240229`     | $$$  | 200K    | [console.anthropic.com](https://console.anthropic.com/settings/keys) |

### Configuration Quick Reference

- Local prompt type (Phi): `.phi`
- Local prompt type (Llama): `.llama3`
- Local stop tokens (Phi): `StopToken.phi` (`["<|end|>"]`)
- Local stop tokens (Llama): `StopToken.llama3` (`["<|eot_id|>"]`)
- External default provider: `openai`
- External default model: `gpt-4o-mini`
- Availability preference key: `preferredIntelligenceEngine`
- Local model preference key: `selectedLocalModel`
- External provider preference key: `externalAPIProvider`
- External model preference key: `externalAPIModel`
- Key schema fields (session): `title`, `key_insights`, `main_themes`, `thought_process`, `action_items`

### API Headers Quick Reference

```swift
// OpenAI
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// Anthropic
request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
```

### Prompt Format Cheat Sheet

```
# Phi-3.5 Format
<system prompt>
<|user|>
<user message>
<|end|>
<|assistant|>

# Llama 3.x Format
<|start_header_id|>system<|end_header_id|>
<system prompt><|eot_id|>
<|start_header_id|>user<|end_header_id|>
<user message><|eot_id|>
<|start_header_id|>assistant<|end_header_id|>
```

---

## Complete File Structure Reference

```
YourApp/
├── App/
│   ├── YourApp.swift                    # @main entry point
│   ├── ContentView.swift                # Main UI
│   └── Coordinators/
│       └── AppCoordinator.swift         # @MainActor orchestrator
│
├── Packages/
│   ├── SharedModels/
│   │   ├── Package.swift
│   │   └── Sources/SharedModels/
│   │       ├── Summary.swift            # Summary data model
│   │       ├── SessionIntelligence.swift
│   │       ├── PeriodIntelligence.swift
│   │       └── Entity.swift
│   │
│   ├── Storage/
│   │   ├── Package.swift
│   │   └── Sources/Storage/
│   │       └── DatabaseManager.swift    # SQLite actor
│   │
│   ├── LocalLLM/
│   │   ├── Package.swift
│   │   └── Sources/LocalLLM/
│   │       ├── LocalLLM.swift           # Configuration + LlamaContext
│   │       └── ModelFileManager.swift   # Model download/storage
│   │
│   ├── SwiftLlamaPatched/               # Patched llama.cpp wrapper
│   │   ├── Package.swift
│   │   └── Sources/SwiftLlama/
│   │       ├── SwiftLlama.swift
│   │       ├── LlamaModel.swift
│   │       ├── Configuration.swift
│   │       └── Models/
│   │           ├── Prompt.swift         # Prompt formats (.phi, .llama3, etc.)
│   │           ├── StopToken.swift      # Stop tokens per model family
│   │           └── Chat.swift
│   │
│   └── Summarization/
│       ├── Package.swift
│       └── Sources/Summarization/
│           ├── SummarizationEngine.swift      # Protocol + EngineTier
│           ├── SummarizationCoordinator.swift # Engine orchestration (actor)
│           ├── SummarizationError.swift       # Error types
│           ├── BasicEngine.swift              # Keyword extraction fallback
│           ├── LocalEngine.swift              # Phi-3.5 via LocalLLM
│           ├── ExternalAPIEngine.swift        # OpenAI/Anthropic
│           ├── KeychainManager.swift          # API key storage
│           └── UniversalPrompt.swift          # Schema-driven prompts
│
├── Config/
│   ├── Debug.xcconfig
│   ├── Release.xcconfig
│   └── Secrets.xcconfig                 # API keys (gitignored)
│
└── Docs/
    └── AI_ARCHITECTURE.md               # This document
```

---

## Testing Checklist

### Local AI Testing

- [ ] Model downloads successfully (~770-810 MB)
- [ ] Model loads without crashing (check RAM usage)
- [ ] Generation produces >1 token (verify prompt format)
- [ ] JSON parsing succeeds for valid output
- [ ] Fallback works when JSON is malformed
- [ ] Works offline (airplane mode)
- [ ] Works on simulator (CPU-only, slower)

### External AI Testing

- [ ] API key saves to Keychain
- [ ] API key retrieves from Keychain
- [ ] Availability check detects missing key
- [ ] Availability check detects no internet
- [ ] API call succeeds with valid key
- [ ] JSON response parses correctly
- [ ] Error messages surface to UI
- [ ] Works with OpenAI
- [ ] Works with Anthropic (if supported)

### Engine Switching

- [ ] Preference persists across app restarts
- [ ] Switching engines updates active engine
- [ ] Unavailable engine falls back gracefully
- [ ] UI shows correct engine badge

---

## Common Errors & Solutions

| Error                          | Cause                  | Solution                                                   |
| ------------------------------ | ---------------------- | ---------------------------------------------------------- |
| "Generated 0 chars (1 tokens)" | Wrong prompt format    | Use `.phi` for Phi, `.llama3` for Llama models             |
| "Unexpected end of file"       | Wrong stop tokens      | Use `StopToken.phi` for Phi, `StopToken.llama3` for Llama  |
| "No summary available"         | JSON parsing failed    | Check schema field names match parser                      |
| "Model not found"              | Model not downloaded   | Verify model file exists and size is correct               |
| "Invalid model size"           | Corrupted download     | Re-download model, verify with `ls -lh`                    |
| "No API key configured"        | Missing Keychain entry | Add API key in Settings UI                                 |
| "API error 401"                | Invalid API key        | Verify API key is correct                                  |
| "API error 429"                | Rate limited           | Implement backoff/retry logic                              |
| App crashes on load            | OOM                    | Reduce nCTX/batchSize, or use smaller model (Llama 3.2 1B) |
| Model generates gibberish      | Prompt/stop mismatch   | Verify promptType and stopTokens match model family        |
| Generation never stops         | Wrong stop tokens      | Model can't find its end token; fix stopTokens             |

### Local Model Troubleshooting

**Phi-3.5 Issues:**

- Must use `.phi` prompt type
- Must use `StopToken.phi` (`["<|end|>"]`)
- Sensitive to temperature; keep ≤0.3 for JSON

**Llama 3.2 Issues:**

- Must use `.llama3` prompt type
- Must use `StopToken.llama3` (`["<|eot_id|>"]`)
- Date in system prompt helps with context

### External API Troubleshooting

**OpenAI Issues:**

| Error              | Cause                 | Solution                                                                      |
| ------------------ | --------------------- | ----------------------------------------------------------------------------- |
| 401 Unauthorized   | Invalid API key       | Regenerate key at [platform.openai.com](https://platform.openai.com/api-keys) |
| 429 Rate Limited   | Too many requests     | Implement retry with exponential backoff                                      |
| 429 Quota Exceeded | Billing limit reached | Add credits or upgrade plan                                                   |
| "invalid_model"    | Model ID typo         | Use exact model ID: `gpt-4o-mini`, `gpt-4o`, etc.                             |
| Slow response      | Model overloaded      | Switch to `gpt-4o-mini` for faster responses                                  |
| Response truncated | max_tokens too low    | Increase max_tokens (2000+ for summaries)                                     |

**Anthropic Issues:**

| Error                     | Cause              | Solution                                                                           |
| ------------------------- | ------------------ | ---------------------------------------------------------------------------------- |
| 401 Invalid API Key       | Wrong key          | Regenerate at [console.anthropic.com](https://console.anthropic.com/settings/keys) |
| 400 Invalid Model         | Model ID typo      | Use full ID: `claude-3-5-sonnet-20241022`                                          |
| Missing anthropic-version | Header missing     | Add `anthropic-version: 2023-06-01` header                                         |
| 529 Overloaded            | API congested      | Retry after delay; Claude is busy                                                  |
| Empty response            | max_tokens not set | `max_tokens` is required for Anthropic                                             |

**General External API Tips:**

```swift
// Always set timeouts
request.timeoutInterval = 60  // 60 seconds for long transcripts

// Always check HTTP status before parsing
guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200 else {
    // Handle error
}

// Extract error details from response body
if httpResponse.statusCode != 200 {
    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown"
    throw SummarizationError.apiError("[\(httpResponse.statusCode)] \(errorBody)")
}
```

---

## Resources

### Model Downloads (GGUF Format - Local AI)

- [Phi-3.5 Mini Instruct GGUF](https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF) - Recommended, best quality
- [Llama 3.2 1B Instruct GGUF](https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF) - Lightweight alternative
- [Llama 3.2 3B Instruct GGUF](https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF) - Mid-size option

### API Key Setup (External AI)

| Provider  | Get API Key                                                                        | Pricing                                                    |
| --------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| OpenAI    | [platform.openai.com/api-keys](https://platform.openai.com/api-keys)               | [openai.com/pricing](https://openai.com/pricing)           |
| Anthropic | [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys) | [anthropic.com/pricing](https://www.anthropic.com/pricing) |

### Documentation

- [llama.cpp GitHub](https://github.com/ggerganov/llama.cpp)
- [Phi-3 Model Card (Microsoft)](https://huggingface.co/microsoft/Phi-3.5-mini-instruct)
- [Llama 3.2 Model Card (Meta)](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)
- [OpenAI Chat Completions API](https://platform.openai.com/docs/api-reference/chat)
- [Anthropic Messages API](https://docs.anthropic.com/en/api/messages)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

### Quantization Guide (Local Models)

| Quantization | Size Reduction | Quality Loss | Recommended                |
| ------------ | -------------- | ------------ | -------------------------- |
| Q8_0         | ~50%           | Minimal      | Best quality, more RAM     |
| Q6_K         | ~60%           | Very low     | Good balance               |
| **Q4_K_M**   | ~70%           | Low          | **Recommended for mobile** |
| Q4_K_S       | ~75%           | Moderate     | Smaller devices            |
| Q2_K         | ~85%           | High         | Not recommended            |

---

Use this document as a blueprint to add or extend AI engines on iOS with Swift: wire prompts correctly, guard availability, parse schema-driven JSON, and surface errors transparently.
