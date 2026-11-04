import UIKit
import KeyboardCore

/// A panel's tool: an icon at the bar's left.
final class ToolButton: UIControl {
    let panel: Panel
    var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    private let icon = UIImageView()

    init(panel: Panel) {
        self.panel = panel
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.tool.\(panel)"
        accessibilityLabel = panel.title
        isAccessibilityElement = true
        accessibilityTraits = .button
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        icon.image = panel.icon
        layer.cornerCurve = .continuous
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refresh() } }
    }

    private func refresh() {
        icon.tintColor = theme.label.ui
        backgroundColor = isHighlighted ? theme.candidatePill.ui : .clear
    }

    /// The cell is a key wide; taps in the gaps around it still reach it.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -BarLayout.gap / 2, dy: -4).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds
        layer.cornerRadius = min(bounds.height, bounds.width) / 2
    }
}

extension Panel {
    var title: String {
        switch self {
        case .emoji: "Emoji"
        case .gif: "GIFs"
        case .clipboard: "Clipboard"
        }
    }

    /// The tools' glyphs, and the More button's, drawn the same size: about 18 points across or tall.
    var icon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        switch self {
        case .emoji: return UIImage(systemName: "face.smiling", withConfiguration: configuration)
        case .gif: return Self.gifGlyph
        case .clipboard: return UIImage(systemName: "list.clipboard", withConfiguration: configuration)
        }
    }

    /// Raycast's four rounded squares, for the More button, a little narrower than the GIF glyph.
    static let moreGlyph: UIImage = {
        let size = CGSize(width: 22, height: 22), side: CGFloat = 7, gap: CGFloat = 2.4
        return UIGraphicsImageRenderer(size: size).image { _ in
            let origin = (size.width - 2 * side - gap) / 2
            UIColor.black.setFill()
            for row in 0..<2 {
                for column in 0..<2 {
                    let square = CGRect(x: origin + CGFloat(column) * (side + gap), y: origin + CGFloat(row) * (side + gap), width: side, height: side)
                    UIBezierPath(roundedRect: square, cornerRadius: 2).fill()
                }
            }
        }.withRenderingMode(.alwaysTemplate)
    }()

    /// GIF has no SF Symbol: a rounded rect with "GIF" in it (docs/design.md).
    static let gifGlyph: UIImage = {
        let size = CGSize(width: 22, height: 22)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(x: (size.width - 18.4) / 2, y: (size.height - 14.4) / 2, width: 18.4, height: 14.4)
            let path = UIBezierPath(roundedRect: box.insetBy(dx: 0.85, dy: 0.85), cornerRadius: 3.6)
            path.lineWidth = 1.7
            UIColor.black.setStroke()
            path.stroke()
            let text = NSAttributedString(string: "GIF", attributes: [.font: UIFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: UIColor.black])
            let bounds = text.size()
            text.draw(at: CGPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
        }.withRenderingMode(.alwaysTemplate)
    }()
}
