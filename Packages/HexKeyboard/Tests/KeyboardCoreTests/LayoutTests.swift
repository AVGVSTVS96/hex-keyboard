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
}
