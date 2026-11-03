/// The emoji each word finds, for the suggestion bar.
public struct EmojiCatalog: Sendable {
    private let byWord: [String: [String]]
    /// Where the rest of a word's emoji come from, after the ones picked for it.
    private let search: EmojiSearch?

    /// Reads the index (`emoji.txt`): each line is a word, a tab, and the emoji it finds, best first, or none.
    public init(text: String, search: EmojiSearch? = nil) {
        self.search = search
        var byWord: [String: [String]] = [:]
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            byWord[String(line[..<tab])] = line[line.index(after: tab)...].split(separator: " ").map(String.init)
        }
        self.byWord = byWord
    }

    /// The emoji for a word typed in the text, for the suggestion bar: what the word finds, or else what its singular
    /// finds, then every emoji the search names with that word. A word the index gives no emoji ("with", "heard") finds
    /// none, even when its singular or the search would.
    public func suggestions(for word: String, history: EmojiHistory, limit: Int = 3) -> [String] {
        let word = word.lowercased()
        guard word.count > 1 else { return [] }
        var forms = [word]
        if word.hasSuffix("s"), !word.hasSuffix("ss") {
            forms.append(String(word.dropLast()))
            let stem = word.dropLast(2)
            if word.hasSuffix("es"), ["s", "x", "z", "ch", "sh", "o"].contains(where: stem.hasSuffix) { forms.append(String(stem)) }
        }
        let found = forms.lazy.compactMap { byWord[$0] }.first ?? []
        guard !found.isEmpty else { return [] }
        let picked = ranked(found.map { search?.toned($0, history: history) ?? $0 }, history: history)
        let named = search?.named(word, history: history).filter { !picked.contains($0) } ?? []
        return Array((picked + named).prefix(limit))
    }

    /// Emoji you've used first, most used first, then everyone's order.
    private func ranked(_ shown: [String], history: EmojiHistory) -> [String] {
        let used = shown.compactMap { emoji in history.scores[emoji].map { (emoji, $0) } }.sorted { $0.1 > $1.1 }.map(\.0)
        return used + shown.filter { history.scores[$0] == nil }
    }
}

/// Every emoji in Apple's order, with the words that find it, for the emoji panel's grid and search.
public struct EmojiSearch: Sendable {
    /// Every emoji, Smileys & People first, as Apple's emoji keyboard orders them.
    public let all: [String]
    /// Each emoji that comes in skin tones, mapped to its five toned versions.
    public let tones: [String: [String]]
    private let bases: [String: String]
    /// Every emoji, most used by everyone first, and the words of its name and keywords.
    private let entries: [(emoji: String, words: [String])]

    /// Reads `scripts/emoji-search.py`'s format: "# Name" starts a category, and each line is an emoji and its skin
    /// tones, then a tab, its rank by use and a tab, its name and keywords separated by "|".
    public init(text: String) {
        var all: [String] = []
        var tones: [String: [String]] = [:]
        var ranked: [(rank: Int, emoji: String, words: [String])] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("# ") {
            let fields = line.split(separator: "\t")
            let variants = fields[0].split(separator: " ").map(String.init)
            let emoji = variants[0]
            all.append(emoji)
            if variants.count > 1 { tones[emoji] = Array(variants.dropFirst()) }
            guard fields.count == 3, let rank = Int(fields[1]) else { continue }
            var words: [String] = []
            for word in fields[2].split(whereSeparator: { $0 == "|" || $0 == " " || $0 == "-" || $0 == ":" || $0 == "," }) where !words.contains(String(word)) {
                words.append(String(word))
            }
            ranked.append((rank, emoji, words))
        }
        self.all = all
        self.tones = tones
        bases = Dictionary(tones.flatMap { base, toned in ([base] + toned).map { ($0, base) } }, uniquingKeysWith: { first, _ in first })
        entries = ranked.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map { ($0.element.emoji, $0.element.words) }
    }

    /// The untoned emoji whose skin tones include `emoji`, or `emoji` itself when it has tones.
    public func base(of emoji: String) -> String? {
        bases[emoji]
    }

    /// The emoji whose name or keywords hold `word` whole, the ones you pick first.
    public func named(_ word: String, history: EmojiHistory) -> [String] {
        let term = word.lowercased()
        return ranked(entries.filter { $0.words.contains { Self.isWhole(term, $0) } }.map(\.emoji), history: history)
    }

    /// `emoji` in the tone last picked for it, else in your preferred tone, else as it is.
    public func toned(_ emoji: String, history: EmojiHistory) -> String {
        if let picked = history.tones[emoji] { return picked }
        guard let tone = history.skinTone, let toned = tones[emoji], let index = SkinTone.allCases.firstIndex(of: tone), toned.indices.contains(index) else { return emoji }
        return toned[index]
    }

    private func ranked(_ tier: [String], history: EmojiHistory) -> [String] {
        let tier = tier.map { toned($0, history: history) }
        let used = tier.filter { history.scores[$0] != nil }.sorted { history.scores[$0]! > history.scores[$1]! }
        return used + tier.filter { history.scores[$0] == nil }
    }

    /// What the panel shows for `query`: each word of it must start a word of the emoji's name or keywords. Emoji that
    /// match every word whole come first, and within each, the ones you pick, then the ones everyone uses most. An
    /// empty query shows what you pick most, then every emoji.
    public func search(_ query: String, history: EmojiHistory) -> [String] {
        let terms = query.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        guard !terms.isEmpty else {
            let frequent = history.frequent.map { toned($0, history: history) }
            return frequent + all.map { toned($0, history: history) }.filter { !frequent.contains($0) }
        }
        var tiers: [[String]] = [[], []]
        for entry in entries {
            var prefixOnly = false
            let matches = terms.allSatisfy { term in
                if entry.words.contains(where: { Self.isWhole(term, $0) }) { return true }
                prefixOnly = true
                return entry.words.contains { $0.hasPrefix(term) }
            }
            if matches { tiers[prefixOnly ? 1 : 0].append(entry.emoji) }
        }
        return tiers.flatMap { ranked($0, history: history) }
    }

    private static func isWhole(_ term: String, _ word: String) -> Bool {
        word == term || word == term + "s" || word == term + "es" || term == word + "s"
    }
}

/// The emoji you pick from the bar or the panel, which both offer first from then on. Each use counts for more than the ones before
/// it, so a new favorite climbs within a few uses while an old one fades only as you use others, never on a clock.
public struct EmojiHistory: Codable, Hashable, Sendable {
    public private(set) var scores: [String: Double] = [:]
    /// The skin tone last picked for each emoji that has them, which the panel shows from then on.
    public private(set) var tones: [String: String] = [:]
    /// The tone emoji take until you pick another for one (Settings › Keys), not kept with the history.
    public var skinTone: SkinTone?
    private var weight = 1.0

    static let growth = 1.1
    static let capacity = 60

    static let shown = 30
    /// Common picks, for a keyboard that hasn't seen you pick an emoji yet.
    static let starters = ["❤️", "😂", "👍", "😭", "🙏", "😘", "🥰", "😍", "😊", "🎉", "😁", "💕", "🥺", "😅", "🔥", "☺️", "🤦", "♥️", "🤷", "🙄", "😆", "🤗", "😉", "🎂", "🤔", "👏", "🙂", "😳", "🥳", "😎"]

    public init() {}

    /// What you pick most, filled out with everyone's common picks.
    public var frequent: [String] {
        let used = scores.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let starters = Self.starters.map { tones[$0] ?? $0 }.filter { scores[$0] == nil }
        return Array((used + starters).prefix(Self.shown))
    }

    /// `base` is the emoji's untoned version, when `emoji` was picked among its skin tones.
    public mutating func use(_ emoji: String, base: String? = nil) {
        if let base { tones[base] = emoji }
        scores[emoji, default: 0] += weight
        weight *= Self.growth
        if weight > 1e12 {
            scores = scores.mapValues { $0 / weight }
            weight = 1
        }
        if scores.count > Self.capacity, let least = scores.min(by: { $0.value < $1.value })?.key { scores[least] = nil }
    }
}

extension EmojiHistory {
    private enum CodingKeys: String, CodingKey { case scores, tones, weight }

    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scores = try container.decode([String: Double].self, forKey: .scores)
        tones = try container.decodeIfPresent([String: String].self, forKey: .tones) ?? [:]
        weight = try container.decode(Double.self, forKey: .weight)
    }
}
