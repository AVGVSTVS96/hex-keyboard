public enum DeviceClass: Hashable, Sendable, CaseIterable {
    case phone
    case compactPad
    case pad
    case largePad
}

public struct LayoutContext: Hashable, Sendable {
    public var device: DeviceClass
    public var layer: KeyboardLayer
    public var kind: InputKind
    public var showsGlobe: Bool
    public var isLandscape: Bool
    /// The iPhone Duo unfolded, whose keys are half again as wide as on its cover.
    public var isOpen: Bool
    public var oneHanded: OneHanded
    /// The open Duo, wider than tall, with its keys in two halves, one under each thumb.
    public var isSplit: Bool
    /// The emoji key in an iPhone's bottom row, beside space.
    public var showsEmoji: Bool
    /// A row of digits above an iPhone's letters.
    public var showsNumberRow: Bool

    public init(device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false, isLandscape: Bool = false, isOpen: Bool = false, oneHanded: OneHanded = .off, isSplit: Bool = false, showsEmoji: Bool = false, showsNumberRow: Bool = false) {
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
        if !allowsOneHanded { self.oneHanded = .off }
        if !allowsSplit { self.isSplit = false }
    }

    /// Like Apple's, only an upright iPhone narrows its keys for one hand, and on the Duo only its cover.
    public var allowsOneHanded: Bool { device == .phone && !isLandscape && !isOpen }

    /// Like Apple's, only the open Duo wider than tall splits its keys.
    public var allowsSplit: Bool { isOpen && isLandscape }

    /// The key whose hold opens the layer menu, as Apple's globe opens its menu: the layer key in the bottom row, Hex's
    /// own key nearest where the system draws its globe.
    public func menuKey(in layout: KeyboardLayout) -> Key? {
        layout.rows.last?.lazy.compactMap { item -> Key? in
            if case .key(let key) = item, case .layer = key.action { key } else { nil }
        }.first
    }

    /// What holding the layer key offers: the one-handed layouts, where they apply.
    public var menu: [OneHanded] {
        allowsOneHanded ? OneHanded.menuOrder : []
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

/// The iPhone Duo's screens in points, upright: the cover, and the inner screen unfolded. They are the only iPhones over
/// 440 points on the short side.
public enum Duo {
    public static let cover = (width: 466.0, height: 678.0)
    public static let open = (width: 669.0, height: 951.0)

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
