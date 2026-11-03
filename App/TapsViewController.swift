import KeyboardCore
import KeyboardUI
import UIKit
import notify

final class TapsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stats = UIStackView()
    private let modes = PillBar(titles: ["Heat", "Aim", "Accuracy"])
    private let titleRow = UIStackView()
    private let layouts = UIButton(configuration: .gray())
    private var split: NSLayoutConstraint?
    private let map = TapMapView()
    private let scale = HeatScale()
    private let legend = UILabel()
    private let detail = KeyDetailView()
    private let pullHeader = UILabel()
    private let pull = TapPullView()
    private let pullCaption = UILabel()
    private let missedHeader = UILabel()
    private let missed = UIStackView()
    private let pullCard = UIStackView()
    private let missedCard = UIStackView()
    private let primary = UIStackView()
    private let secondary = UIStackView()
    private let columns = UIStackView()
    private var touches = TouchModel()
    private var signature: String?
    private var observer: Int32 = 0

    private static let modeOrder: [TapMapView.Mode] = [.heat, .aim, .accuracy]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Your Taps"
        view.backgroundColor = HexStyle.page

        let name = UILabel()
        name.text = "Your Taps"
        name.font = UIFontMetrics(forTextStyle: .title3).scaledFont(for: .systemFont(ofSize: 20, weight: .semibold))
        name.adjustsFontForContentSizeCategory = true
        name.accessibilityTraits = .header
        layouts.configuration?.cornerStyle = .capsule
        layouts.configuration?.baseBackgroundColor = HexStyle.card
        layouts.configuration?.baseForegroundColor = .label
        layouts.showsMenuAsPrimaryAction = true
        titleRow.addArrangedSubview(name)
        titleRow.addArrangedSubview(UIView())
        titleRow.addArrangedSubview(layouts)
        titleRow.alignment = .center

        stats.axis = .vertical
        stats.spacing = 12

        modes.onChange = { [unowned self] index in
            map.mode = Self.modeOrder[index]
            updateLegend()
        }

        map.onSelect = { [unowned self] aim in
            showDetail(aim)
        }

        legend.numberOfLines = 0
        legend.font = .preferredFont(forTextStyle: .footnote)
        legend.textColor = HexStyle.secondary

        for header in [pullHeader, missedHeader] {
            header.font = .preferredFont(forTextStyle: .headline)
        }
        pullHeader.text = "How your thumbs pull"
        pullCaption.numberOfLines = 0
        pullCaption.font = .preferredFont(forTextStyle: .footnote)
        pullCaption.textColor = HexStyle.secondary

        missedHeader.text = "Most missed"
        missed.axis = .vertical
        missed.spacing = 10


        map.layer.cornerRadius = HexStyle.cardRadius
        for view in [scale, legend, pullHeader, pull, pullCaption] { pullCard.addArrangedSubview(view) }
        pullCard.setCustomSpacing(8, after: scale)
        pullCard.setCustomSpacing(20, after: legend)
        for view in [missedHeader, missed] { missedCard.addArrangedSubview(view) }
        for card in [pullCard, missedCard] {
            card.axis = .vertical
            card.spacing = 12
            card.isLayoutMarginsRelativeArrangement = true
            card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            HexStyle.makeCard(card)
        }
        for column in [primary, secondary] {
            column.axis = .vertical
            column.spacing = 16
        }
        columns.alignment = .top
        columns.spacing = 36
        columns.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(columns)
        view.addSubview(scroll)
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleRow)
        let readable = columns.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32)
        readable.priority = .required - 1

        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleRow.leadingAnchor.constraint(equalTo: columns.leadingAnchor, constant: 4),
            titleRow.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            columns.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            columns.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -32),
            columns.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            columns.widthAnchor.constraint(lessThanOrEqualToConstant: 1000),
            columns.widthAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
            readable,
        ])
        arrange()

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

    private var empty: UIContentUnavailableConfiguration {
        var empty = UIContentUnavailableConfiguration.empty()
        empty.image = UIImage(systemName: "hand.tap")
        empty.text = "No Taps Yet"
        guard !SettingsStore.fullAccessSeen else {
            empty.secondaryText = "Type with Hex anywhere, and your taps show up here each time the keyboard closes."
            return empty
        }
        empty.secondaryText = "Type with Hex anywhere, and your taps show up here each time the keyboard closes. Hex needs Allow Full Access to share them with this app."
        var button = UIButton.Configuration.borderedProminent()
        button.title = "Allow Full Access"
        button.cornerStyle = .capsule
        empty.button = button
        empty.buttonProperties.primaryAction = UIAction { _ in HexStatus.openSettings() }
        return empty
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if wantsWide != isWide { arrange() }
        if let window = view.window, isWide {
            let left = view.convert(CGPoint.zero, to: window).x + view.safeAreaInsets.left + 16
            split?.constant = max(window.bounds.width / 2 - left - columns.spacing / 2, 200)
        }
    }

    private var wantsWide: Bool { view.bounds.width >= Arrangement.wide && view.bounds.width > view.bounds.height }

    private var isWide: Bool { secondary.superview != nil }

    /// Wider than tall, the map and how your thumbs pull take the half before the hinge, your numbers, a key's close-up
    /// and the most missed keys the half after it; otherwise all of it in one column, the numbers first.
    private func arrange() {
        let wide = wantsWide
        for stack in [columns, primary, secondary] { stack.arrangedSubviews.forEach { $0.removeFromSuperview() } }
        split?.isActive = false
        if wide {
            [modes, map, pullCard].forEach(primary.addArrangedSubview)
            [stats, detail, missedCard].forEach(secondary.addArrangedSubview)
            [primary, secondary].forEach(columns.addArrangedSubview)
            split = primary.widthAnchor.constraint(equalToConstant: 400)
            split?.isActive = true
        } else {
            [stats, modes, map, detail, pullCard, missedCard].forEach(primary.addArrangedSubview)
            columns.addArrangedSubview(primary)
        }
        primary.setCustomSpacing(12, after: modes)
    }

    private func reload() {
        touches = MemoryStore.sharedTouches() ?? TouchModel()
        let layouts = touches.signatures.filter { LayoutContext(signature: $0.signature) != nil }
        if signature.map({ name in !layouts.contains { $0.signature == name } }) ?? true {
            signature = layouts.first { $0.signature == current }?.signature ?? layouts.first?.signature
        }
        self.layouts.isHidden = layouts.count < 2
        self.layouts.configuration?.title = signature.map(title(of:)) ?? "Layout"
        self.layouts.configuration?.image = UIImage(systemName: "chevron.up.chevron.down", withConfiguration: UIImage.SymbolConfiguration(scale: .small))
        self.layouts.configuration?.imagePlacement = .trailing
        self.layouts.configuration?.imagePadding = 6
        self.layouts.menu = UIMenu(children: layouts.map { layout in
            UIAction(title: title(of: layout.signature), subtitle: "\(layout.taps.formatted()) taps", state: layout.signature == signature ? .on : .off) { [unowned self] _ in
                signature = layout.signature
                reload()
            }
        })
        let hasTaps = signature != nil
        [stats, modes, map, pullCard, missedCard].forEach { $0.isHidden = !hasTaps }
        contentUnavailableConfiguration = hasTaps ? nil : empty
        detail.isHidden = true
        guard let signature, let context = LayoutContext(signature: signature) else { return updateLegend() }
        map.show(touches, on: context, screen: screen)
        showStats()
        showPull()
        showMissed()
        showDetail(map.selected)
    }

    private func applyLaunchOptions() {
        if let mode = LaunchOptions.tapsMode {
            modes.selected = Self.modeOrder.firstIndex(of: mode) ?? 0
            map.mode = mode
        }
        if let label = LaunchOptions.tapsKey, let aim = map.aims.first(where: { $0.key.label == label }) { map.select(aim) }
        updateLegend()
        if LaunchOptions.scrollsToEnd {
            view.layoutIfNeeded()
            scroll.contentOffset.y = max(scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom, -scroll.adjustedContentInset.top)
            return
        }
        guard let target = LaunchOptions.tapsScroll else { return }
        view.layoutIfNeeded()
        let anchor: UIView = target == "detail" ? detail : missed
        let frame = anchor.convert(anchor.bounds, to: scroll)
        let bottom = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
        scroll.contentOffset.y = min(max(frame.minY - scroll.adjustedContentInset.top - 60, -scroll.adjustedContentInset.top), bottom)
    }

    /// The screen and hold a touch model was kept for: on the iPhone Duo, which screen and which way up (open and
    /// upright, the screen is wider than tall).
    private func title(of signature: String) -> String {
        guard let context = LayoutContext(signature: signature) else { return signature }
        let screen = if context.device != .phone {
            "iPad, \(context.isLandscape ? "landscape" : "portrait")"
        } else if isDuo {
            "\(context.isOpen ? "Open" : "Folded"), \(context.isLandscape != context.isOpen ? "on its side" : "upright")"
        } else {
            "iPhone, \(context.isLandscape ? "landscape" : "portrait")"
        }
        let layer = switch context.layer {
        case .letters: ""
        case .numbers: ", numbers"
        case .symbols: ", symbols"
        }
        let hand = switch context.oneHanded {
        case .left: ", left hand"
        case .right: ", right hand"
        case .off: ""
        }
        return screen + layer + hand + (context.isSplit ? ", split" : "")
    }

    private var screen: CGSize { view.window?.windowScene?.screen.bounds.size ?? view.bounds.size }

    private var isDuo: Bool { Duo.isDuo(short: min(screen.width, screen.height)) }

    /// The letters of the screen the app is on now, whose taps show first.
    private var current: String {
        LayoutContext(device: .phone, layer: .letters, isLandscape: screen.width > screen.height, isOpen: Duo.isOpen(short: min(screen.width, screen.height))).signature
    }

    private func showStats() {
        let taps = map.aims.reduce(0) { $0 + $1.taps }
        let letters = map.aims.filter { $0.key.label != " " }
        let weight = Double(max(letters.reduce(0) { $0 + $1.taps }, 1))
        let onTarget = letters.reduce(0.0) { $0 + Double($1.taps) * $1.onTarget } / weight
        let drift = letters.reduce(0.0) { $0 + Double($1.taps) * hypot($1.drift.x, $1.drift.y) } / weight
        let recent = letters.flatMap { aim in aim.recent.map { $0.landed == aim.key } }
        let lately = recent.isEmpty ? nil : Double(recent.count(where: \.self)) / Double(recent.count)
        stats.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let tiles = [
            StatView(value: taps.formatted(), caption: "taps learned"),
            StatView(value: TapMapPalette.percent(onTarget), caption: "of letter taps land on the key you meant"),
            StatView(value: lately.map { TapMapPalette.percent($0) } ?? "–", caption: recent.isEmpty ? "on target lately" : "on target in your last \(recent.count.formatted())"),
            StatView(value: String(format: "%.1f pt", drift), caption: "from a letter’s center to where you aim"),
        ]
        for pair in [tiles[0...1], tiles[2...3]] {
            let row = UIStackView(arrangedSubviews: Array(pair))
            row.distribution = .fillEqually
            row.spacing = 12
            row.alignment = .fill
            stats.addArrangedSubview(row)
        }
    }

    private func showPull() {
        let letters = map.aims.filter { $0.key.label != " " && $0.taps > 0 }
        guard let middle = letters.map(\.frame.midX).max().map({ ($0 + (letters.map(\.frame.midX).min() ?? 0)) / 2 }) else { return }
        pull.show(map.aims, keys: map.keys, size: map.keyboardSize)
        let sides = [("left", letters.filter { $0.frame.midX < middle }), ("right", letters.filter { $0.frame.midX >= middle })].map { name, aims in
            let taps = Double(max(aims.reduce(0) { $0 + $1.taps }, 1))
            let x = aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.x } / taps
            let y = aims.reduce(0.0) { $0 + Double($1.taps) * $1.drift.y } / taps
            return "On the \(name) half you tap \(Self.describe((x, y)))."
        }
        let space = map.aims.first { $0.key.label == " " && $0.taps >= 10 }.map { " You hit the space bar \(Self.describe($0.drift)) of its center." } ?? ""
        pullCaption.text = "Each arrow points from a letter’s center to where you really tap it, drawn \(Int(TapPullView.magnification))× longer so you can see it. "
            + sides.joined(separator: " ") + space
    }

    static func describe(_ drift: (x: Double, y: Double)) -> String {
        let parts = [
            abs(drift.x) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.x), drift.x < 0 ? "left" : "right") : nil,
            abs(drift.y) >= 0.5 ? String(format: "%.1f pt %@", abs(drift.y), drift.y < 0 ? "high" : "low") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "right on center" : parts.joined(separator: " and ")
    }

    private func showMissed() {
        missed.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let worst = map.aims.filter { $0.taps >= 10 }.sorted { $0.onTarget < $1.onTarget }.prefix(5)
        missedCard.isHidden = worst.isEmpty
        for aim in worst {
            let row = MissRow(aim: aim, worst: 1 - (worst.first?.onTarget ?? 0))
            row.addAction(UIAction { [unowned self] _ in
                map.select(aim)
                scroll.scrollRectToVisible(map.convert(map.bounds, to: scroll).union(detail.convert(detail.bounds, to: scroll)), animated: true)
            }, for: .touchUpInside)
            missed.addArrangedSubview(row)
        }
    }

    private func showDetail(_ aim: Aim?) {
        detail.isHidden = aim == nil
        if let aim { detail.show(aim, keys: map.keys) }
        updateLegend()
    }

    private func updateLegend() {
        scale.isHidden = map.mode != .heat || signature == nil
        legend.text = switch (map.mode, map.selected) {
        case (.heat, nil):
            "Where your thumbs press: every key’s taps, spread the way they really land. Tap a key for a close-up."
        case (.heat, _?):
            "Where your thumbs press. Tap the outlined key again to go back."
        case (.aim, _):
            "Each dot is one of your recent taps. The ring holds half of all your taps for that key, and the line runs from the key’s center to where you really aim."
        case (.accuracy, nil):
            "How often a tap lands on the key you meant, judged by where it lands alone, before Hex looks at the word. Tap a key to see where its taps go."
        case (.accuracy, let aim?):
            "Where your taps for “\(TapMapPalette.name(of: aim.key))” land. Tap it again to go back."
        }
    }
}

/// The heat map's ramp, from the fewest taps to the most.
private final class HeatScale: UIView {
    private let ramp = HeatRamp()
    private let fewer = UILabel()
    private let more = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (label, text) in [(fewer, "fewer taps"), (more, "more")] {
            label.text = text
            label.font = .preferredFont(forTextStyle: .caption2)
            label.textColor = HexStyle.secondary
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        let row = UIStackView(arrangedSubviews: [fewer, ramp, more])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            ramp.heightAnchor.constraint(equalToConstant: 6),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Density from none to the most anywhere on the keyboard, colored as the heat map colors it.
private final class HeatRamp: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _) in self.setNeedsDisplay() }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let isDark = traitCollection.userInterfaceStyle == .dark
        UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).addClip()
        TapMapPalette.backdrop.setFill()
        UIRectFill(bounds)
        for x in stride(from: 0, to: bounds.width, by: 1) {
            TapHeat.color(at: (Double(x) / Double(bounds.width)).squareRoot(), isDark: isDark).setFill()
            UIRectFill(CGRect(x: x, y: 0, width: 1, height: bounds.height))
        }
    }
}

private final class StatView: UIView {
    init(value: String, caption: String) {
        super.init(frame: .zero)
        let number = UILabel()
        number.text = value
        number.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .monospacedDigitSystemFont(ofSize: 26, weight: .semibold))
        number.adjustsFontForContentSizeCategory = true
        number.adjustsFontSizeToFitWidth = true
        number.minimumScaleFactor = 0.6
        let label = UILabel()
        label.text = caption
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .caption1)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = HexStyle.secondary
        let stack = UIStackView(arrangedSubviews: [number, label])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        HexStyle.makeCard(self)
        isAccessibilityElement = true
        accessibilityLabel = "\(value) \(caption)"
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
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
        backgroundColor = HexStyle.pressed
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// One key up close: how many taps, where you aim, its last taps around it, how its aim follows you, and where its
/// taps land.
private final class KeyDetailView: UIView {
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        HexStyle.makeCard(self)
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

    func show(_ aim: Aim, keys: [(key: Key, frame: Rect)]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let name = TapMapPalette.name(of: aim.key)
        let cap = Keycap(aim.key, size: 24)
        let taps = UILabel()
        taps.text = aim.taps == 1 ? "1 tap" : "\(aim.taps.formatted()) taps"
        taps.font = .preferredFont(forTextStyle: .headline)
        let where_ = UILabel()
        let aimed = TapsViewController.describe(aim.drift)
        where_.text = aimed == "right on center" ? "You aim at its center." : "You aim \(aimed) of its center."
        where_.font = .preferredFont(forTextStyle: .subheadline)
        where_.textColor = HexStyle.secondary
        where_.numberOfLines = 0
        let text = UIStackView(arrangedSubviews: [taps, where_])
        text.axis = .vertical
        text.spacing = 2
        let header = UIStackView(arrangedSubviews: [cap, text])
        header.spacing = 12
        header.alignment = .center
        NSLayoutConstraint.activate([cap.widthAnchor.constraint(equalToConstant: 44), cap.heightAnchor.constraint(equalToConstant: 48)])
        stack.addArrangedSubview(header)

        let closeUp = TapCloseUpView()
        closeUp.show(aim, keys: keys)
        stack.addArrangedSubview(closeUp)
        if !aim.recent.isEmpty {
            let hits = aim.recent.count(where: { $0.landed == aim.key })
            let strays = Dictionary(grouping: aim.recent.compactMap { $0.landed == aim.key ? nil : $0.landed }, by: \.self)
                .sorted { $0.value.count > $1.value.count }
                .map { "\(TapMapPalette.name(of: $0.key)) \($0.value.count)" }
            stack.addArrangedSubview(Self.legend([
                (.hit, tintColor, "\(hits) of your last \(aim.recent.count) landed on \(name)"),
                (.miss, TapMapPalette.miss, strays.isEmpty ? "none landed elsewhere" : "elsewhere: " + strays.joined(separator: ", ")),
            ]))
        }
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(Self.title("How \(name) follows you"))
        let memories = [("all \(aim.taps.formatted()) taps", 0), ("about the last 30", 1), ("about the last 3", 2)]
        stack.addArrangedSubview(WeightBar(weights: aim.memories.map(\.weight)))
        stack.addArrangedSubview(Self.legend(memories.map { label, index in
            (.memory(index), .label, "\(label) \(TapMapPalette.percent(aim.memories[index].weight))")
        } + [(.aim, tintColor, "where \(name) aims: their blend")]))
        stack.setCustomSpacing(20, after: stack.arrangedSubviews.last!)

        stack.addArrangedSubview(Self.title("Where \(name)’s taps land"))
        let shares = Self.folded(aim)
        stack.addArrangedSubview(ShareBar(shares: shares))
        let lands = UILabel()
        lands.numberOfLines = 0
        lands.font = .preferredFont(forTextStyle: .footnote)
        lands.textColor = HexStyle.secondary
        lands.text = shares.map { "\($0.name) \(TapMapPalette.percent($0.share))" }.joined(separator: " · ")
        stack.addArrangedSubview(lands)
    }

    private static func title(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        return label
    }

    /// Glyphs drawn as the close-up draws them, each beside what it marks.
    private static func legend(_ items: [(glyph: TapGlyph, color: UIColor, text: String)]) -> UIStackView {
        let rows = items.map { item in
            let glyph = UIImageView(image: item.glyph.image(color: item.color, surface: HexStyle.card))
            glyph.setContentHuggingPriority(.required, for: .horizontal)
            let label = UILabel()
            label.text = item.text
            label.numberOfLines = 0
            label.font = .preferredFont(forTextStyle: .footnote)
            label.textColor = HexStyle.secondary
            let row = UIStackView(arrangedSubviews: [glyph, label])
            row.spacing = 8
            row.alignment = .center
            return row
        }
        let column = UIStackView(arrangedSubviews: rows)
        column.axis = .vertical
        column.spacing = 4
        return column
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

/// How much the key's aim leans on each memory, all taps first, in one bar.
private final class WeightBar: UIView {
    private let weights: [Double]

    init(weights: [Double]) {
        self.weights = weights
        super.init(frame: .zero)
        isOpaque = false
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let gap: CGFloat = 2
        let available = bounds.width - gap * CGFloat(weights.count - 1)
        var x: CGFloat = 0
        for (index, weight) in weights.enumerated() {
            let width = max(available * weight, 3)
            UIColor.label.withAlphaComponent([0.75, 0.45, 0.22][index]).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: 0, width: min(width, bounds.width - x), height: bounds.height), cornerRadius: 4).fill()
            x += width + gap
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont(descriptor: fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]]), size: 0)
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
        arrow.textColor = HexStyle.secondary
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
        HexStyle.pressed.setFill()
        UIBezierPath(roundedRect: bounds, cornerRadius: 3).fill()
        TapMapPalette.miss.setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: max(bounds.width * fraction, 6), height: bounds.height), cornerRadius: 3).fill()
    }
}

/// Raycast's pills in UIKit: a row of titles, the picked one on a filled capsule.
final class PillBar: UIView {
    var onChange: (Int) -> Void = { _ in }
    var selected = 0 { didSet { paint() } }
    private let buttons: [UIButton]

    init(titles: [String]) {
        buttons = titles.map { title in
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.cornerStyle = .capsule
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 15, bottom: 8, trailing: 15)
            configuration.titleLineBreakMode = .byClipping
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .medium))
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            return button
        }
        super.init(frame: .zero)
        let row = UIStackView(arrangedSubviews: buttons + [UIView()])
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        for (index, button) in buttons.enumerated() {
            button.addAction(UIAction { [unowned self] _ in
                UIView.animate(withDuration: 0.2) { self.selected = index }
                onChange(index)
            }, for: .touchUpInside)
        }
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func paint() {
        for (index, button) in buttons.enumerated() {
            let picked = index == selected
            button.configuration?.background.backgroundColor = picked ? HexStyle.pill : .clear
            button.configuration?.baseForegroundColor = picked ? HexStyle.pillLabel : HexStyle.secondary
            button.accessibilityTraits = picked ? [.button, .selected] : .button
        }
    }
}
