/// Where the host draws a caret position of a paragraph: which of its wrapped lines, and how far along it in points.
public struct Caret: Hashable, Sendable {
    public var line: Int
    public var x: Double

    public init(line: Int, x: Double) {
        self.line = line
        self.x = x
    }
}

/// How the host wraps its text. A keyboard is never told, so the platform lays the text out as the field likely does.
public protocol LineLayout {
    /// A caret for each position in `paragraph`, one more than it has characters. The paragraph holds no line break.
    func carets(in paragraph: String) -> [Caret]
}

/// The x the caret keeps through a run of moves up and down, as a text view keeps it, so crossing a short line brings
/// it back out where it went in.
struct LineGoal: Hashable, Sendable {
    var x: Double
    /// Where the last move left the caret: the goal holds only while it's still there. Nil when the move crossed into
    /// a paragraph the host hadn't shown, which the caret enters at its edge and settles along once the host shows it.
    var landing: Landing?

    struct Landing: Hashable, Sendable {
        var paragraph: String
        var index: Int
    }
}

enum Lines {
    struct Move {
        var offset: Int
        var goal: LineGoal
    }

    /// The move that lands the caret `count` lines down (up when negative) in `before` + `after`, nearest the goal's x.
    /// Hosts show only so much text around the caret (a text view, only the caret's paragraph), so a move past what
    /// they show crosses the line break and stops there, its landing left to settle.
    static func move(_ count: Int, before: String, after: String, goal: LineGoal?, layout: some LineLayout) -> Move {
        let text = Array(before) + Array(after), caret = before.count
        var range = paragraph(around: caret, in: text)
        var carets = layout.carets(in: String(text[range]))
        let start = caret - range.lowerBound
        let holds = goal.map { $0.landing.map { $0 == LineGoal.Landing(paragraph: String(text[range]), index: start) } ?? true } ?? false
        let x = holds ? goal!.x : carets[start].x
        var line = carets[start].line
        for _ in 0..<abs(count) {
            if count < 0, line > 0 {
                line -= 1
            } else if count > 0, line < carets[carets.count - 1].line {
                line += 1
            } else if count < 0, range.lowerBound > 0 {
                range = paragraph(around: range.lowerBound - 1, in: text)
                carets = layout.carets(in: String(text[range]))
                line = carets[carets.count - 1].line
            } else if count > 0, range.upperBound < text.count {
                range = paragraph(around: range.upperBound + 1, in: text)
                carets = layout.carets(in: String(text[range]))
                line = 0
            } else {
                let edge = count < 0 ? range.lowerBound - 1 : range.upperBound + 1
                return Move(offset: edge - caret, goal: LineGoal(x: x))
            }
        }
        let index = carets.indices.filter { carets[$0].line == line }.min { abs(carets[$0].x - x) < abs(carets[$1].x - x) }!
        return Move(offset: range.lowerBound + index - caret, goal: LineGoal(x: x, landing: .init(paragraph: String(text[range]), index: index)))
    }

    /// The paragraph holding position `index`: from the line break before it to the one after, or the text's ends.
    private static func paragraph(around index: Int, in text: [Character]) -> Range<Int> {
        var start = index, end = index
        while start > 0, !text[start - 1].isNewline { start -= 1 }
        while end < text.count, !text[end].isNewline { end += 1 }
        return start..<end
    }
}
