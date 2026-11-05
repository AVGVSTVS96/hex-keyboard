import Testing
@testable import KeyboardCore

struct VocabularyTests {
    let vocabulary = Vocabulary([
        Vocabulary.Term("Claude", heardAs: ["clawed"]),
        Vocabulary.Term("Claude Code", heardAs: ["clawed code"]),
        Vocabulary.Term("herdr", heardAs: ["herder"]),
        Vocabulary.Term("react-shiki", heardAs: ["react shicky"]),
        Vocabulary.Term("Tailscale"),
        Vocabulary.Term("Codex", heardAs: ["codecs"]),
    ])

    @Test func aListedSpellingBecomesTheTerm() {
        #expect(vocabulary.corrected("Ask clawed about it.") == "Ask Claude about it.")
        #expect(vocabulary.corrected("Herder is recording, right?") == "herdr is recording, right?")
        #expect(vocabulary.corrected("Open React Shicky now") == "Open react-shiki now")
    }

    @Test func theTermWrittenAnotherWayBecomesTheTerm() {
        #expect(vocabulary.corrected("it's on tail scale") == "it's on Tailscale")
        #expect(vocabulary.corrected("TAILSCALE and tail-scale") == "Tailscale and Tailscale")
        #expect(vocabulary.corrected("open react shiki") == "open react-shiki")
    }

    @Test func theLongestMatchWinsAndPossessivesKeepTheirS() {
        #expect(vocabulary.corrected("I ran clawed code twice") == "I ran Claude Code twice")
        #expect(vocabulary.corrected("herder's sessions") == "herdr's sessions")
    }

    @Test func onlyWholeWordsMatchAndNeverAcrossPunctuation() {
        #expect(vocabulary.corrected("the herders sat by a tail, scale it") == "the herders sat by a tail, scale it")
        #expect(vocabulary.corrected("unclawed") == "unclawed")
        #expect(Vocabulary().corrected("clawed") == "clawed")
        #expect(vocabulary.corrected("clone tail-scale-demo and openai/codex, then codecs.") == "clone tail-scale-demo and openai/codex, then Codex.")
    }
}
