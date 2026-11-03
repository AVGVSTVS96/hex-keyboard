public struct KeyboardSettings: Hashable, Sendable {
    public var autoCapitalization = true
    public var autoCorrection = true
    public var capsLock = true
    public var smartPunctuation = true
    public var periodShortcut = true
    public var predictiveText = true
    public var characterPreview = CharacterPreview.attached
    public var haptics = HapticFeedback.standard
    public var sound = true
    /// The emoji key in the bottom row; without it, the bar's emoji for a word are the way to emoji.
    public var emojiKey = true
    /// The emoji and GIF panels as one row that scrolls sideways on every screen, as they are in landscape.
    public var compactPanels = false
    public var oneHanded = OneHanded.off
    /// The open Duo's keys in two halves while it's wider than tall, as Apple's More button's Split picks.
    public var split = false
    public var theme = ThemeName.standard
    public var themeAppearance = ThemeAppearance.automatic
    /// A row of digits above an iPhone's letters, which grows the keyboard upward.
    public var numberRow = false
    /// The tone emoji take until you pick another for one; nil keeps them yellow.
    public var skinTone: SkinTone?
    /// How the app writes what you dictate (`DictationWriting`).
    public var dictationStyle = DictationStyle.standard
    public var dictationEditing = DictationEditing.standard
    public var dictationLists = true

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

/// What pressing a key shows above it: nothing, the letter in a bubble of its own, or Apple's, the key grown upward.
public enum CharacterPreview: String, CaseIterable, Hashable, Sendable {
    case none, detached, attached

    public var title: String {
        switch self {
        case .none: "None"
        case .detached: "Detached"
        case .attached: "Attached"
        }
    }
}

/// How hard each key taps back: Standard is Apple's keyboard's own values.
public enum HapticFeedback: String, CaseIterable, Hashable, Sendable {
    case off, soft, standard

    public var title: String {
        switch self {
        case .off: "Off"
        case .soft: "Soft"
        case .standard: "Standard"
        }
    }

    /// A share of Apple's intensity.
    public var strength: Double {
        switch self {
        case .off: 0
        case .soft: 0.55
        case .standard: 1
        }
    }
}

/// Unicode's five skin tones, in the order every toned emoji lists them.
public enum SkinTone: String, CaseIterable, Hashable, Sendable {
    case light, mediumLight, medium, mediumDark, dark

    public var title: String {
        switch self {
        case .light: "Light"
        case .mediumLight: "Medium Light"
        case .medium: "Medium"
        case .mediumDark: "Medium Dark"
        case .dark: "Dark"
        }
    }

    /// The tone's modifier, U+1F3FB to U+1F3FF.
    public var modifier: Character {
        ["\u{1F3FB}", "\u{1F3FC}", "\u{1F3FD}", "\u{1F3FE}", "\u{1F3FF}"][SkinTone.allCases.firstIndex(of: self)!]
    }
}
