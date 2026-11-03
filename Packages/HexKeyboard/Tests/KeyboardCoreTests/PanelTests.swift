import Testing
@testable import KeyboardCore

struct PanelTests {
    let search = EmojiSearch(text: """
    # Smileys & People
    😀\t52\tgrinning face|face|grin|happy|smile
    😂\t0\tface with tears of joy|face|joy|laugh|lol
    👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿\t2\tthumbs up|+1|hand|thumb|up|yes
    # Food & Drink
    🍕\t300\tpizza|cheese|slice
    🍔\t310\thamburger|burger
    """)

    @Test func theEmojiKeyOpensThePickerAndClosesIt() {
        var engine = TypingEngine()
        let document = TestDocument("hi ")
        engine.handle(.trigger(Key(.emoji)), in: document)
        #expect(engine.panel == .emoji)
        engine.handle(.trigger(Key(.emoji)), in: document)
        #expect(engine.panel == nil)
    }

    @Test func theKeysTypeIntoTheSearchWhileAPanelIsOpenAndReturnClosesIt() {
        var engine = TypingEngine()
        let document = TestDocument("hi ")
        engine.handle(.panel(.emoji), in: document)
        engine.type("pizza", in: document)
        #expect(engine.query == "pizza")
        #expect(document.text == "hi ", "nothing reaches the app while the search has the keys")
        engine.perform(.delete, in: document)
        engine.perform(.space, in: document)
        #expect(engine.query == "pizz ")
        engine.deleteWord(in: document)
        #expect(engine.query == "")
        engine.perform(.delete, in: document)
        #expect(document.text == "hi", "with the search empty, delete reaches the app")
        engine.perform(.return, in: document)
        #expect(engine.panel == nil)
        engine.type("yo", in: document)
        #expect(document.text == "hiyo")
    }

    @Test func holdingDeleteToClearTheSearchStopsBeforeTheApp() {
        var engine = TypingEngine()
        let document = TestDocument("hi there")
        engine.handle(.panel(.emoji), in: document)
        engine.type("ab", in: document)
        engine.handle(.down(Key(.delete), tapCount: 1), in: document)
        for _ in 0..<5 { engine.perform(.delete, in: document) }
        engine.deleteWord(in: document)
        engine.handle(.up(Key(.delete)), in: document)
        #expect(engine.query == "")
        #expect(document.text == "hi there", "the repeat that emptied the search leaves the app alone")
        engine.handle(.down(Key(.delete), tapCount: 1), in: document)
        #expect(document.text == "hi ther", "a new press with the search empty deletes in the app")
    }

    @Test func closingAPanelBringsBackTheFieldsKeys() {
        var engine = TypingEngine(traits: InputTraits(kind: .number))
        let document = TestDocument()
        engine.handle(.panel(.emoji), in: document)
        #expect(engine.layer == .letters)
        engine.handle(.panel(nil), in: document)
        #expect(engine.layer == .numbers, "closed with the back button")
        engine.handle(.panel(.clipboard), in: document)
        engine.perform(.return, in: document)
        #expect(engine.layer == .numbers, "closed with return")
    }

    @Test func theSearchTypesLowercaseAndOnPlainTextKeys() {
        var engine = TypingEngine(traits: InputTraits(kind: .url, returnKind: .go))
        let document = TestDocument()
        engine.handle(.panel(.emoji), in: document)
        #expect(engine.shift == .off)
        #expect(engine.layout(on: .phone).kind == .text)
        #expect(engine.faces(on: .phone).returnKind == .default)
        engine.handle(.panel(nil), in: document)
        #expect(engine.layout(on: .phone).kind == .url)
    }

    @Test func anEmojiFromThePanelEndsTheWordAndIsRemembered() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.type("so good", in: document)
        engine.handle(.panel(.emoji), in: document)
        engine.handle(.emoji("🍕", base: nil), in: document)
        #expect(document.text == "so good🍕")
        #expect(engine.emojiHistory.frequent.first == "🍕")
        #expect(engine.panel == .emoji, "the panel stays open for another pick")
    }

    @Test func searchFindsWordStartsWholeWordsFirstThenYourPicksThenEveryonesOrder() {
        #expect(search.search("pizza", history: EmojiHistory()) == ["🍕"])
        #expect(search.search("face", history: EmojiHistory()) == ["😂", "😀"])
        #expect(search.search("bur", history: EmojiHistory()) == ["🍔"])
        #expect(search.search("thumbs up", history: EmojiHistory()) == ["👍"])
        var history = EmojiHistory()
        history.use("😀")
        #expect(search.search("face", history: history) == ["😀", "😂"])
        #expect(search.search("smi", history: EmojiHistory()) == ["😀"])
    }

    @Test func anEmptySearchShowsYourPicksThenEveryEmojiInApplesOrder() {
        #expect(search.all == ["😀", "😂", "👍", "🍕", "🍔"])
        var history = EmojiHistory()
        history.use("🍔")
        let shown = search.search("", history: history)
        #expect(shown.first == "🍔")
        #expect(shown.count == Set(shown).count, "no emoji twice")
        #expect(shown.suffix(2) == ["😀", "🍕"], "then every emoji not already shown, in Apple's order")
    }

    @Test func aSkinTonePickedForAnEmojiIsWhatThePanelShowsFromThenOn() {
        #expect(search.tones["👍"]?.count == 5)
        #expect(search.base(of: "👍🏽") == "👍")
        var history = EmojiHistory()
        history.use("👍🏽", base: "👍")
        #expect(search.search("thumbs", history: history) == ["👍🏽"])
        #expect(!search.search("", history: history).contains("👍"))
        history.use("👍", base: "👍")
        #expect(search.search("thumbs", history: history) == ["👍"])
    }

}
