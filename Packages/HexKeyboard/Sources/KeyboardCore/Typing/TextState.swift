/// The text around the caret as the keyboard knows it: what the host last reported, plus every edit the keyboard made
/// since. The host's own view (`documentContextBeforeInput`) is cut to a window and can lag the keyboard's edits, so
/// a report is compared with this, not copied into it.
public struct TextState: Hashable, Sendable {
    public enum Report: Hashable, Sendable {
        /// The host shows what the keyboard knows (or a shorter window of it).
        case current
        /// The host shows the text as it was before some of the keyboard's edits; those edits are still on their way.
        case behind
        /// Something the keyboard's edits don't explain (the caret moved, the app changed the text): the host wins.
        case changed
    }

    public private(set) var before = ""
    public private(set) var after: String?
    /// The text the host has selected between `before` and `after`, which the next edit replaces. The keyboard never
    /// selects, so only a report sets it.
    public private(set) var selected = ""
    /// How many characters at the end of `before` the keyboard typed itself: all that automatic edits may replace.
    public private(set) var owned = 0
    public private(set) var isKnown = false
    /// The field holds nothing, as after a message is sent.
    public var isEmpty: Bool { before.isEmpty && selected.isEmpty && (after ?? "").isEmpty }
    /// How long the host's view was where `before` starts. iOS cuts that view at the start of the text, of a line, or at
    /// a length; once the keyboard deletes, a view cut at a length slides back over text the keyboard never saw, but it
    /// never grows. So the host can show text in front of `before` only in a view no longer than this.
    private var reach = 0
    /// The tails of the states since the host last confirmed one, oldest first: what a late report may still show.
    private var unconfirmed: [Remembered] = []

    private struct Remembered: Hashable, Sendable {
        var tail: String
        var after: String?
        var selected: String
        var reach: Int
    }

    static let window = 64

    public init() {}

    public mutating func insert(_ text: String) {
        remember()
        selected = ""
        before += text
        owned += text.count
    }

    public mutating func deleteBackward(_ count: Int) {
        remember()
        let count = selected.isEmpty ? count : count - 1
        selected = ""
        before.removeLast(min(count, before.count))
        owned = max(owned - count, 0)
    }

    public mutating func moveCursor(by offset: Int) {
        remember()
        owned = 0
        if !selected.isEmpty {
            selected = ""
            isKnown = false
        } else if offset < 0, -offset <= before.count {
            after = String(before.suffix(-offset)) + (after ?? "")
            before.removeLast(-offset)
        } else if offset > 0, let after, offset <= after.count {
            before += after.prefix(offset)
            self.after = String(after.dropFirst(offset))
        } else {
            isKnown = false
        }
    }

    /// The same text can recur (type a letter, delete it), so a late report matches the earliest state it could be,
    /// and only the states before that one are dropped.
    @discardableResult
    public mutating func reconcile(before host: String?, after hostAfter: String?, selected hostSelected: String? = nil) -> Report {
        let host = host ?? "", hostSelected = hostSelected ?? ""
        if isKnown, !host.isEmpty, let index = unconfirmed.firstIndex(where: {
            Self.agree(host, $0.tail, reach: $0.reach) && Self.agree(after: hostAfter, $0.after) && hostSelected == $0.selected
        }) {
            unconfirmed.removeFirst(index)
            return .behind
        }
        if isKnown, hostSelected == selected, Self.agree(host, before, reach: reach), Self.agree(after: hostAfter, after) {
            if host.count > before.count {
                owned = min(owned, before.count)
                before = host
                reach = host.count
            }
            after = hostAfter
            unconfirmed = []
            return .current
        }
        before = host
        after = hostAfter
        selected = hostSelected
        owned = 0
        isKnown = true
        reach = host.count
        unconfirmed = []
        return .changed
    }

    private mutating func remember() {
        unconfirmed.append(Remembered(tail: String(before.suffix(Self.window)), after: after.map { String($0.prefix(Self.window)) }, selected: selected, reach: reach))
    }

    /// Whether the host's view can be `known`: a window of it, or more of it in a view no longer than `reach`. An
    /// empty view is an empty field (a sent message leaves one), never a late report.
    static func agree(_ host: String, _ known: String, reach: Int) -> Bool {
        guard !host.isEmpty, !known.isEmpty else { return host.isEmpty && known.isEmpty }
        let shown = host.suffix(window), mine = known.suffix(window)
        return mine.hasSuffix(shown) || (host.count <= reach && shown.hasSuffix(mine))
    }

    /// Whether the host's text after the caret can be `known`'s, either cut to a window. A caret tapped back into the
    /// text shows a before that the keyboard's own typing passed through on its way there, so only the text after the
    /// caret tells the two apart. Hosts show nothing after the caret at the end of the text, as nil or empty.
    static func agree(after host: String?, _ known: String?) -> Bool {
        let host = host ?? "", known = known ?? ""
        guard !host.isEmpty, !known.isEmpty else { return host.isEmpty && known.isEmpty }
        let shown = host.prefix(window), mine = known.prefix(window)
        return mine.hasPrefix(shown) || shown.hasPrefix(mine)
    }
}
