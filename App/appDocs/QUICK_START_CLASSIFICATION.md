# Quick Start: Testing Work/Personal Classification

> **Status, September 28, 2026:** written in December 2025 for the first Year Wrap. Year Wrap has since been rebuilt: Work and Personal are separate journals with their own month summaries and their own wrap, "All" is put together in code, and since 1.3 wraps can be made with any summary engine. The steps below no longer match the app.

## 🎯 Goal

Verify that Year Wrap items are correctly classified as Work/Personal/Both based on your session categories.

---

## ⚡ Quick Test (5 minutes)

### 1. Mark Some Sessions (2 min)

Open app → History tab → Tap sessions → Mark categories:

- Mark 3 sessions as **Work** 💼
- Mark 3 sessions as **Personal** 🏠
- Leave 2-3 **Uncategorized**

### 2. Regenerate Year Wrap (2 min)

Overview tab → Year Wrap card → Tap **Regenerate**

- Wait for AI to complete (~30 seconds)
- Watch logs for: `📊 Year 2025: X work, Y personal`

### 3. Check Results (1 min)

View Year Wrap → Look for category badges:

- **💼 Work** (blue) - From work sessions
- **🏠 Personal** (orange) - From personal sessions
- **🔄 Both** (purple) - Across both types

---

## 📋 Expected Behavior

### ✅ What Should Happen:

1. Sessions marked as Work → Items show 💼 Work badge
2. Sessions marked as Personal → Items show 🏠 Personal badge
3. Items appearing in both → Show 🔄 Both badge
4. PDF filters work: All / Work Only / Personal Only

### ❌ What Should NOT Happen:

1. All items showing as "Both" (old behavior)
2. AI guessing categories from content
3. Categories changing when regenerating with same sessions

---

## 🔍 How to Verify

### Check Console Logs:

```
📊 [SummaryCoordinator] Year 2025: 3 work sessions, 3 personal sessions out of 9 total
🔄 [SummaryCoordinator] Force regenerate enabled - will call AI
```

### Check Year Wrap UI:

- Open any insight section (Major Arcs, Wins, etc.)
- Each item should have a colored badge
- Different items should have different categories

### Test PDF Export:

1. Tap Share → Export PDF
2. Try each filter:
   - **All**: See all items with category prefixes
   - **Work Only**: Only items with 💼
   - **Personal Only**: Only items with 🏠

---

## 🐛 Troubleshooting

### "All items still showing 'Both'"

→ The Year Wrap wasn't regenerated with new code  
→ **Fix**: Tap Regenerate button again

### "No category context in logs"

→ Sessions aren't marked with categories  
→ **Fix**: Mark sessions as Work/Personal in detail view

### "Force regenerate not working"

→ Build might be stale  
→ **Fix**: Clean build folder, rebuild app

### "Old format warning in logs"

→ Existing Year Wrap from before this feature  
→ **Fix**: Normal, regenerate will create new format

---

## 📊 Test Matrix

| Sessions Marked  | Expected Result                     |
| ---------------- | ----------------------------------- |
| All Work         | All items show 💼 Work              |
| All Personal     | All items show 🏠 Personal          |
| Mixed (50/50)    | Items split by source, some 🔄 Both |
| None categorized | Items default to 🔄 Both            |

---

## ✅ Success Criteria

You're done when:

- [x] Sessions can be marked as Work/Personal
- [x] Year Wrap regenerates with new schema
- [x] Items display category badges
- [x] PDF filters work correctly
- [x] Makes intuitive sense

---

## 📝 Notes

- First regenerate after this change will take ~30s (AI call)
- Subsequent views are instant (cached)
- Old Year Wraps still work (backward compatible)
- Categories persist across app restarts

---

## 🆘 Need Help?

Check detailed documentation:

- [WORK_PERSONAL_CLASSIFICATION_TEST.md](./WORK_PERSONAL_CLASSIFICATION_TEST.md) - Full test plan
- [.github/copilot-instructions.md](../.github/copilot-instructions.md) - Architecture docs

Console logs are your friend! Look for:

- `📊 [SummaryCoordinator]` - Category statistics
- `🔄 [SummaryCoordinator]` - Regeneration status
- `✅/❌` - Success/failure indicators
