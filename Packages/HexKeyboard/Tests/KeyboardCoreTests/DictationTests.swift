import Testing
@testable import KeyboardCore

struct DictationTests {
    private func dictate(_ heard: String, into text: String, cursor: Int? = nil) -> String {
        var engine = TypingEngine()
        engine.corrector = Corrector(source: testLexicon)
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
}
