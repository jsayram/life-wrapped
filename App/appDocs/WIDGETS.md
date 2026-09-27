# Life Wrapped Widgets

## Overview

Life Wrapped has two widgets, for the Home Screen and the Lock Screen. They follow the app's graphite style: monochrome, using the system's primary and secondary colors, so they fit light, dark and tinted Home Screens.

---

## Available Widgets

### 1. Quick Record (`RecordWidget`)

**Purpose:** Start a recording with Work or Personal already chosen. Shown in the widget gallery as "Quick Record".

| Size                   | Description                                                            |
| ---------------------- | ---------------------------------------------------------------------- |
| **Small**              | Work and Personal buttons, and the streak                              |
| **Medium**             | Work, record and Personal buttons, the streak and today's recordings   |
| **Accessory Circular** | Lock Screen mic ("REC") that starts a recording                        |

**Tap actions:**

- **Work:** opens the app and starts a Work recording (`lifewrapped://record?category=work`)
- **Personal:** opens the app and starts a Personal recording (`lifewrapped://record?category=personal`)
- **Record (medium) and the circular widget:** `lifewrapped://record`, with the journal last chosen in the app

When the streak is at risk (nothing recorded yet today), the streak line reads "Save your streak".

---

### 2. Today's Recordings (`SessionsWidget`)

**Purpose:** Today's recording count and the streak at a glance. Shown in the widget gallery as "Today's Recordings".

| Size                   | Description                                           |
| ---------------------- | ----------------------------------------------------- |
| **Small**              | Today's recording count and the streak                |
| **Accessory Circular** | Today's recording count                               |
| **Accessory Inline**   | "N recordings today"                                  |

**Tap action:** opens the History tab (`lifewrapped://history`)

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
| **Streak Days**    | Days in a row with a recording that started on that day           |
| **Today's recordings** | Recordings started today (`todayEntries`), plus today's minutes and words |
| **Last recording** | Time of the latest recording                                      |
| **Streak At Risk** | True if no recording today and previous days had recordings       |

**Refresh Rate:** Every 15 minutes, or immediately when:

- A recording is completed
- App becomes active
- App enters/exits background

---

## Adding Widgets

1. Touch and hold the Home Screen, then tap **Edit** and **Add Widget**
2. Search for "Life Wrapped"
3. Choose **Quick Record** or **Today's Recordings**, then a size
4. Tap **Add Widget**

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
- Streak and recording counts update right after a recording stops (no waiting for transcription)
- Only numbers are shared with the widget: no audio, transcripts or summaries
