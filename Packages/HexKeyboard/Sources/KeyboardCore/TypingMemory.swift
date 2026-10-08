public struct TypingMemory: Codable, Hashable, Sendable {
    public private(set) var counts: [String: Int] = [:]
    public private(set) var kept: Set<String> = []
    public private(set) var following: [String: [String: Int]] = [:]

    static let capacity = 20_000

    public init() {}

    public mutating func record(_ word: String, after previous: String?) {
        counts[word, default: 0] += 1
        if let previous { following[previous, default: [:]][word, default: 0] += 1 }
        if counts.count > Self.capacity { forgetRarest() }
    }

    public mutating func keep(_ word: String) {
        kept.insert(word.lowercased())
    }

    public func isKept(_ word: String) -> Bool {
        kept.contains(word.lowercased())
    }

    func completions(for prefix: String) -> [String] {
        let lower = prefix.lowercased()
        return counts
            .filter { $0.key.count > prefix.count && $0.key.lowercased().hasPrefix(lower) && ($0.value > 1 || isKept($0.key)) }
            .sorted(by: Self.frequent)
            .map(\.key)
    }

    func predictions(after previous: String) -> [String] {
        (following[previous] ?? [:]).filter { $0.value > 1 }.sorted(by: Self.frequent).map(\.key)
    }

    private mutating func forgetRarest() {
        counts = counts.filter { $0.value > 1 || isKept($0.key) }
        following = following.compactMapValues { next in
            let frequent = next.filter { $0.value > 1 }
            return frequent.isEmpty ? nil : frequent
        }
    }

    private static func frequent(_ a: (key: String, value: Int), _ b: (key: String, value: Int)) -> Bool {
        a.value != b.value ? a.value > b.value : a.key < b.key
    }
}
