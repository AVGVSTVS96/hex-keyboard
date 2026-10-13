import UIKit
import KeyboardCore

/// Apple's emoji keyboard: every emoji in one sideways-scrolling grid, Frequently Used first, a category bar to jump
/// through it, ABC to go back to the letters, and skin tones under a held emoji.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onEvent: (KeyboardEvent) -> Void = { _ in }

    private let catalog = EmojiCatalog.english
    private var history = EmojiHistory()
    private var sections: [EmojiCatalog.Category] = []
    private let layout = EmojiGridLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let title = UILabel()
    private let abc = UIButton(type: .custom)
    private let delete = UIButton(type: .custom)
    private var categories: [UIButton] = []
    private let selection = UIView()
    private let tones = AlternatesView()
    private var theme = KeyboardTheme.lightCurrent
    private var metrics = KeyboardMetrics.phone(width: 390)
    private var shown = -1

    private static let symbols = ["clock", "face.smiling", "teddybear", "takeoutbag.and.cup.and.straw", "soccerball", "car", "lightbulb", "music.note", "flag"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        grid.backgroundColor = .clear
        grid.showsHorizontalScrollIndicator = false
        grid.dataSource = self
        grid.delegate = self
        grid.delaysContentTouches = false
        [grid.topEdgeEffect, grid.bottomEdgeEffect, grid.leftEdgeEffect, grid.rightEdgeEffect].forEach { $0.isHidden = true }
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        grid.accessibilityIdentifier = "hex.emoji"
        grid.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        abc.accessibilityIdentifier = "hex.abc"
        abc.addAction(UIAction { [unowned self] _ in onEvent(.closeEmoji) }, for: .touchUpInside)
        delete.accessibilityIdentifier = "hex.emoji.delete"
        delete.accessibilityLabel = "Delete"
        delete.addAction(UIAction { [unowned self] _ in onEvent(.down(Key(.delete), tapCount: 1)) }, for: .touchDown)
        for ending in [UIControl.Event.touchUpInside, .touchUpOutside, .touchCancel] {
            delete.addAction(UIAction { [unowned self] _ in onEvent(.up(Key(.delete))) }, for: ending)
        }
        selection.isUserInteractionEnabled = false
        tones.isHidden = true
        [grid, title, selection, abc, delete].forEach(addSubview)
        addSubview(tones)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Frequently Used changes only as the keyboard opens, so emoji never move under your finger.
    func update(history: EmojiHistory, opening: Bool, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let changed = opening && (history != self.history || sections.isEmpty)
        self.history = history
        self.metrics = metrics
        if changed {
            sections = [EmojiCatalog.Category(name: "Frequently Used", emoji: history.frequent)] + catalog.categories
            if categories.isEmpty { makeCategoryButtons() }
            grid.reloadData()
        }
        guard theme != self.theme || changed else { return }
        self.theme = theme
        title.textColor = theme.label.ui.withAlphaComponent(0.4)
        abc.setTitleColor(theme.label.ui, for: .normal)
        delete.setImage(UIImage(systemName: "delete.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), for: .normal)
        delete.tintColor = theme.label.ui
        selection.backgroundColor = theme.label.ui.withAlphaComponent(0.12)
        shown = -1
        showSection()
    }

    private func makeCategoryButtons() {
        categories = zip(sections.indices, Self.symbols).map { index, symbol in
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)), for: .normal)
            button.accessibilityLabel = sections[index].name
            button.addAction(UIAction { [unowned self] _ in
                grid.setContentOffset(CGPoint(x: min(layout.start(of: index) - layout.inset, grid.contentSize.width - grid.bounds.width), y: 0), animated: false)
                showSection()
            }, for: .touchUpInside)
            addSubview(button)
            return button
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bar: CGFloat = 38
        let top: CGFloat = 22
        title.frame = CGRect(x: 12, y: 2, width: bounds.width - 24, height: top - 4)
        grid.frame = CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top - bar)
        layout.rows = max(3, Int(grid.bounds.height / 36))
        layout.cell = CGSize(width: min(46, bounds.width / 8.7), height: grid.bounds.height / CGFloat(layout.rows))
        layout.invalidateLayout()
        abc.frame = CGRect(x: 4, y: bounds.height - bar, width: 52, height: bar)
        delete.frame = CGRect(x: bounds.width - 56, y: bounds.height - bar, width: 52, height: bar)
        let span = bounds.width - 120
        let step = span / CGFloat(max(categories.count, 1))
        for (index, button) in categories.enumerated() {
            button.frame = CGRect(x: 60 + CGFloat(index) * step, y: bounds.height - bar, width: step, height: bar)
        }
        shown = -1
        showSection()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        showSection()
    }

    /// Names and marks the category under the grid's left edge.
    private func showSection() {
        guard !sections.isEmpty else { return }
        let section = layout.section(at: grid.contentOffset.x + layout.inset + 1)
        guard section != shown else { return }
        shown = section
        title.text = sections[section].name.uppercased()
        guard categories.indices.contains(section) else { return }
        let button = categories[section]
        let side = min(button.bounds.height - 10, 28)
        selection.frame = CGRect(x: button.frame.midX - side / 2, y: button.frame.midY - side / 2, width: side, height: side)
        selection.layer.cornerRadius = side / 2
        for (index, other) in categories.enumerated() {
            other.tintColor = theme.label.ui.withAlphaComponent(index == section ? 0.85 : 0.4)
        }
    }

    private func emoji(at indexPath: IndexPath) -> String {
        let emoji = sections[indexPath.section].emoji[indexPath.item]
        return indexPath.section == 0 ? emoji : history.tones[emoji] ?? emoji
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].emoji.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        cell.show(emoji(at: indexPath), size: min(32, layout.cell.height * 0.88), pressed: theme.label.ui.withAlphaComponent(0.12))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onEvent(.emoji(emoji(at: indexPath), base: nil))
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let indexPath = grid.indexPathForItem(at: gesture.location(in: grid)),
                  let base = catalog.base(of: emoji(at: indexPath)), let toned = catalog.tones[base],
                  let cell = grid.cellForItem(at: indexPath) else { return gesture.state = .failed }
            let key = cell.convert(cell.bounds, to: self)
            tones.show([base] + toned, base: emoji(at: indexPath), over: key, in: bounds, metrics: metrics, theme: theme, font: .systemFont(ofSize: layout.cell.height * 0.7))
            tones.track(point)
        case .changed:
            tones.track(point)
        case .ended:
            if let picked = tones.selected, let base = catalog.base(of: picked) { onEvent(.emoji(picked, base: base)) }
            tones.hide()
        default:
            tones.hide()
        }
    }
}

private final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()
    private let backdrop = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backdrop.layer.cornerRadius = 8
        backdrop.layer.cornerCurve = .continuous
        backdrop.isHidden = true
        label.textAlignment = .center
        contentView.addSubview(backdrop)
        contentView.addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ emoji: String, size: CGFloat, pressed: UIColor) {
        label.text = emoji
        label.font = .systemFont(ofSize: size)
        backdrop.backgroundColor = pressed
        accessibilityLabel = emoji
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
        backdrop.frame = contentView.bounds.insetBy(dx: 1, dy: 1)
    }

    override var isHighlighted: Bool {
        didSet { backdrop.isHidden = !isHighlighted }
    }
}

/// Columns of `rows` emoji, each category starting a new column after a gap.
private final class EmojiGridLayout: UICollectionViewLayout {
    var rows = 5
    var cell = CGSize(width: 46, height: 40)
    let inset: CGFloat = 3
    private let gap: CGFloat = 14
    private var frames: [[CGRect]] = []
    private var starts: [CGFloat] = []
    private var width: CGFloat = 0

    override func prepare() {
        guard let collectionView else { return }
        var x = inset
        starts = []
        frames = (0 ..< collectionView.numberOfSections).map { section in
            starts.append(x)
            let count = collectionView.numberOfItems(inSection: section)
            let frames = (0 ..< count).map { item in
                CGRect(x: x + CGFloat(item / rows) * cell.width, y: CGFloat(item % rows) * cell.height, width: cell.width, height: cell.height)
            }
            x += CGFloat((count + rows - 1) / rows) * cell.width + gap
            return frames
        }
        width = x - gap + inset
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: width, height: collectionView?.bounds.height ?? 0)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        frames.enumerated().flatMap { section, frames in
            frames.indices.filter { frames[$0].intersects(rect) }.map { attributes(at: IndexPath(item: $0, section: section)) }
        }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes(at: indexPath)
    }

    private func attributes(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = frames[indexPath.section][indexPath.item]
        return attributes
    }

    func start(of section: Int) -> CGFloat {
        starts.indices.contains(section) ? starts[section] : 0
    }

    func section(at x: CGFloat) -> Int {
        starts.lastIndex { $0 <= x } ?? 0
    }
}
