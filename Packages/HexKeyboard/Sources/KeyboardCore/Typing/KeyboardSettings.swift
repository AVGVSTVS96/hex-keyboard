public struct KeyboardSettings: Hashable, Sendable {
    public var autoCapitalization = true
    public var autoCorrection = true
    public var capsLock = true
    public var smartPunctuation = true
    public var periodShortcut = true
    public var predictiveText = true
    public var characterPreview = true
    public var haptics = true
    public var sound = true
    public var oneHanded = OneHanded.off
    /// What letting go of a held 123 picks: it sits right above the key, so it's under the thumb as the menu opens.
    public var menuPick = MenuItem.emoji

    public init() {}
}
