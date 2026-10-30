import UIKit
import KeyboardCore

/// The emoji panel's results: ten columns of emoji (more on a wide iPad) scrolling up and down, what you pick most first, then every emoji in
/// Apple's order, or what the search finds.
final class EmojiPanel: UIView, PanelContent, UICollectionViewDataSource, UICollectionViewDelegate {
    /// An emoji tapped, or picked among its skin tones with its untoned version.
    var onPick: (String, String?) -> Void = { _, _ in }
    /// What you've picked, read as the panel opens and as the search changes, so emoji never move under your finger.
    var history: () -> EmojiHistory = { EmojiHistory() }
    let placeholder = "Search emoji"

    private let layout = UICollectionViewFlowLayout()
    private lazy var grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let empty = UILabel()
    private var shown: [String] = []
    private var query: String?
    private var size: CGFloat = 30
    private var theme = KeyboardTheme.lightCurrent
    private var metrics = KeyboardMetrics.phone(width: 390)
    private let tones = AlternatesView()
    private var held: [String] = []
    /// How far the finger sat from the tone it started on, so letting go without sliding picks that tone.
    private var slide: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        grid.backgroundColor = .clear
        grid.showsVerticalScrollIndicator = false
        grid.dataSource = self
        grid.delegate = self
        grid.delaysContentTouches = false
        grid.accessibilityIdentifier = "hex.emoji"
        [grid.topEdgeEffect, grid.bottomEdgeEffect, grid.leftEdgeEffect, grid.rightEdgeEffect].forEach { $0.isHidden = true }
        grid.register(EmojiCell.self, forCellWithReuseIdentifier: "emoji")
        empty.font = .systemFont(ofSize: 15)
        empty.textAlignment = .center
        empty.isHidden = true
        grid.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(hold)))
        tones.isHidden = true
        clipsToBounds = false
        addSubview(grid)
        addSubview(empty)
        addSubview(tones)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        query = nil
    }

    func show(query: String, theme: KeyboardTheme, metrics: KeyboardMetrics) {
        self.metrics = metrics
        size = metrics.toolbar.pills == nil ? 26 : 30
        if theme != self.theme {
            self.theme = theme
            empty.textColor = theme.candidate.ui
            grid.reloadData()
        }
        guard query != self.query else { return }
        self.query = query
        shown = EmojiSearch.english.search(query, history: history())
        empty.text = "No emoji for “\(query.trimmingCharacters(in: .whitespaces))”"
        empty.isHidden = !shown.isEmpty
        grid.reloadData()
        grid.contentOffset = .zero
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.frame = bounds
        empty.frame = bounds
        let side = bounds.width / max(10, (bounds.width / 44).rounded(.down))
        let cell = CGSize(width: side, height: min(side, bounds.height))
        if layout.itemSize != cell {
            layout.itemSize = cell
            layout.invalidateLayout()
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { shown.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emoji", for: indexPath) as! EmojiCell
        cell.show(shown[indexPath.item], size: size, pressed: theme.label.ui.withAlphaComponent(0.12))
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        onPick(shown[indexPath.item], nil)
    }

    /// Holding an emoji that comes in skin tones offers them above it, picked by sliding, like a key's accents.
    @objc private func hold(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            guard let indexPath = grid.indexPathForItem(at: gesture.location(in: grid)), let cell = grid.cellForItem(at: indexPath),
                  let base = EmojiSearch.english.base(of: shown[indexPath.item]), let toned = EmojiSearch.english.tones[base]
            else { return gesture.state = .failed }
            held = [base] + toned
            let key = cell.convert(cell.bounds, to: self)
            tones.show(held, selected: held.firstIndex(of: shown[indexPath.item]) ?? 0, over: key, in: bounds.insetBy(dx: 0, dy: -8), metrics: metrics, theme: theme)
            slide = tones.selectedMidX - point.x
        case .changed:
            tones.track(CGPoint(x: point.x + slide, y: point.y))
        case .ended:
            if held.indices.contains(tones.selection) { onPick(held[tones.selection], held[0]) }
            fallthrough
        default:
            tones.hide()
            held = []
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
        accessibilityIdentifier = "hex.emoji.\(emoji)"
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
