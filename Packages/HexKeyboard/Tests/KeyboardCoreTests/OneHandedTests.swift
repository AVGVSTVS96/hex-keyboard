import Testing
@testable import KeyboardCore

struct OneHandedTests {
    private func grid(_ hand: OneHanded, width: Double) -> KeyGrid {
        let context = LayoutContext(device: .phone, layer: .letters, oneHanded: hand)
        let metrics = KeyboardMetrics.for(.phone, width: width, height: 874, oneHanded: context.oneHanded)
        return KeyGrid(Layouts.layout(for: context), width: width, metrics: metrics.grid, signature: context.signature)
    }

    private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1.0 / 3 }

    @Test func keysMatchApplesOneHandedKeyboard() {
        for width in [390.0, 402, 440] {
            let left = grid(.left, width: width)
            #expect(near(left.frame(of: "q")!.x, 4) && near(left.frame(of: "q")!.width, 25.8), "\(width)")
            #expect(near(left.frame(of: "p")!.x + left.frame(of: "p")!.width, 316), "\(width)")
            #expect(near(left.frame(of: "a")!.x, 20), "\(width)")
            let right = grid(.right, width: width)
            #expect(near(right.frame(of: "q")!.x, width - 318) && near(right.frame(of: "q")!.width, 26), "\(width)")
            #expect(near(right.frame(of: "p")!.x + right.frame(of: "p")!.width, width - 4), "\(width)")
        }
    }

    @Test func chevronSitsWhereApplesDoes() {
        let left = grid(.left, width: 402).expander
        #expect(left?.pointsRight == true)
        #expect(near(left!.frame.x, 362) && near(left!.frame.y - KeyboardMetrics.phone(width: 402).topInset, 687 - 598))
        let right = grid(.right, width: 440).expander
        #expect(right?.pointsRight == false && near(right!.frame.x, 27.67))
        #expect(grid(.off, width: 402).expander == nil)
    }

    @Test func onlyPhonesInPortraitNarrow() {
        #expect(LayoutContext(device: .phone, layer: .letters, isLandscape: true, oneHanded: .left).oneHanded == .off)
        #expect(LayoutContext(device: .pad, layer: .letters, oneHanded: .right).oneHanded == .off)
        #expect(LayoutContext(device: .phone, layer: .numbers, oneHanded: .right).oneHanded == .right)
        #expect(LayoutContext(device: .phone, layer: .letters, isOpen: true, oneHanded: .left).oneHanded == .off, "the open Duo never narrows, as Apple's doesn't")
    }

    @Test func eachHandLearnsItsOwnTaps() {
        let context = LayoutContext(device: .phone, layer: .letters, oneHanded: .left)
        #expect(context.signature == "phone-portrait-letters-left")
        #expect(LayoutContext(signature: context.signature) == context)
        #expect(LayoutContext(device: .phone, layer: .letters).signature == "phone-portrait-letters")
    }

    @Test func holdingTheLayerKeyOffersTheHandsOnAPhoneInPortraitOnly() {
        let context = LayoutContext(device: .phone, layer: .letters)
        #expect(context.menuKeys(in: Layouts.layout(for: context)).first?.action == .layer(.numbers))
        #expect(context.menu == [.pick(.left), .pick(.off), .pick(.right), .settings])
        let numbers = LayoutContext(device: .phone, layer: .numbers)
        #expect(numbers.menuKeys(in: Layouts.layout(for: numbers)).first?.action == .layer(.letters))
        #expect(LayoutContext(device: .pad, layer: .letters).menu.isEmpty, "an iPad's globe is its key")
        #expect(LayoutContext(device: .phone, layer: .letters, isLandscape: true).menu == [.keep, .settings], "only a phone in portrait narrows for one hand")
    }

    /// Holding 123 is how Bassim reaches Hex's settings, so it offers them on every iPhone screen; where no layout
    /// applies, the layout in use comes first; letting go without sliding changes nothing.
    @Test func holding123OffersHexSettingsOnEveryScreen() {
        for screen in Duo.Screen.allCases {
            let context = LayoutContext(device: .phone, layer: .numbers, showsGlobe: true, isLandscape: screen.isLandscape, isOpen: screen.isOpen)
            #expect(context.menu.suffix(2) == [.nextKeyboard, .settings], "\(screen.name)")
            #expect(context.menu.contains(context.menuPick), "\(screen.name): the layout in use is there, picked")
        }
        var engine = TypingEngine()
        let document = TestDocument()
        engine.handle(.down(Key(.layer(.numbers)), tapCount: 1), in: document)
        let settings = engine.settings
        engine.handle(.keep, in: document)
        #expect(engine.layer == .letters && engine.settings == settings)
    }

    /// Apple's keyboard opens its menu from the globe or emoji key (Apple's guide for the Duo: "long-press the globe or
    /// emoji key, then tap the left or right layout"), so Hex's opens from them too, beside 123, on every layer.
    @Test func holdingTheGlobeOrEmojiOpensTheSameMenu() {
        for screen in Duo.Screen.allCases {
            for layer in KeyboardLayer.allCases {
                var settings = KeyboardSettings()
                settings.split = true
                let context = LayoutContext(device: .phone, layer: layer, showsGlobe: true, screen: screen.size, settings: settings)
                let held = context.menuKeys(in: Layouts.layout(for: context)).map(\.action)
                #expect(held == [.nextKeyboard, .layer(layer == .letters ? .numbers : .letters), .emoji], "\(screen.name), \(layer)")
            }
        }
        var settings = KeyboardSettings()
        (settings.globeKey, settings.emojiKey) = (false, false)
        let bare = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, screen: Duo.Screen.foldedPortrait.size, settings: settings)
        #expect(bare.menuKeys(in: Layouts.layout(for: bare)).map(\.action) == [.layer(.numbers)], "without them, 123 alone")
    }

    @Test func pickingAHandBringsTheLettersBack() {
        var engine = TypingEngine()
        let document = TestDocument()
        let numbers = Key(.layer(.numbers))
        engine.handle(.down(numbers, tapCount: 1), in: document)
        #expect(engine.layer == .numbers)
        engine.handle(.pick(.right), in: document)
        #expect(engine.layer == .letters && engine.settings.oneHanded == .right)
        #expect(engine.layout(on: .phone, screen: Size(width: 402, height: 874)).oneHanded == .right)
        engine.handle(.oneHanded(.off), in: document)
        #expect(engine.settings.oneHanded == .off && engine.layer == .letters)
    }
}
