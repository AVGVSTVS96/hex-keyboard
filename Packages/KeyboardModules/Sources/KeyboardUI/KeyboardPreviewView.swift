import UIKit
import KeyboardCore

/// iikb as it looks with some settings, for the app's "Tap to try": the bar and the letter keys the keyboard lays out
/// on the device and screen the app is on (the Duo's folded or open screen, split or one-handed as set), drawn by the keyboard's
/// own views at the width iOS gives the keyboard there and scaled to fit. Nothing in it takes a touch.
public final class KeyboardPreviewView: UIView {
    private static let bottom = 10.0

    private let content = UIView()
    private let bar = SuggestionBar()
    private let keyboard = KeyboardView()
    private var settings = KeyboardSettings.initial
    private var screen = Size(width: 390, height: 844)
    private var dark = false

    /// The card behind the keys: Raycast's preview in a dark app (its photos, Nov 3), iOS's card behind a third-party
    /// keyboard in a light one (docs/design.md, Colors).
    private static let card = (dark: RGBA(red: 0x10 / 255.0, green: 0x10 / 255.0, blue: 0x10 / 255.0), light: RGBA(red: 0xE2 / 255.0, green: 0xE3 / 255.0, blue: 0xE8 / 255.0))

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
        show(settings, dark: traitCollection.userInterfaceStyle == .dark, screen: CGSize(width: screen.width, height: screen.height))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Draws the keyboard as `settings` make it on a `screen`-sized device, in a dark or light app.
    public func show(_ settings: KeyboardSettings, dark: Bool, screen: CGSize) {
        self.settings = settings
        self.dark = dark
        self.screen = Size(width: screen.width, height: screen.height)
        let theme = KeyboardTheme.named(settings.theme, appearance: settings.themeAppearance, dark: dark, style: .current)
        let keys = Self.keys(settings, on: self.screen)
        let faces = KeyFaceContext(device: keys.context.device, layer: .letters, kind: .text, shift: .off, returnKind: .default, returnEnabled: true)
        keyboard.characterPreview = .none
        keyboard.slidesToType = false
        keyboard.update(layout: keys.layout, signature: "preview", metrics: keys.metrics, faces: faces, theme: theme)
        bar.toolbar = keys.metrics.toolbar
        bar.keys = (keys.grid.rows.first ?? []).map { (minX: $0.frame.x, maxX: $0.frame.x + $0.frame.width) }
        bar.update(tools: [.gif, .clipboard], theme: theme)
        bar.update(more: keys.context.showsMoreButton ? UIMenu(children: []) : nil)
        bar.update(mic: .off, recorded: 0, saved: [], waitingFor: nil, notice: nil, theme: theme)
        bar.update([Suggestion("The", .candidate), Suggestion("I", .candidate), Suggestion("And", .candidate)], emoji: [], enabled: true, theme: theme)
        let card = dark ? Self.card.dark : Self.card.light
        content.backgroundColor = card.ui
        setNeedsLayout()
    }

    /// How tall the preview is at `width`, keeping the keyboard's shape on a `screen`-sized device.
    public static func height(forWidth width: CGFloat, settings: KeyboardSettings, screen: CGSize) -> CGFloat {
        let keys = keys(settings, on: Size(width: screen.width, height: screen.height))
        return width * (keys.metrics.toolbar.height + keys.height) / keys.width
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        let keys = Self.keys(settings, on: screen)
        content.transform = .identity
        let top = keys.metrics.toolbar.height
        content.frame = CGRect(x: 0, y: 0, width: keys.width, height: top + keys.height)
        bar.frame = CGRect(x: 0, y: 0, width: keys.width, height: top)
        keyboard.frame = CGRect(x: 0, y: top, width: keys.width, height: keys.height)
        let scale = bounds.width / keys.width
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// The keyboard's own keys on `screen`, at the width iOS gives it there, over the card's bottom.
    private static func keys(_ settings: KeyboardSettings, on screen: Size) -> KeyboardGeometry {
        let device = DeviceClass(isPad: UIDevice.current.userInterfaceIdiom == .pad, shortSide: min(screen.width, screen.height))
        var keys = KeyboardGeometry(LayoutContext(device: device, layer: .letters, showsGlobe: true, screen: screen, settings: settings), screen: screen, style: .current)
        keys.metrics.bottomInset = bottom
        return keys
    }
}
