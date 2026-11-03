public struct RGBA: Hashable, Sendable {
    public var red, green, blue, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: Double, alpha: Double = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> RGBA {
        RGBA(red: red / 255, green: green / 255, blue: blue / 255)
    }

    static let white = RGBA(white: 1)
    static let black = RGBA(white: 0)
}

public enum KeyboardStyle: Hashable, Sendable {
    case ios26, ios27

    public var dimsKeyUnderAccents: Bool { self == .ios27 }
}

public struct KeyboardTheme: Hashable, Sendable {
    public var key: RGBA
    public var keyPressed: RGBA
    public var label: RGBA
    public var secondaryLabel: RGBA
    public var prominent: RGBA
    public var prominentLabel: RGBA
    public var selection: RGBA
    public var selectionLabel: RGBA
    public var shadow: RGBA
    public var candidate: RGBA
    public var candidateHighlighted: RGBA
    public var candidatePill: RGBA
    public var candidateDivider: RGBA
    public var expander: RGBA
    /// The mic's circle and its glyph, the record red, and a panel's search field (docs/design.md, Colors).
    public var mic: RGBA
    public var micGlyph: RGBA
    public var record: RGBA
    public var searchField: RGBA

    /// How each kind of key is painted; the plain themes paint every key with `key`, `keyPressed` and `label`.
    public var letterKey = KeyPaint.flat(.white, pressed: .white, label: .black)
    public var functionKey = KeyPaint.flat(.white, pressed: .white, label: .black)
    public var prominentKey = KeyPaint.flat(.white, pressed: .white, label: .black)
    /// Shift while it's on, where the theme lights it (iOS 5).
    public var litKey: KeyPaint?
    public var cornerScale = 1.0
    public var typeface = Typeface.standard
    /// iOS 5's keys always showed capitals, whatever shift said.
    public var capitalLetters = false
    public var spaceLabel: String?

    public static func light(_ style: KeyboardStyle) -> KeyboardTheme {
        let ios27 = style == .ios27
        return KeyboardTheme.plain(
            key: .white,
            keyPressed: RGBA(red: 0.67, green: 0.69, blue: 0.73),
            label: .black,
            secondaryLabel: RGBA(white: 0, alpha: 0.32),
            prominent: .rgb(0, 122, 255),
            prominentLabel: .white,
            selection: ios27 ? .rgb(226, 228, 232) : .rgb(0, 122, 255),
            selectionLabel: ios27 ? .black : .white,
            shadow: RGBA(white: 0, alpha: 0.18),
            candidate: ios27 ? .rgb(74, 74, 76) : .rgb(54, 56, 60),
            candidateHighlighted: .rgb(44, 46, 49),
            candidatePill: .rgb(235, 237, 240),
            candidateDivider: .rgb(200, 201, 206),
            expander: .white,
            mic: .black,
            micGlyph: .white,
            record: .rgb(255, 59, 48),
            searchField: .white
        )
    }

    public static func dark(_ style: KeyboardStyle) -> KeyboardTheme {
        let ios27 = style == .ios27
        return KeyboardTheme.plain(
            key: RGBA(white: (ios27 ? 68 : 61) / 255),
            keyPressed: RGBA(white: 0.42),
            label: .white,
            secondaryLabel: RGBA(white: 1, alpha: 0.4),
            prominent: .rgb(10, 132, 255),
            prominentLabel: .white,
            selection: ios27 ? RGBA(white: 0.36) : .rgb(10, 132, 255),
            selectionLabel: .white,
            shadow: RGBA(white: 0, alpha: 0.5),
            candidate: ios27 ? .rgb(162, 162, 162) : .rgb(172, 172, 172),
            candidateHighlighted: .white,
            candidatePill: .rgb(115, 115, 115),
            candidateDivider: .rgb(58, 58, 60),
            expander: RGBA(white: 90 / 255),
            mic: .white,
            micGlyph: .black,
            record: .rgb(255, 69, 58),
            searchField: .rgb(51, 51, 53)
        )
    }

    private static func plain(
        key: RGBA, keyPressed: RGBA, label: RGBA, secondaryLabel: RGBA, prominent: RGBA, prominentLabel: RGBA, selection: RGBA,
        selectionLabel: RGBA, shadow: RGBA, candidate: RGBA, candidateHighlighted: RGBA, candidatePill: RGBA, candidateDivider: RGBA,
        expander: RGBA, mic: RGBA, micGlyph: RGBA, record: RGBA, searchField: RGBA
    ) -> KeyboardTheme {
        var theme = KeyboardTheme(
            key: key, keyPressed: keyPressed, label: label, secondaryLabel: secondaryLabel, prominent: prominent,
            prominentLabel: prominentLabel, selection: selection, selectionLabel: selectionLabel, shadow: shadow, candidate: candidate,
            candidateHighlighted: candidateHighlighted, candidatePill: candidatePill, candidateDivider: candidateDivider, expander: expander,
            mic: mic, micGlyph: micGlyph, record: record, searchField: searchField
        )
        theme.letterKey = .flat(key, pressed: keyPressed, label: label)
        theme.functionKey = theme.letterKey
        theme.prominentKey = .flat(prominent, pressed: prominent, label: prominentLabel)
        return theme
    }
}
