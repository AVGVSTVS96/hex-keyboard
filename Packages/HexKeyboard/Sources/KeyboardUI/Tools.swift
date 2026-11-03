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

    /// The cell is the mic's size; taps in the gaps around it still reach it.
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

    var icon: UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        switch self {
        case .emoji: return UIImage(systemName: "face.smiling", withConfiguration: configuration)
        case .gif: return Self.gifGlyph
        case .clipboard: return UIImage(systemName: "list.clipboard", withConfiguration: configuration)
        }
    }

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
