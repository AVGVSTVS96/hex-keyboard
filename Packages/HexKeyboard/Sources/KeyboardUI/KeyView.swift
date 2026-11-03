import UIKit
import KeyboardCore

final class KeyView: UIView {
    let key: Key
    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let cornerLabel = UILabel()
    private let icon = UIImageView()
    /// A raised key's sides, around its face; hidden on flat keys.
    private let sides = CAGradientLayer()
    private let face = CAGradientLayer()
    private var shown = KeyFace(content: .none)
    private var metrics: KeyboardMetrics?

    var theme = KeyboardTheme.lightCurrent {
        didSet {
            guard theme != oldValue else { return }
            if theme.typeface != oldValue.typeface || theme.capitalLetters != oldValue.capitalLetters || theme.spaceLabel != oldValue.spaceLabel || theme.cornerScale != oldValue.cornerScale {
                applyFace()
            }
            updateColors()
        }
    }
    var isPressed = false { didSet { if isPressed != oldValue { updateColors() } } }
    var showsLabel = true { didSet { contentAlpha = showsLabel ? 1 : 0 } }
    var isFlicked = false {
        didSet {
            guard isFlicked != oldValue, let secondary = shown.secondary, case .letter(let primary) = shown.content else { return }
            label.text = isFlicked ? secondary : letter(primary)
            secondaryLabel.isHidden = isFlicked
            setNeedsLayout()
        }
    }

    private var contentAlpha: CGFloat = 1 {
        didSet { [label, secondaryLabel, cornerLabel, icon].forEach { $0.alpha = contentAlpha } }
    }

    init(key: Key) {
        self.key = key
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        for shape in [sides, face] {
            shape.cornerCurve = .circular
            shape.actions = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull(), "frame": NSNull()]
            layer.addSublayer(shape)
        }
        icon.contentMode = .center
        label.textAlignment = .center
        secondaryLabel.textAlignment = .center
        [secondaryLabel, cornerLabel, label, icon].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ face: KeyFace, metrics: KeyboardMetrics) {
        guard face != shown || metrics != self.metrics else { return }
        shown = face
        self.metrics = metrics
        applyFace()
        updateColors()
    }

    private func applyFace() {
        guard let metrics else { return }
        let classic = theme.typeface == .classic
        switch shown.content {
        case .letter(let text):
            label.text = letter(text)
            label.font = classic ? Self.helvetica(metrics.letterSize * 0.9) : KeyboardFont.letter(metrics.letterSize)
            icon.image = nil
        case .text(let text):
            label.text = text
            label.font = classic ? Self.helvetica(metrics.labelSize * 0.88) : .systemFont(ofSize: metrics.labelSize, weight: .regular)
            icon.image = nil
        case .smallText(let text):
            label.text = text
            label.font = classic ? Self.helvetica(metrics.labelSize * 0.7) : .systemFont(ofSize: metrics.labelSize * 0.75, weight: .regular)
            icon.image = nil
        case .symbol(let name):
            label.text = nil
            let configuration = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: classic ? .semibold : .regular)
            icon.image = UIImage(systemName: name, withConfiguration: configuration)
        case .none:
            label.text = key.action == .space ? theme.spaceLabel : nil
            label.font = Self.helvetica(metrics.labelSize * 0.88)
            icon.image = nil
        }
        accessibilityLabel = accessibilityName
        accessibilityIdentifier = if case .character(let value) = key.action { "hex.\(value)" } else { "hex.\(accessibilityName)" }
        secondaryLabel.text = shown.secondary
        cornerLabel.text = shown.corner
        cornerLabel.font = .systemFont(ofSize: metrics.secondarySize, weight: .regular)
        if shown.secondary != nil, !shown.secondaryIsDimmed {
            label.font = .systemFont(ofSize: metrics.pairSize, weight: .regular)
            secondaryLabel.font = label.font
        } else {
            secondaryLabel.font = .systemFont(ofSize: metrics.secondarySize, weight: .regular)
        }
        setNeedsLayout()
    }

    private func letter(_ text: String) -> String {
        theme.capitalLetters ? text.uppercased() : text
    }

    private static func helvetica(_ size: CGFloat) -> UIFont {
        UIFont(name: "Helvetica-Bold", size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metrics else { return }
        layoutPaint(radius: metrics.cornerRadius * theme.cornerScale)
        label.sizeToFit()
        icon.sizeToFit()
        layoutCorner(inset: metrics.cornerRadius)
        let lift = paint.keycap == nil ? 0 : bounds.height * (Keycap.faceBottom - Keycap.faceTop) / 2

        switch shown.alignment {
        case .center:
            let offset = isLetter ? metrics.letterOffset : 0
            label.center = CGPoint(x: bounds.midX, y: bounds.midY + offset - lift)
            icon.center = CGPoint(x: bounds.midX, y: bounds.midY - lift)
        case .bottomLeading, .bottomTrailing:
            let leading = shown.alignment == .bottomLeading
            let inset = metrics.edgeInset
            label.frame.origin = CGPoint(
                x: leading ? inset.width : bounds.width - inset.width - label.bounds.width,
                y: bounds.height - metrics.textBaselineInset - (label.font?.ascender ?? 0) - lift
            )
            icon.frame.origin = CGPoint(
                x: leading ? inset.width : bounds.width - inset.width - icon.bounds.width,
                y: bounds.height - inset.height - icon.bounds.height - lift
            )
        }

        guard shown.secondary != nil, let font = label.font, let secondaryFont = secondaryLabel.font else {
            return secondaryLabel.frame = .zero
        }
        secondaryLabel.sizeToFit()
        var capTop = metrics.secondaryCapTop
        var baseline = bounds.height - metrics.letterBaselineInset
        if !shown.secondaryIsDimmed {
            capTop = metrics.pairCapTop
            baseline = bounds.height * (1 - metrics.pairBaselineRatio)
        }
        secondaryLabel.frame.origin = CGPoint(
            x: bounds.midX - secondaryLabel.bounds.width / 2,
            y: capTop - (secondaryFont.ascender - secondaryFont.capHeight)
        )
        label.frame.origin = CGPoint(x: bounds.midX - label.bounds.width / 2, y: baseline - font.ascender)
    }

    private func layoutPaint(radius: CGFloat) {
        sides.frame = bounds
        sides.cornerRadius = radius
        var faceFrame = bounds
        if paint.keycap != nil {
            let height = bounds.height
            faceFrame = bounds.inset(by: UIEdgeInsets(
                top: height * Keycap.faceTop, left: height * Keycap.faceSide, bottom: height * Keycap.faceBottom, right: height * Keycap.faceSide
            ))
        }
        face.frame = faceFrame
        face.cornerRadius = paint.keycap == nil ? radius : max(radius - bounds.height * Keycap.faceSide * 0.6, 2)
        layer.shadowPath = paint.drop == nil ? nil : UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    private func layoutCorner(inset: CGFloat) {
        guard shown.corner != nil, let font = cornerLabel.font else { return cornerLabel.frame = .zero }
        cornerLabel.sizeToFit()
        cornerLabel.frame.origin = CGPoint(x: bounds.width - inset - cornerLabel.bounds.width, y: inset - (font.ascender - font.capHeight))
    }

    private var accessibilityName: String {
        switch key.action {
        case .character: label.text ?? ""
        case .space: "space"
        case .delete: "delete"
        case .shift: "shift"
        case .capsLock: "caps lock"
        case .return: label.text ?? "return"
        case .tab: "tab"
        case .layer(.letters): "letters"
        case .layer(.numbers): "numbers"
        case .layer(.symbols): "symbols"
        case .nextKeyboard: "next keyboard"
        case .dismiss: "dismiss keyboard"
        case .emoji: "emoji"
        }
    }

    private var isLetter: Bool {
        if case .letter = shown.content { true } else { false }
    }

    /// The paint for this key as it is now: letters and space in the letter paint, the rest in the function paint,
    /// a prominent return (and, in iOS 5, caps lock) in the prominent one, and shift while it's on lit where the theme
    /// lights it.
    private var paint: KeyPaint {
        if shown.isProminent { return theme.prominentKey }
        if let lit = theme.litKey, shown.lit != .off { return shown.lit == .locked ? theme.prominentKey : lit }
        switch key.action {
        case .character, .space: return theme.letterKey
        default: return theme.functionKey
        }
    }

    private func updateColors() {
        let paint = paint
        backgroundColor = nil
        let top = isPressed ? paint.pressedTop : paint.top
        let bottom = isPressed ? paint.pressedBottom : paint.bottom
        face.colors = [top.ui.cgColor, bottom.ui.cgColor]
        sides.isHidden = paint.keycap == nil
        if let keycap = paint.keycap { sides.colors = [keycap.top.ui.cgColor, keycap.bottom.ui.cgColor] }
        if let drop = paint.drop, !isPressed || paint.keycap == nil {
            layer.shadowColor = drop.color.ui.cgColor
            layer.shadowOffset = CGSize(width: 0, height: drop.y)
            layer.shadowRadius = drop.blur
            layer.shadowOpacity = 1
        } else {
            layer.shadowOpacity = 0
        }
        let foreground = paint.label.ui
        label.textColor = key.action == .space ? foreground.withAlphaComponent(0.6) : foreground
        icon.tintColor = foreground
        if let shadow = paint.labelShadow {
            label.shadowColor = shadow.ui
            label.shadowOffset = CGSize(width: 0, height: -1)
            icon.layer.shadowColor = shadow.ui.cgColor
            icon.layer.shadowOffset = CGSize(width: 0, height: -1)
            icon.layer.shadowRadius = 0
            icon.layer.shadowOpacity = 1
        } else {
            label.shadowColor = nil
            icon.layer.shadowOpacity = 0
        }
        secondaryLabel.textColor = shown.secondaryIsDimmed ? theme.secondaryLabel.ui : foreground
        cornerLabel.textColor = theme.secondaryLabel.ui
        setNeedsLayout()
    }
}
