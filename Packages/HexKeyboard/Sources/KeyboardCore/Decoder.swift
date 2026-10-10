/// How well one tap fits each letter: log densities per square point, indexed a–z then the apostrophe, plus the
/// density of a stray tap (one that meant no letter at all).
public struct TapEvidence: Hashable, Sendable {
    public var letters: [Double]
    public var stray: Double

    public init(letters: [Double], stray: Double) {
        self.letters = letters
        self.stray = stray
    }

    static func exact(_ letter: UInt8) -> TapEvidence {
        var letters = [Double](repeating: -.infinity, count: Lexicon.alphabet)
        if let index = Lexicon.index(of: letter) { letters[index] = 0 }
        return TapEvidence(letters: letters, stray: -.infinity)
    }

    var best: Double { letters.max() ?? 0 }
}

/// Finds the words a sequence of taps most likely meant: exact A* over the lexicon trie, scoring each word as
/// P(taps | word) × P(word). A word may also differ by one missed, extra or swapped tap (about 1 in 100 keystrokes),
/// and whether you bother typing a contraction's apostrophe is a coin flip. The subtree mass stored in the trie bounds every word below a node, so the search returns the true
/// best words first.
struct Decoder {
    let lexicon: Lexicon

    static let editLogProbability = Math.log(0.01)
    static let apostropheLogProbability = Math.log(0.5)
    static let budget = 6000

    struct Result: Hashable {
        var word: String
        var logLikelihood: Double
        var logPrior: Double
        var isCompletion: Bool
    }

    private struct State {
        var node: Lexicon.Node
        var tap: Int
        var edits: Int
        var completing: Bool
        var score: Double
        var spelling: [UInt8]
        var terminal: Bool
    }

    /// The `count` likeliest words, completions included, and at least the likeliest word of exactly the typed length.
    func decode(_ taps: [TapEvidence], count: Int = 4) -> [Result] {
        guard !taps.isEmpty else { return [] }
        let best = taps.map(\.best)
        let offset = best.reduce(0, +)
        var heap = Heap<State>()
        var found: [Result] = []
        var seen: Set<String> = []
        var exact = 0, pops = 0

        func push(_ state: State) {
            let bound = state.terminal ? state.score : state.score + lexicon.logMass(state.node)
            if bound > -.infinity { heap.push(state, priority: bound) }
        }
        func emit(_ state: State) {
            guard let word = lexicon.logWord(state.node) else { return }
            var terminal = state
            terminal.terminal = true
            terminal.score += word
            push(terminal)
        }
        push(State(node: lexicon.root, tap: 0, edits: 0, completing: false, score: 0, spelling: [], terminal: false))

        while found.count < count || exact == 0, pops < Self.budget, let state = heap.pop() {
            pops += 1
            if state.terminal {
                let word = String(decoding: state.spelling, as: UTF8.self)
                guard seen.insert(word).inserted else { continue }
                let logPrior = lexicon.logWord(state.node) ?? 0
                found.append(Result(word: lexicon.canonical(word) ?? word, logLikelihood: state.score - logPrior + offset, logPrior: logPrior, isCompletion: state.completing))
                if !state.completing { exact += 1 }
                continue
            }
            let i = state.tap
            if i == taps.count, state.spelling.count > 0 {
                if !state.completing { emit(state) }
            }
            if i < taps.count, state.edits == 0 {
                push(State(node: state.node, tap: i + 1, edits: 1, completing: false,
                           score: state.score + taps[i].stray - best[i] + Self.editLogProbability, spelling: state.spelling, terminal: false))
            }
            for child in lexicon.children(state.node) {
                let letter = lexicon.letter(child)
                guard let index = Lexicon.index(of: letter) else { continue }
                let spelling = state.spelling + [letter]
                if i == taps.count {
                    let next = State(node: child, tap: i, edits: state.edits, completing: true, score: state.score, spelling: spelling, terminal: false)
                    if lexicon.logWord(child) != nil { emit(next) }
                    push(next)
                    continue
                }
                guard !state.completing else { continue }
                push(State(node: child, tap: i + 1, edits: state.edits, completing: false,
                           score: state.score + taps[i].letters[index] - best[i], spelling: spelling, terminal: false))
                if letter == 39 || state.edits == 0 {
                    push(State(node: child, tap: i, edits: state.edits + (letter == 39 ? 0 : 1), completing: false,
                               score: state.score + (letter == 39 ? Self.apostropheLogProbability : Self.editLogProbability), spelling: spelling, terminal: false))
                }
                if state.edits == 0, i + 1 < taps.count {
                    for grandchild in lexicon.children(child) {
                        guard let second = Lexicon.index(of: lexicon.letter(grandchild)), second != index else { continue }
                        let swapped = taps[i].letters[second] + taps[i + 1].letters[index] - best[i] - best[i + 1]
                        push(State(node: grandchild, tap: i + 2, edits: 1, completing: false,
                                   score: state.score + swapped + Self.editLogProbability, spelling: spelling + [lexicon.letter(grandchild)], terminal: false))
                    }
                }
            }
        }
        return found
    }

    /// Scores one word against taps the way the search does, for words outside the lexicon. `completing` lets the
    /// taps cover only the start of the word.
    static func logLikelihood(of word: String, given taps: [TapEvidence], completing: Bool = false) -> Double {
        let letters = Array(word.lowercased().utf8).compactMap(Lexicon.index(of:))
        guard letters.count == word.utf8.count else { return -.infinity }
        let n = letters.count, m = taps.count
        var rows = [[Double]](repeating: [Double](repeating: -.infinity, count: m + 1), count: n + 1)
        rows[0][0] = 0
        for i in 0...n {
            for j in 0...m where !(i == 0 && j == 0) {
                var value = -Double.infinity
                if i > 0, j > 0 { value = max(value, rows[i - 1][j - 1] + taps[j - 1].letters[letters[i - 1]]) }
                if i > 0 { value = max(value, rows[i - 1][j] + (letters[i - 1] == 26 ? apostropheLogProbability : editLogProbability)) }
                if j > 0 { value = max(value, rows[i][j - 1] + taps[j - 1].stray + editLogProbability) }
                if i > 1, j > 1, letters[i - 1] != letters[i - 2] {
                    value = max(value, rows[i - 2][j - 2] + taps[j - 2].letters[letters[i - 1]] + taps[j - 1].letters[letters[i - 2]] + editLogProbability)
                }
                rows[i][j] = value
            }
        }
        return completing ? (1..<n).map { rows[$0][m] }.max() ?? -.infinity : rows[n][m]
    }
}

struct Heap<Element> {
    private var items: [(priority: Double, element: Element)] = []

    mutating func push(_ element: Element, priority: Double) {
        items.append((priority, element))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[parent].priority < items[child].priority else { break }
            items.swapAt(parent, child)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = parent * 2 + 1, right = left + 1
            var largest = parent
            if left < items.count, items[left].priority > items[largest].priority { largest = left }
            if right < items.count, items[right].priority > items[largest].priority { largest = right }
            guard largest != parent else { break }
            items.swapAt(parent, largest)
            parent = largest
        }
        return top.element
    }
}
