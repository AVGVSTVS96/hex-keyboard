/// Every emoji with the words that find it, for the suggestion bar.
public struct EmojiCatalog: Sendable {
    /// Every emoji with words, most used first, and the words of its name and keywords.
    private let entries: [(emoji: String, words: [String])]
    private let byWord: [String: [Int]]

    /// Reads `scripts/emoji.py`'s format: "# Name" starts a category, and each line is an emoji and its skin tones,
    /// then a tab, its rank by use and a tab, its name and keywords separated by "|".
    public init(text: String) {
        var ranked: [(rank: Int, emoji: String, words: [String])] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("# ") {
            let fields = line.split(separator: "\t")
            let emoji = String(fields[0].prefix { $0 != " " })
            if fields.count == 3, let rank = Int(fields[1]) {
                var words: [String] = []
                for word in fields[2].split(whereSeparator: { $0 == "|" || $0 == " " || $0 == "-" || $0 == ":" || $0 == "," }) where !words.contains(String(word)) {
                    words.append(String(word))
                }
                ranked.append((rank, emoji, words))
            }
        }
        entries = ranked.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map { ($0.element.emoji, $0.element.words) }
        var byWord: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for word in entry.words { byWord[word, default: []].append(index) }
        }
        self.byWord = byWord
    }

    /// The emoji for a word typed in the text, for the suggestion bar: the word, or its singular, is a word of their
    /// name or keywords. Words that only hold a sentence together ("you", "not") find none.
    public func suggestions(for word: String, history: EmojiHistory, limit: Int = 3) -> [String] {
        let word = word.lowercased()
        guard word.count > 1, !Self.functionWords.contains(word) else { return [] }
        let forms = [word] + (word.hasSuffix("es") ? [String(word.dropLast(2))] : []) + (word.hasSuffix("s") ? [String(word.dropLast())] : [])
        let found = Set(forms.flatMap { byWord[$0] ?? [] }).sorted()
        return Array(ranked(found, history: history).prefix(limit))
    }

    /// Emoji you've used first, most used first, then everyone's order.
    private func ranked(_ indices: [Int], history: EmojiHistory) -> [String] {
        let shown = indices.map { entries[$0].emoji }
        let used = shown.compactMap { emoji in history.scores[emoji].map { (emoji, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return used + shown.filter { history.scores[$0] == nil }
    }

    static let functionWords: Set<String> = [
        "i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself", "he", "him", "his", "she", "her", "hers",
        "it", "its", "we", "us", "our", "ours", "they", "them", "their", "theirs", "this", "that", "these", "those",
        "a", "an", "the", "and", "or", "but", "nor", "if", "so", "as", "at", "by", "for", "from", "in", "into", "of",
        "off", "on", "onto", "out", "over", "to", "up", "down", "with", "without", "about", "after", "before", "under",
        "than", "then", "there", "here", "not", "no", "do", "does", "did", "be", "is", "am", "are", "was", "were",
        "been", "being", "have", "has", "had", "can", "could", "will", "would", "shall", "should", "may", "might",
        "must", "what", "which", "who", "whom", "whose", "when", "where", "why", "how", "all", "any", "some", "each",
        "every", "both", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "just", "too",
        "very", "also", "only", "own", "same", "such", "other", "more", "most", "much", "many", "few",
    ]
}

/// The emoji you pick from the bar, which it offers first from then on. Each use counts for more than the ones before
/// it, so a new favorite climbs within a few uses while an old one fades only as you use others, never on a clock.
public struct EmojiHistory: Codable, Hashable, Sendable {
    public private(set) var scores: [String: Double] = [:]
    private var weight = 1.0

    static let growth = 1.1
    static let capacity = 60

    public init() {}

    public mutating func use(_ emoji: String) {
        scores[emoji, default: 0] += weight
        weight *= Self.growth
        if weight > 1e12 {
            scores = scores.mapValues { $0 / weight }
            weight = 1
        }
        if scores.count > Self.capacity, let least = scores.min(by: { $0.value < $1.value })?.key { scores[least] = nil }
    }
}
