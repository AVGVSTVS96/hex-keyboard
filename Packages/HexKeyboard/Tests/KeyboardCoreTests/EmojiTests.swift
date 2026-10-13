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
