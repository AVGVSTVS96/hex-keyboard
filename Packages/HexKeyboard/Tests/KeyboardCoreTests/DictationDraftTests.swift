import Testing
@testable import KeyboardCore

/// A field that shows the keyboard only `window` characters on each side of the caret, as iOS does.
private final class ClippedDocument: TestDocument {
    let window: Int

    init(_ text: String = "", window: Int = 40) {
        self.window = window
        super.init(text)
    }

    override var textBeforeInput: String? { String(text.prefix(cursor).suffix(window)) }
    override var textAfterInput: String? { String(text.dropFirst(cursor + selection).prefix(window)) }
}

struct DictationDraftTests {
    private let long = "The garden behind the old library has seven benches, a fountain that only runs in summer, and a gardener named Ruth who waters the roses every morning before the doors open."

    private func dictate(_ said: String, into document: TestDocument, id: String = "a", in engine: inout TypingEngine) {
        engine.documentChanged(document)
        engine.handle(.dictated(said, id: id), in: document)
    }

    /// The host moves the caret, or changes the text itself, and tells the keyboard.
    private func host(_ document: TestDocument, _ engine: inout TypingEngine, _ change: (TestDocument) -> Void) {
        change(document)
        engine.documentChanged(document)
    }

    private func send(_ document: TestDocument, _ engine: inout TypingEngine) -> [DictationDraft.Outcome] {
        host(document, &engine) { $0.text = ""; $0.cursor = 0; $0.selection = 0 }
        return engine.takeDictations()
    }

    private func moveTo(_ word: String, in document: TestDocument, _ engine: inout TypingEngine, after: Bool = true) {
        host(document, &engine) {
            let range = $0.text.range(of: word)!
            $0.cursor = $0.text.distance(from: $0.text.startIndex, to: after ? range.upperBound : range.lowerBound)
        }
    }

    @Test func aDictationSentAsTypedEndsAsItWasTyped() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("See you at noon.", into: document, in: &engine)
        #expect(send(document, &engine) == [.init(id: "a", typed: "See you at noon.", final: "See you at noon.", sent: true)])
    }

    @Test func aWordRetypedAtTheEndIsInWhatItBecame() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("See you at noon.", into: document, in: &engine)
        for _ in 0..<5 { engine.perform(.delete, in: document) }
        engine.type("one", in: document)
        #expect(send(document, &engine).map(\.final) == ["See you at one"])
    }

    @Test func anEditInsideALongDictationSeenThroughAWindowKeepsAllOfIt() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate(long, into: document, in: &engine)
        moveTo("Ruth", in: document, &engine)
        for _ in 0..<4 {
            engine.perform(.delete, in: document)
            engine.documentChanged(document)
        }
        engine.type("rose", in: document)
        moveTo("seven", in: document, &engine)
        for _ in 0..<5 { engine.perform(.delete, in: document) }
        engine.type("eight", in: document)
        host(document, &engine) { $0.cursor = $0.text.count }
        let final = send(document, &engine).map(\.final)
        #expect(final == [long.replacingOccurrences(of: "Ruth", with: "rose").replacingOccurrences(of: "seven", with: "eight")])
    }

    @Test func aSelectionTypedOverChangesTheDictation() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate(long, into: document, in: &engine)
        host(document, &engine) { $0.select("fountain") }
        engine.type("pond", in: document)
        #expect(send(document, &engine).map(\.final) == [long.replacingOccurrences(of: "fountain", with: "pond")])
    }

    @Test func aPasteAndACutTheAppMakesAreFollowed() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate(long, into: document, in: &engine)
        moveTo("benches", in: document, &engine)
        host(document, &engine) { $0.insert(" and tables") }
        host(document, &engine) { $0.select(" every morning") }
        host(document, &engine) { $0.insert("") }
        let expected = long.replacingOccurrences(of: "benches", with: "benches and tables").replacingOccurrences(of: " every morning", with: "")
        #expect(send(document, &engine).map(\.final) == [expected])
    }

    @Test func textAroundADictationIsNotPartOfIt() {
        var engine = TypingEngine()
        let document = ClippedDocument("Dear Sam, ", window: 30)
        dictate("The keys are under the mat.", into: document, in: &engine)
        engine.type(" Thanks", in: document)
        moveTo("Sam", in: document, &engine)
        for _ in 0..<3 { engine.perform(.delete, in: document) }
        engine.type("Max", in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.typed) == ["The keys are under the mat."])
        #expect(outcome.map(\.final) == ["The keys are under the mat. Thanks"])
    }

    @Test func twoDictationsInOneFieldAreEachFollowed() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate("Bring the blue folder.", into: document, id: "a", in: &engine)
        engine.handle(.dictated("Also the green one.", id: "b"), in: document)
        moveTo("blue", in: document, &engine)
        for _ in 0..<4 { engine.perform(.delete, in: document) }
        engine.type("red", in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.id) == ["a", "b"])
        #expect(outcome.map(\.final) == ["Bring the red folder.", " Also the green one."])
    }

    @Test func aDictationLeftUnsentIsKeptAsLeft() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("Call the plumber.", into: document, in: &engine)
        engine.endSession()
        #expect(engine.takeDictations() == [.init(id: "a", typed: "Call the plumber.", final: "Call the plumber.", sent: false)])
        #expect(engine.takeDictations().isEmpty)
    }

    @Test func aCaretFarFromTheDictationChangesNothing() {
        var engine = TypingEngine()
        let filler = String(repeating: "Lorem ipsum dolor sit amet. ", count: 8)
        let document = ClippedDocument(filler, window: 30)
        dictate("Meet at the station.", into: document, in: &engine)
        host(document, &engine) { $0.cursor = 10 }
        engine.type("x", in: document)
        host(document, &engine) { $0.cursor = $0.text.count }
        #expect(send(document, &engine).map(\.final) == ["Meet at the station."])
    }

    @Test func aDictationWithoutATranscriptIsNotFollowed() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        engine.documentChanged(document)
        engine.handle(.dictated("Hello there."), in: document)
        #expect(send(document, &engine).isEmpty)
    }

    @Test func aDictationDeletedAndRetypedEndsAsTheRetyping() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("Lunch at two.", into: document, in: &engine)
        for _ in 0..<13 { engine.perform(.delete, in: document) }
        engine.type("Dinner at six", in: document)
        #expect(send(document, &engine).map(\.final) == ["Dinner at six"])
    }

    /// Random edits all over a long dictation alone in a field seen through a short window, as the keyboard and the app
    /// make them, with the host reporting after each: what it became must be the whole field.
    @Test func randomEditsThroughAWindowEndAsTheField() {
        let words = ["river", "stone", "bright", "seven", "maple", "quiet", "over", "the", "a", "lantern", "north", "and"]
        var failures = 0
        for seed in 0..<UInt64(3000) {
            var random = seed &* 6364136223846793005 &+ 1442695040888963407
            func next(_ bound: Int) -> Int {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                return Int((random >> 33) % UInt64(max(bound, 1)))
            }
            var engine = TypingEngine()
            let document = ClippedDocument(window: 20 + next(40))
            let said = (0..<(30 + next(40))).map { _ in words[next(words.count)] }.joined(separator: " ")
            dictate(said, into: document, in: &engine)
            for _ in 0..<(5 + next(20)) {
                switch next(6) {
                case 0:
                    host(document, &engine) { $0.selection = 0; $0.cursor = next($0.text.count + 1) }
                case 1:
                    for _ in 0...next(3) {
                        engine.perform(.delete, in: document)
                        engine.documentChanged(document)
                    }
                case 2:
                    engine.type(" " + words[next(words.count)], in: document)
                    engine.documentChanged(document)
                case 3:
                    host(document, &engine) { $0.insert(words[next(words.count)]) }
                case 4:
                    host(document, &engine) {
                        $0.cursor = next($0.text.count + 1)
                        $0.selection = min(1 + next(10), $0.text.count - $0.cursor)
                    }
                    host(document, &engine) { $0.insert("") }
                default:
                    host(document, &engine) {
                        $0.cursor = next($0.text.count + 1)
                        $0.selection = min(1 + next(10), $0.text.count - $0.cursor)
                    }
                    engine.type(words[next(words.count)], in: document)
                    engine.documentChanged(document)
                }
            }
            let field = document.text
            if send(document, &engine).map(\.final) != [field] { failures += 1 }
        }
        #expect(failures == 0)
    }
}
