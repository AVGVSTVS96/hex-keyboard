/// What iikb has learned about you: the words you keep, what follows what, and where your thumbs land.
public struct TypingMemory: Codable, Hashable, Sendable {
    public private(set) var counts: [String: Int] = [:]
    public private(set) var kept: Set<String> = []
    public private(set) var following: [String: [String: Int]] = [:]
    public private(set) var total = 0
    public private(set) var spacesAfterSpace = 0
    public private(set) var keysAfterSpace = 0
    public var touches = TouchModel()
    public var apps: [String: AppWords]?

    static let capacity = 20_000

    public init() {}

    /// Counts a word after the word before it and, when `earlier` is known, after the two before it.
    public mutating func record(_ word: String, after previous: String?, earlier: String? = nil) {
        let word = Words.plain(word), previous = previous.map(Words.plain)
        counts[word, default: 0] += 1
        total += 1
        for context in Self.contexts(previous, earlier) { following[context, default: [:]][word, default: 0] += 1 }
        if counts.count > Self.capacity { forgetRarest(keeping: word) }
    }

    public mutating func forget(_ word: String, after previous: String?, earlier: String? = nil) {
        let word = Words.plain(word), previous = previous.map(Words.plain)
        guard let count = counts[word] else { return }
        counts[word] = count > 1 ? count - 1 : nil
        total -= 1
        for context in Self.contexts(previous, earlier) {
            if let next = following[context]?[word] { following[context]?[word] = next > 1 ? next - 1 : nil }
        }
    }

    /// The keys `following` counts a word under: the word before it, and the two before it joined by a space, which no
    /// word contains.
    static func contexts(_ previous: String?, _ earlier: String?) -> [String] {
        guard let previous else { return [] }
        guard let earlier, !previous.isEmpty else { return [previous] }
        return [previous, Words.plain(earlier) + " " + previous]
    }

    /// Counts what you type right after a space, so a second space (the "." shortcut) is as likely as you make it.
    public mutating func recordAfterSpace(isSpace: Bool) {
        keysAfterSpace += 1
        if isSpace { spacesAfterSpace += 1 }
    }

    mutating func unrecordSpaceAfterSpace(keepingKey: Bool) {
        spacesAfterSpace -= 1
        if !keepingKey { keysAfterSpace -= 1 }
    }

    public mutating func keep(_ word: String) {
        kept.insert(Words.plain(word).lowercased())
    }

    public func isKept(_ word: String) -> Bool {
        kept.contains(Words.plain(word).lowercased())
    }

    func count(of word: String) -> Int {
        counts[word, default: 0] + (word.first?.isLowercase == true ? counts[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0)
    }

    func count(of word: String, after previous: String) -> (count: Int, total: Int, types: Int) {
        guard let next = following[previous] else { return (0, 0, 0) }
        let capitalized = word.first?.isLowercase == true ? next[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0
        return (next[word, default: 0] + capitalized, next.values.reduce(0, +), next.count)
    }

    func completions(for prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return counts
            .filter { $0.key.count > prefix.count && $0.key.lowercased().hasPrefix(lower) && ($0.value > 1 || isKept($0.key)) }
            .sorted(by: Self.frequent)
            .map(\.key)
    }

    var familiar: some Sequence<String> {
        counts.lazy.filter { $0.value > 1 || self.isKept($0.key) }.map(\.key)
    }

    func predictions(after previous: String) -> [String] {
        (following[previous] ?? [:]).filter { $0.value > 1 }.sorted(by: Self.frequent).map(\.key)
    }

    /// Drops the rarest words, and the next-word counts that name them, until the words are back at `capacity`. Kept words
    /// and the word just typed stay.
    private mutating func forgetRarest(keeping word: String) {
        let kept = kept
        var gone: Set<String> = []
        while counts.count - gone.count > Self.capacity,
              let rarest = counts.lazy.filter({ !gone.contains($0.key) && $0.key != word && !kept.contains(Words.plain($0.key).lowercased()) }).min(by: Self.rarer) {
            gone.insert(rarest.key)
        }
        guard !gone.isEmpty else { return }
        for word in gone { counts[word] = nil }
        total = counts.values.reduce(0, +)
        following = following.reduce(into: [:]) { result, entry in
            guard entry.key.split(separator: " ").allSatisfy({ !gone.contains(String($0)) }) else { return }
            let next = entry.value.filter { !gone.contains($0.key) }
            if !next.isEmpty { result[entry.key] = next }
        }
    }

    private static func rarer(_ a: (key: String, value: Int), _ b: (key: String, value: Int)) -> Bool {
        a.value != b.value ? a.value < b.value : a.key > b.key
    }

    private static func frequent(_ a: (key: String, value: Int), _ b: (key: String, value: Int)) -> Bool {
        a.value != b.value ? a.value > b.value : a.key < b.key
    }
}
