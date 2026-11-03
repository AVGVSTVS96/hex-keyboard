import UIKit
import KeyboardCore

/// Two keys, A and B, painted as a theme paints them, as Raycast's theme picker shows each choice. For Physical and
/// Mechanical, Automatic shows A light and B dark.
public final class KeycapSwatchView: UIView {
    private static let key = CGSize(width: 44, height: 46)
    private static let gap: CGFloat = 6
    private static let metrics = KeyboardMetrics.phone(width: 390)
    private let keys = ["a", "b"].map { KeyView(key: Key(.character($0))) }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        keys.forEach(addSubview)
        isAccessibilityElement = false
        show(.standard, dark: traitCollection.userInterfaceStyle == .dark)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `dark` is the app's appearance, which Automatic and the themes without one follow.
    public func show(_ theme: ThemeName, appearance: ThemeAppearance = .automatic, dark: Bool) {
        let split = theme.hasAppearance && appearance == .automatic
        for (index, key) in keys.enumerated() {
            let darkKey = split ? index == 1 : dark
            key.theme = KeyboardTheme.named(theme, appearance: split ? (darkKey ? .dark : .light) : appearance, dark: darkKey, style: .current)
            key.configure(KeyFace(content: .letter(index == 0 ? "A" : "B")), metrics: Self.metrics)
        }
        setNeedsLayout()
    }

    override public var intrinsicContentSize: CGSize {
        CGSize(width: Self.key.width * 2 + Self.gap + 4, height: Self.key.height + 4)
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let scale = min(bounds.width / intrinsicContentSize.width, bounds.height / intrinsicContentSize.height)
        let size = CGSize(width: Self.key.width * scale, height: Self.key.height * scale)
        let width = size.width * 2 + Self.gap * scale
        for (index, key) in keys.enumerated() {
            key.transform = .identity
            key.bounds = CGRect(origin: .zero, size: Self.key)
            key.transform = CGAffineTransform(scaleX: scale, y: scale)
            key.center = CGPoint(x: bounds.midX - width / 2 + size.width / 2 + CGFloat(index) * (size.width + Self.gap * scale), y: bounds.midY)
        }
    }
}
