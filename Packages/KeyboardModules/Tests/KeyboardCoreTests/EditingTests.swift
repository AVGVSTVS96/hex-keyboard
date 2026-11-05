import Testing
@testable import KeyboardCore

private let grid = KeyGrid.standard

private func type(_ text: String, into engine: inout TypingEngine, _ document: some TextDocument) {
    for character in text {
        let label = String(character)
        let frame = grid.frame(of: label.lowercased())
        let tap = frame.map { Tap(x: $0.midX, y: $0.midY, key: label.lowercased()) }
        engine.perform(label == " " ? .space : .character(label), in: document, tap: tap)
    }
}

private func engine() -> TypingEngine {
    var engine = TypingEngine()
    engine.corrector = Corrector(source: testLexicon)
    return engine
}

/// Editing text typed earlier: the caret tapped back into it, suggestions picked there, the host's reports meanwhile.
struct EditingTests {
    @Test func aSuggestionPickedInsideAWordReplacesAllOfIt() throws {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("go hime now", into: &engine, document)
        document.cursor = 5
        engine.documentChanged(document)
        engine.accept(try #require(engine.suggestions.first { $0.text == "home" }), in: document)
        #expect(document.text == "Go home now")
        #expect(document.cursor == 8)
    }

    @Test func aSuggestionPickedBeforeASpaceStepsOverIt() throws {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("go hime now", into: &engine, document)
        document.cursor = 7
        engine.documentChanged(document)
        engine.accept(try #require(engine.suggestions.first { $0.text == "home" }), in: document)
        #expect(document.text == "Go home now")
        #expect(document.cursor == 8)
    }

    @Test func punctuationAfterAPickTakesThePlaceOfItsSpace() throws {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("go hom", into: &engine, document)
        engine.accept(try #require(engine.suggestions.first { $0.text == "home" }), in: document)
        #expect(document.text == "Go home ")
        type(".", into: &engine, document)
        #expect(document.text == "Go home. ")
        #expect(engine.shift == .on)
        type("ok", into: &engine, document)
        #expect(document.text == "Go home. Ok")
    }

    @Test func punctuationAfterATypedSpaceKeepsIt() {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("go :", into: &engine, document)
        #expect(document.text == "Go :")
    }

    @Test func theLiteralKeepsTheWordAsItStandsNow() throws {
        var engine = engine()
        engine.defersSuggestions = true
        let document = TestDocument("ok ")
        engine.documentChanged(document)
        type("hel", into: &engine, document)
        var job = try #require(engine.suggestionJob())
        job.run()
        engine.finish(job)
        let literal = try #require(engine.suggestions.first { $0.kind == .literal })
        type("p", into: &engine, document)
        engine.accept(literal, in: document)
        #expect(document.text == "ok help ")
        #expect(engine.corrector!.memory.isKept("help"))
        #expect(!engine.corrector!.memory.isKept("hel"))
    }

    @Test func aReportLeavesShiftAsYouTappedIt() {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("say ", into: &engine, document)
        engine.handle(.down(Key(.shift), tapCount: 1), in: document)
        engine.handle(.up(Key(.shift)), in: document)
        engine.documentChanged(document)
        type("j", into: &engine, document)
        #expect(document.text == "Say J")
    }

    @Test func curlyApostrophesAreCorrectedAndWrittenCurly() {
        var engine = engine()
        let document = TestDocument()
        engine.documentChanged(document)
        type("dln't dont ", into: &engine, document)
        #expect(document.text == "Don’t don’t ")
    }
}
