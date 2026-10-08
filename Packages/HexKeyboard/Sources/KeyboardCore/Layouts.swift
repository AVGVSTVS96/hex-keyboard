public enum DeviceClass: Hashable, Sendable {
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

    public init(device: DeviceClass, layer: KeyboardLayer, kind: InputKind = .text, showsGlobe: Bool = false, isLandscape: Bool = false) {
        self.device = device
        self.layer = layer
        self.kind = kind
        self.showsGlobe = showsGlobe
        self.isLandscape = isLandscape
    }
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
