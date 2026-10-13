/// Apple's One-Handed Keyboard: on an upright iPhone the keys narrow toward one thumb and leave a margin on the other side.
public enum OneHanded: String, Hashable, Sendable, CaseIterable {
    case off, left, right
}

extension OneHanded {
    /// Left to right, as the hands sit in the layer menu.
    public static let menuOrder: [OneHanded] = [.left, .off, .right]
}

/// An item in the menu that holding the layer key opens.
public enum MenuItem: Hashable, Sendable {
    case emoji
    case voice
    case hand(OneHanded)
}
