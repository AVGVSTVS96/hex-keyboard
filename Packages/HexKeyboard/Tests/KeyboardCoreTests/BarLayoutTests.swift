import Testing
@testable import KeyboardCore

/// The bar on every screen Hex knows, on the Duo's four screens, one-handed, and with each number of tools.
struct BarLayoutTests {
    private struct Screen {
        var name: String
        var device: DeviceClass
        var width, height: Double
        /// The keyboard's window, where iOS gives it less than the screen.
        var window: Double
        var oneHanded = OneHanded.off
    }

    private static let screens: [Screen] = [
        Screen(name: "Duo folded, portrait", device: .phone, width: 466, height: 678, window: 452),
        Screen(name: "Duo folded, landscape", device: .phone, width: 678, height: 466, window: 678),
        Screen(name: "Duo open, portrait", device: .phone, width: 669, height: 951, window: 669),
        Screen(name: "Duo open, landscape", device: .phone, width: 951, height: 669, window: 801),
        Screen(name: "iPhone 17", device: .phone, width: 402, height: 874, window: 402),
        Screen(name: "iPhone 17 Pro Max", device: .phone, width: 440, height: 956, window: 440),
        Screen(name: "iPhone 17 landscape", device: .phone, width: 874, height: 402, window: 874),
        Screen(name: "iPhone 17 left hand", device: .phone, width: 402, height: 874, window: 402, oneHanded: .left),
        Screen(name: "iPhone 17 right hand", device: .phone, width: 402, height: 874, window: 402, oneHanded: .right),
        Screen(name: "iPad mini", device: .compactPad, width: 744, height: 1133, window: 744),
        Screen(name: "iPad Pro 11", device: .pad, width: 834, height: 1210, window: 834),
        Screen(name: "iPad Pro 13", device: .largePad, width: 1032, height: 1376, window: 1032),
    ]

    private func layouts(_ screen: Screen) -> [(metrics: KeyboardMetrics, layout: BarLayout, label: String)] {
        var metrics = KeyboardMetrics.for(screen.device, width: screen.width, height: screen.height, oneHanded: screen.oneHanded)
        metrics = metrics.fitted(screen: screen.width, window: screen.window)
        let block = (minX: metrics.margin.leading + metrics.sideInset, maxX: screen.window - metrics.margin.trailing - metrics.sideInset)
        // An iPhone's emoji open from the key beside space, so its bar has two tools at most.
        return Array(0...(screen.device == .phone ? 2 : 3)).flatMap { tools in
            [false, true].flatMap { more in
                [BarLayout(
                    metrics.toolbar, width: screen.window, screenInset: (screen.width - screen.window) / 2, block: block,
                    topInset: metrics.topInset, tools: tools, more: more, maximumSlot: screen.device == .phone ? .infinity : 154.5
                )].map { (metrics, $0, "\(screen.name), \(tools) tools\(more ? " and More" : "")") }
            }
        }
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }

    /// The mic is never closer to the keyboard's side than it is to the keys below it, and where the keys sit further
    /// in, it lines up with them; the tools mirror it on the left.
    @Test func theMicSitsEvenlyInItsCorner() {
        for screen in Self.screens {
            for (metrics, layout, label) in layouts(screen) {
                let inset = (screen.width - screen.window) / 2
                let toKeys = metrics.toolbar.top + metrics.toolbar.bar - (layout.mic.y + layout.mic.height) + metrics.topInset
                let toSide = screen.window + inset - (layout.mic.x + layout.mic.width)
                let keysSide = screen.window + inset - (screen.window - metrics.margin.trailing - metrics.sideInset)
                #expect(near(toSide, max(toKeys, keysSide)), "\(label): \(toSide) from the side, \(toKeys) from the keys")
                #expect(near(layout.mic.y - metrics.toolbar.top, metrics.toolbar.top + metrics.toolbar.bar - layout.mic.y - layout.mic.height), "\(label): centered in the bar")
                if let leftmost = layout.more ?? layout.tools.first, screen.oneHanded == .off {
                    #expect(near(leftmost.x + inset, toSide), "\(label): what sits leftmost mirrors the mic")
                }
                if let first = layout.tools.first {
                    #expect(first.y == layout.mic.y && first.width == layout.mic.width, "\(label): tools are the mic's size")
                }
            }
        }
    }

    /// Tools, suggestions, emoji and mic sit in order, apart, inside the bar.
    @Test func nothingOverlaps() {
        for screen in Self.screens {
            for (_, layout, label) in layouts(screen) {
                var edge = layout.more?.x ?? layout.tools.first?.x ?? layout.minX
                #expect(edge >= 0, "\(label)")
                if let more = layout.more {
                    #expect(near(more.width, layout.mic.width / 2) && more.y == layout.mic.y, "\(label): More is half a tool, first at the left")
                    edge = more.x + more.width + BarLayout.gap
                }
                for tool in layout.tools {
                    #expect(near(tool.x, edge) || tool.x >= edge, "\(label)")
                    edge = tool.x + tool.width + BarLayout.gap
                }
                #expect(layout.minX >= edge - 0.001, "\(label)")
                for slot in layout.slots {
                    #expect(slot.x >= layout.minX - 0.001 && slot.x + slot.width <= layout.maxX + 0.001, "\(label)")
                    #expect(slot.width >= (screen.oneHanded == .off ? 79 : 53), "\(label): a suggestion has room (\(slot.width))")
                }
                #expect(layout.emoji.x >= layout.minX - 0.001 && layout.emoji.x + layout.emoji.width <= layout.maxX + 0.001, "\(label)")
                if layout.emojiBeside {
                    #expect(layout.slots[2].x + layout.slots[2].width <= layout.emoji.x + 0.001, "\(label)")
                }
                #expect(layout.maxX + BarLayout.gap <= layout.mic.x + 0.001 && layout.mic.x + layout.mic.width <= screen.window, "\(label)")
            }
        }
    }

    /// On an iPhone the mic has the same space above it (to the backdrop iOS draws), below it (to the keys) and beside
    /// it where the keys reach the side: on the Duo folded in portrait, 7 all round, where it had 14 above, 12 below and 7
    /// beside; open in landscape, where iOS draws the backdrop 7 above the keyboard, 7 all round, where it had 10 above.
    @Test func theMicHasTheSameSpaceAllRound() {
        for screen in Self.screens where screen.device == .phone {
            let backdrop = screen.width == 951 ? Toolbar.openWideBackdropAbove : Toolbar.backdropAbove
            for (metrics, layout, label) in layouts(screen) {
                let above = layout.mic.y + backdrop
                let below = metrics.toolbar.height - (layout.mic.y + layout.mic.height) + metrics.topInset
                #expect(near(above, Toolbar.gap) && near(below, Toolbar.gap), "\(label): \(above) above, \(below) below")
            }
        }
        let (_, cover, _) = layouts(Self.screens[0])[0]
        #expect(near(452 + 7 - (cover.mic.x + cover.mic.width), Toolbar.gap))
    }

    /// Where the bar has room for three suggestions and more, the word's emoji sit beside them; folded in portrait
    /// they take the third suggestion's place.
    @Test func wideBarsKeepTheThirdSuggestion() {
        func beside(_ index: Int) -> Bool { layouts(Self.screens[index]).first { $0.label.hasSuffix("2 tools") }!.layout.emojiBeside }
        #expect(!beside(0) && beside(2) && beside(3))
        let open = layouts(Self.screens[3]).first { $0.label.hasSuffix("2 tools") }!.layout
        #expect(open.emoji.width >= 6 * BarLayout.emojiPitch, "held open in landscape, six emoji show beside")
    }
}
