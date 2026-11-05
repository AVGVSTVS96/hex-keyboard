import Foundation
import Testing
@testable import KeyboardCore

/// scripts/fieldbench's scorer, where prose is a control that must type what it does today: set FIELD_BENCH to the speech model's writing of Tools/FieldBench's cases, and FIELD_CASES to cases.jsonl.
struct FieldBenchTests {
    private struct Case: Decodable { var id, field, expected: String }
    private struct Row: Decodable { var id, text: String }

    private static let traits: [String: InputTraits] = [
        "email": InputTraits(kind: .email), "url": InputTraits(kind: .url), "search": InputTraits(kind: .webSearch),
        "phone": InputTraits(kind: .number, content: .telephoneNumber), "code": InputTraits(kind: .number, content: .oneTimeCode),
        "zip": InputTraits(kind: .number, content: .postalCode),
    ]

    /// Without Casual's dropped last period, which no field's answer depends on.
    private static func closed(_ text: String) -> String { text.hasSuffix(".") ? String(text.dropLast()) : text }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIELD_BENCH"] != nil))
    func score() throws {
        let rows = try String(contentsOfFile: ProcessInfo.processInfo.environment["FIELD_BENCH"]!, encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Row.self, from: Data($0.utf8)) }
        let cases = try Dictionary(uniqueKeysWithValues: String(contentsOfFile: ProcessInfo.processInfo.environment["FIELD_CASES"]!, encoding: .utf8).split(separator: "\n")
            .map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }.map { ($0.id, $0) })
        var score: [String: (before: Int, after: Int, total: Int)] = [:]
        var misses: [String] = []
        for row in rows {
            let id = String(row.id.split(separator: "-").dropLast().joined(separator: "-"))
            guard let expected = cases[id] else { continue }
            let writing = DictationWriting()
            let styled = writing.written(row.text)
            let before = writing.typed(row.text, lexicon: testLexicon)
            let wrote = { (traits: InputTraits) -> String in
                var engine = TypingEngine(traits: traits)
                engine.corrector = Corrector(source: testLexicon)
                let document = TestDocument("")
                engine.handle(.dictated(styled, plain: row.text), in: document)
                return document.text
            }
            let after = wrote(Self.traits[expected.field] ?? InputTraits())
            let wanted = expected.field == "prose" ? before : expected.expected
            let hit = { (typed: String) in Self.closed(typed) == Self.closed(wanted) ? 1 : 0 }
            let at = score[expected.field] ?? (0, 0, 0)
            score[expected.field] = (at.before + hit(before), at.after + hit(after), at.total + 1)
            if Self.closed(after) != Self.closed(wanted) { misses.append("\(row.id): heard \"\(row.text)\" typed \"\(after)\" wanted \"\(wanted)\"") }
        }
        for (field, at) in score.sorted(by: { $0.key < $1.key }) {
            print("FIELDBENCH \(field.padding(toLength: 12, withPad: " ", startingAt: 0)) before \(at.before)/\(at.total)  after \(at.after)/\(at.total)")
        }
        let all = score.values.reduce((0, 0, 0)) { ($0.0 + $1.before, $0.1 + $1.after, $0.2 + $1.total) }
        print("FIELDBENCH all          before \(all.0)/\(all.2)  after \(all.1)/\(all.2)")
        for miss in misses { print("FIELDMISS \(miss)") }
    }
}
