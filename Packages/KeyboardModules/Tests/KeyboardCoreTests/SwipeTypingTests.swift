import Foundation
import Testing
@testable import KeyboardCore

/// The finger going over the keys of `word` on the standard grid, at 8 points a step and 8 ms apart.
private func path(_ word: String, on grid: KeyGrid = .standard) -> [SwipePoint] {
    let centers = word.map { grid.frame(of: String($0))! }.map { (x: $0.midX, y: $0.midY) }
    var points = [SwipePoint(x: centers[0].x, y: centers[0].y, time: 0)]
    for (from, to) in zip(centers, centers.dropFirst()) {
        let steps = max(Int((hypot(to.x - from.x, to.y - from.y) / 0.25).rounded(.up)), 1)
        for step in 1...steps {
            let share = Double(step) / Double(steps)
            points.append(SwipePoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share, time: points.last!.time + 0.008))
        }
    }
    return points
}

private let vocabulary = Lexicon(counts: [("hello", 50), ("world", 30), ("the", 1000), ("a", 800), ("I'm", 100), ("men", 20), ("come", 30), ("home", 30), ("about", 40), ("hell", 5)].map { (word: $0.0, count: Double($0.1)) })

private func engine() -> (engine: TypingEngine, document: TestDocument) {
    var engine = TypingEngine()
    engine.corrector = Corrector(source: vocabulary)
    engine.settings.autoCapitalization = false
    engine.swipeModel = swipe
    let document = TestDocument()
    engine.documentChanged(document)
    return (engine, document)
}

struct SwipeTypingTests {
    @Test func aSwipeTypesItsWordAndTheNextOneFollowsAfterASpace() {
        var (engine, document) = engine()
        let typed = engine.handle(.swipe(path("hello")), in: document)
        #expect(typed)
        #expect(document.text == "hello", "no space before the first word, none after")
        engine.handle(.swipe(path("world")), in: document)
        #expect(document.text == "hello world")
        #expect(engine.text.owned == document.text.count, "the keyboard typed it, so it may correct it")
    }

    @Test func noSpaceGoesInAfterASpaceOrAnOpener() {
        var (engine, document) = engine()
        engine.perform(.space, in: document)
        engine.handle(.swipe(path("hello")), in: document)
        #expect(document.text == " hello")
        let quote = TestDocument("(")
        engine.documentChanged(quote)
        engine.handle(.swipe(path("hello")), in: quote)
        #expect(quote.text == "(hello")
    }

    @Test func aWordInProgressEndsBeforeTheSwipe() {
        var (engine, document) = engine()
        engine.perform(.character("h"), in: document)
        engine.perform(.character("i"), in: document)
        engine.handle(.swipe(path("world")), in: document)
        #expect(document.text == "hi world")
    }

    @Test func capitalsFollowShiftAndCapsLock() {
        var (engine, document) = engine()
        engine.settings.autoCapitalization = true
        engine.handle(.swipe(path("hello")), in: document)
        #expect(document.text == "Hello", "the field's start asks for a capital, as typing does")
        engine.handle(.swipe(path("hello")), in: document)
        #expect(document.text == "Hello hello")

        let other = TestDocument()
        engine.documentChanged(other)
        engine.perform(.capsLock, in: other)
        engine.handle(.swipe(path("hello")), in: other)
        #expect(other.text == "HELLO")
    }

    @Test func theSpellingIsTheLexicons() {
        var (engine, document) = engine()
        engine.handle(.swipe(path("im")), in: document)
        #expect(document.text == "I’m", "the apostrophe costs no swipe, and is curled as typed ones are")
    }

    @Test func theBarOffersTheOtherReadingsAndAPickReplacesTheSwipedWord() throws {
        var (engine, document) = engine()
        engine.perform(.character("a"), in: document)
        engine.perform(.space, in: document)
        engine.handle(.swipe(path("hello")), in: document)
        let bar = engine.suggestions.map(\.text)
        #expect(bar.count == 3 && !bar.contains("hello"), "\(bar)")
        engine.accept(try #require(engine.suggestions.first), in: document)
        #expect(document.text != "a hello" && document.text.hasSuffix(" "))
    }

    @Test func deleteTakesOutTheWholeSwipedWordAndTheSpaceItAdded() {
        var (engine, document) = engine()
        engine.perform(.character("a"), in: document)
        engine.handle(.swipe(path("hello")), in: document)
        #expect(document.text == "a hello")
        engine.perform(.delete, in: document)
        #expect(document.text == "a")
        engine.perform(.delete, in: document)
        #expect(document.text == "")
    }

    @Test func deleteLeavesASpaceYouTyped() {
        var (engine, document) = engine()
        engine.perform(.character("a"), in: document)
        engine.perform(.space, in: document)
        engine.handle(.swipe(path("hello")), in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "a ")
    }

    @Test func aLetterTypedAfterASwipeGoesOnNormally() {
        var (engine, document) = engine()
        engine.handle(.swipe(path("hello")), in: document)
        engine.perform(.character("s"), in: document)
        #expect(document.text == "hellos")
        engine.perform(.delete, in: document)
        #expect(document.text == "hello", "only the letter, now that something was typed after the swipe")
    }

    @Test func aSwipeIsNotUndoneByDeleteOnceTheCaretMoves() {
        var (engine, document) = engine()
        engine.handle(.swipe(path("hello")), in: document)
        engine.handle(.cursor(offset: -1), in: document)
        engine.handle(.cursor(offset: 1), in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "hell")
    }

    @Test func theSwipedWordIsKeptAsSwipedAndCountedOnceYouMoveOn() {
        var (engine, document) = engine()
        engine.handle(.swipe(path("world")), in: document)
        engine.perform(.space, in: document)
        #expect(document.text == "world ")
        #expect(engine.corrector?.memory.count(of: "world") == 1)
    }

    @Test func withSlideToTypeOffNothingIsTyped() {
        var (engine, document) = engine()
        engine.settings.slideToType = false
        let typed = engine.handle(.swipe(path("hello")), in: document)
        #expect(!typed)
        #expect(document.text.isEmpty)
    }

    @Test func aTouchTooShortToReadTypesNothing() {
        var (engine, document) = engine()
        let typed = engine.handle(.swipe([SwipePoint(x: 1, y: 1, time: 0)]), in: document)
        #expect(!typed)
        #expect(document.text.isEmpty)
    }

    @Test func wordsYouTaughtTheKeyboardCanBeSwiped() {
        var (engine, document) = engine()
        for _ in 0..<2 { engine.corrector?.record("zorp", after: "", earlier: nil) }
        engine.corrector?.setNames(["Quentin"])
        engine.handle(.swipe(path("zorp")), in: document)
        #expect(document.text == "zorp")
        engine.handle(.swipe(path("quentin")), in: document)
        #expect(document.text == "zorp Quentin")
    }

    @Test func aSplitKeyboardsRepeatedKeyIsTheOneNearTheSwipe() throws {
        let width = Duo.Screen.openLandscape.keyboardWidth, height = Duo.Screen.openLandscape.size.height
        let context = LayoutContext(device: .phone, layer: .letters, kind: .text, showsGlobe: true, isLandscape: true, isOpen: true, isSplit: true, showsEmoji: true)
        let metrics = KeyboardMetrics.for(.phone, width: width, height: height, split: true)
        let grid = KeyGrid(Layouts.layout(for: context), width: width, metrics: metrics.grid, signature: context.signature)
        let copies = grid.rows.joined().filter { $0.key.label == "v" }.map(\.frame)
        try #require(copies.count == 2)
        let alphabet = (0..<26).map { String(UnicodeScalar(UInt8(97 + $0))) }
        let v = alphabet.firstIndex(of: "v")!
        for copy in copies {
            let near = [SwipePoint(x: copy.midX, y: copy.midY, time: 0), SwipePoint(x: copy.midX + 1, y: copy.midY, time: 0.01)]
            let layout = try #require(grid.swipeLayout(near: near))
            let box = try #require(SwipeLayout(grid: grid)).frame
            #expect(abs(layout.centers[v].x * box.width + box.x - copy.midX) < 0.001)
        }
    }

    /// What a swipe costs the main thread, from the touch lifting to the word typed: `swift test -c release --filter decodeCost`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIPE_LATENCY"] != nil))
    func decodeCost() {
        var (engine, document) = engine()
        let words = ["hello", "world", "help", "the", "come", "home", "about"]
        let paths = words.map { path($0) }
        let clock = ContinuousClock()
        var milliseconds: [Double] = []
        for round in 0..<10 {
            for path in paths {
                let start = clock.now
                engine.handle(.swipe(path), in: document)
                let spent = clock.now - start
                if round > 0 { milliseconds.append(Double(spent.components.seconds) * 1000 + Double(spent.components.attoseconds) / 1e15) }
            }
        }
        milliseconds.sort()
        print("EVAL latency swipe engine ms: median \(milliseconds[milliseconds.count / 2]) p95 \(milliseconds[milliseconds.count * 95 / 100])")
    }
}
