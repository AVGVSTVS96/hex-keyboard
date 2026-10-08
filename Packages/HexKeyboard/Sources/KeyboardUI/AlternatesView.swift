import UIKit

final class AlternatesView: UIView {
    private let panel = UIView()
    private let highlight = UIView()
    private var labels: [UILabel] = []
    private var cellWidth: CGFloat = 0
    private var highlightHeight: CGFloat = 0
    private let padding: CGFloat = 10
    private(set) var options: [String] = []
    private(set) var selectedIndex = 0

    var selected: String? { options.indices.contains(selectedIndex) ? options[selectedIndex] : nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        panel.layer.cornerCurve = .continuous
        panel.layer.shadowOffset = CGSize(width: 0, height: 2)
        panel.layer.shadowRadius = 8
        panel.layer.shadowOpacity = 1
        highlight.layer.cornerCurve = .continuous
        addSubview(panel)
        panel.addSubview(highlight)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ options: [String], base: String, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        self.options = options
        labels.forEach { $0.removeFromSuperview() }
        cellWidth = key.width + 4
        let height = key.height * 1.57
        let width = cellWidth * CGFloat(options.count) + padding * 2
        let baseIndex = options.firstIndex(of: base) ?? 0
        let x = key.midX - padding - cellWidth * (CGFloat(baseIndex) + 0.5)
        frame = CGRect(
            x: min(max(x, area.minX + 7), area.maxX - width - 7),
            y: max(key.minY - height - 3, area.minY + 1),
            width: width,
            height: height
        )
        panel.frame = bounds
        panel.layer.cornerRadius = metrics.cornerRadius * 2
        panel.layer.shadowPath = UIBezierPath(roundedRect: panel.bounds, cornerRadius: panel.layer.cornerRadius).cgPath
        panel.backgroundColor = theme.key
        panel.layer.shadowColor = theme.shadow.cgColor
        highlight.backgroundColor = theme.selection
        highlight.layer.cornerRadius = metrics.cornerRadius

        labels = options.enumerated().map { index, option in
            let label = UILabel(frame: CGRect(x: padding + CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: height))
            label.text = option
            label.textAlignment = .center
            label.font = KeyboardFont.letter(metrics.letterSize)
            label.textColor = theme.label
            panel.addSubview(label)
            return label
        }
        highlightHeight = key.height + 4
        select(baseIndex)
        isHidden = false
    }

    func track(_ point: CGPoint) {
        let local = point.x - frame.minX - padding
        select(min(max(Int(local / cellWidth), 0), options.count - 1))
    }

    func hide() {
        isHidden = true
        options = []
    }

    private func select(_ index: Int) {
        selectedIndex = index
        highlight.frame = CGRect(x: padding + CGFloat(index) * cellWidth, y: (bounds.height - highlightHeight) / 2, width: cellWidth, height: highlightHeight)
    }
}
