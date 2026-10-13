import UIKit
import KeyboardCore

/// Stands in for the keys while the app listens: what it's doing, and a Done key as big as the return key's row.
final class DictationPanel: UIView {
    var onFinish: () -> Void = {}
    var onCancel: () -> Void = {}

    private let status = UILabel()
    private let dot = UIView()
    private let done = UIButton(type: .custom)
    private let cancel = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)
        status.font = .systemFont(ofSize: 17, weight: .medium)
        status.textAlignment = .center
        status.numberOfLines = 0
        dot.backgroundColor = .systemRed
        dot.layer.cornerRadius = 5
        done.setTitle("Done", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        done.layer.cornerCurve = .continuous
        done.accessibilityIdentifier = "hex.dictation.done"
        done.addAction(UIAction { [unowned self] _ in onFinish() }, for: .touchUpInside)
        cancel.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
        cancel.layer.cornerCurve = .continuous
        cancel.accessibilityLabel = "Cancel"
        cancel.accessibilityIdentifier = "hex.dictation.cancel"
        cancel.addAction(UIAction { [unowned self] _ in onCancel() }, for: .touchUpInside)
        [dot, status, done, cancel].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ status: Dictation.Status, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        switch (status.state, status.failure) {
        case (.listening, _): self.status.text = "Listening"
        case (.transcribing, _): self.status.text = "Writing it down"
        case (.idle, let failure?): self.status.text = failure
        case (.idle, nil): self.status.text = nil
        }
        dot.isHidden = status.state != .listening
        done.isHidden = status.state != .listening
        done.backgroundColor = theme.prominent.ui
        done.setTitleColor(theme.prominentLabel.ui, for: .normal)
        done.layer.cornerRadius = metrics.cornerRadius
        cancel.backgroundColor = theme.key.ui
        cancel.tintColor = theme.label.ui
        cancel.layer.cornerRadius = metrics.cornerRadius
        self.status.textColor = theme.label.ui
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let key: CGFloat = 46
        let side: CGFloat = 8
        cancel.frame = CGRect(x: side, y: bounds.height - key - 8, width: key * 1.6, height: key)
        done.frame = CGRect(x: cancel.frame.maxX + 8, y: cancel.frame.minY, width: bounds.width - cancel.frame.maxX - 8 - side, height: key)
        let text = status.sizeThatFits(CGSize(width: bounds.width - 60, height: .greatestFiniteMagnitude))
        status.frame = CGRect(x: (bounds.width - text.width) / 2 + (dot.isHidden ? 0 : 9), y: (cancel.frame.minY - text.height) / 2, width: text.width, height: text.height)
        dot.frame = CGRect(x: status.frame.minX - 18, y: status.frame.midY - 5, width: 10, height: 10)
    }
}
