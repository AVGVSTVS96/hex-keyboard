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
    /// The emoji key in the bottom row; without it, the bar's emoji for a word are the way to emoji.
    public var emojiKey = true
    public var oneHanded = OneHanded.off

    public init() {}

    /// What Hex starts with before you change anything: Apple's keyboard, except that auto-capitalization and
    /// auto-correction are opt in.
    public static let initial: KeyboardSettings = {
        var settings = KeyboardSettings()
        settings.autoCapitalization = false
        settings.autoCorrection = false
        return settings
    }()
}
