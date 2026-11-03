/// What you copied, as the keyboard found it on the clipboard (docs/design.md, "Clipboard"): all of it, kept until you
/// delete it. It stays on the device.
public struct ClipboardHistory: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Sendable, Identifiable {
        public enum Content: Codable, Hashable, Sendable {
            case text(String)
            /// An image, by the name of the file the store saved it under (its hash, so a copy of the same image is the same item).
            case image(String)
        }

        public var content: Content
        /// When the keyboard found it, in seconds since 1970. iOS never says which app copied something, so this is all
        /// a row can say about where it came from.
        public var found: Double
        public var pinned = false

        public var id: Content { content }
    }

    /// Pinned items first, then the rest, each newest first.
    public var items: [Item] { saved.sorted { ($0.pinned ? 1 : 0, $0.found) > ($1.pinned ? 1 : 0, $1.found) } }
    private var saved: [Item] = []

    /// The longest text kept, in UTF-8 bytes. The history lives in the keyboard's small memory and is read whenever it
    /// opens, so a copied log or document isn't kept at all rather than kept cut short.
    static let longest = 100_000

    public init() {}

    /// Keeps something just copied. Copying it again moves it up rather than repeating it.
    public mutating func keep(_ content: Item.Content, at time: Double) {
        if case .text(let text) = content, text.utf8.count > Self.longest { return }
        let pinned = saved.first { $0.content == content }?.pinned ?? false
        saved.removeAll { $0.content == content }
        saved.append(Item(content: content, found: time, pinned: pinned))
    }

    /// Takes in items kept elsewhere, each one this history doesn't have yet.
    public mutating func add(_ items: [Item]) {
        let have = Set(saved.map(\.content))
        saved += items.filter { !have.contains($0.content) }
    }

    public mutating func setPinned(_ pinned: Bool, _ content: Item.Content) {
        guard let index = saved.firstIndex(where: { $0.content == content }) else { return }
        saved[index].pinned = pinned
    }

    public mutating func remove(_ content: Item.Content) {
        saved.removeAll { $0.content == content }
    }

    /// Deletes everything but what's pinned, and says what went.
    public mutating func removeUnpinned() -> [Item.Content] {
        let gone = saved.filter { !$0.pinned }.map(\.content)
        saved.removeAll { !$0.pinned }
        return gone
    }

    /// The items whose text holds the search, ignoring case. An empty search shows everything; images match none.
    public func matching(_ search: String) -> [Item] {
        let search = search.lowercased()
        guard !search.isEmpty else { return items }
        return items.filter {
            guard case .text(let text) = $0.content else { return false }
            return text.lowercased().contains(search)
        }
    }

    /// How long ago something was found, as a row shows it: "now", "5m", "3h", "2d", "6w", "1y".
    public static func age(of found: Double, now: Double) -> String {
        let minutes = Int(max(0, now - found) / 60)
        let steps: [(Int, String)] = [(60 * 24 * 365, "y"), (60 * 24 * 7, "w"), (60 * 24, "d"), (60, "h"), (1, "m")]
        guard let (size, unit) = steps.first(where: { minutes >= $0.0 }) else { return "now" }
        return "\(minutes / size)\(unit)"
    }
}
