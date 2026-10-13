/// The emoji keyboard's emoji, in Apple's categories and order.
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

    /// Reads `scripts/emoji.py`'s format: "# Name" starts a category, and each line is an emoji and its skin tones.
    public init(text: String) {
        var categories: [Category] = []
        var tones: [String: [String]] = [:]
        var name: String?
        var emoji: [String] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("# ") {
                if let name { categories.append(Category(name: name, emoji: emoji)) }
                name = String(line.dropFirst(2))
                emoji = []
            } else {
                let variants = line.split(separator: " ").map(String.init)
                emoji.append(variants[0])
                if variants.count > 1 { tones[variants[0]] = Array(variants.dropFirst()) }
            }
        }
        if let name { categories.append(Category(name: name, emoji: emoji)) }
        self.categories = categories
        self.tones = tones
        self.bases = Dictionary(tones.flatMap { base, toned in ([base] + toned).map { ($0, base) } }, uniquingKeysWith: { first, _ in first })
    }

    /// The untoned emoji whose skin tones include `emoji`, or `emoji` itself when it has tones.
    public func base(of emoji: String) -> String? {
        bases[emoji]
    }
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
