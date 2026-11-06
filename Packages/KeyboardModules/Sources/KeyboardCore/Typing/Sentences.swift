/// The space bar trackpad's moves up and down. iOS moves a keyboard's caret only by characters and never tells it where
/// the field wraps its lines, so up and down go by sentence, as KeyboardKit's trackpad does: up to the start of the
/// caret's sentence, then of the one before; down to its end, then to the end of the one after. A line the text breaks
/// ends a sentence too, so a list or a short message moves a line at a time.
enum Sentences {
    struct Move {
        var offset: Int
        /// The move stepped past the text the host showed (a text view shows only the caret's paragraph), so the caret
        /// still has to reach the nearest stop once the host shows what's there (`settle`).
        var crossed = false
    }

    /// The move `count` sentences down, up when negative, in `before` + `after`.
    static func move(_ count: Int, before: String, after: String) -> Move {
        let text = Array(before) + Array(after), caret = before.count, step = count.signum()
        var index = caret
        for _ in 0..<abs(count) {
            guard let stop = stop(step, from: index, in: text) else { return Move(offset: index + step - caret, crossed: true) }
            index = stop
        }
        return Move(offset: index - caret)
    }

    /// The offset to the nearest stop up (`step` -1) or down (1), staying where the caret is when it's one.
    static func settle(_ step: Int, before: String, after: String) -> Int {
        let text = Array(before) + Array(after)
        return (stop(step, from: before.count, in: text, including: true) ?? before.count) - before.count
    }

    private static func stop(_ step: Int, from index: Int, in text: [Character], including: Bool = false) -> Int? {
        let first = including ? index : index + step
        return step < 0
            ? stride(from: first, through: 0, by: -1).first { starts(at: $0, in: text) }
            : stride(from: first, through: text.count, by: 1).first { ends(at: $0, in: text) }
    }

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", ")", "]", "”", "’", "»"]

    private static func starts(at index: Int, in text: [Character]) -> Bool {
        if index == 0 || text[index - 1].isNewline { return true }
        guard index < text.count, !text[index].isWhitespace else { return false }
        var gap = index
        while gap > 0, text[gap - 1].isWhitespace, !text[gap - 1].isNewline { gap -= 1 }
        return gap < index && ends(at: gap, in: text)
    }

    private static func ends(at index: Int, in text: [Character]) -> Bool {
        if index == text.count || text[index].isNewline { return true }
        guard text[index].isWhitespace else { return false }
        var mark = index
        while mark > 0, closers.contains(text[mark - 1]) { mark -= 1 }
        return mark > 0 && terminators.contains(text[mark - 1])
    }
}
