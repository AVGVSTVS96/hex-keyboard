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

/// A color a gradient reaches `at` (0 at its start, 1 at its end).
public struct Stop: Hashable, Sendable {
    public var color: RGBA
    public var at: Double

    public init(_ color: RGBA, at: Double) {
        self.color = color
        self.at = at
    }
}

/// How one kind of key is painted: a face shading from top to bottom, and around it, where the theme has them, a lit rim,
/// a keycap's sides and the shadow the key casts.
public struct KeyPaint: Hashable, Sendable {
    public var top, bottom: RGBA
    public var pressedTop, pressedBottom: RGBA
    public var label: RGBA
    /// iOS 5's letterpress: a light line under a dark label, or a dark one over a light label.
    public var labelShadow: LabelShadow?
    public var rim: Rim?
    public var keycap: Keycap?
    public var drop: Drop?

    public init(
        top: RGBA, bottom: RGBA, pressedTop: RGBA, pressedBottom: RGBA, label: RGBA, labelShadow: LabelShadow? = nil, rim: Rim? = nil,
        keycap: Keycap? = nil, drop: Drop? = nil
    ) {
        self.top = top
        self.bottom = bottom
        self.pressedTop = pressedTop
        self.pressedBottom = pressedBottom
        self.label = label
        self.labelShadow = labelShadow
        self.rim = rim
        self.keycap = keycap
        self.drop = drop
    }

    public static func flat(_ fill: RGBA, pressed: RGBA, label: RGBA) -> KeyPaint {
        KeyPaint(top: fill, bottom: fill, pressedTop: pressed, pressedBottom: pressed, label: label)
    }
}

/// A copy of the label `y` points below it (above, when negative).
public struct LabelShadow: Hashable, Sendable {
    public var color: RGBA
    public var y: Double

    public init(_ color: RGBA, y: Double) {
        self.color = color
        self.y = y
    }
}

/// A line `width` points wide just inside the key's edge, lit from above: `color` at the top, gone `fade` of the way down.
public struct Rim: Hashable, Sendable {
    public var color: RGBA
    public var width, fade: Double

    public init(_ color: RGBA, width: Double, fade: Double) {
        self.color = color
        self.width = width
        self.fade = fade
    }
}

/// A mechanical keycap: sides shading down through `sides`, lit by `glow` from the middle of their top edge, around a face
/// set in from the key's edges.
public struct Keycap: Hashable, Sendable {
    public var sides: [Stop]
    public var glow: RGBA

    public init(sides: [Stop], glow: RGBA) {
        self.sides = sides
        self.glow = glow
    }

    /// The face's inset from the key's edges and how far the glow reaches, as shares of the key's height, and its corners
    /// as a share of the key's.
    public static let faceTop = 0.105, faceSide = 0.097, faceBottom = 0.15, glowReach = 0.93, faceCorner = 0.37
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

/// Raycast's keys, on every theme: continuous corners as round as `cornerBase` plus `cornerPerWidth` of a letter key's
/// width (measured on the open Duo upright and on its side, and in its app's preview), letters in SF Pro, rounder than
/// Apple's SF Compact, and letters, labels (`123`) and symbols at these shares of Apple's sizes.
public struct KeyShape: Hashable, Sendable {
    public static let raycast = KeyShape(cornerBase: 3.9, cornerPerWidth: 0.143, letterScale: 1.07, labelScale: 0.67, symbolScale: 0.86)

    public var cornerBase, cornerPerWidth, letterScale, labelScale, symbolScale: Double

    public func cornerRadius(letterWidth: Double) -> Double { cornerBase + cornerPerWidth * letterWidth }
}

extension KeyboardTheme {
    /// The theme as the keyboard draws it in a host that's dark or light: the bar and panels sit on iOS's card and follow
    /// the host, while Physical and Mechanical keys follow their own appearance. Colors are Raycast's, read off its
    /// keyboard and its app's preview on the iPhone Duo (docs/design.md, "Themes").
    public static func named(_ name: ThemeName, appearance: ThemeAppearance = .automatic, dark: Bool, style: KeyboardStyle) -> KeyboardTheme {
        let darkKeys = switch appearance {
        case .automatic: dark
        case .dark: true
        case .light: false
        }
        var theme = dark ? Self.dark(style) : Self.light(style)
        theme.keyShape = .raycast
        switch name {
        case .standard:
            if dark {
                theme.letterKey = .flat(.rgb(47, 47, 47), pressed: theme.keyPressed, label: .white)
                theme.functionKey = theme.letterKey
            }
        case .clear:
            let pressed = RGBA(red: theme.label.red, green: theme.label.green, blue: theme.label.blue, alpha: 0.16)
            theme.letterKey = .flat(.clear, pressed: pressed, label: theme.label)
            theme.functionKey = theme.letterKey
        case .physical:
            theme.letterKey = darkKeys
                ? KeyPaint(
                    top: .rgb(11, 11, 11), bottom: .rgb(5, 5, 5), pressedTop: .rgb(58, 58, 60), pressedBottom: .rgb(52, 52, 54), label: .white,
                    rim: Rim(RGBA(white: 1, alpha: 0.15), width: 1 / 3, fade: 0.25)
                )
                : KeyPaint(
                    top: .rgb(248, 248, 248), bottom: .rgb(248, 248, 248), pressedTop: .rgb(196, 198, 204), pressedBottom: .rgb(196, 198, 204),
                    label: .rgb(44, 44, 44), rim: Rim(RGBA(white: 1, alpha: 0.6), width: 1 / 3, fade: 0.1)
                )
            theme.functionKey = theme.letterKey
        case .mechanical:
            theme.letterKey = darkKeys
                ? KeyPaint(
                    top: .rgb(23, 23, 23), bottom: .rgb(32, 32, 32), pressedTop: .rgb(17, 17, 17), pressedBottom: .rgb(24, 24, 24), label: .white,
                    keycap: Keycap(sides: [Stop(.rgb(23, 23, 23), at: 0), Stop(.rgb(14, 14, 14), at: 0.8), Stop(.rgb(13, 13, 13), at: 1)], glow: RGBA(white: 1, alpha: 0.108))
                )
                : KeyPaint(
                    top: .rgb(250, 250, 250), bottom: .rgb(229, 229, 229), pressedTop: .rgb(232, 232, 232), pressedBottom: .rgb(214, 214, 214),
                    label: .rgb(42, 42, 41), keycap: Keycap(sides: [Stop(.rgb(224, 224, 224), at: 0), Stop(.rgb(219, 219, 219), at: 1)], glow: RGBA(white: 1, alpha: 0.23))
                )
            theme.functionKey = theme.letterKey
        case .classic:
            theme.classic()
        }
        return theme
    }

    /// Raycast's iOS 5: white keys shading to gray with a light line under their labels, blue-gray function keys whose
    /// white labels sit under a dark line and whose top edge catches the light, and a soft shadow under every key.
    private mutating func classic() {
        let drop = Drop(RGBA(white: 0, alpha: 0.3), y: 1, blur: 1)
        let lit = { (alpha: Double) in Rim(RGBA(white: 1, alpha: alpha), width: 0.85, fade: 0.2) }
        let pressedIn = LabelShadow(RGBA(white: 0, alpha: 0.55), y: -1)
        letterKey = KeyPaint(
            top: .rgb(244, 244, 244), bottom: .rgb(196, 197, 201), pressedTop: .rgb(196, 199, 205), pressedBottom: .rgb(172, 176, 184),
            label: .black, labelShadow: LabelShadow(.white, y: 1), rim: lit(0.3), drop: drop
        )
        functionKey = KeyPaint(
            top: .rgb(160, 166, 174), bottom: .rgb(113, 118, 126), pressedTop: .rgb(128, 134, 143), pressedBottom: .rgb(90, 95, 104),
            label: .white, labelShadow: pressedIn, rim: lit(0.18), drop: drop
        )
        prominentKey = KeyPaint(
            top: .rgb(96, 156, 245), bottom: .rgb(36, 98, 216), pressedTop: .rgb(70, 128, 222), pressedBottom: .rgb(26, 78, 190),
            label: .white, labelShadow: pressedIn, drop: drop
        )
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
