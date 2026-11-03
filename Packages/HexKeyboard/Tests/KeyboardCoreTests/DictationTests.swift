import Testing
@testable import KeyboardCore

struct DictationTests {
    private func dictate(_ heard: String, into text: String, cursor: Int? = nil, style: DictationStyle = .formal, field: Autocapitalization = .sentences, autoCapitalization: Bool = true) -> String {
        var engine = TypingEngine(traits: InputTraits(autocapitalization: field))
        engine.corrector = Corrector(source: testLexicon)
        engine.settings.dictationStyle = style
        engine.settings.autoCapitalization = autoCapitalization
        let document = TestDocument(text)
        if let cursor { document.cursor = cursor }
        engine.handle(.dictated(heard), in: document)
        return document.text
    }

    @Test func aDictationContinuingASentenceStartsLowercase() {
        #expect(dictate("In which case go home.", into: "start there unless it's a lot of work ") == "start there unless it's a lot of work in which case go home.")
        #expect(dictate("The job is done.", into: "and then,") == "and then, the job is done.")
    }

    @Test func aNewSentenceOrANameKeepsItsCapital() {
        #expect(dictate("How are you?", into: "Hello there.") == "Hello there. How are you?")
        #expect(dictate("In the morning.", into: "Done.\n") == "Done.\nIn the morning.")
        #expect(dictate("In the morning.", into: "") == "In the morning.")
        #expect(dictate("I left.", into: "and then ") == "and then I left.")
        #expect(dictate("Claude did it.", into: "so ") == "so Claude did it.")
        #expect(dictate("OK, done.", into: "so ") == "so OK, done.")
    }

    @Test func aDictationBeforeMoreOfTheSentenceLosesItsPeriodAndKeepsASpace() {
        #expect(dictate("To the job.", into: "I go and come home", cursor: 5) == "I go to the job and come home")
        #expect(dictate("To work.", into: "I go, then home", cursor: 4) == "I go to work, then home")
        #expect(dictate("Hello there.", into: "How are you", cursor: 0) == "Hello there. How are you")
        #expect(dictate("In the house.", into: "I was , and done", cursor: 6) == "I was in the house, and done")
    }

    @Test func withAutoCapitalizationOffADictationStartsSentencesLowercaseInEveryStyle() {
        for style in DictationStyle.allCases {
            #expect(dictate("Hello. I think it's done. Cheryl liked it.", into: "", style: style, autoCapitalization: false).hasPrefix("hello. i think it's done. Cheryl liked it"))
        }
    }

    @Test func veryCasualStartsSentencesLowercaseAndNamesKeepTheirCapitals() {
        let off = { (heard: String, text: String) in dictate(heard, into: text, style: .veryCasual) }
        #expect(off("Hello. I think it's done. Cheryl liked it.", "") == "hello. i think it's done. Cheryl liked it.")
        #expect(off("Hello. I'm home and I left.", "Done. ") == "Done. hello. i'm home and i left.")
        #expect(off("The job is done! OK, go.", "") == "the job is done! OK, go.")
        #expect(off("\"Hello,\" he said.", "") == "\"hello,\" he said.")
        #expect(dictate("Hello there.", into: "", field: .none) == "hello there.")
    }

    @Test func theOtherStylesStartEverySentenceWithACapital() {
        #expect(dictate("go home. then work.", into: "") == "Go home. Then work.")
        #expect(dictate("go home. then work.", into: "and ") == "and go home. Then work.")
        #expect(dictate("iPhone is here.", into: "") == "iPhone is here.")
        #expect(dictate("go home.", into: "", field: .words) == "go home.")
        #expect(dictate("My goals are:\n1. finish the report\n2. send it", into: "") == "My goals are:\n1. Finish the report\n2. Send it")
        #expect(dictate("The job:\n1. The job is done", into: "", style: .veryCasual) == "the job:\n1. the job is done")
    }
}
