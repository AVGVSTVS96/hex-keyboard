/// What you copied, as the keyboard found it on the clipboard (docs/design.md, "Clipboard"): the newest 50 and whatever
/// you pinned. It stays on the device.
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

    static let capacity = 50

    public init() {}

    /// Keeps something just copied. Copying it again moves it up rather than repeating it. Returns what aged out, so
    /// the store can delete its files.
    @discardableResult
    public mutating func keep(_ content: Item.Content, at time: Double) -> [Item.Content] {
        let pinned = saved.first { $0.content == content }?.pinned ?? false
        saved.removeAll { $0.content == content }
        saved.append(Item(content: content, found: time, pinned: pinned))
        let dropped = items.filter { !$0.pinned }.dropFirst(Self.capacity).map(\.content)
        saved.removeAll { dropped.contains($0.content) }
        return dropped
    }

    public mutating func setPinned(_ pinned: Bool, _ content: Item.Content) {
        guard let index = saved.firstIndex(where: { $0.content == content }) else { return }
        saved[index].pinned = pinned
    }

    public mutating func remove(_ content: Item.Content) {
        saved.removeAll { $0.content == content }
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
