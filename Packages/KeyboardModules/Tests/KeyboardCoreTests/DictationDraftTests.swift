import Foundation
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

/// A field that shows the keyboard `before` characters before the caret and `after` after it, as iOS does, each side
/// with a length of its own.
private final class LopsidedDocument: TestDocument {
    let before: Int, after: Int

    init(before: Int, after: Int) {
        (self.before, self.after) = (before, after)
        super.init("")
    }

    override var textBeforeInput: String? { String(text.prefix(cursor).suffix(before)) }
    override var textAfterInput: String? { String(text.dropFirst(cursor + selection).prefix(after)) }
}

/// A field that shows the keyboard only the line the caret is in, as some hosts do.
private final class LineDocument: TestDocument {
    override var textBeforeInput: String? { String(text.prefix(cursor).split(separator: "\n", omittingEmptySubsequences: false).last ?? "") }
    override var textAfterInput: String? { String(text.dropFirst(cursor + selection).split(separator: "\n", omittingEmptySubsequences: false).first ?? "") }
}

/// A field that never shows the keyboard its text.
private final class BlindDocument: TestDocument {
    override var textBeforeInput: String? { "" }
    override var textAfterInput: String? { "" }
}

struct DictationDraftTests {
    private let long = "The garden behind the old library has seven benches, a fountain that only runs in summer, and a gardener named Ruth who waters the roses every morning before the doors open."

    private func dictate(_ said: String, into document: TestDocument, id: String = "a", in engine: inout TypingEngine) {
        engine.documentChanged(document)
        engine.handle(.dictated(said, id: id), in: document)
        engine.documentChanged(document)
    }

    /// The host moves the caret, or changes the text itself, and tells the keyboard.
    private func host(_ document: TestDocument, _ engine: inout TypingEngine, _ change: (TestDocument) -> Void) {
        change(document)
        engine.documentChanged(document)
    }

    private func send(_ document: TestDocument, _ engine: inout TypingEngine) -> [DictationDraft.Outcome] {
        engine.documentChanged(document)
        host(document, &engine) { $0.text = ""; $0.cursor = 0; $0.selection = 0 }
        return engine.takeDictations()
    }

    private func leave(_ engine: inout TypingEngine) -> [DictationDraft.Outcome] {
        engine.leaveField()
        return engine.takeDictations()
    }

    private func moveTo(_ word: String, in document: TestDocument, _ engine: inout TypingEngine, after: Bool = true) {
        host(document, &engine) {
            let range = $0.text.range(of: word)!
            $0.cursor = $0.text.distance(from: $0.text.startIndex, to: after ? range.upperBound : range.lowerBound)
            $0.selection = 0
        }
    }

    @Test func aDictationSentAsTypedEndsAsItWasTyped() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("See you at noon.", into: document, in: &engine)
        #expect(send(document, &engine) == [.init(id: "a", typed: "See you at noon.", final: "See you at noon.", sent: true, uncertain: false)])
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

    @Test func typingRunningOnFromADictationIsNotPartOfIt() {
        var engine = TypingEngine()
        let document = ClippedDocument("Dear Sam, ", window: 30)
        dictate("The keys are under the mat.", into: document, in: &engine)
        engine.type(" Thanks", in: document)
        moveTo("Sam", in: document, &engine)
        for _ in 0..<3 { engine.perform(.delete, in: document) }
        engine.type("Max", in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.typed) == ["The keys are under the mat."])
        #expect(outcome.map(\.final) == ["The keys are under the mat."])
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

    @Test func aDictationAtTheStartOfAnotherLeavesItWhole() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate("See you at noon.", into: document, id: "a", in: &engine)
        host(document, &engine) { $0.cursor = 0 }
        engine.handle(.dictated("Hi Sam.", id: "b"), in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.final) == ["See you at noon.", outcome[1].typed])
    }

    @Test func aDictationInsideAnotherIsCutOutOfIt() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate("Bring the blue folder to the meeting.", into: document, id: "a", in: &engine)
        moveTo("folder", in: document, &engine)
        engine.handle(.dictated("and the red pen", id: "b"), in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.final) == ["Bring the blue folder to the meeting.", outcome[1].typed])
    }

    @Test func aLineThatRepeatsLosesThePlaceRatherThanGuessing() {
        var engine = TypingEngine()
        let document = LineDocument()
        dictate("• Eggs\n• Milk\n• Eggs", into: document, in: &engine)
        host(document, &engine) { $0.cursor = 2 }
        engine.type("two ", in: document)
        let outcome = send(document, &engine)
        #expect(outcome.map(\.uncertain) == [true])
        #expect(outcome.map(\.final) != ["• Eggs\n• Milk\n• two Eggs"])
    }

    @Test func aLineLikeAnotherIsNeverEditedInTheWrongPlace() {
        var engine = TypingEngine()
        let document = LineDocument()
        dictate("• Eggs\n• Milk\n• Eggs again", into: document, in: &engine)
        host(document, &engine) { $0.cursor = 2 }
        engine.type("two ", in: document)
        let field = document.text
        let outcome = send(document, &engine)
        #expect(outcome.map(\.final) == [field] || outcome.map(\.uncertain) == [true])
    }

    /// A messaging app refuses the return that sends, and empties the field.
    @Test func theReturnThatSendsIsNotInWhatItBecame() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate(long, into: document, in: &engine)
        moveTo("seven", in: document, &engine)
        engine.perform(.return, in: document)
        host(document, &engine) { $0.text = ""; $0.cursor = 0 }
        #expect(engine.takeDictations().map(\.final) == [long])
    }

    /// The same sentence three times, seen through a window longer before the caret than after it: an edit in the middle
    /// one is placed there, or the outcome says it may be wrong, never placed on another.
    @Test func aSentenceThatRepeatsIsNeverEditedInTheWrongPlace() {
        let sentence = "Pack the blue tent and two lanterns for the trip."
        for cut in [(60, 20), (20, 60), (40, 40)] {
            var engine = TypingEngine()
            let document = LopsidedDocument(before: cut.0, after: cut.1)
            dictate([sentence, sentence, sentence].joined(separator: " "), into: document, in: &engine)
            host(document, &engine) { $0.cursor = sentence.count + 1 + 13 }
            for _ in 0..<4 { engine.perform(.delete, in: document) }
            engine.type("green", in: document)
            let field = document.text
            let outcome = send(document, &engine)
            #expect(outcome.map(\.final) == [field] || outcome.map(\.uncertain) == [true], "\(cut)")
        }
    }

    /// A host that shows the keyboard its text only late, a step behind: emptying it still sends.
    @Test func aFieldShownOnlyLateIsStillSent() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        engine.documentChanged(document)
        engine.handle(.dictated("Running late, be there soon.", id: "a"), in: document)
        document.text.removeLast()
        document.cursor -= 1
        engine.documentChanged(document)
        document.text += "."
        document.cursor += 1
        host(document, &engine) { $0.text = ""; $0.cursor = 0 }
        #expect(engine.takeDictations().map(\.sent) == [true])
    }

    @Test func aFieldCutFromASelectionIsNotSent() {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate("Call the plumber about the sink.", into: document, in: &engine)
        host(document, &engine) { $0.cursor = 0; $0.selection = $0.text.count }
        host(document, &engine) { $0.insert("") }
        #expect(engine.takeDictations().isEmpty)
        #expect(leave(&engine) == [.init(id: "a", typed: "Call the plumber about the sink.", final: "", sent: false, uncertain: false)])
    }

    @Test func aFieldThatShowsNoTextIsNeverTakenForSent() {
        var engine = TypingEngine()
        let document = BlindDocument()
        dictate("Call the plumber.", into: document, in: &engine)
        #expect(engine.takeDictations().isEmpty)
        engine.type(" Now", in: document)
        #expect(leave(&engine).map(\.sent) == [false])
    }

    @Test func aDictationLeftUnsentIsKeptAsLeft() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("Call the plumber.", into: document, in: &engine)
        #expect(leave(&engine) == [.init(id: "a", typed: "Call the plumber.", final: "Call the plumber.", sent: false, uncertain: false)])
        #expect(engine.takeDictations().isEmpty)
    }

    /// The keyboard goes away (the app scrolls it off, or opens for the next dictation) and a new one comes up in the
    /// same field: it goes on following, from the draft the last one kept.
    @Test func theNextKeyboardInTheFieldGoesOnFollowing() throws {
        var engine = TypingEngine()
        let document = ClippedDocument(window: 30)
        dictate(long, into: document, in: &engine)
        moveTo("Ruth", in: document, &engine)
        for _ in 0..<4 { engine.perform(.delete, in: document) }
        engine.type("rose", in: document)
        engine.endSession()
        let draft = engine.takeDraft()
        let kept = try JSONEncoder().encode(try #require(draft))
        #expect(engine.takeDictations().isEmpty)

        var next = TypingEngine()
        next.resume(try JSONDecoder().decode(DictationDraft.self, from: kept))
        moveTo("seven", in: document, &next)
        for _ in 0..<5 { next.perform(.delete, in: document) }
        next.type("eight", in: document)
        let field = document.text
        let outcome = send(document, &next)
        #expect(field == long.replacingOccurrences(of: "Ruth", with: "rose").replacingOccurrences(of: "seven", with: "eight"))
        #expect(outcome.map(\.final) == [field])
        #expect(outcome.map(\.uncertain) == [false])
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

    @Test func aDictationDeletedWholeStaysEmpty() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("Lunch at two.", into: document, in: &engine)
        for _ in 0..<13 { engine.perform(.delete, in: document) }
        engine.type("Dinner at six", in: document)
        #expect(send(document, &engine).map(\.final) == [""])
    }

    @Test func aDictationSelectedAndDeletedDoesNotTakeTheNextMessage() {
        var engine = TypingEngine()
        let document = ClippedDocument()
        dictate("Running late.", into: document, in: &engine)
        host(document, &engine) { $0.cursor = 0; $0.selection = $0.text.count }
        engine.perform(.delete, in: document)
        engine.type("Ok see you there", in: document)
        #expect(send(document, &engine).map(\.final) == [""])
    }

    /// Random edits inside a long dictation between two lines of other text, seen through a short window, as the
    /// keyboard and the app make them, with the host reporting after each: what it became must be what lies between
    /// those lines, or say it may be wrong, which only a window that fits two places equally may do.
    @Test func randomEditsThroughAWindowEndAsTheField() {
        let words = ["river", "stone", "bright", "seven", "maple", "quiet", "over", "the", "a", "lantern", "north", "and"]
        let (head, tail) = ("Dear Sam,\n", "\nThanks")
        var failures = 0, uncertain = 0
        for seed in 0..<UInt64(3000) {
            var random = seed &* 6364136223846793005 &+ 1442695040888963407
            func next(_ bound: Int) -> Int {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                return Int((random >> 33) % UInt64(max(bound, 1)))
            }
            var engine = TypingEngine()
            let document = ClippedDocument(head + tail, window: 20 + next(40))
            document.cursor = head.count
            let said = (0..<(30 + next(40))).map { _ in words[next(words.count)] }.joined(separator: " ")
            dictate(said, into: document, in: &engine)
            func inside() -> Int {
                let end = document.text.count - tail.count - 14
                return head.count + 14 + next(max(end - head.count - 14, 1))
            }
            for _ in 0..<(5 + next(20)) {
                switch next(6) {
                case 0:
                    host(document, &engine) { $0.selection = 0; $0.cursor = inside() }
                case 1:
                    host(document, &engine) { $0.selection = 0; $0.cursor = inside() }
                    for _ in 0...next(3) {
                        engine.perform(.delete, in: document)
                        engine.documentChanged(document)
                    }
                case 2:
                    host(document, &engine) { $0.selection = 0; $0.cursor = inside() }
                    engine.type(" " + words[next(words.count)], in: document)
                    engine.documentChanged(document)
                case 3:
                    host(document, &engine) { $0.selection = 0; $0.cursor = inside() }
                    host(document, &engine) { $0.insert(words[next(words.count)]) }
                case 4:
                    host(document, &engine) { $0.cursor = inside(); $0.selection = 1 + next(10) }
                    host(document, &engine) { $0.insert("") }
                default:
                    host(document, &engine) { $0.cursor = inside(); $0.selection = 1 + next(10) }
                    engine.type(words[next(words.count)], in: document)
                    engine.documentChanged(document)
                }
            }
            let field = String(document.text.dropFirst(head.count).dropLast(tail.count))
            let outcome = send(document, &engine)
            if outcome.map(\.final) != [field] { outcome.first?.uncertain == true ? (uncertain += 1) : (failures += 1) }
        }
        #expect(failures == 0)
        #expect(uncertain < 30)
    }
}
