/// Raycast's keyboard themes (docs/design.md, "Themes").
public enum ThemeName: String, CaseIterable, Hashable, Sendable {
    case standard, clear, physical, mechanical, classic

    public var title: String {
        switch self {
        case .standard: "Default"
        case .clear: "Clear"
        case .physical: "Physical"
        case .mechanical: "Mechanical"
        case .classic: "iOS 5"
        }
    }

    /// Physical and Mechanical come dark or light whatever the app is; the rest follow it, and iOS 5 is always iOS 5.
    public var hasAppearance: Bool { self == .physical || self == .mechanical }
}

public enum ThemeAppearance: String, CaseIterable, Hashable, Sendable {
    case automatic, dark, light

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

public enum Typeface: Hashable, Sendable {
    /// SF Compact letters and SF Pro words, as Apple's keyboard has them.
    case standard
    /// Helvetica Bold, as iOS 5's keys had it.
    case classic
}

/// How one kind of key is painted: a face shading from top to bottom, and for a raised key, the keycap's sides around it
/// and the shadow it casts.
public struct KeyPaint: Hashable, Sendable {
    public var top, bottom: RGBA
    public var pressedTop, pressedBottom: RGBA
    public var label: RGBA
    /// iOS 5 pressed its function keys' labels into the key: a dark line just above each glyph.
    public var labelShadow: RGBA?
    public var keycap: Keycap?
    public var drop: Drop?

    public init(top: RGBA, bottom: RGBA, pressedTop: RGBA, pressedBottom: RGBA, label: RGBA, labelShadow: RGBA? = nil, keycap: Keycap? = nil, drop: Drop? = nil) {
        self.top = top
        self.bottom = bottom
        self.pressedTop = pressedTop
        self.pressedBottom = pressedBottom
        self.label = label
        self.labelShadow = labelShadow
        self.keycap = keycap
        self.drop = drop
    }

    public static func flat(_ fill: RGBA, pressed: RGBA, label: RGBA, drop: Drop? = nil) -> KeyPaint {
        KeyPaint(top: fill, bottom: fill, pressedTop: pressed, pressedBottom: pressed, label: label, drop: drop)
    }
}

/// A mechanical keycap: its sides shade from `top` to `bottom` around a face that sits higher than its lower edge.
public struct Keycap: Hashable, Sendable {
    public var top, bottom: RGBA

    public init(top: RGBA, bottom: RGBA) {
        self.top = top
        self.bottom = bottom
    }

    /// The face's inset from the key's edges, as shares of the key's height.
    public static let faceTop = 0.07, faceSide = 0.1, faceBottom = 0.19
}

/// A shadow below a key, `y` down and `blur` wide.
public struct Drop: Hashable, Sendable {
    public var color: RGBA
    public var y, blur: Double

    public init(_ color: RGBA, y: Double, blur: Double) {
        self.color = color
        self.y = y
        self.blur = blur
    }
}

extension KeyboardTheme {
    /// The theme as the keyboard draws it in a host that's dark or light: the bar and panels sit on iOS's card and follow
    /// the host, while Physical and Mechanical keys follow their own appearance.
    public static func named(_ name: ThemeName, appearance: ThemeAppearance = .automatic, dark: Bool, style: KeyboardStyle) -> KeyboardTheme {
        let darkKeys = switch appearance {
        case .automatic: dark
        case .dark: true
        case .light: false
        }
        var theme = dark ? Self.dark(style) : Self.light(style)
        switch name {
        case .standard:
            break
        case .clear:
            let pressed = RGBA(red: theme.label.red, green: theme.label.green, blue: theme.label.blue, alpha: 0.16)
            theme.letterKey = .flat(.clear, pressed: pressed, label: theme.label)
            theme.functionKey = theme.letterKey
        case .physical:
            theme.letterKey = darkKeys
                ? .flat(.rgb(10, 10, 11), pressed: .rgb(58, 58, 60), label: .white)
                : .flat(.white, pressed: .rgb(196, 198, 204), label: .black, drop: Drop(RGBA(white: 0, alpha: 0.2), y: 1, blur: 0))
            theme.functionKey = theme.letterKey
        case .mechanical:
            theme.letterKey = darkKeys
                ? KeyPaint(
                    top: .rgb(40, 40, 42), bottom: .rgb(35, 35, 37), pressedTop: .rgb(28, 28, 30), pressedBottom: .rgb(24, 24, 26), label: .white,
                    keycap: Keycap(top: .rgb(78, 78, 82), bottom: .rgb(14, 14, 15)), drop: Drop(RGBA(white: 0, alpha: 0.7), y: 2, blur: 2)
                )
                : KeyPaint(
                    top: .rgb(252, 252, 252), bottom: .rgb(242, 242, 243), pressedTop: .rgb(222, 222, 224), pressedBottom: .rgb(214, 214, 216),
                    label: .rgb(28, 28, 30), keycap: Keycap(top: .rgb(226, 226, 229), bottom: .rgb(176, 176, 181)),
                    drop: Drop(RGBA(white: 0, alpha: 0.4), y: 1.5, blur: 1.5)
                )
            theme.functionKey = theme.letterKey
        case .classic:
            theme.classic()
        }
        return theme
    }

    /// iOS     /// iOS 5's keyboard: white keys shading to gray, blue-gray function keys with pressed-in white labels, blue for
    /// the prominent return, caps lock and the picked accent, and Helvetica Bold capitals. The blue-gray backdrop stays
    /// out: a keyboard's view sits inside iOS's card, short of its edges, so it would show as a box within the card.
    private mutating func classic() {
        let edge = Drop(.rgb(36, 38, 44), y: 1, blur: 0)
        let pressedIn = RGBA(white: 0, alpha: 0.45)
        letterKey = KeyPaint(top: .rgb(252, 252, 253), bottom: .rgb(212, 214, 219), pressedTop: .rgb(196, 199, 205), pressedBottom: .rgb(172, 176, 184), label: .black, drop: edge)
        functionKey = KeyPaint(
            top: .rgb(165, 171, 182), bottom: .rgb(115, 122, 136), pressedTop: .rgb(132, 138, 150), pressedBottom: .rgb(92, 99, 113),
            label: .white, labelShadow: pressedIn, drop: edge
        )
        prominentKey = KeyPaint(
            top: .rgb(96, 156, 245), bottom: .rgb(36, 98, 216), pressedTop: .rgb(70, 128, 222), pressedBottom: .rgb(26, 78, 190),
            label: .white, labelShadow: pressedIn, drop: edge
        )
        litKey = letterKey
        selection = prominentKey.top
        selectionLabel = .white
        secondaryLabel = RGBA(white: 0, alpha: 0.4)
        cornerScale = 0.62
        typeface = .classic
        capitalLetters = true
        spaceLabel = "space"
    }
}

extension KeyboardTheme {
    /// What a pressed key's preview and a held key's accents are drawn in: the letter keys' face, or the plain key
    /// where the keys have none (Clear).
    public var bubble: RGBA { letterKey.top.alpha > 0 ? letterKey.top : key }
    public var bubbleLabel: RGBA { letterKey.top.alpha > 0 ? letterKey.label : label }
}

extension RGBA {
    static let clear = RGBA(white: 0, alpha: 0)
}
