import Testing
@testable import KeyboardCore

struct EmojiTests {
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

    @Test func theBarFindsEmojiForContentWordsAndTheirPlurals() {
        #expect(catalog.suggestions(for: "Pizza", history: EmojiHistory()) == ["🍕"])
        #expect(catalog.suggestions(for: "dogs", history: EmojiHistory()) == ["🐶", "🌭", "🐕"])
        #expect(catalog.suggestions(for: "love", history: EmojiHistory()) == ["❤️", "😍", "💕"])
        #expect(catalog.suggestions(for: "with", history: EmojiHistory()).isEmpty, "words that hold a sentence together find none")
        #expect(catalog.suggestions(for: "piz", history: EmojiHistory()).isEmpty, "the bar wants the whole word")
    }

    @Test func theBarOffersWhatYouPickFirstAndRecentPicksOutweighOlderOnes() {
        var history = EmojiHistory()
        history.use("🐕")
        #expect(catalog.suggestions(for: "dog", history: history) == ["🐕", "🐶", "🌭"])
        for _ in 0 ..< 3 { history.use("🌭") }
        #expect(catalog.suggestions(for: "dog", history: history) == ["🌭", "🐕", "🐶"])
        for _ in 0 ..< 4 { history.use("🐕") }
        #expect(catalog.suggestions(for: "dog", history: history) == ["🐕", "🌭", "🐶"])
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
        #expect(engine.emojiHistory.scores["🍕"] != nil)
        engine.type("my dog ", in: document)
        #expect(engine.emojiSuggestions.first == "🐶", "a word just typed still offers its emoji")
        engine.accept(emoji: "🐶", in: document)
        #expect(document.text == "i love 🍕 my dog 🐶 ")
        engine.type("you", in: document)
        #expect(engine.emojiSuggestions.isEmpty)
    }

    @Test func dictationJoinsWhatsThereWithASpace() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.dictated("Hello there."), in: document)
        #expect(document.text == "Hello there.")
        engine.handle(.dictated("How are you?"), in: document)
        #expect(document.text == "Hello there. How are you?")
    }
}
