import Foundation
import Testing
@testable import KeyboardCore

/// scripts/gate: everyday text typed through the engine over the shipped lexicon and network, each key tapped at its
/// center as scripts/applebar taps Apple's, and the words the bar must show after it (scripts/gate.txt, in GATE). `phone` runs on the iPhone's own network and memory (GATE_NETWORK,
/// GATE_MEMORY, from the backup), which are private, so its failures print without their bars.
struct GateTests {
    private struct Saved: Decodable { var memory: TypingMemory }

    private static let environment = ProcessInfo.processInfo.environment
    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/KeyboardEnglish/Resources")
    private static let names = ["M3", "M5", "A1", "B2", "Mo", "Mya", "Myles", "Meg", "Mel", "Yu", "Yousef", "Yvonne", "Ana", "Andy",
                                "Hana", "Kenji", "Tom", "Will", "Mark", "May", "Grace", "Joy", "Art", "Sunny", "Iris", "Theo", "Ian", "Pat"]

    private static func bytes(_ path: String) -> [UInt8] { [UInt8](FileManager.default.contents(atPath: path)!) }

    @Test(.enabled(if: environment["GATE"] != nil), arguments: ["fresh", "names", "phone"])
    func bar(_ condition: String) throws {
        let phone = condition == "phone"
        if phone, Self.environment["GATE_MEMORY"] == nil { return print("GATE phone: no phone state here") }
        let lexicon = Lexicon(bytes: Bytes(Self.bytes(Self.resources.appending(path: "en.lexicon").path)))!
        let network = Network(bytes: Self.bytes(phone ? Self.environment["GATE_NETWORK"]! : Self.resources.appending(path: "en.network").path))!
        let emoji = try EmojiCatalog(text: String(contentsOf: Self.resources.appending(path: "emoji.txt"), encoding: .utf8))
        let corrector = Corrector(source: lexicon, network: network)
        if condition != "fresh" { corrector.setNames(Self.names) }
        var memory = TypingMemory()
        if phone {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
            memory = try decoder.decode(Saved.self, from: Data(contentsOf: URL(fileURLWithPath: Self.environment["GATE_MEMORY"]!))).memory
        }
        let cases = try String(contentsOfFile: Self.environment["GATE"]!, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") }
        var failed: [String] = [], missing: [String] = []
        for line in cases {
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            let required = !parts[0].hasPrefix("?")
            let text = String(parts[0].drop { $0 == "?" }), wanted = parts[1].split(separator: " ").map(String.init)
            corrector.changeMemory { $0 = memory }
            var engine = TypingEngine()
            engine.corrector = corrector
            engine.emojiCatalog = emoji
            engine.defersSuggestions = true
            let document = TestDocument()
            for character in text {
                let key = String(character), center = corrector.grid.frame(of: key).map { Tap(x: $0.midX, y: $0.midY, key: key) }
                engine.perform(character == " " ? .space : .character(key), in: document, tap: center)
            }
            if var job = engine.suggestionJob() { job.run(); engine.finish(job) }
            let shown = engine.suggestions.prefix(engine.emojiSuggestions.isEmpty ? 3 : 2)
            let words = shown.filter { $0.kind != .literal }.map { $0.text.lowercased().replacingOccurrences(of: "’", with: "'") }
            guard !wanted.allSatisfy(words.contains) else { continue }
            let bar = shown.map(\.title) + engine.emojiSuggestions.prefix(1)
            let line = "\"\(text)\" wants \(wanted.joined(separator: " "))" + (phone ? "" : ", bar: \(bar.joined(separator: " "))")
            if required { failed.append("GATE \(condition) FAIL " + line) } else { missing.append("GATE \(condition) NOT YET " + line) }
        }
        let passed = cases.count - failed.count - missing.count
        print((["GATE \(condition): \(passed)/\(cases.count) pass"] + failed + missing).joined(separator: "\n"))
        #expect(failed.count == 0)
    }
}
