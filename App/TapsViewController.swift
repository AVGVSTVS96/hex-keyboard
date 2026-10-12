import KeyboardCore
import KeyboardUI
import UIKit
import notify

final class TapsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let stats = UIStackView()
    private let modes = UISegmentedControl(items: ["Aim", "Accuracy"])
    private let map = TapMapView()
    private let legend = UILabel()
    private let detail = KeyDetailView()
    private let missedHeader = UILabel()
    private let missed = UIStackView()
    private let empty = UILabel()
    private var touches = TouchModel()
    private var signature: String?
    private var observer: Int32 = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Taps"
        view.backgroundColor = .systemBackground

        stats.axis = .horizontal
        stats.distribution = .fillEqually
        stats.spacing = 12

        modes.selectedSegmentIndex = 0
        modes.addAction(UIAction { [unowned self] _ in
            map.mode = modes.selectedSegmentIndex == 0 ? .aim : .accuracy
            updateLegend()
        }, for: .valueChanged)

        map.onSelect = { [unowned self] aim in
            showDetail(aim)
        }

        legend.numberOfLines = 0
        legend.font = .preferredFont(forTextStyle: .footnote)
        legend.textColor = .secondaryLabel

        missedHeader.text = "Most missed"
        missedHeader.font = .preferredFont(forTextStyle: .headline)
        missed.axis = .vertical
        missed.spacing = 10

        empty.numberOfLines = 0
        empty.textAlignment = .center
        empty.font = .preferredFont(forTextStyle: .body)
        empty.textColor = .secondaryLabel
        empty.text = "Type with Hex anywhere, and your taps show up here each time the keyboard closes.\n\nHex needs Allow Full Access to share them with this app."

        let top = Self.column([stats, modes], spacing: 20)
        let bottom = Self.column([legend, detail, missedHeader, missed, empty], spacing: 12)
        bottom.setCustomSpacing(28, after: legend)
        bottom.setCustomSpacing(28, after: detail)
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        [top, map, bottom].forEach(stack.addArrangedSubview)
        stack.setCustomSpacing(10, after: map)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(stack)
        view.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])

        observer = MemoryStore.observeTouches { [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        updateLegend()
    }

    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        reload()
        applyLaunchOptions()
    }

    deinit {
        notify_cancel(observer)
    }

    private static func column(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let column = UIStackView(arrangedSubviews: views)
        column.axis = .vertical
        column.spacing = spacing
        column.isLayoutMarginsRelativeArrangement = true
        column.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        return column
    }

    private func reload() {
        touches = MemoryStore.sharedTouches() ?? TouchModel()
        let layouts = touches.signatures.filter { LayoutContext(signature: $0.signature) != nil }
        if signature.map({ name in !layouts.contains { $0.signature == name } }) ?? true { signature = layouts.first?.signature }
        navigationItem.rightBarButtonItem = layouts.count > 1 ? UIBarButtonItem(title: "Layout", image: UIImage(systemName: "keyboard"), menu: UIMenu(children: layouts.map { layout in
            UIAction(title: Self.title(of: layout.signature), subtitle: "\(layout.taps.formatted()) taps", state: layout.signature == signature ? .on : .off) { [unowned self] _ in
                signature = layout.signature
                reload()
            }
        })) : nil
        let hasTaps = signature != nil
        [stats, modes, map, legend, missedHeader, missed].forEach { $0.isHidden = !hasTaps }
        empty.isHidden = hasTaps
        detail.isHidden = true
        guard let signature, let context = LayoutContext(signature: signature) else { return }
        map.show(touches, on: context, screen: view.window?.windowScene?.screen.bounds.size ?? view.bounds.size)
        showStats()
        showMissed()
        showDetail(map.selected)
    }

    private func applyLaunchOptions() {
        if LaunchOptions.tapsAccuracy {
            modes.selectedSegmentIndex = 1
            map.mode = .accuracy
        }
        if let label = LaunchOptions.tapsKey, let aim = map.aims.first(where: { $0.key.label == label }) { map.select(aim) }
        updateLegend()
    }

    private static func title(of signature: String) -> String {
        guard let context = LayoutContext(signature: signature) else { return signature }
        let device = context.device == .phone ? "iPhone" : "iPad"
        return "\(device), \(context.isLandscape ? "landscape" : "portrait")"
    }

    private func showStats() {
        let taps = map.aims.reduce(0) { $0 + $1.taps }
        let letters = map.aims.filter { $0.key.label != " " }
        let weight = Double(max(letters.reduce(0) { $0 + $1.taps }, 1))
        let onTarget = letters.reduce(0.0) { $0 + Double($1.taps) * $1.onTarget } / weight
        let drift = letters.reduce(0.0) { $0 + Double($1.taps) * hypot($1.drift.x, $1.drift.y) } / weight
        stats.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (value, caption) in [
            (taps.formatted(), "taps learned"),
            (TapMapPalette.percent(onTarget), "of letter taps land on the key you meant"),
            (String(format: "%.1f pt", drift), "your aim off a letter’s center, on average"),
        ] {
            stats.addArrangedSubview(StatView(value: value, caption: caption))
        }
    }

    private func showMissed() {
        missed.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let worst = map.aims.filter { $0.taps >= 10 }.sorted { $0.onTarget < $1.onTarget }.prefix(5)
        missedHeader.isHidden = worst.isEmpty
        for aim in worst {
            let row = MissRow(aim: aim, worst: 1 - (worst.first?.onTarget ?? 0))
            row.addAction(UIAction { [unowned self] _ in map.select(aim) }, for: .touchUpInside)
            missed.addArrangedSubview(row)
        }
    }

    private func showDetail(_ aim: Aim?) {
        detail.isHidden = aim == nil
        if let aim { detail.show(aim) }
        updateLegend()
    }

    private func updateLegend() {
        legend.text = switch (map.mode, map.selected) {
        case (.aim, _):
            "Each dot is one of your recent taps. The ring holds half of all your taps for that key, and the line runs from the key’s center to where you really aim."
        case (.accuracy, nil):
            "How often a tap lands on the key you meant, before Hex reads it with your words. Tap a key to see where its taps go."
        case (.accuracy, let aim?):
            "Where your taps for “\(TapMapPalette.name(of: aim.key))” land. Tap it again to go back."
        }
    }
}

private final class StatView: UIView {
    init(value: String, caption: String) {
        super.init(frame: .zero)
        let number = UILabel()
        number.text = value
        number.font = UIFont.monospacedDigitSystemFont(ofSize: 26, weight: .semibold)
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.6
        let label = UILabel()
        label.text = caption
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [number, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

private final class Keycap: UILabel {
    init(_ key: Key, size: CGFloat) {
        super.init(frame: .zero)
        text = TapMapPalette.name(of: key)
        textAlignment = .center
        font = .systemFont(ofSize: key.label?.count == 1 && key.label != " " ? size : size * 0.6)
        backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : .white }
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        layer.borderColor = UIColor.separator.cgColor
        layer.borderWidth = 1 / 3
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// One key's taps: how many, where you aim, and the share that lands on each key, as one bar.
private final class KeyDetailView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ aim: Aim) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let cap = Keycap(aim.key, size: 24)
        let taps = UILabel()
        taps.text = aim.taps == 1 ? "1 tap" : "\(aim.taps.formatted()) taps"
        taps.font = .preferredFont(forTextStyle: .headline)
        let where_ = UILabel()
        where_.text = Self.describe(aim.drift)
        where_.font = .preferredFont(forTextStyle: .subheadline)
        where_.textColor = .secondaryLabel
        where_.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [taps, where_])
        text.axis = .vertical
        text.spacing = 2
        let header = UIStackView(arrangedSubviews: [cap, text])
        header.spacing = 12
        header.alignment = .center
        NSLayoutConstraint.activate([cap.widthAnchor.constraint(equalToConstant: 44), cap.heightAnchor.constraint(equalToConstant: 48)])
        stack.addArrangedSubview(header)

        let shares = Self.folded(aim)
        stack.addArrangedSubview(ShareBar(shares: shares))
        let legend = UILabel()
        legend.numberOfLines = 0
        legend.font = .preferredFont(forTextStyle: .footnote)
        legend.textColor = .secondaryLabel
        legend.text = "Lands on " + shares.map { "\($0.name) \(TapMapPalette.percent($0.share))" }.joined(separator: " · ")
        stack.addArrangedSubview(legend)
    }

    private static func describe(_ drift: (x: Double, y: Double)) -> String {
        let parts = [
            abs(drift.x) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.x), drift.x < 0 ? "left" : "right") : nil,
            abs(drift.y) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.y), drift.y < 0 ? "high" : "low") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "You aim at its center." : "You aim \(parts.joined(separator: " and ")) of its center."
    }

    /// The key itself, its three biggest misses, and the rest as one.
    private static func folded(_ aim: Aim) -> [(name: String, share: Double, isTarget: Bool)] {
        let misses = aim.landing.filter { $0.key != aim.key }
        var shares = [(name: TapMapPalette.name(of: aim.key), share: aim.onTarget, isTarget: true)]
        shares += misses.prefix(3).filter { $0.share >= 0.005 }.map { (TapMapPalette.name(of: $0.key), $0.share, false) }
        let rest = 1 - shares.reduce(0) { $0 + $1.share }
        if rest >= 0.005 { shares.append(("other", rest, false)) }
        return shares
    }
}

private final class ShareBar: UIView {
    private let shares: [(name: String, share: Double, isTarget: Bool)]

    init(shares: [(name: String, share: Double, isTarget: Bool)]) {
        self.shares = shares
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 2
        let available = bounds.width - gap * CGFloat(shares.count - 1)
        var x: CGFloat = 0
        for (index, item) in shares.enumerated() {
            let width = max(available * item.share, 3)
            let segment = CGRect(x: x, y: 0, width: min(width, bounds.width - x), height: bounds.height)
            (item.isTarget ? tintColor : TapMapPalette.miss.withAlphaComponent(index == shares.count - 1 && item.name == "other" ? 0.4 : 0.85))?.setFill()
            UIBezierPath(roundedRect: segment, cornerRadius: 4).fill()
            x += width + gap
        }
    }
}

/// A key that often misses: where its stray taps go, and how many stray.
private final class MissRow: UIControl {
    init(aim: Aim, worst: Double) {
        super.init(frame: .zero)
        let miss = 1 - aim.onTarget
        let neighbor = aim.landing.first { $0.key != aim.key }
        let cap = Keycap(aim.key, size: 18)
        cap.isUserInteractionEnabled = false
        let arrow = UILabel()
        arrow.text = neighbor.map { "mostly onto \(TapMapPalette.name(of: $0.key))" } ?? ""
        arrow.font = .preferredFont(forTextStyle: .subheadline)
        arrow.textColor = .secondaryLabel
        let value = UILabel()
        value.text = "\(TapMapPalette.percent(miss)) miss"
        value.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        value.setContentHuggingPriority(.required, for: .horizontal)
        let track = MissTrack(fraction: miss / worst)
        let middle = UIStackView(arrangedSubviews: [arrow, track])
        middle.axis = .vertical
        middle.spacing = 6
        let row = UIStackView(arrangedSubviews: [cap, middle, value])
        row.spacing = 12
        row.alignment = .center
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            cap.widthAnchor.constraint(equalToConstant: 34), cap.heightAnchor.constraint(equalToConstant: 38),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(TapMapPalette.name(of: aim.key)), \(TapMapPalette.percent(miss)) miss, \(arrow.text ?? "")"
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.5 : 1 } }
}

/// How much of a key's taps stray, against a full track for the key that strays most.
private final class MissTrack: UIView {
    private let fraction: Double

    init(fraction: Double) {
        self.fraction = fraction
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 6).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: bounds, cornerRadius: 3).fill()
        TapMapPalette.miss.setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: max(bounds.width * fraction, 6), height: bounds.height), cornerRadius: 3).fill()
    }
}
