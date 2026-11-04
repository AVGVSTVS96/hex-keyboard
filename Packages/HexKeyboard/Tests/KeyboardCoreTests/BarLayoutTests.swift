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
        Screen(name: "Duo folded, landscape", device: .phone, width: 678, height: 466, window: 528),
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

    private func layouts(_ screen: Screen) -> [(metrics: KeyboardMetrics, layout: BarLayout, keys: [(minX: Double, maxX: Double)], label: String)] {
        var metrics = KeyboardMetrics.for(screen.device, width: screen.width, height: screen.height, oneHanded: screen.oneHanded)
        metrics = metrics.fitted(screen: screen.width, window: screen.window)
        let context = LayoutContext(device: screen.device, layer: .letters, isLandscape: screen.width > screen.height, oneHanded: screen.oneHanded)
        let grid = KeyGrid(Layouts.layout(for: context), width: screen.window, metrics: metrics.grid)
        let keys = grid.rows[0].map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
        // An iPhone's emoji open from the key beside space, so its bar has two tools at most.
        return Array(0...(screen.device == .phone ? 2 : 3)).flatMap { tools in
            [false, true].map { more in
                let layout = BarLayout(metrics.toolbar, keys: keys, tools: tools, more: more, maximumSlot: screen.device == .phone ? .infinity : 154.5)
                return (metrics, layout, keys, "\(screen.name), \(tools) tools\(more ? " and More" : "")")
            }
        }
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.001 }
    private func center(_ key: (minX: Double, maxX: Double)) -> Double { (key.minX + key.maxX) / 2 }

    /// The More button and the tools are each centered over one of the first keys, all the same size; the mic is centered over
    /// the last key and the bar, and cancel, the mic's size, over the key after the tools.
    @Test func theBarSitsOnTheKeys() {
        for screen in Self.screens {
            for (metrics, layout, keys, label) in layouts(screen) {
                let cells = (layout.more.map { [$0] } ?? []) + layout.tools
                for (index, cell) in cells.enumerated() {
                    #expect(near(cell.midX, center(keys[index])) && cell.width <= keys[index].maxX - keys[index].minX + 0.001, "\(label): cell \(index) is centered over its key")
                    #expect(near(cell.width, cells[0].width), "\(label): every cell is the same size")
                    #expect(cell.y == metrics.toolbar.top && cell.height == metrics.toolbar.bar, "\(label)")
                }
                guard let mic = layout.mic else { Issue.record("\(label): no mic"); continue }
                #expect(near(mic.midX, center(keys[keys.count - 1])) && mic.width == metrics.toolbar.mic, "\(label): the mic over the last key")
                #expect(near(mic.midY, metrics.toolbar.top + metrics.toolbar.bar / 2) && mic.width < metrics.toolbar.bar, "\(label): centered in the bar, smaller than it")
                #expect(near(layout.cancel.midX, center(keys[cells.count])) && near(layout.cancel.midY, mic.midY), "\(label): cancel over the key after the tools")
                #expect(layout.cancel.width == mic.width, "\(label): cancel is the mic's size")
            }
        }
    }

    /// Tools, suggestions and mic sit in order, apart, inside the bar; while you dictate, cancel, then the
    /// recording to the mic's edge.
    @Test func nothingOverlaps() {
        for screen in Self.screens {
            for (_, layout, keys, label) in layouts(screen) {
                let cells = (layout.more.map { [$0] } ?? []) + layout.tools
                let edge = cells.last.map { $0.x + $0.width } ?? keys[0].minX
                #expect(layout.minX >= edge - 0.001, "\(label)")
                for slot in layout.slots {
                    #expect(slot.x >= layout.minX - 0.001 && slot.x + slot.width <= layout.maxX + 0.001, "\(label)")
                    #expect(slot.width >= (screen.oneHanded == .off ? 64 : 48), "\(label): a suggestion has room (\(slot.width))")
                }
                #expect(layout.emoji.x >= layout.minX - 0.001 && layout.emoji.x + layout.emoji.width <= layout.maxX + 0.001, "\(label)")
                if layout.emojiBeside {
                    #expect(layout.slots[2].x + layout.slots[2].width <= layout.emoji.x + 0.001, "\(label)")
                }
                guard let mic = layout.mic else { continue }
                #expect(near(layout.maxX + BarLayout.gap, mic.x) && mic.x + mic.width <= screen.window, "\(label)")
                #expect(layout.cancel.x + layout.cancel.width <= layout.recording.x && near(layout.recording.x + layout.recording.width, mic.x + mic.width), "\(label): cancel, then the recording to the mic's edge")
                #expect(layout.recording.height == mic.height && near(layout.recording.midY, mic.midY), "\(label): the recording is the mic grown")
                #expect(layout.recording.width >= 150, "\(label): the recording has room (\(layout.recording.width))")
            }
        }
    }

    /// With the mic in the bottom row, the bar has no mic, and the suggestions and the recording run to the last key.
    @Test func withoutTheMicTheBarRunsToTheLastKey() {
        for (metrics, _, keys, label) in layouts(Self.screens[0]) {
            let layout = BarLayout(metrics.toolbar, keys: keys, tools: 2, more: true, mic: false)
            #expect(layout.mic == nil && near(layout.maxX, keys[keys.count - 1].maxX), "\(label): the suggestions run to the last key")
            #expect(near(layout.recording.x + layout.recording.width, keys[keys.count - 1].maxX), "\(label): and so does the recording")
        }
    }

    /// Where the bar has room for three suggestions and more, the word's emoji sit beside them; folded in portrait
    /// they take the third suggestion's place.
    @Test func wideBarsKeepTheThirdSuggestion() {
        func beside(_ index: Int) -> Bool { layouts(Self.screens[index]).first { $0.label.hasSuffix("2 tools") }!.layout.emojiBeside }
        #expect(!beside(0) && beside(2) && beside(3))
        let open = layouts(Self.screens[3]).first { $0.label.hasSuffix("2 tools") }!.layout
        #expect(open.emoji.width >= 4 * BarLayout.emojiPitch, "held open in landscape, four emoji show beside")
    }
}
