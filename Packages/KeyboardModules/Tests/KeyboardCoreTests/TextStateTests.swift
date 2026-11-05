import Testing
@testable import KeyboardCore

/// A host whose view of the text is set by the test, while the keyboard's edits land on `truth` in order.
private final class ShownHost: TextDocument {
    let truth: TestDocument
    var shown: String?

    init(_ text: String = "") {
        truth = TestDocument(text)
        shown = text
    }

    var textBeforeInput: String? { shown }
    var textAfterInput: String? { "" }
    func insert(_ text: String) { truth.insert(text) }
    func deleteBackward(_ count: Int) { truth.deleteBackward(count) }
    func moveCursor(by offset: Int) { truth.moveCursor(by: offset) }
}

struct TextStateTests {
    @Test func aLateReportChangesNothing() {
        var engine = TypingEngine.correcting()
        let host = ShownHost()
        engine.documentChanged(host)
        engine.type("so helo", in: host)
        host.shown = "So he"
        #expect(engine.documentChanged(host) == .behind)
        engine.type(" ", in: host)
        #expect(host.truth.text == "So hello ")
    }

    @Test func aWindowOfTheTextIsCurrent() {
        var engine = TypingEngine.correcting()
        let host = ShownHost()
        engine.documentChanged(host)
        engine.type("so helo", in: host)
        host.shown = "elo"
        #expect(engine.documentChanged(host) == .current)
        #expect(engine.text.before == "So helo")
    }

    @Test func aReportOfTextTheKeyboardNeverHadIsAdoptedButNeverAutocorrected() {
        var engine = TypingEngine.correcting()
        let host = ShownHost("so ")
        engine.documentChanged(host)
        engine.type("helo", in: host)
        host.shown = "so helok"
        #expect(engine.documentChanged(host) == .changed)
        engine.type(" ", in: host)
        #expect(host.truth.text == "so helo ")
    }

    @Test func appTextEndingLikeAnEarlierStateIsAChange() {
        var engine = TypingEngine.correcting()
        let host = ShownHost("hi")
        engine.documentChanged(host)
        engine.type(" thre", in: host)
        host.truth.text = "say hi"
        host.truth.cursor = 6
        host.shown = "say hi"
        #expect(engine.documentChanged(host) == .changed)
        #expect(engine.text.before == "say hi")
        engine.type(" ", in: host)
        #expect(host.truth.text == "say hi ")
    }

    @Test func aViewCutAtALengthSlidesBackOverDeletedText() {
        var engine = TypingEngine.correcting()
        let host = ShownHost("abc def ghi jkl")
        host.shown = "ghi jkl"
        engine.documentChanged(host)
        engine.perform(.delete, in: host)
        engine.perform(.delete, in: host)
        engine.type("x", in: host)
        host.shown = "f ghi j"
        #expect(engine.documentChanged(host) == .behind)
        host.shown = " ghi jx"
        #expect(engine.documentChanged(host) == .current)
        #expect(engine.text.before == " ghi jx")
    }

    @Test func anEmptyFieldAfterSendingStartsASentence() {
        var engine = TypingEngine.correcting()
        let host = ShownHost()
        engine.documentChanged(host)
        engine.type("hi there", in: host)
        host.truth.text = ""
        host.truth.cursor = 0
        host.shown = ""
        #expect(engine.documentChanged(host) == .changed)
        #expect(engine.shift == .on)
        engine.type("ok", in: host)
        #expect(host.truth.text == "Ok")
    }

    @Test func movingTheCaretMovesTheKnownText() {
        var engine = TypingEngine.correcting()
        let host = ShownHost()
        engine.documentChanged(host)
        engine.type("help world", in: host)
        engine.moveCursor(by: -6, in: host)
        #expect(engine.text.before == "Help")
        #expect(engine.text.after == " world")
        host.shown = "Help world"
        #expect(engine.documentChanged(host) == .behind)
        engine.type("s", in: host)
        #expect(host.truth.text == "Helps world")
    }

    @Test func aTapBackIntoTheTextIsNeverTakenForALateReport() {
        var engine = TypingEngine.correcting()
        let host = LateHost()
        engine.documentChanged(host)
        engine.type("i went to the store", in: host)
        host.place(cursor: 6)
        #expect(engine.documentChanged(host) == .changed)
        #expect(engine.text.before == "I went")
        #expect(engine.text.after == " to the store")
        for _ in 0..<4 { engine.perform(.delete, in: host) }
        engine.type("walked", in: host)
        #expect(host.text == "I walked to the store")
        #expect(engine.text.before == "I walked")
    }

    @Test func aWordRetypedAfterATapBackIsCorrectedWhereItIs() {
        var engine = TypingEngine.correcting()
        let host = LateHost()
        engine.documentChanged(host)
        engine.type("the help world", in: host)
        host.place(cursor: 8)
        engine.documentChanged(host)
        for _ in 0..<4 { engine.perform(.delete, in: host) }
        engine.type("wrk", in: host)
        engine.perform(.character(","), in: host)
        #expect(host.text == "The work, world")
    }
}
