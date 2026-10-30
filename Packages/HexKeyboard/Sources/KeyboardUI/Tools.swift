import UIKit
import KeyboardCore

/// The row of tools under the bar on an upright iPhone: one pill per panel, equal widths across the keys block. A
/// pill's bottom edge goes nowhere, so a reach for the top row never opens a panel.
final class PillRow: UIView {
    var onTool: (Panel) -> Void = { _ in }
    var block = (minX: CGFloat(0), maxX: CGFloat(0)) { didSet { if block != oldValue { setNeedsLayout() } } }
    private var pills: [ToolButton] = []

    func update(_ panels: [Panel], theme: KeyboardTheme) {
        if panels != pills.map(\.panel) {
            pills.forEach { $0.removeFromSuperview() }
            pills = panels.map { panel in
                let pill = ToolButton(panel: panel, pill: true)
                pill.addAction(UIAction { [unowned self] _ in onTool(panel) }, for: .touchUpInside)
                addSubview(pill)
                return pill
            }
            setNeedsLayout()
        }
        pills.forEach { $0.theme = theme }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        point.y < bounds.height - Toolbar.deadEdge && super.point(inside: point, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let count = CGFloat(pills.count)
        let width = (block.maxX - block.minX - Toolbar.pillGap * (count - 1)) / count
        for (index, pill) in pills.enumerated() {
            let minX = (block.minX + CGFloat(index) * (width + Toolbar.pillGap)).rounded(scale: scale)
            pill.frame = CGRect(x: minX, y: 0, width: (minX + width).rounded(scale: scale) - minX, height: bounds.height)
        }
    }
}

/// A panel's tool: a pill in the pill row, or an icon at the bar's left in the compact layout.
final class ToolButton: UIControl {
    let panel: Panel
    var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    private let pill: Bool
    private let icon = UIImageView()

    init(panel: Panel, pill: Bool) {
        self.panel = panel
        self.pill = pill
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
        backgroundColor = pill ? (isHighlighted ? theme.keyPressed.ui : theme.key.ui) : (isHighlighted ? theme.candidatePill.ui : .clear)
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
