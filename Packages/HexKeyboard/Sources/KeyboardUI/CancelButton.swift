import UIKit
import KeyboardCore

/// The cancel button beside the recording: an x in a gray circle the mic's size, which gives under your finger as the
/// mic does. `SuggestionBar` moves it, out of the mic and back.
final class CancelButton: UIControl {
    private let face = UIView()
    private let glyph = UIImageView()
    private var glyphSide: CGFloat = 0

    var shows = false {
        didSet {
            isUserInteractionEnabled = shows
            accessibilityElementsHidden = !shows
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.cancel"
        accessibilityLabel = "Cancel Dictation"
        isAccessibilityElement = true
        accessibilityTraits = .button
        face.isUserInteractionEnabled = false
        glyph.contentMode = .center
        addSubview(face)
        face.addSubview(glyph)
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(_ theme: KeyboardTheme) {
        face.backgroundColor = theme.candidatePill.ui
        glyph.tintColor = theme.label.ui
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(springDuration: isHighlighted ? 0.16 : 0.3, bounce: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.face.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }

    /// The x as heavy as the stop beside it and in the same proportion: 11 points in a 28 circle.
    override func layoutSubviews() {
        super.layoutSubviews()
        face.bounds = bounds
        face.center = CGPoint(x: bounds.midX, y: bounds.midY)
        face.layer.cornerRadius = bounds.height / 2
        glyph.frame = bounds
        let side = min(bounds.width, bounds.height)
        guard side != glyphSide, side > 0 else { return }
        glyphSide = side
        glyph.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: (side * 0.39).rounded(), weight: .semibold))
    }
}
