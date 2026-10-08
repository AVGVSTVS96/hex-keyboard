import UIKit
import KeyboardCore

final class KeyView: UIView {
    let key: Key
    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let icon = UIImageView()
    private var face = KeyFace(content: .none)
    private var metrics: KeyboardMetrics?

    var theme = KeyboardTheme.light { didSet { updateColors() } }
    var isPressed = false { didSet { if isPressed != oldValue { updateColors() } } }
    var showsLabel = true { didSet { contentAlpha = showsLabel ? 1 : 0 } }

    private var contentAlpha: CGFloat = 1 {
        didSet { [label, secondaryLabel, icon].forEach { $0.alpha = contentAlpha } }
    }

    init(key: Key) {
        self.key = key
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerCurve = .continuous
        icon.contentMode = .center
        label.textAlignment = .center
        secondaryLabel.textAlignment = .center
        [secondaryLabel, label, icon].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ face: KeyFace, metrics: KeyboardMetrics) {
        guard face != self.face || metrics != self.metrics else { return }
        self.face = face
        self.metrics = metrics
        layer.cornerRadius = metrics.cornerRadius

        switch face.content {
        case .letter(let text):
            label.text = text
            label.font = KeyboardFont.letter(metrics.letterSize)
            icon.image = nil
        case .text(let text):
            label.text = text
            label.font = .systemFont(ofSize: metrics.labelSize, weight: .regular)
            icon.image = nil
        case .symbol(let name):
            label.text = nil
            let configuration = UIImage.SymbolConfiguration(pointSize: metrics.symbolSize, weight: .regular)
            icon.image = UIImage(systemName: name, withConfiguration: configuration)
        case .none:
            label.text = nil
            icon.image = nil
        }
        secondaryLabel.text = face.secondary
        secondaryLabel.font = .systemFont(ofSize: metrics.secondarySize, weight: .regular)
        updateColors()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let metrics else { return }
        let padding = CGSize(width: 12, height: 9)
        let content = bounds.insetBy(dx: padding.width, dy: padding.height)

        for view in [label, icon] as [UIView] {
            view.sizeToFit()
            var frame = view.frame
            switch face.alignment {
            case .center:
                let offset = view === label && isLetter ? metrics.letterOffset : 0
                frame.origin = CGPoint(x: bounds.midX - frame.width / 2, y: bounds.midY - frame.height / 2 + offset)
            case .bottomLeading:
                frame.origin = CGPoint(x: content.minX, y: content.maxY - frame.height)
            case .bottomTrailing:
                frame.origin = CGPoint(x: content.maxX - frame.width, y: content.maxY - frame.height)
            }
            view.frame = frame
        }

        guard face.secondary != nil else { return secondaryLabel.frame = .zero }
        secondaryLabel.sizeToFit()
        let spacing = metrics.keyHeight * 0.03
        let stack = secondaryLabel.bounds.height + spacing + label.bounds.height
        let top = bounds.midY - stack / 2
        secondaryLabel.center = CGPoint(x: bounds.midX, y: top + secondaryLabel.bounds.height / 2)
        label.center = CGPoint(x: bounds.midX, y: top + secondaryLabel.bounds.height + spacing + label.bounds.height / 2)
    }

    private var isLetter: Bool {
        if case .letter = face.content { true } else { false }
    }

    private func updateColors() {
        let prominent = face.isProminent
        backgroundColor = prominent ? theme.prominent : isPressed ? theme.keyPressed : theme.key
        let foreground = prominent ? theme.prominentLabel : theme.label
        label.textColor = foreground
        icon.tintColor = foreground
        secondaryLabel.textColor = face.secondaryIsDimmed ? theme.secondaryLabel : foreground
    }
}
