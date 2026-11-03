import Testing
@testable import KeyboardCore

struct SplitTests {
    private let width = Duo.Screen.openLandscape.keyboardWidth, height = Duo.Screen.openLandscape.size.height

    private func grid(_ layer: KeyboardLayer = .letters, kind: InputKind = .text) -> KeyGrid {
        let context = LayoutContext(device: .phone, layer: layer, kind: kind, showsGlobe: true, isLandscape: true, isOpen: true, isSplit: true, showsEmoji: true)
        let metrics = KeyboardMetrics.for(.phone, width: width, height: height, split: context.isSplit)
        return KeyGrid(Layouts.layout(for: context), width: width, metrics: metrics.grid, signature: context.signature)
    }

    @Test func holding123OrMoreOffersFullSplitAndSettings() {
        let open = LayoutContext(device: .phone, layer: .numbers, isLandscape: true, isOpen: true)
        #expect(open.menu == [.split(false), .split(true), .settings])
        #expect(open.menuKey(in: Layouts.layout(for: open))?.action == .layer(.letters))
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        engine.handle(.split(true), in: document)
        #expect(engine.layer == .letters, "a pick from 123's hold brings the letters back")
    }

    @Test func onlyTheOpenDuoWiderThanTallSplits() {
        #expect(LayoutContext(device: .phone, layer: .letters, isLandscape: true, isOpen: true, isSplit: true).isSplit)
        #expect(!LayoutContext(device: .phone, layer: .letters, isOpen: true, isSplit: true).isSplit)
        #expect(!LayoutContext(device: .phone, layer: .letters, isLandscape: true, isSplit: true).isSplit)
        #expect(!LayoutContext(device: .pad, layer: .letters, isLandscape: true, isSplit: true).isSplit)
    }

    @Test func eachHalfSitsUnderItsThumb() {
        let grid = grid()
        let middle = width / 2
        for row in grid.rows {
            let left = row.filter { $0.frame.midX < middle }, right = row.filter { $0.frame.midX > middle }
            #expect(!left.isEmpty && !right.isEmpty)
            let gap = right.map(\.frame.x).min()! - left.map { $0.frame.x + $0.frame.width }.max()!
            #expect(gap > 60, "at least a key's room between the halves")
            let leftEdge = left.map(\.frame.x).min()!, rightEdge = width - right.map { $0.frame.x + $0.frame.width }.max()!
            #expect(abs(leftEdge - rightEdge) < 0.01, "the halves mirror each other")
        }
    }

    /// Bassim found Apple's split, 57 points a key, used "barely any" of the screen: each half is five keys from the
    /// keyboard's edge with two keys' room between the hands.
    @Test func theSplitFillsTheKeyboard() {
        let full = KeyboardMetrics.for(.phone, width: Duo.Screen.openLandscape.size.width, height: height)
        let letters = KeyGrid(Layouts.layout(for: LayoutContext(device: .phone, layer: .letters, isLandscape: true, isOpen: true)), width: width, metrics: full.grid, signature: "")
        let split = grid()
        let pitch = split.frame(of: "w")!.x - split.frame(of: "q")!.x
        #expect(abs(pitch - (width - 2 * full.sideInset + full.keyGap) / 12) < 0.01)
        #expect(pitch > 57 * 1.15, "well past Apple's 57")
        #expect(split.frame(of: "q")!.width < letters.frame(of: "q")!.width)
        let between = split.frame(of: "y")!.x - (split.frame(of: "t")!.x + split.frame(of: "t")!.width)
        #expect(abs(between - (2 * pitch + full.keyGap)) < 0.01, "two keys' room between T and Y")
        let keys = grid().rows.joined()
        #expect(keys.map(\.frame.x).min()! < 10 && keys.map { $0.frame.x + $0.frame.width }.max()! > width - 10,
                "the halves start at the keyboard's edges, where the full keyboard's keys do")
    }

    @Test func gAndVSitOnBothHalves() {
        let grid = grid()
        for label in ["g", "v"] {
            let left = grid.frame(of: label, nearX: 0, y: grid.frame(of: label)!.midY)!
            let right = grid.frame(of: label, nearX: width, y: left.midY)!
            #expect(left.midX < width / 2 && right.midX > width / 2)
            #expect(grid.key(atX: right.midX, y: right.midY)?.label == label)
        }
        #expect(grid.rows.joined().count { $0.key.action == .space } == 2)
    }

    @Test func aTapOnEitherGTeachesTheSameKey() {
        let grid = grid()
        let left = grid.frame(of: "g", nearX: 0, y: grid.frame(of: "g")!.midY)!
        let right = grid.frame(of: "g", nearX: width, y: left.midY)!
        var model = TouchModel()
        model.learn((0..<20).map { _ in TapSample(tap: Tap(x: right.midX - right.width * 0.3, y: right.midY, key: "g"), intended: "g") }, on: grid)
        #expect(model.center(of: "g", on: grid).x < -0.2, "taps on the right G move the key's learned center")
        let near = model.logLikelihood(x: left.midX - left.width * 0.3, y: left.midY, for: "g", on: grid)!
        let far = model.logLikelihood(x: left.midX + left.width * 0.3, y: left.midY, for: "g", on: grid)!
        #expect(near > far, "and the left G learns the same aim")
    }

    @Test func everyLayerSplits() {
        for layer in KeyboardLayer.allCases {
            for kind in [InputKind.text, .email, .url, .webSearch] {
                let grid = grid(layer, kind: kind)
                #expect(grid.rows.allSatisfy { row in row.allSatisfy { $0.frame.width > 20 } }, "\(layer) \(kind)")
                #expect(grid.rows.joined().allSatisfy { $0.frame.x >= 0 && $0.frame.x + $0.frame.width <= width })
            }
        }
    }

    @Test func splittingIsASettingThatSticks() {
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.split(true), in: document)
        #expect(engine.layout(on: .phone, screen: Duo.Screen.openLandscape.size).isSplit)
        #expect(engine.layout(on: .phone, screen: Duo.Screen.openLandscape.size).menuPick == .split(true))
        #expect(!engine.layout(on: .phone, screen: Duo.Screen.openPortrait.size).isSplit, "in portrait, the same setting keeps one keyboard")
        engine.handle(.split(false), in: document)
        #expect(!engine.layout(on: .phone, screen: Duo.Screen.openLandscape.size).isSplit)
    }
}
