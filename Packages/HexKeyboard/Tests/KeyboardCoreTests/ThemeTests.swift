import Testing
@testable import KeyboardCore

struct ThemeTests {
    @Test func physicalAndMechanicalKeysKeepTheirAppearanceWhileTheBarFollowsTheApp() {
        let lightKeysInDarkApp = KeyboardTheme.named(.physical, appearance: .light, dark: true, style: .ios27)
        #expect(lightKeysInDarkApp.letterKey.top == .white)
        #expect(lightKeysInDarkApp.candidateDivider == KeyboardTheme.dark(.ios27).candidateDivider, "the bar sits on iOS's dark card")
        let automatic = KeyboardTheme.named(.mechanical, appearance: .automatic, dark: true, style: .ios27)
        #expect(automatic == KeyboardTheme.named(.mechanical, appearance: .dark, dark: true, style: .ios27))
        #expect(automatic.letterKey.keycap != nil)
    }

    @Test func defaultIsTodaysKeyboard() {
        for dark in [false, true] {
            let theme = KeyboardTheme.named(.standard, dark: dark, style: .ios27)
            #expect(theme == (dark ? KeyboardTheme.dark(.ios27) : KeyboardTheme.light(.ios27)))
            #expect(theme.letterKey.top == theme.key && theme.functionKey == theme.letterKey)
        }
    }

    @Test func clearKeysHaveNoFillButTheirPreviewDoes() {
        let theme = KeyboardTheme.named(.clear, dark: true, style: .ios27)
        #expect(theme.letterKey.top.alpha == 0)
        #expect(theme.bubble == theme.key)
    }

    @Test func iOS5ShowsCapitalsAndSetsFunctionKeysApart() {
        let theme = KeyboardTheme.named(.classic, appearance: .dark, dark: false, style: .ios27)
        #expect(theme.capitalLetters && theme.typeface == .classic && theme.spaceLabel == "space")
        #expect(theme.functionKey.top != theme.letterKey.top && theme.functionKey.labelShadow != nil)
        #expect(theme.litKey == theme.letterKey)
    }

    @Test func shiftKeysSayWhetherShiftIsOn() {
        let context = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .locked, returnKind: .default, returnEnabled: true)
        #expect(KeyFace(Key(.shift), trailing: false, context: context).lit == .locked)
        #expect(KeyFace(Key(.character("a")), trailing: false, context: context).lit == .off)
    }

    @Test func theNumberRowGrowsTheKeyboardUpwardAndLeavesTheLettersWhereTheyWere() {
        let plain = LayoutContext(device: .phone, layer: .letters, showsGlobe: true)
        var numbered = plain
        numbered.showsNumberRow = true
        let metrics = KeyboardMetrics.for(.phone, width: 466, height: 678, style: .ios27)
        let without = Layouts.layout(for: plain), with = Layouts.layout(for: numbered)
        #expect(with.hasNumberRow && with.rows.count == without.rows.count + 1)
        let grow = metrics.height(rows: with.rows.count, hasNumberRow: true) - metrics.height(rows: without.rows.count, hasNumberRow: false)
        #expect(grow == metrics.numberRowHeight + metrics.rowGap)
        let before = KeyGrid(without, width: 466, metrics: metrics.grid), after = KeyGrid(with, width: 466, metrics: metrics.grid)
        let q = before.frame(of: "q")!, numberedQ = after.frame(of: "q")!
        #expect(numberedQ.x == q.x && numberedQ.y == q.y + grow, "q keeps its place above the bottom")
        #expect(after.frame(of: "1")!.height == metrics.numberRowHeight)
        #expect(!Layouts.layout(for: LayoutContext(device: .phone, layer: .numbers, showsNumberRow: true)).hasNumberRow)
        #expect(!Layouts.layout(for: LayoutContext(device: .pad, layer: .letters, showsNumberRow: true)).hasNumberRow)
    }

    @Test func emojiTakeThePreferredToneUntilYouPickOne() {
        let search = EmojiSearch(text: """
        # Smileys & People
        👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿\t2\tthumbs up|+1|hand|thumb|up|yes
        😀\t52\tgrinning face|face|grin|happy|smile
        """)
        var history = EmojiHistory()
        history.skinTone = .medium
        #expect(search.search("thumb", history: history) == ["👍🏽"])
        #expect(search.search("grin", history: history) == ["😀"], "an emoji without tones stays as it is")
        history.use("👍", base: "👍")
        #expect(search.search("thumb", history: history) == ["👍"], "picking the yellow one keeps it yellow")
        history.use("👍🏿", base: "👍")
        #expect(search.search("thumb", history: history) == ["👍🏿"])
        let catalog = EmojiCatalog(text: "great\t👍", search: search)
        var fresh = EmojiHistory()
        fresh.skinTone = .light
        #expect(catalog.suggestions(for: "great", history: fresh).first == "👍🏻")
    }
}
