import Testing
@testable import KeyboardCore

struct LayoutTests {
    private func characters(_ layout: KeyboardLayout, row: Int) -> String {
        layout.rows[row].compactMap { item -> String? in
            guard case .key(let key) = item, case .character(let value) = key.action else { return nil }
            return value
        }.joined()
    }

    @Test func phoneLettersMatchQwerty() {
        let layout = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters))
        #expect(characters(layout, row: 0) == "qwertyuiop")
        #expect(characters(layout, row: 1) == "asdfghjkl")
        #expect(characters(layout, row: 2) == "zxcvbnm")
        #expect(!layout.keys.contains { $0.action == .nextKeyboard })
    }

    /// On iPhone Duo iOS gives a third-party keyboard 452pt of the 466pt screen, 7pt in from each side; Apple's keys,
    /// measured in the iOS 27.1 simulator, sit 46pt apart with q centered 26.5pt and p 439.7pt from the screen's edge.
    @Test func keysSitWhereApplesDoOnIPhoneDuo() {
        let context = LayoutContext(device: .phone, layer: .letters)
        let metrics = KeyboardMetrics.for(.phone, width: 466, height: 678).fitted(screen: 466, window: 452)
        let grid = KeyGrid(Layouts.layout(for: context), width: 452, metrics: metrics.grid, signature: context.signature)
        let center = { (label: String) in 7 + grid.frame(of: label)!.x + grid.frame(of: label)!.width / 2 }
        #expect(abs(center("q") - 26.5) <= 1 && abs(center("p") - 439.7) <= 1)
        #expect(KeyboardMetrics.for(.phone, width: 402, height: 874).fitted(screen: 402, window: 402) == KeyboardMetrics.for(.phone, width: 402, height: 874))
    }

    /// Where iOS wants a way to the next keyboard, an iPhone's globe sits left of 123, away from the emoji key, and
    /// leaves the menu; with Settings' Globe Key off, the menu offers it instead.
    @Test func thePhonesGlobeSitsLeftOf123OrInTheMenu() {
        var settings = KeyboardSettings()
        let duo = { LayoutContext(device: .phone, layer: .letters, showsGlobe: true, screen: Size(width: 466, height: 678), settings: settings) }
        for layer in KeyboardLayer.allCases {
            var context = duo()
            context.layer = layer
            let row = Layouts.layout(for: context).rows.last!.compactMap { if case .key(let key) = $0 { key.action } else { nil } }
            #expect(row.prefix(3) == [.nextKeyboard, .layer(layer == .letters ? .numbers : .letters), .emoji], "\(layer)")
        }
        #expect(!duo().moreMenu.contains(.nextKeyboard))
        settings.globeKey = false
        #expect(!Layouts.layout(for: duo()).keys.contains { $0.action == .nextKeyboard } && duo().moreMenu.contains(.nextKeyboard))
        settings.globeKey = true
        settings.split = true
        let split = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, screen: Size(width: 951, height: 669), settings: settings)
        #expect(split.isSplit && Layouts.layout(for: split).rows.last!.first == .key(Key(.nextKeyboard)))
        let faceID = LayoutContext(device: .phone, layer: .letters, screen: Size(width: 402, height: 874), settings: KeyboardSettings())
        #expect(!Layouts.layout(for: faceID).keys.contains { $0.action == .nextKeyboard }, "iOS draws its own globe under the keys")
    }

    /// With Settings' Record Key on, the record button takes the globe's place left of 123, split or not, on every
    /// iPhone, and the globe goes to the menu.
    @Test func theRecordKeyTakesTheGlobesPlace() {
        var settings = KeyboardSettings()
        settings.micKey = true
        for (width, height) in [(466.0, 678.0), (402, 874), (951, 669)] {
            for split in [false, true] {
                settings.split = split
                let context = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, screen: Size(width: width, height: height), settings: settings)
                let row = Layouts.layout(for: context).rows.last!.compactMap { if case .key(let key) = $0 { key.action } else { nil } }
                #expect(row.prefix(2) == [.dictate, .layer(.numbers)] && !row.contains(.nextKeyboard), "\(width)×\(height)\(split ? " split" : "")")
                #expect(context.moreMenu.contains(.nextKeyboard), "\(width)×\(height)")
            }
        }
        let pad = LayoutContext(device: .pad, layer: .letters, showsGlobe: true, screen: Size(width: 834, height: 1194), settings: settings)
        #expect(!Layouts.layout(for: pad).keys.contains { $0.action == .dictate }, "an iPad keeps its mic in the bar")
    }

    @Test func theNextKeyboardIsInAPhonesMenusAndAPadsKeys() {
        let phone = LayoutContext(device: .phone, layer: .letters, showsGlobe: true)
        #expect(!Layouts.layout(for: phone).keys.contains { $0.action == .nextKeyboard })
        #expect(phone.moreMenu == [.pick(.left), .pick(.off), .pick(.right), .nextKeyboard, .settings])
        #expect(phone.menu == phone.moreMenu)
        let open = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, isOpen: true)
        #expect(open.moreMenu == [.nextKeyboard, .settings] && open.menu == [.keep, .nextKeyboard, .settings])
        #expect(LayoutContext(device: .phone, layer: .letters).moreMenu == [.pick(.left), .pick(.off), .pick(.right), .settings])
        let pad = LayoutContext(device: .pad, layer: .letters, showsGlobe: true)
        #expect(Layouts.layout(for: pad).keys.contains { $0.action == .nextKeyboard } && pad.moreMenu == [.settings])
    }

    /// The menu opens from holding 123, the bar's menu button, or both, as Settings picks; an iPad, with no hold menu,
    /// always keeps its button.
    @Test func theKeyboardMenuOpensWhereSettingsPutIt() {
        var settings = KeyboardSettings()
        let open = { (device: DeviceClass) in LayoutContext(device: device, layer: .letters, showsGlobe: true, screen: Size(width: 402, height: 874), settings: settings) }
        #expect(!open(.phone).menu.isEmpty && open(.phone).showsMoreButton)
        settings.keyboardMenu = .hold
        #expect(!open(.phone).menu.isEmpty && !open(.phone).showsMoreButton)
        #expect(open(.pad).menu.isEmpty && open(.pad).showsMoreButton)
        settings.keyboardMenu = .button
        #expect(open(.phone).menu.isEmpty && open(.phone).showsMoreButton)
    }

    @Test func emailAndURLBottomRows() {
        let email = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, kind: .email))
        #expect(characters(email, row: 3) == "@.")
        let url = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, kind: .url))
        #expect(characters(url, row: 3) == "./.com")
    }

    /// The emoji key is the one Bassim taps most: every field has it, beside 123.
    @Test func everyFieldHasTheEmojiKey() {
        for kind in [InputKind.text, .email, .url, .twitter, .webSearch] {
            for landscape in [false, true] {
                let context = LayoutContext(device: .phone, layer: .letters, kind: kind, isLandscape: landscape, showsEmoji: true)
                let row = Layouts.layout(for: context).rows.last!.compactMap { item -> Key? in if case .key(let key) = item { key } else { nil } }
                #expect(row.prefix(2).map(\.action) == [.layer(.numbers), .emoji], "\(kind)")
                let grid = KeyGrid(Layouts.layout(for: context), width: landscape ? 874 : 402, metrics: KeyboardMetrics.for(.phone, width: landscape ? 874 : 402, height: landscape ? 402 : 874).grid)
                #expect(grid.rows.last!.allSatisfy { $0.frame.width > 30 }, "\(kind): every key has room")
            }
        }
    }

    @Test func everyLayoutHasDeleteAndReturnOrLayerKeys() {
        for device in [DeviceClass.phone, .compactPad, .pad, .largePad] {
            for layer in [KeyboardLayer.letters, .numbers, .symbols] {
                let keys = Layouts.layout(for: LayoutContext(device: device, layer: layer)).keys
                #expect(keys.contains { $0.action == .delete }, "\(device) \(layer)")
                #expect(keys.contains { $0.action == .space }, "\(device) \(layer)")
                #expect(keys.contains { if case .layer = $0.action { true } else { false } }, "\(device) \(layer)")
            }
        }
    }

    @Test func padKeysCarryFlickSecondaries() {
        let layout = Layouts.layout(for: LayoutContext(device: .pad, layer: .letters))
        let q = layout.keys.first { $0.action == .character("q") }
        #expect(q?.secondary == "1")
        #expect(q?.text(shifted: true) == "q")
        #expect(q?.text(shifted: false, flicked: true) == "1")
        let comma = layout.keys.first { $0.action == .character(",") }
        #expect(comma?.text(shifted: true) == "!")
    }

    @Test func alternatesIncludeTheBaseLetter() {
        let e = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)).keys.first { $0.action == .character("e") }
        #expect(e?.alternates.contains("e") == true)
        #expect(e?.alternates.contains("é") == true)
    }

    @Test func landscapePhoneUsesNarrowerBottomKeys() {
        let portrait = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters))
        let landscape = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, isLandscape: true))
        #expect(portrait.keys.first { $0.action == .return }?.width == .pitch(2.5))
        #expect(landscape.keys.first { $0.action == .return }?.width == .pitch(2))
    }

    @Test func bottomRowKeys123AsWideAsEmoji() {
        for isLandscape in [false, true] {
            let keys = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, showsGlobe: true, isLandscape: isLandscape, showsEmoji: true)).keys
            let width = { (action: KeyAction) in keys.first { $0.action == action }?.width.span ?? 0 }
            #expect(width(.emoji) == (isLandscape ? 1 : 1.25), "the emoji key keeps its width")
            #expect(width(.layer(.numbers)) == width(.emoji), "123 is as wide as the emoji key")
            #expect(width(.return) == 1.4, "return is Raycast's")
        }
    }

    @Test func rowsFitTheirColumns() {
        let columns: [DeviceClass: Double] = [.phone: 10, .compactPad: 11.2, .pad: 12.5, .largePad: 14.54]
        for (device, total) in columns {
            for layer in [KeyboardLayer.letters, .numbers, .symbols] {
                for row in Layouts.layout(for: LayoutContext(device: device, layer: layer, showsGlobe: true)).rows {
                    let fixed = row.compactMap(\.width.span).reduce(0, +)
                    #expect(fixed <= total + 0.01, "\(device) \(layer) row overflows: \(fixed)")
                }
            }
        }
    }

    private func rowsAboveBottom(width: Double, style: KeyboardStyle) -> Double {
        let metrics = KeyboardMetrics.phone(width: width, style: style)
        let grid = KeyGrid(Layouts.layout(for: LayoutContext(device: .phone, layer: .letters)), width: width, metrics: metrics.grid)
        return metrics.height(rows: 4, hasNumberRow: false) - grid.rows[0][0].frame.y
    }

    @Test func iOS27MovesRowsAsAppleDoesWithinTheKeyboardsArea() {
        #expect(rowsAboveBottom(width: 402, style: .ios27) - rowsAboveBottom(width: 402, style: .ios26) == -3)
        #expect(rowsAboveBottom(width: 420, style: .ios27) - rowsAboveBottom(width: 420, style: .ios26) == 2)
        #expect(rowsAboveBottom(width: 440, style: .ios27) - rowsAboveBottom(width: 440, style: .ios26) == 2)
    }

    /// docs/design.md, "Per device": the bar over the keys, or a panel in its place.
    @Test func theToolbarFollowsTheDesignOnEachScreen() {
        let cover = KeyboardMetrics.for(.phone, width: 466, height: 678)
        #expect(cover.toolbar.height + cover.topInset == 3 + 38 + 7, "the mic's 38 with 7 above (4 of it iOS's backdrop) and 7 below: Apple's height, with the tools beside the suggestions")
        #expect(cover.toolbar.panelHeight - cover.toolbar.height == 144, "a panel's results and search row replace the bar")
        #expect(!cover.toolbar.isCompact)
        #expect(cover.cornerRadius == 9 && cover.margin == .none)
        let open = KeyboardMetrics.for(.phone, width: 669, height: 951)
        #expect(open.margin == .none && open.toolbar == cover.toolbar)
        let side = KeyboardMetrics.for(.phone, width: 951, height: 669)
        #expect(side.toolbar.isCompact && side.margin == .none && side.toolbar.bar == cover.toolbar.bar)
        let folded = KeyboardMetrics.for(.phone, width: 678, height: 466)
        #expect(folded.toolbar.isCompact && folded.toolbar.bar == 32 && folded.toolbar.mic == 26 && folded.topInset == 7)
        let landscape = KeyboardMetrics.for(.phone, width: 874, height: 402)
        #expect(landscape.toolbar.isCompact && landscape.margin == .none && landscape.topInset == 7)
        #expect(KeyboardMetrics.for(.pad, width: 834, height: 1194).toolbar.isCompact)
    }

    @Test func compactEmojiAndGifsAreOneRowOnEveryScreen() {
        let cover = KeyboardMetrics.for(.phone, width: 466, height: 678).toolbar
        let landscape = KeyboardMetrics.for(.phone, width: 951, height: 669).toolbar
        #expect(cover.showing(.emoji, compact: false) == cover, "the large panels are the default")
        for panel in [Panel.emoji, .gif] {
            let compact = cover.showing(panel, compact: true)
            #expect(compact.isCompact && compact.results == landscape.results && compact.field == landscape.field)
            #expect(compact.height == cover.height, "the bar stays as it is")
            #expect(landscape.showing(panel, compact: true) == landscape)
        }
        #expect(cover.showing(.clipboard, compact: true) == cover, "the clipboard keeps its rows")
        #expect(cover.showing(nil, compact: true) == cover)
    }

    /// His Duo open in portrait, slightly folded: iOS gave the keyboard about 322 of the 420 the GIF panel asked for.
    @Test func aPanelFitsTheRoomIOSGives() {
        let open = KeyboardMetrics.for(.phone, width: 669, height: 951)
        let toolbar = open.toolbar
        let keys = open.height(rows: 4, hasNumberRow: false)
        #expect(toolbar.fitting(toolbar.panelHeight) == toolbar, "a panel that fits keeps its size")
        let given = ((keys + toolbar.panelHeight) * 3).rounded(.down) / 3 - keys
        #expect(toolbar.fitting(given) == toolbar, "the height iOS rounds to the screen's pixels still fits")
        let folded = toolbar.fitting(322 - keys)
        #expect(folded.isCompact && folded.panelHeight <= 322 - keys && folded.results > 40, "one row, still a full one")
        #expect(folded.height == toolbar.height, "the bar stays as it is")
        #expect(toolbar.fitting(0).results == 0)
    }

    /// His Duo open in portrait, slightly folded: iOS gave Apple's keyboard and Hex the same height, about 50pt more than
    /// Hex asked for flat (his photos, Nov 3 1:51am and 1:53am), and Apple's rows took it.
    @Test func theKeysFillTheExtraHeightIOSGives() {
        let open = KeyboardMetrics.for(.phone, width: 669, height: 951)
        let keys = open.height(rows: 4, hasNumberRow: false)
        let tall = open.filling(keys + 50, rows: 4, hasNumberRow: false)
        #expect(tall.height(rows: 4, hasNumberRow: false) == keys + 50)
        #expect(tall.keyHeight == open.keyHeight + 12.5)
        #expect(tall.rowGap == open.rowGap && tall.topInset == open.topInset && tall.bottomInset == open.bottomInset)
        #expect(open.filling(keys, rows: 4, hasNumberRow: false) == open)
        #expect(open.filling(keys - 100, rows: 4, hasNumberRow: false) == open, "short of room, the panel gives way, not the keys")
        let numbers = open.filling(open.height(rows: 5, hasNumberRow: true) + 50, rows: 5, hasNumberRow: true)
        #expect(numbers.height(rows: 5, hasNumberRow: true) == open.height(rows: 5, hasNumberRow: true) + 50)
    }

    /// docs/design.md, "Per device": Apple's keys and letters on each of the Duo's screens, measured in the iOS 27.1
    /// simulator: (key height, row gap, key gap, side inset, letter size). Open, the keys take over Apple's margins and
    /// gaps, in the same height, as Bassim asked.
    @Test func theDuoMatchesApplesKeysOnEachScreen() {
        let screens: [(width: Double, height: Double, keys: [Double])] = [
            (466, 678, [45, 11, 6, 6.5, 25.5]),
            (669, 951, [49.42, 9, 6, 4.5, 28]),
            (678, 466, [33.33, 9, 7, 4.5, 23.5]),
            (951, 669, [41.67, 9, 6, 4.5, 28.5]),
        ]
        for screen in screens {
            let metrics = KeyboardMetrics.for(.phone, width: screen.width, height: screen.height)
            #expect([metrics.keyHeight, metrics.rowGap, metrics.keyGap, metrics.sideInset, metrics.letterSize] == screen.keys, "\(screen.width) × \(screen.height)")
        }
        let apple = [(Duo.Screen.openPortrait, 45.67, 14.0), (.openLandscape, 38.67, 13)]
        for (screen, key, row) in apple {
            let metrics = KeyboardMetrics.for(.phone, width: screen.size.width, height: screen.size.height)
            #expect(abs(metrics.height(rows: 4, hasNumberRow: false) - (metrics.topInset + 4 * key + 3 * row + metrics.bottomInset)) < 0.05, "\(screen.name): Apple's keyboard height")
        }
        #expect(KeyboardMetrics.for(.phone, width: 440, height: 956).letterSize == 23, "regular iPhones keep their letters")
    }

    /// The Duo's keys span the keyboard's whole width on its four screens.
    @Test func theDuosKeysSpanTheWholeWidth() {
        for screen in Duo.Screen.allCases {
            let (width, height) = (screen.size.width, screen.size.height)
            let context = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, isLandscape: width > height)
            let metrics = KeyboardMetrics.for(.phone, width: width, height: height)
            let grid = KeyGrid(Layouts.layout(for: context), width: width, metrics: metrics.grid)
            let frames = grid.rows.flatMap { $0.map(\.frame) }
            let inset = metrics.sideInset + 0.01
            #expect(frames.map(\.x).min()! <= inset && frames.map { $0.x + $0.width }.max()! >= width - inset, "\(width) × \(height)")
            #expect(grid.expander == nil)
        }
    }
}
