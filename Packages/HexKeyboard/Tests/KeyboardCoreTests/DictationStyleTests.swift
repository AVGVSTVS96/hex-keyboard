import Testing
@testable import KeyboardCore

struct DictationStyleTests {
    @Test func everyWordIsKeptUmAndUhIncluded() {
        let heard = "Um, so I think, uh, the the job is done."
        #expect(DictationStyle.formal.written(heard, keepingFillers: true) == heard)
        #expect(DictationStyle.standard == .formal)
    }

    @Test func withoutFillersLeavesOutUmAndUh() {
        let write = { DictationStyle.formal.written($0, keepingFillers: false) }
        #expect(write("Um, so I think, uh, the job is done.") == "So I think, the job is done.")
        #expect(write("So uh we go home.") == "So we go home.")
        #expect(write("I was there, uh.") == "I was there.")
        #expect(write("I was there uh?") == "I was there?")
        #expect(write("Ummm... Hmm, uhm, erm, done.") == "Done.")
        #expect(write("Um.") == "")
        #expect(write("Uh-huh, the umbrella.") == "Uh-huh, the umbrella.")
        #expect(write("UH is a state.") == "UH is a state.")
    }

    @Test func formalEndsWithAPeriod() {
        #expect(DictationStyle.formal.written("go home. then work", keepingFillers: true) == "go home. then work.")
        #expect(DictationStyle.formal.written("Is it done?", keepingFillers: true) == "Is it done?")
    }

    @Test func casualDropsOnlyTheLastPeriod() {
        let write = { DictationStyle.casual.written($0, keepingFillers: true) }
        #expect(write("Um, go home. Then work.") == "Um, go home. Then work")
        #expect(write("Is it done?") == "Is it done?")
        #expect(write("Wait for it...") == "Wait for it...")
    }
}
