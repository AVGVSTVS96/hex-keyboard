import Testing
@testable import KeyboardCore

struct DictationStyleTests {
    private func write(_ heard: String, _ style: DictationStyle = .formal, _ editing: DictationEditing = .asSaid, lists: Bool = true) -> String {
        DictationWriting(style: style, editing: editing, lists: lists).written(heard)
    }

    @Test func asSaidKeepsEveryWordUmAndUhIncluded() {
        let heard = "Um, so I think, uh, the the job is done."
        #expect(write(heard) == heard)
        #expect(KeyboardSettings.initial.dictation == DictationWriting(style: .casual, editing: .asSaid, lists: true))
    }

    @Test func lightLeavesOutUmAndUh() {
        let light = { write($0, .formal, .light) }
        #expect(light("Um, so I think, uh, the job is done.") == "So I think, the job is done.")
        #expect(light("So uh we go home.") == "So we go home.")
        #expect(light("I was there, uh.") == "I was there.")
        #expect(light("I was there uh?") == "I was there?")
        #expect(light("Ummm... Hmm, uhm, erm, done.") == "Done.")
        #expect(light("Um.") == "")
        #expect(light("Uh-huh, the umbrella.") == "Uh-huh, the umbrella.")
        #expect(light("UH is a state.") == "UH is a state.")
        #expect(light("And the the job.") == "And the the job.")
    }

    @Test func cleanAlsoLeavesOutWordsSaidTwiceAndWhatYouScratch() {
        let clean = { write($0, .formal, .clean) }
        #expect(clean("Um, so I I think the the job is done.") == "So I think the job is done.")
        #expect(clean("I I I think so, it it works.") == "I think so, it works.")
        #expect(clean("When you press it, it opens.") == "When you press it, it opens.")
        #expect(clean("I know that that works and I had had enough. It's very very good.") == "I know that that works and I had had enough. It's very very good.")
        #expect(clean("Meet at two. Scratch that, meet at three.") == "Meet at three.")
        #expect(clean("Done. Meet at two, scratch that. Meet at three.") == "Done. Meet at three.")
        #expect(clean("Scratch that.") == "")
    }

    @Test func formalEndsWithAPeriod() {
        #expect(write("go home. then work") == "go home. then work.")
        #expect(write("Is it done?") == "Is it done?")
        #expect(write("Also, written into a list.. Um, done.") == "Also, written into a list. Um, done.")
        #expect(write("Wait for it...") == "Wait for it...")
    }

    @Test func casualDropsTheLastPeriodAndTheCommaAfterAnOpener() {
        let casual = { write($0, .casual) }
        #expect(casual("Um, go home. Then work.") == "Um go home. Then work")
        #expect(casual("Also, the emoji button. So, it works, so we ship.") == "Also the emoji button. So it works, so we ship")
        #expect(casual("Is it done?") == "Is it done?")
        #expect(casual("Wait for it...") == "Wait for it...")
        #expect(write("Also, done.", .veryCasual) == "Also done")
    }

    @Test func excitedEndsWithAnExclamationMark() {
        #expect(write("We shipped it.", .excited) == "We shipped it!")
        #expect(write("We shipped it", .excited) == "We shipped it!")
        #expect(write("Did we ship it?", .excited) == "Did we ship it?")
    }

    @Test func veryCasualAsksTheKeyboardForNoCapitals() {
        #expect(DictationStyle.veryCasual.capitals(in: .sentences) == .none)
        #expect(DictationStyle.formal.capitals(in: .sentences) == .sentences)
        #expect(DictationStyle.casual.capitals(in: .none) == .none)
    }

    @Test func aSpokenListIsWrittenAsOne() {
        #expect(write("My goals are one, finish the report, two, send the deck, and three, call Simon. Then rest.")
            == "My goals are:\n1. finish the report\n2. send the deck\n3. call Simon\nThen rest.")
        #expect(write("One. Eggs. Two. Milk. Three. Bread.") == "1. Eggs\n2. Milk\n3. Bread")
        #expect(write("First, we go home. Second, we eat?") == "1. we go home\n2. we eat?")
        #expect(write("Buy these: number one, eggs, number two, milk.") == "Buy these:\n1. eggs\n2. milk")
        #expect(write("Steps: 1, open it, 2, close it.", .casual) == "Steps:\n1. open it\n2. close it")
    }

    @Test func numbersInASentenceStayInIt() {
        #expect(write("I have one cat and two dogs.") == "I have one cat and two dogs.")
        #expect(write("I have one, maybe two, cats.") == "I have one, maybe two, cats.")
        #expect(write("One, two, three, go.") == "One, two, three, go.")
        #expect(write("Twenty-one, then two, then done.") == "Twenty-one, then two, then done.")
        #expect(write("My goals are one, finish, two, send.", lists: false) == "My goals are one, finish, two, send.")
    }

    @Test func hisListFromNovemberThird() {
        let heard = "Now, one thing they do is when mentioning a list like one, this item, two, that item, three, the other item, they are automatically written into a list.. Um, I'm not sure."
        #expect(write(heard, .formal, .light)
            == "Now, one thing they do is when mentioning a list like:\n1. this item\n2. that item\n3. the other item, they are automatically written into a list\nI'm not sure.")
    }

    @Test func theAppsExampleTypedInEachStyle() {
        let lexicon = Lexicon(counts: ["so", "i", "think", "the", "second", "draft", "reads", "better", "let's", "send", "it", "to", "tonight", "Sam"].map { (word: $0, count: 100) })
        let heard = "So, um, I think the the second draft reads better. Let's send it to Sam tonight."
        let typed = { DictationWriting(style: $0, editing: $1).typed(heard, lexicon: lexicon) }
        #expect(typed(.formal, .asSaid) == heard)
        #expect(typed(.casual, .asSaid) == "So um, I think the the second draft reads better. Let's send it to Sam tonight")
        #expect(typed(.veryCasual, .light) == "so i think the the second draft reads better. let's send it to Sam tonight")
        #expect(typed(.excited, .clean) == "So, I think the second draft reads better. Let's send it to Sam tonight!")
    }
}
