import Testing
@testable import KeyboardCore

struct AutocorrectTests {
    @Test func findsMisspelledWords() {
        let corrector = Corrector(source: testLexicon)
        corrector.changeMemory { $0.keep("qzxv") }
        let text = "I’m done, helo world's qzxv 42nd 'wrld' hello"
        #expect(corrector.misspellings(in: text).map { String(text[$0]) } == ["helo", "wrld"])
    }

    @Test func correctsOnSpaceKeepingCase() {
        var engine = TypingEngine.correcting()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("helo wrld ", in: document)
        #expect(document.text == "Hello world ")
    }

    @Test func correctsBeforePunctuation() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("ok ")
        engine.documentChanged(document)
        engine.type("wrld.", in: document)
        #expect(document.text == "ok world.")
    }

    @Test func showsLiteralThenPendingCorrection() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo", in: document)
        #expect(engine.suggestions.map(\.text) == ["helo", "hello", "help"])
        #expect(engine.suggestions.map(\.kind) == [.literal, .correction, .candidate])
    }

    @Test func offersTheCorrectionWithAutoCorrectionOff() {
        var engine = TypingEngine.correcting()
        engine.settings.autoCorrection = false
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo", in: document)
        #expect(engine.suggestions.map(\.text) == ["helo", "hello", "help"])
        #expect(engine.suggestions.map(\.kind) == [.literal, .candidate, .candidate])
        engine.type(" ", in: document)
        #expect(document.text == "so helo ")
    }

    @Test func suggestionJobMatchesRankingInline() {
        var inline = TypingEngine()
        inline.corrector = Corrector(source: testLexicon)
        var deferred = TypingEngine()
        deferred.corrector = Corrector(source: testLexicon)
        deferred.defersSuggestions = true
        let (a, b) = (TestDocument("so "), TestDocument("so "))
        inline.documentChanged(a)
        deferred.documentChanged(b)
        inline.type("helo", in: a)
        deferred.type("helo", in: b)
        #expect(deferred.suggestionsAreStale)
        var job = try! #require(deferred.suggestionJob())
        job.run()
        deferred.finish(job)
        #expect(!deferred.suggestionsAreStale)
        #expect(deferred.suggestions == inline.suggestions)
        inline.type(" ", in: a)
        deferred.type(" ", in: b)
        #expect(b.text == a.text)
    }

    @Test func suggestionJobForOlderTextIsDropped() {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon)
        engine.defersSuggestions = true
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("hel", in: document)
        var job = try! #require(engine.suggestionJob())
        engine.type("o", in: document)
        job.run()
        engine.finish(job)
        #expect(engine.suggestionsAreStale)
        #expect(engine.suggestions.isEmpty)
    }

    @Test func completesPartialWords() {
        var engine = TypingEngine.correcting()
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("hel", in: document)
        #expect(engine.suggestions.map(\.text) == ["Hel", "Help", "Hello"])
    }

    @Test func deleteAfterCorrectionOffersRevert() throws {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo ", in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "so hello")
        let revert = try #require(engine.suggestions.first)
        #expect(revert == Suggestion("helo", .revert))
        engine.accept(revert, in: document)
        #expect(document.text == "so helo ")
        engine.type("helo ", in: document)
        #expect(document.text == "so helo helo ")
    }

    @Test func secondDeleteDropsTheRevert() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo ", in: document)
        engine.perform(.delete, in: document)
        engine.perform(.delete, in: document)
        #expect(document.text == "so hell")
        #expect(!engine.suggestions.contains { $0.kind == .revert })
    }

    @Test func tappingTheLiteralKeepsIt() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("helo", in: document)
        engine.accept(engine.suggestions[0], in: document)
        engine.type("helo ", in: document)
        #expect(document.text == "so helo helo ")
    }

    @Test func tappingACandidateReplacesTheWord() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("hel", in: document)
        engine.accept(engine.suggestions[2], in: document)
        #expect(document.text == "so hello ")
    }

    @Test func correctsASelectedWord() throws {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so helo world")
        document.select("helo")
        engine.documentChanged(document)
        let hello = try #require(engine.suggestions.first { $0.text == "hello" })
        #expect(hello.kind == .candidate)
        engine.accept(hello, in: document)
        #expect(document.text == "so hello world")
    }

    @Test func keepsASelectedWordTappedAsTyped() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so helo world")
        document.select("helo")
        engine.documentChanged(document)
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "so helo world")
        #expect(document.cursor == 8)
    }

    @Test func aNewWordTypedInFrontOfAnotherIsRankedAlone() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("I world")
        document.cursor = 2
        engine.documentChanged(document)
        engine.type("hel", in: document)
        #expect(engine.suggestions.map(\.text).contains("help"))
        engine.accept(engine.suggestions.first { $0.text == "help" }!, in: document)
        #expect(document.text == "I help world")
    }

    @Test func aWordYouGoBackIntoIsRankedWhole() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("so helo world")
        document.cursor = 5
        engine.documentChanged(document)
        let hello = engine.suggestions.first { $0.text == "hello" }
        #expect(hello?.kind == .candidate)
        engine.accept(hello!, in: document)
        #expect(document.text == "so hello world")
    }

    @Test func expandsTextReplacements() {
        var engine = TypingEngine.correcting()
        engine.corrector?.setReplacements([("omw", "On my way!")])
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("omw", in: document)
        #expect(engine.suggestions[1] == Suggestion("On my way!", .correction))
        engine.perform(.space, in: document)
        #expect(document.text == "On my way! ")
        engine.perform(.delete, in: document)
        engine.accept(engine.suggestions[0], in: document)
        #expect(document.text == "Omw ")
    }

    @Test func capitalizesNames() {
        var engine = TypingEngine.correcting()
        engine.corrector?.setNames(["Bassim"])
        let document = TestDocument("hi ")
        engine.documentChanged(document)
        engine.type("bas", in: document)
        #expect(engine.suggestions[1].text == "Bassim")
        engine.type("sim ", in: document)
        #expect(document.text == "hi Bassim ")
    }

    @Test func namesThatAreEverydayWordsStayLowercase() {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon)
        engine.corrector?.setNames(["A", "The", "Man", "Bassim"])
        let document = TestDocument("so ")
        engine.documentChanged(document)
        engine.type("the man is a bassim ", in: document)
        #expect(document.text == "so the man is a Bassim ")
    }

    @Test func respectsFieldsAndSettings() {
        for traits in [InputTraits(kind: .url), InputTraits(kind: .email), InputTraits(autocorrection: false)] {
            var engine = TypingEngine.correcting()
            engine.update(traits)
            let document = TestDocument("x ")
            engine.type("helo ", in: document)
            #expect(document.text == "x helo ")
        }
        var engine = TypingEngine.correcting()
        engine.settings.autoCorrection = false
        let document = TestDocument("x ")
        engine.type("helo ", in: document)
        #expect(document.text == "x helo ")
    }

    @Test func hidesSuggestionsWhenPredictiveTextIsOffButStillCorrects() {
        var engine = TypingEngine.correcting()
        engine.settings.predictiveText = false
        let document = TestDocument("x ")
        engine.type("helo", in: document)
        #expect(engine.suggestions.isEmpty)
        engine.perform(.space, in: document)
        #expect(document.text == "x hello ")
    }

    @Test func leavesHandlesUrlsAndNumbersAlone() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("mail @")
        engine.type("helo ", in: document)
        engine.type("wrld2 ", in: document)
        #expect(document.text == "mail @helo wrld2 ")
    }

    @Test func doesNotCorrectInsideAWord() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("heloworld")
        document.cursor = 4
        engine.perform(.space, in: document)
        #expect(document.text == "helo world")
    }

    @Test func correctsAWordTypedRightBeforeAnother() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("the world")
        document.cursor = 4
        engine.documentChanged(document)
        engine.type("helo ", in: document)
        #expect(document.text == "the hello world")
    }

    @Test func learnsNextWordsFromWhatYouType() {
        var engine = TypingEngine.correcting()
        let document = TestDocument("x ")
        engine.type("see you. see you. see ", in: document)
        #expect(engine.suggestions.first == Suggestion("you", .candidate))
    }

    @Test func findsTheCurrentWord() {
        #expect(Words.current(in: "it's") == "it's")
        #expect(Words.current(in: "say 'hi") == "hi")
        #expect(Words.current(in: "end. ") == "")
        #expect(Words.isCorrectable(Words.current(in: "(helo"), in: "(helo"))
        #expect(!Words.isCorrectable(Words.current(in: "a.helo"), in: "a.helo"))
    }
}

struct MissedSpaceTests {
    let corrector = Corrector(source: Lexicon(counts: [
        ("great", 300), ("day", 400), ("the", 1000), ("what", 500), ("given", 80), ("give", 100), ("treat", 40),
        ("i", 900), ("also", 300), ("updated", 60), ("update", 80), ("done", 200), ("ok", 100), ("love", 200), ("you", 900),
        ("baby", 60), ("about", 300), ("hr", 20), ("but", 600), ("pm", 30), ("see", 400), ("dont", 20), ("don't", 500),
        ("its", 300), ("it's", 250),
    ].map { (word: $0.0, count: Double($0.1)) }))

    @Test func readsAMistypedLetterBesidesEveryMissedSpace() {
        #expect(corrector.split(TypedWord("iblovebuoubbaby")) == "i love you baby")
    }

    @Test func readsASpaceThatWasNeverTyped() {
        #expect(corrector.split(TypedWord("greatday")) == "great day")
    }

    @Test func readsASpaceTapThatMeantALetter() {
        #expect(corrector.split(TypedWord("a out the")) == "about the")
        #expect(corrector.split(TypedWord("what the")) == nil)
    }

    @Test func readsEveryMissedSpaceInARun() {
        #expect(corrector.split(TypedWord("inalsonuodated", previous: "done")) == "i also updated")
    }

    @Test func readsAMissedSpaceByTheWordsAroundIt() {
        let vocabulary = Network.specials + ["in", "i", "also", "updated", "done"]
        let network = Network(vocabulary: vocabulary, embedding: vocabulary.map { word in
            switch word {
            case "in", "<s>": [1, 0]
            case "i": [0, 1]
            case "also": [-1, 1]
            default: [0, 0]
            }
        }, input: [[0, 0], [0, 0], [0, 0], [0, 0], [5, 0], [0, 5], [0, 0], [0, 0]], recurrent: Array(repeating: [0, 0], count: 8),
                              gates: [10, 10, -10, -10, 0, 0, 10, 10], projection: [[20, 0], [0, 20]], projectionBias: [0, 0],
                              output: vocabulary.map { Network.specials.contains($0) ? -10 : 0 })
        let corrector = Corrector(source: Lexicon(counts: [("in", 3000), ("i", 900), ("also", 300), ("updated", 60), ("done", 200)]
            .map { (word: $0.0, count: Double($0.1)) }), network: network)
        let typed = TypedWord("inalsonuodated", previous: "done")
        #expect(corrector.split(typed) == "in also updated")
        #expect(corrector.split(typed, context: "done ") == "i also updated")
    }

    @Test func offersTheWordsOfASelectedRun() throws {
        var engine = TypingEngine()
        engine.corrector = corrector
        let document = TestDocument("done freatvday ok")
        document.select("freatvday")
        engine.documentChanged(document)
        let pair = try #require(engine.suggestions.first { $0.text == "great day" })
        engine.accept(pair, in: document)
        #expect(document.text == "done great day ok")
    }

    @Test func rereadsASelectionOfSeveralWords() throws {
        var engine = TypingEngine()
        engine.corrector = corrector
        let document = TestDocument("done a out the ok")
        document.select("a out the")
        engine.documentChanged(document)
        let words = try #require(engine.suggestions.first { $0.text == "about the" })
        engine.accept(words, in: document)
        #expect(document.text == "done about the ok")
    }

    @Test func offersTheWordsOfARunBeforeTheCaret() {
        var engine = TypingEngine()
        engine.corrector = corrector
        let document = TestDocument("done inalsonuodated ok")
        document.cursor = 5
        engine.documentChanged(document)
        #expect(engine.suggestions.map(\.text).contains("i also updated"))
    }

    @Test func offersTheTwoWordsAMissedSpaceJoined() {
        let suggestions = corrector.suggestions(for: TypedWord("freatvday"), correcting: true, guessing: true)
        #expect(suggestions.map(\.text).contains("great day"))
        #expect(suggestions.first { $0.text == "great day" }?.kind == .candidate)
        #expect(corrector.correction(for: TypedWord("freatvday")) == nil)
    }

    @Test func readsANumberAndItsUnitAsOneWord() {
        #expect(corrector.split(TypedWord("1hrbut")) == "1hr but")
        #expect(corrector.correction(for: TypedWord("1hrbut")) == "1hr but")
        #expect(corrector.correction(for: TypedWord("2pm")) == nil)
        #expect(corrector.correction(for: TypedWord("2day")) == nil)
    }

    @Test func theSpaceAppliesOnlyMissedSpaces() {
        var engine = TypingEngine()
        engine.corrector = corrector
        let document = TestDocument()
        engine.documentChanged(document)
        engine.type("greatday 1hrbut freatvday ", in: document)
        #expect(document.text == "Great day 1hr but freatvday ")
    }

    @Test func neverSplitsAWordYouKept() {
        let corrector = Corrector(source: corrector.source)
        corrector.changeMemory { $0.keep("greatday") }
        #expect(corrector.correction(for: TypedWord("greatday")) == nil)
    }

    @Test func addsTheApostropheAWordWasTypedWithout() {
        #expect(corrector.correction(for: TypedWord("dont")) == "don't")
        #expect(corrector.correction(for: TypedWord("its")) == nil)
        corrector.changeMemory { $0.keep("dont") }
        #expect(corrector.correction(for: TypedWord("dont")) == nil)
    }

    @Test func keepsTheTypedCapital() {
        #expect(corrector.split(TypedWord("Whatbthe")) == "What the")
    }

    @Test func leavesARealWordWhole() {
        #expect(corrector.split(TypedWord("given")) == nil)
    }
}
