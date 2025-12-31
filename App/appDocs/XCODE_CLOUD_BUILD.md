# Life Wrapped - Xcode Cloud & Build Guide

**Version:** 1.0  
**Date:** December 31, 2025  
**Developer:** Jose Ramirez-Villa

---

## Overview

This document covers the build and deployment process for Life Wrapped using Xcode Cloud.

---

## Xcode Cloud Configuration

### Workflow: Default

| Setting        | Value                           |
| -------------- | ------------------------------- |
| **Repository** | github.com/jsayram/life-wrapped |
| **Branch**     | main                            |
| **Trigger**    | Push to main                    |
| **Actions**    | Archive - iOS                   |

---

## Required Files for Xcode Cloud

Xcode Cloud requires these files to be committed (not gitignored):

### Package.resolved Files

These files lock dependency versions for reproducible builds:

```
LifeWrapped.xcworkspace/xcshareddata/swiftpm/Package.resolved
Packages/LocalLLM/Package.resolved
Packages/Summarization/Package.resolved
```

**If missing, you'll see this error:**

> Could not resolve package dependencies: a resolved file is required when automatic dependency resolution is disabled

**Fix:** Ensure Package.resolved files are committed to the repository.

---

## Dependencies

### External Swift Packages

| Package                | Repository                                | Purpose                |
| ---------------------- | ----------------------------------------- | ---------------------- |
| **mlx-swift**          | github.com/ml-explore/mlx-swift           | Apple ML framework     |
| **mlx-swift-lm**       | github.com/ml-explore/mlx-swift-lm        | Language model support |
| **swift-transformers** | github.com/huggingface/swift-transformers | Tokenization           |

### Local Swift Packages

| Package            | Path                    | Purpose              |
| ------------------ | ----------------------- | -------------------- |
| **SharedModels**   | Packages/SharedModels   | Core data models     |
| **Storage**        | Packages/Storage        | SQLite database      |
| **AudioCapture**   | Packages/AudioCapture   | Recording & playback |
| **Transcription**  | Packages/Transcription  | Speech recognition   |
| **Summarization**  | Packages/Summarization  | AI summary engines   |
| **LocalLLM**       | Packages/LocalLLM       | On-device AI         |
| **InsightsRollup** | Packages/InsightsRollup | Analytics            |
| **WidgetCore**     | Packages/WidgetCore     | Widget data          |

---

## Build Process

### Local Build

```bash
# Build packages only (fast)
./Scripts/build.sh packages

# Build iOS app
./Scripts/build.sh ios

# Build all targets
./Scripts/build.sh all
```

### Xcode Archive (for App Store)

1. Open `LifeWrapped.xcworkspace`
2. Select scheme: **LifeWrapped**
3. Select destination: **Any iOS Device (arm64)**
4. Menu: **Product → Archive**
5. Wait for build (5-15 minutes)
6. **Distribute App** → **App Store Connect**

### Xcode Cloud Build

Xcode Cloud automatically:

1. Clones repository
2. Resolves dependencies using Package.resolved
3. Archives for iOS
4. Uploads to App Store Connect
5. Makes build available for TestFlight

---

## Troubleshooting

### "Could not resolve package dependencies"

**Cause:** Package.resolved files missing from repository

**Fix:**

```bash
git add -f LifeWrapped.xcworkspace/xcshareddata/swiftpm/Package.resolved
git add -f Packages/LocalLLM/Package.resolved
git add -f Packages/Summarization/Package.resolved
git commit -m "Add Package.resolved files"
git push
```

### "No such module" errors

**Cause:** Package dependencies not resolved

**Fix:**

1. In Xcode: **File → Packages → Reset Package Caches**
2. Then: **File → Packages → Resolve Package Versions**

### Build timeout

**Cause:** MLX packages are large and take time to compile

**Fix:** Xcode Cloud should handle this, but ensure you have the latest Xcode version selected.

---

## Version & Build Numbers

| Field       | Location         | Rule                        |
| ----------- | ---------------- | --------------------------- |
| **Version** | Target → General | Semantic versioning (1.0.0) |
| **Build**   | Target → General | Increment for each upload   |

**Important:** Each upload to App Store Connect requires a unique build number.

---

## Code Signing

### Automatic Signing (Recommended)

1. Xcode → Target → Signing & Capabilities
2. Check **"Automatically manage signing"**
3. Select your Team

### Xcode Cloud Signing

Xcode Cloud uses cloud-managed certificates. Ensure:

- Apple Developer Program membership is active
- Team is selected in project settings

---

## Environment

| Requirement                 | Version     |
| --------------------------- | ----------- |
| **Xcode**                   | 26.0+       |
| **Swift**                   | 6.2         |
| **iOS Deployment Target**   | 18.0        |
| **macOS (for development)** | Tahoe 26.0+ |

---

## Useful Commands

```bash
# Check Swift version
swift --version

# Check Xcode version
xcodebuild -version

# Resolve packages
cd /path/to/project
xcodebuild -resolvePackageDependencies

# Clean build folder
xcodebuild clean -workspace LifeWrapped.xcworkspace -scheme LifeWrapped
```

---

## Related Documentation

- [APP_STORE_SUBMISSION.md](../../docs/APP_STORE_SUBMISSION.md) — Full App Store submission guide
- [APP_REVIEW_GUIDE.md](APP_REVIEW_GUIDE.md) — Guide for Apple reviewers

---

_Document prepared for Life Wrapped development team_
