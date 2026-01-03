# Year Wrap Progress Tracking Enhancement

## Overview

Added detailed real-time progress tracking for Year Wrap generation to improve user experience during the 2-3 minute Local AI processing time.

## Implementation

### 1. Progress Callback System

**File**: [SummaryCoordinator.swift](../Coordinators/SummaryCoordinator.swift)

Added callback mechanism to report generation progress:

```swift
public var onYearWrapProgressUpdate: ((String) -> Void)?
```

Progress updates at 3 key stages:

- **Step 1 of 3**: Combined Year Wrap (all sessions)
- **Step 2 of 3**: Work Year Wrap (work-only sessions)
- **Step 3 of 3**: Personal Year Wrap (personal-only sessions)

### 2. Coordinator Integration

**File**: [AppCoordinator.swift](../../App/Coordinators/AppCoordinator.swift)

Added published property for UI binding:

```swift
@Published public private(set) var yearWrapProgress: String = ""
```

Connected callback in initialization:

```swift
summaryCoord.onYearWrapProgressUpdate = { [weak self] progress in
    Task { @MainActor in
        self?.yearWrapProgress = progress
    }
}
```

### 3. Enhanced Loading Overlay

**File**: [OverviewTab.swift](../Views/Tabs/OverviewTab.swift)

**Visual Progress Indicators**:

- **Step Circles**: 3 circles showing completed (green), in-progress (purple), pending (gray)
- **Status Messages**: Real-time updates showing current variant and operation
- **Animated Dots**: Pulsing animation to indicate active processing

**UI Components**:

```swift
// Progress circles
HStack(spacing: 8) {
    ForEach(1...3, id: \.self) { step in
        Circle()
            .fill(getStepColor(for: step, current: statusMessage))
            .frame(width: 10, height: 10)
    }
}
```

**Color Logic**:

- 🟢 Green: Completed steps
- 🟣 Purple: Current step in progress
- ⚪ Gray: Pending steps

## User Experience Flow

### Before Enhancement

```
Generating Year Wrap
Analyzing with Local AI...
This may take 2-3 minutes
[spinning animation]
```

### After Enhancement

```
Generating Year Wrap

Step 1 of 3: Combined Year Wrap
Processing all sessions...
● ○ ○  [3 progress circles]

[animated dots]
```

Then automatically updates to:

```
Step 2 of 3: Work Year Wrap
Processing work sessions...
● ● ○

[animated dots]
```

Finally:

```
Step 3 of 3: Personal Year Wrap
Processing personal sessions...
● ● ●

[animated dots]
```

## Technical Details

### Message Format

Progress messages follow pattern: `"Step X of 3: [Variant Name]\n[Operation]"`

- Step 1: Combined Year Wrap
- Step 2: Work Year Wrap
- Step 3: Personal Year Wrap

### Color Extraction Logic

```swift
private func getStepColor(for step: Int, current statusMessage: String) -> Color {
    if let range = statusMessage.range(of: "Step \\d+", options: .regularExpression),
       let currentStepString = statusMessage[range].split(separator: " ").last,
       let currentStep = Int(currentStepString) {
        if step < currentStep {
            return AppTheme.green // Completed
        } else if step == currentStep {
            return AppTheme.purple // In progress
        } else {
            return Color.white.opacity(0.3) // Pending
        }
    }
    return Color.white.opacity(0.3) // Default
}
```

### Thread Safety

- Progress updates occur on background thread
- UI updates automatically dispatched to main actor via @Published property
- Callback uses `[weak self]` to prevent retain cycles

## Performance Impact

- Minimal overhead: String updates only at 3 checkpoints
- No additional AI computation required
- UI updates use efficient SwiftUI animations
- Regex extraction runs once per update (~negligible cost)

## Testing Checklist

- [ ] Verify progress circles update correctly (gray → purple → green)
- [ ] Confirm messages change at each step transition
- [ ] Test with all 3 variants (Combined, Work, Personal)
- [ ] Validate animations remain smooth during updates
- [ ] Check thread safety (no UI glitches or crashes)
- [ ] Verify fallback behavior if progress message format changes

## Future Enhancements

### Sub-Step Progress (Phase 2)

Could add more granular updates within each variant:

```
Step 1 of 3: Combined Year Wrap
Loading model... (5s)

Step 1 of 3: Combined Year Wrap
Synthesizing Q1... (10s)

Step 1 of 3: Combined Year Wrap
Generating title & summary... (8s)

Step 1 of 3: Combined Year Wrap
Extracting topics... (7s)
```

**Implementation**:

- Add callback parameter to LocalEngine's 5-step process
- Report each of 5 prompts: title/summary, wins/challenges, projects, topics/actions, people
- Update UI to show sub-progress bar within each variant

### Time Estimation

Add elapsed time counter and estimated remaining time:

```
Step 2 of 3: Work Year Wrap
Processing work sessions...
⏱️ Elapsed: 1m 25s | Est. remaining: 45s
```

**Implementation**:

- Track start time in coordinator
- Use historical averages for time estimation
- Display countdown timer in overlay

### Progress Percentage

Add numeric progress indicator:

```
Generating Year Wrap (67%)

Step 2 of 3: Work Year Wrap
Processing work sessions...
● ● ○
```

**Implementation**:

- Calculate: `(completedSteps / totalSteps) * 100`
- Update progress bar width or numeric label
- Smooth transitions between percentages

## Related Documentation

- [Local AI Architecture](LOCAL_AI_ARCHITECTURE.md) - Phi-3.5 Mini implementation details
- [Work/Personal Classification](WORK_PERSONAL_CLASSIFICATION_TEST.md) - Category system
- [AI Architecture](AI_ARCHITECTURE.md) - Multi-tier summarization overview

## Changelog

- **2024-01-XX**: Initial implementation with 3-step progress tracking
- Callback system: SummaryCoordinator → AppCoordinator → UI
- Visual indicators: Step circles with color-coded states
- Real-time message updates for each variant generation
