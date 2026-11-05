import UIKit
import KeyboardCore

/// The bar's mic: a round button, white on dark and black on light, with a green dot while the app keeps the
/// microphone on. While it listens it turns record red and grows into a capsule over the suggestions, which holds the
/// recording, with a white stop where the mic was and a soft red halo that swells as you talk; while the
/// app writes a dictation down a spinner takes the glyph's place, and a tap still starts the next one. Tap to start or
/// stop; only the app turns the microphone off.
public final class MicButton: UIControl {
    public enum Phase { case off, on, listening, writing }

    /// The face's corner radius, where it takes a key's shape; otherwise round.
    var corner: CGFloat? { didSet { setNeedsLayout() } }
    /// Whether a halo swells around it with your voice while it listens: in the bar, never as the Record Key, whose
    /// neighbors sit too close.
    var breathes = false
    private(set) var phase = Phase.off
    private let halo = UIView()
    private let face = UIView()
    private let glyph = UIImageView()
    private let stop = UIImageView()
    private let dot = UIView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var theme = KeyboardTheme.lightCurrent
    private var glyphSide: CGFloat = 0
    private var voice: CGFloat = 0

    override public init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.mic"
        isAccessibilityElement = true
        accessibilityTraits = .button
        for view in [halo, face] { view.layer.cornerCurve = .continuous }
        for view in [halo, face, glyph, stop, dot, spinner] as [UIView] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        halo.alpha = 0
        stop.alpha = 0
        stop.tintColor = .white
        for view in [glyph, stop] { view.contentMode = .center }
        dot.backgroundColor = UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
        spinner.hidesWhenStopped = false
        spinner.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pressed, it gives by the same 3 points whatever its width.
    override public var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale = isHighlighted ? 1 - 6 / max(bounds.width, 1) : 1
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    /// Into or out of listening it moves on `morph`, the spring the bar grows it on; otherwise it settles.
    public func show(_ phase: Phase, theme: KeyboardTheme) {
        let old = self.phase
        self.phase = phase
        self.theme = theme
        accessibilityLabel = phase == .listening ? "Stop Dictating" : "Dictate"
        accessibilityValue = switch phase {
        case .on: "Mic On"
        case .writing: "Writing"
        case .off, .listening: nil
        }
        if phase != .listening { voice = 0 }
        if phase == .writing { spinner.startAnimating() }
        let done: (Bool) -> Void = { _ in if self.phase != .writing { self.spinner.stopAnimating() } }
        guard phase != old, window != nil else {
            refresh()
            return done(true)
        }
        if (phase == .listening) != (old == .listening) {
            morph(growing: phase == .listening, { self.refresh() }, completion: done)
        } else {
            settle({ self.refresh() }, completion: done)
        }
    }

    /// The halo swells with your voice, on a softer spring than the bars, so it breathes rather than flickers.
    func hear(_ level: Float) {
        guard phase == .listening, breathes else { return }
        voice = loudness(level)
        follow(duration: 0.32) { self.layoutHalo() }
    }

    /// The glyphs never change color: the mic's waveform shrinks away in its own color as the stop, always white,
    /// grows in its place, so neither flashes against the face while it turns red.
    private func refresh() {
        let listening = phase == .listening, idle = phase == .off || phase == .on
        face.backgroundColor = listening ? theme.record.ui : theme.mic.ui
        halo.backgroundColor = theme.record.ui
        halo.alpha = listening && breathes ? 0.2 : 0
        glyph.tintColor = theme.micGlyph.ui
        glyph.alpha = idle ? 1 : 0
        glyph.transform = idle ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        stop.alpha = listening ? 1 : 0
        stop.transform = listening ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        dot.alpha = phase == .on ? 1 : 0
        dot.transform = phase == .on ? .identity : CGAffineTransform(scaleX: 0.5, y: 0.5)
        spinner.color = theme.micGlyph.ui
        spinner.alpha = phase == .writing ? 1 : 0
        spinner.transform = CGAffineTransform(scaleX: phase == .writing ? 0.75 : 0.5, y: phase == .writing ? 0.75 : 0.5)
        layoutHalo()
    }

    /// The glyphs in proportion with the circle (the waveform 15 points in a 28 one, the stop 12), and no bigger than 17
    /// and 13 in the Record Key's key.
    private static func symbol(_ name: String, side: CGFloat, ratio: CGFloat, largest: CGFloat) -> UIImage? {
        UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: min((side * ratio).rounded(), largest), weight: .semibold))
    }

    /// The circle is smaller than a fingertip; taps a little around it still reach it.
    override public func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// The glyphs, spinner and dot sit in the square at the right end of the capsule, or in the middle of a circle or key.
    override public func layoutSubviews() {
        super.layoutSubviews()
        face.frame = bounds
        face.layer.cornerRadius = corner ?? bounds.height / 2
        let side = min(bounds.width, bounds.height)
        let end = CGRect(x: bounds.width > bounds.height * 1.5 ? bounds.width - side : (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        if glyphSide != side, side > 0 {
            glyphSide = side
            glyph.image = Self.symbol("waveform", side: side, ratio: 0.54, largest: 17)
            stop.image = Self.symbol("stop.fill", side: side, ratio: 0.43, largest: 13)
        }
        for view in [glyph, stop] {
            view.bounds.size = end.size
            view.center = CGPoint(x: end.midX, y: end.midY)
        }
        spinner.center = CGPoint(x: end.midX, y: end.midY)
        let dotSide: CGFloat = 6
        dot.bounds = CGRect(x: 0, y: 0, width: dotSide, height: dotSide)
        dot.center = CGPoint(x: end.maxX - dotSide / 2 - end.width * 0.04, y: end.minY + end.width * 0.04 + dotSide / 2)
        dot.layer.cornerRadius = dotSide / 2
        layoutHalo()
    }

    /// The halo hugs the capsule, a point out when you're quiet and four when you're loud.
    private func layoutHalo() {
        let out = phase == .listening ? 1 + 3 * voice : 0
        halo.bounds.size = CGSize(width: bounds.width + 2 * out, height: bounds.height + 2 * out)
        halo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        halo.layer.cornerRadius = (corner ?? bounds.height / 2) + out
    }
}
