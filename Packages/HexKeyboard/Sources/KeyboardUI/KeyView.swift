import UIKit
import KeyboardCore

final class KeyView: UIView {
    let key: Key
    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let cornerLabel = UILabel()
    private let icon = UIImageView()
    /// A raised key's sides around its face, and the light along their top; hidden on flat keys.
    private let sides = CAGradientLayer()
    private let glow = CAGradientLayer()
    private let face = CAGradientLayer()
    /// The lit line just inside the key's edge, where the theme has one.
    private let rim = CAGradientLayer()
    private let rimShape = CAShapeLayer()
    private var shown = KeyFace(content: .none)
    private var metrics: KeyboardMetrics?

    var theme = KeyboardTheme.lightCurrent {
        didSet {
            guard theme != oldValue else { return }
            if theme.keyShape != oldValue.keyShape { applyFace() }
            updateColors()
        }
    }
    var isPressed = false { didSet { if isPressed != oldValue { updateColors() } } }
    var showsLabel = true { didSet { contentAlpha = showsLabel ? restingAlpha : 0 } }
    var isFlicked = false {
        didSet {
            guard isFlicked != oldValue, let secondary = shown.secondary, case .letter(let primary) = shown.content else { return }
            label.text = isFlicked ? secondary : primary
            secondaryLabel.isHidden = isFlicked
            setNeedsLayout()
        }
    }

    private var contentAlpha: CGFloat = 1 {
        didSet { [label, secondaryLabel, cornerLabel, icon].forEach { $0.alpha = contentAlpha } }
    }

    /// The spacer globe is dimmed, so it reads as a key that does nothing.
    private var restingAlpha: CGFloat { key.action == .globeSpacer ? 0.35 : 1 }

    init(key: Key) {
        self.key = key
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        let still: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "colors": NSNull(), "locations": NSNull(), "frame": NSNull(), "path": NSNull()]
        for shape in [sides, glow, face, rim, rimShape] {
            shape.actions = still
        }
        [sides, face, rim].forEach(layer.addSublayer)
        sides.addSublayer(glow)
        sides.masksToBounds = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        rimShape.fillColor = nil
        rimShape.strokeColor = UIColor.black.cgColor
        rim.mask = rimShape
        icon.contentMode = .center
        label.textAlignment = .center
        secondaryLabel.textAlignment = .center
        [secondaryLabel, cornerLabel, label, icon].forEach(addSubview)
        contentAlpha = restingAlpha
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
        let shape = theme.keyShape
        let labelScale = shape?.labelScale ?? 1
        switch shown.content {
        case .letter(let text):
            label.text = text
            label.font = KeyboardFont.letter(metrics.letterSize * (shape?.letterScale ?? 1))
            icon.image = nil
        case .text(let text):
            label.text = text
            label.font = .systemFont(ofSize: metrics.labelSize * labelScale, weight: .regular)
            icon.image = nil
        case .smallText(let text):
            label.text = text
            label.font = .systemFont(ofSize: metrics.labelSize * 0.75 * labelScale, weight: .regular)
            icon.image = nil
        case .symbol(let name):
            label.text = nil
            let size = metrics.symbolSize * (shape?.symbolScale ?? 1)
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular))
        case .none:
            label.text = nil
            icon.image = nil
        }
        accessibilityLabel = accessibilityName
        accessibilityIdentifier = if case .character(let value) = key.action { "hex.\(value)" } else { "hex.\(accessibilityName)" }
        secondaryLabel.text = shown.secondary
        cornerLabel.text = shown.corner
        let corner = (metrics.secondarySize + 3) * labelScale
        cornerLabel.font = UIFont(name: "HelveticaNeue-Bold", size: corner) ?? .systemFont(ofSize: corner, weight: .bold)
        if shown.secondary != nil, !shown.secondaryIsDimmed {
            label.font = .systemFont(ofSize: metrics.pairSize, weight: .regular)
            secondaryLabel.font = label.font
        } else {
            secondaryLabel.font = .systemFont(ofSize: metrics.secondarySize, weight: .regular)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metrics else { return }
        defer { placeContentOnPixels() }
        layoutPaint(radius: metrics.cornerRadius)
        label.sizeToFit()
        icon.sizeToFit()
        layoutCorner(inset: metrics.cornerRadius)

        switch shown.alignment {
        case .center:
            let offset = isLetter ? metrics.letterOffset : -(theme.keyShape?.labelLift ?? 0)
            label.center = CGPoint(x: bounds.midX, y: bounds.midY + offset)
            icon.center = CGPoint(x: bounds.midX, y: bounds.midY)
        case .bottomLeading, .bottomTrailing:
            let leading = shown.alignment == .bottomLeading
            let inset = metrics.edgeInset
            label.frame.origin = CGPoint(
                x: leading ? inset.width : bounds.width - inset.width - label.bounds.width,
                y: bounds.height - metrics.textBaselineInset - (label.font?.ascender ?? 0)
            )
            icon.frame.origin = CGPoint(
                x: leading ? inset.width : bounds.width - inset.width - icon.bounds.width,
                y: bounds.height - inset.height - icon.bounds.height
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

    /// Centered, a label or icon usually starts between two pixels, and the screen smears its edges across both.
    private func placeContentOnPixels() {
        let scale = traitCollection.displayScale
        for view in [label, secondaryLabel, cornerLabel, icon] {
            view.frame.origin = CGPoint(x: view.frame.minX.rounded(scale: scale), y: view.frame.minY.rounded(scale: scale))
        }
    }

    private func layoutPaint(radius: CGFloat) {
        let curve: CALayerCornerCurve = theme.keyShape == nil ? .circular : .continuous
        let paint = paint
        let height = bounds.height
        sides.frame = bounds
        sides.cornerRadius = radius
        let reach = height * Keycap.glowReach
        glow.frame = CGRect(x: bounds.midX - reach, y: -reach, width: reach * 2, height: reach * 2)
        var faceFrame = bounds
        if paint.keycap != nil {
            faceFrame = bounds.inset(by: UIEdgeInsets(
                top: height * Keycap.faceTop, left: height * Keycap.faceSide, bottom: height * Keycap.faceBottom, right: height * Keycap.faceSide
            ))
        }
        face.frame = faceFrame
        face.cornerRadius = paint.keycap == nil ? radius : radius * Keycap.faceCorner
        for shape in [sides, face] { shape.cornerCurve = curve }
        rim.frame = bounds
        if let line = paint.rim {
            rimShape.lineWidth = line.width
            rimShape.path = Self.outline(bounds.insetBy(dx: line.width / 2, dy: line.width / 2), radius: radius - line.width / 2, curve: curve)
        }
        layer.shadowPath = paint.drop.map { drop in
            Self.outline(bounds.insetBy(dx: drop.blur, dy: 0), radius: max(0, radius - drop.blur), curve: curve)
        }
    }

    /// The key's outline: continuous corners as `cornerCurve` draws them, or circular ones.
    private static func outline(_ rect: CGRect, radius: CGFloat, curve: CALayerCornerCurve) -> CGPath {
        curve == .continuous
            ? UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
            : CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
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
        case .globeSpacer: "spacer"
        case .dictate: "dictate"
        case .dismiss: "dismiss keyboard"
        case .emoji: "emoji"
        }
    }

    private var isLetter: Bool {
        if case .letter = shown.content { true } else { false }
    }

    /// The paint for this key: letters and space in the letter paint, a prominent return in the prominent one, and the
    /// rest in the function paint.
    private var paint: KeyPaint {
        if shown.isProminent { return theme.prominentKey }
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
        if let keycap = paint.keycap {
            sides.colors = keycap.sides.map(\.color.ui.cgColor)
            sides.locations = keycap.sides.map { NSNumber(value: $0.at) }
            glow.colors = [keycap.glow.ui.cgColor, keycap.glow.ui.withAlphaComponent(0).cgColor]
        }
        rim.isHidden = paint.rim == nil
        if let line = paint.rim {
            rim.colors = [line.color.ui.cgColor, line.color.ui.withAlphaComponent(0).cgColor]
            rim.locations = [0, NSNumber(value: line.fade)]
        }
        if let drop = paint.drop, !isPressed || paint.keycap == nil {
            layer.shadowColor = drop.color.ui.cgColor
            layer.shadowOffset = CGSize(width: 0, height: drop.y)
            layer.shadowRadius = drop.blur
            layer.shadowOpacity = 1
        } else {
            layer.shadowOpacity = 0
        }
        let foreground = paint.label.ui
        label.textColor = foreground
        icon.tintColor = foreground
        if let shadow = paint.labelShadow {
            label.shadowColor = shadow.color.ui
            label.shadowOffset = CGSize(width: 0, height: shadow.y)
            cornerLabel.shadowColor = shadow.color.ui
            cornerLabel.shadowOffset = CGSize(width: 0, height: shadow.y)
            icon.layer.shadowColor = shadow.color.ui.cgColor
            icon.layer.shadowOffset = CGSize(width: 0, height: shadow.y)
            icon.layer.shadowRadius = 0
            icon.layer.shadowOpacity = 1
        } else {
            label.shadowColor = nil
            cornerLabel.shadowColor = nil
            icon.layer.shadowOpacity = 0
        }
        secondaryLabel.textColor = shown.secondaryIsDimmed ? theme.secondaryLabel.ui : foreground
        cornerLabel.textColor = foreground.withAlphaComponent(paint.label.alpha * theme.secondaryLabel.alpha)
        setNeedsLayout()
    }
}
