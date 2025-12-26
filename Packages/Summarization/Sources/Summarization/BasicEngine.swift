//
//  BasicEngine.swift
//  Summarization
//
//  Created by Life Wrapped on 12/16/2025.
//  Enhanced with TF-IDF, NLEmbedding, NLTokenizer, Key Moments, and Trend Detection
//

import Foundation
import NaturalLanguage
import SharedModels
import Storage

// MARK: - Embedding Cache

/// Thread-safe cache for word embeddings to improve performance
/// Caches top 1000 most frequently used words
private final class EmbeddingCache: @unchecked Sendable {
    private var cache: [String: [Double]] = [:]
    private let lock = NSLock()
    private let maxSize = 1000
    private var accessCount: [String: Int] = [:]
    
    func get(_ word: String) -> [Double]? {
        lock.lock()
        defer { lock.unlock() }
        if let vector = cache[word] {
            accessCount[word, default: 0] += 1
            return vector
        }
        return nil
    }
    
    func set(_ word: String, vector: [Double]) {
        lock.lock()
        defer { lock.unlock() }
        
        // Evict least accessed if at capacity
        if cache.count >= maxSize {
            if let leastAccessed = accessCount.min(by: { $0.value < $1.value })?.key {
                cache.removeValue(forKey: leastAccessed)
                accessCount.removeValue(forKey: leastAccessed)
            }
        }
        
        cache[word] = vector
        accessCount[word] = 1
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}

// MARK: - BasicEngine

/// Enhanced basic summarization engine using Apple's Natural Language framework
/// Features: TF-IDF ranking, semantic embeddings, proper tokenization, key moments detection
public actor BasicEngine: SummarizationEngine {
    
    // MARK: - Protocol Properties
    
    public let tier: EngineTier = .basic
    
    // MARK: - Private Properties
    
    private let storage: DatabaseManager
    private let config: EngineConfiguration
    
    // MARK: - NLP Resources
    
    /// Shared embedding for semantic similarity (English)
    /// NLEmbedding is thread-safe for reads; marked nonisolated(unsafe) for Swift 6 concurrency
    nonisolated(unsafe) private static let wordEmbedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)
    
    /// Cache for frequently used word embeddings
    private static let embeddingCache = EmbeddingCache()
    
    /// Combined stopwords: custom list + NLTagger detection
    private static let stopWords: Set<String> = {
        var words: Set<String> = [
            // Articles
            "a", "an", "the",
            // Pronouns
            "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
            "my", "your", "his", "its", "our", "their", "mine", "yours", "hers", "ours", "theirs",
            "myself", "yourself", "himself", "herself", "itself", "ourselves", "themselves",
            "this", "that", "these", "those", "who", "whom", "whose", "what", "which",
            // Prepositions
            "about", "above", "across", "after", "against", "along", "among", "around", "as", "at",
            "before", "behind", "below", "beneath", "beside", "between", "beyond", "by", "down",
            "during", "for", "from", "in", "inside", "into", "near", "of", "off", "on", "onto",
            "out", "outside", "over", "past", "through", "to", "toward", "towards", "under",
            "until", "up", "upon", "with", "within", "without",
            // Conjunctions
            "and", "but", "or", "nor", "so", "yet", "because", "although", "if", "when", "while",
            // Common verbs
            "am", "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "having",
            "do", "does", "did", "doing", "done", "can", "could", "may", "might", "must", "shall",
            "should", "will", "would", "get", "got", "go", "goes", "going", "gone", "went",
            "come", "comes", "coming", "came", "make", "makes", "making", "made",
            // Adverbs
            "very", "really", "quite", "rather", "too", "so", "just", "only", "even", "also",
            "now", "then", "here", "there", "always", "never", "often", "sometimes",
            // Fillers (important for speech transcripts!)
            "um", "uh", "er", "ah", "oh", "hmm", "huh", "mhm", "yeah", "yep", "yup", "nope",
            "like", "okay", "ok", "alright", "right", "well", "anyway", "basically", "actually",
            "literally", "gonna", "wanna", "gotta", "kinda", "sorta"
        ]
        return words
    }()
    
    // MARK: - Statistics
    
    private(set) var summariesGenerated: Int = 0
    private(set) var totalProcessingTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    public init(storage: DatabaseManager, config: EngineConfiguration? = nil) {
        self.storage = storage
        self.config = config ?? .defaults(for: .basic)
        
        #if DEBUG
        print("🧪 [BasicEngine] Running timestamp removal test...")
        _ = testTimestampRemoval()
        print("🧠 [BasicEngine] Word embedding available: \(Self.wordEmbedding != nil)")
        #endif
    }
    
    // MARK: - SummarizationEngine Protocol
    
    public func isAvailable() async -> Bool {
        return true
    }
    
    public func summarizeSession(
        sessionId: UUID,
        transcriptText: String,
        duration: TimeInterval,
        languageCodes: [String]
    ) async throws -> SessionIntelligence {
        let startTime = Date()
        
        // Clean timestamps from input
        let cleanedText = removeTimestamps(from: transcriptText)
        
        // Tokenize properly using NLTokenizer
        let words = tokenize(cleanedText, unit: .word)
        let wordCount = words.count
        
        guard wordCount >= config.minimumWords else {
            throw SummarizationError.insufficientContent(
                minimumWords: config.minimumWords,
                actualWords: wordCount
            )
        }
        
        // Detect language for fallback handling
        let detectedLanguage = detectLanguage(cleanedText)
        let useSemanticScoring = detectedLanguage == .english && Self.wordEmbedding != nil
        
        // Truncate if needed
        let processedText = truncateToWords(cleanedText, maxWords: config.maxContextLength)
        
        // Extract sentences properly
        let sentences = tokenize(processedText, unit: .sentence)
            .filter { $0.split(separator: " ").count > 3 }
        
        // Build TF-IDF scores for keywords
        let tfidfScores = computeTFIDF(sentences: sentences)
        
        // Extract topics using TF-IDF ranking
        let topics = extractTopicsWithTFIDF(tfidfScores: tfidfScores, limit: 5)
        
        // Generate summary using enhanced scoring
        let summaryText = generateSummary(
            sentences: sentences,
            tfidfScores: tfidfScores,
            useSemanticScoring: useSemanticScoring,
            maxWords: 150
        )
        
        // Extract entities
        let entities = extractEntities(from: processedText)
        
        // Analyze sentiment
        let sentiment = analyzeSentiment(from: processedText)
        
        // Extract key moments (high-sentiment or entity-rich sentences)
        let keyMoments = extractKeyMoments(
            sentences: sentences,
            entities: entities,
            limit: 3
        )
        
        // Update statistics
        let processingTime = Date().timeIntervalSince(startTime)
        summariesGenerated += 1
        totalProcessingTime += processingTime
        
        #if DEBUG
        print("📊 [BasicEngine] Summary generated in \(String(format: "%.2f", processingTime))s")
        print("   - Words: \(wordCount), Sentences: \(sentences.count)")
        print("   - Semantic scoring: \(useSemanticScoring)")
        print("   - Cache size: \(Self.embeddingCache.count)")
        #endif
        
        return SessionIntelligence(
            sessionId: sessionId,
            summary: summaryText,
            topics: topics,
            entities: entities,
            sentiment: sentiment,
            duration: duration,
            wordCount: wordCount,
            languageCodes: languageCodes,
            keyMoments: keyMoments.isEmpty ? nil : keyMoments
        )
    }
    
    public func summarizePeriod(
        periodType: PeriodType,
        sessionSummaries: [SessionIntelligence],
        periodStart: Date,
        periodEnd: Date
    ) async throws -> PeriodIntelligence {
        guard !sessionSummaries.isEmpty else {
            throw SummarizationError.noTranscriptData
        }
        
        // Clean and format summaries WITHOUT timestamps
        let cleanedSummaries = sessionSummaries.map { intelligence -> String in
            removeTimestamps(from: intelligence.summary)
        }
        
        // For period summaries, create a coherent narrative
        let combinedText = cleanedSummaries.joined(separator: " ")
        let sentences = tokenize(combinedText, unit: .sentence)
            .filter { $0.split(separator: " ").count > 3 }
        
        // Build TF-IDF for the combined text
        let tfidfScores = computeTFIDF(sentences: sentences)
        
        // Detect language
        let detectedLanguage = detectLanguage(combinedText)
        let useSemanticScoring = detectedLanguage == .english && Self.wordEmbedding != nil
        
        // Generate a coherent period summary (not just bullet points)
        let periodSummary: String
        if sentences.count <= 3 {
            // Few sentences - use them all
            periodSummary = sentences.joined(separator: ". ") + (sentences.isEmpty ? "" : ".")
        } else {
            // Generate extractive summary
            periodSummary = generateSummary(
                sentences: sentences,
                tfidfScores: tfidfScores,
                useSemanticScoring: useSemanticScoring,
                maxWords: periodType == .day ? 100 : (periodType == .week ? 150 : 200)
            )
        }
        
        // Aggregate topics with frequency
        let allTopics = sessionSummaries.flatMap { $0.topics }
        let topics = aggregateTopicsWithFrequency(allTopics, limit: 10)
        
        // Aggregate entities
        let allEntities = sessionSummaries.flatMap { $0.entities }
        let entities = aggregateEntities(allEntities, limit: 15)
        
        // Average sentiment
        let avgSentiment = sessionSummaries.map { $0.sentiment }.reduce(0.0, +) / Double(sessionSummaries.count)
        
        // Calculate totals
        let totalDuration = sessionSummaries.map { $0.duration }.reduce(0, +)
        let totalWords = sessionSummaries.map { $0.wordCount }.reduce(0, +)
        
        // Detect trends (topic changes across sessions)
        let trends = detectTrends(sessionSummaries: sessionSummaries)
        
        return PeriodIntelligence(
            periodType: periodType,
            periodStart: periodStart,
            periodEnd: periodEnd,
            summary: periodSummary,
            topics: topics,
            entities: entities,
            sentiment: avgSentiment,
            sessionCount: sessionSummaries.count,
            totalDuration: totalDuration,
            totalWordCount: totalWords,
            trends: trends.isEmpty ? nil : trends
        )
    }
    
    // MARK: - Statistics
    
    public func getStatistics() -> (summariesGenerated: Int, averageProcessingTime: TimeInterval) {
        let avgTime = summariesGenerated > 0 ? totalProcessingTime / Double(summariesGenerated) : 0
        return (summariesGenerated, avgTime)
    }
    
    public func resetStatistics() {
        summariesGenerated = 0
        totalProcessingTime = 0
    }
    
    // MARK: - NLP Tokenization
    
    /// Proper tokenization using NLTokenizer
    private nonisolated func tokenize(_ text: String, unit: NLTokenUnit) -> [String] {
        let tokenizer = NLTokenizer(unit: unit)
        tokenizer.string = text
        
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let token = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }
    
    /// Detect text language
    private nonisolated func detectLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }
    
    // MARK: - TF-IDF Implementation
    
    /// Compute TF-IDF scores for all words across sentences
    private nonisolated func computeTFIDF(sentences: [String]) -> [String: Double] {
        guard !sentences.isEmpty else { return [:] }
        
        // Term frequency per sentence
        var termFrequencies: [[String: Int]] = []
        var documentFrequency: [String: Int] = [:]
        
        for sentence in sentences {
            let words = tokenize(sentence, unit: .word)
                .map { $0.lowercased() }
                .filter { isContentWord($0) }
            
            var tf: [String: Int] = [:]
            for word in words {
                tf[word, default: 0] += 1
            }
            termFrequencies.append(tf)
            
            // Count documents containing each word
            for word in Set(words) {
                documentFrequency[word, default: 0] += 1
            }
        }
        
        // Calculate TF-IDF
        let n = Double(sentences.count)
        var tfidfScores: [String: Double] = [:]
        
        for (index, tf) in termFrequencies.enumerated() {
            let sentenceWords = tokenize(sentences[index], unit: .word)
            let totalWords = Double(sentenceWords.count)
            guard totalWords > 0 else { continue }
            
            for (word, count) in tf {
                let termFreq = Double(count) / totalWords
                let docFreq = Double(documentFrequency[word] ?? 1)
                let idf = log(n / docFreq) + 1.0  // Smoothed IDF
                let tfidf = termFreq * idf
                
                // Accumulate score (higher = more important across document)
                tfidfScores[word, default: 0] += tfidf
            }
        }
        
        return tfidfScores
    }
    
    /// Check if word is a content word (not a stopword)
    private nonisolated func isContentWord(_ word: String) -> Bool {
        let lowered = word.lowercased()
        
        // Check custom stopwords
        if Self.stopWords.contains(lowered) {
            return false
        }
        
        // Filter very short words
        if lowered.count < 3 {
            return false
        }
        
        // Filter numbers
        if Double(lowered) != nil {
            return false
        }
        
        // Use NLTagger to check lexical class
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = word
        
        if let tag = tagger.tag(at: word.startIndex, unit: .word, scheme: .lexicalClass).0 {
            // Keep nouns, verbs (non-auxiliary), adjectives, adverbs
            switch tag {
            case .noun, .verb, .adjective, .adverb:
                return true
            default:
                return false
            }
        }
        
        return true
    }
    
    /// Extract topics using TF-IDF scores
    private nonisolated func extractTopicsWithTFIDF(tfidfScores: [String: Double], limit: Int) -> [String] {
        return tfidfScores
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    // MARK: - Semantic Scoring with NLEmbedding
    
    /// Get word embedding vector with caching
    private nonisolated func getEmbedding(for word: String) -> [Double]? {
        let lowered = word.lowercased()
        
        // Check cache first
        if let cached = Self.embeddingCache.get(lowered) {
            return cached
        }
        
        // Get from NLEmbedding
        guard let embedding = Self.wordEmbedding,
              let vector = embedding.vector(for: lowered) else {
            return nil
        }
        
        let vectorArray = Array(vector)
        Self.embeddingCache.set(lowered, vector: vectorArray)
        return vectorArray
    }
    
    /// Compute average embedding for a sentence
    private nonisolated func sentenceEmbedding(_ sentence: String) -> [Double]? {
        let words = tokenize(sentence, unit: .word)
            .filter { isContentWord($0) }
        
        guard !words.isEmpty else { return nil }
        
        var sumVector: [Double]? = nil
        var count = 0
        
        for word in words {
            if let vector = getEmbedding(for: word) {
                if sumVector == nil {
                    sumVector = vector
                } else {
                    for i in 0..<vector.count {
                        sumVector![i] += vector[i]
                    }
                }
                count += 1
            }
        }
        
        guard let sum = sumVector, count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }
    
    /// Compute cosine similarity between two vectors
    private nonisolated func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        return denominator > 0 ? dotProduct / denominator : 0
    }
    
    // MARK: - Summary Generation
    
    /// Generate summary using enhanced multi-factor scoring with de-duplication
    private nonisolated func generateSummary(
        sentences: [String],
        tfidfScores: [String: Double],
        useSemanticScoring: Bool,
        maxWords: Int
    ) -> String {
        guard !sentences.isEmpty else {
            return "No content available for summary."
        }
        
        // Calculate document centroid for semantic scoring
        var documentEmbedding: [Double]? = nil
        if useSemanticScoring {
            let allText = sentences.joined(separator: " ")
            documentEmbedding = sentenceEmbedding(allText)
        }
        
        // Score each sentence (now tracking index for de-duplication)
        let scoredSentences = sentences.enumerated().map { index, sentence -> (sentence: String, score: Double, index: Int) in
            var score = 0.0
            
            // 1. Position score (first and last sentences often important)
            let position = Double(index) / Double(sentences.count)
            let positionScore: Double
            if position < 0.2 {
                positionScore = 1.0  // First 20%
            } else if position > 0.8 {
                positionScore = 0.7  // Last 20%
            } else {
                positionScore = 0.5 - (position - 0.5).magnitude * 0.5
            }
            score += positionScore * 0.15
            
            // 2. Length score (prefer medium-length sentences)
            let wordCount = sentence.split(separator: " ").count
            let lengthScore: Double
            if wordCount >= 10 && wordCount <= 30 {
                lengthScore = 1.0
            } else if wordCount >= 5 && wordCount <= 40 {
                lengthScore = 0.7
            } else {
                lengthScore = 0.3
            }
            score += lengthScore * 0.10
            
            // 3. TF-IDF keyword score
            let words = tokenize(sentence, unit: .word).map { $0.lowercased() }
            var keywordScore = 0.0
            for word in words {
                keywordScore += tfidfScores[word] ?? 0
            }
            keywordScore = min(keywordScore / Double(max(words.count, 1)), 1.0)
            score += keywordScore * 0.35
            
            // 4. Semantic similarity score (if available)
            if useSemanticScoring, let docEmbed = documentEmbedding,
               let sentEmbed = sentenceEmbedding(sentence) {
                let similarity = cosineSimilarity(sentEmbed, docEmbed)
                score += similarity * 0.25
            } else {
                // Fallback: boost keyword score weight
                score += keywordScore * 0.15
            }
            
            // 5. Entity presence bonus
            let entityScore = hasNamedEntities(sentence) ? 0.15 : 0
            score += entityScore
            
            return (sentence, score, index)
        }
        
        // Select top sentences WITH de-duplication
        let avgWordsPerSentence = 15
        let maxSentences = max(1, maxWords / avgWordsPerSentence)
        
        let selected = selectWithDeduplication(
            scoredSentences: scoredSentences,
            maxSentences: maxSentences,
            useSemanticScoring: useSemanticScoring,
            similarityThreshold: 0.75  // Skip if >75% similar to already selected
        )
        
        // Restore original order for coherence
        let ordered = selected
            .sorted { $0.index < $1.index }
            .map { $0.sentence }
        
        // Join with proper punctuation
        var summary = ordered.joined(separator: ". ")
        if !summary.isEmpty && !summary.hasSuffix(".") && !summary.hasSuffix("!") && !summary.hasSuffix("?") {
            summary += "."
        }
        
        return summary
    }
    
    // MARK: - De-duplication
    
    /// Select sentences while filtering out semantically similar ones
    /// Uses both semantic similarity (embeddings) and lexical overlap (Jaccard)
    private nonisolated func selectWithDeduplication(
        scoredSentences: [(sentence: String, score: Double, index: Int)],
        maxSentences: Int,
        useSemanticScoring: Bool,
        similarityThreshold: Double
    ) -> [(sentence: String, score: Double, index: Int)] {
        // Sort by score (highest first)
        let sorted = scoredSentences.sorted { $0.score > $1.score }
        
        var selected: [(sentence: String, score: Double, index: Int)] = []
        var selectedEmbeddings: [[Double]] = []
        var selectedWordSets: [Set<String>] = []
        
        for candidate in sorted {
            guard selected.count < maxSentences else { break }
            
            // Get candidate's word set for Jaccard similarity
            let candidateWords = Set(
                tokenize(candidate.sentence, unit: .word)
                    .map { $0.lowercased() }
                    .filter { isContentWord($0) }
            )
            
            // Skip very short sentences (likely fragments)
            guard candidateWords.count >= 3 else { continue }
            
            // Check for duplicates
            var isDuplicate = false
            
            // 1. Check lexical similarity (Jaccard) - works for all languages
            for selectedWords in selectedWordSets {
                let jaccardSim = jaccardSimilarity(candidateWords, selectedWords)
                if jaccardSim >= similarityThreshold {
                    isDuplicate = true
                    #if DEBUG
                    print("🔄 [Dedup] Skipping (Jaccard=\(String(format: "%.2f", jaccardSim))): \(candidate.sentence.prefix(50))...")
                    #endif
                    break
                }
            }
            
            // 2. Check semantic similarity (embeddings) - English only
            if !isDuplicate && useSemanticScoring {
                if let candidateEmbed = sentenceEmbedding(candidate.sentence) {
                    for selectedEmbed in selectedEmbeddings {
                        let semanticSim = cosineSimilarity(candidateEmbed, selectedEmbed)
                        if semanticSim >= similarityThreshold {
                            isDuplicate = true
                            #if DEBUG
                            print("🔄 [Dedup] Skipping (Semantic=\(String(format: "%.2f", semanticSim))): \(candidate.sentence.prefix(50))...")
                            #endif
                            break
                        }
                    }
                    
                    // Store embedding for future comparisons
                    if !isDuplicate {
                        selectedEmbeddings.append(candidateEmbed)
                    }
                }
            }
            
            // Add if not duplicate
            if !isDuplicate {
                selected.append(candidate)
                selectedWordSets.append(candidateWords)
            }
        }
        
        return selected
    }
    
    /// Calculate Jaccard similarity between two word sets
    /// Returns value between 0.0 (no overlap) and 1.0 (identical)
    private nonisolated func jaccardSimilarity(_ set1: Set<String>, _ set2: Set<String>) -> Double {
        guard !set1.isEmpty || !set2.isEmpty else { return 0.0 }
        
        let intersection = set1.intersection(set2).count
        let union = set1.union(set2).count
        
        return Double(intersection) / Double(union)
    }
    
    /// Check if sentence contains named entities
    private nonisolated func hasNamedEntities(_ text: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var hasEntity = false
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: [.omitWhitespace]) { tag, _ in
            if tag != nil {
                hasEntity = true
                return false  // Stop enumeration
            }
            return true
        }
        return hasEntity
    }
    
    // MARK: - Key Moments Extraction
    
    /// Extract key moments (high-impact sentences)
    private func extractKeyMoments(
        sentences: [String],
        entities: [Entity],
        limit: Int
    ) -> [KeyMoment] {
        var scoredMoments: [(sentence: String, score: Double, index: Int)] = []
        
        for (index, sentence) in sentences.enumerated() {
            var score = 0.0
            
            // Sentiment intensity
            let sentiment = analyzeSentiment(from: sentence)
            score += abs(sentiment) * 2.0  // Strong emotions = interesting
            
            // Entity density
            let sentenceEntities = extractEntities(from: sentence)
            score += Double(sentenceEntities.count) * 0.5
            
            // Exclamation/question = emphasis
            if sentence.contains("!") { score += 0.3 }
            if sentence.contains("?") { score += 0.2 }
            
            // Length (not too short, not too long)
            let wordCount = sentence.split(separator: " ").count
            if wordCount >= 8 && wordCount <= 25 {
                score += 0.3
            }
            
            scoredMoments.append((sentence, score, index))
        }
        
        // Sort by score and take top moments
        let topMoments = scoredMoments
            .sorted { $0.score > $1.score }
            .prefix(limit)
        
        // Convert to KeyMoment objects
        // Use sentence index as approximate timestamp position (normalized 0-1)
        let totalSentences = max(sentences.count, 1)
        return topMoments.map { moment in
            KeyMoment(
                timestamp: Double(moment.index) / Double(totalSentences),
                description: moment.sentence,
                importance: min(moment.score / 3.0, 1.0)  // Normalize to 0-1
            )
        }
    }
    
    // MARK: - Trend Detection
    
    /// Detect trends across sessions
    private func detectTrends(sessionSummaries: [SessionIntelligence]) -> [String] {
        guard sessionSummaries.count >= 2 else { return [] }
        
        // Split into halves
        let midpoint = sessionSummaries.count / 2
        let firstHalf = Array(sessionSummaries.prefix(midpoint))
        let secondHalf = Array(sessionSummaries.suffix(from: midpoint))
        
        // Count topics in each half
        var firstTopics: [String: Int] = [:]
        var secondTopics: [String: Int] = [:]
        
        for session in firstHalf {
            for topic in session.topics {
                firstTopics[topic, default: 0] += 1
            }
        }
        
        for session in secondHalf {
            for topic in session.topics {
                secondTopics[topic, default: 0] += 1
            }
        }
        
        // Find emerging topics (new or significantly increased)
        var trends: [String] = []
        
        for (topic, count) in secondTopics {
            let firstCount = firstTopics[topic] ?? 0
            if count > firstCount * 2 || (firstCount == 0 && count >= 2) {
                trends.append("📈 \(topic)")
            }
        }
        
        // Find declining topics
        for (topic, count) in firstTopics {
            let secondCount = secondTopics[topic] ?? 0
            if count > secondCount * 2 && count >= 2 {
                trends.append("📉 \(topic)")
            }
        }
        
        return Array(trends.prefix(5))
    }
    
    // MARK: - Entity Extraction
    
    /// Extract entities using NLTagger
    private func extractEntities(from text: String) -> [Entity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        
        var entities: [Entity] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, tokenRange in
            if let tag = tag {
                let name = String(text[tokenRange])
                let entityType = mapNLTagToEntityType(tag)
                let entity = Entity(name: name, type: entityType, confidence: 0.7)
                entities.append(entity)
            }
            return true
        }
        
        return entities.uniqueNames.prefix(10).map { name in
            entities.first(where: { $0.name == name }) ?? Entity(name: name, type: .other, confidence: 0.5)
        }
    }
    
    /// Map NLTag to EntityType
    private func mapNLTagToEntityType(_ tag: NLTag) -> EntityType {
        switch tag {
        case .personalName: return .person
        case .placeName: return .location
        case .organizationName: return .organization
        default: return .other
        }
    }
    
    // MARK: - Sentiment Analysis
    
    /// Analyze sentiment using NLTagger
    private func analyzeSentiment(from text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        
        guard let tag = tag, let score = Double(tag.rawValue) else {
            return 0.0
        }
        
        return score
    }
    
    // MARK: - Topic Aggregation
    
    /// Aggregate topics with frequency weighting
    private func aggregateTopicsWithFrequency(_ topics: [String], limit: Int) -> [String] {
        var frequencies: [String: Int] = [:]
        for topic in topics {
            frequencies[topic.lowercased(), default: 0] += 1
        }
        
        return frequencies
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { $0.key }
    }
    
    /// Aggregate entities from multiple sessions
    private func aggregateEntities(_ entities: [Entity], limit: Int) -> [Entity] {
        var grouped: [String: Entity] = [:]
        for entity in entities {
            let key = entity.name.lowercased()
            if let existing = grouped[key] {
                if entity.confidence > existing.confidence {
                    grouped[key] = entity
                }
            } else {
                grouped[key] = entity
            }
        }
        
        return Array(grouped.values.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }
    
    // MARK: - Text Utilities
    
    /// Truncate text to maximum word count
    private nonisolated func truncateToWords(_ text: String, maxWords: Int) -> String {
        let words = tokenize(text, unit: .word)
        guard words.count > maxWords else { return text }
        return words.prefix(maxWords).joined(separator: " ") + "..."
    }
    
    /// Remove timestamps from text
    private nonisolated func removeTimestamps(from text: String) -> String {
        var cleaned = text
        
        // Remove timestamp patterns: "• Dec 22, 2025 12:00 AM: "
        let anyTimestampPattern = #"(?:[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*)+"#
        cleaned = cleaned.replacingOccurrences(of: anyTimestampPattern, with: "", options: .regularExpression)
        
        // Safety pass
        let singlePattern = #"[•●]?\s*[A-Za-z]+\s+\d{1,2},\s+\d{4}\s+\d{1,2}:\d{2}\s+[AP]M:\s*"#
        cleaned = cleaned.replacingOccurrences(of: singlePattern, with: "", options: .regularExpression)
        
        // Remove leading bullets
        cleaned = cleaned.replacingOccurrences(of: #"^[•●\s]+"#, with: "", options: .regularExpression)
        
        // Clean whitespace
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Testing
    
    public nonisolated func testTimestampRemoval() -> Bool {
        let testCases = [
            "• Dec 22, 2025 12:00 AM: • Dec 22, 2025 12:00 AM: • Dec 22, 2025 9:08 PM: OK, I'm gonna just start recording this.",
            "• Dec 22, 2025 8:47 PM: OK, so I'm gonna try to see this.",
            "Dec 22, 2025 12:00 AM: Text without bullet",
            "• Dec 1, 2025 12:00 AM: Some text here"
        ]
        
        #if DEBUG
        print("🧪 [BasicEngine] Testing timestamp removal:")
        #endif
        
        var allPassed = true
        for (index, test) in testCases.enumerated() {
            let cleaned = removeTimestamps(from: test)
            let hasTimestamp = cleaned.range(of: #"\d{1,2}:\d{2}\s+[AP]M"#, options: .regularExpression) != nil
            
            if hasTimestamp {
                #if DEBUG
                print("❌ Test \(index + 1) FAILED: Timestamp remains in '\(cleaned)'")
                #endif
                allPassed = false
            } else {
                #if DEBUG
                print("✅ Test \(index + 1) PASSED: '\(cleaned)'")
                #endif
            }
        }
        
        return allPassed
    }
}
