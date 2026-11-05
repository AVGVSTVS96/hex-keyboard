import Testing
@testable import KeyboardCore

struct DictationStyleTests {
    private func write(_ heard: String, _ style: DictationStyle = .formal, _ editing: DictationEditing = .asSaid, lists: DictationLists = .numbered) -> String {
        DictationWriting(style: style, editing: editing, lists: lists).written(heard)
    }

    @Test func asSaidKeepsEveryWordUmAndUhIncluded() {
        let heard = "Um, so I think, uh, the the job is done."
        #expect(write(heard) == heard)
        #expect(KeyboardSettings.initial.dictation == DictationWriting(style: .casual, editing: .asSaid, lists: .numbered, capitalizes: false))
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
        #expect(light("Mm hmm, that works. Mm-hmm, sure. Hmm, maybe.") == "Mm hmm, that works. Mm-hmm, sure. Maybe.")
        #expect(light("UH is a state.") == "UH is a state.")
        #expect(light("And the the job.") == "And the the job.")
    }

    @Test func cleanAlsoLeavesOutWordsSaidTwiceAndWhatYouScratch() {
        let clean = { write($0, .formal, .clean) }
        #expect(clean("Um, so I I think the the job is done.") == "So I think the job is done.")
        #expect(clean("I I I think so, it it works.") == "I think so, it works.")
        #expect(clean("When you press it, it opens.") == "When you press it, it opens.")
        #expect(clean("I know that that works and I had had enough. It's very very good.") == "I know that that works and I had had enough. It's very very good.")
        #expect(clean("and can we you you know ship it") == "and can we you you know ship it?")
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

    @Test func capitalsFollowAutoCapitalizationAndVeryCasualHasNone() {
        #expect(DictationWriting(style: .veryCasual).capitals(in: .sentences) == .none)
        #expect(DictationWriting(style: .formal).capitals(in: .sentences) == .sentences)
        #expect(DictationWriting(style: .casual).capitals(in: .none) == .none)
        #expect(DictationWriting(style: .formal, capitalizes: false).capitals(in: .sentences) == .none)
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
        #expect(write("My goals are one, finish, two, send.", lists: .off) == "My goals are one, finish, two, send.")
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
    private let lexicon = Lexicon(counts: [
        "so", "are", "you", "free", "tonight", "let's", "grab", "dinner", "and", "then", "see", "the", "show", "hey", "thanks",
        "for", "notes", "they", "helped", "a", "lot", "can", "we", "meet", "at", "two", "however", "plan", "works", "shipped",
        "it", "wow", "that", "was", "fast", "honestly", "i", "can't", "wait", "is", "ready", "right", "but", "missed", "train",
        "home", "late", "it's", "i'm", "Sam",
    ].map { (word: $0, count: 100) })

    /// The same dictations, as the model writes them, typed in each style at the start of a message.
    @Test func eachStyleTypesTheSameDictationsItsOwnWay() {
        let dictations: [(said: String, formal: String, casual: String, veryCasual: String, excited: String)] = [
            ("So, are you free tonight. Let's grab dinner, and then see the show.",
             "So, are you free tonight? Let's grab dinner, and then see the show.",
             "So are you free tonight? Let's grab dinner, and then see the show",
             "so are you free tonight? let's grab dinner and then see the show",
             "So, are you free tonight? Let's grab dinner, and then see the show!"),
            ("Hey, Sam, thanks for the notes; they helped a lot. Can we meet at two.",
             "Hey, Sam, thanks for the notes; they helped a lot. Can we meet at two?",
             "Hey Sam, thanks for the notes, they helped a lot. Can we meet at two?",
             "hey Sam, thanks for the notes, they helped a lot. can we meet at two?",
             "Hey, Sam, thanks for the notes; they helped a lot! Can we meet at two?"),
            ("However the plan works. We shipped it!! Wow, that was fast. Honestly I can't wait.",
             "However, the plan works. We shipped it! Wow, that was fast. Honestly, I can't wait.",
             "However the plan works. We shipped it!! Wow that was fast. Honestly I can't wait",
             "however the plan works. we shipped it!! wow that was fast. honestly i can't wait",
             "However, the plan works. We shipped it! Wow, that was fast! Honestly, I can't wait!"),
            ("I missed the train, but I'm home. It's late, right.",
             "I missed the train, but I'm home. It's late, right?",
             "I missed the train, but I'm home. It's late, right?",
             "i missed the train but i'm home. it's late, right?",
             "I missed the train, but I'm home. It's late, right?"),
        ]
        for dictation in dictations {
            let typed = { DictationWriting(style: $0).typed(dictation.said, lexicon: lexicon) }
            #expect(typed(.formal) == dictation.formal)
            #expect(typed(.casual) == dictation.casual)
            #expect(typed(.veryCasual) == dictation.veryCasual)
            #expect(typed(.excited) == dictation.excited)
        }
    }

    @Test func everyStyleAsksAQuestionTheModelEndedWithAPeriod() {
        for style in DictationStyle.allCases {
            #expect(write("Are you coming. Did it work. What do you think. Where's Sam.", style) == "Are you coming? Did it work? What do you think? Where's Sam?")
            #expect(write("So, can we go now", style).hasSuffix("can we go now?"))
            #expect(write("It works, doesn't it.", style) == "It works, doesn't it?")
            #expect(write("Let's go, okay.", style) == "Let's go, okay?")
        }
        #expect(write("Do it now. Have it ready. What I want is rest. When you're done, call me. How nice.") == "Do it now. Have it ready. What I want is rest. When you're done, call me. How nice.")
        #expect(write("Is it done...") == "Is it done...")
    }

    @Test func formalSetsOffAnOpeningTransitionAndKeepsOneMark() {
        #expect(write("However we ship. Also I left. Actually not yet. Hopefully it works!!") == "However, we ship. Also, I left. Actually not yet. Hopefully, it works!")
        #expect(write("So we ship. Instead of that, wait.") == "So we ship. Instead of that, wait.")
        #expect(write("Really?? Yes.") == "Really? Yes.")
    }

    @Test func casualLoosensOpenersAndSemicolons() {
        let casual = { write($0, .casual) }
        #expect(casual("Hey, Sam. Thanks, that helps; it works. Sorry, I'm late.") == "Hey Sam. Thanks that helps, it works. Sorry I'm late")
        #expect(casual("I tried, but it failed, and so did Sam.") == "I tried, but it failed, and so did Sam")
        #expect(casual("Wait for it...") == "Wait for it...")
    }

    @Test func veryCasualAlsoDropsTheCommaBeforeAConjunction() {
        let veryCasual = { write($0, .veryCasual) }
        #expect(veryCasual("I tried, but it failed, and so did Sam.") == "I tried but it failed and so did Sam")
        #expect(veryCasual("Eggs, milk, and bread.") == "Eggs, milk and bread")
        #expect(veryCasual("Hi, I'm here, so let's go; it's late.") == "Hi I'm here so let's go, it's late")
    }

    @Test func excitedEndsShortSentencesAndCheersWithExclamationMarks() {
        let excited = { write($0, .excited) }
        #expect(excited("Thanks so much. The report is in the shared folder now. Great work, everyone. See you Monday.")
            == "Thanks so much! The report is in the shared folder now. Great work, everyone! See you Monday!")
        #expect(excited("We finally shipped the whole thing today. Can you check it.") == "We finally shipped the whole thing today. Can you check it?")
        #expect(excited("Wait for it...") == "Wait for it...")
    }

    @Test func cleanTakesOutWhatYouCorrectAsYouGo() {
        let clean = { write($0, .formal, .clean) }
        #expect(clean("Let's meet at two, I mean three.") == "Let's meet at three.")
        #expect(clean("Meet at two pm, I mean three.") == "Meet at three pm.")
        #expect(clean("Send it to Sam, I mean Alex, tonight.") == "Send it to Alex tonight.")
        #expect(clean("I'll have the pasta, actually the salad.") == "I'll have the salad.")
        #expect(clean("Book it for Tuesday, no wait, Wednesday.") == "Book it for Wednesday.")
        #expect(clean("Call Sam at five, sorry, six.") == "Call Sam at six.")
        #expect(clean("On Tuesday, actually Wednesday.") == "On Wednesday.")
        #expect(write("Let's meet at two, I mean three.", .formal, .light) == "Let's meet at two, I mean three.")
    }

    @Test func cleanKeepsWhatOnlySoundsLikeACorrection() {
        let clean = { write($0, .formal, .clean) }
        for kept in [
            "I'm busy, sorry I can't.", "It's fine, I mean it works.", "We should go, actually, it's late.", "Thanks, actually.",
            "I like it, actually a lot.", "No, no, it's fine.", "I think so, no doubt.",
        ] {
            #expect(clean(kept) == kept)
        }
    }

    @Test func cleanTakesOutLikeAndYouKnowSaidAsAnAside() {
        let clean = { write($0, .formal, .clean) }
        #expect(clean("It was, like, huge.") == "It was huge.")
        #expect(clean("It works, you know.") == "It works.")
        #expect(clean("You know, it works. Like, I said so. I mean, it's fine.") == "It works. I said so. It's fine.")
        #expect(clean("I like it. Like I said, it works. You know what I mean.") == "I like it. Like I said, it works. You know what I mean.")
        #expect(clean("It's really big on Reddit, you know? Then we share it.") == "It's really big on Reddit, you know? Then we share it.")
        #expect(write("It was, like, huge.", .formal, .light) == "It was, like, huge.")
    }

    @Test func aSpokenListCanBeBulletedOrLeftInItsSentence() {
        let heard = "Buy one, eggs, two, milk, and three, bread. Then go home."
        #expect(write(heard, lists: .numbered) == "Buy:\n1. eggs\n2. milk\n3. bread\nThen go home.")
        #expect(write(heard, lists: .bulleted) == "Buy:\n• eggs\n• milk\n• bread\nThen go home.")
        #expect(write(heard, lists: .off) == heard)
        let typed = DictationWriting(style: .formal, lists: .bulleted).typed(heard, lexicon: lexicon)
        #expect(typed == "Buy:\n• Eggs\n• Milk\n• Bread\nThen go home.")
        #expect(write("Also, one, eggs, two, milk.", .casual, lists: .bulleted) == "Also:\n• eggs\n• milk")
    }
}
