import UIKit
import KeyboardCore

/// Apple's emoji keyboard: a search field, every emoji in one sideways-scrolling grid, Frequently Used first, a category
/// bar to jump through it, ABC to go back to the letters, and skin tones under a held emoji. While searching, the field
/// and a row of what it finds sit above the letter keys, which type into it.
final class EmojiKeyboardView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    /// Measured on iOS 27: the field is 40pt tall, and in search its top sits 95pt above the keys, its results between.
    static let fieldTop: CGFloat = 6
    static let fieldHeight: CGFloat = 40
    static let keysBelowField: CGFloat = 95
    /// How much taller than the letters the emoji keyboard is, for the field above the grid.
    static let fieldSpan: CGFloat = 52

    /// The height above the keys' view while searching.
    static func searchHeight(_ metrics: KeyboardMetrics) -> CGFloat {
        fieldTop + keysBelowField - metrics.topInset
    }

    var onEvent: (KeyboardEvent) -> Void = { _ in }

    private var catalog: EmojiCatalog { .english }
    private var history = EmojiHistory()
    private var sections: [EmojiCatalog.Category] = []
    private var query: String?
    private var results: [String] = []
    private let layout = EmojiGridLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let resultsLayout = UICollectionViewFlowLayout()
    private lazy var resultsRow = UICollectionView(frame: .zero, collectionViewLayout: resultsLayout)
    private let field = EmojiSearchField()
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
        resultsLayout.scrollDirection = .horizontal
        resultsLayout.minimumLineSpacing = 0
        resultsLayout.sectionInset = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        for view in [grid, resultsRow] {
            view.backgroundColor = .clear
            view.showsHorizontalScrollIndicator = false
            view.dataSource = self
            view.delegate = self
            view.delaysContentTouches = false
            [view.topEdgeEffect, view.bottomEdgeEffect, view.leftEdgeEffect, view.rightEdgeEffect].forEach { $0.isHidden = true }
            view.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
            view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        }
        grid.accessibilityIdentifier = "hex.emoji"
        resultsRow.accessibilityIdentifier = "hex.emoji.results"
        resultsRow.isHidden = true
        field.onTap = { [unowned self] in if query == nil { onEvent(.emojiSearch("")) } }
        field.onClear = { [unowned self] in onEvent(.emojiSearch("")) }
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
        [field, grid, resultsRow, title, selection, abc, delete].forEach(addSubview)
        addSubview(tones)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Frequently Used, and what a search finds, change only as the keyboard opens and as you type the search, so
    /// emoji never move under your finger.
    func update(history: EmojiHistory, opening: Bool, query: String?, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        let changed = opening && (history != self.history || sections.isEmpty)
        let searchChanged = query != self.query
        self.history = history
        self.metrics = metrics
        if changed {
            sections = [EmojiCatalog.Category(name: "Frequently Used", emoji: history.frequent)] + catalog.categories
            if categories.isEmpty { makeCategoryButtons() }
            grid.reloadData()
        }
        if searchChanged {
            if (query == nil) != (self.query == nil) { setNeedsLayout() }
            self.query = query
            results = query.map { $0.allSatisfy(\.isWhitespace) ? history.frequent : catalog.search($0, history: history) } ?? []
            resultsRow.reloadData()
            resultsRow.contentOffset = .zero
            field.show(query)
            [grid, title, selection, abc, delete].forEach { $0.isHidden = query != nil }
            categories.forEach { $0.isHidden = query != nil }
            resultsRow.isHidden = query == nil
        }
        guard theme != self.theme || changed else { return }
        self.theme = theme
        field.theme = theme
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
            button.isHidden = query != nil
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
        field.frame = CGRect(x: 28 / 3, y: Self.fieldTop, width: bounds.width - 56 / 3, height: Self.fieldHeight)
        resultsRow.frame = CGRect(x: 0, y: field.frame.maxY, width: bounds.width, height: Self.fieldTop + Self.keysBelowField - field.frame.maxY)
        resultsLayout.itemSize = CGSize(width: 160 / 3, height: resultsRow.bounds.height)
        let bar: CGFloat = 38
        let top = Self.fieldSpan + 22
        title.frame = CGRect(x: 12, y: Self.fieldSpan + 2, width: bounds.width - 24, height: 18)
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

    /// While searching, the keys below the results take their own touches.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        query == nil ? super.point(inside: point, with: event) : point.y < resultsRow.frame.maxY
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView === grid { showSection() }
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

    private func emoji(at indexPath: IndexPath, in view: UICollectionView) -> String {
        guard view === grid else { return results[indexPath.item] }
        let emoji = sections[indexPath.section].emoji[indexPath.item]
        return indexPath.section == 0 ? emoji : history.tones[emoji] ?? emoji
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { collectionView === grid ? sections.count : 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        collectionView === grid ? sections[section].emoji.count : results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        let size = collectionView === grid ? min(32, layout.cell.height * 0.88) : 37
        cell.show(emoji(at: indexPath, in: collectionView), size: size, pressed: theme.label.ui.withAlphaComponent(0.12))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onEvent(.emoji(emoji(at: indexPath, in: collectionView), base: nil))
    }

    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let view = gesture.view as? UICollectionView, let indexPath = view.indexPathForItem(at: gesture.location(in: view)),
                  case let emoji = emoji(at: indexPath, in: view), let base = catalog.base(of: emoji), let toned = catalog.tones[base],
                  let cell = view.cellForItem(at: indexPath) else { return gesture.state = .failed }
            let key = cell.convert(cell.bounds, to: self)
            tones.show([base] + toned, base: emoji, over: key, in: bounds, metrics: metrics, theme: theme, font: .systemFont(ofSize: layout.cell.height * 0.7))
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

/// Apple's Search Emoji field: a magnifier, what you've typed and a caret, and a clear button once there's text.
private final class EmojiSearchField: UIControl {
    var onTap: () -> Void = {}
    var onClear: () -> Void = {}
    var theme = KeyboardTheme.lightCurrent { didSet { refresh() } }
    private let magnifier = UIImageView(image: UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)))
    private let label = UILabel()
    private let caret = UIView()
    private let clear = UIButton(type: .custom)
    private var query: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "hex.emoji.search"
        isAccessibilityElement = true
        accessibilityTraits = .searchField
        accessibilityLabel = "Search Emoji"
        layer.cornerRadius = 13
        layer.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 17)
        caret.layer.cornerRadius = 1
        clear.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
        clear.accessibilityIdentifier = "hex.emoji.search.clear"
        clear.accessibilityLabel = "Clear"
        clear.addAction(UIAction { [unowned self] _ in onClear() }, for: .touchUpInside)
        addAction(UIAction { [unowned self] _ in onTap() }, for: .touchUpInside)
        [magnifier, label, caret].forEach {
            $0.isUserInteractionEnabled = false
            addSubview($0)
        }
        addSubview(clear)
        show(nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ query: String?) {
        let opened = query != nil && self.query == nil
        self.query = query
        label.text = query.flatMap { $0.isEmpty ? nil : $0 } ?? "Search Emoji"
        accessibilityValue = query
        clear.isHidden = query?.isEmpty ?? true
        caret.isHidden = query == nil
        if opened || query == nil { blink() }
        refresh()
        setNeedsLayout()
    }

    /// The caret blinks the way UIKit's does, on Core Animation's clock rather than a timer.
    private func blink() {
        caret.layer.removeAllAnimations()
        guard query != nil else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = 0.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        caret.layer.add(animation, forKey: "blink")
    }

    private func refresh() {
        backgroundColor = theme.searchField.ui
        magnifier.tintColor = theme.searchPlaceholder.ui
        clear.tintColor = theme.searchPlaceholder.ui
        label.textColor = query?.isEmpty == false ? theme.label.ui : theme.searchPlaceholder.ui
        caret.backgroundColor = theme.prominent.ui
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        magnifier.frame = CGRect(x: 19, y: 0, width: magnifier.intrinsicContentSize.width, height: bounds.height)
        magnifier.contentMode = .center
        clear.frame = CGRect(x: bounds.width - 30.67, y: 0, width: 30.67, height: bounds.height)
        let text: CGFloat = 130 / 3
        let width = min(label.intrinsicContentSize.width, bounds.width - text - 32)
        label.frame = CGRect(x: text, y: 0, width: width, height: bounds.height)
        let typed = query?.isEmpty == false ? width : 0
        caret.frame = CGRect(x: (text + typed + 1).rounded(scale: scale), y: ((bounds.height - 22) / 2).rounded(scale: scale), width: 2, height: 22)
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
