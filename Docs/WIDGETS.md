# Life Wrapped Widgets

## Overview

Life Wrapped provides two iOS widgets for quick access to recording and session stats directly from your home screen or lock screen.

---

## Available Widgets

### 1. 📱 Sessions Widget

**Purpose:** Display today's recording session count and streak at a glance.

| Size                   | Description                                                   |
| ---------------------- | ------------------------------------------------------------- |
| **Small**              | Shows session count with waveform icon, plus streak indicator |
| **Accessory Circular** | Lock screen widget showing session count                      |
| **Accessory Inline**   | Lock screen inline text showing streak and sessions           |

**What it shows:**

- 📊 Number of sessions recorded today
- 🔥 Current streak (days in a row with recordings)

**Tap action:** Opens the app to Home tab

---

### 2. 🎙️ Record Widget

**Purpose:** Quick-start recording with Work or Personal category pre-selected.

| Size                   | Description                                      |
| ---------------------- | ------------------------------------------------ |
| **Small**              | Two buttons: Work and Personal                   |
| **Medium**             | Larger Work/Personal buttons with streak display |
| **Accessory Circular** | Lock screen mic button for quick recording       |

**What it shows:**

- 💼 **Work** button (blue) - Starts recording with Work category
- 🏠 **Personal** button (purple) - Starts recording with Personal category
- 🔥 Current streak indicator

**Tap actions:**

- **Work button:** Opens app and starts recording with Work category (`lifewrapped://record?category=work`)
- **Personal button:** Opens app and starts recording with Personal category (`lifewrapped://record?category=personal`)

---

## Deep Links

Widgets use deep links to navigate and trigger actions:

| Deep Link                                | Action                                         |
| ---------------------------------------- | ---------------------------------------------- |
| `lifewrapped://home`                     | Opens Home tab                                 |
| `lifewrapped://history`                  | Opens History tab                              |
| `lifewrapped://record`                   | Opens Home tab and toggles recording           |
| `lifewrapped://record?category=work`     | Sets Work category, then toggles recording     |
| `lifewrapped://record?category=personal` | Sets Personal category, then toggles recording |

---

## Widget Data

Widgets display data from the shared App Group (`group.com.jsayram.lifewrapped`):

| Data               | Source                                                            |
| ------------------ | ----------------------------------------------------------------- |
| **Streak Days**    | Calculated from recording session dates (not transcript segments) |
| **Sessions Today** | Count of recording sessions started today                         |
| **Streak At Risk** | True if no recording today and previous days had recordings       |

**Refresh Rate:** Every 15 minutes, or immediately when:

- A recording is completed
- App becomes active
- App enters/exits background

---

## Adding Widgets

1. Long-press on your iPhone home screen
2. Tap the **+** button (top left)
3. Search for "LifeWrapped"
4. Choose between:
   - **Sessions Widget** - For viewing stats
   - **Record Widget** - For quick recording with category
5. Select your preferred size
6. Tap "Add Widget"

---

## Technical Details

### Files

| File                                       | Purpose                        |
| ------------------------------------------ | ------------------------------ |
| `WidgetExtension/LifeWrappedWidget.swift`  | Widget definitions and views   |
| `Packages/WidgetCore/`                     | Shared data models and manager |
| `App/Coordinators/WidgetCoordinator.swift` | Updates widget data from app   |

### Widget Bundle

```swift
@main
struct LifeWrappedWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordWidget()
        SessionsWidget()
    }
}
```

### Supported Families

| Widget             | Families                                                 |
| ------------------ | -------------------------------------------------------- |
| **RecordWidget**   | `.systemSmall`, `.systemMedium`, `.accessoryCircular`    |
| **SessionsWidget** | `.systemSmall`, `.accessoryCircular`, `.accessoryInline` |

---

## Privacy

- All widget data is stored locally in the App Group
- No network requests are made by widgets
- Data is calculated from on-device recording sessions
- Streak and session counts update immediately after recordings (no waiting for transcription)
