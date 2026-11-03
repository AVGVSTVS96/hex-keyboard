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
    /// The open Duo's keys in two halves in landscape, as Apple's More button's Split picks.
    public var split = false
    public var keySpacing = KeySpacing.standard
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

/// How hard each key taps back: Standard, in the middle, is Apple's keyboard's own tap, with three steps softer and
/// three stronger.
public enum HapticFeedback: String, CaseIterable, Hashable, Sendable {
    case off, lightest, lighter, light, standard, strong, stronger, strongest

    public static let levels = allCases.filter { $0 != .off }

    public var title: String {
        switch self {
        case .off: "Off"
        case .lightest: "Lightest"
        case .lighter: "Lighter"
        case .light: "Light"
        case .standard: "Standard"
        case .strong: "Strong"
        case .stronger: "Stronger"
        case .strongest: "Strongest"
        }
    }

    /// A share of Apple's intensity. Strongest doubles Apple's key tap, the most Core Haptics plays.
    public var strength: Double {
        switch self {
        case .off: 0
        case .lightest: 0.5
        case .lighter: 0.65
        case .light: 0.8
        case .standard: 1
        case .strong: 1.3
        case .stronger: 1.6
        case .strongest: 2
        }
    }
}

/// The space between the keys, which sets the keycaps' size: the keyboard and each key's place stay as they are, and
/// the keycaps take what the gaps give up. Standard, in the middle, is iikb's own, with three steps tighter and three
/// roomier.
public enum KeySpacing: String, CaseIterable, Hashable, Sendable {
    case tightest, tighter, tight, standard, roomy, roomier, roomiest

    public var title: String {
        switch self {
        case .tightest: "Tightest"
        case .tighter: "Tighter"
        case .tight: "Tight"
        case .standard: "Standard"
        case .roomy: "Roomy"
        case .roomier: "Roomier"
        case .roomiest: "Roomiest"
        }
    }

    /// A share of the standard gaps: a quarter of them at Tightest, seven quarters at Roomiest.
    public var share: Double {
        Double(Self.allCases.firstIndex(of: self)! + 1) / 4
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
