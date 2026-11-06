import KeyboardCore
import KeyboardEnglish
import KeyboardUI
import UIKit

/// `-iikbRankingProbe YES` (`scripts/rankprobe`): types the phrases in `Documents/probe-phrases.txt` through `TypingEngine`
/// with seeded noisy taps the way `Evaluation.latency()` does, timing every letter-up and space-up on this iPhone, and
/// logs their median, p95, p99 and max to `Documents/rank.log`. Keep the screen unlocked while it runs.
enum RankingProbe {
    static var asked: Bool { UserDefaults.standard.bool(forKey: "iikbRankingProbe") }

    @MainActor static func runIfAsked() {
        guard asked else { return }
        DispatchQueue.main.async {
            try? run()
            Probe.end()
        }
    }

    @MainActor private static func run() throws {
        let phrases = try String(contentsOf: .documentsDirectory.appendingPathComponent("probe-phrases.txt"), encoding: .utf8) // file: probe input
            .split(separator: "\n").prefix(100).map { $0.lowercased() }
        let width = 402.0, noise = 0.2
        let grid = KeyGrid(Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)), width: width,
                           metrics: KeyboardMetrics.phone(width: width).grid, signature: "probe")
        let corrector = Corrector(source: Lexicon.english, network: .english)
        corrector.grid = grid
        var random = SeededRandom(seed: 2026)
        var letters: [Duration] = [], spaces: [Duration] = []
        let clock = ContinuousClock()
        for phrase in phrases {
            var engine = TypingEngine(traits: InputTraits(autocapitalization: .none))
            engine.corrector = corrector
            let document = ProbeDocument()
            engine.suggestionsChanged()
            for character in phrase + " " {
                let frame = grid.frame(of: String(character))!
                let pitchX = character == " " ? 45.0 : frame.width + 6, pitchY = frame.height + 11
                let x = frame.midX + random.gaussian() * noise * pitchX, y = frame.midY + random.gaussian() * noise * pitchY
                guard let hit = engine.key(atX: x, y: y, in: grid), let label = grid.rows[hit.row][hit.key].key.label else { continue }
                let up = clock.measure {
                    engine.perform(label == " " ? .space : .character(label), in: document, tap: Tap(x: x, y: y, key: label))
                }
                if label == " " { spaces.append(up) } else { letters.append(up) }
                _ = engine.documentChanged(document)
            }
            engine.endSession()
        }
        let log = "ranking probe \(Date.now.formatted()) thermal \(ProcessInfo.processInfo.thermalState.rawValue) keys=\(letters.count + spaces.count)\n"
            + "\(summary("letter up", letters))\n\(summary("space up", spaces))\ndone\n"
        try log.write(to: .documentsDirectory.appendingPathComponent("rank.log"), atomically: true, encoding: .utf8) // file: probe log
    }

    private static func summary(_ name: String, _ samples: [Duration]) -> String {
        let ms = samples.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1000 }.sorted()
        let at = { (q: Double) in String(format: "%.2f", ms[min(ms.count - 1, Int(Double(ms.count) * q))]) }
        return "\(name) ms median=\(at(0.5)) p95=\(at(0.95)) p99=\(at(0.99)) max=\(at(1))"
    }
}

private final class ProbeDocument: TextDocument {
    private(set) var text = ""
    var textBeforeInput: String? { text }
    var textAfterInput: String? { nil }
    func insert(_ value: String) { text += value }
    func deleteBackward(_ count: Int) { text.removeLast(min(count, text.count)) }
    func moveCursor(by offset: Int) {}
}

private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func uniform() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }

    mutating func gaussian() -> Double {
        sqrt(-2 * log(max(uniform(), .leastNormalMagnitude))) * cos(2 * .pi * uniform())
    }
}
