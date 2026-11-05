import Testing
@testable import KeyboardCore

struct ThemeTests {
    @Test func physicalAndMechanicalKeysKeepTheirAppearanceWhileTheBarFollowsTheApp() {
        let lightKeysInDarkApp = KeyboardTheme.named(.physical, appearance: .light, dark: true, style: .ios27)
        #expect(lightKeysInDarkApp.letterKey.top == RGBA(white: 248 / 255))
        #expect(lightKeysInDarkApp.candidateDivider == KeyboardTheme.dark(.ios27).candidateDivider, "the bar sits on iOS's dark card")
        let automatic = KeyboardTheme.named(.mechanical, appearance: .automatic, dark: true, style: .ios27)
        #expect(automatic == KeyboardTheme.named(.mechanical, appearance: .dark, dark: true, style: .ios27))
        #expect(automatic.letterKey.keycap != nil)
    }

    @Test func defaultIsRaycastsInDarkAndTodaysInLight() {
        let light = KeyboardTheme.named(.standard, dark: false, style: .ios27)
        #expect(light.letterKey == KeyboardTheme.light(.ios27).letterKey)
        let dark = KeyboardTheme.named(.standard, dark: true, style: .ios27)
        #expect(dark.letterKey.top == RGBA(white: 47 / 255) && dark.functionKey == dark.letterKey)
        #expect(dark.keyShape == .raycast && KeyboardTheme.dark(.ios27).keyShape == nil)
    }

    @Test func clearKeysHaveNoFillButTheirPreviewDoes() {
        let theme = KeyboardTheme.named(.clear, dark: true, style: .ios27)
        #expect(theme.letterKey.top.alpha == 0)
        #expect(theme.bubble == theme.key)
    }

    @Test func iOS5PressesLabelsIntoItsKeys() {
        let theme = KeyboardTheme.named(.classic, appearance: .dark, dark: false, style: .ios27)
        #expect(theme.letterKey.labelShadow?.y == 1 && theme.functionKey.labelShadow?.y == -1, "light under dark letters, dark over light ones")
        #expect(theme.functionKey.top != theme.letterKey.top && theme.functionKey.rim != nil)
    }

    @Test func raycastsCornersFollowTheLetterKeysWidth() {
        #expect(abs(KeyShape.raycast.cornerRadius(letterWidth: 69) - 13.75) < 0.2, "the open Duo in landscape")
        #expect(abs(KeyShape.raycast.cornerRadius(letterWidth: 55) - 11.75) < 0.2, "the open Duo in portrait")
        #expect(abs(KeyShape.raycast.cornerRadius(letterWidth: 28) - 7.8) < 0.2, "Raycast's app preview")
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
