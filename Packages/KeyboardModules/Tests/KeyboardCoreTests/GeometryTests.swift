import Testing
@testable import KeyboardCore

/// The keyboard, the app's preview and Your Taps lay out from one `KeyboardGeometry`, on every screen iikb knows.
struct GeometryTests {
    private static let phones = [Size(width: 402, height: 874), Size(width: 874, height: 402), Size(width: 440, height: 956)]
    private static let pads: [(DeviceClass, Size)] = [
        (.compactPad, Size(width: 744, height: 1133)), (.pad, Size(width: 834, height: 1210)), (.largePad, Size(width: 1376, height: 1032)),
    ]

    /// What the preview lays out on `screen`.
    private func preview(_ device: DeviceClass, on screen: Size, settings: KeyboardSettings = .initial) -> KeyboardGeometry {
        KeyboardGeometry(LayoutContext(device: device, layer: .letters, showsGlobe: true, screen: screen, settings: settings), screen: screen, style: .ios27)
    }

    private func letters(_ grid: KeyGrid) -> [Rect] { "qpazm".map { grid.frame(of: String($0))! } }

    @Test func theKeyboardGetsTheScreensWidthButOnTheDuoItsScreensOwn() {
        for screen in Duo.Screen.allCases {
            #expect(preview(.phone, on: screen.size).width == screen.keyboardWidth, "\(screen.name)")
        }
        for screen in Self.phones { #expect(preview(.phone, on: screen).width == screen.width) }
        for (device, screen) in Self.pads { #expect(preview(device, on: screen).width == screen.width, "\(device) is no Duo") }
    }

    @Test func aWindowTheKeyboardWasGivenWins() {
        let context = LayoutContext(device: .phone, layer: .letters)
        #expect(KeyboardGeometry(context, screen: Size(width: 466, height: 678), window: 460, style: .ios27).width == 460)
    }

    @Test func theKeysHeightIsTheMetricsForTheLayoutsRows() {
        var settings = KeyboardSettings.initial
        for numberRow in [false, true] {
            settings.numberRow = numberRow
            for screen in Duo.Screen.allCases.map(\.size) + Self.phones {
                let keys = preview(.phone, on: screen, settings: settings)
                #expect(keys.layout.hasNumberRow == numberRow)
                #expect(keys.height == keys.metrics.height(rows: keys.layout.rows.count, hasNumberRow: numberRow))
            }
        }
    }

    /// Each of the Duo's screens is the screen its size names, so a screen found from a context or from a size is one.
    @Test func everyDuoScreenIsTheOneItsSizeNames() {
        for screen in Duo.Screen.allCases {
            #expect(Duo.Screen(width: screen.size.width, height: screen.size.height) == screen)
            #expect(Duo.Screen(open: screen.isOpen, landscape: screen.isLandscape) == screen)
        }
    }

    /// Your Taps draws a screen's keys whichever screen the app is on: on the Duo, all four, and elsewhere the screen
    /// turned the way the keys were held. They're the keys the preview draws on that screen.
    @Test func yourTapsDrawsTheKeysThePreviewDoesOnEveryScreen() {
        let devices: [(DeviceClass, [Size])] = [(.phone, Duo.Screen.allCases.map(\.size))] + Self.phones.map { (.phone, [$0]) } + Self.pads.map { ($0.0, [$0.1]) }
        for (device, screens) in devices {
            for shown in screens {
                let drawn = preview(device, on: shown)
                let context = LayoutContext(signature: drawn.context.signature)!
                for app in screens + screens.map({ Size(width: $0.height, height: $0.width) }) {
                    let taps = KeyboardGeometry(context, screen: context.screen(on: app), style: .ios27)
                    let label = "\(drawn.context.signature) from \(app)"
                    #expect(taps.width == drawn.width, "\(label)")
                    #expect(taps.metrics == drawn.metrics, "\(label)")
                    #expect(taps.height == drawn.height, "\(label)")
                    #expect(letters(taps.grid) == letters(drawn.grid), "\(label)")
                }
            }
        }
    }

    /// The keyboard, in the window iOS gives it on a screen (measured in the iOS 27.1 simulator), lays out the keys its
    /// preview shows there.
    @Test func theKeyboardLaysOutWhatItsPreviewShows() {
        let engine = TypingEngine()
        let windows: [(DeviceClass, Size, Double)] = [
            (.phone, Size(width: 466, height: 678), 452), (.phone, Size(width: 678, height: 466), 528),
            (.phone, Size(width: 669, height: 951), 669), (.phone, Size(width: 951, height: 669), 801),
        ] + Self.phones.map { (.phone, $0, $0.width) } + Self.pads.map { ($0.0, $0.1, $0.1.width) }
        for (device, screen, window) in windows {
            let real = KeyboardGeometry(engine.layout(on: device, screen: screen, showsGlobe: true), screen: screen, window: window, style: .ios27)
            #expect(real == preview(device, on: screen, settings: engine.settings), "\(device) \(screen)")
        }
    }
}
