import UIKit
import KeyboardCore

/// One of the buttons at the bar's left, the More button or a panel's tool: its glyph, in a circle that shows only while
/// pressed.
final class BarButton: UIButton {
    var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    private let draw: @MainActor (CGFloat) -> UIImage?
    private let icon = UIImageView()
    private var glyph: CGFloat = 0
    private var reach = UIEdgeInsets.zero

    /// `draw` makes the glyph to fit a square of a side.
    init(_ title: String, draw: @escaping @MainActor (CGFloat) -> UIImage?) {
        self.draw = draw
        super.init(frame: .zero)
        accessibilityLabel = title
        icon.isUserInteractionEnabled = false
        icon.contentMode = .center
        layer.cornerCurve = .continuous
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { if isHighlighted != oldValue { refresh() } }
    }

    /// `glyph` is the side of the square its glyph fits; taps out to `reach` around the circle still reach it.
    func place(_ frame: CGRect, glyph: CGFloat, reach: UIEdgeInsets) {
        self.frame = frame
        self.reach = reach
        guard glyph != self.glyph else { return }
        self.glyph = glyph
        icon.image = draw(glyph)
    }

    private func refresh() {
        icon.tintColor = theme.label.ui
        backgroundColor = isHighlighted ? theme.candidatePill.ui : .clear
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.inset(by: reach).contains(point)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        icon.frame = bounds
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
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

    /// The tool's glyph, its longer side `side` long, so every tool and the More button read as one size.
    func icon(_ side: CGFloat) -> UIImage? {
        switch self {
        case .emoji: Self.symbol("face.smiling", side)
        case .gif: Self.gifGlyph(side)
        case .clipboard: Self.symbol("list.clipboard", side)
        }
    }

    /// A symbol scaled so its glyph, without the margins a symbol image carries, is `side` long on its longer side.
    private static func symbol(_ name: String, _ side: CGFloat) -> UIImage? {
        guard let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: side, weight: .regular)) else { return nil }
        let ink = CGRect(origin: .zero, size: image.size).inset(by: image.alignmentRectInsets)
        let scale = side / max(ink.width, ink.height)
        let size = CGSize(width: ink.width * scale, height: ink.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.withTintColor(.black).draw(in: CGRect(x: -ink.minX * scale, y: -ink.minY * scale, width: image.size.width * scale, height: image.size.height * scale))
        }.withRenderingMode(.alwaysTemplate)
    }

    /// Raycast's four rounded squares, for the More button, drawn in a `side` square. A solid block looks bigger than an
    /// outline of the same size, so they span 0.88 of it.
    static func moreGlyph(_ side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let extent = side * 0.88, gap = side * 0.13
        let square = (extent - gap) / 2
        return UIGraphicsImageRenderer(size: size).image { _ in
            let origin = (side - extent) / 2
            UIColor.black.setFill()
            for row in 0..<2 {
                for column in 0..<2 {
                    let rect = CGRect(x: origin + CGFloat(column) * (square + gap), y: origin + CGFloat(row) * (square + gap), width: square, height: square)
                    UIBezierPath(roundedRect: rect, cornerRadius: square * 0.28).fill()
                }
            }
        }.withRenderingMode(.alwaysTemplate)
    }

    /// GIF has no SF Symbol: a rounded rect with "GIF" in it, `side` wide (docs/design.md).
    package static func gifGlyph(_ side: CGFloat) -> UIImage {
        let unit = side / 18.4
        let size = CGSize(width: side, height: 14.4 * unit)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(roundedRect: box.insetBy(dx: 0.85 * unit, dy: 0.85 * unit), cornerRadius: 3.6 * unit)
            path.lineWidth = 1.7 * unit
            UIColor.black.setStroke()
            path.stroke()
            let text = NSAttributedString(string: "GIF", attributes: [.font: UIFont.systemFont(ofSize: 8 * unit, weight: .heavy), .foregroundColor: UIColor.black])
            let bounds = text.size()
            text.draw(at: CGPoint(x: box.midX - bounds.width / 2, y: box.midY - bounds.height / 2))
        }.withRenderingMode(.alwaysTemplate)
    }
}
