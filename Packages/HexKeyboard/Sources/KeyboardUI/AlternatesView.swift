import UIKit
import KeyboardCore

/// The panel a held key opens: a key's accents in one row, or the layer key's menu in rows, picked by sliding.
final class AlternatesView: UIView {
    private let panel = UIView()
    private let highlight = UIView()
    private var labels: [[UILabel]] = []
    private var rowHeight: CGFloat = 0
    private var highlightHeight: CGFloat = 0
    private let padding: CGFloat = 10
    private var inset: CGFloat = 0
    private var labelColor = UIColor.black
    private var selectedLabelColor = UIColor.white
    private(set) var options: [[String]] = []
    private(set) var selection = (row: 0, column: 0)

    var selected: String? { options.indices.contains(selection.row) ? options[selection.row][selection.column] : nil }

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

    func show(_ options: [String], base: String, over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme, font: UIFont? = nil) {
        let font = font ?? KeyboardFont.letter(metrics.letterSize)
        let selected = options.firstIndex(of: base) ?? 0
        let cellWidth = key.width + 4
        let height = key.height * 1.57
        let width = cellWidth * CGFloat(options.count) + padding * 2
        let x = key.midX - padding - cellWidth * (CGFloat(selected) + 0.5)
        present([options.map { NSAttributedString(string: $0, attributes: [.font: font]) }],
                frame: CGRect(x: x, y: max(key.minY - height - 3, area.minY + 1), width: width, height: height),
                rowHeight: height, highlightHeight: key.height + 4, inset: 0, in: area, metrics: metrics, theme: theme)
        self.options = [options]
        select(row: 0, column: selected)
    }

    /// Rows of SF Symbols over `key`, the last row nearest it and its first item right above it.
    func show(menu symbols: [[String]], over key: CGRect, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        let configuration = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: .regular)
        let columns = CGFloat(symbols.map(\.count).max() ?? 1)
        let cell = CGSize(width: 50, height: key.height + 8)
        let width = cell.width * columns + padding * 2
        let height = cell.height * CGFloat(symbols.count) + padding
        let firstNearest = padding + (width - padding * 2) / CGFloat(symbols.last?.count ?? 1) / 2
        present(symbols.map { row in
            row.map { NSAttributedString(attachment: NSTextAttachment(image: UIImage(systemName: $0, withConfiguration: configuration) ?? UIImage())) }
        }, frame: CGRect(x: key.midX - firstNearest, y: max(key.minY - height - 3, area.minY + 1), width: width, height: height),
                rowHeight: cell.height, highlightHeight: cell.height - 6, inset: padding / 2, in: area, metrics: metrics, theme: theme)
        options = symbols
        track(CGPoint(x: key.midX, y: key.midY))
    }

    private func present(_ rows: [[NSAttributedString]], frame: CGRect, rowHeight: CGFloat, highlightHeight: CGFloat, inset: CGFloat, in area: CGRect, metrics: KeyboardMetrics, theme: KeyboardTheme) {
        labels.joined().forEach { $0.removeFromSuperview() }
        self.frame = CGRect(x: min(max(frame.minX, area.minX + 7), area.maxX - frame.width - 7), y: frame.minY, width: frame.width, height: frame.height)
        self.rowHeight = rowHeight
        self.highlightHeight = highlightHeight
        self.inset = inset
        panel.frame = bounds
        panel.layer.cornerRadius = metrics.cornerRadius * 2
        panel.layer.shadowPath = UIBezierPath(roundedRect: panel.bounds, cornerRadius: panel.layer.cornerRadius).cgPath
        panel.backgroundColor = theme.key.ui
        panel.layer.shadowColor = theme.shadow.ui.cgColor
        highlight.backgroundColor = theme.selection.ui
        highlight.layer.cornerRadius = metrics.cornerRadius * 1.25
        labelColor = theme.label.ui
        selectedLabelColor = theme.selectionLabel.ui

        labels = rows.enumerated().map { row, contents in
            contents.enumerated().map { column, content in
                let label = UILabel(frame: cellFrame(row: row, column: column, of: contents.count))
                label.attributedText = content
                label.textAlignment = .center
                label.textColor = labelColor
                panel.addSubview(label)
                return label
            }
        }
        isHidden = false
    }

    private func cellFrame(row: Int, column: Int, of count: Int) -> CGRect {
        let width = (bounds.width - padding * 2) / CGFloat(count)
        return CGRect(x: padding + CGFloat(column) * width, y: inset + CGFloat(row) * rowHeight, width: width, height: rowHeight)
    }

    func track(_ point: CGPoint) {
        guard !options.isEmpty else { return }
        let row = min(max(Int((point.y - frame.minY - inset) / rowHeight), 0), options.count - 1)
        let width = (bounds.width - padding * 2) / CGFloat(options[row].count)
        select(row: row, column: min(max(Int((point.x - frame.minX - padding) / width), 0), options[row].count - 1))
    }

    func hide() {
        isHidden = true
        options = []
    }

    private func select(row: Int, column: Int) {
        selection = (row, column)
        for (r, views) in labels.enumerated() {
            for (c, view) in views.enumerated() {
                view.textColor = (r, c) == (row, column) ? selectedLabelColor : labelColor
            }
        }
        let cell = cellFrame(row: row, column: column, of: labels[row].count)
        highlight.frame = CGRect(x: cell.minX, y: cell.midY - highlightHeight / 2, width: cell.width, height: highlightHeight)
    }
}
