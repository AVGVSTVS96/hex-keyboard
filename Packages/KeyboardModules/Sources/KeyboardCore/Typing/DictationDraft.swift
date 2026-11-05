/// The dictations typed into a field, followed through every edit until the field is sent or left, so what each became
/// can be kept beside what the model wrote. A keyboard sees only a window of the field around the caret, so the draft
/// keeps all of the field it has seen: the keyboard's own edits land on it exactly, and each window the host shows
/// that they don't explain (the caret moved, a paste, a cut) is placed on it as the smallest edit that explains it.
/// It's `Codable`, so the next keyboard in the same field goes on following it.
public struct DictationDraft: Codable, Sendable {
    /// What one dictation became.
    public struct Outcome: Hashable, Codable, Sendable {
        public var id: String
        /// What the keyboard typed for it.
        public var typed: String
        /// What it is in the field now: what was typed, with every edit inside it. Typing that runs on from either end
        /// isn't in it, unless it retypes what was deleted at that end; once all of it is deleted it stays empty.
        public var final: String
        /// The field was emptied after it, as sending a message does; false when it was left.
        public var sent: Bool
        /// The keyboard lost its place in the field while something there changed, so `final` may be wrong.
        public var uncertain: Bool
    }

    private struct Dictation: Codable, Sendable {
        var id: String
        var typed: String
    }

    /// A stretch of one dictation's text; one typed inside another splits it in two.
    private struct Piece: Codable, Sendable {
        var dictation: Int
        var range: Range<Int>
        /// That end was deleted into, so typing there retypes it, until the caret moves.
        var openStart = false
        var openEnd = false
    }

    private var text: [Character]
    private var dictations: [Dictation] = []
    private var pieces: [Piece] = []
    /// The caret, or the selection, in `text`; nil while the keyboard can't tell where it is.
    private var caret: Range<Int>?
    /// The most the host has shown before the caret and after it, each cut at a length of its own. iOS cuts its view at
    /// the start of the text, of a line, or at that length, so a side shorter than its reach was cut at the field's or
    /// a line's end, as an empty side always is.
    private var reach = (before: 0, after: 0)
    private var uncertain = false
    /// The host has shown some of the field's text since the first dictation, so an empty window from it means the
    /// field was emptied; some hosts show a keyboard nothing at all.
    public private(set) var shown = false

    /// The keyboard can't tell where the caret is in the draft, so its edits aren't followed until a window is placed.
    public var isLost: Bool { caret == nil }

    /// How many characters of a window must agree with the draft to place it there.
    static let anchor = 12

    public init(_ state: TextState) {
        let before = Array(state.before), selected = Array(state.selected)
        text = before + selected + Array(state.after ?? "")
        caret = before.count..<before.count + selected.count
    }

    private enum CodingKeys: CodingKey { case text, dictations, pieces, reachBefore, reachAfter, uncertain, shown }

    /// A draft read back has lost the caret: the field may have changed while no keyboard was up.
    public init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = Array(try container.decode(String.self, forKey: .text))
        dictations = try container.decode([Dictation].self, forKey: .dictations)
        pieces = try container.decode([Piece].self, forKey: .pieces)
        reach = (try container.decode(Int.self, forKey: .reachBefore), try container.decode(Int.self, forKey: .reachAfter))
        uncertain = try container.decode(Bool.self, forKey: .uncertain)
        shown = try container.decode(Bool.self, forKey: .shown)
        caret = nil
    }

    public func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(String(text), forKey: .text)
        try container.encode(dictations, forKey: .dictations)
        try container.encode(pieces, forKey: .pieces)
        try container.encode(reach.before, forKey: .reachBefore)
        try container.encode(reach.after, forKey: .reachAfter)
        try container.encode(uncertain, forKey: .uncertain)
        try container.encode(shown, forKey: .shown)
    }

    /// Follows the dictation the keyboard just typed, which ends at the caret, cutting it out of any it was typed into.
    public mutating func add(_ id: String, typed: String) {
        guard let caret, caret.isEmpty, caret.lowerBound >= typed.count else { return }
        let range = caret.lowerBound - typed.count..<caret.lowerBound
        guard String(text[range]) == typed else { return }
        pieces = pieces.flatMap { piece -> [Piece] in
            guard piece.range.overlaps(range) else { return [piece] }
            var head = piece, tail = piece
            head.range = piece.range.lowerBound..<range.lowerBound
            head.openEnd = false
            tail.range = range.upperBound..<piece.range.upperBound
            tail.openStart = false
            return [head, tail].filter { !$0.range.isEmpty }
        }
        dictations.append(Dictation(id: id, typed: typed))
        pieces.append(Piece(dictation: dictations.count - 1, range: range))
        pieces.sort { $0.range.lowerBound < $1.range.lowerBound }
    }

    public mutating func insert(_ string: String) {
        guard let caret else { return uncertain = true }
        let inserted = Array(string)
        replace(caret, with: inserted)
        self.caret = caret.lowerBound + inserted.count..<caret.lowerBound + inserted.count
    }

    /// As `TextState.deleteBackward`: a selection goes with the first delete.
    public mutating func deleteBackward(_ count: Int) {
        guard let caret else { return uncertain = true }
        let start = max(caret.lowerBound - (caret.isEmpty ? count : count - 1), 0)
        replace(start..<caret.upperBound, with: [])
        self.caret = start..<start
    }

    public mutating func moveCursor(by offset: Int) {
        close()
        guard let caret, caret.isEmpty, (0...text.count).contains(caret.lowerBound + offset) else { return caret = nil }
        self.caret = caret.lowerBound + offset..<caret.lowerBound + offset
    }

    /// The host showed the keyboard this much of the field on each side of the caret.
    public mutating func see(before: Int, after: Int) {
        shown = true
        reach = (max(reach.before, before), max(reach.after, after))
    }

    public mutating func lose() {
        caret = nil
    }

    /// What every dictation in the field became.
    public func outcomes(sent: Bool) -> [Outcome] {
        dictations.indices.map { index in
            let final = pieces.filter { $0.dictation == index }.map { String(text[$0.range]) }.joined()
            return Outcome(id: dictations[index].id, typed: dictations[index].typed, final: final, sent: sent, uncertain: uncertain)
        }
    }

    /// The host's window of the field, as it is now, taken as the smallest edit of the draft that explains it: the
    /// window's start agrees with the draft at one place and its end at another, and what lies between them is what
    /// changed. A caret moved changes nothing; a paste or a cut changes what's at the caret. Text the window shows past
    /// either end of the draft is added to it. A window that agrees nowhere, as in another part of a long document, or
    /// as well in two places, as in a list of short lines that repeat, loses the caret until one is placed for sure.
    public mutating func place(before: String, selected: String, after: String) {
        let window = Array(before) + Array(selected) + Array(after)
        let shown = before.count..<before.count + selected.count
        reach = (max(reach.before, before.count), max(reach.after, after.count))
        let (lefts, rights) = agreements(of: window, around: shown, whole: (before.isEmpty || before.count < reach.before, after.isEmpty || after.count < reach.after))
        var best: (rank: [Int], left: Int, right: Int, span: Int, end: Int)?, tied = false
        for left in lefts {
            for right in rights {
                let span = max(0, right.reach - left.reach, left.offset - right.offset)
                let (first, last) = (max(right.reach, span), min(left.reach + span, window.count))
                guard first <= last else { continue }
                let cost = 2 * span - (left.offset - right.offset) + max(0, -left.offset) + max(0, right.offset + window.count - text.count)
                let rank = [left.cuts + right.cuts, cost, left.overruns + right.overruns]
                let end = min(max(shown.lowerBound, first), last)
                if let best, rank == best.rank {
                    tied = tied || (left.offset, right.offset + end, left.offset + end - span) != (best.left, best.right + best.end, best.left + best.end - best.span)
                } else if best.map({ rank.lexicographicallyPrecedes($0.rank) }) ?? true {
                    best = (rank, left.offset, right.offset, span, end)
                    tied = false
                }
            }
        }
        let wasLost = caret == nil
        guard let best, !tied else { return caret = nil }
        let lead = max(0, -best.left)
        prepend(window[..<lead])
        let (left, right) = (best.left + lead, best.right + lead)
        if right + window.count > text.count { text += window[(text.count - right)...] }
        let edit = left + best.end - best.span..<right + best.end
        let moved = caret != left + shown.lowerBound..<left + shown.upperBound
        if !edit.isEmpty || best.span > 0 {
            if wasLost { uncertain = true }
            replace(edit, with: window[best.end - best.span..<best.end])
        }
        if moved { close() }
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
            if end - low >= max(k, 1) || low == 0 && [expected?.left, 0].contains(offset) && caret.map({ (offset...offset + end).contains($0.lowerBound) }) == true {
                let cuts = whole.left && offset > 0 && text[offset - 1] != "\n"
                left.append(Side(offset: offset, reach: end, cuts: cuts ? 1 : 0, overruns: low == 0 ? 0 : 1))
            }
            if high - start >= max(k, 1) || high == window.count && [expected?.right, text.count - window.count].contains(offset) && caret.map({ (offset + start...offset + high).contains($0.upperBound) }) == true {
                let cuts = whole.right && offset + window.count < text.count && text[offset + window.count] != "\n"
                right.append(Side(offset: offset, reach: start, cuts: cuts ? 1 : 0, overruns: high == window.count ? 0 : 1))
            }
        }
        return (left, right)
    }

    /// Replaces `range` of the draft. An edit inside a dictation changes it, and so does typing at an end of one that was
    /// just deleted into; typing at either end otherwise isn't part of it, and an edit over all of it leaves it empty.
    private mutating func replace(_ range: Range<Int>, with new: some Collection<Character>) {
        let (a, b, n) = (range.lowerBound, range.upperBound, new.count)
        let delta = n - (b - a)
        text.replaceSubrange(range, with: new)
        for index in pieces.indices {
            var piece = pieces[index]
            let (s, e) = (piece.range.lowerBound, piece.range.upperBound)
            let inserted = a == b
            if s == e || a <= s && b >= e && !(inserted && (piece.openStart || piece.openEnd)) {
                let at = s <= a ? s : s >= b ? s + delta : a
                piece.range = at..<at
                piece.openStart = false
                piece.openEnd = false
            } else if b < s || b == s && !(inserted && piece.openStart) {
                piece.range = s + delta..<e + delta
            } else if a > e || a == e && !(inserted && piece.openEnd) {
            } else {
                piece.range = min(s, a)..<(e >= b ? e + delta : a + n)
                if !inserted {
                    if a <= s { piece.openStart = true }
                    if b >= e { piece.openEnd = true }
                }
            }
            pieces[index] = piece
        }
        for index in pieces.indices.dropFirst() {
            let floor = pieces[index - 1].range.upperBound
            let range = pieces[index].range
            pieces[index].range = max(range.lowerBound, floor)..<max(range.upperBound, floor)
        }
    }

    /// The caret moved, so typing at an end of a dictation no longer retypes it.
    private mutating func close() {
        for index in pieces.indices {
            pieces[index].openStart = false
            pieces[index].openEnd = false
        }
    }

    /// Text the window shows before what the draft has seen, which no dictation takes.
    private mutating func prepend(_ lead: some Collection<Character>) {
        guard !lead.isEmpty else { return }
        text.insert(contentsOf: lead, at: 0)
        for index in pieces.indices {
            pieces[index].range = pieces[index].range.lowerBound + lead.count..<pieces[index].range.upperBound + lead.count
        }
        caret = caret.map { $0.lowerBound + lead.count..<$0.upperBound + lead.count }
    }
}
