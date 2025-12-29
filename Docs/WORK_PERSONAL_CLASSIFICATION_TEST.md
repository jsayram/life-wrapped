# Work/Personal Classification — Test Plan

> **Completed**: December 28, 2025  
> **Status**: Ready for Testing

---

## Overview

Implemented a complete work/personal classification system for Year Wrap that respects user-defined session categories instead of AI inference from content.

---

## Architecture Summary

### Data Flow

```
User marks sessions → Database stores category → Year Wrap fetch → Build context → AI uses context → Items classified
```

### Key Components

1. **Database Layer** ([SessionRepository.swift](../Packages/Storage/Sources/Storage/Repositories/SessionRepository.swift))

   - `fetchSessionMetadataBatch(sessionIds:)` - Batch fetch session categories
   - Session metadata includes optional `category: SessionCategory?`

2. **UI Layer** ([SessionDetailView.swift](../App/Views/Details/SessionDetailView.swift))

   - Picker to mark sessions as Work/Personal/None
   - Automatically saves to database
   - Color-coded (Work: blue, Personal: orange)

3. **Summarization Layer** ([SummaryCoordinator.swift](../App/Coordinators/SummaryCoordinator.swift))

   - `fetchSessionCategoriesForYear(year:)` - Get all session categories
   - `buildCategoryContext(categoryMap:)` - Format context for AI
   - Passes context to AI during Year Wrap generation

4. **AI Prompt** ([UniversalPrompt.swift](../Packages/Summarization/Sources/Summarization/UniversalPrompt.swift))
   - Updated `yearlySchema` with category classification rules
   - AI instructed to respect user's session categories
   - Categories: "work", "personal", or "both"

---

## Testing Checklist

### Phase 1: Session Categorization ✅

- [x] UI exists in SessionDetailView
- [x] Database method exists (`updateSessionCategory`)
- [x] Coordinator method exists and wired up
- [ ] **Manual Test**: Mark some sessions as Work
- [ ] **Manual Test**: Mark some sessions as Personal
- [ ] **Manual Test**: Leave some sessions uncategorized
- [ ] **Verify**: Check database has categories stored

### Phase 2: Year Wrap Generation 🔄

- [x] Force regenerate fixed (no longer just updates timestamp)
- [x] Category context fetching implemented
- [x] Category context building implemented
- [x] AI prompt updated with new instructions
- [ ] **Manual Test**: Force regenerate Year Wrap
- [ ] **Verify**: AI receives category context in prompt
- [ ] **Verify**: Check logs for category statistics

### Phase 3: Result Verification 📊

- [ ] **Verify**: Year Wrap JSON includes category fields
- [ ] **Verify**: Items classified as work/personal/both
- [ ] **Verify**: UI shows category badges
- [ ] **Verify**: PDF filter works (All/Work Only/Personal Only)
- [ ] **Verify**: Backward compatibility with old Year Wraps

---

## Manual Test Steps

### Step 1: Categorize Sessions

1. Open app and navigate to History tab
2. Tap on a session to open details
3. Scroll to "Category" picker
4. Select "Work" or "Personal" for each session
5. Categorize at least:
   - 3+ sessions as Work
   - 3+ sessions as Personal
   - Leave 1-2 uncategorized

### Step 2: Generate Year Wrap

1. Navigate to Overview tab
2. Tap on Year Wrap card
3. Tap "Regenerate" button (force regenerate)
4. Wait for AI to complete
5. Check console logs for:
   ```
   📊 [SummaryCoordinator] Year 2025: X work sessions, Y personal sessions
   ```

### Step 3: Verify Results

1. View Year Wrap in app
2. Check that items have category badges:
   - 💼 Work (blue)
   - 🏠 Personal (orange)
   - 🔄 Both (purple)
3. Test PDF export with filters:
   - Export "All" → See all items with prefixes
   - Export "Work Only" → Only work items
   - Export "Personal Only" → Only personal items

### Step 4: Edge Cases

1. Year Wrap with no categorized sessions → Should work (no category context)
2. Year Wrap with only Work sessions → All items should be "work"
3. Year Wrap with only Personal sessions → All items should be "personal"
4. Mixed sessions → Items classified based on source

---

## Expected Logs

### During Year Wrap Generation:

```
📊 [SummaryCoordinator] Starting Year Wrap for 2025
🔄 [SummaryCoordinator] Force regenerate enabled - will call AI
📊 [SummaryCoordinator] Year 2025: 5 work sessions, 3 personal sessions out of 9 total
```

### Category Context Example:

```
The user has categorized their recording sessions this year as: 5 work sessions and 3 personal sessions.

When classifying items in the Year Wrap:
- Items from work sessions should be marked as "work"
- Items from personal sessions should be marked as "personal"
- Items that appear across both types should be marked as "both"
```

---

## Success Criteria

✅ **Complete** when:

1. Sessions can be marked as work/personal in UI
2. Year Wrap generation includes category context
3. AI returns items with correct category classifications
4. UI displays category badges correctly
5. PDF filters work as expected
6. Old Year Wraps still display (backward compatible)

---

## Known Issues

- Pre-existing DataExporter.swift UIKit import errors (unrelated to this feature)
- Old Year Wraps created before this change will show all items as "both" (expected, needs regeneration)

---

## Next Steps

1. **Run manual tests** with the checklist above
2. **Verify AI output** includes category fields in JSON
3. **Test PDF export** with all three filters
4. **Edge case testing** with various session distributions
5. **User acceptance** - Does classification make sense?

---

## Files Modified

### Core Implementation:

- `Packages/SharedModels/Sources/SharedModels/Models.swift` - Added ItemCategory, ItemFilter, ClassifiedItem
- `Packages/SharedModels/Sources/SharedModels/IntelligenceModels.swift` - Added category field to SessionIntelligence
- `Packages/Storage/Sources/Storage/Repositories/SessionRepository.swift` - Added fetchSessionMetadataBatch
- `Packages/Storage/Sources/Storage/DatabaseManager.swift` - Exposed fetchSessionMetadataBatch

### Summarization:

- `Packages/Summarization/Sources/Summarization/UniversalPrompt.swift` - Updated yearlySchema, added categoryContext parameter
- `Packages/Summarization/Sources/Summarization/SummarizationEngine.swift` - Added categoryContext to protocol
- `Packages/Summarization/Sources/Summarization/ExternalAPIEngine.swift` - Implemented categoryContext support
- `Packages/Summarization/Sources/Summarization/SummarizationCoordinator.swift` - Added categoryContext parameter
- `Packages/Summarization/Sources/Summarization/AppleEngine.swift` - Added categoryContext parameter
- `Packages/Summarization/Sources/Summarization/BasicEngine.swift` - Added categoryContext parameter
- `Packages/Summarization/Sources/Summarization/LocalEngine.swift` - Added categoryContext parameter

### App Coordinators:

- `App/Coordinators/SummaryCoordinator.swift` - Added fetchSessionCategoriesForYear, buildCategoryContext, fixed force regenerate

### UI:

- `App/Views/Overview/YearWrapDetailView.swift` - Category badges, PDF filters
- `Packages/Storage/Sources/Storage/DataExporter.swift` - PDF filtering logic

---

## Documentation Updated

- This test plan created
- `.github/copilot-instructions.md` to be updated with classification approach
