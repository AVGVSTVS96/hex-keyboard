import Testing
@testable import KeyboardCore

struct LinesTests {
    /// Wraps like a text view in a font whose every letter is 1pt wide: whole words, spaces hanging at the line's end.
    struct Monospace: LineLayout {
        var width: Int

        func carets(in paragraph: String) -> [Caret] {
            let characters = Array(paragraph)
            var carets: [Caret] = [], line = 0, x = 0, index = 0
            while index < characters.count {
                var end = index
                while end < characters.count, characters[end] != " " { end += 1 }
                if end == index { end += 1 } else if x > 0, x + end - index > width { line += 1; x = 0 }
                for _ in index..<end {
                    carets.append(Caret(line: line, x: Double(x)))
                    x += 1
                }
                index = end
            }
            return carets + [Caret(line: line, x: Double(x))]
        }
    }

    /// A text view's report: only the caret's paragraph.
    final class ParagraphDocument: TestDocument {
        override var textBeforeInput: String? { super.textBeforeInput?.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) }
        override var textAfterInput: String? { super.textAfterInput?.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) }
    }

    private func move(_ text: String, from cursor: Int, _ lines: Int..., showing document: TestDocument? = nil) -> Int {
        var engine = TypingEngine()
        engine.lineLayout = Monospace(width: 10)
        let document = document ?? TestDocument(text)
        document.text = text
        document.cursor = cursor
        engine.documentChanged(document)
        for count in lines {
            _ = engine.handle(.cursorLines(count), in: document)
            engine.documentChanged(document)
        }
        return document.cursor
    }

    @Test func movesUpAndDownWrappedLinesKeepingItsPlace() {
        let text = "aaaa bbbb cccc dddd eeee"
        #expect(move(text, from: 12, -1) == 2)
        #expect(move(text, from: 2, 1) == 12)
        #expect(move(text, from: 2, 2) == 22)
        #expect(move(text, from: 22, -2) == 2)
    }

    @Test func crossesLineBreaksIntoTheNearestSpotOfTheNextParagraph() {
        #expect(move("aaaa bbbb cc\ndddddddd", from: 21, -1) == 12)
        #expect(move("aaaa bbbb cc\ndddddddd", from: 7, 1) == 12)
        #expect(move("aaaa\n\nbbbb", from: 4, 1) == 5)
        #expect(move("aaaa\n\nbbbb", from: 4, 1, 1) == 10)
    }

    @Test func crossesIntoParagraphsTheHostHasntShownAndSettlesWhenItDoes() {
        let text = "aaaa bbbb cc\ndddddddd\neeeeee"
        #expect(move(text, from: 21, -1, showing: ParagraphDocument()) == 12)
        #expect(move(text, from: 7, 1, 1, showing: ParagraphDocument()) == 20)
        #expect(move(text, from: 21, 1, showing: ParagraphDocument()) == 28)
        #expect(move(text, from: 28, -1, showing: ParagraphDocument()) == 19)
        #expect(move(text, from: 28, -1, -1, showing: ParagraphDocument()) == 12)
    }

    @Test func comesBackOutOfAShortLineWhereItWentIn() {
        #expect(move("aaaaaaaa\nbb\ncccccccc", from: 20, -1) == 11)
        #expect(move("aaaaaaaa\nbb\ncccccccc", from: 20, -1, -1) == 8)
        #expect(move("aaaaaaaa\nbb\ncccccccc", from: 20, -2) == 8)
    }

    @Test func staysPutPastTheFirstAndLastLines() {
        #expect(move("aaaa bbbb cccc", from: 3, -1) == 3)
        #expect(move("aaaa bbbb cccc", from: 12, 1) == 12)
    }

    @Test func movingAlongTheLineSetsANewPlace() {
        var engine = TypingEngine()
        engine.lineLayout = Monospace(width: 10)
        let document = TestDocument("aaaaaaaa\nbb\ncccccccc")
        engine.documentChanged(document)
        _ = engine.handle(.cursorLines(-1), in: document)
        _ = engine.handle(.cursor(offset: -1), in: document)
        _ = engine.handle(.cursorLines(-1), in: document)
        #expect(document.cursor == 1)
    }

    @Test func needsALayout() {
        var engine = TypingEngine()
        let document = TestDocument("aaaa bbbb cccc")
        engine.documentChanged(document)
        _ = engine.handle(.cursorLines(-1), in: document)
        #expect(document.cursor == 14)
    }
}
