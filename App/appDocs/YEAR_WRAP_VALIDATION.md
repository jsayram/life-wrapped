# Year Wrap Topic Validation System

## Problem

Local AI (Phi-3.5 Mini) was fabricating topics not present in the source summaries. Example:

```
❌ "The summarization tool functioned without crashing"
❌ "The summarization tool failed during personal summaries"
```

These topics were completely invented by the AI, not extracted from actual recording summaries.

## Root Cause

- **Prompt Hallucination**: Even with "CRITICAL: Only mention what's in summaries" instructions, small LLMs can hallucinate
- **No Verification**: Single-pass extraction had no validation against source material
- **Inference Over Facts**: AI was inferring/imagining content rather than strictly extracting

## Solution: Two-Pass Validation System

### Architecture

```
Month Summaries → Extract Topics → Validate Topics → Verified Output
     (Step 1)         (Step 4)        (Step 5)        (Final)
```

### Implementation

**Step 4: Topic Extraction** (64 tokens)

```swift
private func buildTopicsActionsPrompt(summaries: String, categoryLabel: String) -> String {
    return """
    Extract main topics from the summary below. List only what's explicitly mentioned (2-3 items).

    SUMMARY:
    \(summaries.prefix(400))

    CRITICAL: Extract only actual topics/themes from the SUMMARY above.
    """
}
```

**Step 5: Topic Validation** (64 tokens) - NEW!

```swift
private func buildValidationPrompt(extractedTopics: String, sourceSummaries: String) -> String {
    return """
    Review these extracted topics and verify each one appears in the source summaries.

    EXTRACTED TOPICS:
    \(extractedTopics)

    SOURCE SUMMARIES:
    \(sourceSummaries.prefix(600))

    TASK: For each topic, check if it's actually mentioned in the source.
    Remove any fabricated topics.

    CRITICAL: Be strict. Only keep topics with clear evidence in the source.
    """
}
```

### Generation Flow

**Before (5 Steps):**

1. Title & Summary (128 tokens)
2. Wins & Challenges (64 tokens)
3. Projects (64 tokens)
4. Topics & Actions (64 tokens) ← Single pass, no validation
5. People (32 tokens)

**After (6 Steps):**

1. Title & Summary (128 tokens)
2. Wins & Challenges (64 tokens)
3. Projects (64 tokens)
4. **Extract Topics** (64 tokens) ← First pass
5. **Validate Topics** (64 tokens) ← Second pass (NEW!)
6. People (32 tokens)

### Code Changes

**File**: [LocalEngine.swift](../../Packages/Summarization/Sources/Summarization/LocalEngine.swift)

```swift
// Step 4: Extract topics
let topicsPrompt = buildTopicsActionsPrompt(summaries: combinedQuarterlySummaries, categoryLabel: categoryLabel)
let rawTopics = try await llamaContext.generate(prompt: topicsPrompt, maxTokens: 64)
totalLLMCalls += 1
try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

// Step 5: Validate topics against source
let validationPrompt = buildValidationPrompt(extractedTopics: rawTopics, sourceSummaries: combinedQuarterlySummaries)
let topics = try await llamaContext.generate(prompt: validationPrompt, maxTokens: 64)
totalLLMCalls += 1
```

### Strengthened Prompts

All prompts now include explicit "DO NOT FABRICATE" instructions:

**Title & Summary:**

```
CRITICAL RULES:
- Write in FIRST PERSON (I/my/me)
- Only mention what's actually in the SUMMARIES above
- DO NOT make up, infer, or imagine any content
- Every statement must have evidence in the summaries
- If you can't find something in the summaries, don't mention it
```

**Wins & Challenges:**

```
CRITICAL RULES:
- Only list what's explicitly mentioned in the SUMMARIES
- DO NOT invent or imagine wins/challenges
- If no wins/challenges found, output "None found"
- Every item must have clear evidence in the summaries
```

**Projects:**

```
CRITICAL RULES:
- Only list projects explicitly mentioned in the SUMMARIES
- DO NOT invent or imagine projects
- If none found, output "None found"
- Every project must be clearly stated in the summaries
```

## Performance Impact

### Token Cost

- **Added**: 64 tokens per validation step
- **Total**: 352 tokens → 416 tokens (18% increase)
- **Time**: ~5-7 seconds added per variant (extraction + validation)

### Total Generation Time

- **Before**: ~120 seconds (3 variants × 40s each)
- **After**: ~140 seconds (3 variants × ~47s each)
- **Trade-off**: +20 seconds for accuracy ✅

### Memory

- No additional memory overhead
- Still within 2.1GB GPU limit on iPhone
- Validation uses same model, no reload needed

## Validation Logic

The validation prompt instructs the AI to:

1. **Read extracted topics** from Step 4 output
2. **Search source summaries** for evidence of each topic
3. **Remove fabricated items** that have no evidence
4. **Output only verified topics** that clearly exist in source

**Example:**

**Input (Step 4 output):**

```
- Working on summarization tool
- Debugging app crashes
- Learning Swift concurrency
```

**Validation (Step 5):**

```
Source contains: "Working on summarization", "Debugging crashes"
No evidence for: "Learning Swift concurrency" ← Remove

Verified output:
- Working on summarization tool
- Debugging app crashes
```

## Testing Strategy

### Unit Tests

- Mock summaries with known topics
- Verify extracted topics exist in source
- Confirm fabricated topics are removed

### Integration Tests

- Generate Year Wrap with real recordings
- Manual review of topics against transcripts
- Verify no hallucinated content

### Edge Cases

- **Empty summaries**: Should output "None found"
- **Vague summaries**: Should extract conservative topics only
- **Multiple interpretations**: Should choose most explicit one

## Future Enhancements

### Three-Pass System (If Needed)

```
Extract → Validate → Re-extract
```

1. First extraction (broad)
2. Validation (strict filtering)
3. Second extraction (refine survivors)

### Semantic Matching

Use embeddings to verify topic similarity:

```swift
func validateTopicWithEmbeddings(topic: String, source: String) -> Bool {
    let topicEmbedding = nlModel.embedding(for: topic)
    let sourceEmbedding = nlModel.embedding(for: source)
    let similarity = cosineSimilarity(topicEmbedding, sourceEmbedding)
    return similarity > 0.7 // Threshold
}
```

### Confidence Scores

Add confidence metadata to each topic:

```json
{
  "topic": "Working on app stability",
  "confidence": 0.95,
  "evidence": "...fixing crashes and improving performance..."
}
```

## Related Documentation

- [Local AI Architecture](LOCAL_AI_ARCHITECTURE.md) - Phi-3.5 Mini implementation
- [Year Wrap Progress Tracking](YEAR_WRAP_PROGRESS_TRACKING.md) - UI feedback
- [AI Architecture](AI_ARCHITECTURE.md) - Multi-tier system overview

## Changelog

- **2024-01-03**: Initial two-pass validation system
- Added Step 5: Topic validation against source summaries
- Strengthened all prompts with "DO NOT FABRICATE" rules
- Increased generation time by ~20s for accuracy
- Total steps: 5 → 6 per variant
