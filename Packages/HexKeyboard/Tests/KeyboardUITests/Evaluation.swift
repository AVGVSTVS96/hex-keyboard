import Foundation
import Testing
import KeyboardCore
@testable import KeyboardUI

@MainActor
struct Evaluation {
    static let width = 402.0
    static let noiseLevels = [0.0, 0.15, 0.25, 0.35]

    @Test func baseline() throws {
        let url = try #require(Bundle.module.url(forResource: "phrases", withExtension: "txt"))
        let phrases = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { $0.lowercased() }
        let keyboard = TapSimulator(width: Self.width)
        for noise in Self.noiseLevels {
            var score = Score()
            var random = SplitMix64(seed: 2026)
            let corrector = Corrector(source: TextCheckerSource(language: "en-US"))
            for phrase in phrases {
                var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
                engine.corrector = corrector
                let document = Document()
                for word in phrase.split(separator: " ") {
                    let typed = keyboard.type(String(word), noise: noise, into: &engine, document: document, random: &random)
                    let shown = engine.suggestions.map { $0.text.lowercased() }
                    engine.perform(.space, in: document)
                    let final = document.text.split(separator: " ").last.map(String.init) ?? ""
                    score.add(word: String(word), typed: typed, final: final.lowercased(), shown: shown)
                }
            }
            print("EVAL noise=\(noise) \(score)")
        }
    }
}

@MainActor
struct TapSimulator {
    let centers: [Character: Rect]
    let grid: KeyGrid

    init(width: Double) {
        let layout = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters))
        grid = KeyGrid(layout, width: width, metrics: KeyboardMetrics.phone(width: width).grid)
        var centers: [Character: Rect] = [:]
        for row in grid.rows {
            for (key, frame) in row {
                if case .character(let value) = key.action, let character = value.first { centers[character] = frame }
            }
        }
        self.centers = centers
    }

    func type(_ word: String, noise: Double, into engine: inout TypingEngine, document: Document, random: inout SplitMix64) -> String {
        var typed = ""
        for character in word {
            guard let frame = centers[character] else { continue }
            let pitchX = frame.width + 6, pitchY = frame.height + 11
            let x = frame.midX + random.gaussian() * noise * pitchX
            let y = frame.midY + random.gaussian() * noise * pitchY
            guard let key = grid.key(atX: x, y: y), case .character(let value) = key.action else { continue }
            engine.perform(.character(value), in: document, tap: Tap(x: x, y: y, key: value))
            typed += value
        }
        return typed
    }
}

struct Score: CustomStringConvertible {
    var words = 0, raw = 0, corrected = 0, topThree = 0, fixed = 0, broken = 0

    mutating func add(word: String, typed: String, final: String, shown: [String]) {
        words += 1
        if typed == word { raw += 1 }
        if final == word { corrected += 1 }
        if shown.contains(word) { topThree += 1 }
        if typed != word, final == word { fixed += 1 }
        if typed == word, final != word { broken += 1 }
    }

    private func percent(_ count: Int) -> String {
        String(format: "%.1f%%", Double(count) * 100 / Double(max(words, 1)))
    }

    var description: String {
        "words=\(words) raw=\(percent(raw)) autocorrect=\(percent(corrected)) top3=\(percent(topThree)) fixed=\(fixed) broken=\(broken)"
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
