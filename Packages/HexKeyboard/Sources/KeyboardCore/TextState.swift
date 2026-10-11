/// The text around the caret as the keyboard knows it: what the host last reported, plus every edit the keyboard made
/// since. The engine reads only this. The host's own view (`documentContextBeforeInput`) is cut to a window and can
/// arrive late, showing text from before the keyboard's latest edits, so a report is compared against what the
/// keyboard knows instead of replacing it.
public struct TextState: Hashable, Sendable {
    public enum Report: Hashable, Sendable {
        /// The host shows what the keyboard knows (or a shorter window of it).
        case current
        /// The host shows the text as it was before some of the keyboard's edits; those edits are still on their way.
        case behind
        /// The text changed in a way the keyboard's edits don't explain (the caret moved, the app changed the text):
        /// the host's view becomes the truth.
        case changed
    }

    public private(set) var before = ""
    public private(set) var after: String?
    /// How many characters at the end of `before` the keyboard typed itself. Automatic edits (autocorrect, joins, the
    /// "." shortcut) only ever replace these, so a wrong report can never make them delete someone else's text.
    public private(set) var owned = 0
    public private(set) var isKnown = false
    /// Whether `before` reaches back to the start of the document, so the host can't show more of it. True once the
    /// host has shown an empty context: the caret at the start of a field.
    private var isWhole = false
    /// The tails of the states since the host last confirmed one, oldest first: what a late report may still show.
    private var unconfirmed: [Remembered] = []

    private struct Remembered: Hashable, Sendable {
        var tail: String
        var isWhole: Bool
    }

    static let window = 64

    public init() {}

    public mutating func insert(_ text: String) {
        remember()
        before += text
        owned += text.count
    }

    public mutating func deleteBackward(_ count: Int) {
        remember()
        before.removeLast(min(count, before.count))
        owned = max(owned - count, 0)
    }

    public mutating func moveCursor(by offset: Int) {
        remember()
        owned = 0
        if offset < 0, -offset <= before.count {
            after = String(before.suffix(-offset)) + (after ?? "")
            before.removeLast(-offset)
        } else if offset > 0, let after, offset <= after.count {
            before += after.prefix(offset)
            self.after = String(after.dropFirst(offset))
        } else {
            isKnown = false
        }
    }

    /// Compares what the host shows now with what the keyboard knows. The same text can recur (type a letter, delete
    /// it), so a report is matched to the earliest state it could be, and only the states before that are dropped: the
    /// host can still show any later one.
    @discardableResult
    public mutating func reconcile(before host: String?, after hostAfter: String?) -> Report {
        let host = host ?? ""
        if isKnown, !host.isEmpty, let index = unconfirmed.firstIndex(where: { Self.agree(host, $0.tail, isWhole: $0.isWhole) }) {
            unconfirmed.removeFirst(index)
            return .behind
        }
        if isKnown, Self.agree(host, before, isWhole: isWhole) {
            if host.count > before.count {
                owned = min(owned, before.count)
                before = host
            }
            after = hostAfter
            unconfirmed = []
            return .current
        }
        before = host
        after = hostAfter
        owned = 0
        isKnown = true
        isWhole = host.isEmpty
        unconfirmed = []
        return .changed
    }

    private mutating func remember() {
        unconfirmed.append(Remembered(tail: String(before.suffix(Self.window)), isWhole: isWhole))
    }

    /// Whether the host's view of the text before the caret can be `known`, compared over the last `window`
    /// characters: the host shows a window of it, or, when `known` doesn't reach the start of the document, more of
    /// it. An empty view means the caret is at the start of a field (a sent message leaves one), so it is never read
    /// as a late report of a field that has text now.
    static func agree(_ host: String, _ known: String, isWhole: Bool) -> Bool {
        guard !host.isEmpty, !known.isEmpty else { return host.isEmpty && known.isEmpty }
        let shown = host.suffix(window), mine = known.suffix(window)
        return mine.hasSuffix(shown) || (!isWhole && shown.hasSuffix(mine))
    }
}
