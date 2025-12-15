//
//  StopWords.swift
//  LifeWrapped
//
//  Created on 12/14/2025.
//

import SwiftUI

/// Comprehensive list of stopwords categorized by linguistic function
/// Single source of truth for word frequency analysis
struct StopWords {
    
    // MARK: - Articles
    static let articles: Set<String> = [
        "a", "an", "the"
    ]
    
    // MARK: - Pronouns
    static let pronouns: Set<String> = [
        // Personal pronouns
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        // Possessive pronouns
        "my", "your", "his", "her", "its", "our", "their",
        "mine", "yours", "hers", "ours", "theirs",
        // Reflexive pronouns
        "myself", "yourself", "himself", "herself", "itself",
        "ourselves", "yourselves", "themselves",
        // Demonstrative pronouns
        "this", "that", "these", "those",
        // Interrogative pronouns
        "who", "whom", "whose", "what", "which",
        // Relative pronouns
        "whoever", "whomever", "whichever", "whatever",
        // Indefinite pronouns
        "anybody", "anyone", "anything", "everybody", "everyone",
        "everything", "nobody", "none", "nothing", "somebody",
        "someone", "something", "one", "ones"
    ]
    
    // MARK: - Prepositions
    static let prepositions: Set<String> = [
        "about", "above", "across", "after", "against", "along",
        "amid", "among", "around", "as", "at",
        "before", "behind", "below", "beneath", "beside", "besides",
        "between", "beyond", "by",
        "concerning",
        "down", "during",
        "except",
        "for", "from",
        "in", "inside", "into",
        "like",
        "near",
        "of", "off", "on", "onto", "out", "outside", "over",
        "past",
        "regarding",
        "since",
        "through", "throughout", "till", "to", "toward", "towards",
        "under", "underneath", "until", "unto", "up", "upon",
        "via",
        "with", "within", "without"
    ]
    
    // MARK: - Conjunctions
    static let conjunctions: Set<String> = [
        // Coordinating conjunctions
        "and", "but", "or", "nor", "for", "yet", "so",
        // Subordinating conjunctions
        "after", "although", "as", "because", "before", "even",
        "if", "once", "since", "than", "that", "though",
        "till", "unless", "until", "when", "whenever", "where",
        "wherever", "while", "whereas"
    ]
    
    // MARK: - Common Verbs & Auxiliaries
    static let commonVerbs: Set<String> = [
        // To be
        "am", "is", "are", "was", "were", "be", "been", "being",
        // To have
        "have", "has", "had", "having",
        // To do
        "do", "does", "did", "doing", "done",
        // Modal verbs
        "can", "could", "may", "might", "must", "shall", "should",
        "will", "would", "ought",
        // Common action verbs
        "get", "got", "gotten", "getting",
        "go", "goes", "going", "gone", "went",
        "come", "comes", "coming", "came",
        "make", "makes", "making", "made",
        "take", "takes", "taking", "took", "taken",
        "see", "sees", "seeing", "saw", "seen",
        "know", "knows", "knowing", "knew", "known",
        "think", "thinks", "thinking", "thought",
        "look", "looks", "looking", "looked",
        "want", "wants", "wanting", "wanted",
        "give", "gives", "giving", "gave", "given",
        "use", "uses", "using", "used",
        "find", "finds", "finding", "found",
        "tell", "tells", "telling", "told",
        "ask", "asks", "asking", "asked",
        "work", "works", "working", "worked",
        "seem", "seems", "seeming", "seemed",
        "feel", "feels", "feeling", "felt",
        "try", "tries", "trying", "tried",
        "leave", "leaves", "leaving", "left",
        "call", "calls", "calling", "called"
    ]
    
    // MARK: - Adverbs & Intensifiers
    static let adverbs: Set<String> = [
        // Degree adverbs
        "very", "really", "quite", "rather", "pretty", "too",
        "so", "enough", "extremely", "highly", "totally",
        "completely", "absolutely", "utterly", "fairly", "slightly",
        // Time adverbs
        "now", "then", "today", "tomorrow", "yesterday",
        "soon", "later", "already", "yet", "still",
        "always", "never", "often", "sometimes", "usually",
        "frequently", "occasionally", "rarely", "seldom",
        // Place adverbs
        "here", "there", "everywhere", "nowhere", "anywhere",
        "somewhere", "away", "back", "far", "near",
        // Manner adverbs
        "well", "better", "best", "badly", "worse", "worst",
        "how", "however",
        // Other common adverbs
        "just", "only", "even", "also", "too", "either",
        "neither", "both", "all", "any", "each", "every",
        "another", "other", "such", "same", "own",
        "more", "most", "less", "least", "much", "many",
        "few", "little", "several", "some"
    ]
    
    // MARK: - Determiners & Quantifiers
    static let determiners: Set<String> = [
        "all", "another", "any", "both", "each", "either",
        "enough", "every", "few", "fewer", "less", "little",
        "many", "more", "most", "much", "neither", "no",
        "other", "several", "some", "such", "that", "these",
        "this", "those", "what", "whatever", "which", "whichever"
    ]
    
    // MARK: - Negations
    static let negations: Set<String> = [
        "no", "not", "none", "never", "neither", "nor",
        "nothing", "nobody", "nowhere"
    ]
    
    // MARK: - Contractions
    static let contractions: Set<String> = [
        // Negative contractions
        "ain't", "aren't", "can't", "cannot", "couldn't", "didn't",
        "doesn't", "don't", "hadn't", "hasn't", "haven't",
        "isn't", "mightn't", "mustn't", "needn't", "shan't",
        "shouldn't", "wasn't", "weren't", "won't", "wouldn't",
        // Pronoun + verb contractions
        "i'm", "i've", "i'll", "i'd",
        "you're", "you've", "you'll", "you'd",
        "he's", "he'll", "he'd",
        "she's", "she'll", "she'd",
        "it's", "it'll", "it'd",
        "we're", "we've", "we'll", "we'd",
        "they're", "they've", "they'll", "they'd",
        // Other contractions
        "that's", "that'll", "that'd",
        "there's", "there'll", "there'd",
        "here's", "here'll",
        "what's", "what'll", "what'd",
        "who's", "who'll", "who'd",
        "where's", "where'll", "where'd",
        "when's", "when'll", "when'd",
        "why's", "why'll", "why'd",
        "how's", "how'll", "how'd",
        "let's", "ain't"
    ]
    
    // MARK: - Fillers & Discourse Markers
    static let fillers: Set<String> = [
        // Common fillers
        "um", "uh", "er", "ah", "oh", "hmm", "huh", "mhm",
        "aha", "haha", "yeah", "yep", "yup", "nope", "nah",
        // Discourse markers
        "like", "okay", "ok", "alright", "right", "well",
        "anyway", "anyways", "basically", "actually", "literally",
        "seriously", "honestly", "frankly", "personally",
        // Informal contractions
        "gonna", "wanna", "gotta", "kinda", "sorta",
        "dunno", "lemme", "gimme", "gotcha", "betcha",
        "woulda", "coulda", "shoulda"
    ]
    
    // MARK: - Question Words
    static let questionWords: Set<String> = [
        "who", "what", "when", "where", "why", "how",
        "which", "whose", "whom"
    ]
    
    // MARK: - Conjunctive Adverbs
    static let conjunctiveAdverbs: Set<String> = [
        "however", "therefore", "thus", "hence", "moreover",
        "furthermore", "nevertheless", "nonetheless", "meanwhile",
        "otherwise", "besides", "consequently", "accordingly",
        "instead", "likewise", "similarly", "conversely"
    ]
    
    // MARK: - Combined Set (All Stopwords)
    static let all: Set<String> = {
        var combined: Set<String> = []
        combined.formUnion(articles)
        combined.formUnion(pronouns)
        combined.formUnion(prepositions)
        combined.formUnion(conjunctions)
        combined.formUnion(commonVerbs)
        combined.formUnion(adverbs)
        combined.formUnion(determiners)
        combined.formUnion(negations)
        combined.formUnion(contractions)
        combined.formUnion(fillers)
        combined.formUnion(questionWords)
        combined.formUnion(conjunctiveAdverbs)
        return combined
    }()
    
    // MARK: - Category Information for UI
    struct Category {
        let name: String
        let icon: String
        let color: Color
        let words: Set<String>
    }
    
    static let categories: [Category] = [
        Category(name: "Articles", icon: "a.circle.fill", color: .blue, words: articles),
        Category(name: "Pronouns", icon: "person.circle.fill", color: .green, words: pronouns),
        Category(name: "Prepositions", icon: "arrow.left.and.right.circle.fill", color: .orange, words: prepositions),
        Category(name: "Conjunctions", icon: "link.circle.fill", color: .purple, words: conjunctions),
        Category(name: "Common Verbs", icon: "bolt.circle.fill", color: .red, words: commonVerbs),
        Category(name: "Adverbs & Intensifiers", icon: "star.circle.fill", color: .teal, words: adverbs),
        Category(name: "Determiners", icon: "number.circle.fill", color: .cyan, words: determiners),
        Category(name: "Negations", icon: "xmark.circle.fill", color: .pink, words: negations),
        Category(name: "Contractions", icon: "ellipsis.circle.fill", color: .indigo, words: contractions),
        Category(name: "Fillers & Discourse", icon: "bubble.circle.fill", color: .mint, words: fillers),
        Category(name: "Question Words", icon: "questionmark.circle.fill", color: .yellow, words: questionWords),
        Category(name: "Conjunctive Adverbs", icon: "arrow.triangle.branch", color: .brown, words: conjunctiveAdverbs)
    ]
}
