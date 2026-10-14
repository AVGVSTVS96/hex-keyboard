/// The emoji keyboard's emoji, in Apple's categories and order, with the words that find each one.
public struct EmojiCatalog: Sendable {
    public struct Category: Sendable {
        public let name: String
        public let emoji: [String]

        public init(name: String, emoji: [String]) {
            self.name = name
            self.emoji = emoji
        }
    }

    public let categories: [Category]
    /// Each emoji that comes in skin tones, mapped to its five toned versions.
    public let tones: [String: [String]]
    private let bases: [String: String]
    /// Every emoji with words, most used first, and the words of its name and keywords.
    private let entries: [(emoji: String, words: [String])]
    private let byWord: [String: [Int]]

    /// Reads `scripts/emoji.py`'s format: "# Name" starts a category, and each line is an emoji and its skin tones,
    /// then a tab, its rank by use and a tab, its name and keywords separated by "|".
    public init(text: String) {
        var categories: [Category] = []
        var tones: [String: [String]] = [:]
        var ranked: [(rank: Int, emoji: String, words: [String])] = []
        var name: String?
        var emoji: [String] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("# ") {
                if let name { categories.append(Category(name: name, emoji: emoji)) }
                name = String(line.dropFirst(2))
                emoji = []
                continue
            }
            let fields = line.split(separator: "\t")
            let variants = fields[0].split(separator: " ").map(String.init)
            emoji.append(variants[0])
            if variants.count > 1 { tones[variants[0]] = Array(variants.dropFirst()) }
            if fields.count == 3, let rank = Int(fields[1]) {
                var words: [String] = []
                for word in fields[2].split(whereSeparator: { $0 == "|" || $0 == " " || $0 == "-" || $0 == ":" || $0 == "," }) where !words.contains(String(word)) {
                    words.append(String(word))
                }
                ranked.append((rank, variants[0], words))
            }
        }
        if let name { categories.append(Category(name: name, emoji: emoji)) }
        self.categories = categories
        self.tones = tones
        self.bases = Dictionary(tones.flatMap { base, toned in ([base] + toned).map { ($0, base) } }, uniquingKeysWith: { first, _ in first })
        entries = ranked.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map { ($0.element.emoji, $0.element.words) }
        var byWord: [String: [Int]] = [:]
        for (index, entry) in entries.enumerated() {
            for word in entry.words { byWord[word, default: []].append(index) }
        }
        self.byWord = byWord
    }

    /// The untoned emoji whose skin tones include `emoji`, or `emoji` itself when it has tones.
    public func base(of emoji: String) -> String? {
        bases[emoji]
    }

    /// The emoji search's results: each word of `query` must start a word of the emoji's name or keywords. Emoji that
    /// match every word whole come first, and within that, the ones you use, then the ones everyone uses most.
    public func search(_ query: String, history: EmojiHistory) -> [String] {
        let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard !terms.isEmpty else { return [] }
        var tiers: [[Int]] = [[], []]
        for (index, entry) in entries.enumerated() {
            var prefixOnly = false
            let matches = terms.allSatisfy { term in
                if entry.words.contains(where: { Self.isWhole(term, $0) }) { return true }
                prefixOnly = true
                return entry.words.contains { $0.hasPrefix(term) }
            }
            if matches { tiers[prefixOnly ? 1 : 0].append(index) }
        }
        return tiers.flatMap { ranked($0, history: history) }
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

    /// Emoji you've used first, most used first, then everyone's order; each in the skin tone you picked.
    private func ranked(_ indices: [Int], history: EmojiHistory) -> [String] {
        let shown = indices.map { history.tones[entries[$0].emoji] ?? entries[$0].emoji }
        let used = shown.compactMap { emoji in history.scores[emoji].map { (emoji, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return used + shown.filter { history.scores[$0] == nil }
    }

    private static func isWhole(_ term: String, _ word: String) -> Bool {
        word == term || word == term + "s" || word == term + "es" || term == word + "s"
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

/// The emoji you reach for, for the emoji keyboard's Frequently Used. Each use counts for more than the ones before
/// it, so a new favorite climbs within a few uses while an old one fades only as you use others, never on a clock.
public struct EmojiHistory: Codable, Hashable, Sendable {
    public private(set) var scores: [String: Double] = [:]
    /// The skin tone last picked for each emoji that has them, which its key shows from then on.
    public private(set) var tones: [String: String] = [:]
    private var weight = 1.0

    static let growth = 1.1
    static let capacity = 60
    public static let shown = 30
    /// Common picks, for a keyboard that hasn't seen you type an emoji yet.
    public static let starters = ["❤️", "😂", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥", "☺️", "🤦", "♥️", "🤷", "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎"]

    public init() {}

    /// `base` is the emoji's untoned key, when `emoji` was picked among its skin tones.
    public mutating func use(_ emoji: String, base: String? = nil) {
        if let base { tones[base] = emoji == base ? nil : emoji }
        scores[emoji, default: 0] += weight
        weight *= Self.growth
        if weight > 1e12 {
            scores = scores.mapValues { $0 / weight }
            weight = 1
        }
        if scores.count > Self.capacity, let least = scores.min(by: { $0.value < $1.value })?.key { scores[least] = nil }
    }

    /// Most used first, filled out with Apple's starters.
    public var frequent: [String] {
        let used = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let starters = Self.starters.filter { scores[$0] == nil }
        return Array((used + starters).prefix(Self.shown))
    }
}
