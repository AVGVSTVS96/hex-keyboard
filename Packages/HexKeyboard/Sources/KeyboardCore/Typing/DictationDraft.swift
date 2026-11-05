/// The dictations typed into a field, followed through every edit until the field is sent or left, so what each became
/// can be kept beside what the model wrote. A keyboard sees only a window of the field around the caret, so the draft
/// keeps all of the field it has seen: the keyboard's own edits land on it exactly, and each window the host shows
/// that they don't explain (the caret moved, a paste, a cut) is placed on it where it agrees, its difference taken as
/// one edit.
public struct DictationDraft: Sendable {
    /// What one dictation became.
    public struct Outcome: Hashable, Codable, Sendable {
        public var id: String
        /// What the keyboard typed for it.
        public var typed: String
        /// What it is in the field now: what was typed, with every edit inside it, and typing that runs on from either end.
        public var final: String
        /// The field was emptied after it, as sending a message does; false when the keyboard went away first.
        public var sent: Bool
    }

    private struct Passage: Sendable {
        var id: String
        var typed: String
        var range: Range<Int>
    }

    private var text: [Character]
    private var passages: [Passage] = []
    /// The caret, or the selection, in `text`; nil while the keyboard can't tell where it is.
    private var caret: Range<Int>?
    /// The most the host has shown on either side of the caret. iOS cuts its view at the start of the text, of a line,
    /// or at a length, so a side shorter than this was cut at the field's or a line's end, not at the length.
    private var reach: Int

    /// The keyboard can't tell where the caret is in the draft, so its edits aren't followed until a window is placed.
    public var isLost: Bool { caret == nil }

    /// How many characters of a window must agree with the draft to place it there.
    static let anchor = 12

    public init(_ state: TextState) {
        let before = Array(state.before), selected = Array(state.selected)
        text = before + selected + Array(state.after ?? "")
        caret = before.count..<before.count + selected.count
        reach = max(before.count, state.after?.count ?? 0)
    }

    /// Follows the dictation the keyboard just typed, which ends at the caret.
    public mutating func add(_ id: String, typed: String) {
        guard let caret, caret.isEmpty, caret.lowerBound >= typed.count else { return }
        let range = caret.lowerBound - typed.count..<caret.lowerBound
        guard String(text[range]) == typed else { return }
        for index in passages.indices where passages[index].range.overlaps(range) {
            passages[index].range = min(passages[index].range.lowerBound, range.lowerBound)..<range.lowerBound
        }
        passages.append(Passage(id: id, typed: typed, range: range))
        passages.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    public mutating func insert(_ string: String) {
        guard let caret else { return }
        let inserted = Array(string)
        replace(caret, with: inserted)
        self.caret = caret.lowerBound + inserted.count..<caret.lowerBound + inserted.count
    }

    /// As `TextState.deleteBackward`: a selection goes with the first delete.
    public mutating func deleteBackward(_ count: Int) {
        guard let caret else { return }
        let start = max(caret.lowerBound - (caret.isEmpty ? count : count - 1), 0)
        replace(start..<caret.upperBound, with: [])
        self.caret = start..<start
    }

    public mutating func moveCursor(by offset: Int) {
        guard let caret, caret.isEmpty, (0...text.count).contains(caret.lowerBound + offset) else { return caret = nil }
        self.caret = caret.lowerBound + offset..<caret.lowerBound + offset
    }

    /// What every dictation in the field became.
    public func outcomes(sent: Bool) -> [Outcome] {
        passages.map { Outcome(id: $0.id, typed: $0.typed, final: String(text[$0.range]), sent: sent) }
    }

    /// The host's window of the field, as it is now, taken as the smallest edit of the draft that explains it: the
    /// window's start agrees with the draft at one place and its end at another, and what lies between them is what
    /// changed. A caret moved changes nothing; a paste or a cut changes what's at the caret. Text the window shows past
    /// either end of the draft is added to it. A window that agrees nowhere, as in another part of a long document,
    /// loses the caret until one does.
    public mutating func place(before: String, selected: String, after: String) {
        let window = Array(before) + Array(selected) + Array(after)
        let shown = before.count..<before.count + selected.count
        reach = max(reach, before.count, after.count)
        let (lefts, rights) = agreements(of: window, around: shown, whole: (before.count < reach, after.count < reach))
        var best: (rank: [Int], left: Int, right: Int, span: Int, end: Int)?
        for left in lefts {
            for right in rights {
                let span = max(0, right.reach - left.reach, left.offset - right.offset)
                let (first, last) = (max(right.reach, span), min(left.reach + span, window.count))
                guard first <= last else { continue }
                let cost = 2 * span - (left.offset - right.offset) + max(0, -left.offset) + max(0, right.offset + window.count - text.count)
                let rank = [left.cuts + right.cuts, cost, left.overruns + right.overruns, left.distance + right.distance]
                guard best.map({ rank.lexicographicallyPrecedes($0.rank) }) ?? true else { continue }
                best = (rank, left.offset, right.offset, span, min(max(shown.lowerBound, first), last))
            }
        }
        guard let best else { return caret = nil }
        let lead = max(0, -best.left)
        prepend(window[..<lead])
        let (left, right) = (best.left + lead, best.right + lead)
        if right + window.count > text.count { text += window[(text.count - right)...] }
        replace(left + best.end - best.span..<right + best.end, with: window[best.end - best.span..<best.end])
        caret = left + shown.lowerBound..<left + shown.upperBound
    }

    /// Where one end of the window agrees with the draft: the window's offset in it, and how far into the window the
    /// agreement reaches from that end.
    private struct Side {
        var offset: Int
        var reach: Int
        /// It puts that end of the window inside the draft, where the host would have cut the window short of the field's
        /// or a line's end though that side of it is shorter than the most the host shows.
        var cuts: Int
        /// It runs past the draft's end rather than holding to the window's.
        var overruns: Int
        /// How far it is from where the caret puts it.
        var distance: Int
    }

    /// Where the window's start agrees with the draft, and where its end does. Candidates are where short runs of the
    /// window are found in the draft, where the caret puts it, and where the window starts or ends with the draft. One
    /// shorter than `anchor` counts only at one of the last three, holding all of the draft on its side of the caret
    /// that the window shows, as after a paste or a cut there.
    private func agreements(of window: [Character], around shown: Range<Int>, whole: (left: Bool, right: Bool)) -> (left: [Side], right: [Side]) {
        let expected = caret.map { (left: $0.lowerBound - shown.lowerBound, right: $0.upperBound - shown.upperBound) }
        var offsets = Set([expected?.left, expected?.right, 0, text.count - window.count].compactMap(\.self))
        let k = min(Self.anchor, window.count)
        if k > 0, text.count >= k {
            for i in Set([0, shown.lowerBound - k, shown.lowerBound, shown.upperBound - k, shown.upperBound, window.count - k].map { min(max($0, 0), window.count - k) }) {
                let run = window[i..<i + k]
                for position in 0...(text.count - k) where text[position] == run.first && text[position..<position + k].elementsEqual(run) {
                    offsets.insert(position - i)
                }
            }
        }
        var left: [Side] = [], right: [Side] = []
        for offset in offsets {
            let low = max(0, -offset), high = min(window.count, text.count - offset)
            guard low <= high else { continue }
            var end = low
            while end < high, window[end] == text[offset + end] { end += 1 }
            var start = high
            while start > low, window[start - 1] == text[offset + start - 1] { start -= 1 }
            if end - low >= k || low == 0 && [expected?.left, 0].contains(offset) && caret.map({ (offset...offset + end).contains($0.lowerBound) }) == true {
                let cuts = whole.left && offset > 0 && text[offset - 1] != "\n"
                left.append(Side(offset: offset, reach: end, cuts: cuts ? 1 : 0, overruns: low == 0 ? 0 : 1, distance: expected.map { abs($0.left - offset) } ?? 0))
            }
            if high - start >= k || high == window.count && [expected?.right, text.count - window.count].contains(offset) && caret.map({ (offset + start...offset + high).contains($0.upperBound) }) == true {
                let cuts = whole.right && offset + window.count < text.count && text[offset + window.count] != "\n"
                right.append(Side(offset: offset, reach: start, cuts: cuts ? 1 : 0, overruns: high == window.count ? 0 : 1, distance: expected.map { abs($0.right - offset) } ?? 0))
            }
        }
        return (left, right)
    }

    /// Replaces `range` of the draft, as an edit inside a dictation, or at either end of one, changes it.
    private mutating func replace(_ range: Range<Int>, with new: some Collection<Character>) {
        let (a, b, n) = (range.lowerBound, range.upperBound, new.count)
        let delta = n - (b - a)
        text.replaceSubrange(range, with: new)
        for index in passages.indices {
            let (s, e) = (passages[index].range.lowerBound, passages[index].range.upperBound)
            let start = s <= a ? s : s >= b ? s + delta : a
            let end = e < a || e == a && a < b ? e : e >= b ? e + delta : a + n
            passages[index].range = start..<max(start, end)
        }
        for index in passages.indices.dropFirst() {
            let floor = passages[index - 1].range.upperBound
            let range = passages[index].range
            passages[index].range = max(range.lowerBound, floor)..<max(range.upperBound, floor)
        }
    }

    /// Text the window shows before what the draft has seen, which no dictation takes.
    private mutating func prepend(_ lead: some Collection<Character>) {
        guard !lead.isEmpty else { return }
        text.insert(contentsOf: lead, at: 0)
        for index in passages.indices {
            passages[index].range = passages[index].range.lowerBound + lead.count..<passages[index].range.upperBound + lead.count
        }
        caret = caret.map { $0.lowerBound + lead.count..<$0.upperBound + lead.count }
    }
}
