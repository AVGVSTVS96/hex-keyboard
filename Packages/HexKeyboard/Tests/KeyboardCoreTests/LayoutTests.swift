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

    @Test func globeAppearsOnlyWhenNeeded() {
        let layout = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, showsGlobe: true))
        #expect(layout.keys.contains { $0.action == .nextKeyboard })
    }

    @Test func emailAndURLBottomRows() {
        let email = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, kind: .email))
        #expect(characters(email, row: 3) == "@.")
        let url = Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, kind: .url))
        #expect(characters(url, row: 3) == "./.com")
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

    /// docs/design.md, "Per device": the bar and pill row over the keys, or a panel in their place.
    @Test func theToolbarFollowsTheDesignOnEachScreen() {
        let cover = KeyboardMetrics.for(.phone, width: 466, height: 678)
        #expect(cover.toolbar.height + cover.topInset == 8 + 40 + 8 + 40 + 11)
        #expect(cover.toolbar.panelHeight - cover.toolbar.height == 94, "a panel grows the Duo's keyboard from 359 to 453")
        #expect(cover.cornerRadius == 9 && cover.margin == .none)
        let open = KeyboardMetrics.for(.phone, width: 669, height: 951)
        #expect(open.margin.leading == (669 - 466) / 2 && open.margin.trailing == open.margin.leading, "the open Duo draws the folded keys, centered")
        #expect(open.keyHeight == cover.keyHeight && open.toolbar == cover.toolbar)
        let side = KeyboardMetrics.for(.phone, width: 951, height: 669)
        #expect(side.toolbar.pills == nil && side.keyHeight == 36 && side.margin.leading == (951 - 560) / 2)
        let folded = KeyboardMetrics.for(.phone, width: 678, height: 466)
        #expect(folded.keyHeight == 30 && folded.toolbar.bar == 34 && folded.toolbar.mic == 32)
        let landscape = KeyboardMetrics.for(.phone, width: 874, height: 402)
        #expect(landscape.toolbar.pills == nil && landscape.margin == .none && landscape.topInset == 8)
        #expect(KeyboardMetrics.for(.pad, width: 834, height: 1194).toolbar.pills == nil)
    }

    @Test func centeredKeysDrawNoOneHandedChevron() {
        let context = LayoutContext(device: .phone, layer: .letters)
        let metrics = KeyboardMetrics.for(.phone, width: 669, height: 951)
        #expect(KeyGrid(Layouts.layout(for: context), width: 669, metrics: metrics.grid).expander == nil)
    }
}
