import Testing
@testable import KeyboardCore

struct DictationStyleTests {
    private func write(_ heard: String, _ style: DictationStyle) -> String {
        style.written(heard, lexicon: testLexicon)
    }

    @Test func asSaidKeepsEveryWord() {
        let heard = "Um, so I think, uh, the the job is done."
        #expect(write(heard, .asSaid) == heard)
        #expect(DictationStyle.standard == .asSaid)
    }

    @Test func theOtherStylesLeaveOutUmAndUh() {
        #expect(write("Um, so I think, uh, the job is done.", .formal) == "So I think, the job is done.")
        #expect(write("So uh we go home.", .formal) == "So we go home.")
        #expect(write("I was there, uh.", .formal) == "I was there.")
        #expect(write("I was there uh?", .formal) == "I was there?")
        #expect(write("Ummm... Hmm, uhm, erm, done.", .formal) == "Done.")
        #expect(write("Um.", .formal) == "")
        #expect(write("Uh-huh, the umbrella.", .formal) == "Uh-huh, the umbrella.")
        #expect(write("UH is a state.", .formal) == "UH is a state.")
    }

    @Test func formalCapitalizesAndEndsEverySentence() {
        #expect(write("go home. then work", .formal) == "Go home. Then work.")
        #expect(write("Is it done?", .formal) == "Is it done?")
    }

    @Test func casualDropsOnlyTheLastPeriod() {
        #expect(write("Go home. Then work.", .casual) == "Go home. Then work")
        #expect(write("Is it done?", .casual) == "Is it done?")
        #expect(write("Wait for it...", .casual) == "Wait for it...")
    }

    @Test func veryCasualLowercasesSentenceStartsButNotNames() {
        #expect(write("Hello. I'm home and I left. Cheryl came.", .veryCasual) == "hello. i'm home and i left. Cheryl came")
        #expect(write("The job is done! OK, go.", .veryCasual) == "the job is done! OK, go")
        #expect(write("Um, the job is done.", .veryCasual) == "the job is done")
        #expect(write("\"Hello,\" he said.", .veryCasual) == "\"hello,\" he said")
    }
}
