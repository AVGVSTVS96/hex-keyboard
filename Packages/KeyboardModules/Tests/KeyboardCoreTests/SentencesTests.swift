import Testing
@testable import KeyboardCore

struct SentencesTests {
    /// A text view's report: only the caret's paragraph.
    final class ParagraphDocument: TestDocument {
        override var textBeforeInput: String? { super.textBeforeInput?.split(separator: "\n", omittingEmptySubsequences: false).last.map(String.init) }
        override var textAfterInput: String? { super.textAfterInput?.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) }
    }

    private func move(_ text: String, from cursor: Int, _ counts: Int..., showing document: TestDocument? = nil) -> Int {
        var engine = TypingEngine()
        let document = document ?? TestDocument(text)
        document.text = text
        document.cursor = cursor
        engine.documentChanged(document)
        for count in counts {
            _ = engine.handle(.cursorSentences(count), in: document)
            engine.documentChanged(document)
        }
        return document.cursor
    }

    let text = "One two. Three four! Five six"

    @Test func upGoesToTheStartOfTheSentenceThenOfTheOneBefore() {
        #expect(move(text, from: 24, -1) == 21)
        #expect(move(text, from: 24, -1, -1) == 9)
        #expect(move(text, from: 24, -3) == 0)
        #expect(move(text, from: 9, -1) == 0)
    }

    @Test func downGoesToTheEndOfTheSentenceThenOfTheOneAfter() {
        #expect(move(text, from: 2, 1) == 8)
        #expect(move(text, from: 2, 1, 1) == 20)
        #expect(move(text, from: 8, 1) == 20)
        #expect(move(text, from: 2, 3) == 29)
    }

    @Test func aLineTheTextBreaksIsASentence() {
        #expect(move("milk\neggs\nbread", from: 7, -1) == 5)
        #expect(move("milk\neggs\nbread", from: 7, -1, -1) == 0)
        #expect(move("milk\neggs\nbread", from: 2, 1, 1) == 9)
        #expect(move("aaaa\n\nbbbb", from: 4, 1) == 5)
        #expect(move("aaaa\n\nbbbb", from: 8, -1, -1) == 5)
    }

    @Test func closingQuotesAndBracketsStayWithTheirSentence() {
        let text = "He said \"go.\" Then (it rained.) Done"
        #expect(move(text, from: 16, -1) == 14)
        #expect(move(text, from: 2, 1) == 13)
        #expect(move(text, from: 16, 1) == 31)
    }

    @Test func aPointInsideAWordEndsNothing() {
        #expect(move("Version 2.5 is out. Go", from: 15, -1) == 0)
        #expect(move("see iikb.app now", from: 2, 1) == 16)
    }

    @Test func staysPutPastTheTextsEnds() {
        #expect(move(text, from: 3, -1, -1) == 0)
        #expect(move(text, from: 26, 1, 1) == 29)
    }

    @Test func crossesIntoParagraphsTheHostHasntShownAndSettlesWhenItDoes() {
        let text = "First one. Second one\nThird. Fourth\n\nFifth"
        #expect(move(text, from: 24, -1, -1, showing: ParagraphDocument()) == 11)
        #expect(move(text, from: 5, 1, 1, showing: ParagraphDocument()) == 21)
        #expect(move(text, from: 5, 1, 1, 1, showing: ParagraphDocument()) == 28)
        #expect(move(text, from: 30, 1, 1, showing: ParagraphDocument()) == 36)
        #expect(move(text, from: 38, -1, -1, showing: ParagraphDocument()) == 36)
    }
}
