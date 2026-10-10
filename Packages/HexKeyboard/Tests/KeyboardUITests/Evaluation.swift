import Foundation
import Testing
import KeyboardCore
@testable import KeyboardUI

/// Types the MacKenzie & Soukoreff phrase set through `TypingEngine` with simulated taps and reports word accuracy.
///
/// Three keyboards: (a) nearest-key hit-testing + `UITextChecker` (the old default), (b) Hex's decoder with the touch
/// model held at its prior, (c) the same decoder learning from every word it commits.
@MainActor
struct Evaluation {
    static let width = 402.0
    static let noiseLevels = [0.0, 0.15, 0.25, 0.35]

    enum Keyboard: String, CaseIterable {
        case baseline, decoder, learning
    }

    static func phrases() throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: "phrases", withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { $0.lowercased() }
    }

    @Test func noise() throws {
        let phrases = try Self.phrases()
        for keyboard in Keyboard.allCases {
            for noise in Self.noiseLevels {
                var user = SimulatedUser(width: Self.width, noise: noise, seed: 2026)
                var session = Session(keyboard, grid: user.grid)
                for phrase in phrases {
                    session.startPhrase()
                    for word in phrase.split(separator: " ") { session.type(String(word), by: &user, tappingSpace: false) }
                }
                print("EVAL noise=\(noise) keyboard=\(keyboard.rawValue) \(session.score)")
            }
        }
    }

    @Test func biasedThumbs() throws {
        let phrases = try Self.phrases()
        let block = 500
        for keyboard in Keyboard.allCases {
            var user = SimulatedUser(width: Self.width, noise: 0.2, seed: 7, bias: SimulatedUser.thumbs)
            var session = Session(keyboard, grid: user.grid)
            var curve: [String] = []
            for _ in 0..<2 {
                for phrase in phrases {
                    session.startPhrase()
                    for word in phrase.split(separator: " ") {
                        session.type(String(word), by: &user, tappingSpace: true)
                        if session.score.words % block == 0 { curve.append(session.window.summary); session.window = Score() }
                    }
                }
            }
            print("EVAL thumbs keyboard=\(keyboard.rawValue) total: \(session.score)")
            print("EVAL thumbs keyboard=\(keyboard.rawValue) per \(block) words (raw/final): \(curve.joined(separator: " "))")
            if keyboard == .learning, let corrector = session.engine.corrector {
                let centers = ["m", "b", "o", "e"].map { label in
                    let c = corrector.memory.touches.center(of: label, on: user.grid)
                    return "\(label)=(\(String(format: "%+.2f", c.x)),\(String(format: "%+.2f", c.y)))"
                }
                print("EVAL thumbs learned centers: \(centers.joined(separator: " "))")
            }
        }
    }
}

@MainActor
struct Session {
    let keyboard: Evaluation.Keyboard
    let grid: KeyGrid
    var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
    var document = Document()
    var score = Score()
    var window = Score()

    init(_ keyboard: Evaluation.Keyboard, grid: KeyGrid) {
        self.keyboard = keyboard
        self.grid = grid
        let source: any CandidateSource = keyboard == .baseline ? TextCheckerSource(language: "en-US") : Lexicon.english!
        let corrector = Corrector(source: source)
        corrector.grid = grid
        engine.corrector = corrector
    }

    mutating func startPhrase() {
        engine.endSession()
        let corrector = engine.corrector
        engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
        engine.corrector = corrector
        document = Document()
    }

    mutating func type(_ word: String, by user: inout SimulatedUser, tappingSpace: Bool) {
        let start = document.text.count
        var typed = ""
        for character in word + (tappingSpace ? " " : "") {
            let (x, y) = user.tap(character)
            let hit = keyboard == .baseline ? grid.index(atX: x, y: y) : engine.key(atX: x, y: y, in: grid, document: document)
            guard let hit, let label = grid.rows[hit.row][hit.key].key.label, tappingSpace || label != " " else { continue }
            if character != " " { typed += label }
            if character == " " { shown = engine.suggestions.map { $0.text.lowercased() } }
            engine.perform(label == " " ? .space : .character(label), in: document, tap: Tap(x: x, y: y, key: label))
        }
        if !tappingSpace {
            shown = engine.suggestions.map { $0.text.lowercased() }
            engine.perform(.space, in: document)
        }
        if keyboard == .decoder {
            engine.endSession()
            engine.corrector?.memory.touches = TouchModel()
        }
        let final = String(document.text.dropFirst(start)).trimmingCharacters(in: .whitespaces).lowercased()
        score.add(word: word, typed: typed, final: final, shown: shown)
        window.add(word: word, typed: typed, final: final, shown: shown)
    }

    private var shown: [String] = []
}

@MainActor
struct SimulatedUser {
    let grid: KeyGrid
    let noise: Double
    let bias: [Character: (x: Double, y: Double)]
    var random: SplitMix64

    /// Offsets in key pitches: m drifts toward n, b toward the space bar, o toward i, and every tap lands a bit low.
    static let thumbs: [Character: (x: Double, y: Double)] = ["m": (-0.4, 0.1), "b": (0, 0.55), "o": (-0.45, 0.1), "*": (0, 0.1)]

    init(width: Double, noise: Double, seed: UInt64, bias: [Character: (x: Double, y: Double)] = [:]) {
        let layout = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters))
        grid = KeyGrid(layout, width: width, metrics: KeyboardMetrics.phone(width: width).grid, signature: "eval")
        self.noise = noise
        self.bias = bias
        random = SplitMix64(seed: seed)
    }

    mutating func tap(_ character: Character) -> (Double, Double) {
        let frame = grid.frame(of: String(character))!
        let pitchX = character == " " ? 45.0 : frame.width + 6, pitchY = frame.height + 11
        let offset = bias[character] ?? bias["*"] ?? (0, 0)
        return (frame.midX + (offset.x + random.gaussian() * noise) * pitchX,
                frame.midY + (offset.y + random.gaussian() * noise) * pitchY)
    }
}

struct Score: CustomStringConvertible {
    var words = 0, raw = 0, corrected = 0, topThree = 0, fixed = 0, broken = 0
    var brokenWords: [String] = []

    mutating func add(word: String, typed: String, final: String, shown: [String]) {
        words += 1
        if typed == word { raw += 1 }
        if final == word { corrected += 1 }
        if shown.contains(word) { topThree += 1 }
        if typed != word, final == word { fixed += 1 }
        if typed == word, final != word {
            broken += 1
            brokenWords.append("\(word)→\(final)")
        }
    }

    private func percent(_ count: Int) -> String {
        String(format: "%.1f%%", Double(count) * 100 / Double(max(words, 1)))
    }

    var summary: String { "\(percent(raw))/\(percent(corrected))" }

    var description: String {
        "words=\(words) raw=\(percent(raw)) autocorrect=\(percent(corrected)) top3=\(percent(topThree)) fixed=\(fixed) broken=\(broken) \(brokenWords.prefix(8))"
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func gaussian() -> Double {
        sqrt(-2 * log(max(uniform(), .leastNormalMagnitude))) * cos(2 * .pi * uniform())
    }
}

final class Document: TextDocument {
    private(set) var text = ""

    var textBeforeInput: String? { text }
    var textAfterInput: String? { nil }
    func insert(_ value: String) { text += value }
    func deleteBackward(_ count: Int) { text.removeLast(min(count, text.count)) }
    func moveCursor(by offset: Int) {}
}
