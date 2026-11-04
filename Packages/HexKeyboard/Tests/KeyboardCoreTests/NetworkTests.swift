import Testing
@testable import KeyboardCore

/// A network that expects "to" after "want" and "i" at a sentence's start: each word's embedding is what it reads and
/// what it scores, the gates keep only the last token, the projection sharpens it, and the output biases rule out the
/// special tokens and "want".
let testNetwork: Network = {
    let vocabulary = Network.specials + ["want", "to", "i", "work"]
    let embedding = vocabulary.map { word -> [Float] in
        switch word {
        case "<s>", "i": [0, 1]
        case "want", "to": [1, 0]
        default: [0, 0]
        }
    }
    let input: [[Float]] = [[0, 0], [0, 0], [0, 0], [0, 0], [5, 0], [0, 5], [0, 0], [0, 0]]
    return Network(vocabulary: vocabulary, embedding: embedding, input: input, recurrent: Array(repeating: [0, 0], count: 8),
                   gates: [10, 10, -10, -10, 0, 0, 10, 10], projection: [[20, 0], [0, 20]], projectionBias: [0, 0],
                   output: vocabulary.map { Network.specials.contains($0) || $0 == "want" ? -10 : 0 })
}()

struct NetworkTests {
    @Test func findsEveryWordItStores() {
        for word in ["want", "to", "i", "work"] {
            #expect(testNetwork.id(of: word).map(testNetwork.spelling(of:)) == word)
        }
        #expect(testNetwork.id(of: "wan") == nil)
        #expect(testNetwork.ids(startingWith: "w").map(testNetwork.spelling(of:)) == ["want", "work"])
    }

    @Test func readsSentenceStartsCommasAndNumbers() {
        let names = testNetwork.tokens(before: "I want 2, to. Want").map(testNetwork.spelling(of:))
        #expect(names == ["<s>", "i", "want", "<n>", ",", "to", "<s>", "want"])
    }

    @Test func probabilitiesAddUpAndFollowTheLastWord() {
        let afterWant = testNetwork.logProbabilities(at: testNetwork.read(testNetwork.tokens(before: "I want"), from: testNetwork.start))
        #expect(abs(afterWant.reduce(0) { $0 + Math.exp(Double($1)) } - 1) < 1e-4)
        #expect(afterWant.indices.max { afterWant[$0] < afterWant[$1] } == testNetwork.id(of: "to"))
        let atStart = testNetwork.logProbabilities(at: testNetwork.read(testNetwork.tokens(before: ""), from: testNetwork.start))
        #expect(atStart.indices.max { atStart[$0] < atStart[$1] } == testNetwork.id(of: "i"))
    }

    @Test func goesOnFromWhatItRead() {
        let corrector = Corrector(source: testLexicon, network: testNetwork)
        _ = corrector.expected(after: "I want")
        let continued = corrector.expected(after: "I want to work")!.logProbabilities
        let fresh = Corrector(source: testLexicon, network: testNetwork).expected(after: "I want to work")!.logProbabilities
        #expect(zip(continued, fresh).allSatisfy { abs($0 - $1) < 1e-5 })
    }

    @Test func predictionsAreCapitalizedWhereTheNextWordIs() {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon, network: testNetwork)
        let document = TestDocument()
        engine.documentChanged(document)
        engine.suggestionsChanged()
        #expect(engine.suggestions.first?.text == "I")
        for character in "want " { engine.perform(character == " " ? .space : .character(String(character)), in: document) }
        #expect(engine.suggestions.first?.text == "to")
    }

    @Test func contextReadsTwoWordsBack() {
        let text = "Hi. I want "
        let word = Words.current(in: text)
        #expect(Words.context(before: word, in: text) == ("want", "i"))
        let start = "Hi. I "
        #expect(Words.context(before: Words.current(in: start), in: start) == ("i", ""))
        #expect(Words.context(before: Words.current(in: "Hi. "), in: "Hi. ") == ("", nil))
    }
}
