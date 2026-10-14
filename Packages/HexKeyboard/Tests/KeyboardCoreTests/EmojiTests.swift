import Testing
@testable import KeyboardCore

struct EmojiTests {
    @Test func catalogReadsCategoriesAndSkinTones() {
        let catalog = EmojiCatalog(text: "# Smileys & People\n😀\n👋 👋🏻 👋🏼 👋🏽 👋🏾 👋🏿\n# Flags\n🏁\n")
        #expect(catalog.categories.map(\.name) == ["Smileys & People", "Flags"])
        #expect(catalog.categories[0].emoji == ["😀", "👋"])
        #expect(catalog.tones["👋"]?.count == 5)
        #expect(catalog.base(of: "👋🏽") == "👋" && catalog.base(of: "👋") == "👋")
        #expect(catalog.base(of: "😀") == nil)
    }

    @Test func frequentlyUsedFollowsWhatYouPickAndFillsWithStarters() {
        var history = EmojiHistory()
        #expect(history.frequent == Array(EmojiHistory.starters.prefix(EmojiHistory.shown)))
        history.use("🦀")
        #expect(history.frequent.first == "🦀")
        for _ in 0 ..< 3 { history.use("🍕") }
        #expect(history.frequent.prefix(2) == ["🍕", "🦀"])
        for _ in 0 ..< 4 { history.use("🦀") }
        #expect(history.frequent.first == "🦀", "recent uses outweigh older ones")
        #expect(history.frequent.count == EmojiHistory.shown && Set(history.frequent).count == EmojiHistory.shown)
    }

    @Test func aPickedSkinToneSticksUntilTheDefaultIsPicked() {
        var history = EmojiHistory()
        history.use("👋🏽", base: "👋")
        #expect(history.tones["👋"] == "👋🏽")
        history.use("👋🏽")
        #expect(history.tones["👋"] == "👋🏽")
        history.use("👋", base: "👋")
        #expect(history.tones["👋"] == nil)
    }

    @Test func holdingTheLayerKeyOpensEmojiAndABCClosesIt() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        engine.handle(.pick(.emoji), in: document)
        #expect(engine.showsEmoji && engine.layer == .letters)
        engine.handle(.emoji("🎉", base: nil), in: document)
        #expect(document.text == "🎉" && engine.emojiHistory.frequent.first == "🎉")
        engine.handle(.closeEmoji, in: document)
        #expect(!engine.showsEmoji)
    }

    @Test func anEmojiEndsTheWordBeforeIt() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.type("hi", in: document)
        engine.handle(.emoji("👋", base: nil), in: document)
        engine.type(" ok", in: document)
        #expect(document.text == "hi👋 ok")
    }

    @Test func dictationJoinsWhatsThereWithASpace() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.dictated("Hello there."), in: document)
        #expect(document.text == "Hello there.")
        engine.handle(.dictated("How are you?"), in: document)
        #expect(document.text == "Hello there. How are you?")
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        engine.handle(.pick(.voice), in: document)
        #expect(engine.layer == .letters, "picking voice brings the letters back")
    }
}

struct EmojiSearchTests {
    let catalog = EmojiCatalog(text: """
    # Smileys & People
    😂\t0\tface with tears of joy|funny|laugh|lol
    😍\t2\tsmiling face with heart-eyes|love|smile
    👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿\t5\tthumbs up|+1|good|like|yes
    # Animals & Nature
    🐶\t40\tdog face|dog|pet|puppy
    🐕\t90\tdog|pet
    # Food & Drink
    🍕\t30\tpizza|cheese|food|slice
    🌭\t80\thot dog|frankfurter|sausage
    # Symbols
    ❤️\t1\tred heart|heart|love
    💕\t9\ttwo hearts|love
    """)

    @Test func searchPutsWholeWordsFirstThenPrefixesInOrderOfUse() {
        #expect(catalog.search("heart", history: EmojiHistory()) == ["❤️", "😍", "💕"])
        #expect(catalog.search("dog", history: EmojiHistory()) == ["🐶", "🌭", "🐕"])
        #expect(catalog.search("do", history: EmojiHistory()) == ["🐶", "🌭", "🐕"])
        #expect(catalog.search("hot d", history: EmojiHistory()) == ["🌭"])
        #expect(catalog.search("  ", history: EmojiHistory()).isEmpty)
        #expect(catalog.search("zebra", history: EmojiHistory()).isEmpty)
    }

    @Test func searchShowsWhatYouUseFirstInYourSkinTone() {
        var history = EmojiHistory()
        history.use("🐕")
        history.use("👍🏽", base: "👍")
        #expect(catalog.search("dog", history: history) == ["🐕", "🐶", "🌭"])
        #expect(catalog.search("good", history: history) == ["👍🏽"])
    }

    @Test func theBarFindsEmojiForContentWordsAndTheirPlurals() {
        #expect(catalog.suggestions(for: "Pizza", history: EmojiHistory()) == ["🍕"])
        #expect(catalog.suggestions(for: "dogs", history: EmojiHistory()) == ["🐶", "🌭", "🐕"])
        #expect(catalog.suggestions(for: "love", history: EmojiHistory()) == ["❤️", "😍", "💕"])
        #expect(catalog.suggestions(for: "with", history: EmojiHistory()).isEmpty, "words that hold a sentence together find none")
        #expect(catalog.suggestions(for: "piz", history: EmojiHistory()).isEmpty, "the bar wants the whole word")
    }

    @Test func anEmojiFromTheBarTakesTheWordsPlaceOrFollowsIt() {
        var engine = TypingEngine()
        engine.emojiCatalog = catalog
        let document = TestDocument()
        engine.type("i love pizza", in: document)
        #expect(engine.emojiSuggestions == ["🍕"])
        engine.accept(emoji: "🍕", in: document)
        #expect(document.text == "i love 🍕 ")
        #expect(engine.emojiSuggestions.isEmpty)
        #expect(engine.emojiHistory.frequent.first == "🍕")
        engine.type("my dog ", in: document)
        #expect(engine.emojiSuggestions.first == "🐶", "a word just typed still offers its emoji")
        engine.accept(emoji: "🐶", in: document)
        #expect(document.text == "i love 🍕 my dog 🐶 ")
        engine.type("you", in: document)
        #expect(engine.emojiSuggestions.isEmpty)
    }

    @Test func whileSearchingTheKeysTypeIntoTheSearchAndReturnClosesIt() {
        var engine = TypingEngine()
        let document = TestDocument("hi ")
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        engine.handle(.pick(.emoji), in: document)
        engine.handle(.emojiSearch(""), in: document)
        #expect(engine.shift == .off && engine.layout(on: .phone).kind == .text && engine.faces(on: .phone).returnKind == .done)
        engine.type("hot dg", in: document)
        engine.perform(.delete, in: document)
        engine.type("og", in: document)
        #expect(engine.emojiQuery == "hot dog" && document.text == "hi ")
        engine.handle(.emoji("🌭", base: nil), in: document)
        #expect(document.text == "hi 🌭" && engine.emojiQuery == "hot dog", "picking a result types it and keeps the search open")
        engine.deleteWord(in: document)
        #expect(engine.emojiQuery == "hot " && document.text == "hi 🌭")
        engine.handle(.emojiSearch(""), in: document)
        #expect(engine.emojiQuery == "")
        engine.perform(.return, in: document)
        #expect(engine.emojiQuery == nil && engine.showsEmoji && document.text == "hi 🌭")
        engine.handle(.emojiSearch(""), in: document)
        engine.handle(.closeEmoji, in: document)
        #expect(engine.emojiQuery == nil && !engine.showsEmoji)
    }
}
