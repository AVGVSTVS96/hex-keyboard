public enum DeviceClass: Hashable, Sendable, CaseIterable {
    case phone
    case compactPad
    case pad
    case largePad

    /// An iPad by its short side, or an iPhone.
    public init(isPad: Bool, shortSide: Double) {
        self = !isPad ? .phone : shortSide >= 1000 ? .largePad : shortSide < 800 ? .compactPad : .pad
    }
}

public struct LayoutContext: Hashable, Sendable {
    public var device: DeviceClass
    public var layer: KeyboardLayer
    public var kind: InputKind
    /// iOS wants a way to the next keyboard: an iPad's keys carry a globe, and an iPhone's menus offer Next Keyboard,
    /// so a reach for the bottom row never leaves Hex.
    public var showsGlobe: Bool
    /// Wider than tall.
    public var isLandscape: Bool
    /// The iPhone Duo open, on its inner screen, whose keys are half again as wide as folded, on its cover.
    public var isOpen: Bool
    public var oneHanded: OneHanded
    /// The open Duo in landscape with its keys in two halves, one under each thumb.
    public var isSplit: Bool
    /// The emoji key in an iPhone's bottom row, beside space.
    public var showsEmoji: Bool
    /// A row of digits above an iPhone's letters.
    public var showsNumberRow: Bool
    public var keySpacing = KeySpacing.standard
    public var keyboardMenu: KeyboardMenu

    public init(device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false, isLandscape: Bool = false, isOpen: Bool = false, oneHanded: OneHanded = .off, isSplit: Bool = false, showsEmoji: Bool = false, showsNumberRow: Bool = false, keyboardMenu: KeyboardMenu = .both) {
        self.device = device
        self.layer = layer
        self.kind = kind
        self.showsGlobe = showsGlobe
        self.isLandscape = isLandscape
        self.isOpen = isOpen && device == .phone
        self.oneHanded = oneHanded
        self.isSplit = isSplit
        self.showsEmoji = showsEmoji && device == .phone
        self.showsNumberRow = showsNumberRow && device == .phone && layer == .letters
        self.keyboardMenu = device == .phone ? keyboardMenu : .button
        if !allowsOneHanded { self.oneHanded = .off }
        if !allowsSplit { self.isSplit = false }
    }

    /// The layout on a `screen`-sized device as `settings` set it up: the keyboard's, and the app's preview of it.
    public init(device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false, screen: Size, settings: KeyboardSettings) {
        self.init(
            device: device, layer: layer, kind: kind, showsGlobe: showsGlobe, isLandscape: screen.width > screen.height,
            isOpen: Duo.isOpen(short: min(screen.width, screen.height)), oneHanded: settings.oneHanded, isSplit: settings.split,
            showsEmoji: settings.emojiKey, showsNumberRow: settings.numberRow, keyboardMenu: settings.keyboardMenu
        )
        keySpacing = settings.keySpacing
    }

    /// Like Apple's, only an iPhone in portrait narrows its keys for one hand, and on the Duo only folded.
    public var allowsOneHanded: Bool { device == .phone && !isLandscape && !isOpen }

    /// Like Apple's, only the open Duo in landscape splits its keys.
    public var allowsSplit: Bool { isOpen && isLandscape }

    /// The key whose hold opens the layer menu, as Apple's globe opens its menu: the layer key in the bottom row, Hex's
    /// own key nearest where the system draws its globe.
    public func menuKey(in layout: KeyboardLayout) -> Key? {
        layout.rows.last?.lazy.compactMap { item -> Key? in
            if case .key(let key) = item, case .layer = key.action { key } else { nil }
        }.first
    }

    /// What the bar's More button offers, top to bottom: the layouts that apply here (one hand or the other on an
    /// iPhone in portrait, Full and Split on the open Duo in landscape), the next keyboard where an iPhone needs one,
    /// then Hex's settings.
    public var moreMenu: [KeyboardEvent] {
        layoutPicks + (showsGlobe && device == .phone ? [.nextKeyboard] : []) + [.settings]
    }

    /// What holding an iPhone's layer key offers, left to right, on every screen: the More button's items, after the
    /// layout in use where no other applies, so letting go without sliding changes nothing.
    public var menu: [KeyboardEvent] {
        guard keyboardMenu != .button else { return [] }
        return (layoutPicks.isEmpty ? [.keep] : []) + moreMenu
    }

    /// Whether the bar shows its More button.
    public var showsMoreButton: Bool { keyboardMenu != .hold }

    /// The layouts that apply here.
    public var layoutPicks: [KeyboardEvent] {
        if allowsSplit { [.split(false), .split(true)] }
        else if allowsOneHanded { OneHanded.menuOrder.map(KeyboardEvent.pick) }
        else { [] }
    }

    /// The layout in use, as the menu offers it.
    public var menuPick: KeyboardEvent {
        allowsSplit ? .split(isSplit) : allowsOneHanded ? .pick(oneHanded) : .keep
    }
}

extension LayoutContext {
    /// What a touch model is kept per: the same keys under the same hands, so the open Duo's wider keys learn apart
    /// from its cover's.
    public var signature: String {
        "\(device)-\(isLandscape ? "landscape" : "portrait")-\(layer)" + (isOpen ? "-open" : "") + (oneHanded == .off ? "" : "-\(oneHanded)") + (isSplit ? "-split" : "")
    }

    /// The layout a touch model's signature was kept for.
    public init?(signature: String) {
        let contexts = DeviceClass.allCases.flatMap { device in
            KeyboardLayer.allCases.flatMap { layer in
                [false, true].flatMap { landscape in
                    [false, true].flatMap { open in
                        OneHanded.allCases.flatMap { hand in
                            [false, true].map { LayoutContext(device: device, layer: layer, isLandscape: landscape, isOpen: open, oneHanded: hand, isSplit: $0) }
                        }
                    }
                }
            }
        }
        guard let context = contexts.first(where: { $0.signature == signature }) else { return nil }
        self = context
    }
}

/// The iPhone Duo, the only iPhone over 440 points on the short side.
public enum Duo {
    /// Its four screens, in Bassim's words: folded (the cover) or open (the inner screen), each in portrait (taller
    /// than wide) or landscape (wider than tall). Slightly folding the open screen keeps its screen: iOS only gives the
    /// keyboard a different height (`KeyboardMetrics.filling`).
    public enum Screen: CaseIterable, Sendable {
        case foldedPortrait, foldedLandscape, openPortrait, openLandscape

        public init(open: Bool, landscape: Bool) {
            self = switch (open, landscape) {
            case (false, false): .foldedPortrait
            case (false, true): .foldedLandscape
            case (true, false): .openPortrait
            case (true, true): .openLandscape
            }
        }

        /// The Duo's screen of that size, or nil on any other device.
        public init?(width: Double, height: Double) {
            let short = min(width, height)
            guard Duo.isDuo(short: short) else { return nil }
            self.init(open: Duo.isOpen(short: short), landscape: width > height)
        }

        public var isOpen: Bool { self == .openPortrait || self == .openLandscape }
        public var isLandscape: Bool { self == .foldedLandscape || self == .openLandscape }

        public var size: Size {
            switch self {
            case .foldedPortrait: Size(width: 466, height: 678)
            case .foldedLandscape: Size(width: 678, height: 466)
            case .openPortrait: Size(width: 669, height: 951)
            case .openLandscape: Size(width: 951, height: 669)
            }
        }

        /// What iOS gives a third-party keyboard of the screen's width, centered on it (iOS 27.1 simulator).
        public var keyboardWidth: Double {
            switch self {
            case .foldedPortrait: 452
            case .foldedLandscape: 528
            case .openPortrait: size.width
            case .openLandscape: 801
            }
        }

        public var name: String {
            switch self {
            case .foldedPortrait: "Folded, portrait"
            case .foldedLandscape: "Folded, landscape"
            case .openPortrait: "Open, portrait"
            case .openLandscape: "Open, landscape"
            }
        }
    }

    public static func isDuo(short side: Double) -> Bool { side > 440 }
    public static func isOpen(short side: Double) -> Bool { side >= 600 }
}

public enum Layouts {
    public static func layout(for context: LayoutContext) -> KeyboardLayout {
        switch context.device {
        case .phone: PhoneLayouts.layout(for: context)
        case .compactPad: CompactPadLayouts.layout(for: context)
        case .pad: PadLayouts.layout(for: context)
        case .largePad: LargePadLayouts.layout(for: context)
        }
    }
}

extension RowItem {
    static func keys(_ primary: String, secondaries: String = "", pairs: Bool = false) -> [RowItem] {
        let secondaries = secondaries.map { $0 == " " ? nil : String($0) }
        return primary.enumerated().map { index, character in
            let value = String(character)
            return .key(Key(
                .character(value),
                alternates: Alternates.for(value),
                secondary: index < secondaries.count ? secondaries[index] : nil,
                isPair: pairs
            ))
        }
    }

    static let flexible = RowItem.spacer(.fill)
}
