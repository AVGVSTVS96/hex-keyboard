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

    let lexicon = Lexicon(counts: "a also another as be could dash do dot flow if i is it like my now on or pool proxy run sound the to we well wondering around agent agents cloud".split(separator: " ").map { (word: String($0), count: 100.0) })
    let names = Vocabulary([
        Vocabulary.Term("kestrel", heardAs: ["kestril"]),
        Vocabulary.Term("kestrel.run", heardAs: ["kestrel dot run"]),
        Vocabulary.Term("iikb"),
        Vocabulary.Term("Wispr Flow"),
        Vocabulary.Term("Astound", heardAs: ["stowned"]),
    ])

    @Test func aMadeUpWordThatSoundsLikeATermBecomesIt() {
        #expect(names.corrected("as well as another pool.kestrul dot run", lexicon: lexicon) == "as well as another pool.kestrel.run")
        #expect(names.corrected("Kestril dot run link.", lexicon: lexicon) == "kestrel.run link.")
        #expect(names.corrected("my kestril.run domain", lexicon: lexicon) == "my kestrel.run domain")
        #expect(names.corrected("rename it to IKB", lexicon: lexicon) == "rename it to iikb")
        #expect(names.corrected("I'm wondering if we could also do like dash dot kestul.run.", lexicon: lexicon)
            == "I'm wondering if we could also do like dash.kestrel.run.")
    }

    @Test func aRealWordOrAWordBesideTheTermStays() {
        #expect(names.corrected("it is around now", lexicon: lexicon) == "it is around now")
        #expect(names.corrected("like Wispr Flow or Aquavoice", lexicon: lexicon) == "like Wispr Flow or Aquavoice")
        #expect(names.corrected("make iikb a lot smarter", lexicon: lexicon) == "make iikb a lot smarter")
        #expect(names.corrected("pool.kestrul dot run") == "pool.kestrul dot run")
    }

    @Test func wordsAlreadyInTheFieldComeOutTheSame() {
        let field = "proxy.kestrel.run? i'm wondering if we could also do like dash.kestrel.run, "
        #expect(Vocabulary().corrected("as well as another pool.kestrul dot run", lexicon: lexicon, field: field)
            == "as well as another pool.kestrel.run")
        #expect(Vocabulary().corrected("ask Wolfgang about Wolfgung", lexicon: lexicon, field: "Wolfgang said")
            == "ask Wolfgang about Wolfgang")
        #expect(Vocabulary().corrected("the subagents and Wolfgang", lexicon: lexicon, field: "one subagent, wolfgang")
            == "the subagents and Wolfgang")
    }
}

