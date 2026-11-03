import UIKit
import KeyboardCore

/// Hex as it looks with some settings, for the app's "Tap to try": the bar and the letter keys of an iPhone, drawn by
/// the keyboard's own views at the width of a phone and scaled to fit. Nothing in it takes a touch.
public final class KeyboardPreviewView: UIView {
    private static let width = 390.0
    private static let bottom = 10.0
    private static let faces = KeyFaceContext(device: .phone, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)

    private let content = UIView()
    private let bar = SuggestionBar()
    private let keyboard = KeyboardView()
    private var settings = KeyboardSettings.initial
    private var dark = false

    /// iOS's card behind a third-party keyboard (docs/design.md, Colors).
    private static let card = (dark: RGBA(red: 0x22 / 255.0, green: 0x22 / 255.0, blue: 0x23 / 255.0), light: RGBA(red: 0xE2 / 255.0, green: 0xE3 / 255.0, blue: 0xE8 / 255.0))

    override public init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
        content.addSubview(bar)
        content.addSubview(keyboard)
        addSubview(content)
        isAccessibilityElement = true
        accessibilityLabel = "Keyboard preview"
        show(settings, dark: traitCollection.userInterfaceStyle == .dark)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Draws the keyboard as `settings` make it, in a dark or light app.
    public func show(_ settings: KeyboardSettings, dark: Bool) {
        self.settings = settings
        self.dark = dark
        let theme = KeyboardTheme.named(settings.theme, appearance: settings.themeAppearance, dark: dark, style: .current)
        let (layout, metrics) = Self.layout(settings)
        keyboard.characterPreview = .none
        keyboard.update(layout: layout, signature: "preview", metrics: metrics, faces: Self.faces, theme: theme)
        bar.toolbar = metrics.toolbar
        bar.block = (CGFloat(metrics.sideInset), CGFloat(Self.width - metrics.sideInset))
        bar.update(tools: [.gif, .clipboard], theme: theme)
        bar.update(more: UIMenu(children: []))
        bar.update(mic: .off, listeningSince: nil, notice: nil, theme: theme)
        bar.update([Suggestion("The", .candidate), Suggestion("I", .candidate), Suggestion("And", .candidate)], emoji: [], enabled: true, theme: theme)
        let card = dark ? Self.card.dark : Self.card.light
        content.backgroundColor = card.ui
        setNeedsLayout()
    }

    /// How tall the preview is at `width`, keeping a phone keyboard's shape.
    public static func height(forWidth width: CGFloat, settings: KeyboardSettings) -> CGFloat {
        width * naturalHeight(settings) / Self.width
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let height = Self.naturalHeight(settings)
        let (layout, metrics) = Self.layout(settings)
        content.transform = .identity
        content.frame = CGRect(x: 0, y: 0, width: Self.width, height: height)
        bar.frame = CGRect(x: 0, y: 0, width: Self.width, height: metrics.toolbar.height)
        keyboard.frame = CGRect(x: 0, y: metrics.toolbar.height, width: Self.width, height: metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow))
        let scale = bounds.width / Self.width
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private static func layout(_ settings: KeyboardSettings) -> (KeyboardLayout, KeyboardMetrics) {
        let context = LayoutContext(device: .phone, layer: .letters, showsGlobe: true, showsEmoji: settings.emojiKey, showsNumberRow: settings.numberRow)
        var metrics = KeyboardMetrics.for(.phone, width: width, height: 844, style: .current)
        metrics.bottomInset = bottom
        return (Layouts.layout(for: context), metrics)
    }

    private static func naturalHeight(_ settings: KeyboardSettings) -> Double {
        let (layout, metrics) = layout(settings)
        return metrics.toolbar.height + metrics.height(rows: layout.rows.count, hasNumberRow: layout.hasNumberRow)
    }
}
