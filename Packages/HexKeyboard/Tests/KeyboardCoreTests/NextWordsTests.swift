import Testing
@testable import KeyboardCore

/// Encodes a table the way `scripts/nextwords.py` does.
func nextWords(_ table: [String: (backoff: Double, followers: [(String, Double)])]) -> NextWords {
    let entries = table.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { context -> [UInt8] in
        let (backoff, followers) = table[context]!
        var entry = [UInt8(context.utf8.count)] + Array(context.utf8) + [UInt8((backoff * 255).rounded()), UInt8(followers.count)]
        for (word, p) in followers {
            entry += [UInt8(word.utf8.count)] + Array(word.utf8) + [UInt8(max(1, (-Math.log(p) * 10).rounded()))]
        }
        return entry
    }
    func u32(_ value: Int) -> [UInt8] { (0..<4).map { UInt8((value >> ($0 * 8)) & 0xff) } }
    var bytes = Array("HXN1".utf8) + u32(entries.count)
    var offset = 8 + 4 * entries.count
    for entry in entries {
        bytes += u32(offset)
        offset += entry.count
    }
    return NextWords(bytes: bytes + entries.joined())!
}

private let table = nextWords([
    "": (0.5, [("I", 0.2), ("the", 0.1), ("I'm", 0.05)]),
    "i'm": (0.4, [("done", 0.3), ("home", 0.2)]),
    "go": (0.6, [("home", 0.2), ("to", 0.15), ("out", 0.05)]),
    "come": (0.5, [("home", 0.3), ("out", 0.1)]),
])

struct NextWordsTests {
    @Test func findsEachContextAndItsFollowers() {
        #expect(table.context("go")?.followers.map(\.word) == ["home", "to", "out"])
        #expect(table.context("I'm")?.followers.first?.word == "done")
        #expect(table.context("")?.followers.first?.word == "I")
        #expect(table.context("went") == nil)
        #expect(NextWords(bytes: Array("HXL1".utf8) + [0, 0, 0, 0]) == nil)
    }

    @Test func listedFollowersGainAndTheRestBackOff() {
        let context = table.context("come")!
        #expect(abs(context.probability(of: "home", backingOffTo: 0.01) - (0.3 + 0.5 * 0.01)) < 0.01)
        #expect(abs(context.probability(of: "the", backingOffTo: 0.2) - 0.5 * 0.2) < 0.01)
    }

    @Test func predictsTheWordsThatFollow() {
        let corrector = Corrector(source: testLexicon, next: table)
        #expect(corrector.predictions(after: "come", context: "come ").first?.text == "home")
        #expect(corrector.predictions(after: "i'm", context: "I'm ").first?.text == "done")
        #expect(Corrector(source: testLexicon).predictions(after: "come", context: "come ").first?.text == "the")
    }

    @Test func sentenceStartPredictionsFollowShift() {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon, next: table)
        let document = TestDocument()
        engine.documentChanged(document)
        engine.suggestionsChanged()
        #expect(Array(engine.suggestions.map(\.text).prefix(2)) == ["I", "The"])
        #expect(engine.suggestions.allSatisfy { $0.text.first?.isUppercase == true })
        engine.type("go ", in: document)
        #expect(Set(engine.suggestions.prefix(2).map(\.text)) == ["to", "home"])
    }
}
