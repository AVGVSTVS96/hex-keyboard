import Testing
@testable import KeyboardCore

private final class Reading: SwipeSource {
    var words: [(word: String, score: Double)]
    var keys: [String: Rect] = [:]

    init(_ words: [(word: String, score: Double)]) { self.words = words }

    func decode(_ path: [SwipePoint], keys: [String: Rect]) -> [(word: String, score: Double)] {
        self.keys = keys
        return words
    }
}

private let path = [SwipePoint(x: 20, y: 20, time: 0), SwipePoint(x: 120, y: 40, time: 80), SwipePoint(x: 200, y: 20, time: 160)]

private func engine(reading words: [(word: String, score: Double)]) -> (engine: TypingEngine, source: Reading, document: TestDocument) {
    var engine = TypingEngine()
    engine.corrector = Corrector(source: testLexicon)
    engine.settings.autoCapitalization = false
    let source = Reading(words)
    engine.swipeSource = source
    let document = TestDocument()
    engine.documentChanged(document)
    return (engine, source, document)
}

struct SwipeTests {
    @Test func aSwipeTypesItsWordAndTheNextOneFollowsAfterASpace() {
        var (engine, source, document) = engine(reading: [("hello", -1)])
        let typed = engine.handle(.swipe(path), in: document)
        #expect(typed)
        #expect(document.text == "hello", "no space before the first word, none after")
        source.words = [("world", -1)]
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "hello world")
        #expect(engine.text.owned == document.text.count, "the keyboard typed it, so it may correct it")
    }

    @Test func noSpaceGoesInAfterASpaceOrAnOpener() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.perform(.space, in: document)
        engine.handle(.swipe(path), in: document)
        #expect(document.text == " hello")
        let quote = TestDocument("(")
        engine.documentChanged(quote)
        engine.handle(.swipe(path), in: quote)
        #expect(quote.text == "(hello")
    }

    @Test func aWordInProgressEndsBeforeTheSwipe() {
        var (engine, _, document) = engine(reading: [("world", -1)])
        engine.perform(.character("h"), in: document)
        engine.perform(.character("i"), in: document)
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "hi world")
    }

    @Test func capitalsFollowShiftAndCapsLock() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.settings.autoCapitalization = true
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "Hello", "the field's start asks for a capital, as typing does")
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "Hello hello")

        let other = TestDocument()
        engine.documentChanged(other)
        engine.perform(.capsLock, in: other)
        engine.handle(.swipe(path), in: other)
        #expect(other.text == "HELLO")
    }

    @Test func theSentenceDecidesBetweenCloseReadings() {
        var (engine, _, document) = engine(reading: [("man", -1), ("the", -1.5)])
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "the", "log P(word | before it) outweighs half a point of swipe score")
    }

    @Test func theSpellingIsTheLexicons() {
        var (engine, _, document) = engine(reading: [("i", -1)])
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "I")
    }

    @Test func theBarOffersTheOtherReadingsAndAPickReplacesTheSwipedWord() throws {
        var (engine, _, document) = engine(reading: [("hello", -1), ("help", -1.2), ("hell", -3)])
        engine.perform(.character("a"), in: document)
        engine.perform(.space, in: document)
        engine.handle(.swipe(path), in: document)
        #expect(engine.suggestions.map(\.text) == ["help", "hello", "hell"])
        engine.accept(try #require(engine.suggestions.first { $0.text == "help" }), in: document)
        #expect(document.text == "a help ")
    }

    @Test func deleteTakesOutTheWholeSwipedWordAndTheSpaceItAdded() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.perform(.character("a"), in: document)
        engine.handle(.swipe(path), in: document)
        #expect(document.text == "a hello")
        engine.perform(.delete, in: document)
        #expect(document.text == "a")
        engine.perform(.delete, in: document)
        #expect(document.text == "")
    }

    @Test func deleteLeavesASpaceYouTyped() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.perform(.character("a"), in: document)
        engine.perform(.space, in: document)
        engine.handle(.swipe(path), in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "a ")
    }

    @Test func aLetterTypedAfterASwipeGoesOnNormally() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.handle(.swipe(path), in: document)
        engine.perform(.character("s"), in: document)
        #expect(document.text == "hellos")
        engine.perform(.delete, in: document)
        #expect(document.text == "hello", "only the letter, now that something was typed after the swipe")
    }

    @Test func aSwipeIsNotUndoneByDeleteOnceTheCaretMoves() {
        var (engine, _, document) = engine(reading: [("hello", -1)])
        engine.handle(.swipe(path), in: document)
        engine.handle(.cursor(offset: -1), in: document)
        engine.handle(.cursor(offset: 1), in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "hell")
    }

    @Test func theSwipedWordIsKeptAsSwipedAndCountedOnceYouMoveOn() {
        var (engine, _, document) = engine(reading: [("world", -1)])
        engine.handle(.swipe(path), in: document)
        engine.perform(.space, in: document)
        #expect(document.text == "world ")
        #expect(engine.corrector?.memory.count(of: "world") == 1)
    }

    @Test func withSlideToTypeOffNothingIsTyped() {
        var (engine, source, document) = engine(reading: [("hello", -1)])
        engine.settings.slideToType = false
        let typed = engine.handle(.swipe(path), in: document)
        #expect(!typed)
        #expect(document.text.isEmpty)
        #expect(source.keys.isEmpty)
    }

    @Test func aSwipeNoWordFitsTypesNothing() {
        var (engine, _, document) = engine(reading: [])
        let typed = engine.handle(.swipe(path), in: document)
        #expect(!typed)
        #expect(document.text.isEmpty)
    }

    @Test func theDecoderGetsEveryLetterKeyOfTheLiveGrid() throws {
        var (engine, source, document) = engine(reading: [("hello", -1)])
        engine.handle(.swipe(path), in: document)
        let grid = try #require(engine.corrector?.grid)
        #expect(source.keys.count == 26)
        #expect(source.keys["q"] == grid.frame(of: "q"))
    }

    @Test func aSplitKeyboardsRepeatedKeyIsTheOneNearTheSwipe() throws {
        let width = Duo.Screen.openLandscape.keyboardWidth, height = Duo.Screen.openLandscape.size.height
        let context = LayoutContext(device: .phone, layer: .letters, kind: .text, showsGlobe: true, isLandscape: true, isOpen: true, isSplit: true, showsEmoji: true)
        let metrics = KeyboardMetrics.for(.phone, width: width, height: height, split: true)
        let grid = KeyGrid(Layouts.layout(for: context), width: width, metrics: metrics.grid, signature: context.signature)
        var (engine, source, document) = engine(reading: [("hello", -1)])
        engine.corrector?.grid = grid
        let copies = grid.rows.joined().filter { $0.key.label == "v" }.map(\.frame)
        try #require(copies.count == 2)
        for copy in copies {
            let near = [SwipePoint(x: copy.midX, y: copy.midY, time: 0), SwipePoint(x: copy.midX + 1, y: copy.midY, time: 10)]
            engine.handle(.swipe(near), in: document)
            #expect(source.keys["v"] == copy)
        }
        #expect(source.keys.count == 26)
    }
}
