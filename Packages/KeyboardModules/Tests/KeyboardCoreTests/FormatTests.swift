import Foundation
import Testing
@testable import KeyboardCore

/// scripts/formats: what a dictation types for what Parakeet writes (scripts/formats.txt), through the app's writing
/// and Dictionary and then the keyboard's reading, over the shipped lexicon.
struct FormatTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let fields: [String: InputTraits] = [
        "email": InputTraits(kind: .email), "url": InputTraits(kind: .url), "search": InputTraits(kind: .webSearch),
        "decimal": InputTraits(kind: .decimal),
    ]

    @Test func dictationTypesEachFormatAsWritten() throws {
        let lexicon = Lexicon(bytes: Bytes([UInt8](FileManager.default.contents(atPath: Self.root.appending(path: "Packages/KeyboardModules/Sources/KeyboardEnglish/Resources/en.lexicon").path)!)))!
        let vocabulary = Vocabulary([Vocabulary.Term("kestrel.run"), Vocabulary.Term("tamsin", heardAs: ["tamsen"])])
        let corrector = Corrector(source: lexicon)
        corrector.changeMemory { memory in
            let typed = [("Opus", "with", 6), ("Corvina", "to", 8), ("iikb", "on", 10), ("Niri", "on", 5), ("Autofork", "on", 5),
                         ("Also", "", 3), ("also", "it", 20), ("Sure", "", 5), ("Thanks", "", 6), ("Nice", "", 5), ("Same", "", 5), ("quillon", "a", 2)]
            for (word, previous, times) in typed {
                for _ in 0 ..< times { memory.record(word, after: previous) }
            }
        }
        let cases = try String(contentsOf: Self.root.appending(path: "scripts/formats.txt"), encoding: .utf8)
            .split(separator: "\n").filter { !$0.hasPrefix("#") }
        var failed: [String] = []
        for line in cases {
            let parts = line.components(separatedBy: " | ")
            let field = parts.count == 3 ? parts[0] : nil, heard = parts[parts.count - 2], wanted = parts[parts.count - 1]
            let written = field.flatMap { $0.hasPrefix("> ") ? String($0.dropFirst(2)) + " " : nil } ?? ""
            var engine = TypingEngine(traits: field.flatMap { Self.fields[$0] } ?? InputTraits(autocapitalization: .sentences))
            engine.corrector = corrector
            let document = TestDocument(written)
            engine.handle(.dictated(vocabulary.corrected(DictationWriting().written(heard), lexicon: lexicon),
                                    plain: vocabulary.corrected(heard, lexicon: lexicon)), in: document)
            if document.text != wanted { failed.append("FORMAT FAIL \"\(heard)\" typed \"\(document.text)\", wants \"\(wanted)\"") }
        }
        print((["FORMAT: \(cases.count - failed.count)/\(cases.count) pass"] + failed).joined(separator: "\n"))
        #expect(failed.count == 0)
    }
}
