/// One sample of a swipe: where the finger was, in keyboard points, and when, in milliseconds after it touched down.
public struct SwipePoint: Hashable, Sendable {
    public var x, y, time: Double

    public init(x: Double, y: Double, time: Double) {
        self.x = x
        self.y = y
        self.time = time
    }
}

/// Reads a swipe over the letter keys as the words it may have spelled, likeliest first, each scored by a
/// log-probability-like number that knows nothing of the sentence.
public protocol SwipeSource: AnyObject {
    func decode(_ path: [SwipePoint], keys: [String: Rect]) -> [(word: String, score: Double)]
}

/// The word a swipe just typed, which delete takes out whole and the bar offers alternatives to, for as long as the text
/// before the caret is as the swipe left it.
struct Swiped: Hashable {
    var length: Int
    var end: String
    var alternatives: [Suggestion]
}

extension TypingEngine {
    /// How much the sentence counts against the swipe, as a multiple of log P(word | the words before it).
    static let swipeContextWeight = 0.65

    /// Types the likeliest word for a swipe, as a word follows a word: a space first when the caret follows one, none
    /// after. Returns false when nothing was typed.
    mutating func swipe(_ path: [SwipePoint], in document: some TextDocument) -> Bool {
        guard settings.slideToType, panel == nil, layer == .letters, path.count > 1, let swipeSource, let corrector else { return false }
        attach(document)
        let decoded = swipeSource.decode(path, keys: corrector.grid.letterFrames(near: path))
        guard !decoded.isEmpty else { return false }
        lastSpace = nil
        revert = nil
        commitWord(in: document)
        let joins = text.before.last.map { !$0.isWhitespace && !Words.openers.contains($0) } ?? false
        let continues = corrector.continuation(after: text.before + (joins ? " " : ""))
        var seen: Set<String> = []
        let words = decoded
            .map { (word: corrector.spelling(of: $0.word), swipe: $0.score) }
            .map { (word: $0.word, score: $0.swipe + Self.swipeContextWeight * continues($0.word)) }
            .filter { seen.insert($0.word.lowercased()).inserted }
            .sorted { $0.score > $1.score }
            .prefix(3)
            .map { written(cased($0.word)) }
        guard let best = words.first else { return false }
        write((joins ? " " : "") + best, in: document)
        let slots = Array(words.dropFirst().prefix(1)) + [best] + Array(words.dropFirst(2))
        swiped = Swiped(length: best.count + (joins ? 1 : 0), end: text.before, alternatives: slots.map { Suggestion($0, .candidate) })
        refreshShift()
        suggestionsChanged()
        return true
    }

    /// The swipe's word while it's still the last thing typed.
    var swipedWord: Swiped? {
        swiped.flatMap { text.before == $0.end && text.owned >= $0.length ? $0 : nil }
    }

    private func cased(_ word: String) -> String {
        switch shift {
        case .off: word
        case .on: word.prefix(1).uppercased() + word.dropFirst()
        case .locked: word.uppercased()
        }
    }
}

extension Corrector {
    /// A word as the keyboard spells it: a name, or the lexicon's capitals ("I", "London").
    func spelling(of word: String) -> String {
        names[word.lowercased()] ?? lexicon?.canonical(word) ?? word
    }

    /// log P(word | the text before it) as the bar ranks the words that come next. `text` ends where the word starts.
    func continuation(after text: String) -> (String) -> Double {
        guard let lexicon else { return { _ in 0 } }
        let context = Words.context(before: text[text.endIndex...], in: text)
        return languageModel(lexicon).predictor(after: context.previous, earlier: context.earlier, expected: expected(after: text))
    }
}

private extension KeyGrid {
    /// Each letter's key frame; where the halves of a split keyboard both have one, the one nearer the swipe's middle.
    func letterFrames(near path: [SwipePoint]) -> [String: Rect] {
        let x = path.reduce(0) { $0 + $1.x } / Double(path.count), y = path.reduce(0) { $0 + $1.y } / Double(path.count)
        var frames: [String: Rect] = [:]
        for (key, frame) in rows.joined() {
            guard let label = key.label, label.first?.isLetter == true else { continue }
            if let known = frames[label], known.distanceSquared(toX: x, y: y) <= frame.distanceSquared(toX: x, y: y) { continue }
            frames[label] = frame
        }
        return frames
    }
}
