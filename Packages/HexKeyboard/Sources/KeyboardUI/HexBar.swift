import UIKit

final class HexBar: UIView {
    private let slots = (0..<3).map { _ in UILabel() }
    private let dividers = (0..<2).map { _ in UIView() }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.textAlignment = .center
            slot.font = .systemFont(ofSize: 17)
            addSubview(slot)
        }
        dividers.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSuggestions(_ suggestions: [String]) {
        for (slot, text) in zip(slots, suggestions + Array(repeating: "", count: slots.count)) {
            slot.text = text
        }
    }

    func apply(_ theme: KeyboardTheme) {
        slots.forEach { $0.textColor = theme.label }
        dividers.forEach { $0.backgroundColor = theme.secondaryLabel.withAlphaComponent(0.25) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(slots.count)
        for (index, slot) in slots.enumerated() {
            slot.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        let dividerHeight = bounds.height * 0.5
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: CGFloat(index + 1) * width - 0.5, y: (bounds.height - dividerHeight) / 2, width: 1, height: dividerHeight)
        }
    }
}
