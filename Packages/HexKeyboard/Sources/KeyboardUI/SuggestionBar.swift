import UIKit
import KeyboardCore

final class SuggestionBar: UIView {
    var onSelect: (Suggestion) -> Void = { _ in }

    private let slots = (0..<3).map { SuggestionSlot(index: $0) }
    private let dividers = (0..<2).map { _ in UIView() }
    private var enabled = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        for slot in slots {
            slot.addAction(UIAction { [unowned self, unowned slot] _ in
                if let suggestion = slot.suggestion { onSelect(suggestion) }
            }, for: .touchUpInside)
            slot.onHighlight = { [unowned self] in refreshDividers() }
            addSubview(slot)
        }
        dividers.forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ suggestions: [Suggestion], enabled: Bool, theme: KeyboardTheme) {
        self.enabled = enabled
        for (index, slot) in slots.enumerated() {
            slot.isHidden = !enabled
            slot.configure(suggestions.indices.contains(index) ? suggestions[index] : nil, theme: theme)
        }
        dividers.forEach { $0.backgroundColor = theme.candidateDivider }
        refreshDividers()
    }

    private func refreshDividers() {
        for (index, divider) in dividers.enumerated() {
            divider.isHidden = !enabled || slots[index].showsPill || slots[index + 1].showsPill
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        let width = bounds.width / CGFloat(slots.count)
        for (index, slot) in slots.enumerated() {
            let minX = (CGFloat(index) * width).rounded(scale: scale)
            let maxX = (CGFloat(index + 1) * width).rounded(scale: scale)
            slot.frame = CGRect(x: minX, y: 0, width: maxX - minX, height: bounds.height)
        }
        for (index, divider) in dividers.enumerated() {
            divider.frame = CGRect(x: slots[index].frame.maxX - 1, y: bounds.midY - 12, width: 1, height: 24)
        }
    }
}

private final class SuggestionSlot: UIControl {
    private(set) var suggestion: Suggestion?
    var onHighlight: () -> Void = {}
    private let label = UILabel()
    private let pill = UIView()
    private var theme = KeyboardTheme.light

    init(index: Int) {
        super.init(frame: .zero)
        accessibilityIdentifier = "hex.suggestion.\(index)"
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
        pill.isUserInteractionEnabled = false
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 17)
        addSubview(pill)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    var showsPill: Bool { suggestion != nil && (suggestion?.kind == .correction || isHighlighted) }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            refresh()
            onHighlight()
        }
    }

    func configure(_ suggestion: Suggestion?, theme: KeyboardTheme) {
        self.suggestion = suggestion
        self.theme = theme
        label.text = suggestion.map { $0.kind == .literal ? "“\($0.text)”" : $0.text }
        accessibilityLabel = suggestion?.text
        refresh()
        setNeedsLayout()
    }

    private func refresh() {
        pill.isHidden = !showsPill
        pill.backgroundColor = theme.candidatePill
        label.textColor = showsPill ? theme.candidateHighlighted : theme.candidate
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = bounds
        pill.layer.cornerRadius = bounds.height / 2
        guard let font = label.font else { return }
        let baseline = (bounds.midY + font.capHeight / 2).rounded(scale: traitCollection.displayScale)
        let width = min(label.intrinsicContentSize.width, bounds.width - 8)
        label.frame = CGRect(x: (bounds.width - width) / 2, y: baseline - font.ascender, width: width, height: font.lineHeight)
    }
}

extension CGFloat {
    func rounded(scale: CGFloat) -> CGFloat { (self * scale).rounded() / scale }
}
