import UIKit

final class AlternatesView: UIView {
    private let panel = UIView()
    private let highlight = UIView()
    private var labels: [UILabel] = []
    private var cellWidth: CGFloat = 0
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

    func show(_ options: [String], base: String, over key: CGRect, in bounds: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        self.options = options
        labels.forEach { $0.removeFromSuperview() }
        cellWidth = max(key.width * 0.95, 30)
        let height = key.height * 1.15
        let width = cellWidth * CGFloat(options.count) + 12
        let baseIndex = options.firstIndex(of: base) ?? 0
        var x = key.midX - 6 - cellWidth * (CGFloat(baseIndex) + 0.5)
        x = min(max(x, bounds.minX + 4), bounds.maxX - width - 4)
        frame = CGRect(x: x, y: key.minY - height - 8, width: width, height: height)
        panel.frame = bounds
        panel.layer.cornerRadius = metrics.cornerRadius * 1.6
        panel.backgroundColor = theme.key
        panel.layer.shadowColor = theme.shadow.cgColor
        highlight.backgroundColor = theme.keyPressed
        highlight.layer.cornerRadius = metrics.cornerRadius

        labels = options.enumerated().map { index, option in
            let label = UILabel(frame: CGRect(x: 6 + CGFloat(index) * cellWidth, y: 0, width: cellWidth, height: height))
            label.text = option
            label.textAlignment = .center
            label.font = KeyboardFont.letter(metrics.letterSize)
            label.textColor = theme.label
            panel.addSubview(label)
            return label
        }
        select(baseIndex)
        isHidden = false
    }

    func track(_ point: CGPoint) {
        let local = point.x - frame.minX - 6
        select(min(max(Int(local / cellWidth), 0), options.count - 1))
    }

    func hide() {
        isHidden = true
        options = []
    }

    private func select(_ index: Int) {
        selectedIndex = index
        highlight.frame = CGRect(x: 6 + CGFloat(index) * cellWidth, y: 6, width: cellWidth, height: bounds.height - 12)
    }
}
